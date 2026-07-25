# 소셜 로그인 + 계정 복구 계획서 (P2-E)

> ---
> ## 📦 아카이브 문서 (2026-07-25)
> **코드는 완료됐다**(E-1 소셜 로그인 + E-2 비번 재설정). 남은 건 콘솔 설정
> → [`social_login_console_setup.md`](social_login_console_setup.md), 그리고 후속 E-3(카카오 네이티브 SDK)·E-4(SMS 인증).
> **결과 요약은 [`shipped.md`](shipped.md) §4.**
> 삭제하지 않고 남기는 이유: `auth_repository.dart`·`env.dart`·`supabase_client.dart` 등
> **코드 주석이 이 문서를 근거로 가리킨다.**
> ---


> 목적: 운톡 불만 #2(**"아이디·비번 찾기 불가, 소셜 로그인 없음, 탈퇴 후 재가입 불가"**)를 정면 해소한다.
> 출처: `docs/untok_improvement_plan.md` §4 P2-E / §5 E. 본 문서는 그 "별도 계획서"에 해당.
> 설계 정본은 `docs/develop_plan.md` — 본 계획에서 확정된 의존성·플로우는 작업 착수 시 develop_plan §0 의존성 표에 반영.
>
> 작성일: 2026-06-20 / 대상 브랜치: `develop`

---

## 0. 한눈에 — 결론 먼저

- **소셜 로그인은 네이티브 SDK 없이 Supabase Auth OAuth(인앱 브라우저 + PKCE + 딥링크)로 MVP를 낸다.** 카카오·구글·애플 모두 Supabase가 기본 지원하는 공급자라 **신규 Dart 의존성 0**(`supabase_flutter`의 `signInWithOAuth`만 사용). 카카오 네이티브 SDK(앱 핸드오프)는 UX 개선용 후속(B단계)으로 분리.
- **소셜 가입 사용자의 회원 연결은 새로 만들 필요가 없다.** 라우터가 이미 *역할 미정(member_profile 미연결) 로그인 사용자 → `/member/claim`* 으로 redirect 한다(`app_router.dart:261`). 소셜로 처음 들어온 사용자는 자동으로 초대 코드 입력 화면에 도달 → 기존 `claimMemberProfile` 재사용.
- **계정 복구(비번 찾기)는 이메일 가입자 한정** `resetPasswordForEmail` + 딥링크 복귀로 구현. 소셜 가입자는 "이 계정은 카카오로 로그인하세요" 안내로 분기.
- **가장 큰 신규 작업은 Dart 코드가 아니라 "플랫폼 배선"** — PKCE 플로우 켜기, Android intent-filter / iOS URL scheme, Supabase 대시보드 공급자 설정, 각 공급자 콘솔(카카오/구글/애플) 앱 등록. 여기서 시간이 든다.

---

## 1. 현재 인증 구조 감사 (코드 근거)

| 구성요소 | 위치 | 소셜 로그인 관점 영향 |
|----------|------|----------------------|
| `Supabase.initialize` | `core/supabase/supabase_client.dart:17` | **`authFlowType: AuthFlowType.pkce` 미설정** → OAuth/비번재설정 딥링크에 PKCE 필요. 추가해야 함 |
| `AuthRepository` | `features/auth/auth_repository.dart` | Auth를 감싼 깔끔한 seam. `signInWithOAuth` / `resetPasswordForEmail` 메서드 **여기 추가** — UI는 변경 최소 |
| `SignInController.signUp` | `features/auth/auth_providers.dart:127` | 이메일 가입은 `verify→signUp→claim` 3단계로 초대코드와 강결합. 소셜은 이 강결합을 **우회** — 가입 시 코드 없이 들어오고 연결은 `/member/claim`에서 |
| 라우터 redirect | `core/router/app_router.dart:261` | **role==null → `/member/claim`** 이미 존재. 소셜 신규 사용자 연결 흐름 = 공짜로 재사용 |
| `claim_member_screen` | `features/auth/claim_member_screen.dart` | 소셜 가입 후 착지점. 동의 기록(`recordConsent`)을 여기서도 보장해야 함(이메일 가입은 login_screen에서 기록) |
| 동의 기록 | `login_screen.dart:83` `recordConsent()` | 이메일 가입 직후 호출. **소셜 가입엔 이 경로가 없음** → 약관/동의 게이트를 소셜 버튼/클레임 화면에 별도 배치 필요(법적 필수, U5·Phase 3.5 연계) |
| 딥링크 scheme | `android/.../AndroidManifest.xml` | OAuth 콜백용 intent-filter **없음**. iOS `Info.plist` CFBundleURLTypes도 없음. 신규 배선 |

