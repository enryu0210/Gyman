plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.gyman.gyman"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications(zonedSchedule)가 java.time 을 쓰므로
        // 구형 Android 대비 core library desugaring 필수.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // PoC 하네스를 프로덕션 앱과 **나란히** 설치하기 위한 분리.
        //   사용: flutter run -t lib/main_poc.dart -Ppoc=true   → com.gyman.poc
        //   평소: flutter build apk --debug                      → com.gyman.gyman (그대로)
        //
        // product flavor 를 쓰지 않은 이유: flavor 를 추가하면 Flutter 가 **모든** 빌드에
        // --flavor 를 요구해 CLAUDE.md 의 검증 명령(flutter build apk --debug)이 깨진다.
        // Gradle 프로퍼티는 안 넘기면 없는 것과 같아 기존 명령이 전부 그대로 산다.
        //
        // 이 분리가 없으면 PoC 빌드가 프로덕션 앱을 덮어쓴다 — 2026-07-27 에 로컬에서
        // 임시로 고쳤다가 커밋이 안 돼 사라졌던 설정이라, 이번엔 저장소에 남긴다.
        applicationId = if (project.hasProperty("poc")) "com.gyman.poc" else "com.gyman.gyman"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // core library desugaring 런타임 (flutter_local_notifications 요구).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
