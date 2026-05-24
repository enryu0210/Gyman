-- =====================================================================
-- 0001_init_enums.sql
-- ENUM 타입 정의: 역할/상태/가시성/알림 단계 등 코드성 값
-- 참고: docs/data_model.md §2.1
-- =====================================================================

-- 사용자 역할
CREATE TYPE user_role AS ENUM ('trainer', 'member', 'admin');

-- 수업 상태 (예약→완료/노쇼/취소 전이)
CREATE TYPE session_status AS ENUM (
  'scheduled',   -- 예약됨
  'done',        -- 완료 (기록됨)
  'no_show',     -- 노쇼 (회원 미참석, 차감)
  'canceled',    -- 정상 취소 (차감 없음)
  'late_cancel'  -- 당일/지각 취소 (차감)
);

-- 트레이너 전용 메모의 회원 노출 여부
-- 현재는 'trainer_only' 단일 정책이지만, 향후 'shared'(회원도 볼 수 있는 코칭 노트) 확장 대비
CREATE TYPE note_visibility AS ENUM ('trainer_only', 'shared');

-- 재등록 알림 단계 (홈 카드/푸시 트리거에 사용)
CREATE TYPE renewal_alert_level AS ENUM (
  'none',        -- 알림 없음
  'half',        -- 횟수 절반 소진
  'five_left',   -- 5회 남음
  'expiring'     -- 곧 만료 (7일 이내)
);

-- AI 메모 생성 출처 (AI-C 위해 추가)
--   manual:       트레이너가 직접 작성
--   ai_draft:     AI가 만든 초안, 트레이너 미확정
--   ai_confirmed: AI 초안을 트레이너가 검토 후 확정
CREATE TYPE note_source AS ENUM ('manual', 'ai_draft', 'ai_confirmed');

-- 외부 발송 안내 메시지 상태 (AI-B 위해 추가)
--   draft:    초안 생성됨 (AI 또는 템플릿), 트레이너 미검수
--   approved: 트레이너가 검수·발송 승인. 예약 시각 도달하면 발송 큐가 가져감
--   sent:     실제 발송 완료
--   canceled: 트레이너가 발송 취소
CREATE TYPE notification_status AS ENUM ('draft', 'approved', 'sent', 'canceled');
