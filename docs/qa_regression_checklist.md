# QA 회귀 체크리스트 — 운톡 기본기 버그 방어 (U3·U4)

> 출처: `docs/untok_improvement_plan.md` §3 UI/UX 원칙(U3 한글 입력, U4 dead-end).
> 운톡이 실제로 터진 "기본기 버그"를 우리 앱에서 재발 방지하기 위한 점검 항목.
> 정적 감사로 잡히는 것 / 기기에서만 잡히는 것을 구분한다.
>
> 최초 작성: 2026-06-30 (정적 감사 1차 통과 시점)

---

## U3 — 한글 IME 조합 안정성

운톡 불만 원문: *"수업 등록시 앞에 글씨 쓰는데 ㄱㅐㅇㅣㄴㅅㅣㄹ 이렇게 써집니다"* (iOS 한글 조합 깨짐).

### 원인 정리 (왜 깨지는가)
한글은 자모를 모아 한 글자로 조합(composing)하는 IME 동작이 있다. 조합이 **진행 중**일 때
`TextField` 가 새 `TextEditingController` 로 다시 그려지거나 `controller.text` 가 외부에서
덮어써지면, OS의 조합 상태가 끊겨 자모가 분리돼 입력된다. 그래서 아래 3가지가 금지 패턴이다.

### 금지 패턴 (코드 리뷰에서 차단)
1. **`build()` 안에서 `TextEditingController()` 생성 금지.** 리빌드마다 새 컨트롤러 → 조합 끊김.
   → 컨트롤러는 `State` 필드 초기화 또는 `initState`(late 할당)에서 1회 생성하고 `dispose()` 한다.
   → 함수형 다이얼로그(`showXxxDialog`)는 `showDialog` **호출 전에** 만들어 클로저로 캡처하고,
     `finally { ctrl.dispose(); }` 로 정리. (`showNoteEditDialog` 참조 — 2026-06-30 누수 수정)
2. **입력 중 `controller.text = ...` 대입 금지.** 초기값 채우기·전송 실패 복구·즐겨찾기 선택처럼
   "타이핑 경로 바깥"에서만 허용. (현재 `_initEditMode`·`_send` 실패복구·즐겨찾기 탭 — 모두 안전)
3. **`TextField.onChanged` 안에서 그 필드를 다시 그리는 `setState` 금지.** 값 표시용 setState는 OK,
   컨트롤러/값을 갈아끼우는 setState는 조합을 끊는다.

### 정적 감사 결과 (2026-06-30)
- 위 3패턴 **위반 0건.** 모든 컨트롤러가 `State` 필드/`initState` 또는 다이얼로그 호출 전 생성.
- `onChanged + setState` 는 전부 Dropdown/Checkbox/Radio/Slider 등 **비텍스트 위젯**에만 존재.
- 수정: `showNoteEditDialog` 컨트롤러 `dispose()` 누락 보강(IME와 무관한 메모리 누수).

### 기기 검증 필요 (정적 감사로 못 잡음) — 실기기에서만 확인
> Android 에뮬레이터/데스크톱은 한글 조합 버그를 재현 못 하는 경우가 많음. **실기기 필수.**
- [ ] iOS 실기기 + 기본 한글 키보드: 아래 입력 화면에서 "개인실" "어깨운동" 등 받침/이중모음 단어를
      빠르게 타이핑 → 자모 분리(ㄱㅐㅇㅣㄴ…) 없이 정상 조합되는지.
- [ ] Android 실기기 + 천지인/구글 키보드 동일 검증.
- 점검 대상 입력 화면 (TextField 보유 전수):
  - [ ] 수업 기록 — `session_log_screen` (종목명·통증·다음메모·세트 무게/횟수)
  - [ ] 셀프 운동 기록 — `self_log_editor_dialog` (운동·메모)
  - [ ] 채팅 입력 — `chat_screen`
  - [ ] 트레이너 메모 — `member_notes_card` (`showNoteEditDialog`)
  - [ ] 회원 추가/수정 — `add_member_dialog` / `edit_member_dialog`
  - [ ] 계약 추가 — `add_contract_dialog`
  - [ ] 예약 메모 — `add_booking_dialog` / `request_booking_dialog` / `booking_status_sheet`
  - [ ] 인앱 문의 — `inquiry_dialog`
  - [ ] 센터 설정·FAQ — `center_settings_screen` / `add_center_faq_dialog`
  - [ ] 영상 제목 — `upload_class_video_dialog`
  - [ ] AI 초안 검수 편집 — `message_review_dialog`
  - [ ] 인바디 입력 — `add_body_measurement_dialog`
  - [ ] 로그인/가입/코드/비번재설정 — `login_screen` / `claim_member_screen` / `reset_password_screen`

---

## U4 — dead-end(막다른 길) 금지

운톡 불만 원문: *"요청하기 눌러도 '서비스 준비중입니다'만 뜨고 다음으로 넘어갈 수가 없네요."*

### 원칙
- 미구현 기능 버튼은 **노출하지 않는다.** 부득이 노출 시 **명확한 대안/안내**를 함께 준다.
- 모든 네비게이션(`context.push`/`go`) 대상은 라우터에 **등록된 경로**여야 한다.
- 빈/오류 상태도 "여기서 뭘 하면 되는지" 다음 행동을 제시한다.

### 정적 감사 결과 (2026-06-30)
- **빈 핸들러(`onTap: () {}` / `onPressed: null` 등) 0건.**
- 홈·대시보드의 모든 진입점(`context.push`) 대상 라우트가 `app_router.dart` 에 **전부 등록됨**
  (`/member/*`, `/trainer/*`, `/admin/*`, `/settings`, `/legal/*` 대조 완료). 죽은 링크 0.
- 유일한 "준비 중" 노출 = FAQ `_ComingSoonCard`: 규정 미입력 시 *"담당 트레이너에게 문의해 주세요"*
  대안을 제시 → **U4 준수 패턴**(막다른 길 아님).

### 회귀 가드 (앞으로 지킬 것)
- [ ] 새 메뉴/버튼 추가 시 대상 라우트를 `app_router.dart` 에 먼저 등록.
- [ ] "준비 중"·"곧 제공" 류 안내를 새로 넣을 땐 반드시 **대안 행동**(문의·다른 화면)을 함께.
- [ ] (검토) 라우트 등록 누락을 막는 위젯 테스트 — 홈 화면이 참조하는 경로 문자열이
      라우터에 존재하는지 단언. 현재는 수동 대조로 충분, 진입점 증가 시 자동화 검토.

---

## 다음 (B 범위 밖, 후속)
- **U7** — 공통 empty/error/skeleton 위젯화. 현재 일부 화면만 적용. `untok_improvement_plan.md` §3 U7 참조.
