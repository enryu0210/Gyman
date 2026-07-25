allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ---------------------------------------------------------------------------
// [PoC] camera_android_camerax 빌드 실패 회피 (AGP 9 / Gradle 9 조합)
//
// 증상: `:camera_android_camerax:compileReleaseJavaWithJavac` 가
//   "class file for androidx.concurrent.futures.CallbackToFutureAdapter not found"
//   로 깨진다.
//
// 원인: 플러그인 자바 코드가 CallbackToFutureAdapter 를 직접 쓰는데, 그 클래스는
//   플러그인이 선언한 `implementation("androidx.camera:camera-core")` 의 **전이**
//   의존성이다. AGP 9 는 전이 implementation 을 컴파일 클래스패스에 올리지 않아
//   javac 이 심볼을 못 찾는다(런타임엔 존재).
//
// 대응: 그 서브프로젝트에만 concurrent-futures 를 명시 주입한다.
//   ⚠ 상류(camera_android_camerax)가 고치면 제거할 임시 회피책이다.
// ---------------------------------------------------------------------------
subprojects {
    if (name == "camera_android_camerax") {
        afterEvaluate {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
