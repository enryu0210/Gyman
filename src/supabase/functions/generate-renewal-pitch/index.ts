// =====================================================================
// generate-renewal-pitch — AI 재등록 유도 멘트 초안 생성 (Phase 1.9 확장 + 1.11)
//
// 재등록 알림이 뜬 회원에 대해, 그동안의 "성장 근거"(운동 중량 변화 + 인바디 변화)를
// 모아 재등록을 자연스럽게 유도하는 안내 메시지 초안을 만든다. 초안은
// outgoing_notifications 에 trigger_type='renewal_pitch', status='draft' 로 쌓이고,
// 기존 AI 검수 허브(1.9) → 승인 → markSent 게이트를 그대로 통과해야 회원에게 간다.
//
// 흐름(모두 트레이너 JWT 컨텍스트 = RLS 적용):
//   1) 인증 확인 (verify_jwt=true 기본)
//   2) 입력 검증 (memberId, contractId?)
//   3) 회원 조회 + AI 사용 동의(ai_consent_effective) 확인 — 거부 시 차단
//      ※ 트레이너 기록(ai_consent) AND NOT 회원 거부(ai_consent_member_optout).
//        회원이 거부하면 트레이너가 켜도 전송되지 않는다 (0040).
//   4) 일일 호출 한도(비용 가드) 확인 — 초과 시 차단
//   5) 진척 근거 수집: 계약 현황(v_contract_status) + 종목별 중량 향상 + 인바디 변화
//   6) 근거가 하나도 없으면 차단(no_progress_data) — "성장"을 지어내지 않기 위함
//   7) PII 마스킹(실명 → {{NAME}}) 후 Gemini 호출 — 제공 수치만 인용하도록 강하게 그라운딩
//   8) 실명 복원 → outgoing_notifications 에 draft 적재 → ai_call_logs 기록
//
// 보안 핵심(generate-message-draft 와 동일):
//   - LLM API 키는 서버 시크릿(LLM_API_KEY)에만. 클라이언트 노출 0.
//   - 회원 실명은 LLM 으로 전송하지 않음 — {{NAME}} 토큰으로 보내고 응답에서 복원.
//   - 미검수 발송 차단: 여기서는 draft 까지만. 승인/발송은 트레이너 검수(1.9 게이트).
//
// 환각 억제(CLAUDE.md LLM 지침):
//   - "제공된 수치 외의 성과를 지어내지 마라" 그라운딩.
//   - 진척 근거(중량 향상/인바디 변화/함께한 수업)가 하나도 없으면 생성 자체 차단.
//
// 환경변수(supabase secrets): LLM_API_KEY(필수) / LLM_MODEL / AI_DAILY_LIMIT.
// generate-message-draft·generate-memo-draft 와 가드/Gemini 패턴 병렬(베타 단계
// 가독성 우선, _shared 모듈화는 추후).
// 참고: docs/develop_plan.md §4 1.7/1.9/1.11, 와이어 06_ai_review.md.
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

// numeric(소수 첫째자리) 표기 통일. PostgREST 가 numeric 을 문자열/숫자 어느 쪽으로
// 줘도 Number() 로 흡수한다.
function fmt1(n: unknown): string {
  return (Number(n)).toFixed(1);
}

