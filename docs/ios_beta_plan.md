# iOS 베타 배포 계획 (1.12) — 현재 상태·블로커·실행 순서

> **작성 2026-07-30.** 계기: **베타 테스터 트레이너가 전원 아이폰 유저**로 확인됨.
> 이에 따라 `develop_plan.md` 1.12 의 "안드로이드 우선(Firebase App Distribution)" 전제는 폐기하고,
> **iOS/TestFlight 가 크리티컬 패스**가 되었다. 이 문서가 iOS 배포의 정본이다.
>
> 이 문서는 **리포 밖 작업(애플 계정·CI·콘솔)이 절반 이상**이다.
> 코드 작업만 끝내도 배포는 안 되고, 계정 승인이 며칠 걸리므로 **§6 실행 순서**의 1번을 먼저 걸어둘 것.

---

## 0. 결론 요약

| 질문 | 답 |
|------|-----|
| 아이폰을 빌려서 베타테스트 가능한가? | **테스트는 가능, 빌드는 불가.** 테스터가 남의 기기여도 TestFlight 설치엔 아무 문제 없다. 진짜 병목은 iPhone 이 아니라 **Mac** — Xcode 는 macOS 전용이라 Windows 에서는 `.ipa` 를 만들 수 없다 |
| Mac 없이 배포 가능한가? | **가능.** 클라우드 macOS CI(Codemagic 등)에서 빌드 → TestFlight 업로드. Windows-only Flutter 개발자의 표준 경로 |
| 돈이 드는가? | **Apple Developer Program $99/년 필수.** 이건 우회로가 없다. CI 는 무료 티어로 시작 가능 |
| 지금 당장 iOS 빌드를 시도하면? | **`src/app/ios/` 폴더 자체가 없어 시작 전 단계.** 만들어도 Info.plist 권한 문구가 없어 카메라·사진 접근 시 **iOS 는 경고가 아니라 즉시 크래시**한다 |
| 가장 급한 것 | **① Apple Developer Program 등록**(승인 대기 며칠~2주 = 크리티컬 패스), ② `camera`/ML Kit 의존성 정리(최소 iOS 버전과 IPA 크기를 혼자 좌우), ③ 애플 로그인 유무 결정(§5) |
| 승인 기다리는 동안 쓰게 할 방법 | **웹 빌드가 통과한다**(2026-07-30 실측) → Safari 링크로 임시 사용 가능. 단 알림 미지원·파일 업로드 불확실 = **임시 우회로**(§8.1) |
| 최단 경로 | **TestFlight 내부 테스터(최대 100명)** 로 배포 — **베타 심사 없이 즉시 배포**되고, 애플 로그인(가이드라인 4.8)도 이 단계에선 강제되지 않는다. 단 내부 테스터는 App Store Connect 팀 사용자로 초대해야 한다(§4-3 주의) |

---

## 1. 현재 상태 실측 (2026-07-30)

전부 코드/파일 확인 결과다. 추정 아님.

