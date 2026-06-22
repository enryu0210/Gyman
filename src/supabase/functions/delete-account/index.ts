// =====================================================================
// delete-account — 회원 탈퇴(익명화) 처리 (운톡 불만 #1 해결 + Phase 3.5)
//
// 왜 Edge Function 인가:
//   클라 anon 키로는 (1) auth.users 삭제 불가, (2) user_id=NULL 분리 등
//   RLS 밖 작업이 막힌다. 둘 다 service_role 이 필요해 서버에서만 수행한다.
//
// 처리 순서(중요 — 데이터 보존을 위한 순서 강제):
//   1) 호출자 JWT 로 본인(uid) 확인.
//   2) service_role 로 member_profiles 익명화:
//        PII(name/phone/birth_date/goal/...) 제거 + user_id=NULL + deleted_at=now().
//        ※ user_id=NULL 로 먼저 끊어야 3)의 auth 삭제가 프로필을 cascade 로
//          지우지 않는다(member_profiles.user_id 는 auth.users ON DELETE CASCADE).
//        ※ 수업기록/계약/매출 통계는 그대로 보존(트레이너 자산).
//   3) 탈퇴 로그 적재(account_deletion_logs) — 사유 통계.
//   4) auth.users 계정 삭제 → 동일 이메일 재가입 가능(계정 함정 방지, 불만 #2/U5).
//
// verify_jwt: 기본값(true) 유지 — 인증된 사용자만 본인 계정을 지운다.
// 참고: docs/untok_improvement_plan.md §5 A, migrations 0034.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, code: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, code: "unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // 1) 호출자 식별 — 본인 JWT 컨텍스트로 uid 확인(여기서 service_role 안 씀).
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await caller.auth.getUser();
  const user = userData.user;
  if (!user) return json({ ok: false, code: "unauthorized" }, 401);
  const uid = user.id;

  // service_role 미주입(설정 누락) 방어 — 잘못 삭제하느니 막는다.
  if (!serviceKey) {
    return json(
      { ok: false, code: "server_misconfigured", message: "서버 설정 오류로 탈퇴를 처리할 수 없습니다. 운영자에게 문의해 주세요." },
      500,
    );
  }

  // 사유(선택) 파싱 — 없어도 탈퇴는 진행.
  let reason: string | null = null;
  let detail: string | null = null;
  try {
    const body = await req.json();
    if (typeof body?.reason === "string") reason = body.reason.slice(0, 100);
    if (typeof body?.detail === "string") detail = body.detail.slice(0, 1000);
  } catch (_) { /* 본문 없거나 형식 어긋나도 진행 */ }

  // service_role 클라이언트 — RLS 우회. 이 아래 작업은 서버 신뢰 영역.
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 탈퇴 시점 역할(로그용). 우선순위 trainer > admin > member.
  let role = "unknown";
  try {
    const [t, a, m] = await Promise.all([
      admin.from("trainer_profiles").select("user_id").eq("user_id", uid).maybeSingle(),
      admin.from("admin_profiles").select("user_id").eq("user_id", uid).maybeSingle(),
      admin.from("member_profiles").select("id").eq("user_id", uid).maybeSingle(),
    ]);
    role = t.data ? "trainer" : a.data ? "admin" : m.data ? "member" : "unknown";

    // 이 함수는 '회원 셀프 탈퇴' 전용 — 서버에서 역할을 강제한다.
    //   트레이너/관리자가 본인 JWT 로 이 엔드포인트를 직접 호출하면 4) 의 auth 삭제로
    //   trainer_profiles/admin_profiles 가 cascade 되어 담당 회원·계약까지 끊긴다.
    //   되돌릴 수 없는 작업을 UI 노출 여부에만 맡기지 않고 여기서 막는다(defense in depth).
    if (!m.data) {
      return json(
        {
          ok: false,
          code: "not_supported",
          message: "회원 계정만 앱에서 탈퇴할 수 있습니다. 트레이너/관리자 계정은 운영자에게 문의해 주세요.",
        },
        403,
      );
    }

    // 2) 회원 프로필 익명화 — PII 제거 + user_id 분리 + 소프트삭제.
    if (m.data) {
      const { error: anonErr } = await admin
        .from("member_profiles")
        .update({
          name: "(탈퇴한 회원)",
          phone: null,
          birth_date: null,
          goal: null,
          experience: null,
          injury_history: null,
          body_features: null,
          lifestyle: null,
          available_times: null,
          ai_consent: false,
          user_id: null,        // ← auth 삭제 전 반드시 분리(cascade 방지)
          deleted_at: new Date().toISOString(),
        })
        .eq("user_id", uid);
      if (anonErr) {
        return json(
          { ok: false, code: "anonymize_failed", message: "회원 정보 처리에 실패했습니다. 잠시 후 다시 시도해 주세요." },
          500,
        );
      }
    }
  } catch (_) {
    return json(
      { ok: false, code: "anonymize_failed", message: "회원 정보 처리에 실패했습니다. 잠시 후 다시 시도해 주세요." },
      500,
    );
  }

  // 3) 탈퇴 로그 — 실패해도 탈퇴 자체는 진행(로그는 보조).
  try {
    await admin.from("account_deletion_logs").insert({
      deleted_user_id: uid,
      role,
      reason,
      detail,
    });
  } catch (_) { /* 로그 실패는 무시 */ }

  // 4) auth 계정 삭제 — 이 시점엔 회원 프로필 user_id 가 NULL 이라 cascade 없음.
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    // 익명화는 됐는데 계정 삭제만 실패 — 사용자에겐 재시도 안내.
    return json(
      { ok: false, code: "auth_delete_failed", message: "계정 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요." },
      500,
    );
  }

  return json({ ok: true });
});
