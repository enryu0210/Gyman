# features/

화면 단위로 격리. 한 feature는 자기 화면, ViewModel(Riverpod notifier), 위젯만 포함.
도메인 로직과 데이터 접근은 각각 `domain/`, `data/`로 분리.

구조 (develop_plan.md §1):
- `auth/` — 로그인 + 역할 분기
- `trainer/` — 트레이너 화면
  - `session_log/` — M2 수업 기록
  - `member_card/` — M4 회원 카드 + 트레이너 전용 메모
  - `booking/` — M3 예약/노쇼
  - `renewal/` — M1 재등록 알림
- `member/` — 회원 화면 (Phase 2~3)
- `admin/` — 관리자 대시보드 (Phase 3)
