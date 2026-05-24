-- =====================================================================
-- 0007_init_outgoing_notifications.sql
-- outgoing_notifications: AI 안내 메시지 발송 큐 (AI-B)
-- "트레이너 검수 없이는 회원에게 안 감"을 status 흐름 + CHECK + RLS로 강제
-- 참고: docs/data_model.md §2.2, 와이어프레임 06_ai_review.md
-- =====================================================================

CREATE TABLE outgoing_notifications (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id          uuid NOT NULL REFERENCES trainer_profiles(user_id),
  target_member_id    uuid NOT NULL REFERENCES member_profiles(user_id),
  -- 트리거 종류 (자동 cron 또는 수동 트리거 출처 식별)
  --   'pre_session'         : 다음 수업 전날 안내
  --   'renewal_half'        : 횟수 절반 소진
  --   'renewal_five_left'   : 5회 남음
  --   'renewal_expiring'    : 7일 이내 만료
  --   'late_cancel_notice'  : 당일 취소 차감 안내
  --   'manual'              : 트레이너 수동 트리거
  trigger_type        text NOT NULL,
  content             text NOT NULL,           -- 실제 발송될 본문
  status              notification_status NOT NULL DEFAULT 'draft',
  ai_generated        boolean NOT NULL DEFAULT false,
  -- audit용: 어떤 입력으로 LLM이 생성했는지. PII 마스킹 후 저장 권장.
  ai_prompt_snapshot  text,
  -- "AI 원본으로 되돌리기" 위한 원본 보관 (수정 추적)
  ai_original_content text,
  scheduled_for       timestamptz NOT NULL,    -- 발송 예정 시각
  approved_at         timestamptz,             -- 트레이너 검수·승인 시각
  sent_at             timestamptz,             -- 실제 발송 시각
  send_channel        text,                    -- 'fcm' | 'kakao_alimtalk' | ...
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  -- 핵심 안전장치: sent로 가려면 반드시 approved_at이 있어야 한다.
  -- DB 레벨에서 "트레이너 미검수 발송"을 차단.
  CONSTRAINT chk_sent_requires_approval
    CHECK (status <> 'sent' OR approved_at IS NOT NULL)
);

-- 트레이너 홈 "검수 대기 N건" 카운트용
CREATE INDEX idx_notif_trainer_pending ON outgoing_notifications(trainer_id)
  WHERE status = 'draft';

-- 발송 큐 처리 cron이 가져갈 행 빠른 조회
CREATE INDEX idx_notif_send_queue ON outgoing_notifications(scheduled_for)
  WHERE status = 'approved';
