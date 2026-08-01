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
| **애플 계정 없이는 아무것도 못 해보나?** | **아니다.** 서명 없는 빌드(`--no-codesign`)·CocoaPods 해석·시뮬레이터 실행은 **계정 없이 클라우드 macOS 에서 지금 된다.** 계정이 필요한 건 "기기에 올리는 것"부터다 → 그래서 `codemagic.yaml` 에 계정 없이 도는 `ios-validate` 워크플로를 따로 뒀다(§3.4) |
| Mac 없이 배포 가능한가? | **가능.** 클라우드 macOS CI(Codemagic 등)에서 빌드 → TestFlight 업로드. Windows-only Flutter 개발자의 표준 경로 |
| 돈이 드는가? | **Apple Developer Program $99/년 필수.** 이건 우회로가 없다. CI 는 무료 티어로 시작 가능 |
| 지금 당장 iOS 빌드를 시도하면? | ~~폴더가 없다~~ → **2026-08-01 배선 완료.** 이제 막는 건 코드가 아니라 **macOS(빌드)와 애플 계정(서명·업로드)** 둘뿐이다 |
| 가장 급한 것 | **① Apple Developer Program 등록** — ②·③ 은 2026-08-01 에 끝났으므로 **이제 이것 하나가 유일한 크리티컬 패스**다 |
| 승인 기다리는 동안 쓰게 할 방법 | **웹 빌드가 통과한다**(2026-07-30 실측) → Safari 링크로 임시 사용 가능. 단 알림 미지원·파일 업로드 불확실 = **임시 우회로**(§8.1) |
| 최단 경로 | **TestFlight 내부 테스터(최대 100명)** 로 배포 — **베타 심사 없이 즉시 배포**되고, 애플 로그인(가이드라인 4.8)도 이 단계에선 강제되지 않는다. 단 내부 테스터는 App Store Connect 팀 사용자로 초대해야 한다(§4-3 주의) |

---

## 1. 현재 상태 실측 (2026-07-30)

전부 코드/파일 확인 결과다. 추정 아님.

| 항목 | 상태 | 근거 |
|------|------|------|
| iOS 플랫폼 폴더 | ✅ **생성 완료** (2026-08-01, `feat/ios-beta`) — Info.plist 권한 문구·URL scheme·Podfile 13.0·AppIcon 21종 배선까지 끝. **단 `.ipa` 빌드는 미검증**(macOS 부재) | §3.2 |
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
| ~~**B3**~~ | ~~`src/app/ios/` 미생성~~ | — | ✅ **해소 (2026-08-01)** — `flutter create --platforms=ios .` | 완료 |
| ~~**B4**~~ | ~~Info.plist 권한 문구 부재~~ | — | ✅ **해소 (2026-08-01)** — §3.1 키 전부 추가, XML 파싱 검증 | 완료 |
| **B5** | 애플 로그인 미구현 | 카카오·구글을 제공하므로 **가이드라인 4.8** 대상 → 정식 심사·외부 테스터에서 반려 위험 | ✅ **내부 테스터로 회피 확정**(§5 결정 2). 외부 테스터 전환 시 되살아난다 | 회피 완료 / 구현 시 1~2일+콘솔 |
| ~~**B6**~~ | ~~ML Kit 이 최소 iOS 15.5 강제~~ | — | ✅ **해소 (2026-08-01)** — `develop` 에 애초에 없어 분기만으로 해결(§5 결정 1) | 완료 |

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

### 3.2 그 외 코드 작업 — **전부 완료 (2026-08-01, `feat/ios-beta` 브랜치)**

- [x] `flutter create --platforms=ios .` — `ios/` 만 생성됨(다른 폴더 무변경)
- [x] **번들 ID `com.gyman.gyman`** — `--org com.gyman` 로 생성 시 자동 일치. Android 와 통일 확인
- [x] `ios/Podfile` `platform :ios, '13.0'` — Flutter 정본 템플릿 기반, 주석 한 줄만 해제.
      Xcode 프로젝트의 `IPHONEOS_DEPLOYMENT_TARGET` 도 13.0 이라 일치
- [x] **앱 아이콘/스플래시** — `ios: true` 전환 후 재생성. AppIcon 21종 생성, **전부 알파 없음** 확인
- [x] `CFBundleDisplayName` = `Gyman` (기본 생성값이 이미 맞음)
- [x] iOS 산출물 gitignore — `flutter create` 가 만든 `ios/.gitignore` 가 `Pods/`·`.symlinks/`·
      `xcuserdata`·`Generated.xcconfig`·`GeneratedPluginRegistrant.*` 를 이미 전부 커버. 추가 작업 없음
