package com.gyman.gyman

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * [PoC 3] 영상에서 표본 프레임을 뽑는 경로가 성립하는지 검증한다.
 * `docs/design_class_video_tracking.md` §7 "미해결 결정 #1" 의 답을 내기 위한 코드.
 *
 * **왜 새 플러그인을 안 썼는가**
 * Android 내장 [MediaMetadataRetriever] 를 직접 호출한다. 의존성 추가는 늦을수록 좋고
 * (CLAUDE.md), camera 플러그인에서 이미 AGP 9 전이 의존성 지뢰를 밟았기 때문에
 * 네이티브 플러그인을 하나 더 늘리는 쪽이 오히려 리스크가 크다고 봤다.
 *
 * **이 PoC 의 진짜 질문은 "되는가"가 아니라 "어느 모드가 쓸 만한가"다.**
 * [MediaMetadataRetriever] 의 두 탐색 모드는 성격이 정반대다:
 *   - `OPTION_CLOSEST_SYNC` : 키프레임만 본다 → **빠르지만 시점이 부정확**하다.
 *     키프레임 간격이 2초인 영상에서 5fps 로 요청하면 **같은 프레임이 10번 나온다.**
 *   - `OPTION_CLOSEST`      : 요청 시점의 실제 프레임 → **정확하지만 느리다.**
 *     직전 키프레임부터 순차 디코딩해야 하기 때문.
 *
 * 그래서 두 모드를 같은 영상에 돌려 **소요 시간과 '실제로 서로 다른 프레임 수'**를
 * 함께 잰다. 중복 판별은 비트맵 픽셀 해시로 한다 — MediaMetadataRetriever 는
 * 반환된 프레임의 실제 타임스탬프를 알려주지 않아서, 중복 여부를 알 방법이 이것뿐이다.
 */
class VideoFrameExtractor(private val cacheDir: File) {