// exercises JSON 한 종목의 최고 세트 중량(kg). 세트가 없으면 0.
// 도메인 WeightTrendCalculator._topSetWeight 와 동일 규칙(그날 든 제일 무거운 무게).
// deno-lint-ignore no-explicit-any
function topSetWeight(ex: any): number {
  const sets = Array.isArray(ex?.sets) ? ex.sets : [];
  let top = 0;
  for (const s of sets) {
    const w = Number(s?.weight) || 0;
    if (w > top) top = w;
  }
  return top;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, code: "method_not_allowed" }, 405);
  }

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

  // ----- 입력 -----
  let payload: { memberId?: string; contractId?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, code: "bad_request", message: "JSON 본문 필요" }, 400);
  }
  const memberId = payload.memberId;
  const contractId = payload.contractId;
  if (!memberId) {
    return json({ ok: false, code: "bad_request", message: "memberId 필요" }, 400);
  }

  // ai_call_logs 기록 헬퍼 (실패해도 본 흐름을 막지 않음).
  const log = async (status: string, error?: string) => {
    try {
      await supabase.from("ai_call_logs").insert({
        trainer_id: trainer.id,
        member_id: memberId,
        function_name: "generate-renewal-pitch",
        trigger_type: "renewal_pitch",
        status,
        model: MODEL,
        error: error?.slice(0, 500),
      });
    } catch (_) { /* 로깅 실패는 무시 */ }
  };

  // ----- 3) 회원 + 동의 확인 (RLS 가 본인 담당 회원만 노출) -----
  const { data: member, error: memberErr } = await supabase
    .from("member_profiles")
    .select("id, name, goal, ai_consent_effective")
    .eq("id", memberId)
    .maybeSingle();

  if (memberErr || !member) {
    await log("blocked", "member_not_found_or_forbidden");
    return json(
      { ok: false, code: "not_found", message: "회원을 찾을 수 없습니다." },
      404,
    );
  }
  if (member.ai_consent_effective !== true) {
    await log("blocked", "consent_required");
    return json(
      {
        ok: false,
        code: "consent_required",
        message: "회원이 AI 사용에 동의하지 않았습니다. 멘트를 직접 작성해 주세요.",
      },
      403,
    );
  }

  // ----- 4) 일일 호출 한도(비용 가드) -----
  // KST 기준 오늘 시작 이후의 성공 호출 수. trainer_id 를 명시적으로 걸어
  // '1인 한도'가 전체 합산으로 새지 않게 방어(defense in depth).
  const kstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const todayKst = kstNow.toISOString().slice(0, 10);
  const todayStartIso = new Date(`${todayKst}T00:00:00+09:00`).toISOString();
  const { count } = await supabase
    .from("ai_call_logs")
    .select("*", { count: "exact", head: true })
    .eq("trainer_id", trainer.id)
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

  // ----- 5a) 계약 현황 (재등록 시급성) -----
  // contractId 가 오면 그 계약을, 없으면 잔여가 가장 적은(가장 시급한) 활성 계약을 본다.
  let statusQuery = supabase
    .from("v_contract_status")
    .select("contract_id, total_sessions, used_sessions, remaining_sessions, end_date")
    .eq("member_id", memberId);
  statusQuery = contractId
    ? statusQuery.eq("contract_id", contractId)
    : statusQuery.order("remaining_sessions", { ascending: true });
  const { data: statusRows } = await statusQuery.limit(1);
  const status = statusRows?.[0];
  // COUNT/집계는 bigint → Number() 로 흡수(직접 캐스팅 금지).
  const usedSessions = status ? Number(status.used_sessions) : 0;

  // ----- 5b) 종목별 중량 향상 (done 수업의 운동기록) -----
  // 오름차순으로 받아 "첫 기록 → 최신 기록" 최고중량 변화를 종목별로 집계한다.
  const { data: sessRows } = await supabase
    .from("sessions")
    .select(`
      scheduled_at, status,
      session_records(exercises),
      pt_contracts!inner(member_id)
    `)
    .eq("pt_contracts.member_id", memberId)
    .eq("status", "done")
    .order("scheduled_at", { ascending: true })
    .limit(300);

  // 종목명 → { 첫 최고중량, 최신 최고중량, 첫/최신 날짜 }
  const byExercise = new Map<
    string,
    { first: number; last: number; firstDate: string; lastDate: string }
  >();
  let firstSessionDate: string | null = null;
  let lastSessionDate: string | null = null;
  for (const s of (sessRows ?? [])) {
    const rec = Array.isArray(s.session_records)
      ? s.session_records[0]
      : s.session_records;
    const exs = rec?.exercises;
    if (!Array.isArray(exs)) continue;
    const date = String(s.scheduled_at).slice(0, 10);
    firstSessionDate ??= date;
    lastSessionDate = date;

    // 한 수업 안에서 같은 종목이 여러 번 나오면 최고중량으로 먼저 합친다.
    const topThisSession = new Map<string, number>();
    for (const ex of exs) {
      const name = (ex?.name ?? "").trim();
      if (!name) continue;
      const top = topSetWeight(ex);
      if (top <= 0) continue; // 맨몸/무게 미기록은 중량 변화에서 제외
      const prev = topThisSession.get(name) ?? 0;
      if (top > prev) topThisSession.set(name, top);
    }
    for (const [name, top] of topThisSession) {
      const p = byExercise.get(name);
      if (!p) {
        byExercise.set(name, { first: top, last: top, firstDate: date, lastDate: date });
      } else {
        // 오름차순이라 나중 수업이 last 를 덮어쓴다.
        p.last = top;
        p.lastDate = date;
      }
    }
  }
  // 향상폭이 큰 순으로 상위 4개 종목만(멘트가 장황해지지 않게).
  const improvements = [...byExercise.entries()]
    .map(([name, p]) => ({ name, gain: p.last - p.first, first: p.first, last: p.last }))
    .filter((x) => x.gain > 0)
    .sort((a, b) => b.gain - a.gain)
    .slice(0, 4);

  // ----- 5c) 인바디 변화 (첫 측정 → 최신 측정) -----
  const { data: measRows } = await supabase
    .from("body_measurements")
    .select("weight_kg, body_fat_pct, skeletal_muscle_kg, measured_at")
    .eq("member_id", memberId)
    .order("measured_at", { ascending: true });

  const measDeltaLines: string[] = [];
  if (Array.isArray(measRows) && measRows.length >= 2) {
    const first = measRows[0];
    const last = measRows[measRows.length - 1];
    const period = `${String(first.measured_at).slice(0, 10)} ~ ${String(last.measured_at).slice(0, 10)}`;
    // 지표별로 첫/최신 둘 다 있을 때만 변화 표기(부분 측정 대비).
    const push = (label: string, f: unknown, l: unknown, unit: string, betterDown: boolean) => {
      if (f == null || l == null) return;
      const fv = Number(f), lv = Number(l);
      const delta = lv - fv;
      const sign = delta > 0 ? "+" : "";
      // 방향 해석은 LLM 에 맡기되, 사실만 제공.
      measDeltaLines.push(
        `- ${label}: ${fmt1(fv)}${unit} → ${fmt1(lv)}${unit} (${sign}${fmt1(delta)}${unit})`,
      );
      void betterDown; // 방향 힌트는 프롬프트 규칙으로 대체(여기선 사실만).
    };
    // 측정 기간을 한 줄로 먼저.
    if (
      first.weight_kg != null || first.skeletal_muscle_kg != null ||
      first.body_fat_pct != null
    ) {
      measDeltaLines.push(`- 측정 기간: ${period}`);
    }
    push("체중", first.weight_kg, last.weight_kg, "kg", true);
    push("골격근량", first.skeletal_muscle_kg, last.skeletal_muscle_kg, "kg", false);
    push("체지방률", first.body_fat_pct, last.body_fat_pct, "%", true);
  }

  // ----- 6) 근거 유무 검증 — 없으면 생성 차단(성장 지어내기 방지) -----
  const hasMeasurementDelta = measDeltaLines.some((l) => !l.startsWith("- 측정 기간"));
  const hasEvidence = improvements.length > 0 || hasMeasurementDelta ||
    usedSessions >= 1;
  if (!hasEvidence) {
    await log("blocked", "no_progress_data");
    return json(
      {
        ok: false,
        code: "no_progress_data",
        message:
          "분석할 운동/인바디 기록이 없습니다. 수업 기록이나 인바디 측정을 남긴 뒤 다시 시도하거나 직접 작성해 주세요.",
      },
      409,
    );
  }

  // ----- 7) 컨텍스트 조립 + PII 마스킹 -----
  const realName: string = member.name;
  const NAME_TOKEN = "{{NAME}}";
  const mask = (t: string | null | undefined): string =>
    (t ?? "").split(realName).join(NAME_TOKEN);

  const ctxLines: string[] = [];
  if (member.goal) ctxLines.push(`- 회원 운동 목적: ${mask(member.goal)}`);
  if (status) {
    const total = Number(status.total_sessions);
    const remaining = Number(status.remaining_sessions);
    ctxLines.push(
      `- PT 진행: 총 ${total}회 중 ${usedSessions}회 함께함, 잔여 ${remaining}회`,
    );
    if (status.end_date) ctxLines.push(`- 계약 만료 예정일: ${status.end_date}`);
  }
  if (firstSessionDate && lastSessionDate && firstSessionDate !== lastSessionDate) {
    ctxLines.push(`- 함께한 기간: ${firstSessionDate} ~ ${lastSessionDate}`);
  }
  if (improvements.length > 0) {
    ctxLines.push("- 주요 종목 중량 성장:");
    for (const im of improvements) {
      ctxLines.push(`  · ${im.name}: ${im.first}kg → ${im.last}kg (+${im.gain}kg)`);
    }
  }
  if (measDeltaLines.length > 0) {
    ctxLines.push("- 인바디 변화:");
    for (const l of measDeltaLines) ctxLines.push(`  ${l}`);
  }

  const systemInstruction = [
    "너는 한국의 PT 트레이너다. 아래 '회원 진척 정보'에 실제로 적힌 수치만 근거로,",
    "회원에게 보낼 재등록 유도 안내 메시지를 작성한다.",
    "",
    "[출력 규칙 — 반드시 지킬 것]",
    "- 회원에게 보낼 메시지 본문만 출력한다(너의 생각/분석/머리말/따옴표/코드블록 금지).",
    `- 회원을 부를 때는 정확히 ${NAME_TOKEN} 라고만 쓴다. 실제 이름을 지어내지 않는다.`,
    "- 아래 제공된 수치(중량 변화·인바디 변화·수업 횟수·기간)만 인용한다. 없는 성과를 지어내지 마라.",
    "- 그동안의 구체적 변화를 짚어 준 뒤, 계속 이어가자는 흐름으로 재등록을 자연스럽게 제안한다.",
    "- 강매/압박 표현(예: '지금 결제하세요', '할인 마감 임박')은 쓰지 않는다. 따뜻하게 다음 단계를 권한다.",
    "- 3~5문장, 친근하고 자연스러운 한국어. 의학적 단정(진단)이나 과장 표현은 피한다.",
  ].join("\n");
  const userPrompt =
    `다음 회원의 진척 정보를 바탕으로 ${NAME_TOKEN} 에게 보낼 재등록 유도 메시지를 작성해줘.\n` +
    "아래에 적힌 수치 외의 성과는 절대 추가하지 마.\n" +
    ctxLines.join("\n");

  // ----- Gemini 호출 (thinking off + 견고한 파싱) -----
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
        generationConfig: {
          // 설득 멘트라 약간의 표현력은 두되, 수치 그라운딩이 흔들리지 않게 중간값.
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
        message: "AI 멘트 생성에 실패했습니다. 잠시 후 다시 시도하거나 직접 작성해 주세요.",
      },
      502,
    );
  }

  // ----- 8) 실명 복원 + draft 적재 -----
  const finalContent = aiText.replace(/\{\{\s*NAME\s*\}\}/g, realName);
  // 재등록 멘트는 트레이너 승인 즉시(markSent) 발송되는 흐름이라 scheduled_for 는
  // 검수 여유용 placeholder(1시간 뒤)로 둔다.
  const scheduledFor = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  const { data: inserted, error: insertErr } = await supabase
    .from("outgoing_notifications")
    .insert({
      trainer_id: trainer.id,
      target_member_id: memberId,
      // 특정 수업이 아니라 누적 진척 기반이라 source_session_id 는 없음.
      source_session_id: null,
      trigger_type: "renewal_pitch",
      content: finalContent,
      status: "draft",
      ai_generated: true,
      // audit: 마스킹된 프롬프트만 저장(실명 미포함).
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
