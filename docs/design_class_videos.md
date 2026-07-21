# 수업 영상 보관·열람 설계 (Class Videos)

> 상태: **A단계(MVP) 완료 + B-1(수업 연결)·B-2(보관 개수 상한) 완료** · 작성일 2026-05-30 · 갱신 2026-06-01
> 구현 범위: 마이그레이션 0027(`class_videos`+버킷+RLS), 트레이너 업로드(촬영/갤러리·검증·보상 트랜잭션), 회원 열람·재생(서명URL+`video_player`). 의존성 `video_player` 추가(develop_plan §0). analyze/test(141)/build(apk debug) 통과.
> 출처/상위: `docs/develop_plan.md` (Phase 2~4 후보, S 시리즈). 결정 변경 시 develop_plan 먼저 갱신.
> 사전 검토 결론: Supabase Storage 로 **기술적 감당 가능**. 단 "짧은 클립 + Pro + RLS/서명URL + 압축"이 전제.
> 비용 핵심: **저장보다 전송량(egress)**, 그리고 **트랜스코딩 부재**가 함정.

---

## 0. 목적과 범위

### 0.1 무엇을 푸는가
트레이너가 **수업 영상(주로 자세/폼 체크 짧은 클립)**을 올려두면, 해당 **회원만** 앱에서 다시 볼 수 있게 한다.
- 회원 가치: 내 자세를 복기 → 재등록 동기/신뢰 ↑ (변화 추이 그래프 S1과 같은 결).
- 트레이너 가치: 말로 설명하던 교정 포인트를 영상으로 → 수업 외 가치 제공.

### 0.2 베타 범위 (스코프 가드 — 비용/UX 직결)
- **짧은 클립만**: 길이 상한 **120초**(권장 30~90초). 풀세션 30~60분 통영상은 **금지**(저장·전송 폭발).
- **세로/가로 1080p 이하**. 4K 금지(분당 350MB+).
- 트레이너가 **업로드**, 회원은 **열람만**(회원 셀프 업로드는 후순위).
- 1:1 노출(회원 본인 + 담당 트레이너). 공개/공유 링크 없음.

### 0.3 비범위 (후순위/별트랙)
- 트랜스코딩·적응형 스트리밍(HLS)·자동 화질조절 → Supabase 미지원. 필요해지면 **Cloudflare Stream/Mux 이전**(§8).
- AI 자세 분석(C3, MediaPipe)은 별개 트랙(Phase 4) — 본 설계는 "보관·열람"만.
- **객체 트래킹·자동 프레이밍(손떨림 완화)은 별개 트랙(Phase 4.6)** — 온디바이스로 인물 위치만 뽑아 재생 시점 팬/줌(비파괴). 상세: `docs/design_class_video_tracking.md`.
- 댓글/타임스탬프 주석 등은 후속.

---

## 1. 비용·한도 근거 (2026-05 확인)

| 항목 | Free | Pro($25/월) |
|---|---|---|
| 총 저장 | 1 GB | 100 GB 포함, +$0.0213/GB |
| 파일 1개 최대 | 50 MB | 최대 500 GB(대용량은 resumable 업로드) |
| Egress 비캐시 | 5 GB | 250 GB 포함, +$0.09/GB |
| Egress 캐시(CDN) | 5 GB | 250 GB 포함, +$0.03/GB |

- **Free 불가**(50MB 파일 한도 + 1GB 총량). **Pro 필수.**
- 폰 1080p ≈ 분당 80~130MB → 2분 클립 ≈ 150~250MB.
- 베타 시뮬(30명·인당 월 8영상·인당 월 10회 시청, 영상 150MB): 저장 ~36GB/월 누적, 전송 ~45GB/월 → **Pro 포함량 내, 추가비 ~0**.
- 가드 깨지면(풀세션 업로드) GB 단위로 폭증 → §0.2 상한이 비용 방어선.

---

## 2. 데이터 모델

### 2.1 메타데이터 테이블 `class_videos`
영상 실파일은 Storage, **DB엔 경로/메타만** (기존 `body_assessments` 사진 패턴과 동일).

