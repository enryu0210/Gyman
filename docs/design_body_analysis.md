# AI 체형 분석 설계 (Body Analysis / C3)

> 상태: **설계 초안 (미구현)** · 작성일 2026-05-30 (최종 갱신 2026-07-25 — 우선순위 상향)
> 출처/상위: `docs/develop_plan.md` Phase 4 (4.1 카메라 가이드 / 4.2 체형 분석 / 4.3 검수 플로우). 결정 변경 시 develop_plan 먼저 갱신.
> **🔺 우선순위 상향(2026-07-24 트레이너 피드백):** "개인화된 신체·습관 피드백" 요구의 *신체* 축이 본 기능이고, 동시에 **CV 트랙의 관문**이다 — 고스트 오버레이(4.7)·영상 트래킹(4.6)이 `google_mlkit_pose_detection`·`camera` 를 본 트랙과 공유하므로, 여기를 세우면 나머지 둘의 한계비용이 급감한다. 착수 순서는 develop_plan §4 "CV·개인화 트랙 실행 순서" 참조.
> 연계 문서: `docs/design_ghost_overlay.md`(4.7 — `camera` 공유), `docs/design_class_video_tracking.md`(4.6 — ML Kit 공유), `docs/design_movement_coaching.md`(4.8 — 본 기능의 `metrics` 가 **제약 등록(L1)의 근거 자료**로 트레이너에게 제시된다. 단 수치가 제약을 *판정*하지는 않는다 — 판정 주체는 트레이너/의료기관).
> 핵심 결정(확정): **분석은 100% 온디바이스**(ML Kit Pose). 신체 사진은 분석을 위해 외부로 **전송하지 않는다**. LLM 미사용.
> 안전 원칙(재사용): AI 결과는 **트레이너가 코멘트를 단 뒤에만** 회원에게 노출 (B/C 검수 게이트와 동일).

---

## 0. 목적과 범위

### 0.1 무엇을 푸는가
트레이너가 회원의 **체형 사진(정면/측면/후면)**을 촬영하면, **기기 안에서** 자세 키포인트를 뽑아 좌우 비대칭·기울기 같은 **참고 수치**를 계산하고, 그 위에 트레이너가 코멘트를 달아 회원에게 보여준다.
- 회원 가치: "어깨 높이 좌우 차이 3도" 같은 수치 + 4·8·12주 비교로 변화 체감 → 재등록 동기 (변화 추이 S1과 같은 결).
- 트레이너 가치: 눈대중으로 보던 체형 평가를 수치·사진으로 객관화. 수업 외 가치 제공.

### 0.2 베타 범위 (스코프 가드)
- **온디바이스 분석만**: 키포인트 추출·각도 계산은 전부 기기에서. 사진은 트레이너 검토용으로 **비공개 버킷에 저장**(동의 시)하되, 분석 목적의 외부 전송은 0.
- **트레이너가 촬영·등록**, 회원은 **열람만**(회원 셀프 촬영은 후순위).
- 결과는 **"참고 수치(screening)"**로만 표현. **진단·단정 금지**("라운드숄더입니다" ✗ → "어깨 전방 기울기 X도, 트레이너 확인 필요" ○).
- 측정 부위(베타): **좌우 어깨 높이차 / 좌우 골반 높이차** 우선. (정면·후면 2D로 가장 신뢰도 높은 항목)

### 0.3 비범위 (후순위/별트랙)
- **측면 자세(거북목·굽은등) 정밀 측정**: 2D 단일 사진 키포인트로는 신뢰도 한계 → 보조 표시만, 단정 금지. 정밀화는 별트랙.
- **식단 분석(C4, 멀티모달 LLM)** / **자세 영상 분석(4.5)**: 본 설계 밖.
- LLM 기반 코멘트 문장 자동생성: 이번 결정에서 **제외**(온디바이스 전용). 회원/트레이너용 문구는 **수치 → 규칙기반 템플릿**으로 생성, 최종 표현은 트레이너가.
- 회원 셀프 촬영, 좌우 대칭 자동 보정, 3D 스캔.

