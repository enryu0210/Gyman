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
| 카메라+영상 동시 렌더 성능 | ⏳ **실기기 측정 대기** | 미판정 |
| ML Kit 정지사진 정확도 | ⏳ **실기기 측정 대기** | 미판정 |

**코드로 확인 가능한 건 전부 끝났고, 남은 둘은 실기기가 있어야 한다**(§4).

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

## 4. 실기기에서 확인해야 할 것 (남은 절반)

```bash
cd src/app
flutter run -t lib/main_poc.dart
```

### PoC 1 — 고스트 실현성 (가장 중요)
1. `PoC 1` 진입 → 카메라 프리뷰만 있는 상태에서 상단 통계 확인 → **raster 평균 기록**
2. `고스트 영상 선택` 으로 갤러리 영상 얹기 → `통계 리셋` → **raster 평균 다시 기록**
3. 핀치줌·드래그·좌우반전을 조작하며 값이 튀는지 확인
4. 2~3분 두고 **발열·프레임 저하** 확인

| 판정 | 기준 |
|---|---|
| ✅ 통과 | 영상 얹은 뒤 raster 평균 **≤ 16.7ms**, jank < 5% |
| ⚠ 조건부 | 16.7~33ms (30fps) — 프리뷰 해상도를 낮춰 재시도 |
| ❌ 실패 | 33ms 초과 또는 프리뷰가 멈춤 → **고스트 설계 재검토** |

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
2. `camera` 회피책을 develop 에 넣을 것인가 — PoC 1 통과 시 G1 과 함께.
3. **PoC 3(영상 프레임 추출, 4.6/L3)은 아직 안 했다.** 의존성이 또 필요하고 가장 먼 트랙이라,
   앞의 둘이 통과한 뒤에 본다.

---

## 6. 되돌리는 법

PoC 가 엎어지면 지울 것:
- `src/app/lib/main_poc.dart`, `src/app/lib/poc/`
- `pubspec.yaml` 의 `camera`, `google_mlkit_pose_detection`
- `android/build.gradle.kts` 의 `camera_android_camerax` 주입 블록
- `AndroidManifest.xml` 의 CAMERA 권한

브랜치째 버려도 develop 은 영향 없다.