> **핵심 인사이트:** 회원 연결(claim)·역할 분기·redirect는 이미 완성돼 있어 **소셜 로그인이 얹힐 레일이 깔려 있다.** 신규 작업의 본질은 "OAuth 토큰을 받아 세션을 만드는 입구"와 "그 입구의 플랫폼 배선"이다.

---

## 2. 범위 결정 (MVP에 넣을 것 / 뺄 것)

### 2.1 P2-E를 두 트랙으로 분리

| 트랙 | 내용 | MVP 포함? |
|------|------|-----------|
| **E-1 소셜 로그인** | 카카오(1순위)·구글·애플 OAuth 로그인/가입 | ✅ MVP |
| **E-2 계정 복구** | 이메일 비밀번호 재설정(`resetPasswordForEmail`) | ✅ MVP (작고 독립적) |
| E-3 카카오 네이티브 SDK | 카카오톡 앱 핸드오프(웹뷰 없이) | ⬜ 후속 B단계 |
| E-4 SMS/전화 인증 복구 | 운톡 "문자 인증 안 됨" 대응 | ⬜ 후속 (비용·본인인증 업체 필요, 별도 검토) |

> **왜 카카오 네이티브 SDK를 MVP에서 빼나:** 네이티브 SDK는 `kakao_flutter_sdk` 의존성 + 네이티브 키 해시 등록 + 플랫폼 채널 + 별도 토큰→Supabase 교환(`signInWithIdToken`)이 필요해 규모가 크다. Supabase 기본 카카오 OAuth(인앱 브라우저)는 **공급자 설정만으로** 동작하고 UX도 충분히 수용 가능(로그인 시 카카오 로그인 페이지가 인앱 브라우저로 뜸). 먼저 OAuth로 출시하고, 핸드오프 UX가 필요하면 B단계에서 네이티브 SDK로 교체(`AuthRepository` seam 덕에 UI 무변경).

### 2.2 애플 로그인 주의

- iOS 앱에서 **"제3자 소셜 로그인을 제공하면 Apple 로그인도 제공"이 App Store 심사 가이드라인 4.8**. 카카오/구글을 iOS에 넣는 순간 **애플 로그인은 사실상 필수**. → iOS 빌드 대상이면 E-1에 애플 포함 확정. 안드로이드 우선 베타(1.12)면 카카오+구글로 먼저 내고 애플은 iOS 빌드 직전 추가 가능.

---

## 3. 기술 설계

### 3.1 OAuth 플로우 (모바일, PKCE)

```
[소셜 버튼 탭]
  → AuthRepository.signInWithOAuth(provider, redirectTo: 'io.supabase.gyman://login-callback')
  → supabase_flutter 가 인앱 브라우저로 공급자 로그인 페이지 오픈
  → 사용자 인증 → 공급자가 redirectTo 로 콜백(딥링크)
  → OS가 딥링크를 앱으로 전달 → supabase_flutter 가 code→session 교환(PKCE)
  → onAuthStateChange 에 User 발행
  → 라우터 redirect: member_profile 없으면 /member/claim, 있으면 역할 홈
```

- `signInWithOAuth`는 `Future<bool>`(브라우저 오픈 성공 여부)만 반환하고 **세션 생성은 비동기로 `onAuthStateChange`를 통해** 들어온다 → 기존 `authStateProvider` 스트림이 그대로 잡아 redirect 한다. **컨트롤러에서 await로 세션을 기다리지 말 것**(이메일 로그인과 다른 지점).

### 3.2 신규/변경 코드 (최소 변경 원칙)

**`core/supabase/supabase_client.dart`** — PKCE 활성화:
```dart
await Supabase.initialize(
  url: Env.supabaseUrl,
  anonKey: Env.supabaseAnonKey,
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce, // OAuth·비번재설정 딥링크에 필요
  ),
);
```