| 항목 | 상태 | 근거 |
|------|------|------|
| iOS 플랫폼 폴더 | ❌ **없음** (`android`/`web`/`windows` 만) | `ls src/app/` |
| Flutter / Dart | 3.44.0 stable / Dart 3.12.0 | `flutter --version` |
| 앱 버전 | `1.0.0+1` (+ `kAppVersion` 상수 수동 동기화) | `pubspec.yaml:19`, `lib/core/config/app_info.dart` |
| 번들 ID 후보 | `com.gyman.gyman` (Android `applicationId`/namespace 와 통일 권장). PoC 는 `com.gyman.poc` | `android/app/build.gradle.kts` |
| 앱 표시명 | `Gyman` | `AndroidManifest.xml` `android:label` |
| 로컬 알림 iOS 대응 | ✅ **이미 구현됨** — `DarwinInitializationSettings`(권한은 사용자가 켤 때 요청) + `IOSFlutterLocalNotificationsPlugin.requestPermissions` + `DarwinNotificationDetails` | `lib/core/notifications/notification_service.dart:43,68,105` |
| iOS 대기 알림 64개 제한 | ✅ **이미 대비됨** — `computePtReminders(max: 32)` 로 가까운 32건만 예약 | `lib/domain/pt_reminder.dart:69` |
| 계정 삭제(탈퇴) | ✅ 구현됨 — 심사 가이드라인 **5.1.1(v) 계정 삭제 요건 충족** | `lib/features/settings/delete_account_dialog.dart` + Edge Function `delete-account` |
| 문의하기 | ✅ 구현됨(앱 내 문의 → 관리자 문의함) | `lib/features/settings/inquiry_dialog.dart` → `lib/features/admin/support/` |
| 애플 로그인 | ❌ **미구현** — 카카오·구글 버튼만 | `lib/features/auth/login_screen.dart:293,304` |
| OAuth 딥링크 | Android intent-filter ✅ / **iOS `CFBundleURLTypes` 없음**(폴더 자체가 없음) | `AndroidManifest.xml`, `.env.example` `OAUTH_REDIRECT_URL=io.supabase.gyman://login-callback` |
| 앱 아이콘 원본 | ✅ **`assets/brand/` 4종 전부 git 추적됨** — `icon_master.png`(1024×1024)·`icon_foreground.png`(1024×1024)·`splash_logo.png`·`splash_bolt.png` | `git ls-files`, PNG 헤더 실측 (2026-08-01) |
| 아이콘 생성 도구 | ✅ **이미 도입** — `flutter_launcher_icons ^0.14.1` + `flutter_native_splash ^2.4.1` (dev_dependencies). 둘 다 `ios: false` 로 꺼져 있고 사유가 "iOS 프로젝트 스캐폴드 없음" 이라 명시됨 | `pubspec.yaml:80,87-109` |
| 웹 빌드(우회로 후보) | ⚠ **빌드는 통과**(`flutter build web --release` ✅ 64.4s / 산출물 50MB, 2026-07-30 실측). 단 **런타임 미검증** — 상세는 §8.1 | `build/web` |
| PoC 네이티브 채널 | Android(Kotlin `VideoFrameExtractor`)만. iOS 미구현 — **PoC 전용이라 베타 범위 밖** | `MethodChannel('gyman/poc_video_frames')` |

### 1.1 의존성별 iOS 요구사항 — **여기가 이 문서의 핵심**

| 패키지 | iOS 최소 버전 | iOS 추가 배선 |
|--------|--------------|--------------|
| `google_mlkit_pose_detection` 0.15.0 | **15.5** ⚠ | CocoaPods `GoogleMLKit/PoseDetection` + `PoseDetectionAccurate` ~>9.0.0 (**둘 다** — 네이티브 모델 2종 번들 = IPA 대폭 증가) |
| `camera` 0.12.0+2 (`camera_avfoundation`) | 13.0 | `NSCameraUsageDescription` (+영상 시 `NSMicrophoneUsageDescription`) |
| `image_picker` 1.2.2 (`image_picker_ios`) | 13.0 | `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription` |
| `video_player` (`video_player_avfoundation`) | 13.0 | 서명 URL(HTTPS)이라 ATS 예외 불필요 |
| `flutter_local_notifications` 18.0.1 | 11.0 | 코드 대응 완료(§1). Podfile 최소 버전만 맞으면 됨 |
| `supabase_flutter` 2.12.4 (`app_links` 7.0.0) | — | `CFBundleURLTypes` 에 `io.supabase.gyman` 등록 |

> **⚠ 가장 중요한 사실:** `camera` 와 `google_mlkit_pose_detection` 은 **`lib/poc/` 4개 파일에서만 쓰이고
> 프로덕션 코드에서 사용처가 0건**이다(`grep` 확인). 그런데 `pubspec.yaml` 의 `dependencies:` 에 있어
> **iOS 빌드에는 그대로 링크된다.** 그 대가는:
> - 앱 전체 최소 지원 버전이 **iOS 15.5** 로 끌려 올라간다(다른 패키지는 13.0)
> - ML Kit 자세 검출 모델 2종이 IPA 에 번들 → **다운로드 용량 급증**(안드로이드에서 이미 측정된 문제)
> - 카메라 권한 문구가 **필수**가 된다(문구 없이 접근하면 iOS 는 즉시 크래시, Android 와 다르다)
>
> → **베타 iOS 빌드에서는 두 의존성을 빼는 것을 강력 권고**(§5 결정 1). PoC 는 `poc/cv-track` 브랜치의
> 안드로이드 전용 작업이므로 베타에 실릴 이유가 없다.

