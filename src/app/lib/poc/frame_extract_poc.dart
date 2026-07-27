/// [PoC 3] 영상 → 표본 프레임 → ML Kit 경로가 성립하는지 검증한다.
/// `docs/design_class_video_tracking.md` §7 "미해결 결정 #1" / §8 최상위 리스크.
///
/// **무엇을 증명하려는가**
///   1. `video_player` 가 못 주는 표본 프레임을 네이티브로 뽑을 수 있는가
///   2. 뽑은 프레임이 **서로 다른 프레임인가** (키프레임 모드의 함정 확인)
///   3. 그 프레임을 ML Kit 에 그대로 넣어 인물 위치가 나오는가
///   4. **2분 영상 한 편을 처리하는 데 몇 초 걸리는가** ← 트레이너 대기 UX 를 가르는 값
///
/// 여기서 막히면 4.6(자동 프레이밍)과 4.8 L3(자동 검출)이 통째로 재설계다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;
import 'package:image_picker/image_picker.dart';

/// 네이티브 [VideoFrameExtractor] 와 이어지는 채널.
const _channel = MethodChannel('gyman/poc_video_frames');

/// 한 번의 추출 실행 결과. 네이티브가 준 raw map 을 읽기 좋은 형태로 정리한다.
class ExtractionRun {
  ExtractionRun({
    required this.exactSeek,
    required this.durationMs,
    required this.requestedCount,
    required this.plannedCount,
    required this.cappedByLimit,
    required this.totalMs,
    required this.frames,
  });

  final bool exactSeek;
  final int durationMs;
  final int requestedCount;
  final int plannedCount;
  final bool cappedByLimit;
  final double totalMs;
  final List<Map<String, dynamic>> frames;

  factory ExtractionRun.fromNative(Map<dynamic, dynamic> raw) {
    return ExtractionRun(
      exactSeek: raw['exactSeek'] as bool,
      durationMs: (raw['durationMs'] as num).toInt(),
      requestedCount: (raw['requestedCount'] as num).toInt(),
      plannedCount: (raw['plannedCount'] as num).toInt(),
      cappedByLimit: raw['cappedByLimit'] as bool,
      totalMs: (raw['totalMs'] as num).toDouble(),
      frames: (raw['frames'] as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList(),
    );
  }

  Iterable<Map<String, dynamic>> get okFrames =>
      frames.where((f) => f['ok'] == true);

  int get okCount => okFrames.length;
  int get failCount => frames.length - okCount;

  /// **이 PoC 의 핵심 지표.** 뽑힌 프레임 중 실제로 내용이 다른 것의 개수.
  ///
  /// 키프레임 모드는 요청 시점과 무관하게 같은 키프레임을 반복해서 준다.
  /// "50장 뽑았다"가 아니라 "그중 5장만 서로 다르다"면 5fps 표본추출이 성립하지 않는다.
  int get distinctCount => okFrames.map((f) => f['hash'] as int).toSet().length;

  double get msPerFrame => okCount == 0 ? 0 : totalMs / okCount;

  /// 프레임당 실측 시간으로 **전체 영상 처리 시간**을 추정한다.
  /// 상한(maxFrames)에 걸려 일부만 뽑았을 때 실제 비용을 가늠하기 위한 값.
  double get projectedFullMs => msPerFrame * plannedCount;
}

class FrameExtractPoc extends StatefulWidget {
  const FrameExtractPoc({super.key});

  @override
  State<FrameExtractPoc> createState() => _FrameExtractPocState();
}

class _FrameExtractPocState extends State<FrameExtractPoc> {
  static const _sampleFps = 5.0;
  static const _maxWidth = 640;
  static const _maxFrames = 120;

  String? _videoPath;
  String _status = '영상을 골라 시작하세요.';
  bool _busy = false;

  ExtractionRun? _syncRun;
  ExtractionRun? _exactRun;

  // ML Kit 결과
  int? _mlkitFrames;
  int? _mlkitDetected;
  double? _mlkitTotalMs;

