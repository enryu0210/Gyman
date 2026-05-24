# Gyman — 데이터 모델 & RLS 정책 (v0.1 초안)

> 본 문서는 `docs/develop_plan.md` §2를 기준으로
> **Supabase(Postgres)에서 그대로 실행 가능한 수준의 SQL 스키마와 RLS 정책**을 정의합니다.
>
> 작성일: 2026-05-24
> 대상 DB: PostgreSQL 15+ (Supabase)
> 상태: **초안** — 친구/사용자 검토 후 Phase 0 마이그레이션(`supabase/migrations/0001_init.sql`)으로 확정

---

## 0. 설계 원칙 (다시 한번)

| # | 원칙 | 출처 |
|---|------|------|
| 1 | **필드 단위 가시성** — 트레이너 전용 메모는 회원이 절대 못 본다 | 기획서 답변 9 |
| 2 | **AI 결과는 트레이너 검수 후에만 회원 노출** — `body_assessments.trainer_comment IS NOT NULL` 조건 | 기획서 답변 14 |
| 3 | **잔여 횟수/재등록 계산은 DB가 아닌 도메인 로직에서** — 분쟁 시 재계산/감사 가능 | develop_plan §2.3 |
| 4 | **모든 테이블에 RLS 활성화** — 누락된 테이블 = 데이터 유출 경로 | develop_plan §6 |
| 5 | **soft delete 우선** — 회원/계약 삭제는 `deleted_at` 마킹, 매출 분쟁 대비 | 신규 |

---

## 1. 엔티티 관계도 (ERD, 텍스트)

```
auth.users (Supabase Auth)
   │
   ├──< trainer_profiles (1:1)
   │       └──< sessions.recorded_by_trainer_id
   │       └──< member_notes.trainer_id
   │       └──< pt_contracts.trainer_id
   │
   ├──< member_profiles (1:1)
   │       └──< pt_contracts.member_id
   │       └──< member_notes.member_id
   │       └──< body_assessments.member_id
   │
   └──< admin_profiles (1:1)

centers (1) ──< trainer_profiles, member_profiles, pt_contracts

pt_contracts (1) ──< sessions ──< session_records (1:1)
                       │
                       └──< bookings (예약 별도 추적)

messages: sender_id ↔ receiver_id (auth.users 양방향)
```

---

## 2. SQL 스키마 (PostgreSQL)

### 2.1 ENUM 타입

```sql
-- 역할
CREATE TYPE user_role AS ENUM ('trainer', 'member', 'admin');

-- 수업 상태
CREATE TYPE session_status AS ENUM (
  'scheduled',  -- 예약됨
  'done',       -- 완료(기록됨)
  'no_show',    -- 노쇼 (회원 미참석)
  'canceled',   -- 정상 취소 (규정 내)
  'late_cancel' -- 당일/지각 취소 (차감 대상)
);

-- 메모 가시성 (확장 대비, 현재는 trainer_only / shared 2종)
CREATE TYPE note_visibility AS ENUM ('trainer_only', 'shared');

-- 재등록 알림 단계
CREATE TYPE renewal_alert_level AS ENUM ('none', 'half', 'five_left', 'expiring');
```

### 2.2 핵심 테이블

#### centers — 헬스장(센터)
```sql
CREATE TABLE centers (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  address    text,
  -- PT 규정(차감, 노쇼 정책 등)을 JSON으로 보관. 센터마다 다름.
  rules      jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
```

#### trainer_profiles
```sql
CREATE TABLE trainer_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  center_id  uuid REFERENCES centers(id),
  name       text NOT NULL,
  phone      text,
  bio        text,
  created_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX idx_trainer_center ON trainer_profiles(center_id);
```

#### member_profiles
```sql
-- 회원 기본 정보 (트레이너/본인이 모두 볼 수 있는 영역)
CREATE TABLE member_profiles (
  user_id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  center_id        uuid REFERENCES centers(id),
  name             text NOT NULL,
  phone            text,
  birth_date       date,
  goal             text,          -- 운동 목적 (예: "체중감량")
  experience       text,          -- 운동 경험
  injury_history   text,          -- 부상 이력
  body_features    text,          -- 체형 특징
  lifestyle        text,          -- 생활 패턴
  available_times  jsonb,         -- [{day:'mon', from:'19:00', to:'21:00'}, ...]
  created_at       timestamptz DEFAULT now(),
  deleted_at       timestamptz
);

CREATE INDEX idx_member_center ON member_profiles(center_id);
```