- [x] `codemagic.yaml` 커밋 (리포 루트)

> **검증 범위:** `flutter analyze` 무결점 · `flutter test` 343건 통과 · `flutter build apk --debug` 성공
> (아이콘 재생성이 안드로이드를 깨지 않았음을 확인). **`.ipa` 빌드는 macOS 부재로 미검증** — §3.4 참조.

#### 아이콘에서 실제로 걸린 문제 2건 (다음에 또 만난다)

1. **`remove_alpha_ios: true` 를 믿으면 안 된다.** `flutter_launcher_icons` 0.14.4 에서
   이 옵션 + `background_color_ios` 조합이 **녹색 채널을 터뜨린다** — 원본의 둥근 모서리
   곡선을 따라 `(23,254,28)` 같은 형광 녹색 픽셀이 좌상단에만 1201개 남았다(전수 검사로 발견).
   브랜드 볼트 라임(`#C6FF00` = 198,255,0)과도 다른 값이라 명백한 버그다.
   → **소스를 미리 평탄화**해 `assets/brand/icon_ios.png`(잉크 배경 위 알파 합성, 24bpp)로 만들고
   `image_path_ios` 로 지정. 알파 제거 기능은 쓰지 않는다.
2. **`icon_master.png` 를 iOS 에 그대로 주면 안 된다.** 모서리가 이미 둥글고 그 바깥이 투명한데,
   iOS 는 자체 squircle 마스크를 또 씌우므로 **이중 라운딩**이 된다. iOS 소스는 항상 풀블리드 정사각.

### 3.4 남은 것 — **애플 계정이 필요한 것과 아닌 것을 가른다**

`ios/` 폴더와 CI 설정은 "**CI 에 올릴 준비 완료**" 상태이지 "**빌드 검증 완료**"가 아니다.
그런데 **검증의 상당 부분은 애플 계정 없이 지금 할 수 있다** — 갈라지는 기준은
"빌드가 되느냐"(계정 불필요)와 "기기에 올리느냐"(계정 필요)다.

| 하려는 것 | Apple Developer Program | 근거 |
|---|---|---|
| **iOS 컴파일 검증** (`flutter build ios --no-codesign`) | ❌ **불필요** | 서명은 빌드 산출물에 붙이는 단계라 컴파일과 무관 |
| **CocoaPods 해석 + `Podfile.lock` 생성** | ❌ **불필요** | pub/pod 레지스트리만 씀 |
| **시뮬레이터 실행·스크린샷** | ❌ **불필요** | 레이아웃·세이프에어리어·라우팅 확인 가능 |
| 실제 아이폰에 설치 | ✅ 필요 | 무료 Apple ID(personal team)로도 되지만 **맥에 케이블로 물린 상태**여야 하고 프로파일이 7일마다 만료 → CI 로는 사실상 불가 |
| **TestFlight 배포** | ✅ 필요 | 예외 없음 |
| Ad Hoc 배포 | ✅ 필요 | 무료 계정에는 없는 배포 방식 |

→ 그래서 `codemagic.yaml` 에 워크플로를 **둘** 두었다.

| 워크플로 | 계정 | 언제 |
|---|---|---|
| `ios-validate` | 불필요 | **지금 바로.** Codemagic 가입 + 리포 연결만 하면 된다. 환경변수 그룹도 필요 없다(`.env` 를 `.env.example` 로 채움 — 컴파일만 확인하므로 실제 값이 불필요) |
| `ios-testflight` | 필요 | 승인 후 |

**`ios-validate` 를 먼저 통과시킬 것.** 그래야 첫 TestFlight 빌드가 깨졌을 때
원인이 "배선"인지 "서명"인지 갈린다. 여기서 나올 법한 실패는 전부 Windows 에서
미리 잡을 수 없던 것들이다 — 플러그인의 iOS 최소버전이 Podfile 13.0 과 안 맞거나,
Swift 버전 충돌이거나, `use_frameworks!` 와 특정 Pod 의 비호환.

| # | 그 뒤에 남는 것 | 왜 |
|---|-----------|----------------|
| 1 | `Podfile.lock` 커밋 | `ios-validate` 아티팩트로 받아서 커밋(재현 가능한 빌드에 필요) |
| 2 | `.ipa` 빌드·서명 | 계정 승인 후. 첫 성공까지 CI 로그 왕복이 보통 여러 번 |
| 3 | Codemagic 환경변수 그룹 2종 | `appstore` 그룹은 계정 선행 |
| 4 | 실기기 동작 (§7 재검증 8항목) | TestFlight 설치 후에만. **특히 1번 한글 IME 는 실기기 필수** — 시뮬레이터는 맥 키보드를 쓰면 iOS IME 조합 버그를 재현하지 못한다(소프트 키보드 강제 시 부분적으로만 유효) |

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

