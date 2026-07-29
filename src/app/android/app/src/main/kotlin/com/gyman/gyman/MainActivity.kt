package com.gyman.gyman

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // [PoC 3] 영상 프레임 추출 채널. PoC 전용이라 프로덕션 진입점(main.dart)에서는
    // 아무도 호출하지 않는다 — 채널이 열려 있어도 동작에 영향이 없다.
    // PoC 가 엎어지면 이 클래스와 VideoFrameExtractor.kt 만 지우면 원복된다.
    private var frameExtractor: VideoFrameExtractor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val extractor = VideoFrameExtractor(cacheDir)
        frameExtractor = extractor

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractFrames" -> {
                        val path = call.argument<String>("videoPath")
                        if (path.isNullOrEmpty()) {
                            result.error("BAD_ARGS", "videoPath 가 비었습니다", null)
                            return@setMethodCallHandler
                        }
                        extractor.extract(
                            videoPath = path,
                            sampleFps = call.argument<Double>("sampleFps") ?: 5.0,
                            maxWidth = call.argument<Int>("maxWidth") ?: 640,
                            exactSeek = call.argument<Boolean>("exactSeek") ?: false,
                            maxFrames = call.argument<Int>("maxFrames") ?: 120,
                            result = result,
                        )
                    }
                    // [PoC 2-B] 검증 사진 세트를 넣어둔 앱 내부 저장소 경로.
                    //
                    // 왜 Dart 쪽에서 경로를 만들지 않는가: /sdcard/Android/data/<pkg>
                    // 는 Android 11+ 에서 raw path 접근이 막혀 Permission denied 가
                    // 난다(2026-07-29 실측). 앱 내부 저장소는 제약이 없고, 경로를
                    // 아는 건 네이티브뿐이라 여기서 돌려준다.
                    // path_provider 를 쓰면 정석이지만 PoC 하나 때문에 의존성을
                    // 늘리지 않는다(CLAUDE.md).
                    "getFilesDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        frameExtractor?.dispose()
        frameExtractor = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "gyman/poc_video_frames"
    }
}