---

## 1. 분석 엔진 결정 — 온디바이스 (확정)

### 1.1 왜 온디바이스인가
| 기준 | 온디바이스(채택) | 클라우드 멀티모달 LLM(미채택) |
|---|---|---|
| 민감 신체사진 외부전송 | **없음** | 있음 — 본 제품 프라이버시 우선 설계와 충돌 |
| 비용 | **0**(호출당 과금 없음) | 호출당 과금 + 사진 토큰 비쌈 |
| 오프라인 | **가능** | 불가 |
| 환각 | 없음(기하 계산) | 있음(없는 비대칭 지어냄) |
| 정확도 | 2D 키포인트 한계(아래 §1.3) | 일관성 낮음·검증 어려움 |

→ **프라이버시·비용·검증가능성**에서 온디바이스가 명확히 우세. develop_plan 4.2의 "MediaPipe Pose 키포인트" 방향과도 일치.

### 1.2 라이브러리
- **`google_mlkit_pose_detection`** — Google ML Kit의 온디바이스 Pose Detection(내부적으로 MediaPipe 계열). Flutter 공식 MediaPipe 플러그인은 없으므로 이게 현실적 경로. 정지 사진(`InputImage.fromFile`)에 대해 33개 랜드마크 반환.
- 카메라 가이드(라이브 프리뷰 + 그리드/수평 오버레이)는 **`camera`** 패키지 + `CustomPainter`(변화추이 차트와 같은 무의존 그리기 방식).
- ⚠ 둘 다 **네이티브 플러그인 증가** → develop_plan §0 의존성 표 갱신 + 빌드 영향 점검 필수(아래 §6).

### 1.3 정확도 한계 (정직하게 — 게이트 설계의 근거)
- 2D 단일 사진 키포인트는 **카메라 거리·각도·옷·자세 흔들림**에 민감. 절대 진단 도구가 아니다.
- 그래서 **좌우 비교(어깨/골반 높이차)** 같은 *상대* 지표를 우선한다(전역 오차가 상쇄됨).
- 측면 깊이(거북목 전방이동량)는 2D로 부정확 → 베타에선 보조 표시·단정 금지.
- **결론:** 수치는 "트레이너가 눈으로 확인할 출발점"이지 결과가 아니다 → **trainer_comment 게이트가 안전장치로 필수**(§3.1).

---

## 2. 데이터 모델

### 2.1 `body_assessments` 개편 (스키마 빚 정리 포함)
현재 `0008`의 `body_assessments`는 **`member_id`가 `member_profiles(user_id)`를 참조** — 0013에서 PK가 `id`로 바뀐 뒤의 규칙(회원 FK는 모두 `id`, 회원 RLS는 `current_member_profile_id()` 경유)과 어긋난다. 그대로 켜면 **앱 미연결 회원(user_id NULL)은 분석 불가** + 식별자 정책 붕괴.

→ 신규 마이그레이션에서 **FK를 `id`로 이전**한다(CLAUDE.md "참조 FK 모두 DROP → PK 교체 → FK 재추가" 순서 원칙; 여기선 PK 교체가 아니라 FK 대상 컬럼 재지정이라 참조 무결성만 점검).

```
body_assessments (
  id              uuid PK default gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES member_profiles(id) ON DELETE CASCADE,  -- ★ user_id → id
  photos          jsonb NOT NULL,        -- { "front":"path", "side":"path", "back":"path" } (object key)
  ai_result       jsonb,                 -- 아래 §2.3 구조(키포인트·각도·플래그·provenance)
  trainer_comment text,                  -- NULL/빈값이면 회원 노출 금지 (RLS 게이트)
  assessed_at     timestamptz NOT NULL DEFAULT now(),
  recorded_by     uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL  -- 촬영·등록 트레이너(audit)
);
CREATE INDEX idx_assess_member ON body_assessments(member_id, assessed_at DESC);
```