**`features/auth/auth_repository.dart`** — 2개 메서드 추가:
```dart
/// 소셜 로그인. 세션은 비동기로 onAuthStateChange 에 들어온다(여기서 await 안 함).
Future<void> signInWithOAuth(OAuthProvider provider) async {
  try {
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: Env.oauthRedirectUrl, // io.supabase.gyman://login-callback
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  } on AuthException catch (e) {
    throw AuthFailure(_mapAuthMessage(e), cause: e);
  } catch (e) {
    throw AuthFailure('소셜 로그인을 시작할 수 없습니다.', cause: e);
  }
}

/// 비밀번호 재설정 메일 발송(이메일 가입자 한정).
Future<void> sendPasswordReset(String email) async { ... resetPasswordForEmail ... }
```

**`features/auth/auth_providers.dart`** — `SignInController`에 `signInWithProvider(OAuthProvider)` 추가(로딩 상태만 관리, 세션 대기 X).

**`features/auth/login_screen.dart`** — 소셜 버튼 3개(카카오/구글/애플) + "비밀번호를 잊으셨나요?" 링크. **소셜 버튼 위에 약관/개인정보 동의 안내**(소셜은 가입=로그인이라 사전 동의 게이트가 login_screen 체크박스 흐름을 안 타므로, 버튼 아래 "가입 시 약관·개인정보 처리방침에 동의" 명시 + 링크).

**`features/auth/claim_member_screen.dart`** — 진입 시 `recordConsent()` 멱등 보장(소셜 가입자 동의 누락 방지). 이미 기록돼 있으면 중복 무시.

**`core/config/env.dart`** — `oauthRedirectUrl` getter 추가(상수 또는 .env). `.env.example`에 주석.

> 신규 **Dart 의존성 0.** `supabase_flutter`만으로 완결. develop_plan §0 의존성 표엔 "OAuth = supabase_flutter 내장, 카카오 네이티브 SDK는 후속" 한 줄 추가.

### 3.3 플랫폼 배선 (실제 작업량의 대부분)

| 플랫폼 | 작업 | 파일 |
|--------|------|------|
| Android | OAuth 콜백 intent-filter 추가(scheme `io.supabase.gyman`, host `login-callback`) | `android/app/src/main/AndroidManifest.xml` |
| iOS | `CFBundleURLTypes`에 동일 scheme 등록 + 애플 로그인 capability | `ios/Runner/Info.plist`, Xcode Signing&Capabilities |
| Supabase 대시보드 | Authentication > Providers 에서 Kakao/Google/Apple 활성 + Client ID/Secret 입력 + **Redirect URL에 `io.supabase.gyman://login-callback` 등록** | (콘솔) |
| 카카오 콘솔 | 앱 생성 → REST API 키 → Redirect URI에 **Supabase 콜백**(`https://<project>.supabase.co/auth/v1/callback`) 등록 → 동의항목(이메일) 설정 | (콘솔) |
| 구글 콘솔 | OAuth 클라이언트(Web) 생성 → Supabase 콜백 등록 | (콘솔) |
| 애플 | Service ID + Sign in with Apple 키 → Supabase 입력 | (콘솔, iOS 빌드 시) |

> ⚠️ **두 가지 Redirect URL을 혼동 금지:** ① 공급자 콘솔에는 **Supabase의 콜백**(`https://<ref>.supabase.co/auth/v1/callback`)을 넣고, ② 앱 `redirectTo`와 Supabase 대시보드 Redirect URLs에는 **앱 딥링크**(`io.supabase.gyman://login-callback`)를 넣는다. 이 배선 실수가 OAuth 디버깅 시간의 대부분.

### 3.4 계정 복구(E-2) 플로우

```
[로그인 화면 "비밀번호를 잊으셨나요?"]
  → 이메일 입력 다이얼로그 → resetPasswordForEmail(email, redirectTo: 딥링크)
  → 메일의 링크 탭 → 앱으로 딥링크 복귀(onAuthStateChange: passwordRecovery 이벤트)
  → 새 비밀번호 입력 화면 → updateUser(password)
```

- 소셜 전용 계정(비번 없음)에 비번 재설정 시도 시 Supabase는 메일을 보내되 무의미 → 안내 카피로 "카카오로 가입한 계정일 수 있어요. 소셜 로그인을 이용해 주세요" 보완.

---

## 4. 운톡 불만과의 대응 검증 (U5: 계정 라이프사이클)