---

## 2. 블로커 (없으면 배포 자체가 불가)

| # | 블로커 | 왜 막히나 | 해소 방법 | 리드타임 |
|---|--------|-----------|-----------|----------|
| **B1** | **macOS/Xcode 없음** | Windows 에서 `.ipa` 빌드·서명·업로드 불가. 아이폰을 몇 대 빌려도 해결 안 됨 | 클라우드 macOS CI(§3) | 반나절~1일 세팅 |
| **B2** | **Apple Developer Program 미등록** | TestFlight 배포·인증서·App ID 전부 잠김. 기존에 만든 건 그냥 Apple ID 일 가능성 — **별개로 Enroll 필요** | 개인 등록(신분 확인) 또는 법인 등록(D-U-N-S 번호 필요) + **$99/년** | **며칠~2주** ← 크리티컬 패스 |
| **B3** | `src/app/ios/` 미생성 | 빌드 대상 자체가 없음 | `flutter create --platforms=ios .` — **Windows 에서도 실행됨**(파일 생성만) | 수분 |
| **B4** | Info.plist 권한 문구 부재 | iOS 는 사용 목적 문구 없이 카메라/사진 접근 시 **경고가 아니라 즉시 크래시**. 심사도 반려 | §3.1 키 추가 | 수분 |
| **B5** | 애플 로그인 미구현 | 카카오·구글을 제공하므로 **가이드라인 4.8** 대상 → 정식 심사·외부 테스터에서 반려 위험 | 내부 테스터로 회피(즉시) 또는 구현(§5 결정 2) | 회피 0 / 구현 1~2일+콘솔 |
| **B6** | ML Kit 이 최소 iOS 15.5 강제 + IPA 비대 | PoC 전용 의존성이 베타 빌드의 지원 기기·용량을 결정해버림 | pubspec 에서 제거(§5 결정 1) | 수분 |

> **B2 를 먼저 거는 이유:** B1·B3~B6 는 전부 우리가 몇 시간~며칠에 끝낼 수 있지만,
> B2 는 **애플의 승인 속도에 종속**되어 우리가 단축할 수 없다. 오늘 걸어두고 나머지를 병행하는 것이 최적.

---

## 3. 코드/리포 작업 목록

### 3.1 `ios/Runner/Info.plist` 에 추가할 키

```xml
<!-- 권한 사용 목적 — 문구 없이 접근하면 iOS 는 즉시 크래시하고, 심사도 반려된다.
     문구는 "무엇에 쓰는지 + 무엇을 하지 않는지"까지 써야 반려 확률이 낮다. -->
<key>NSPhotoLibraryUsageDescription</key>
<string>수업 사진·영상을 회원과 공유하기 위해 앨범에서 선택합니다. 선택한 항목만 업로드되며 앨범 전체를 읽지 않습니다.</string>

<key>NSCameraUsageDescription</key>
<string>수업 사진·영상을 바로 촬영해 기록하기 위해 사용합니다.</string>

<!-- 영상 촬영 시 오디오 트랙 때문에 필요. 영상 기능을 넣는 빌드라면 필수. -->
<key>NSMicrophoneUsageDescription</key>
<string>수업 영상을 촬영할 때 소리를 함께 녹음합니다.</string>

<!-- 소셜 로그인·비밀번호 재설정 OAuth 콜백. Android intent-filter / Supabase 대시보드
     Redirect URLs / .env 의 OAUTH_REDIRECT_URL 과 정확히 같아야 한다. -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array><string>io.supabase.gyman</string></array>
  </dict>
</array>

<!-- 수출 규정 심사 질문을 매 빌드마다 되묻지 않게 하는 선언(표준 HTTPS 만 사용). -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>

<!-- 한국어 앱이므로 기본 언어 고정. -->
<key>CFBundleLocalizations</key>
<array><string>ko</string></array>
```

> `camera`/ML Kit 을 제거하면 `NSCameraUsageDescription`·`NSMicrophoneUsageDescription` 은
> **image_picker 의 촬영 경로 때문에 여전히 필요**하다(제거해도 남는다).

### 3.2 그 외 코드 작업

