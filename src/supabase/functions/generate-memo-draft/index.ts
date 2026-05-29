// =====================================================================
// generate-memo-draft — AI-C 트레이너 전용 메모 초안 생성 (Phase 1.10 + 1.11)
//
// 수업 기록(condition/pain/next_memo/exercises)을 바탕으로 트레이너 "본인만 보는"
// 메모 초안을 만들어 member_notes 에 source='ai_draft', visibility='trainer_only' 로
// 적재한다. RLS(notes_member_deny)로 회원에게는 어떤 경우에도 안 보임.
//
// 흐름(트레이너 JWT 컨텍스트 = RLS):
//   인증 → 입력(memberId, sessionId?) → 기반 수업 선택(미지정 시 최근 done) →
//   동의 확인 → 일일 한도 → PII 마스킹 → Gemini → 폴백 → member_notes 적재 → 로그
//
// 안전:
//   - 메모는 트레이너 전용 — 그래도 LLM 전송 전 실명은 {{NAME}} 토큰으로 마스킹.
//   - ai_draft 로만 저장. ai_confirmed(확정)는 트레이너가 검수 후 앱에서 전환.
//
// generate-message-draft 와 가드/Gemini 호출 패턴 동일(의도적 병렬 — 베타 단계
// 가독성 우선, 함수 2개 분량이라 _shared 모듈화는 추후).
// 참고: docs/develop_plan.md §4 1.10/1.11, 와이어 06_ai_review.md 6.4.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL = Deno.env.get("LLM_MODEL") ?? "gemini-3.5-flash";
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");

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

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData } = await supabase.auth.getUser();
  const trainer = userData.user;
  if (!trainer) return json({ ok: false, code: "unauthorized" }, 401);

  let payload: { memberId?: string; sessionId?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, code: "bad_request", message: "JSON 본문 필요" }, 400);
  }
  const memberId = payload.memberId;
  if (!memberId) {
    return json({ ok: false, code: "bad_request", message: "memberId 필요" }, 400);
  }

  const log = async (status: string, error?: string) => {
    try {
      await supabase.from("ai_call_logs").insert({
        trainer_id: trainer.id,
        member_id: memberId,
        function_name: "generate-memo-draft",
        trigger_type: "session_memo",
        status,
        model: MODEL,
        error: error?.slice(0, 500),
      });
    } catch (_) { /* 로깅 실패는 무시 */ }
  };

  // ----- 기반 수업 선택 (sessionId 미지정 시 최근 done 수업) -----
  let q = supabase.from("sessions").select(`
      id, scheduled_at, status,
      session_records(condition, pain, next_memo, exercises),
      pt_contracts!inner(member_id, member_profiles!inner(id, name, goal, ai_consent))
    `).eq("pt_contracts.member_id", memberId);
  q = payload.sessionId
    ? q.eq("id", payload.sessionId)
    : q.eq("status", "done").order("scheduled_at", { ascending: false });
  const { data: sessRows, error: sessErr } = await q.limit(1);
  const session = sessRows?.[0];
  if (sessErr || !session) {
    await log("blocked", "no_session");
    return json(
      {
        ok: false,
        code: "no_session",
        message: "메모의 기반이 될 수업 기록이 없습니다. 수업을 먼저 기록해 주세요.",
      },
      404,
    );
  }

  // deno-lint-ignore no-explicit-any
  const contract = (session as any).pt_contracts;
  const member = contract.member_profiles;
  if (member.ai_consent !== true) {
    await log("blocked", "consent_required");
    return json(
      {
        ok: false,
        code: "consent_required",
        message: "회원이 AI 사용에 동의하지 않았습니다. 메모를 직접 작성해 주세요.",
      },
      403,
    );
  }

  // ----- 일일 한도 -----
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const todayKst = kstNow.toISOString().slice(0, 10);
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
        message: "오늘 AI 생성 한도를 초과했습니다. 내일 다시 시도하거나 직접 작성해 주세요.",
      },
      429,
    );
  }

  // ----- 컨텍스트 + PII 마스킹 -----
  const rec = Array.isArray(session.session_records)
    ? session.session_records[0]
    : session.session_records;
  const realName: string = member.name;
  const NAME_TOKEN = "{{NAME}}";
  const mask = (t: string | null | undefined): string =>
    (t ?? "").split(realName).join(NAME_TOKEN);

  // 운동 종목 이름만 요약(세트 상세는 메모 초안에 과함).
  let exerciseNames = "";
  try {
    const ex = rec?.exercises;
    if (Array.isArray(ex)) {
      exerciseNames = ex
        // deno-lint-ignore no-explicit-any
        .map((e: any) => (typeof e?.name === "string" ? e.name : ""))
        .filter((s: string) => s.length > 0)
        .join(", ");
    }
  } catch (_) { /* 형식 어긋나도 메모는 생성 */ }

  const sessionDate = String(session.scheduled_at).slice(0, 10);
  const ctxLines: string[] = [`- 수업일: ${sessionDate}`];
  if (member.goal) ctxLines.push(`- 회원 목적: ${mask(member.goal)}`);
  if (exerciseNames) ctxLines.push(`- 진행 종목: ${exerciseNames}`);
  if (rec?.condition) ctxLines.push(`- 컨디션: ${mask(rec.condition)}`);
  if (rec?.pain) ctxLines.push(`- 통증/특이사항: ${mask(rec.pain)}`);
  if (rec?.next_memo) ctxLines.push(`- 다음 수업 메모: ${mask(rec.next_memo)}`);

  const systemInstruction = [
    "너는 한국의 PT 트레이너다. 방금 진행한 수업 기록을 바탕으로, 트레이너 본인만 보는 짧은 메모 초안을 작성한다.",
    "",
    "[출력 규칙 — 반드시 지킬 것]",
    "- 트레이너 전용 내부 메모만 출력한다(회원에게 보내는 메시지가 아니다).",
    "- 너의 생각/분석/설명/머리말/코드블록/따옴표는 절대 포함하지 않는다.",
    `- 회원을 지칭할 때는 정확히 ${NAME_TOKEN} 라고만 쓴다. 실제 이름을 지어내지 않는다.`,
    "- 3~5개의 간결한 한국어 불릿(각 줄을 '• ' 로 시작)으로 작성한다.",
    "- 내용: 관찰된 특이사항, 통증/컨디션, 다음 수업 조정 포인트.",
    "- 의학적 단정(진단)은 피하고 관찰/제안 톤으로 쓴다.",
  ].join("\n");
  const userPrompt = "다음 수업 기록을 바탕으로 트레이너 메모 초안을 작성해줘.\n" +
    ctxLines.join("\n");

  // ----- Gemini 호출 (thinking off + 견고한 파싱) -----
  const apiKey = Deno.env.get("LLM_API_KEY");
  if (!apiKey) {
    await log("failed", "missing_api_key");
    return json({ ok: false, code: "llm_failed", message: "AI 키가 설정되지 않았습니다." }, 502);
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
        generationConfig: {
          temperature: 0.6,
          maxOutputTokens: 1024,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`gemini ${res.status}: ${body.slice(0, 200)}`);
    }
    const data = await res.json();
    const cand = data?.candidates?.[0];
    const parts = cand?.content?.parts;
    let text = "";
    if (Array.isArray(parts)) {
      text = parts
        .filter((p: { thought?: boolean; text?: string }) =>
          p && p.thought !== true && typeof p.text === "string")
        .map((p: { text?: string }) => p.text ?? "")
        .join("")
        .trim();
    }
    if (!text) {
      throw new Error(`empty_completion (finishReason=${cand?.finishReason ?? "?"})`);
    }
    aiText = text;
  } catch (e) {
    await log("failed", e instanceof Error ? e.message : String(e));
    return json(
      {
        ok: false,
        code: "llm_failed",
        message: "AI 메모 초안 생성에 실패했습니다. 잠시 후 다시 시도하거나 직접 작성해 주세요.",
      },
      502,
    );
  }

  // ----- 실명 복원 + member_notes 적재 (ai_draft) -----
  const finalContent = aiText.replace(/\{\{\s*NAME\s*\}\}/g, realName);

  const { data: inserted, error: insertErr } = await supabase
    .from("member_notes")
    .insert({
      member_id: memberId,
      trainer_id: trainer.id,
      content: finalContent,
      visibility: "trainer_only",
      source: "ai_draft",
      source_session_id: session.id,
    })
    .select("id")
    .single();

  if (insertErr || !inserted) {
    await log("failed", `insert_failed: ${insertErr?.message ?? "unknown"}`);
    return json({ ok: false, code: "save_failed", message: "메모 초안 저장에 실패했습니다." }, 500);
  }

  await log("success");
  return json({ ok: true, noteId: inserted.id, content: finalContent });
});
