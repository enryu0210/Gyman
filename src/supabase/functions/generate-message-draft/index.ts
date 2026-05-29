// =====================================================================
// generate-message-draft — AI-B 회원 안내 메시지 초안 생성 (Phase 1.9 + 1.11)
//
// 흐름 (모두 트레이너 JWT 컨텍스트 = RLS 적용):
//   1) 인증 확인 (verify_jwt=true 기본)
//   2) 입력 검증 (memberId, triggerType)
//   3) 회원 조회 + AI 사용 동의(ai_consent) 확인 — 거부 시 차단
//   4) 일일 호출 한도(비용 가드) 확인 — 초과 시 차단
//   5) 컨텍스트 수집(목적/잔여 횟수/수업 시각) + PII 마스킹(실명 → {{NAME}})
//   6) Gemini 호출 — 실패 시 앱이 수동 입력으로 폴백하도록 구조화된 에러 반환
//   7) 응답에서 실명 복원 → outgoing_notifications 에 status='draft', ai_generated=true 적재
//   8) ai_call_logs 에 결과 기록(success/failed/blocked)
//
// 보안 핵심:
//   - LLM API 키는 서버 시크릿(LLM_API_KEY)에만. 클라이언트 노출 0.
//   - 회원 실명은 LLM 으로 전송하지 않음 — {{NAME}} 토큰으로 보내고 응답에서 복원.
//   - 미검수 발송 차단: 여기서는 draft 까지만. 승인/발송은 트레이너 검수(1.9 게이트).
//
// 환경변수(supabase secrets):
//   LLM_API_KEY   : Gemini API 키 (필수)
//   LLM_MODEL     : 모델명 (기본 gemini-3.5-flash)
//   AI_DAILY_LIMIT: 트레이너 1인 일일 성공 호출 한도 (기본 50)
//
// 참고: docs/develop_plan.md §4 1.9/1.11, §6, 와이어 06_ai_review.md.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL = Deno.env.get("LLM_MODEL") ?? "gemini-3.5-flash";
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");

// 트리거 → 프롬프트용 한국어 의도 설명.
function triggerIntent(triggerType: string): string {
  switch (triggerType) {
    case "pre_session":
      return "내일 예정된 수업을 부드럽게 리마인드하고 컨디션을 묻는 안내";
    case "renewal_five_left":
      return "잔여 횟수가 얼마 남지 않았음을 알리고 다음 일정/재등록을 자연스럽게 제안";
    case "renewal_half":
      return "PT 횟수를 절반 사용했음을 격려와 함께 알리는 안내";
    case "renewal_expiring":
      return "PT 가 곧 만료됨을 알리고 재등록을 부담스럽지 않게 제안";
    case "late_cancel_notice":
      return "당일 취소로 1회 차감되었음을 정중하게 안내";
    default:
      return "회원에게 보내는 일반적인 안내";
  }
}

