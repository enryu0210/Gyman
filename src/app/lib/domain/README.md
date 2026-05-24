# domain/

매출·분쟁과 직결되는 비즈니스 로직. UI/네트워크 의존성 0.
develop_plan.md §5.1 에 명시된 대로 **단위 테스트 필수**.

들어갈 모듈:
- `renewal_calculator.dart` — 재등록 시점 계산
- `remaining_sessions.dart` — 잔여 횟수 계산 (노쇼/취소 차감 포함)
- `deduction_rule.dart` — 당일취소/지각 등 차감 규정
- `visibility.dart` — 트레이너 전용 메모 가시성 검사

원칙:
- 순수 Dart (Flutter 의존 X) → `flutter test` 없이 `dart test`로도 돌아가야 함
- 입력→출력 결정론. 외부 시간/랜덤 의존 시 주입 받기.
