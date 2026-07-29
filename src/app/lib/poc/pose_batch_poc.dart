/// [PoC] 체형분석 — 여러 장 일괄 분석 + 편차 요약.
/// docs/poc_cv_track_results.md §4 "PoC 2" 의 4번(재현성)을 재기 위한 하네스.
///
/// **왜 단일 분석([PoseAnalysisPoc]) 으로는 부족한가:**
///   재현성은 한 장의 수치가 아니라 **여러 장 사이의 흔들림**이다. 한 장씩 눌러
///   화면 값을 손으로 옮겨 적으면 16장에 오탈자가 섞이고, 무엇보다 표준편차를
///   손으로 못 낸다. 그래서 선택 → 순차 분석 → 통계까지 앱이 한 번에 한다.
///
/// **결과는 logcat 에도 CSV 로 찍는다**(`[POC2]` 태그). 화면 스크린샷은 옮겨
///   적어야 하지만 logcat 은 `adb logcat -s flutter` 로 그대로 긁어 문서에 붙일 수 있다.
///
/// ⚠ **요약 통계는 "같은 사진의 변형" 을 넣었을 때만 의미가 있다.**
///   서로 다른 사람 사진을 섞으면 편차는 그냥 사람이 다른 것이지 재현성이 아니다.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;
import 'package:image_picker/image_picker.dart';

import '../domain/posture_metrics.dart';
import 'pose_analysis_poc.dart' show MlKitPoseAdapter;

/// 사진 1장의 분석 결과.
///
/// 각도를 **부호 있는 값**으로 들고 있는 게 핵심이다. 도메인
/// [PostureMetric.valueDeg] 는 크기(0~90)와 방향([PostureMetric.higherSide])이
/// 분리돼 있는데, 그대로는 평균·표준편차를 낼 수 없다 — 왼쪽 2도와 오른쪽 2도가
/// 둘 다 "2.0" 이라 편차 0 으로 잡히기 때문이다.
class PoseBatchRow {
  final String name;
  final int elapsedMs;
  final int width;
  final int height;

  /// 검출된 인원 수. 0 이면 미검출.
  final int poseCount;

  /// 피사체 **왼쪽이 높으면 +**, 오른쪽이 높으면 −. 측정 불가면 null.
  final double? shoulderSignedDeg;
  final double? pelvisSignedDeg;

  final String shoulderFlag;
  final String pelvisFlag;

  /// 측정 불가 사유(가드 문구 확인용).
  final String? note;

  const PoseBatchRow({
    required this.name,
    required this.elapsedMs,
    required this.width,
    required this.height,
    required this.poseCount,
    required this.shoulderFlag,
    required this.pelvisFlag,
    this.shoulderSignedDeg,
    this.pelvisSignedDeg,
    this.note,
  });

  /// logcat 수집용 한 줄. 열 순서를 바꾸면 기존 로그와 안 맞으니 주의.
  String toCsv() => [
        name,
        '${width}x$height',
        elapsedMs,
        poseCount,
        shoulderSignedDeg?.toStringAsFixed(2) ?? '',
        shoulderFlag,
        pelvisSignedDeg?.toStringAsFixed(2) ?? '',
        pelvisFlag,
        note ?? '',
      ].join(',');
}

/// [PostureMetric] → 부호 있는 각도.
///
/// y 축이 아래로 증가하므로 도메인은 "y 가 작은 쪽이 높다" 로 판정한다.
/// 여기서는 그 판정을 부호로만 옮긴다 — 좌/우는 **피사체 기준**(ML Kit 규약).
double? signedDeg(PostureMetric m) {
  final v = m.valueDeg;
  if (v == null) return null;
  return switch (m.higherSide) {
    BodySide.left => v,
    BodySide.right => -v,
    null => 0.0, // 완전 수평
  };
}

/// 표본 통계. 표본이 2개 미만이면 표준편차가 정의되지 않아 null.
class BatchStats {
  final int n;
  final double min;
  final double max;
  final double mean;

  /// 표본 표준편차(n−1). **재현성 판정에 쓰는 값이다.**
  final double? sd;

  const BatchStats({
    required this.n,
    required this.min,
    required this.max,
    required this.mean,
    this.sd,
  });

  /// 최대−최소. 표준편차보다 보수적이라 "최악의 두 장 차이" 를 본다.
  double get spread => max - min;