식별자 정책(0013 이후): `member_id`는 **member_profiles.id** 참조. `body_measurements`(0023)와 동일 패턴 — 그 카드 UI를 그대로 본떠 co-locate.

### 2.2 Storage 버킷 `body-photos`
- 버킷명 `body-photos`, **비공개(public=false)**. 채팅 이미지(0026 `chat-images`)와 같은 구조이되 **권한은 더 좁다**(채팅 상대 개념 없음 — 본인 + 담당 트레이너만).
- object key 규칙(ASCII 고정 — 한글 금지): `"{member_id}/{assessment_id}/{front|side|back}.jpg"`
  - 첫 세그먼트 = member_id → Storage RLS에서 `(storage.foldername(name))[1]`로 소유 회원 판별.
- 파일 크기 상한 예: **5MB**, 허용 MIME `image/jpeg`. 업로드 전 1600px·품질80% 압축(0026 채팅 패턴 재사용).

### 2.3 `ai_result` JSON 구조 (제안)
온디바이스 산출물 + audit 정보를 함께. LLM이 없으므로 **추적가능성은 엔진 버전으로** 확보(develop_plan "AI 생성 콘텐츠 audit log" 충족).
```jsonc
{
  "engine": "mlkit_pose",           // 엔진 식별
  "engine_version": "x.y.z",        // 패키지 버전 — 사후 재현/분쟁 대응
  "captured_at": "2026-..Z",
  "views": {                         // 뷰별 키포인트(정규화 좌표) + 신뢰도
    "front": { "landmarks": [...], "in_frame_likelihood": 0.97 }
  },
  "metrics": [                       // 규칙기반 파생 수치(회원 표시 후보)
    { "key": "shoulder_tilt_deg", "value": 3.1, "ref": "±2", "flag": "watch" },
    { "key": "pelvis_tilt_deg",   "value": 1.2, "ref": "±2", "flag": "ok" }
  ]
}
```
- `metrics`만 트레이너 화면/회원 화면에 노출(키포인트 원시값은 내부용).
- 코멘트 템플릿 문구는 `metrics`에서 규칙기반으로 생성(예: `shoulder_tilt_deg > 2 → "어깨 높이 좌우 차이 {value}도 — 확인 권장"`).

---

## 3. RLS / 보안

### 3.1 `body_assessments` 테이블 (개편 — 신규 마이그레이션)
`0010`의 기존 정책은 `member_id = auth.uid()`(잘못된 식별자) → **재작성**한다.
- 트레이너 ALL: `current_user_role()='trainer' AND is_member_of_trainer(member_id)` (member_id가 이제 .id라 헬퍼 시그니처 점검).
- 회원 SELECT(게이트 유지): `member_id = current_member_profile_id() AND trainer_comment IS NOT NULL AND length(trim(trainer_comment)) > 0`.
  - **AI/수치 단독으로는 회원에게 안 보임** — 트레이너 코멘트가 채워져야만 노출. 이 한 줄이 §1.3 정확도 한계를 덮는 안전장치.

> ⚠ `0010`은 이미 적용된 파일이라 **수정 금지** — 신규 번호 마이그레이션에서 `DROP POLICY IF EXISTS … CREATE POLICY`로 덮어쓴다(멱등).

### 3.2 `storage.objects` 정책 (버킷 `body-photos`)
폴더 첫 세그먼트(member_id)를 권한 키로. **채팅(0026)과 달리 `are_chat_peers` 미사용** — 신체사진은 더 민감하므로 본인+담당트레이너로 한정.
- 회원 SELECT: `bucket_id='body-photos' AND (storage.foldername(name))[1] = current_member_profile_id()::text`
- 트레이너 ALL: `bucket_id='body-photos' AND is_member_of_trainer( ((storage.foldername(name))[1])::uuid )`
- 캐스팅/`storage.foldername` 사용은 적용 후 검증 SQL 필수(0026 교훈).

### 3.3 표시 = 서명 URL
- 비공개 버킷 → 항상 `createSignedUrl(path, ttl)` 단기 발급(예: 1시간). 영구 public URL 금지. (0026 채팅 이미지와 동일 메커니즘 재사용)

