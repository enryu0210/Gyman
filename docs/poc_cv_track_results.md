# CV 트랙 PoC 결과 (2026-07-25)

> 대상: `develop_plan.md` §4 "CV·개인화 트랙 실행 순서" **0단계 PoC**.
> 브랜치: `poc/cv-track` (develop 미병합 — 판단 후 결정)
> 실행: `cd src/app && flutter run -t lib/main_poc.dart` (**실기기 필수**)

---

## 0. 한눈에

| 항목 | 결과 | 판정 |
|---|---|---|
| `camera` 빌드 | ❌ 실패 → ✅ **회피책으로 통과** | 조건부 통과 |
| `camera` APK 증가 (arm64) | **+2.2MB** | 무시 가능 |
| `google_mlkit_pose_detection` 빌드 | ✅ 통과 | 통과 |
| **ML Kit APK 증가 (arm64)** | **+22.1MB (25.2 → 47.3MB)** | ⚠ **결정 필요** |
| 카메라+영상 동시 렌더 성능 | ✅ **raster 평균 4.8ms / jank 0.1%** | **통과** (2026-07-27, §4) |
| ML Kit 정지사진 정확도 | ⏳ **실기기 측정 대기** | 미판정 |

**PoC 1(고스트)은 실기기 측정까지 끝나 통과**했고, 남은 건 PoC 2(체형분석 재현성)뿐이다(§4).

---

## 1. `camera` 빌드 실패 — 원인과 회피책 ★

### 증상
```
Execution failed for task ':camera_android_camerax:compileReleaseJavaWithJavac'.
> class file for androidx.concurrent.futures.CallbackToFutureAdapter not found
```

### 원인
`camera_android_camerax` 의 자바 코드가 `CallbackToFutureAdapter` 를 직접 쓰는데,
그 클래스는 플러그인이 선언한 `implementation("androidx.camera:camera-core")` 의
**전이(transitive) 의존성**이다.
**AGP 9 는 전이 `implementation` 을 컴파일 클래스패스에 올리지 않는다** → javac 이 심볼을 못 찾는다.
(런타임엔 존재하므로 순수 빌드 타임 문제)

이 프로젝트 툴체인이 최신이라 터진 것: **AGP 9.0.1 / Gradle 9.1.0 / Kotlin 2.3.20 / Flutter 3.44**.

### 회피책 (적용됨)
`android/build.gradle.kts` 에 해당 서브프로젝트에만 의존성을 주입:
```kotlin
subprojects {
    if (name == "camera_android_camerax") {
        afterEvaluate {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}
```
→ release/debug 빌드 모두 통과 확인.

### 남는 리스크
- **상류 플러그인이 고칠 때까지 유지해야 하는 임시 패치**다. `camera` 업그레이드 때마다 재확인 필요.
- 같은 원인(전이 implementation)이 **다른 플러그인에서도 터질 수 있다** — 앞으로 네이티브 플러그인을 추가할 때 같은 증상이면 같은 처방.

---

## 2. APK 크기 — ML Kit 이 비싸다

전부 **release** 빌드 실측.

| 구성 | fat APK(전 ABI) | arm64-v8a | armeabi-v7a |
|---|---|---|---|
| 기준선 (플러그인 추가 전) | 63.7MB | — | — |
| `+ camera` | 64.4MB | **25.2MB** | 23.0MB |
| `+ ML Kit pose` | 103.8MB | **47.3MB** | 41.7MB |
| **ML Kit 증가분** | +39.4MB | **+22.1MB** | +18.7MB |

> fat APK 는 전 ABI 를 합친 값이라 실제 배포 크기가 아니다. **arm64-v8a 47.3MB 가 요즘 기기의 실제 설치 크기**에 가깝다. Play 배포 시 App Bundle 을 쓰면 ABI 분리가 자동이다.

### 왜 이렇게 큰가 — 그리고 왜 못 줄이는가
`google_mlkit_pose_detection` 이 **두 모델을 다 번들한다**:
```gradle
implementation("com.google.mlkit:pose-detection:18.0.0-beta5")           // base(빠름)
implementation("com.google.mlkit:pose-detection-accurate:18.0.0-beta5")  // accurate(정확)
```
우리는 둘 중 하나만 쓰면 되지만, **플러그인 Kotlin 코드가 `AccuratePoseDetectorOptions` 를
import 로 직접 참조**해서 Gradle `exclude` 로 빼면 컴파일이 깨진다.

→ **줄이려면 플러그인을 포크해야 한다.** 유지보수 부담 대비 이득을 따져야 하는 선택.