#### member_notes — 트레이너 전용 메모 (분리 보관)
```sql
-- 회원이 보면 기분 나쁠 내용(성향/재등록 가능성 등)을 별도 테이블로 격리.
-- RLS에서 member 역할은 SELECT 자체를 차단.
CREATE TABLE member_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id   uuid NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
  trainer_id  uuid NOT NULL REFERENCES trainer_profiles(user_id),
  content     text NOT NULL,
  visibility  note_visibility NOT NULL DEFAULT 'trainer_only',
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

CREATE INDEX idx_notes_member ON member_notes(member_id);
CREATE INDEX idx_notes_trainer ON member_notes(trainer_id);
```

#### pt_contracts — PT 계약 (잔여 횟수의 원천)
```sql
CREATE TABLE pt_contracts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES member_profiles(user_id),
  trainer_id      uuid NOT NULL REFERENCES trainer_profiles(user_id),
  center_id       uuid REFERENCES centers(id),
  total_sessions  int  NOT NULL CHECK (total_sessions > 0),
  -- used_sessions는 sessions 테이블에서 status='done' OR 차감 대상 count로 계산.
  -- 캐시용 컬럼은 두지 않는다. (도메인 로직에서 일관성 보장)
  start_date      date NOT NULL,
  end_date        date,                       -- NULL이면 만료일 미정
  price           int,                        -- 원 단위
  memo            text,
  created_at      timestamptz DEFAULT now(),
  deleted_at      timestamptz,
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX idx_contract_member ON pt_contracts(member_id);
CREATE INDEX idx_contract_trainer ON pt_contracts(trainer_id);
```

#### sessions — 수업 1건 (예약·실행·차감 모두 추적)
```sql
CREATE TABLE sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id   uuid NOT NULL REFERENCES pt_contracts(id) ON DELETE RESTRICT,
  scheduled_at  timestamptz NOT NULL,
  status        session_status NOT NULL DEFAULT 'scheduled',
  recorded_at   timestamptz,                  -- 기록 완료 시각
  recorded_by_trainer_id uuid REFERENCES trainer_profiles(user_id),
  -- 차감 여부는 status로 판단:
  --   done, no_show, late_cancel → 차감
  --   scheduled, canceled        → 미차감
  created_at    timestamptz DEFAULT now()
);

CREATE INDEX idx_sessions_contract ON sessions(contract_id);
CREATE INDEX idx_sessions_scheduled ON sessions(scheduled_at);
```

#### session_records — 수업 기록 본문
```sql
-- sessions와 1:1. 분리 이유: 예약만 있고 기록은 없는 경우(예약 후 노쇼) 처리.
CREATE TABLE session_records (
  session_id  uuid PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
  -- 운동 종목/세트/무게/반복: 자유도 위해 JSON.
  -- 예: [{name:"스쿼트", sets:[{weight:60,reps:10},{weight:70,reps:8}]}]
  exercises   jsonb NOT NULL DEFAULT '[]'::jsonb,
  condition   text,         -- 회원 컨디션
  pain        text,         -- 통증 메모
  next_memo   text,         -- 다음 수업 메모
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);
```

#### messages — 채팅 (Phase 2)
```sql
CREATE TABLE messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id   uuid NOT NULL REFERENCES auth.users(id),
  receiver_id uuid NOT NULL REFERENCES auth.users(id),
  content     text NOT NULL,
  sent_at     timestamptz DEFAULT now(),
  read_at     timestamptz,
  CHECK (sender_id <> receiver_id)
);

CREATE INDEX idx_msg_receiver_unread ON messages(receiver_id) WHERE read_at IS NULL;
CREATE INDEX idx_msg_pair ON messages(sender_id, receiver_id, sent_at DESC);
```