```
class_videos (
  id            uuid PK default gen_random_uuid(),
  member_id     uuid NOT NULL REFERENCES member_profiles(id) ON DELETE CASCADE,
  session_id    uuid REFERENCES sessions(id) ON DELETE SET NULL,  -- 특정 수업과 연결(선택)
  storage_path  text NOT NULL,        -- 비공개 버킷 내 object key (ASCII)
  title         text,                 -- "스쿼트 폼 체크" 등
  duration_sec  int,                  -- 길이(초) — 상한 검증·표시
  size_bytes    bigint,               -- 용량 — 모니터링/정리
  uploaded_by   uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_class_videos_member ON class_videos(member_id, created_at DESC);
```

식별자 정책(0013 이후): `member_id`는 **member_profiles.id** 참조. 회원 RLS는 `current_member_profile_id()` 경유.

### 2.2 Storage 버킷
- 버킷명 `class-videos`, **비공개(public=false)**.
- object key 규칙(ASCII 고정 — 한글 금지): `"{member_id}/{video_id}.mp4"`
  - 첫 세그먼트 = member_id(폴더) → Storage RLS에서 `(storage.foldername(name))[1]`로 소유 회원 판별.
- 버킷 파일 크기 상한을 **예: 250MB**로 설정(§0.2와 일치). 허용 MIME `video/mp4`(필요시 mov 추가).

---

## 3. RLS / 보안

### 3.1 `class_videos` 테이블 (마이그레이션 0026 예정)
- 트레이너 rw: `current_user_role()='trainer' AND is_member_of_trainer(member_id)` (FOR ALL).
- 회원 read: `member_id = current_member_profile_id()` (FOR SELECT). 검수 게이트 없음 — 영상은 트레이너가 의도적으로 올린 자료.

### 3.2 `storage.objects` 정책 (버킷 `class-videos`)
폴더 첫 세그먼트(member_id)를 권한 키로 사용.
- 회원 SELECT: `bucket_id='class-videos' AND (storage.foldername(name))[1] = current_member_profile_id()::text`
- 트레이너 ALL: `bucket_id='class-videos' AND is_member_of_trainer( ((storage.foldername(name))[1])::uuid )`
- ※ 정책 SQL은 `storage.objects`에 직접 건다(대시보드 또는 마이그레이션). 캐스팅/`storage.foldername` 사용은 적용 후 검증 SQL 필수.

### 3.3 재생 = 서명 URL(Signed URL)
- 버킷 비공개 → 재생 시 `createSignedUrl(path, expiresIn)` 로 **단기 서명 URL**(예: 1시간) 발급해 player에 전달. 영구 public URL 금지.
- 서명 URL도 발급 시점에 RLS를 통과해야 하므로(요청자 JWT) 무단 발급 차단.

### 3.4 프라이버시/동의 (필수 선행)
- 회원 영상 = 민감 개인정보 → **촬영·보관 동의** + 개인정보처리방침(이미 Phase 3.5 예정)에 영상 보관/보존기간 명시.
- 동의 없으면 업로드 차단(트레이너 측 게이트). 회원 탈퇴/삭제 시 영상도 함께 삭제(ON DELETE CASCADE + Storage 객체 정리 잡).

---

## 4. 업로드 플로우 (트레이너)

1. 영상 선택/촬영 — `image_picker`(video) 또는 `file_picker`.
2. **클라 검증**: 길이 ≤ 120초, 크기 ≤ 250MB, MIME=video/mp4. 초과 시 안내 후 차단.
3. (권장) **압축** — 기기에서 1080p/적정 비트레이트로 다운스케일(예: `video_compress`). 업로드·저장·전송 모두 절감.
4. **resumable 업로드**(대용량/모바일 네트워크 대비) → `class-videos/{member_id}/{video_id}.mp4`.
5. **메타 INSERT** `class_videos`(경로·길이·용량·uploaded_by).
6. **보상 트랜잭션**(CLAUDE.md 패턴): 5단계 실패 시 업로드된 Storage 객체 hard delete(고아 파일 방지). Supabase Dart는 멀티테이블 트랜잭션 미지원이라 동일 원칙 적용.

> ⚠ 의존성 추가 필요(아래 §6) — develop_plan §0 의존성 표 먼저 갱신해야 함.

---

## 5. 재생 플로우 (회원)

1. `/member/videos`(신규) 또는 변화추이/기록 화면 내 "내 영상" 진입.
2. `class_videos` 본인 행 목록(최신순) — 제목/길이/날짜 + 썸네일(후속).
3. 탭 → `createSignedUrl`로 단기 URL 발급 → `video_player`로 인라인 재생.
4. 셀룰러 경고/다운로드 양해 문구(원본 직배라 데이터 사용량 큼).

