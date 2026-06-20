# 소셜 로그인 콘솔 설정 가이드 (P2-E 운영 작업)

> 코드(E-1 소셜 로그인 + E-2 비번 재설정)는 구현·빌드 완료. 이 문서는 **실제 로그인이
> 동작하기 위한 콘솔(대시보드) 설정**을 단계별로 정리한다. 설계·코드는
> `docs/social_login_plan.md` 참조.
>
> 작성일: 2026-06-20 / 대상 프로젝트: Supabase `gyman` (ref `sgbkuciriwnryjgfaldq`)

---

## 0. 가장 먼저 — "URL이 두 종류"

OAuth 디버깅 시간의 대부분은 이 둘을 헷갈려서 생긴다. 먼저 외운다.

| 별명 | 실제 값 | 어디에 넣나 |
|------|---------|------------|
| **A. Supabase 콜백** | `https://sgbkuciriwnryjgfaldq.supabase.co/auth/v1/callback` | **카카오·구글 콘솔**의 Redirect URI |
| **B. 앱 딥링크** | `io.supabase.gyman://login-callback` | **Supabase 대시보드**의 Redirect URLs |

**흐름:** 사용자가 카카오에 로그인 → 카카오가 **A(Supabase)** 로 보냄 → Supabase가 처리 후
**B(앱)** 으로 돌려보냄. 그래서 카카오/구글엔 **A**, Supabase엔 **B** 를 넣는다.

> 값의 출처: A의 `sgbkuciriwnryjgfaldq` 는 `src/app/.env` 의 `SUPABASE_URL` 서브도메인.
> B는 코드의 `Env.oauthRedirectUrl` 기본값(`core/config/env.dart`) + Android intent-filter
> (`android/app/src/main/AndroidManifest.xml`)와 동일해야 한다.

---

## 1. 카카오 콘솔 (developers.kakao.com)

1. 로그인 → **내 애플리케이션** → **애플리케이션 추가하기** (앱 이름·회사명 입력)
2. **앱 설정 > 앱 키** → **REST API 키** 복사 → Supabase의 "Client ID" 로 쓴다
3. **제품 설정 > 카카오 로그인** → 상단 **활성화 ON**
4. 같은 화면 아래 **Redirect URI 등록** → **URL A** 입력:
   ```
   https://sgbkuciriwnryjgfaldq.supabase.co/auth/v1/callback
   ```
5. **카카오 로그인 > 보안** → **Client Secret** **코드 생성** + **활성화 상태 = 사용함**
   → 코드 복사 → Supabase의 "Client Secret" 로 쓴다
6. **카카오 로그인 > 동의항목** → **카카오계정(이메일)** 을 **필수 동의**(또는 선택)로 설정
   — Supabase가 이메일을 받아야 계정이 생성된다

---

## 2. 구글 콘솔 (console.cloud.google.com)

1. 프로젝트 생성/선택 → **API 및 서비스 > OAuth 동의 화면** → **External** →
   앱 이름·지원 이메일 입력, 범위(scope)에 `email`·`profile` 기본 포함
2. **API 및 서비스 > 사용자 인증 정보 > 사용자 인증 정보 만들기 > OAuth 클라이언트 ID**
3. 애플리케이션 유형 = **웹 애플리케이션**
   (모바일 아님 — Supabase 웹 OAuth 흐름이라 웹 클라이언트가 맞다)
4. **승인된 리디렉션 URI** 에 **URL A** 추가:
   ```
   https://sgbkuciriwnryjgfaldq.supabase.co/auth/v1/callback
   ```
5. 생성 후 **클라이언트 ID** · **클라이언트 보안 비밀** 복사

---

## 3. Supabase 대시보드 (supabase.com/dashboard → 프로젝트 gyman)

### ① 공급자 켜기 — Authentication > Providers
- **Kakao** → 활성화 → *Client ID* = 카카오 **REST API 키**,
  *Client Secret* = 카카오 **Client Secret**
- **Google** → 활성화 → *Client ID* / *Client Secret* = 구글에서 복사한 값

### ② 앱 딥링크 등록 — Authentication > URL Configuration > Redirect URLs
**URL B** 를 Add URL:
```
io.supabase.gyman://login-callback
```
> 이걸 빠뜨리면 인증은 되는데 **앱으로 안 돌아온다.** 비번 재설정 메일도 같은 B로
> 복귀하므로 이 한 줄이 소셜·비번재설정 둘 다 커버한다.

---

## 4. 확인 (실기기)

설정 후 `.env` 는 그대로 둬도 된다(코드가 기본값 B 사용). **실기기**에서:
1. 로그인 화면 → **카카오로 시작하기** → 카카오 로그인 → 앱 복귀 → `/member/claim` 도착
2. 트레이너가 발급한 초대 코드 입력 → 회원 홈 진입 + `user_consents` 기록 확인
3. (E-2) 로그인 화면 → **비밀번호를 잊으셨나요?** → 이메일 입력 → 메일 링크 탭
   → 앱이 `/reset-password` 로 → 새 비번 설정 → 로그인

> 에뮬레이터는 딥링크가 누락되는 일이 잦으니 **반드시 실기기로** 검증한다.

---

## 5. 자주 막히는 지점 (증상 → 원인)

| 증상 | 원인 / 조치 |
|------|------------|
| 인증 후 **앱으로 안 돌아옴** | Supabase Redirect URLs 에 **URL B** 누락 → 3-② 확인 |
| `redirect_uri_mismatch` (구글/카카오 화면) | 콘솔 Redirect URI 가 **URL A** 와 불일치(오타·끝 슬래시) → 1-4 / 2-4 |
| 카카오 로그인 후 "이메일 없음" 류 | 동의항목 이메일 미설정 → 1-6 |
| "Unsupported provider" / 버튼 눌러도 무반응 | Supabase Providers 에서 해당 공급자 **비활성** → 3-① |
| 구글 "앱이 차단됨"(테스트 모드) | OAuth 동의 화면 테스트 사용자 미등록 또는 게시 필요 → 2-1 |

---

## 6. 남은 작업 (이 가이드 범위 밖)

- **애플 로그인**: iOS 플랫폼 폴더가 아직 없음(`src/app/ios` 미생성, 안드로이드 우선 베타).
  iOS 빌드 착수 시 Service ID + Sign in with Apple 키 발급 → Supabase Apple 공급자 +
  iOS `Info.plist` URL scheme(B). iOS에 소셜을 넣으면 **애플 로그인 필수**(App Store 심사 4.8).
- **카카오 네이티브 SDK**(앱 핸드오프 UX): 후속 B단계. 현재 OAuth(인앱 브라우저)로 충분.

---

*관련 문서: 설계·코드 = `docs/social_login_plan.md` / 운톡 불만 출처 = `docs/untok_improvement_plan.md` §1.1 #2.*
