// 기존 생성 함수와 인증·검수 골격을 맞춰 미검수 회원 노출을 방지한다.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildCoachingPrompt,
  type CoachingInput,
  hasCoachingEvidence,
} from "./coaching_prompt.ts";

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
  let payload: { memberId?: string } | null;
  try {
    payload = await req.json();
  } catch {
    return json(
      { ok: false, code: "bad_request", message: "JSON 본문 필요" },
      400,
    );
  }
  const memberId = payload?.memberId;
  if (typeof memberId !== "string" || !memberId.trim()) {
    return json(
      { ok: false, code: "bad_request", message: "memberId 필요" },
      400,
    );
  }

  // ai_call_logs 기록 헬퍼 (실패해도 본 흐름을 막지 않음).
  const log = async (status: string, error?: string) => {
    try {
      await supabase.from("ai_call_logs").insert({
        trainer_id: trainer.id,
        member_id: memberId,
        function_name: "generate-coaching-draft",
        trigger_type: "coaching_guide",
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
        message:
          "회원이 AI 사용에 동의하지 않았습니다. 멘트를 직접 작성해 주세요.",
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
        message:
          "오늘 AI 생성 한도를 초과했습니다. 내일 다시 시도하거나 직접 작성해 주세요.",
      },
      429,
    );
  }

  // 확인 실패는 동의로 간주하지 않으며 일반 근거 수집은 계속한다.
  let sensitiveConsent = false;
  try {
    const consent = await supabase.rpc("member_sensitive_consent", {
      p_member_id: memberId,
    });
    sensitiveConsent = !consent.error && consent.data === true;
  } catch (_) { /* 동의 확인 실패 시 건강정보를 조회하지 않는다. */ }
  let constraints: CoachingInput["constraints"] = [];
  let rules: CoachingInput["rules"] = [];
  // 조회 전에 차단해야 미동의 건강정보가 서버 메모리에도 들어오지 않는다.
  if (sensitiveConsent) {
    const result = await supabase.from("member_conditions")
      .select("code, label, source, member_note")
      .eq("member_id", memberId).eq("active", true);
    if (result.error) {
      await log("failed", "evidence_query_failed");
      return json({
        ok: false,
        code: "data_failed",
        message: "코칭 근거를 불러오지 못했습니다.",
      }, 500);
    }
    constraints = result.data ?? [];
    const codes = [...new Set(constraints.map((item) => item.code))];
    if (codes.length > 0) {
      const result = await supabase.from("condition_coaching_rules")
        .select("condition_code, movement_pattern, action, cue")
        .in("condition_code", codes).limit(6);
      if (result.error) {
        await log("failed", "evidence_query_failed");
        return json({
          ok: false,
          code: "data_failed",
          message: "코칭 근거를 불러오지 못했습니다.",
        }, 500);
      }
      rules = result.data ?? [];
    }
  }
  const marksResult = await supabase.from("class_video_marks")
    .select("body_part, comment, class_videos!inner(member_id, title)")
    .eq("class_videos.member_id", memberId)
    .order("created_at", { ascending: false }).limit(10);
  const sessionsResult = await supabase.from("sessions")
    .select("session_records(exercises), pt_contracts!inner(member_id)")
    .eq("pt_contracts.member_id", memberId).eq("status", "done")
    .order("scheduled_at", { ascending: false }).limit(5);
  // 조회 실패를 기록 없음으로 안내하면 불필요한 재입력을 유발하므로 구분한다.
  if (marksResult.error || sessionsResult.error) {
    await log("failed", "evidence_query_failed");
    return json({
      ok: false,
      code: "data_failed",
      message: "코칭 근거를 불러오지 못했습니다.",
    }, 500);
  }
  const marks = (marksResult.data ?? []).map((mark) => {
    const video = Array.isArray(mark.class_videos)
      ? mark.class_videos[0]
      : mark.class_videos;
    return {
      body_part: mark.body_part,
      comment: mark.comment,
      title: video?.title ?? "",
    };
  });
  const exerciseNames = new Set<string>();
  for (const session of sessionsResult.data ?? []) {
    const records = Array.isArray(session.session_records)
      ? session.session_records
      : [session.session_records];
    for (const record of records) {
      if (!Array.isArray(record?.exercises)) continue;
      for (const exercise of record.exercises) {
        // 수치나 다른 기록 필드는 복사하지 않고 종목명만 허용한다.
        if (typeof exercise?.name === "string" && exercise.name.trim()) {
          exerciseNames.add(exercise.name.trim());
        }
      }
    }
  }
  const input: CoachingInput = {
    realName: member.name,
    goal: member.goal,
    constraints,
    rules,
    marks,
    exercises: [...exerciseNames].slice(0, 10),
  };
  if (!hasCoachingEvidence(input)) {
    await log("blocked", "no_coaching_data");
    return json({
      ok: false,
      code: "no_coaching_data",
      message:
        "코칭 근거(체형 제약·영상 지적·운동 기록)가 없습니다. 먼저 기록을 남겨 주세요.",
    }, 409);
  }
  const realName: string = member.name;
  const NAME_TOKEN = "{{NAME}}";
  const { system: systemInstruction, user: userPrompt } = buildCoachingPrompt(
    input,
    NAME_TOKEN,
  );

  const apiKey = Deno.env.get("LLM_API_KEY");
  if (!apiKey) {
    await log("failed", "missing_api_key");
    return json(
      {
        ok: false,
        code: "llm_failed",
        message: "AI 키가 설정되지 않았습니다.",
      },
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
          // 근거 밖의 해석을 줄이기 위해 표현의 변동성을 낮춘다.
          temperature: 0.3,
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
          p && p.thought !== true && typeof p.text === "string"
        )
        .map((p: { text?: string }) => p.text ?? "")
        .join("")
        .trim();
    }
    if (!text) {
      throw new Error(
        `empty_completion (finishReason=${cand?.finishReason ?? "?"})`,
      );
    }
    aiText = text;
  } catch (e) {
    await log("failed", e instanceof Error ? e.message : String(e));
    return json(
      {
        ok: false,
        code: "llm_failed",
        message:
          "AI 멘트 생성에 실패했습니다. 잠시 후 다시 시도하거나 직접 작성해 주세요.",
      },
      502,
    );
  }

  // ----- 8) 실명 복원 + draft 적재 -----
  const finalContent = aiText.replace(/\{\{\s*NAME\s*\}\}/g, realName);
  // 트레이너 검수를 거쳐 발송하므로 scheduled_for 는
  // 검수 여유용 placeholder(1시간 뒤)로 둔다.
  const scheduledFor = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  const { data: inserted, error: insertErr } = await supabase
    .from("outgoing_notifications")
    .insert({
      trainer_id: trainer.id,
      target_member_id: memberId,
      // 여러 기록의 코칭 근거를 모으므로 특정 수업에 연결하지 않는다.
      source_session_id: null,
      trigger_type: "coaching_guide",
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