- [ ] `flutter create --platforms=ios .` (기존 파일 덮어쓰지 않음, `ios/` 만 생성)
- [ ] **번들 ID `com.gyman.gyman`** 로 설정 — Android 와 통일(딥링크·콘솔 등록 혼동 방지)
- [ ] `ios/Podfile` 의 `platform :ios, '...'` 를 **§5 결정 1의 결과에 맞춰** 지정
      (ML Kit 유지 → `15.5` / 제거 → `13.0`)
- [ ] **앱 아이콘/스플래시**: 원본도 생성 도구도 이미 다 있다(§1 정정). `pubspec.yaml` 에서
      `flutter_launcher_icons.ios` 와 `flutter_native_splash.ios` 를 `true` 로 뒤집고
      `dart run flutter_launcher_icons` / `dart run flutter_native_splash:create` 재실행하면 끝.
      ⚠ iOS AppIcon 은 **알파 채널이 있으면 App Store Connect 업로드가 거부**된다
      → `remove_alpha_ios: true` 를 함께 넣을 것. (`ios/` 폴더 생성 **후**에 실행해야 산출물이 들어갈 자리가 생긴다)
- [ ] `Runner` 표시명(`CFBundleDisplayName`) — 한글 표기 쓸지 결정(`Gyman` 유지 권장, 홈 화면 이름 길이 제약)
- [ ] `.gitignore` 에 iOS 산출물(`ios/Pods/`, `ios/.symlinks/`, `*.xcworkspace/xcuserdata`) 추가
- [ ] CI 설정 파일(`codemagic.yaml` 등) 커밋 — **로컬에서만 고친 빌드 설정은 사라진다**(CLAUDE.md 선례)

### 3.3 빌드 경로 선택지

| 방법 | 비용 | 장점 | 단점 |
|------|------|------|------|
| **Codemagic** (권고) | 무료 티어 있음(월 빌드 분수 제한, 정책 변동) | Flutter 특화, App Store Connect API 키로 **자동 코드사인 + TestFlight 업로드**까지 yaml 하나 | 무료 분수 초과 시 과금 |
| GitHub Actions (macOS 러너) | 퍼블릭 리포 무료 / **프라이빗은 macOS 분당 요금이 10배** | 리포와 한 곳에서 관리 | fastlane·인증서 배선을 직접 작성 |
| 원격 Mac 임대(MacinCloud 등) | 월 구독 | Xcode 를 직접 만짐(디버깅 유리) | CI 보다 비싸고 수동 |
| 중고 Mac mini 구입 | 일회성 목돈 | 반복 사이클에 가장 빠름, 실기기 디버깅 가능 | 초기 비용 |

> **권고: Codemagic 으로 시작.** 다만 **빌드 검증을 Claude 가 대신할 수 없다**(macOS 부재) —
> 첫 성공까지는 CI 로그를 보고 왕복하는 작업이 필요하다.

---

## 4. 애플 계정·콘솔 작업 (리포 밖)

1. **Apple Developer Program Enroll** ($99/년) — 개인은 신분 확인, 법인은 D-U-N-S. **오늘 걸 것.**
2. **App Store Connect 에 앱 생성** — 번들 ID(App ID) 등록, 이름·기본 언어(한국어)·카테고리
3. **TestFlight 테스터 구성** ← **여기 주의**
   - **내부 테스터(최대 100명, 각 30기기): 베타 심사 없이 즉시 배포.** 최단 경로.
     단 내부 테스터는 **App Store Connect 팀 사용자로 초대**해야 한다 → 트레이너들에게
     팀 계정 권한(최소 권한 롤)을 주는 것에 대한 판단이 필요하다.
   - **외부 테스터(최대 10,000명): 팀 초대 불필요(이메일/공개 링크)** 하지만 **Beta App Review**(보통 1~2일)를
     통과해야 하고, 여기서 **애플 로그인(4.8)·권한 문구·개인정보 항목**이 걸릴 수 있다.
   - 빌드 유효기간 **90일** → 베타 기간이 길면 재빌드 필요