| 운톡 원문 불만 | 본 계획의 대응 |
|----------------|----------------|
| "소셜 로그인 없음" | E-1 카카오/구글/애플 OAuth |
| "아이디·비번 찾기 불가" | E-2 `resetPasswordForEmail` + 딥링크 복귀 |
| "탈퇴 후 재가입 시 SMS 인증 안 됨" | 이미 Phase 3.5 익명화 탈퇴로 **동일 이메일 재가입 가능**(U5). 소셜은 공급자 계정이 살아있으면 재로그인=재가입 자연 동작. **검증 항목으로 명시**(아래 §6) |
| "탈퇴 처리해서 다시 가입 못 함"(관리자앱) | 소셜은 공급자측 계정 불변 → 탈퇴(앱 측 익명화) 후 같은 소셜로 재로그인 시 새 회원으로 진입 → `/member/claim` 재연결. **이 흐름 검증 필수** |

---

## 5. 작업 순서 (착수 시)

```
1. (배선) supabase_client PKCE 활성화 + Env.oauthRedirectUrl + .env.example 주석
2. (배선) Android intent-filter / iOS URL scheme 추가 → 딥링크 왕복만 먼저 검증(빈 콜백 로그)
3. (콘솔) Supabase 대시보드 + 카카오 콘솔 공급자 설정(구글/애플은 뒤에)
4. (코드) AuthRepository.signInWithOAuth + SignInController.signInWithProvider
5. (코드) login_screen 소셜 버튼(카카오 먼저) + 동의 안내 카피/링크
6. (코드) claim_member_screen 진입 시 recordConsent 멱등 보장
7. (E2E) 카카오 신규 → /member/claim → 초대코드 연결 → 회원 홈 / 동의 기록 확인
8. (코드) 구글 추가 → (iOS 빌드 트랙이면) 애플 추가
9. (E-2) resetPasswordForEmail + 새 비번 화면 + 딥링크 passwordRecovery 핸들링
10. develop_plan §0 의존성 표 + §3 라우트 + untok §2 #2 GAP→DONE 갱신
```

각 단계 `flutter analyze && flutter test` 통과 후 Phase 단위 커밋. OAuth는 **실기기 딥링크 검증 필수**(에뮬레이터 딥링크는 누락 잦음).

---

## 6. 리스크 / 의사결정 필요 사항

1. **iOS 빌드 시점** — 카카오/구글을 iOS에 넣으면 애플 로그인 필수(심사 4.8). 베타가 안드로이드 우선(1.12)이면 카카오+구글로 먼저, 애플은 iOS 빌드 직전. **결정 필요: MVP에 애플 포함 여부.**
2. **카카오 OAuth(인앱 브라우저) vs 네이티브 SDK** — MVP는 OAuth 권장(의존성 0). 핸드오프 UX 요구 강하면 B단계 SDK. **결정 필요: MVP UX 수용선.**
3. **딥링크 scheme 명** — `io.supabase.gyman` 관례 채택 제안. 앱 패키지명(`applicationId`)과 다르게 OAuth 전용으로 두면 충돌 적음. **확정 필요.**
4. **동의 기록 시점** — 소셜은 login_screen 체크박스를 안 타므로 "버튼=동의 간주 + 명시 카피" vs "소셜 후 claim 화면에서 동의 강제" 중 택1. **법무/UX 결정**(Phase 3.5 약관 정식화와 함께).
5. **계정 병합** — 같은 이메일을 이메일가입+카카오로 각각 쓰면 별도 계정이 됨(Supabase 기본). 베타 규모에선 병합 미지원으로 두고 "이미 가입된 이메일" 안내. 본격 운영 시 재검토.

---

## 7. 완료 정의 (DoD)

- [ ] 카카오 신규 사용자: 소셜 로그인 → `/member/claim` → 초대코드 연결 → 회원 홈, `user_consents` 기록됨
- [ ] 기존 회원: 소셜 재로그인 시 바로 역할 홈(claim 재요구 X)
- [ ] 탈퇴(익명화) 후 동일 소셜 재로그인 → 신규 회원으로 정상 진입(U5)
- [ ] 이메일 가입자: 비밀번호 재설정 메일 → 딥링크 복귀 → 새 비번 → 재로그인 성공
- [ ] 소셜 전용 계정에 비번재설정 시 안내 카피 노출
- [ ] 실기기(안드로이드) 딥링크 왕복 + `flutter analyze`/`test`/`build apk --debug` 통과
- [ ] develop_plan §0/§3 + untok §2 #2 GAP→DONE 반영

---

*본 계획은 운톡 §1.1 불만 #2 + Gyman 현행 인증 코드 감사(2026-06-20: `auth_repository`/`auth_providers`/`app_router`/`supabase_client`)를 종합. 착수 확정 시 develop_plan 의존성 표를 먼저 갱신한다.*
