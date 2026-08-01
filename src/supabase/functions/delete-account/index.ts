// =====================================================================
// delete-account — 회원 탈퇴(익명화) 처리 (운톡 불만 #1 해결 + Phase 3.5)
//
// 왜 Edge Function 인가:
//   클라 anon 키로는 (1) auth.users 삭제 불가, (2) user_id=NULL 분리 등
//   RLS 밖 작업이 막힌다. 둘 다 service_role 이 필요해 서버에서만 수행한다.
//
// 처리 순서(중요 — 데이터 보존을 위한 순서 강제):
//   1) 호출자 JWT 로 본인(uid) 확인.
//   2) **회원이 올린 콘텐츠 삭제** (2026-08-01 추가 — 상세는 아래 "삭제 범위").
//   3) service_role 로 member_profiles 익명화:
//        PII(name/phone/birth_date/goal/...) 제거 + user_id=NULL + deleted_at=now().
//        ※ user_id=NULL 로 먼저 끊어야 5)의 auth 삭제가 프로필을 cascade 로
//          지우지 않는다(member_profiles.user_id 는 auth.users ON DELETE CASCADE).
//        ※ 수업기록/계약/매출 통계는 그대로 보존(트레이너 자산).
//   4) 탈퇴 로그 적재(account_deletion_logs) — 사유 통계.
//   5) auth.users 계정 삭제 → 동일 이메일 재가입 가능(계정 함정 방지, 불만 #2/U5).
//
//   ⚠ 2)가 3)보다 **앞**인 이유: 2)가 실패하면 아무것도 안 건드린 상태로 끝나
//     사용자가 그대로 재시도할 수 있다. 익명화를 먼저 하면 재시도 시 uid 로
//     프로필을 못 찾아 콘텐츠가 영영 고아가 된다.
//
// ── 삭제 범위 — "회원이 올린 것"만 지운다 (사용자 결정, 2026-08-01) ──────
//   기준: 업로드·작성 주체가 회원인가, 트레이너인가.
//   트레이너가 만든 것은 회원이 나가도 트레이너의 자산으로 남는다.
//
//   지운다:
//     - self_workout_logs        회원이 직접 쓴 운동 일지 (0028, member 가 INSERT)
//     - chat-images 의 "{uid}/"  회원이 채팅에 올린 사진 (0026, key 첫 세그먼트=업로더)
//     - messages (양방향)        아래 ⚠ 참조
//
//   남긴다 (전부 트레이너가 만든 것):
//     - class_videos / class-videos      트레이너가 촬영·업로드 (0027)
//     - body_assessments / body-photos   recorded_by = 트레이너 (0039)
//     - body_measurements                recorded_by = 트레이너 (0023)
//     - member_notes / member_conditions 트레이너 작성 (0004 / 0036)
//     - sessions·contracts               수업·계약 기록
//
//   ⚠ 채팅만 이 기준으로 쪼갤 수 없다. messages.sender_id/receiver_id 는
//     auth.users 를 참조하면서 **ON DELETE 절이 없는 유일한 FK**(NO ACTION)다.
//     회원 계정을 지우려면 그를 참조하는 행이 0이어야 하므로, 트레이너가 보낸
//     메시지도 함께 지울 수밖에 없다. 대화는 원래 양쪽이 같이 만든 것이고,
//     상대가 사라진 반쪽 대화는 스키마상 저장이 불가능하다.
//
//     ※ 이 FK 때문에 **채팅을 한 번이라도 한 회원은 지금까지 탈퇴가 실패했다**
//       (5)에서 FK 위반 → auth_delete_failed). 2)가 그 원인을 같이 제거한다.
//
//     ※ 알려진 한계: 대화가 지워지면 트레이너가 그 대화에 올렸던 사진은
//       chat-images 에 참조 없는 객체로 남는다. 트레이너 자산이라 규칙상
//       지우지 않는다 — 스토리지 정리 잡의 대상.
//
// verify_jwt: 기본값(true) 유지 — 인증된 사용자만 본인 계정을 지운다.
// 참고: docs/legal_docs_gap_check.md A-1, docs/untok_improvement_plan.md §5 A,
//       migrations 0006(messages FK)·0026·0028·0034.
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