4. **App Store Connect 앱 개인정보(App Privacy) 설문** — 수집 항목 신고.
   우리 앱은 이름·연락처·건강 관련 기록(인바디·수업 기록)·사진·사용자 콘텐츠(채팅)를 다루므로 **성실 기재 필수**.
   **외부 LLM(Gemini) 전송**이 있어 "제3자 공유" 항목을 빠뜨리면 반려/제재 사유가 된다
   (`develop_plan.md` §6 의 AI 데이터 전송 동의 항목과 짝을 맞출 것).
5. **지원 URL·개인정보 처리방침 URL** — App Store Connect 필수 입력. 앱 내 문의하기와 별개로 **웹에 접근 가능한 URL**이 필요하다.
   → **현재 없음. 준비 필요**(앱 내 `legal_screen` 본문을 정적 페이지로 게시하는 방안).
6. (애플 로그인을 넣기로 결정한 경우) **Service ID + Sign in with Apple 키** 발급 → Supabase Apple 공급자 입력
   → 절차는 `social_login_console_setup.md` 에 이어서 작성.

---

## 5. 결정이 필요한 사항 (사용자 판단)

| # | 결정 | 선택지 | 권고 |
|---|------|--------|------|
| **1** | 베타 iOS 빌드에 `camera` + `google_mlkit_pose_detection` 을 넣을지 | (a) 제거 → 최소 iOS 13.0, IPA 대폭 감소 (b) 유지 → 최소 15.5, 용량 증가 | **(a) 제거.** 프로덕션 사용처 0건이고, PoC 는 안드로이드 전용 트랙. 4단계 CV 착수 시 다시 넣으면 된다 |
| **2** | 애플 로그인을 베타에 포함할지 | (a) 내부 테스터로 가고 보류 (b) 지금 구현 | **(a) 보류 → 외부 테스터/정식 출시 전에 구현.** 내부 테스터 100명은 트레이너 베타 규모에 충분하고 베타 심사가 없다. 단 §4-3 의 팀 사용자 초대 이슈를 감수해야 함 |
| **3** | 빌드 경로 | Codemagic / GitHub Actions / 원격 Mac / 중고 Mac | **Codemagic 으로 시작.** 베타 사이클이 길어지면(크래시 수정 → 재업로드 반복) 중고 Mac 이 오히려 싸진다 |
| **4** | 안드로이드 베타를 병행할지 | 병행 / iOS 만 | **iOS 우선, 안드로이드는 검증용으로 유지.** 실기기 검증(Z Flip 3)은 계속 안드로이드로 하는 게 빠르다 |
| **5** | 지원/개인정보 URL 호스팅 | GitHub Pages / Supabase Storage 정적 / 기타 | GitHub Pages 가 무료·즉시. 심사 필수 항목이라 빠뜨리면 등록 자체가 막힌다 |

---

## 6. 실행 순서 (의존성 순)

```
[오늘] 1. Apple Developer Program Enroll ────────────┐ (승인 며칠~2주, 우리가 단축 불가)
                                                     │
[병행] 2. 결정 1·2·3 확정 (§5)                       │
       3. flutter create --platforms=ios .           │
       4. Info.plist 키 + Podfile 최소버전            │
       5. 아이콘/스플래시 ios:true 재생성             │
       6. 지원/개인정보 URL 게시                      │
                                                     │
[승인 후] 7. App ID·앱 생성 → API 키 발급 ◄──────────┘
          8. Codemagic 연결 → 첫 .ipa 빌드 (CI 로그 왕복)
          9. TestFlight 업로드 → 내부 테스터 초대
         10. §7 iOS 재검증 항목 실행
         11. 트레이너 배포
```

---

## 7. iOS 에서 반드시 재검증할 항목

안드로이드 검증(`e2e_verification_script.md`)으로 **대체되지 않는** 것만. 서버측 가시성·RLS 는 플랫폼 무관이라 재검증 불필요.