라우트(초안): `/member/videos`(목록), `/member/videos/:id`(재생) 또는 목록 내 바텀시트 재생.
트레이너 진입: 회원 상세에 "수업 영상" 카드(업로드/목록/삭제) — `body_measurements` 카드와 동일 패턴.

---

## 6. 앱 구조 / 의존성

### 6.1 파일 배치(예정, co-locate 패턴)
- `features/trainer/member_card/class_video_*`(repository/providers/card/upload dialog) — 회원 상세에 카드.
- `features/member/videos/`(repository/providers/screen) — 회원 목록·재생.
- 공용 모델: `domain/models/class_video.dart`(순수 Dart, fromRow/경로 규칙).

### 6.2 새 의존성 (★ develop_plan §0 표 갱신 필요)
| 패키지 | 용도 | 비고 |
|---|---|---|
| `video_player` | 재생 | 공식. iOS/Android 플랫폼 코드 포함 |
| `image_picker` 또는 `file_picker` | 영상 선택/촬영 | 권한 처리 동반 |
| `video_compress` (선택) | 기기 압축 | 무겁고 플랫폼 의존 — 도입 전 빌드 영향 점검 |
| resumable 업로드 | 대용량 안정 업로드 | supabase_flutter의 resumable 지원 여부 **검증 필요**; 없으면 `tus_client` 검토 |

> 의존성은 본 제품이 보수적으로 고정(§0)해 둔 영역 → **추가 전 빌드(특히 Android Gradle/한글경로 무관하지만 플러그인 증가) 영향 확인 + §0 표 갱신** 필수.

---

## 7. 단계적 구현 계획 (제안)

- **A. 최소 동작(MVP)** — ✅ **구현 완료(2026-05-30)**: 0027 마이그레이션(테이블+버킷+RLS) → 트레이너 업로드(촬영/갤러리 선택·길이120초/용량250MB 검증·메타·보상삭제) → 회원 목록·서명URL 재생(`video_player`). 압축/썸네일 없이 원본. 길이는 업로드 전 `VideoPlayerController` 로 실측해 상한 강제.
  - 파일: `domain/models/class_video.dart`, `features/trainer/member_card/class_video_{repository,providers,card}.dart` + `upload_class_video_dialog.dart`, `features/member/videos/{repository,providers,screen}.dart`, 공용 재생기 `features/videos/class_video_player.dart`. 라우트 `/member/videos`.
- **B. 품질·비용**: 기기 압축, 썸네일(첫 프레임) 생성·저장, 수업(session) 연결, 회원당 보관 개수/기간 정책.
  - **B-1. 수업(session) 연결 — ✅ 구현 완료(2026-06-01).** 의존성·마이그레이션 추가 없이(`session_id` 는 0027에 이미 존재) 기존 인프라만 재사용:
    - 업로드 다이얼로그에 "연결할 수업(선택)" 드롭다운(`recentSessionsForMemberProvider` — 신청(requested) 제외). 선택 안 하면 회원 단위로만 보관.
    - 조회 select 에 `sessions(scheduled_at, status)` embed → `ClassVideo.sessionScheduledAt`(파생 필드). 트레이너 카드·회원 화면 타일에 "🔗 YYYY-MM-DD 수업" 라인 공용 위젯(`features/videos/class_video_session_link.dart`)으로 표시.
    - 회원 측 embed 는 `sessions_member_read`(0010/0013, 본인 계약 수업 노출) 통과. RLS 로 못 읽으면 라벨만 생략(`sessionScheduledAt=null`) — 크래시 없음. 단위테스트(`class_video_test.dart`)로 embed Map/List/null·미동봉 케이스 검증.
  - **B-2. 보관 개수 상한 — ✅ 구현 완료(2026-06-01).** 회원당 보관 개수 상한(`_maxVideosPerMember`=20, `class_videos_card.dart`). **차단 방식**(자동삭제 X): 한도 도달 시 업로드 버튼 비활성 + 안내문, 트레이너가 직접 오래된 영상을 지운 뒤 재업로드. 카드 제목에 `N/상한` 표시. 의존성·마이그레이션 추가 0. 비용 감각: Pro 100GB / 영상 ~150MB → 회원수×상한×0.15GB 가 저장 상한(상수로 튜닝).
    - 자동삭제 대신 차단을 택한 이유: 회원 영상은 되돌릴 수 없어 조용한 삭제가 위험(§3.4/§10 안전 원칙). 서버측 강제(트리거)는 향후 하드닝 — 베타는 단일 트레이너라 앱측 차단으로 충분.
  - **B-기간(나이 기반 자동삭제) — ⬜ 보류(별트랙).** pg_cron 으로 `class_videos` 행만 지우면 **Storage 실파일이 고아로 남아 비용이 오히려 늘어남**(§10 리스크). 제대로 하려면 cron + Storage 객체 정리 Edge Function 이 함께 와야 함 → 보관기간 약관(Phase 3.5)과 묶어 별도 진행. 그 전까지는 B-2 개수 상한이 저장비 방어선.
  - **B-3~. 남은 항목:** 기기 압축(`video_compress` — §6.2 무거운 네이티브 플러그인, §0 의존성 표 갱신+빌드검증 선행), 썸네일(`video_thumbnail` + 컬럼·스토리지).
