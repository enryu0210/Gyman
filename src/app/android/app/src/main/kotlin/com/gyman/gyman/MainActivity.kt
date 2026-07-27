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