| # | 항목 | 왜 iOS 에서 다시 봐야 하나 |
|---|------|---------------------------|
| **1** | **한글 IME 조합** — 회원 이름·메모·종목·채팅 입력 | **최우선.** 경쟁 앱(운톡)의 대표 불만이 정확히 iOS 한글 조합 깨짐("ㄱㅐㅇㅣㄴㅅㅣㄹ")이다. `qa_regression_checklist.md:37` 이 이미 이 항목을 iOS 실기기 조건으로 명시 |
| 2 | 알림 권한 요청 → 예약 → 발화 | Darwin 권한 흐름은 Android 와 별개 경로. 앱 종료 상태 발화도 확인 |
| 3 | 권한 **거부** 경로 (사진/카메라) | iOS 는 거부 시 동작이 다르고, 문구 누락 시 크래시한다 |
| 4 | OAuth 딥링크 왕복 (카카오·구글) | `CFBundleURLTypes` + ASWebAuthenticationSession 경로. Android 설정이 그대로 먹지 않는다 |
| 5 | 수업 영상 업로드/재생 | `image_picker` 영상 선택 + AVFoundation 재생(서명 URL) — HEVC/HEIC 등 iOS 고유 포맷 |
| 6 | 세이프에어리어·노치·다이나믹 아일랜드 | 하단 홈 인디케이터에 버튼이 가려지는 사고가 흔하다 |
| 7 | 스와이프 뒤로가기 제스처 | go_router 라우팅에서 예상치 못한 pop 이 나올 수 있다 |
| 8 | 텍스트 크기 접근성 설정 확대 | iOS 사용자가 실제로 많이 쓰는 설정 — 레이아웃 깨짐 |

---

## 8. 곁가지: "그럼 당장은 어떻게 쓰게 하나" — 웹 우회로

### 8.1 웹 빌드는 통과한다 (2026-07-30 실측)

`flutter build web --release` 가 **성공했다**(64.4s, `build/web` 50MB).
`dart:io` 를 쓰는 6개 파일 때문에 컴파일이 깨질 것으로 봤는데, 실제로는 통과한다.
즉 **Apple Developer Program 승인을 기다리는 동안 아이폰 트레이너에게 Safari 링크로 먼저 써보게 하는 길이 열려 있다.**

**단, 빌드 통과 ≠ 동작.** 태우기 전에 확인해야 하는 것:

| 확인 항목 | 예상 |
|-----------|------|
| 채팅 사진 / 수업 영상 업로드 | ⚠ `dart:io` `File(picked.path)` 경로 — 웹에서 경로 기반 파일 접근은 동작하지 않을 가능성이 높다. **실측 필요**(`chat_screen.dart:104`, `class_videos_card.dart:205`) |
| PT 시작 전 로컬 알림 | ❌ `flutter_local_notifications` 웹 미지원. 다만 `NotificationService` 가 모든 플랫폼 호출을 try-catch no-op 으로 감싸 **크래시는 안 나고 조용히 안 옴** |
| 카카오·구글 OAuth | ⚠ 커스텀 스킴(`io.supabase.gyman://`) 대신 **https 리다이렉트 URL** 을 Supabase 대시보드에 추가해야 한다 |
| 호스팅 | Supabase Storage 정적 / GitHub Pages / Vercel — §5 결정 5 의 지원 URL 호스팅과 함께 처리하면 한 번에 끝난다 |
| iOS Safari 한글 IME | §7-1 과 동일한 위험 — 웹이라고 면제되지 않는다 |

> **위치:** 웹은 **정식 배포 경로가 아니라 대기 기간용 임시 우회로**다. 알림이 안 오고 파일 업로드가
> 불확실하므로 "트레이너가 회원·계약·수업기록을 넣어보는 것"까지만 기대할 것.
> 이걸 정식 경로로 승격하려면 `dart:io` 조건부 import 리팩터링이 선행돼야 한다.

### 8.2 그 외 베타 전 정리

- **Android release 서명이 debug 키** — `android/app/build.gradle.kts` 의 `TODO`. 안드로이드도 배포할 거면 필수.
- **`kAppVersion` 상수 수동 동기화** — `pubspec.yaml` 버전 올릴 때 같이 올려야 문의 추적이 어긋나지 않는다(`app_info.dart`).

---

## 9. 문서 연계

- `develop_plan.md` 1.12 / §8 — 배포 마일스톤 (본 문서가 그 상세)
- `social_login_plan.md` §2.2 / `social_login_console_setup.md` — 애플 로그인 요건·콘솔 절차
- `qa_regression_checklist.md` — iOS 한글 IME 등 회귀 점검
- `e2e_verification_script.md` — 기능 검증 대본(플랫폼 무관 항목은 재검증 불필요)
- `shipped.md` §3 — 지켜야 할 제약(가시성·의료 안전선·AI 원칙)