- **C. 스케일(별트랙)**: 사용량/비용 임계 도달 시 **Cloudflare Stream/Mux 이전**(§8). 메타는 Supabase 유지, 영상만 위임.

각 단계 끝에 analyze/test/build 통과 + develop_plan 갱신(프로젝트 규칙).

---

## 8. 향후 이전 경로 (스케일 시)

| | Supabase Storage | Cloudflare Stream | Mux |
|---|---|---|---|
| 트랜스코딩/HLS | ✗ | ✓ | ✓ |
| 썸네일/미리보기 | 직접 | ✓ | ✓ |
| 과금 모델 | 저장+전송(GB) | 저장+전송(분 단위) | 인코딩+전송(분) |
| 적합 | 소규모 베타 | 영상이 핵심·중규모+ | 고급 분석 필요 |

이전해도 **DB 메타(`class_videos`)는 그대로 두고** `storage_path` → 외부 asset id 로 의미만 바꾸면 됨(추상화 유지).

---

## 9. 미해결 결정 (구현 전 확정 필요)

1. **압축 위치**: 기기 압축(품질·용량↓, CPU·시간↑) vs 원본 업로드(간단, 비용↑). → 베타는 "길이/해상도 상한 + 원본"으로 시작, 비용 보고 압축 도입(B단계) 권장.
2. **수업 연결 여부**: 영상을 특정 `session_id`에 붙일지, 회원 단위로만 둘지. → 초기엔 회원 단위(단순), 후속 연결.
3. **보존 정책**: ✅ **개수 상한 채택**(회원당 N개, 차단 방식 — B-2). 기간 기반 자동삭제는 Storage 고아 파일 리스크로 정리 잡(Edge Function)과 함께 별트랙 보류(Phase 3.5 약관 연계).
4. **회원 셀프 업로드 허용 여부**: 베타는 트레이너만. 회원 업로드는 동의·악용·용량 관리 부담 → 후순위.
5. **resumable 업로드 수단**: supabase_flutter 자체 지원 확인 → 미지원 시 패키지 결정.
6. **동의 플로우 시점**: 업로드 첫 시도 시 1회 동의 vs 온보딩 동의. (Phase 3.5 약관과 연계.)
   → **MVP 잠정 결정**: 업로드 다이얼로그에 "회원 동의를 받았음" 확인 체크박스(체크 전 업로드 비활성). 서버측 플래그/이력 테이블은 Phase 3.5 약관 확정 시 승격. (코드: `upload_class_video_dialog.dart`)

---

## 10. 리스크 요약

| 리스크 | 영향 | 대응 |
|---|---|---|
| 풀세션 통영상 업로드 | 저장·전송 폭발(비용) | 길이/크기 상한 클라+버킷 양쪽 강제 |
| 원본 직배 → 모바일 느림/데이터 과다 | 회원 UX | 압축(B) → 임계 시 Stream 이전(C) |
| 영상 PII 유출 | 신뢰·법적 | 비공개 버킷 + RLS(폴더=member_id) + 단기 서명URL + 동의 |
| 고아 파일(메타 없는 객체) | 저장 누수 | 업로드→메타 보상 삭제 + 주기적 정리 잡 |
| 의존성 급증(플랫폼 플러그인) | 빌드 취약 | §6 도입 전 빌드 영향 점검 + §0 갱신 |
