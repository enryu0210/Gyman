# data/

Supabase 호출, repository, 모델 정의가 들어갈 자리.

- `repositories/` — 도메인별 데이터 접근(예: `MemberRepository`)
- `models/` — Supabase row를 Dart 객체로 변환 (PT 계약, 수업 기록 등)

원칙: UI 레이어(`features/`)는 절대 Supabase 클라이언트를 직접 호출하지 않는다.
반드시 repository를 거쳐서 접근. 그래야 테스트에서 mock repository로 교체 가능.