#### body_assessments — 체형 분석 (Phase 4 / C3)
```sql
CREATE TABLE body_assessments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES member_profiles(user_id),
  -- 사진은 Supabase Storage에 저장하고 경로만 보관.
  -- 예: {front:"path", side:"path", back:"path"}
  photos          jsonb NOT NULL,
  ai_result       jsonb,         -- 키포인트, 비대칭 각도 등
  trainer_comment text,          -- NULL이면 회원에게 노출 금지 (RLS 조건)
  assessed_at     timestamptz DEFAULT now()
);

CREATE INDEX idx_assess_member ON body_assessments(member_id);
```

---

## 3. RLS (Row Level Security) 정책

> **반드시 전체 테이블에 활성화.** 누락 = 정보 유출.
> `auth.uid()` = 현재 로그인한 사용자 ID, `auth.jwt() ->> 'role'` 같은 커스텀 클레임 활용.

### 3.1 역할 확인 헬퍼 함수

```sql
-- 현재 사용자의 역할 (user_role)
CREATE OR REPLACE FUNCTION current_user_role() RETURNS user_role
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    CASE
      WHEN EXISTS (SELECT 1 FROM trainer_profiles WHERE user_id = auth.uid() AND deleted_at IS NULL)
        THEN 'trainer'::user_role
      WHEN EXISTS (SELECT 1 FROM admin_profiles  WHERE user_id = auth.uid())
        THEN 'admin'::user_role
      WHEN EXISTS (SELECT 1 FROM member_profiles WHERE user_id = auth.uid() AND deleted_at IS NULL)
        THEN 'member'::user_role
    END
$$;

-- 트레이너가 특정 회원의 담당인지 (현재 유효 계약 보유 여부)
CREATE OR REPLACE FUNCTION is_member_of_trainer(p_member_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM pt_contracts
    WHERE member_id  = p_member_id
      AND trainer_id = auth.uid()
      AND deleted_at IS NULL
  )
$$;
```

> `admin_profiles` 테이블은 위 스키마에 미정의 — Phase 3에서 추가합니다. Phase 1까지는 trainer/member만 활성.

### 3.2 정책 적용

#### member_profiles
```sql
ALTER TABLE member_profiles ENABLE ROW LEVEL SECURITY;

-- 본인 조회/수정
CREATE POLICY member_self_rw ON member_profiles
  FOR ALL USING (user_id = auth.uid());

-- 담당 트레이너 조회/수정 (계약 있는 회원만)
CREATE POLICY member_by_trainer ON member_profiles
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(user_id)
  );
```

#### member_notes — 가장 민감
```sql
ALTER TABLE member_notes ENABLE ROW LEVEL SECURITY;

-- 본인이 작성한 메모만 트레이너가 조회/수정 가능.
-- member 역할은 SELECT 정책 자체가 없으므로 0건 반환됨.
CREATE POLICY notes_owner_rw ON member_notes
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND trainer_id = auth.uid()
  );

-- 명시적으로 거부 정책 추가 (이중 안전장치)
CREATE POLICY notes_member_deny ON member_notes
  FOR SELECT TO authenticated
  USING (current_user_role() <> 'member');
```

> **이중 안전장치 이유:** `notes_owner_rw`가 trainer 조건이라 member는 자동 차단되지만,
> 향후 정책 추가 시 실수로 member에게 열어주는 사고를 막기 위해 명시적 거부 정책을 둡니다.

#### pt_contracts
```sql
ALTER TABLE pt_contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY contract_member_read ON pt_contracts
  FOR SELECT USING (member_id = auth.uid());

CREATE POLICY contract_trainer_rw ON pt_contracts
  FOR ALL USING (trainer_id = auth.uid());
```

#### sessions
```sql
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY sessions_member_read ON sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id AND c.member_id = auth.uid()
    )
  );

CREATE POLICY sessions_trainer_rw ON sessions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id AND c.trainer_id = auth.uid()
    )
  );
```