  static BatchStats? of(List<double> xs) {
    if (xs.isEmpty) return null;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    double? sd;
    if (xs.length >= 2) {
      final varSum = xs.fold<double>(0, (s, x) => s + math.pow(x - mean, 2));
      sd = math.sqrt(varSum / (xs.length - 1));
    }
    return BatchStats(
      n: xs.length,
      min: xs.reduce(math.min),
      max: xs.reduce(math.max),
      mean: mean,
      sd: sd,
    );
  }
}

/// 앱 내부 저장소 경로를 네이티브에 물어보는 채널 (PoC 3 채널 재사용).
///
/// **왜 갤러리를 안 쓰는가.** 사진 선택기를 거치면 16장 중 특정 4장을 좌표
/// 탭으로 골라야 해서 자동화가 스크롤 위치에 따라 깨진다. `adb push` 로
/// 넣어둔 폴더를 그대로 읽으면 버튼 한 번으로 세트 전체가 돈다.
///
/// **왜 경로를 Dart 에서 안 만드는가.** `/sdcard/Android/data/<pkg>` 는
/// Android 11+ 에서 raw path 접근이 막혀 Permission denied 다(2026-07-29 실측).
const _channel = MethodChannel('gyman/poc_video_frames');

/// 검증 세트가 들어 있는 하위 폴더 이름.
const _batchSubdir = 'poc2';

class PoseBatchPoc extends StatefulWidget {
  const PoseBatchPoc({super.key});

  @override
  State<PoseBatchPoc> createState() => _PoseBatchPocState();
}

class _PoseBatchPocState extends State<PoseBatchPoc> {
  final List<PoseBatchRow> _rows = [];
  String? _status;
  bool _busy = false;
  int _done = 0;
  int _total = 0;

  /// 앱 내부 저장소 경로. 채널 왕복을 매번 하지 않으려고 한 번만 받아 캐시한다.
  String? _baseDir;

  /// `[_batchSubdir]` 아래에 실제로 있는 세트 폴더들.
  ///
  /// 하드코딩하지 않고 스캔하는 이유: 세트를 하나 추가할 때마다 재빌드·재설치를
  /// 하면 측정 한 번에 1분이 더 든다. `adb push` 만으로 새 세트가 버튼에 뜬다.
  List<String> _sets = const [];

  /// 단일 분석([PoseAnalysisPoc]) 과 **같은 설정**이어야 수치를 비교할 수 있다.
  final _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.single,
      model: mlkit.PoseDetectionModel.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  @override
  void dispose() {
    _detector.close();
    super.dispose();
  }