### 3.4 프라이버시/동의 (필수 선행 — ai_consent와 별개)
- 신체사진 = **민감 개인정보(건강정보 인접)**. 기존 `member_profiles.ai_consent`(외부 LLM 전송 동의)와 **법적 성격이 다르다**:
  - 본 기능은 외부 전송이 없으므로 *LLM 동의*는 불필요하나, **사진 촬영·저장·보관기간**에 대한 **별도 동의**가 필요.
  - → `member_profiles.body_photo_consent boolean`(신규) 또는 동의 이력 테이블. 동의 없으면 **촬영·저장 차단**(트레이너 측 게이트).
- 회원 탈퇴/삭제 시 사진도 삭제(`ON DELETE CASCADE` + Storage 객체 정리 잡). 보관기간 정책 명시(develop_plan 체크리스트 "AI 분석 결과 보관 기간").

---

## 4. 촬영·분석 플로우 (트레이너)
1. 회원 상세 → "체형 분석" 카드 → 촬영 시작(동의 확인 — 미동의면 차단).
2. **카메라 가이드(4.1)**: `camera` 프리뷰 위 `CustomPainter`로 그리드·수평선·발 위치·거리 안내. 정면/측면/후면 순차 촬영.
3. **온디바이스 분석**: 촬영된 정지 사진마다 `google_mlkit_pose_detection` 실행 → 랜드마크 → 각도 계산(좌우 어깨/골반 등) → `ai_result.metrics` 생성. **사진은 기기 밖으로 안 나감.**
4. (동의 시) 사진을 `body-photos/{member_id}/{assessment_id}/...`에 업로드(압축).
5. **메타 INSERT** `body_assessments`(photos 경로·ai_result·recorded_by). `trainer_comment`는 **비워 둠 → 회원 미노출 상태로 시작**.
6. **보상 트랜잭션**(CLAUDE.md): 5단계(INSERT) 실패 시 4단계 업로드 객체 hard delete(고아 파일 방지). 멀티 사진이면 업로드한 것 전부 정리.

> 분석(3)과 저장(4)은 분리 가능 — 동의 안 한 회원도 "사진 저장 없이 수치만" 받는 모드 검토(§8).

## 5. 검수·열람 플로우
1. 트레이너가 `ai_result.metrics` + 사진을 보고 **trainer_comment 작성** → 저장 순간 회원에게 노출(RLS 게이트 통과). (메시지/메모 검수와 동일 UX 결)
2. 회원 `/member/body`(develop_plan §3.2): 코멘트 달린 분석만 목록·상세. 수치 카드 + (동의 시)사진 + 트레이너 코멘트.
3. **비교 뷰**(4.2): 같은 회원의 과거 분석과 4·8·12주 나란히 — 수치 추이(변화추이 차트 재사용)·사진 전후.

라우트(초안): 트레이너 `features/trainer/member_card/body_analysis_*`(카드/촬영/검수), 회원 `features/member/body/`(목록·상세·비교).

---

## 6. 앱 구조 / 의존성

### 6.1 파일 배치(예정, co-locate)
- `features/trainer/member_card/body_analysis_{repository,providers,card,capture_screen,review_dialog}.dart`
- `features/member/body/{repository,providers,screen,compare_screen}.dart`
- `domain/models/body_assessment.dart`(순수 Dart, fromRow + 경로 규칙)
- `domain/posture_metrics.dart`(키포인트 → 각도 계산 — **순수 함수, 단위테스트 필수**. develop_plan §5.1 도메인 테스트 원칙)

### 6.2 새 의존성 (★ develop_plan §0 표 갱신 필요)
| 패키지 | 용도 | 비고 |
|---|---|---|
| `google_mlkit_pose_detection` | 온디바이스 키포인트 | 네이티브 모델 번들 → **APK 크기↑**, Android minSdk·iOS 설정 점검 |
| `camera` | 라이브 프리뷰 + 가이드 오버레이 | 카메라 권한(AndroidManifest/Info.plist) 문구 필요 |
| (`image_picker` 재사용) | 사진 압축 경로 | 0026에서 이미 도입 — 가능하면 재사용 |