#### session_records
```sql
ALTER TABLE session_records ENABLE ROW LEVEL SECURITY;

-- sessions의 권한을 그대로 상속 (계약 기반)
CREATE POLICY records_member_read ON session_records
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM sessions s
      JOIN pt_contracts c ON c.id = s.contract_id
      WHERE s.id = session_records.session_id AND c.member_id = auth.uid()
    )
  );

CREATE POLICY records_trainer_rw ON session_records
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM sessions s
      JOIN pt_contracts c ON c.id = s.contract_id
      WHERE s.id = session_records.session_id AND c.trainer_id = auth.uid()
    )
  );
```

#### messages
```sql
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 송수신 당사자만
CREATE POLICY msg_participant_rw ON messages
  FOR ALL USING (sender_id = auth.uid() OR receiver_id = auth.uid());
```

#### body_assessments — AI 검수 게이트 (핵심)
```sql
ALTER TABLE body_assessments ENABLE ROW LEVEL SECURITY;

-- 트레이너: 담당 회원의 분석 read/write 가능
CREATE POLICY assess_trainer_rw ON body_assessments
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );

-- 회원: 본인 분석이되, '트레이너 코멘트가 달린 것만' 조회 가능.
-- 이게 핵심: AI가 단독으로 회원에게 결과를 전달하지 못함.
CREATE POLICY assess_member_read_after_review ON body_assessments
  FOR SELECT USING (
    member_id = auth.uid()
    AND trainer_comment IS NOT NULL
    AND length(trim(trainer_comment)) > 0
  );
```

---

## 4. 트리거 / 함수

### 4.1 `updated_at` 자동 갱신
```sql
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_member_notes_touch    BEFORE UPDATE ON member_notes
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_session_records_touch BEFORE UPDATE ON session_records
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
```

### 4.2 잔여 횟수 조회 view (도메인 계산 결과 캐시 X, 항상 실시간)
```sql
-- 계약별 사용/잔여 횟수 view.
-- 도메인 로직(Dart)에서 이 view를 조회하거나 클라이언트가 직접 sessions를 count해도 됨.
-- DB에 계산식을 둔 이유: 관리자 대시보드 SQL과 일관성 유지.
CREATE OR REPLACE VIEW v_contract_status AS
SELECT
  c.id                              AS contract_id,
  c.member_id,
  c.trainer_id,
  c.total_sessions,
  COUNT(s.id) FILTER (WHERE s.status IN ('done', 'no_show', 'late_cancel'))
                                    AS used_sessions,
  c.total_sessions
    - COUNT(s.id) FILTER (WHERE s.status IN ('done', 'no_show', 'late_cancel'))
                                    AS remaining_sessions,
  c.start_date,
  c.end_date
FROM pt_contracts c
LEFT JOIN sessions s ON s.contract_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY c.id;
```

> **주의:** view 자체는 RLS 적용 안 됨. 베이스 테이블(`pt_contracts`, `sessions`)의 RLS가 그대로 작동.

---

## 5. 마이그레이션 파일 구성 제안

```
src/supabase/migrations/
├─ 0001_init_enums.sql              # §2.1 ENUM
├─ 0002_init_centers.sql            # centers
├─ 0003_init_profiles.sql           # trainer_profiles, member_profiles
├─ 0004_init_notes.sql              # member_notes
├─ 0005_init_contracts_sessions.sql # pt_contracts, sessions, session_records
├─ 0006_init_messages.sql           # messages
├─ 0007_init_body_assessments.sql   # body_assessments
├─ 0008_helper_functions.sql        # current_user_role, is_member_of_trainer
├─ 0009_rls_policies.sql            # 모든 RLS 정책
├─ 0010_triggers_views.sql          # updated_at 트리거, v_contract_status
└─ 0011_seed_dev.sql                # 개발용 시드 데이터 (별도 환경에서만 실행)
```

---

## 6. 시드 데이터 (개발용)

```sql
-- 개발 환경 전용. 운영에서는 절대 실행 X.
INSERT INTO centers (id, name, address) VALUES
  ('00000000-0000-0000-0000-000000000001', '강남 테스트 센터', '서울 강남구 ...');

-- trainer/member는 Supabase Auth로 가입 후
-- 해당 user_id로 profiles 행 INSERT 하는 흐름.
-- 이는 Phase 0의 시드 스크립트(0011)에서 환경변수 기반으로 처리.
```

---

## 7. 단위 테스트 시나리오 (RLS 통합 테스트)