  Future<void> _loadSets() async {
    try {
      final base = await _channel.invokeMethod<String>('getFilesDir');
      if (base == null || !mounted) return;
      final root = Directory('$base/$_batchSubdir');
      final sets = root.existsSync()
          ? (root.listSync().whereType<Directory>().toList()
                ..sort((a, b) => a.path.compareTo(b.path)))
              .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
              .toList()
          : <String>[];
      setState(() {
        _baseDir = base;
        _sets = sets;
        if (sets.isEmpty) _status = '세트 폴더가 없습니다: ${root.path}';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '앱 경로를 얻지 못했습니다: $e');
    }
  }

  Future<void> _pickAndAnalyzeAll() async {
    final picked = await ImagePicker().pickMultiImage(
      // 실제 업로드 플로우와 동일 압축(설계 §2.2) — 단일 분석과도 같아야 한다.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked.isEmpty) return;

    // 갤러리 선택 순서는 플랫폼마다 달라서 믿을 수 없다. 이름순으로 고정해야
    // 회전 세트(T_m2 → T_p2)의 응답을 표에서 순서대로 읽을 수 있다.
    final files = [...picked]..sort((a, b) => a.name.compareTo(b.name));

    setState(() {
      _busy = true;
      _rows.clear();
      _done = 0;
      _total = files.length;
      _status = '분석 중…';
    });

    await _runAll([for (final f in files) (f.path, f.name)], 'picker');
  }

  /// 앱 내부 저장소의 `[_batchSubdir]/<세트>` 폴더를 통째로 분석.
  ///
  /// 갤러리 경로와 달리 **image_picker 의 재압축(quality 80)을 거치지 않는다.**
  /// 세트 안에서는 조건이 똑같아 비교가 공정하지만, 실제 업로드 플로우와는
  /// 압축 한 단계가 다르다 — 결과를 적을 때 어느 경로로 쟀는지 함께 남길 것.
  Future<void> _analyzeFolder(String setName) async {
    final base = _baseDir;
    if (base == null) {
      setState(() => _status = '앱 경로를 아직 못 받았습니다');
      return;
    }

    final dir = Directory('$base/$_batchSubdir/$setName');
    if (!dir.existsSync()) {
      setState(() => _status = '폴더 없음: ${dir.path}\n'
          'adb push 로 사진을 넣었는지 확인하세요.');
      return;
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList()
      // 회전 세트(T_m2 → T_p2)의 응답을 표에서 순서대로 읽으려면 이름순 고정이 필요.
      ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      setState(() => _status = '$setName 폴더가 비어 있습니다');
      return;
    }

    setState(() {
      _busy = true;
      _rows.clear();
      _done = 0;
      _total = files.length;
      _status = '$setName 분석 중…';
    });

    await _runAll(
      [for (final f in files) (f.path, f.uri.pathSegments.last)],
      setName,
    );
  }

  /// (경로, 표시이름) 목록을 순차 분석하고 logcat 에 CSV 로 남긴다.
  Future<void> _runAll(List<(String, String)> items, String label) async {
    debugPrint('[POC2] === $label ===');
    debugPrint('[POC2] name,size,ms,poses,shoulder_deg,shoulder_flag,'
        'pelvis_deg,pelvis_flag,note');

    for (final (path, name) in items) {
      final row = await _analyzeOne(path, name);
      if (!mounted) return;
      setState(() {
        _rows.add(row);
        _done++;
      });
      debugPrint('[POC2] ${row.toCsv()}');
    }

    if (!mounted) return;

    // 요약도 logcat 에 남긴다 — 화면 통계를 손으로 옮겨 적지 않기 위해.
    final sh = BatchStats.of(
        _rows.map((r) => r.shoulderSignedDeg).nonNulls.toList());
    final pv =
        BatchStats.of(_rows.map((r) => r.pelvisSignedDeg).nonNulls.toList());
    debugPrint('[POC2] SUMMARY $label '
        'detected=${_rows.where((r) => r.poseCount > 0).length}/${_rows.length} '
        'shoulder_spread=${sh?.spread.toStringAsFixed(3) ?? '-'} '
        'shoulder_sd=${sh?.sd?.toStringAsFixed(3) ?? '-'} '
        'pelvis_spread=${pv?.spread.toStringAsFixed(3) ?? '-'} '
        'pelvis_sd=${pv?.sd?.toStringAsFixed(3) ?? '-'}');

    setState(() {
      _busy = false;
      _status = '$label — ${_rows.length}장 완료';
    });
  }

  Future<PoseBatchRow> _analyzeOne(String path, String name) async {
    final sw = Stopwatch()..start();
    ui.Image? decoded;
    try {
      // 도메인이 픽셀 크기를 요구한다. 디코드 비용이 추론 시간에 섞이지 않도록
      // 스톱워치는 디코드 뒤에 다시 재지 않고 **전체 시간**으로 본다 —
      // 실제 사용자가 체감하는 것도 전체 시간이기 때문.
      decoded = await decodeImageFromList(await File(path).readAsBytes());
      final poses = await _detector.processImage(
        mlkit.InputImage.fromFilePath(path),
      );
      sw.stop();

      if (poses.isEmpty) {
        return PoseBatchRow(
          name: name,
          elapsedMs: sw.elapsedMilliseconds,
          width: decoded.width,
          height: decoded.height,
          poseCount: 0,
          shoulderFlag: PostureFlag.insufficient.code,
          pelvisFlag: PostureFlag.insufficient.code,
          note: '사람 미검출',
        );
      }

      final snapshot = MlKitPoseAdapter.toSnapshot(
        poses.first,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
      final shoulder = PostureMetricsCalculator.computeOne(
          snapshot, PostureMetricKey.shoulderTilt);
      final pelvis = PostureMetricsCalculator.computeOne(
          snapshot, PostureMetricKey.pelvisTilt);

      return PoseBatchRow(
        name: name,
        elapsedMs: sw.elapsedMilliseconds,
        width: decoded.width,
        height: decoded.height,
        poseCount: poses.length,
        shoulderSignedDeg: signedDeg(shoulder),
        pelvisSignedDeg: signedDeg(pelvis),
        shoulderFlag: shoulder.flag.code,
        pelvisFlag: pelvis.flag.code,
        // 가드 문구는 둘 중 하나만 떠도 기록해야 원인을 안다.
        note: shoulder.note ?? pelvis.note,
      );
    } catch (e) {
      sw.stop();
      return PoseBatchRow(
        name: name,
        elapsedMs: sw.elapsedMilliseconds,
        width: 0,
        height: 0,
        poseCount: 0,
        shoulderFlag: 'error',
        pelvisFlag: 'error',
        note: '$e',
      );
    } finally {
      decoded?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shoulderStats = BatchStats.of(
        _rows.map((r) => r.shoulderSignedDeg).nonNulls.toList());
    final pelvisStats =
        BatchStats.of(_rows.map((r) => r.pelvisSignedDeg).nonNulls.toList());
    final msStats = BatchStats.of(
        _rows.map((r) => r.elapsedMs.toDouble()).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('PoC 2 · 여러 장 일괄 분석')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('adb 로 넣은 세트 (권장)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final s in _sets)
                FilledButton(
                  onPressed: _busy ? null : () => _analyzeFolder(s),
                  child: Text(s),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'set1 검출·가드 / set2(R) 재현성 하한 / set3(T) 회전 응답. '
            '세트를 섞지 마세요 — set1 은 서로 다른 사람이라 편차가 '
            '재현성이 아니라 사람 차이가 됩니다.',
            style: TextStyle(fontSize: 12),
          ),
          const Divider(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickAndAnalyzeAll,
            icon: const Icon(Icons.burst_mode_outlined, size: 18),
            label: const Text('갤러리에서 골라 분석'),
          ),
          const SizedBox(height: 4),
          const Text(
            '이쪽은 image_picker 재압축(quality 80)을 거칩니다 — '
            '실제 업로드 플로우와 같은 조건이라 교차 확인용.',
            style: TextStyle(fontSize: 12),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total,
            ),
            const SizedBox(height: 4),
            Text('$_done / $_total'),
          ],
          if (_status != null && !_busy) ...[
            const SizedBox(height: 8),
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _StatsCard(
              shoulder: shoulderStats,
              pelvis: pelvisStats,
              ms: msStats,
              detected: _rows.where((r) => r.poseCount > 0).length,
              total: _rows.length,
            ),
            const SizedBox(height: 16),
            Text('상세', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in _rows) _RowTile(row: r),
          ],
        ],
      ),
    );
  }
}

/// 요약 카드 — 재현성 판정에 실제로 쓰는 값만 크게 보여준다.
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.shoulder,
    required this.pelvis,
    required this.ms,
    required this.detected,
    required this.total,
  });

  final BatchStats? shoulder;
  final BatchStats? pelvis;
  final BatchStats? ms;
  final int detected;
  final int total;

  String _fmt(BatchStats? s) {
    if (s == null) return '측정 없음';
    final sd = s.sd == null ? '—' : s.sd!.toStringAsFixed(2);
    return '폭 ${s.spread.toStringAsFixed(2)}도 · SD $sd · '
        '평균 ${s.mean.toStringAsFixed(2)} '
        '(${s.min.toStringAsFixed(2)} ~ ${s.max.toStringAsFixed(2)}, n=${s.n})';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('요약', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('검출 $detected / $total장'),
            if (ms != null)
              Text('추론 평균 ${ms!.mean.toStringAsFixed(0)}ms '
                  '(${ms!.min.toStringAsFixed(0)} ~ ${ms!.max.toStringAsFixed(0)})'),
            const Divider(height: 20),
            Text('어깨  ${_fmt(shoulder)}'),
            const SizedBox(height: 4),
            Text('골반  ${_fmt(pelvis)}'),
            const SizedBox(height: 8),
            const Text(
              '판정: R 세트(회전 없음)에서 폭이 1도를 넘으면 재현성 실패. '
              'T 세트는 회전각(−2/−1/+1/+2도)만큼 값이 따라 움직여야 정상.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final PoseBatchRow row;

  String _deg(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}'
      '${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final failed = row.poseCount == 0 || row.note != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          failed ? Icons.warning_amber_outlined : Icons.check_circle_outline,
          size: 20,
        ),
        title: Text(row.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          '어깨 ${_deg(row.shoulderSignedDeg)}° (${row.shoulderFlag}) · '
          '골반 ${_deg(row.pelvisSignedDeg)}° (${row.pelvisFlag})\n'
          '${row.elapsedMs}ms · ${row.width}x${row.height} · '
          '검출 ${row.poseCount}명${row.note == null ? '' : ' · ${row.note}'}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