> 의존성은 보수적 고정 영역(§0) → **추가 전 빌드 영향 점검(한글 경로 무관하나 네이티브 플러그인·모델 번들 증가) + §0 표 갱신** 필수. ML Kit는 빌드 무게가 있어 도입 시 `flutter build apk` 시간·크기 측정.

---

## 7. 단계적 구현 계획 (제안)
- **A. 기반(스키마/스토리지/도메인)**: 신규 마이그레이션(body_assessments FK 이전 + RLS 재작성 + `body-photos` 버킷·정책 + body_photo_consent) → `posture_metrics` 순수 도메인 + 단위테스트. *UI/카메라 없이 백엔드+계산부터.* **← 신규 의존성 0이라 베타 검증·배포와 병행 가능한 구간**(develop_plan §4 실행순서 2단계).
- **B. 분석·등록**: ML Kit 연동(정지사진 키포인트) → 각도 계산 → `ai_result` 생성 → (동의 시)사진 업로드 + 메타 INSERT(보상 삭제). 카메라 가이드는 최소(그리드만).
- **C. 검수·열람·비교**: 트레이너 검수(코멘트→노출), 회원 목록·상세, 4·8·12주 비교 뷰.
- **D. 가이드 UI 고도화(4.1)**: 수평/거리/발위치 오버레이 정교화.

각 단계 끝: analyze/test/build 통과 + develop_plan 갱신(프로젝트 규칙).

---

## 8. 미해결 결정 (구현 전 확정 필요)
1. **누가 촬영하나**: 베타=트레이너 촬영(채택안). 회원 셀프 촬영은 동의·자세품질·악용 부담 → 후순위.
2. **사진 저장 vs 수치만**: 동의 안 한 회원에게 "사진 저장 없이 온디바이스 수치만" 제공할지. (분석은 외부전송 0이라 기술적으론 가능 — 트레이너 검토용 사진이 없으면 코멘트 품질↓ 트레이드오프)
3. **측정 항목 범위**: 베타는 좌우 어깨/골반 높이차만? 측면(거북목)·무릎(내반/외반) 추가 시점은? (§1.3 신뢰도 따라)
4. **보관 정책**: 무기한 vs N개월 자동삭제 + 정리 잡. (저장비·민감도 방어)
5. **동의 모델**: `body_photo_consent` 단일 플래그 vs 동의 이력 테이블(시점·버전 추적). Phase 3.5 약관과 연계.
6. **비교 기준선**: "첫 등록"을 baseline 고정 vs 직전 분석 대비. 4·8·12주 자동 매칭 규칙.

---

## 9. 리스크 요약
| 리스크 | 영향 | 대응 |
|---|---|---|
| 2D 키포인트 정확도 한계 | 오판·과신 | "참고 수치" 표현 강제 + **trainer_comment 게이트**(단정 차단) + 좌우 상대지표 우선 |
| 신체사진 PII 유출 | 신뢰·법적 | 비공개 버킷 + 본인/담당트레이너 한정 RLS + 단기 서명URL + 별도 동의 + 외부전송 0 |
| 스키마 빚(0008 FK user_id) 미정리 | 미연결 회원 분석 불가·정책 붕괴 | A단계에서 FK→id 이전 + RLS 재작성 선행 |
| ML Kit 빌드 무게(APK 크기·시간) | 빌드 취약·배포 | 도입 전 build 측정 + §0 갱신, minSdk/iOS 설정 점검 |
| 고아 사진(메타 없는 객체) | 저장 누수 | 업로드→메타 보상 삭제 + 주기적 정리 잡 |
| 카메라 자세·거리 편차 | 수치 흔들림 | 촬영 가이드(4.1) + 동일 조건 재촬영 안내 + 좌우 상대지표 |