| # | 결정 | 선택지 | 결론 |
|---|------|--------|------|
| **1** | 베타 iOS 빌드에 `camera` + `google_mlkit_pose_detection` 을 넣을지 | (a) 제거 → 최소 iOS 13.0 (b) 유지 → 최소 15.5, 용량 증가 | ✅ **(a) 확정 (2026-08-01).** 단 "제거 작업"은 없었다 — **`develop` 에는 애초에 그 두 의존성이 없다.** 둘은 `poc/cv-track` 에서만 추가됐고 `lib/poc/` 4개 파일이 유일한 사용처다. 그래서 `develop` 에서 `feat/ios-beta` 를 분기하는 것으로 이 결정이 저절로 해결됐다. ⚠ 반대로 `poc/cv-track` 에서 이 의존성을 빼면 `lib/poc/` 가 컴파일 실패한다 |
| **2** | 애플 로그인을 베타에 포함할지 | (a) 내부 테스터로 가고 보류 (b) 지금 구현 | ✅ **(a) 보류 확정 (2026-08-01)** → 외부 테스터/정식 출시 전에 구현. 내부 테스터 100명은 트레이너 베타 규모에 충분하고 베타 심사가 없다. 단 §4-3 의 팀 사용자 초대 이슈를 감수해야 함 |
| **3** | 빌드 경로 | Codemagic / GitHub Actions / 원격 Mac / 중고 Mac | ✅ **Codemagic 확정 (2026-08-01)** — `codemagic.yaml` 작성 완료. 베타 사이클이 길어지면(크래시 수정 → 재업로드 반복) 중고 Mac 이 오히려 싸진다 |
| **4** | 안드로이드 베타를 병행할지 | 병행 / iOS 만 | **iOS 우선, 안드로이드는 검증용으로 유지.** 실기기 검증(Z Flip 3)은 계속 안드로이드로 하는 게 빠르다 |
| **5** | 지원/개인정보 URL 호스팅 | GitHub Pages / Supabase Storage 정적 / 기타 | GitHub Pages 가 무료·즉시. 심사 필수 항목이라 빠뜨리면 등록 자체가 막힌다 |

---

## 6. 실행 순서 (의존성 순)

```
[지금] 1. Apple Developer Program Enroll ────────────┐ ← ★ 유일한 크리티컬 패스
          ($99/년, 승인 며칠~2주, 우리가 단축 불가)   │   아직 안 걸었으면 오늘 걸 것
                                                     │
[완료] 2. ✅ 결정 1·2·3 확정 (§5)                    │  2026-08-01
       3. ✅ flutter create --platforms=ios .        │  feat/ios-beta 브랜치
       4. ✅ Info.plist 키 + Podfile 13.0            │
       5. ✅ 아이콘/스플래시 iOS 생성                 │
       6. ✅ codemagic.yaml                          │
                                                     │
[남음 · 계정 불필요 — 승인 기다리는 동안 할 것]        │
       7. Codemagic 가입 + 리포 연결               │
       8. ios-validate 워크플로 실행 ★             │  ← 배선 검증. 여기서 깨지면 고치고 반복
          → Podfile.lock 아티팩트 받아서 커밋       │
       9. 지원/개인정보 URL 게시 (§4-5)            │
                                                     │
[승인 후] 10. App ID·앱 생성 → API 키 발급 ◄─────────┘
         11. 환경변수 그룹 2종 등록 → ios-testflight 실행
         12. TestFlight 업로드 → 내부 테스터 초대
         13. §7 iOS 재검증 8항목 실행 (특히 1번 한글 IME — 실기기 필수)
         14. 트레이너 배포
```

> **지금 상태 한 줄 요약:** 리포 안에서 할 수 있는 iOS 배선은 끝났다.
> **애플 계정 승인을 기다리는 동안 7~9번을 할 수 있고, 그중 8번이 가장 값지다** —
> Windows 에서 원천적으로 검증 불가능했던 구간(CocoaPods·플러그인 iOS 호환·실제 컴파일)을
> 계정 없이 돈 한 푼 안 들이고 확인하는 유일한 방법이다.

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