    // MediaMetadataRetriever 는 블로킹 호출이라 UI 스레드에서 돌리면 앱이 멈춘다.
    // 코루틴을 쓰지 않은 이유: kotlinx-coroutines 는 이 모듈의 직접 의존성이 아니고,
    // 전이 의존성에 기대는 건 AGP 9 에서 깨진다는 걸 이미 겪었다.
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * [videoPath] 를 [sampleFps] 간격으로 훑어 프레임을 뽑는다.
     *
     * 프레임은 채널로 넘기지 않고 **JPEG 파일로 저장한 뒤 경로만 반환**한다.
     * 프레임 수십 장의 바이트를 플랫폼 채널로 실어 나르면 그 직렬화 비용이
     * 추출 시간을 덮어써서, 정작 재려던 값이 오염되기 때문이다.
     * (실제 기능에서도 ML Kit 은 파일 경로를 그대로 받는다 — PoC 2 와 같은 경로)
     */
    fun extract(
        videoPath: String,
        sampleFps: Double,
        maxWidth: Int,
        exactSeek: Boolean,
        maxFrames: Int,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            try {
                val payload = runExtraction(videoPath, sampleFps, maxWidth, exactSeek, maxFrames)
                mainHandler.post { result.success(payload) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("EXTRACT_FAILED", e.message, e.stackTraceToString())
                }
            }
        }
    }

    private fun runExtraction(
        videoPath: String,
        sampleFps: Double,
        maxWidth: Int,
        exactSeek: Boolean,
        maxFrames: Int,
    ): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        // 모드별 출력이 섞이지 않게 실행마다 전용 폴더를 쓰고 비운다.
        val outDir = File(cacheDir, if (exactSeek) "poc_frames_exact" else "poc_frames_sync")
        outDir.deleteRecursively()
        outDir.mkdirs()

        try {
            retriever.setDataSource(videoPath)

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?: throw IllegalStateException("영상 길이를 읽지 못했습니다")

            val stepMs = (1000.0 / sampleFps).toLong().coerceAtLeast(1L)
            // 긴 영상에서 폭주하지 않도록 상한을 둔다. 상한에 걸렸는지는 Dart 로 알린다.
            val plannedCount = ((durationMs / stepMs) + 1).toInt()
            val frameCount = minOf(plannedCount, maxFrames)

            val option = if (exactSeek) {
                MediaMetadataRetriever.OPTION_CLOSEST
            } else {
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            }

            val frames = mutableListOf<Map<String, Any>>()
            val totalStart = System.nanoTime()

            for (i in 0 until frameCount) {
                val requestedMs = i * stepMs
                val frameStart = System.nanoTime()

                // getScaledFrameAtTime 은 축소된 크기로 디코딩해서 더 빠르다(API 27+).
                // 구버전에서는 전체 크기로 받은 뒤 직접 축소한다 — 결과는 같고 속도만 다르다.
                val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    // 이 API 는 종횡비를 유지한 채 주어진 상자 안에 맞춰 축소한다.
                    // 세로 영상까지 상자에 들어오도록 높이는 넉넉히 잡는다 —
                    // 실제로 나온 크기는 아래에서 그대로 Dart 에 보고하므로 추측이 남지 않는다.
                    retriever.getScaledFrameAtTime(
                        requestedMs * 1000, option, maxWidth, maxWidth * 2,
                    )
                } else {
                    retriever.getFrameAtTime(requestedMs * 1000, option)?.let { full ->
                        scaleDown(full, maxWidth)
                    }
                }

                if (bitmap == null) {
                    // 프레임을 못 뽑는 시점이 있어도 전체를 실패시키지 않는다 —
                    // "몇 개나 실패하는가"도 실현성 판단의 일부다.
                    frames.add(
                        mapOf(
                            "index" to i,
                            "requestedMs" to requestedMs,
                            "ok" to false,
                            "elapsedMs" to (System.nanoTime() - frameStart) / 1_000_000.0,
                        ),
                    )
                    continue
                }

                val file = File(outDir, "frame_%04d.jpg".format(i))
                FileOutputStream(file).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }

                frames.add(
                    mapOf(
                        "index" to i,
                        "requestedMs" to requestedMs,
                        "ok" to true,
                        "path" to file.absolutePath,
                        "width" to bitmap.width,
                        "height" to bitmap.height,
                        "hash" to pixelHash(bitmap),
                        "elapsedMs" to (System.nanoTime() - frameStart) / 1_000_000.0,
                    ),
                )
                bitmap.recycle()
            }

            val totalMs = (System.nanoTime() - totalStart) / 1_000_000.0

            return mapOf(
                "durationMs" to durationMs,
                "requestedCount" to frameCount,
                "plannedCount" to plannedCount,
                "cappedByLimit" to (plannedCount > maxFrames),
                "totalMs" to totalMs,
                "exactSeek" to exactSeek,
                "frames" to frames,
            )
        } finally {
            // close() 는 API 29+ 라 호환을 위해 release() 를 쓴다.
            retriever.release()
        }
    }

    /** 종횡비를 유지하며 [maxWidth] 이하로 줄인다. */
    private fun scaleDown(source: Bitmap, maxWidth: Int): Bitmap {
        if (source.width <= maxWidth) return source
        val ratio = maxWidth.toDouble() / source.width
        val scaled = Bitmap.createScaledBitmap(
            source, maxWidth, (source.height * ratio).toInt(), true,
        )
        if (scaled != source) source.recycle()
        return scaled
    }

    /**
     * 서로 다른 프레임인지 판별하기 위한 값싼 해시.
     *
     * 전체 픽셀을 읽으면 그 비용이 추출 시간 측정을 오염시키므로 격자로 성긴 표본만 본다.
     * 목적이 "완전히 같은 프레임인가"이므로 이 정도면 충분하다 —
     * 압축 노이즈가 없는 동일 비트맵은 표본 픽셀도 정확히 같다.
     */
    private fun pixelHash(bitmap: Bitmap): Int {
        var hash = 17
        val stepX = (bitmap.width / 16).coerceAtLeast(1)
        val stepY = (bitmap.height / 16).coerceAtLeast(1)
        var y = 0
        while (y < bitmap.height) {
            var x = 0
            while (x < bitmap.width) {
                hash = hash * 31 + bitmap.getPixel(x, y)
                x += stepX
            }
            y += stepY
        }
        return hash
    }

    fun dispose() {
        executor.shutdown()
    }
}