  /// 영상 프레임용 설정. 정지사진(PoC 2)과 다르게 **stream + base** 를 쓴다 —
  /// 4.6 이 필요한 건 정밀한 관절 각도가 아니라 **인물의 위치(bbox)** 뿐이라
  /// 정확도보다 속도가 중요하고, 프레임 수가 많아 누적 비용이 크기 때문이다.
  final _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.stream,
      model: mlkit.PoseDetectionModel.base,
    ),
  );

  @override
  void dispose() {
    _detector.close();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _videoPath = picked.path;
      _status = '영상 선택됨. "추출 실행" 을 누르세요.';
      _syncRun = null;
      _exactRun = null;
      _mlkitFrames = null;
      _mlkitDetected = null;
      _mlkitTotalMs = null;
    });
  }

  Future<ExtractionRun> _runExtraction({required bool exactSeek}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'extractFrames',
      {
        'videoPath': _videoPath,
        'sampleFps': _sampleFps,
        'maxWidth': _maxWidth,
        'exactSeek': exactSeek,
        'maxFrames': _maxFrames,
      },
    );
    if (raw == null) throw StateError('네이티브가 빈 결과를 반환했습니다');
    return ExtractionRun.fromNative(raw);
  }

  /// 두 모드를 같은 영상에 돌려 비교한다 — 어느 쪽이 쓸 만한지가 이 PoC 의 결론이다.
  Future<void> _extractBoth() async {
    if (_videoPath == null) return;
    setState(() {
      _busy = true;
      _status = '키프레임 모드 추출 중…';
    });

    try {
      final sync = await _runExtraction(exactSeek: false);
      setState(() {
        _syncRun = sync;
        _status = '정확 시점 모드 추출 중… (느릴 수 있습니다)';
      });

      final exact = await _runExtraction(exactSeek: true);
      setState(() {
        _exactRun = exact;
        _status = '추출 완료. ML Kit 를 이어서 돌려보세요.';
        _busy = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = '추출 실패: ${e.code} ${e.message}';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _status = '추출 실패: $e';
        _busy = false;
      });
    }
  }

  /// 뽑은 프레임을 ML Kit 에 그대로 넣어 **경로 전체가 이어지는지** 확인한다.
  /// 정확 시점 모드 결과를 쓰는 이유: 실제 기능이 쓸 프레임이 그쪽이기 때문.
  Future<void> _runMlKit() async {
    final run = _exactRun ?? _syncRun;
    if (run == null) return;

    setState(() {
      _busy = true;
      _status = 'ML Kit 처리 중…';
    });

    final sw = Stopwatch()..start();
    var detected = 0;
    var processed = 0;

    try {
      for (final frame in run.okFrames) {
        final poses = await _detector.processImage(
          mlkit.InputImage.fromFilePath(frame['path'] as String),
        );
        processed++;
        if (poses.isNotEmpty) detected++;
      }
      sw.stop();

      setState(() {
        _mlkitFrames = processed;
        _mlkitDetected = detected;
        _mlkitTotalMs = sw.elapsedMilliseconds.toDouble();
        _status = 'ML Kit 완료.';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _status = 'ML Kit 실패: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PoC 3 · 영상 → 프레임 → ML Kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '표본 ${_sampleFps.toStringAsFixed(0)}fps · 최대 폭 ${_maxWidth}px · '
                '상한 $_maxFrames 프레임\n\n'
                '핵심은 "몇 장 뽑혔나"가 아니라 "서로 다른 프레임이 몇 장인가" 입니다. '
                '키프레임 모드는 같은 프레임을 반복해서 줄 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickVideo,
                icon: const Icon(Icons.video_library_outlined, size: 18),
                label: const Text('영상 선택'),
              ),
              FilledButton.icon(
                onPressed: _busy || _videoPath == null ? null : _extractBoth,
                icon: const Icon(Icons.grid_on_outlined, size: 18),
                label: const Text('추출 실행 (두 모드)'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy || (_syncRun == null && _exactRun == null)
                    ? null
                    : _runMlKit,
                icon: const Icon(Icons.accessibility_new_outlined, size: 18),
                label: const Text('ML Kit 이어서'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (_syncRun != null) _runCard('키프레임 모드 (CLOSEST_SYNC)', _syncRun!),
          if (_exactRun != null) _runCard('정확 시점 모드 (CLOSEST)', _exactRun!),
          if (_mlkitFrames != null) _mlkitCard(),
          if (_exactRun != null) _framePreview(_exactRun!),
        ],
      ),
    );
  }

  Widget _runCard(String title, ExtractionRun run) {
    final distinctRatio =
        run.okCount == 0 ? 0.0 : run.distinctCount / run.okCount * 100;
    // 서로 다른 프레임이 절반도 안 되면 그 모드로는 표본추출이 성립하지 않는다.
    final usable = distinctRatio >= 90;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  usable ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const Divider(),
            _row('영상 길이', '${(run.durationMs / 1000).toStringAsFixed(1)}초'),
            _row('요청/계획 프레임', '${run.requestedCount} / ${run.plannedCount}'
                '${run.cappedByLimit ? " (상한 걸림)" : ""}'),
            _row('성공 / 실패', '${run.okCount} / ${run.failCount}'),
            _row(
              '★ 서로 다른 프레임',
              '${run.distinctCount} (${distinctRatio.toStringAsFixed(0)}%)',
            ),
            _row('총 소요', '${run.totalMs.toStringAsFixed(0)}ms'),
            _row('프레임당', '${run.msPerFrame.toStringAsFixed(1)}ms'),
            _row(
              '전체 영상 환산',
              '${(run.projectedFullMs / 1000).toStringAsFixed(1)}초',
            ),
          ],
        ),
      ),
    );
  }

  Widget _mlkitCard() {
    final frames = _mlkitFrames ?? 0;
    final detected = _mlkitDetected ?? 0;
    final totalMs = _mlkitTotalMs ?? 0;
    final rate = frames == 0 ? 0.0 : detected / frames * 100;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ML Kit (stream + base)',
                style: Theme.of(context).textTheme.titleSmall),
            const Divider(),
            _row('처리 프레임', '$frames'),
            _row('인물 검출', '$detected (${rate.toStringAsFixed(0)}%)'),
            _row('총 소요', '${totalMs.toStringAsFixed(0)}ms'),
            _row(
              '프레임당',
              frames == 0 ? '-' : '${(totalMs / frames).toStringAsFixed(1)}ms',
            ),
          ],
        ),
      ),
    );
  }

  /// 뽑힌 프레임을 눈으로도 확인한다 — 수치만으로는 "깨진 프레임"을 못 잡는다.
  Widget _framePreview(ExtractionRun run) {
    final sample = run.okFrames.take(8).toList();
    if (sample.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('추출 프레임 (앞 8장)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sample.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = sample[i];
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(f['path'] as String),
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Text(
                      '${f['requestedMs']}ms',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
