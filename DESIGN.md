# Gyman 디자인 시스템 — 에너제틱 스포츠

> 이 문서가 **디자인 결정의 단일 출처**다. 색·폰트·간격·형태를 바꿀 땐 여기부터 갱신하고,
> 구현체인 `src/app/lib/core/theme/app_theme.dart`(ColorScheme + 컴포넌트 테마)를 맞춘다.
> 시각/UI 결정 전 항상 이 문서를 먼저 읽는다.

## 제품 맥락
- **무엇:** 헬스장 PT 트레이너 앱. 트레이너(수업기록·회원관리·예약·재등록)와 회원(예약·기록열람·동기부여)이 함께 쓴다.
- **무드:** 에너제틱 스포츠 — 생동감 있고 동기부여되지만, 트레이너의 데이터 화면에서 시끄럽지 않게.
- **핵심 원칙(한 줄):** 에너지는 **볼트 라임 한 색**으로만, 나머지 무게는 **잉크 블랙 + 여백 + 큰 숫자**가 잡는다.

## 결정적 규칙 — 볼트 라임 사용법
볼트 라임(`#C6FF00`)은 밝은 배경 위에서 **텍스트/아이콘 색으로 쓰면 WCAG 대비가 무너져 안 보인다**(리서치 검증).
따라서 라임은 **"채우기(fill) 배경 + 그 위 잉크색 글씨"로만** 쓴다.

- ✅ 스트릭 블록 배경, "임박" 칩 배경, 프로그레스 게이지 채움, 라임 CTA 버튼(`AppTheme.voltButtonStyle`)
- ❌ 라임으로 된 본문/제목 텍스트, 라임 아이콘(라이트 배경 위), 라임 얇은 테두리

## 컬러
구현: `AppTheme` 상수 + `ColorScheme`(`_scheme`). 라이트는 강조=잉크(차분), 다크는 강조=볼트(전기적).

| 토큰 | HEX | ColorScheme 역할 | 용도 |
|------|-----|------------------|------|
| Ink | `#16181D` | (light) `primary` / `onTertiaryContainer` | 텍스트·기본 버튼·라이트 강조·라임 위 글씨 |
| Volt | `#C6FF00` | `tertiaryContainer` / (dark) `primary` | 강조 채우기 전용 |
| Canvas (light) | `#F4F5F3` | `scaffoldBackgroundColor` | 앱 배경 |
| Surface (light) | `#FFFFFF` | `surface` / 카드 | 카드·시트·다이얼로그 |
| Line (light) | `#E6E7E3` | 카드/디바이더 경계 | 그림자 대신 얇은 선으로 구획 |
| Canvas (dark) | `#0F1012` | `scaffoldBackgroundColor` | 다크 앱 배경 |
| Surface (dark) | `#16181D` | `surface` | 다크 카드 |
| Line (dark) | `#262930` | 경계 | 다크 구획선 |
| Error | `#E5484D` (dark `#FF6169`) | `error` | 상태·경고 |

- **다크 모드**: `ThemeMode.system`으로 자동. 다크에선 `primary=Volt`라 강조 텍스트/버튼이 라임으로 살아난다(다크 배경 대비 안전).

## 타이포그래피
- **폰트: Pretendard** (가변폰트 단일 파일 `assets/fonts/PretendardVariable.ttf`, OFL). `fontFamily: 'Pretendard'` 전역 적용.
  - google_fonts 미사용(오프라인 동작 + deps 지침). 라이선스: `assets/fonts/OFL.txt`.
- **위계(Material 3 textTheme + Pretendard):**
  - 핵심 숫자(잔여 횟수·오늘 수업 건수): `displaySmall`~ 초대형, `FontWeight.w800`, `tabular` 느낌으로 크게.
  - 헤드라인/인사말: `headlineSmall` w800, 자간 `-0.02em`.
  - 앱바 타이틀: w800 / 19px / 자간 `-0.2`.
  - 본문: 기본(w400~500). 보조 텍스트는 `onSurfaceVariant`.
  - 리스트 타이틀: w700 / 15px.

## 형태 · 간격
- **라운드:** 카드 `20`, 버튼/입력칸/칩 `12`, 다이얼로그 `20`.
- **카드:** `elevation 0` + 얇은 경계선(`Line`) + `surfaceTint` 투명. 그림자 대신 선으로 구획(플랫·클린).
- **간격:** 화면 패딩 `16`, 카드 내부 `16~18`, 카드 사이 `14~16`.
- **아이콘:** Material `*_outlined` 라인 아이콘. **이모지를 섹션 마커로 쓰지 않는다**(AI-slop). 유일한 예외 없음 — 스트릭도 `Icons.bolt`.