/// Storage 한 폴더 아래의 객체를 전부 지운다.
///
/// list() 는 한 번에 다 주지 않으므로(기본 100건) 빈 페이지가 나올 때까지 돈다.
/// 페이지를 지우면 뒤가 앞으로 당겨지므로 offset 을 올리지 않고 **항상 첫 페이지**를
/// 다시 읽는다 — offset 을 올리면 삭제로 당겨진 만큼을 건너뛰어 남는 게 생긴다.
///
/// 반환: 지운 객체 수. 실패하면 throw (호출부가 탈퇴를 중단시킨다).
async function removeFolder(
  // deno-lint-ignore no-explicit-any
  admin: any,
  bucket: string,
  folder: string,
): Promise<number> {
  const PAGE = 100;
  // 무한 루프 방지 — 삭제가 조용히 실패하면 같은 페이지가 계속 나온다.
  const MAX_PAGES = 200;
  let removed = 0;

  for (let page = 0; page < MAX_PAGES; page++) {
    const { data: files, error: listErr } = await admin
      .storage.from(bucket).list(folder, { limit: PAGE });
    if (listErr) throw listErr;
    if (!files || files.length === 0) return removed;

    // list() 는 하위 "폴더"도 같이 준다(그 경우 id 가 null) — 파일만 고른다.
    // 이 버킷들의 key 는 한 단계라(0026 "{uid}/{uuid}.jpg") 실제로는 전부 파일.
    // deno-lint-ignore no-explicit-any
    const paths = files
      .filter((f: any) => f?.name && f.id !== null)
      .map((f: any) => `${folder}/${f.name}`);
    if (paths.length === 0) return removed;

    const { error: rmErr } = await admin.storage.from(bucket).remove(paths);
    if (rmErr) throw rmErr;
    removed += paths.length;
  }

  // 여기 도달 = 200페이지를 지웠는데도 계속 남음. 조용히 넘기면 안 된다.
  throw new Error(`removeFolder: ${bucket}/${folder} 정리가 끝나지 않음`);
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
    //   트레이너/관리자가 본인 JWT 로 이 엔드포인트를 직접 호출하면 5) 의 auth 삭제로
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

    // 2) 회원이 올린 콘텐츠 삭제 — 익명화보다 **먼저**.
    //    여기서 실패하면 아직 아무것도 안 건드린 상태라 그대로 재시도하면 된다.
    //    반대로 익명화를 먼저 하면 uid↔프로필 연결이 끊겨 재시도가 불가능해진다.
    const memberProfileId = m.data.id as string;
    try {
      // 2-a) 회원이 채팅에 올린 사진. key 규칙 "{업로더 user_id}/{uuid}.jpg"(0026)
      //      라서 uid 폴더 = 회원이 올린 것 전부. 트레이너 폴더는 건드리지 않는다.
      await removeFolder(admin, "chat-images", uid);

      // 2-b) 채팅 메시지 — 양방향. 위 주석의 FK 제약 때문에 트레이너가 보낸 것도
      //      같이 지워야 5)의 auth 삭제가 통과한다.
      const { error: msgErr } = await admin
        .from("messages")
        .delete()
        .or(`sender_id.eq.${uid},receiver_id.eq.${uid}`);
      if (msgErr) throw msgErr;

      // 2-c) 회원이 직접 쓴 운동 일지(0028).
      //      member_profiles 는 soft delete 라 FK CASCADE 가 안 걸린다 → 명시 삭제.
      const { error: logErr } = await admin
        .from("self_workout_logs")
        .delete()
        .eq("member_id", memberProfileId);
      if (logErr) throw logErr;
    } catch (_) {
      return json(
        {
          ok: false,
          code: "content_delete_failed",
          message: "회원 데이터 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.",
        },
        500,
      );
    }

    // 3) 회원 프로필 익명화 — PII 제거 + user_id 분리 + 소프트삭제.
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

  // 4) 탈퇴 로그 — 실패해도 탈퇴 자체는 진행(로그는 보조).
  try {
    await admin.from("account_deletion_logs").insert({
      deleted_user_id: uid,
      role,
      reason,
      detail,
    });
  } catch (_) { /* 로그 실패는 무시 */ }

  // 5) auth 계정 삭제 — 이 시점엔 회원 프로필 user_id 가 NULL 이라 cascade 없음.
  //    2-b)에서 messages 를 지웠으므로 auth.users 를 참조하는 NO ACTION FK 도 없다.
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
