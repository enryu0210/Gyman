import assert from "node:assert";
import {
  buildCoachingPrompt,
  type CoachingInput,
  hasCoachingEvidence,
} from "./coaching_prompt.ts";
const empty = (): CoachingInput => ({
  realName: "홍길동",
  constraints: [],
  rules: [],
  marks: [],
  exercises: [],
});
Deno.test("근거가 없으면 차단하고 각 종류의 근거는 허용한다", () => {
  assert.equal(hasCoachingEvidence(empty()), false);
  assert.equal(
    hasCoachingEvidence({
      ...empty(),
      goal: "건강",
      rules: [{
        condition_code: "a",
        movement_pattern: "b",
        action: "caution",
        cue: "큐",
      }],
    }),
    false,
  );
  assert.equal(
    hasCoachingEvidence({
      ...empty(),
      constraints: [{
        code: "a",
        label: "제약",
        source: "medical",
        member_note: null,
      }],
    }),
    true,
  );
  assert.equal(
    hasCoachingEvidence({
      ...empty(),
      marks: [{ body_part: null, comment: "관찰", title: "영상" }],
    }),
    true,
  );
  assert.equal(
    hasCoachingEvidence({ ...empty(), exercises: ["스쿼트"] }),
    true,
  );
});
Deno.test("미동의 제약과 그 규칙은 사용자 프롬프트에 포함하지 않는다", () => {
  const { user } = buildCoachingPrompt({
    ...empty(),
    exercises: ["스쿼트"],
    rules: [{
      condition_code: "a",
      movement_pattern: "b",
      action: "caution",
      cue: "비공개큐",
    }],
  }, "{{NAME}}");
  assert.ok(!user.includes("체형 제약"));
  assert.ok(!user.includes("동작 큐"));
  assert.ok(!user.includes("비공개큐"));
});
Deno.test("의료 이력과 트레이너 관찰 출처를 구분한다", () => {
  const { user } = buildCoachingPrompt({
    ...empty(),
    constraints: [
      { code: "a", label: "의료기록", source: "medical", member_note: null },
      {
        code: "b",
        label: "관찰기록",
        source: "trainer_observation",
        member_note: "관찰",
      },
    ],
  }, "{{NAME}}");
  assert.ok(user.includes("의료기록 / 진단 이력이 등록되어 있어"));
  assert.ok(user.includes("관찰기록 / 트레이너가 관찰한 (진단 아님)"));
});
Deno.test("안전선과 마지막 의료기관 안내를 지시한다", () => {
  const { system } = buildCoachingPrompt(empty(), "{{NAME}}");
  for (
    const rule of [
      "~증입니다",
      "~하지 마세요",
      "교정/치료",
      "중량·세트·횟수",
      "자세 포인트 2~3개",
      "추천 운동 1~3개",
      "통증이 있으면 운동을 멈추고 트레이너나 의료기관과 상의하세요.",
      "마지막 문장",
      "제공된 근거만",
    ]
  ) assert.ok(system.includes(rule));
});
Deno.test("모든 자유 텍스트의 실명을 마스킹한다", () => {
  const { system, user } = buildCoachingPrompt({
    ...empty(),
    goal: "홍길동의 목표",
    constraints: [{
      code: "홍길동코드",
      label: "홍길동 제약",
      source: "medical",
      member_note: "홍길동 메모",
    }],
    rules: [{
      condition_code: "홍길동코드",
      movement_pattern: "홍길동 패턴",
      action: "caution",
      cue: "홍길동 큐",
    }],
    marks: [{
      body_part: "홍길동 어깨",
      comment: "홍길동 지적",
      title: "홍길동 영상",
    }],
    exercises: ["홍길동 운동"],
  }, "{{NAME}}");
  assert.ok(!`${system}\n---\n${user}`.includes("홍길동"));
  for (
    const masked of [
      "{{NAME}}의 목표",
      "{{NAME}} 메모",
      "{{NAME}} 큐",
      "{{NAME}} 지적",
      "{{NAME}} 영상",
      "{{NAME}} 운동",
    ]
  ) assert.ok(user.includes(masked));
});