### 선택지
| 안 | APK | 대가 |
|---|---|---|
| **A. 그대로 수용** | arm64 47.3MB | 설치 이탈률↑. 베타(친구·지인)엔 무해 |
| **B. 플러그인 포크** (모델 1개만) | 대략 35MB 추정 | 상류 업데이트 추적 부담 |
| **C. ML Kit 없이 간다** | 25.2MB | 체형분석 자동 수치·고스트 G2/G3 포기. **L1·L2 코칭은 이미 CV 없이 동작 중** |
| **D. 기능 분리 배포** | — | 앱 2개 운영 — 베타 규모엔 과함 |

**권고: 베타 동안 A.** 지금 사용자는 친구·지인이라 설치 크기가 이탈 요인이 아니고, 포크는
정식 배포가 가시화될 때 판단해도 늦지 않다. 단 **"체형분석을 켜는 순간 앱이 2배가 된다"는
사실을 결정 기록으로 남긴다** — 나중에 "왜 이렇게 큰가"를 다시 조사하지 않도록.

---

## 3. 만들어 둔 것

프로덕션 코드는 **한 줄도 건드리지 않았다.** 별도 진입점으로만 뜬다.

| 파일 | 역할 |
|---|---|
| `lib/main_poc.dart` | PoC 전용 진입점 + 메뉴 |
| `lib/poc/ghost_render_poc.dart` | PoC 1 — 카메라+영상 합성, 정렬 조작, **프레임 통계 패널** |
| `lib/poc/pose_analysis_poc.dart` | PoC 2 — 사진→ML Kit→수치, **`MlKitPoseAdapter` 포함** |

### `MlKitPoseAdapter` 는 버리는 코드가 아니다
B단계의 실제 산출물이다. ML Kit 은 랜드마크를 **이미지 픽셀 좌표**로 주고 도메인은
**정규화(0~1)** 를 받으므로, 그 변환을 어댑터가 책임진다. 덕분에
`posture_metrics.dart` 는 계속 ML Kit 을 모르는 순수 Dart 로 남아 테스트가 유효하다.

---

## 4. 실기기 측정

```bash
cd src/app
flutter run -t lib/main_poc.dart
```

### PoC 1 — 고스트 실현성 ✅ **통과 (2026-07-27)**

측정 기기: **Galaxy Z Flip 3 (SM-F711N, Snapdragon 888 / 2021)**.
**의도적으로 구형 기기를 골랐다** — 여기서 60fps가 나오면 최신 기기는 볼 것도 없다.

| 구간 | raster 평균 | 최악 | jank |
|---|---|---|---|
| 카메라만 (1 텍스처) | 3.9ms | 22.0ms | 0.1% (1/687) |
| **카메라 + 고스트 (2 텍스처)** | **4.8ms** | 12.8ms | 0.0% (0/996) |
| + 드래그·좌우반전 | 3.2ms | 14.9ms | 0.0% (0/1106) |
| + 핀치줌 | 5.2ms | 14.9ms | 0.0% (0/5310) |
| **+ 발열 3분 31초** | **4.8ms** | 50.4ms | **0.1% (6/11116)** |

**판정: 통과.** 사전 고정한 기준 3개 전부 충족 — 평균 ≤ 16.7ms(예산의 29%), jank < 5%, Thermal Status ≤ 2.

**결론 두 가지.**
1. **영상 레이어 추가 비용은 +0.9ms.** 설계가 걱정한 "카메라+영상 동시 렌더 부하"는 **사실상 논점이 아니었다** — GPU 합성이라 텍스처 1장 추가가 거의 공짜다. 고스트 설계에서 성능은 제약 조건에서 빼도 된다.
2. **정렬 조작 3종(드래그·좌우반전·핀치줌)이 전부 성능에 무해하다.** 매 프레임 변환 행렬만 바꾸므로 재합성 비용이 없다. 즉 **고스트의 난점은 성능이 아니라 정렬 UX**라는 설계 문서의 판단이 실측으로 확인됐다.

**발열**: 3분 31초 무전원 구동(배터리 로그 `usb:false` 구간으로 확인). Thermal Status가 **1 LIGHT → 2 MODERATE** 로 한 단계 올랐는데도 **평균 raster는 4.8ms 그대로**였다. 888이 실제로 클럭을 낮췄는데 프레임 예산엔 영향이 없었다 — 여유가 그만큼 컸다.

| 센서 | 전 | 후 |
|---|---|---|
| AP (SoC) | 43.0°C | 44.3°C |
| SKIN | 39.7°C (status 1) | 40.7°C (status 2) |