> 도메인 단위 테스트(`renewal_calculator_test.dart` 등)와 별개로,
> **RLS 자체를 검증하는 통합 테스트**가 반드시 필요합니다. develop_plan §5.1, §6 참조.

| # | 시나리오 | 기대 |
|---|---------|------|
| RLS-1 | 회원 A로 로그인 → `SELECT * FROM member_notes WHERE member_id = A.id` | 0건 |
| RLS-2 | 트레이너 T1로 로그인 → T2가 작성한 메모 조회 | 0건 |
| RLS-3 | 회원 B로 로그인 → 본인이 아닌 회원 C의 `member_profiles` 조회 | 0건 |
| RLS-4 | 회원 D로 로그인 → 본인의 `body_assessments` 중 `trainer_comment IS NULL`인 것 조회 | 0건 |
| RLS-5 | 회원 D로 로그인 → 본인의 `body_assessments` 중 `trainer_comment` 채워진 것 조회 | 1건 이상 |
| RLS-6 | 트레이너 T1로 로그인 → 담당 아닌 회원의 `pt_contracts` 수정 | 권한 오류 |
| RLS-7 | 회원 E로 로그인 → 본인 계약의 `sessions` 조회 | 정상 |
| RLS-8 | 회원 E로 로그인 → 본인 계약의 `sessions` UPDATE | 권한 오류 (트레이너만 수정) |

> 위 테스트는 **Phase 0 종료 전 통과 필수**. 누락 시 Phase 1 진행 금지.

---

## 8. 미정 / 후속 결정 사항

| 항목 | 결정 시점 | 메모 |
|------|----------|------|
| `admin_profiles` 스키마 + 관리자 RLS | Phase 3 시작 시 | 현재는 trainer/member만 |
| 채팅 알림 시간대 설정 (S2) | Phase 2 | `messages`에 컬럼 추가 또는 별도 `notification_prefs` 테이블 |
| FAQ 운영 (S3) | Phase 2 | DB에 `faqs` 테이블 또는 Notion/외부 CMS 연동 |
| 카카오 알림톡 연동 | Phase 1 후반 | FCM 전달률 측정 후 결정 |
| 사진 보관 기간 정책 | Phase 4 시작 전 | 법무/약관 검토 필요 |
| 계약 만료 자동 처리 (cron) | Phase 1 | Supabase Edge Function + pg_cron |

---

## 9. 잠재 리스크 알림 (파트너 관점)

1. **`v_contract_status` view 의존 시 인덱스 확인 필수.** 회원/계약이 늘면 `LEFT JOIN sessions + GROUP BY`가 느려질 수 있음. `(contract_id, status)` 복합 인덱스 추가 검토.
2. **session_records의 `exercises` JSON 스키마는 초기에 강하게 검증 안 하면 데이터 더러워짐.** Phase 1에서 클라이언트 검증 + 향후 `CHECK (jsonb_typeof(exercises) = 'array')` 추가 권장.
3. **`is_member_of_trainer`가 RLS 정책마다 호출되면 부하 발생 가능.** Supabase의 `STABLE` 함수는 같은 쿼리 내 캐싱되긴 하지만, 회원 수 1000+ 시 EXPLAIN으로 재확인.
4. **soft delete를 RLS에 반영 안 하면 삭제된 트레이너가 여전히 회원 정보를 보는 사고 가능.** `current_user_role()`에서 `deleted_at IS NULL` 체크는 했지만, 정책 전체 재확인 필요.
5. **메시지 RLS는 매우 단순하지만 단체 채팅으로 확장 시 재설계 필요.** 현재는 1:1만.

---

## 10. 다음 단계

- [ ] 본 문서 검토 → 수정 의견 반영
- [ ] `src/supabase/migrations/0001_init_enums.sql` ~ `0010_triggers_views.sql` 실제 작성
- [ ] Supabase 프로젝트에 마이그레이션 적용
- [ ] RLS 통합 테스트 8개 시나리오 작성 및 통과
- [ ] 통과 후 → `docs/develop_plan.md`의 Phase 0 체크리스트 갱신
- [ ] Phase 1 착수 (수업 기록 화면)
