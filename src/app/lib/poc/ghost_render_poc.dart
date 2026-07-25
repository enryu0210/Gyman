/// [PoC] 고스트 오버레이 실현성 검증 — 카메라 프리뷰 + 영상 동시 렌더.
/// docs/design_ghost_overlay.md §5 "PoC(선행, 필수)"
///
/// **무엇을 증명하려는가:**
///   `CameraPreview`(네이티브 텍스처)와 `VideoPlayer`(또 다른 네이티브 텍스처)를
///   한 화면에 겹쳐 그릴 때 **실기기에서 프레임이 나오는가.** 여기서 막히면
///   고스트 기능(4.7) 설계를 통째로 바꿔야 한다.
///
/// **왜 별도 진입점인가:** 프로덕션 라우터·화면을 전혀 건드리지 않는다.
///   `flutter run -t lib/main_poc.dart` 로만 뜬다. PoC 가 엎어져도 되돌릴 게 없다.
///
/// **측정 방법:** `SchedulerBinding.addTimingsCallback` 으로 실제 프레임의
///   build/raster 소요를 읽는다. 눈대중이 아니라 숫자로 판단하기 위함 —
///   **raster 가 16.7ms 를 넘기면 60fps 를 못 낸다.**
library;

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

class GhostRenderPoc extends StatefulWidget {
  const GhostRenderPoc({super.key});

  @override
  State<GhostRenderPoc> createState() => _GhostRenderPocState();
}

class _GhostRenderPocState extends State<GhostRenderPoc> {
  CameraController? _camera;
  VideoPlayerController? _video;
  String? _error;

  // ── 고스트 정렬 상태(G1 조작 모델을 그대로 시험한다) ──
  double _opacity = 0.35;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _flipX = true; // 전면 카메라는 거울상이라 기본 반전

  double _scaleStart = 1.0;
  Offset _offsetStart = Offset.zero;

  // ── 프레임 통계 ──
  final _rasterSamples = <double>[];
  double _rasterAvgMs = 0;
  double _rasterWorstMs = 0;
  int _jankFrames = 0;
  int _totalFrames = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _initCamera();
  }

  /// 프레임 타이밍 수집. raster 시간이 실제 병목(텍스처 합성)이라 그것만 본다.
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.rasterDuration.inMicroseconds / 1000.0;
      _rasterSamples.add(ms);
      _totalFrames++;
      // 60fps 기준 한 프레임 예산 16.7ms 초과 = jank.
      if (ms > 16.7) _jankFrames++;
      if (ms > _rasterWorstMs) _rasterWorstMs = ms;
    }
    // 최근 120프레임만 평균에 반영(순간 상태를 보기 위함).
    if (_rasterSamples.length > 120) {
      _rasterSamples.removeRange(0, _rasterSamples.length - 120);
    }
    final sum = _rasterSamples.fold<double>(0, (a, b) => a + b);
    _rasterAvgMs = _rasterSamples.isEmpty ? 0 : sum / _rasterSamples.length;
    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = '사용 가능한 카메라가 없습니다.');
        return;
      }
      // 전면 우선 — 회원이 화면을 보며 자세를 맞춰야 하므로(설계 §6.1).
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // medium: 녹화가 없으므로 화질보다 프레임 안정이 중요(설계 §2.1).
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) setState(() => _error = '카메라 초기화 실패: $e');
    }
  }

  /// 갤러리에서 영상을 골라 고스트로 얹는다.
  /// (실제 기능은 서명 URL 을 쓰지만, PoC 는 "두 텍스처 동시 렌더"만 증명하면 된다.)
  Future<void> _pickGhostVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    await _video?.dispose();
    final controller = VideoPlayerController.file(File(picked.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _video = controller);
      _resetStats();
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = '영상 로드 실패: $e');
    }
  }

  void _resetStats() {
    _rasterSamples.clear();
    _rasterWorstMs = 0;
    _jankFrames = 0;
    _totalFrames = 0;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _camera?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('PoC 1 · 카메라 + 영상 동시 렌더'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.white70)),
              ),
            )
          : Column(
              children: [
                Expanded(child: _buildStage()),
                _StatsPanel(
                  avgMs: _rasterAvgMs,
                  worstMs: _rasterWorstMs,
                  jank: _jankFrames,
                  total: _totalFrames,
                  hasGhost: _video != null,
                ),
                _buildControls(),
              ],
            ),
    );
  }

  /// 카메라(바닥) + 고스트 영상(반투명, 정렬 가능) 합성.
  Widget _buildStage() {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final vid = _video;

    return GestureDetector(
      // 핀치줌·드래그로 고스트만 움직인다(카메라는 고정) — G1 정렬 모델.
      onScaleStart: (_) {
        _scaleStart = _scale;
        _offsetStart = _offset;
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_scaleStart * d.scale).clamp(0.3, 3.0);
          _offset = _offsetStart + d.focalPointDelta;
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(cam),
          if (vid != null && vid.value.isInitialized)
            Transform.translate(
              offset: _offset,
              child: Transform.scale(
                scale: _scale,
                child: Transform.flip(
                  flipX: _flipX,
                  child: Opacity(
                    opacity: _opacity,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: vid.value.aspectRatio,
                        child: VideoPlayer(vid),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('불투명도', style: TextStyle(color: Colors.white70)),
              Expanded(
                child: Slider(
                  value: _opacity,
                  min: 0.05,
                  max: 1.0,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
              ),
              Text(_opacity.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _pickGhostVideo,
                icon: const Icon(Icons.video_library_outlined, size: 18),
                label: Text(_video == null ? '고스트 영상 선택' : '영상 교체'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _flipX = !_flipX),
                icon: const Icon(Icons.flip, size: 18),
                label: Text('좌우반전 ${_flipX ? "ON" : "OFF"}'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _scale = 1.0;
                  _offset = Offset.zero;
                }),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('정렬 초기화'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(_resetStats),
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('통계 리셋'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 프레임 통계 패널 — PoC 의 판정 근거.
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({
    required this.avgMs,
    required this.worstMs,
    required this.jank,
    required this.total,
    required this.hasGhost,
  });

  final double avgMs;
  final double worstMs;
  final int jank;
  final int total;
  final bool hasGhost;

  @override
  Widget build(BuildContext context) {
    // 평균 raster 가 16.7ms 를 넘으면 60fps 미달.
    final ok = avgMs > 0 && avgMs <= 16.7;
    final jankPct = total == 0 ? 0.0 : jank / total * 100;

    return Container(
      width: double.infinity,
      color: ok ? Colors.green.shade900 : Colors.orange.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasGhost ? '카메라 + 고스트 영상 (2 텍스처)' : '카메라만 (1 텍스처) — 영상을 얹어 비교하세요',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text('raster 평균 ${avgMs.toStringAsFixed(1)}ms  '
                '(60fps 예산 16.7ms) · 최악 ${worstMs.toStringAsFixed(1)}ms'),
            Text('jank ${jankPct.toStringAsFixed(1)}%  ($jank / $total 프레임)'),
          ],
        ),
      ),
    );
  }
}