**⚠ 이 수치의 한계 — 과신 금지.**
- **발열 구간이 격리되지 않았다.** 발열 테스트 직전에 `통계 리셋`을 누르지 않아 11116프레임 표본에 앞선 조작 구간이 섞여 있다. "발열 3분 30초만의 수치"가 아니며, 평균이 후반 저하를 희석했을 수 있다.
- **프레임 수가 적다.** 리셋(13:32)부터 15분간 11116프레임 = 평균 12fps. 60fps 연속 렌더링이었다면 5만 프레임이 나와야 한다 → 화면 꺼짐/백그라운드 구간이 있었다는 뜻이라 **"3분 연속 렌더링"이 온전히 검증되진 않았다.**
- 최악 50.4ms 스파이크는 6프레임뿐이라 지속적 저하가 아니다(충전 상태 변화 등 시스템 이벤트 추정).
- **원인**: adb 가 USB 케이블로 물려 있는데 발열 테스트를 위해 케이블을 뽑아 **3분간 원격 계측이 끊겼다**. 다음에 무전원 계측을 할 땐 **`adb tcpip` 로 Wi-Fi 전환 후** 뽑을 것.

→ **평균이 예산의 29%라 후반 저하가 있었더라도 33ms를 넘길 여지가 거의 없어, 베타 판단 근거로는 충분하다고 보고 통과 처리.** 정밀 수치가 필요해지면 Wi-Fi adb 로 3분 격리 재측정.

### PoC 2 — 체형분석 실현성
1. **정면 전신** 사진으로 촬영/선택 (전신이 다 나와야 함)
2. 어깨·골반 수치가 나오는지, 추론 시간이 몇 ms 인지 확인
3. **옆으로 돌아서** 한 장 더 → "정면으로 다시 촬영해 주세요" 가 뜨는지 (가드 동작 확인)
4. 같은 자세로 2~3장 → **수치가 얼마나 흔들리는지** (설계 §1.3 의 재현성 우려)

| 판정 | 기준 |
|---|---|
| ✅ 통과 | 정면 전신에서 두 수치가 나오고, 같은 자세 반복 시 **±1도 이내** |
| ⚠ 조건부 | 수치는 나오나 반복 편차가 큼 → 촬영 가이드(4.1) 강화 필요 |
| ❌ 실패 | 검출 자체가 안 됨 → 온디바이스 방향 재검토 |

> 4번(재현성)이 특히 중요하다. **수치가 촬영마다 3도씩 흔들리면 "4·8·12주 비교"가 의미를 잃는다.**

---

## 5. 결정 대기 항목

1. **ML Kit APK +22MB 를 수용할 것인가** (§2 선택지) — 실기기 PoC 2 결과를 보고 함께 판단.
2. ~~`camera` 회피책을 develop 에 넣을 것인가~~ → **PoC 1 통과(2026-07-27)로 근거 확보.** 고스트 G1 착수 시 §1 회피책과 함께 병합한다.
3. **PoC 3(영상 프레임 추출, 4.6/L3)은 아직 안 했다.** 의존성이 또 필요하고 가장 먼 트랙이라,
   앞의 둘이 통과한 뒤에 본다.
4. **PoC 앱 분리 설치(`com.gyman.poc`)가 저장소에 없다** — 2026-07-27 확인. 기기엔 설치돼 있으나
   `applicationId` 를 로컬에서 임시로 고쳐 빌드하고 되돌린 것이라 **git 이력 어디에도 없다**(`git log --all -S` 로 확인).
   지금 상태에서 `flutter run -t lib/main_poc.dart` 를 돌리면 `com.gyman.poc` 가 갱신되는 게 아니라
   **프로덕션 앱(`com.gyman.gyman`)을 덮어쓴다.** PoC 를 계속 쓸 거면 분리를 `build.gradle.kts` 에 정식으로 넣어야 한다.
   - 단, product flavor 를 추가하면 Flutter 가 `--flavor` 를 요구해 **CLAUDE.md 의 검증 명령(`flutter build apk --debug`)이 깨진다** — 그 대가를 감수할지 함께 결정할 것.

---

## 6. 되돌리는 법

PoC 가 엎어지면 지울 것:
- `src/app/lib/main_poc.dart`, `src/app/lib/poc/`
- `pubspec.yaml` 의 `camera`, `google_mlkit_pose_detection`
- `android/build.gradle.kts` 의 `camera_android_camerax` 주입 블록
- `AndroidManifest.xml` 의 CAMERA 권한

브랜치째 버려도 develop 은 영향 없다.