## 컴포넌트 (app_theme.dart 컴포넌트 테마)
- **기본 CTA:** `FilledButton` = 잉크(라이트)/볼트(다크), 라운드 12.
- **라임 CTA:** 강조가 필요한 버튼만 `AppTheme.voltButtonStyle`(라임 배경 + 잉크 글씨) 명시.
- **볼트 블록:** "에너지 한 방" 요소(회원 홈 스트릭). `Material(color: AppTheme.volt, radius 20)` + 잉크색 글씨/아이콘. 라이트/다크 공통 고정.
- **잉크 블록:** 집중이 필요한 트레이너 요소(재등록 관리 등)에 near-black 배경 + 흰 글씨 + 라임 강조 수치.
- **배지/칩:** 안읽음·대기 건수는 `errorContainer`, "임박" 등 긍정 강조는 볼트 칩.
- **메뉴 그리드(`core/widgets/app_menu_grid.dart`):** 홈 "바로가기"는 `ListTile` 세로 나열(=설정 화면 같은 밋밋함) 대신 **아이콘 칩 + 라벨 2열 격자 타일**로. 타일=카드 톤(surface + `AppTheme.lineColor` 테두리 + 라운드 16). 화면당 대표 액션 1개만 `highlight`=볼트 채우기(회원=예약 신청). 배지는 타일 우상단 카운트 필. 회원·트레이너 홈이 공유.

## 미리보기
- 디자인 피치 보드(초기 회원/트레이너 홈 목업): https://claude.ai/code/artifact/53aa62a1-f61a-4d70-8756-ee62d36f4752
- 홈 격자+히어로 목업(라이트/다크, 2026-07-16): https://claude.ai/code/artifact/8c0827aa-e68a-410d-912d-4ed42e569048
- 회원 목록 재설계 목업(라이트/다크, 2026-07-16): https://claude.ai/code/artifact/f4d06333-8a76-4bc2-9741-6fddd741602c

## 결정 로그
| 날짜 | 결정 | 근거 |
|------|------|------|
| 2026-07-15 | 초기 디자인 시스템 확정: "블랙 + 볼트 라임" 에너제틱 스포츠 | 기존 = Flutter 기본 Indigo 시드(디자인 전무). 사용자 선택 = 에너제틱 스포츠. 리서치: near-black+단일 하이에너지 강조+큰 숫자가 피트니스 앱 공식이나, 라임은 fill 전용이어야 대비 안전. |
| 2026-07-15 | Pretendard 채택 | 한국어 앱 표준·가변폰트·OFL. 테마 주석에도 후보로 예정돼 있었음. |
| 2026-07-16 | 트레이너 홈에 "오늘 할 일" 잉크 히어로 도입 | 회원 홈(볼트 스트릭 히어로)과 달리 트레이너 홈은 카드만 있어 밋밋 → 흩어진 배지 카운트(승인·검수·채팅)를 잉크 블록 + 볼트 큰 숫자 하나로 집약. 배지=네비게이션 / 히어로=총량 으로 역할 분리(중복 아님). 잉크 블록은 다크에서 canvas와 명도가 가까워 볼트 얇은 테두리로 분리(라임 테두리는 다크에서만 안전). |
| 2026-07-16 | 홈 메뉴를 세로 리스트 → 2열 격자 컴포넌트(`AppMenuGrid`)로 | 사용자 피드백: `ListTile` 나열이 "일자 목록"처럼 밋밋해 실제 앱 느낌·검증이 어려움. 아이콘 칩+라벨 격자 타일로 밀도·스캔성 확보. 회원/트레이너 공용 컴포넌트라 톤 일관. 대표 액션 1개만 볼트 강조로 시선 유도. |
| 2026-07-16 | 회원 목록/상세를 디자인 시스템에 정렬 | 목록: `ListTile`+`Divider` → 카드 타일(홈 격자와 같은 `menuTileSurface`/`menuTileBorder` 톤, 다크에서 배경에 안 묻힘) + "전체/관리 필요" 큰 숫자 요약(관리 필요>0 → `error`색). 상세: 하드코딩 `Colors.green`(가입 체크)·`Colors.red`(삭제) → 테마색(`primary`/`error`)으로 교체해 다크 함정 제거, 로컬 `_NotFoundView` → 공용 `AppEmptyView`. 링크 상태는 "예외에 집중" 원칙 — 미가입만 회색 칩, 가입 완료는 무표식. |
