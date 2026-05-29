// =====================================================================
// health — Edge Function 배포 파이프라인 검증용 헬스체크
//
// 목적:
//   "배포 → 호출 → 시크릿 주입" 3단계가 실제로 동작하는지 확인하는 최소 함수.
//   AI-B(회원 안내 메시지)/AI-C(트레이너 메모) LLM 함수를 올리기 전에,
//   파이프라인 자체를 먼저 검증한다.
//
// 응답 예:
//   { "status": "ok", "time": "2026-05-29T...Z", "llmKeyConfigured": false }
//
// llmKeyConfigured:
//   서버 사이드 시크릿이 제대로 주입되는지 검증하기 위한 boolean.
//   **키 값 자체는 절대 응답에 넣지 않는다** — 존재 여부(boolean)만 노출.
//   실제 키 이름/공급자(OpenAI·Anthropic 등)는 LLM 함수 구현 단계에서 확정.
//   (develop_plan.md §0 AI 모델, §6 PII/키 보안)
//
// 배포/호출 방법: functions/README.md 참고.
// =====================================================================

// CORS — Flutter web 등 브라우저에서 호출 시 preflight 대응.
// 모바일(supabase.functions.invoke)에는 영향 없지만, 채널이 늘어도 깨지지 않게 둠.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve((req: Request) => {
  // preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const body = {
    status: "ok",
    time: new Date().toISOString(),
    // 시크릿 주입 검증 — 값이 아니라 "설정 여부"만.
    llmKeyConfigured: Boolean(Deno.env.get("LLM_API_KEY")),
  };

  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