// JSON 응답 헬퍼.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, code: "method_not_allowed" }, 405);
  }

  // 트레이너 JWT 컨텍스트 클라이언트 — 모든 DB 접근에 RLS 적용.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ ok: false, code: "unauthorized" }, 401);
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData } = await supabase.auth.getUser();
  const trainer = userData.user;
  if (!trainer) {
    return json({ ok: false, code: "unauthorized" }, 401);
  }

  // ----- 입력 -----
  let payload: {
    memberId?: string;
    triggerType?: string;
    tone?: string;
    sessionId?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, code: "bad_request", message: "JSON 본문 필요" }, 400);
  }
  const memberId = payload.memberId;
  const triggerType = payload.triggerType ?? "manual";
  const tone = payload.tone ?? "친근하게";
  if (!memberId) {
    return json({ ok: false, code: "bad_request", message: "memberId 필요" }, 400);
  }

  // ai_call_logs 기록 헬퍼 (실패해도 본 흐름을 막지 않음).
  const log = async (status: string, error?: string) => {
    try {
      await supabase.from("ai_call_logs").insert({
        trainer_id: trainer.id,
        member_id: memberId,
        function_name: "generate-message-draft",
        trigger_type: triggerType,
        status,
        model: MODEL,
        error: error?.slice(0, 500),
      });
    } catch (_) {
      // 로깅 실패는 무시 — 핵심 동작 우선.
    }
  };

  // ----- 3) 회원 + 동의 확인 (RLS 가 본인 담당 회원만 노출) -----
  const { data: member, error: memberErr } = await supabase
    .from("member_profiles")
    .select("id, name, goal, ai_consent")
    .eq("id", memberId)
    .maybeSingle();

  if (memberErr || !member) {
    await log("blocked", "member_not_found_or_forbidden");
    return json(
      { ok: false, code: "not_found", message: "회원을 찾을 수 없습니다." },
      404,
    );
  }
  if (member.ai_consent !== true) {
    await log("blocked", "consent_required");
    return json(
      {
        ok: false,
        code: "consent_required",
        message: "회원이 AI 사용에 동의하지 않았습니다. 수동으로 작성해 주세요.",
      },
      403,
    );
  }

  // ----- 4) 일일 호출 한도(비용 가드) -----
  // KST 기준 오늘 시작 이후의 성공 호출 수.
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const todayKst = kstNow.toISOString().slice(0, 10); // YYYY-MM-DD (KST)
  const todayStartIso = new Date(`${todayKst}T00:00:00+09:00`).toISOString();
  const { count } = await supabase
    .from("ai_call_logs")
    .select("*", { count: "exact", head: true })
    .eq("status", "success")
    .gte("created_at", todayStartIso);
  if ((count ?? 0) >= DAILY_LIMIT) {
    await log("blocked", "rate_limited");
    return json(
      {
        ok: false,
        code: "rate_limited",
        message: "오늘 AI 생성 한도를 초과했습니다. 내일 다시 시도하거나 수동 작성해 주세요.",
      },
      429,
    );
  }

  // ----- 5) 컨텍스트 수집 + PII 마스킹 -----
  // 잔여/총 횟수 (활성 계약 중 하나). 없으면 생략.
  const { data: statusRows } = await supabase
    .from("v_contract_status")
    .select("total_sessions, used_sessions, remaining_sessions, end_date")
    .eq("member_id", memberId)
    .order("remaining_sessions", { ascending: true })
    .limit(1);
  const status = statusRows?.[0];

  const realName: string = member.name;
  const NAME_TOKEN = "{{NAME}}";
  // 실명을 토큰으로 치환(목적 텍스트 등에 이름이 들어가도 마스킹).
  const mask = (t: string | null | undefined): string =>
    (t ?? "").split(realName).join(NAME_TOKEN);

  const ctxLines: string[] = [
    `- 안내 목적: ${triggerIntent(triggerType)}`,
    `- 톤: ${tone}`,
  ];
  if (member.goal) ctxLines.push(`- 회원 운동 목적: ${mask(member.goal)}`);
  if (status) {
    ctxLines.push(
      `- PT 진행: 총 ${status.total_sessions}회 중 ${status.used_sessions}회 사용, 잔여 ${status.remaining_sessions}회`,
    );
    if (status.end_date) ctxLines.push(`- 계약 만료 예정일: ${status.end_date}`);
  }

  const systemInstruction =
    "너는 한국의 PT 트레이너다. 담당 회원에게 보낼 짧고 따뜻한 한국어 안내 메시지를 쓴다. " +
    `회원을 지칭할 때는 반드시 정확히 "${NAME_TOKEN}" 라는 토큰을 그대로 사용한다(실명 추측 금지). ` +
    "2~4문장으로 간결하게. 의학적 단정(진단)·과장 표현은 피한다. " +
    "메시지 본문만 출력하고 다른 설명/머리말/따옴표는 붙이지 않는다.";
  const userPrompt =
    `다음 정보를 바탕으로 ${NAME_TOKEN} 에게 보낼 안내 메시지를 작성해줘.\n` +
    ctxLines.join("\n");

  // ----- 6) Gemini 호출 (실패 시 폴백용 구조화 에러) -----
  const apiKey = Deno.env.get("LLM_API_KEY");
  if (!apiKey) {
    await log("failed", "missing_api_key");
    return json(
      { ok: false, code: "llm_failed", message: "AI 키가 설정되지 않았습니다." },
      502,
    );
  }

  let aiText: string;
  try {
    const endpoint =
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemInstruction }] },
        contents: [{ role: "user", parts: [{ text: userPrompt }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 400 },
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`gemini ${res.status}: ${body.slice(0, 200)}`);
    }
    const data = await res.json();
    const text: string | undefined =
      data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text || !text.trim()) {
      // 안전 필터 차단 등으로 본문이 비어 올 수 있음 → 폴백 처리.
      throw new Error("empty_completion");
    }
    aiText = text.trim();
  } catch (e) {
    await log("failed", e instanceof Error ? e.message : String(e));
    return json(
      {
        ok: false,
        code: "llm_failed",
        message: "AI 초안 생성에 실패했습니다. 잠시 후 다시 시도하거나 수동으로 작성해 주세요.",
      },
      502,
    );
  }

  // ----- 7) 실명 복원 + draft 적재 -----
  const finalContent = aiText.split(NAME_TOKEN).join(realName);
  // 발송 예정: pre_session 은 오늘 20:00(KST), 그 외는 1시간 뒤(검수 여유).
  const scheduledFor = triggerType === "pre_session"
    ? new Date(`${todayKst}T20:00:00+09:00`).toISOString()
    : new Date(Date.now() + 60 * 60 * 1000).toISOString();

  const { data: inserted, error: insertErr } = await supabase
    .from("outgoing_notifications")
    .insert({
      trainer_id: trainer.id,
      target_member_id: memberId,
      source_session_id: payload.sessionId ?? null,
      trigger_type: triggerType,
      content: finalContent,
      status: "draft",
      ai_generated: true,
      // audit: 마스킹된 프롬프트만 저장(실명 미포함). PII 안전.
      ai_prompt_snapshot: `${systemInstruction}\n---\n${userPrompt}`,
      ai_original_content: finalContent,
      scheduled_for: scheduledFor,
    })
    .select("id")
    .single();

  if (insertErr || !inserted) {
    await log("failed", `insert_failed: ${insertErr?.message ?? "unknown"}`);
    return json(
      { ok: false, code: "save_failed", message: "초안 저장에 실패했습니다." },
      500,
    );
  }

  await log("success");
  return json({ ok: true, draftId: inserted.id, content: finalContent });
});
