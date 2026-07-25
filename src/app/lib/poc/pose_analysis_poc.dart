/// [PoC] 체형분석 실현성 검증 — 정지 사진 → ML Kit Pose → 참고 수치.
/// docs/design_body_analysis.md §7 B단계 선행 확인
///
/// **무엇을 증명하려는가:**
///   1. ML Kit 이 정지 사진에서 어깨·골반 랜드마크를 실제로 뽑는가
///   2. 그 결과를 이미 만들어 둔 순수 도메인([PostureMetricsCalculator])에
///      **어댑터 한 겹으로** 물릴 수 있는가
///   3. 좌표계 변환(ML Kit 픽셀 → 도메인 정규화)이 맞는가
///
/// **여기서 만든 [MlKitPoseAdapter] 가 B단계의 실제 산출물이 된다.**
///   도메인은 ML Kit 을 모르게 두고(테스트 가능하게), 변환만 여기서 책임진다.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;
import 'package:image_picker/image_picker.dart';

import '../domain/posture_metrics.dart';

/// ML Kit 결과 → 도메인 [PoseSnapshot] 변환.
///
/// **핵심은 좌표계다.** ML Kit 은 랜드마크를 **이미지 픽셀 좌표**로 준다.
/// 도메인은 해상도 독립적으로 저장하려고 **정규화(0~1)** 를 받는다.
/// 그래서 여기서 이미지 크기로 나눈다 — 이 변환을 빠뜨리면 각도가 통째로 틀린다.
class MlKitPoseAdapter {
  const MlKitPoseAdapter._();

  /// 도메인이 쓰는 랜드마크 ↔ ML Kit 랜드마크 대응.
  /// 좌/우는 양쪽 다 **피사체 기준**이라 그대로 매핑된다.
  static const _mapping = <PoseLandmarkType, mlkit.PoseLandmarkType>{
    PoseLandmarkType.leftShoulder: mlkit.PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder: mlkit.PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip: mlkit.PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip: mlkit.PoseLandmarkType.rightHip,
  };

  static PoseSnapshot toSnapshot(
    mlkit.Pose pose, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final points = <PoseLandmarkType, PoseKeypoint>{};

    for (final entry in _mapping.entries) {
      final lm = pose.landmarks[entry.value];
      if (lm == null) continue;
      points[entry.key] = PoseKeypoint(
        // 픽셀 → 정규화. 프레임 밖으로 나간 랜드마크는 0~1 을 벗어날 수 있어 클램프.
        x: (lm.x / imageWidth).clamp(0.0, 1.0),
        y: (lm.y / imageHeight).clamp(0.0, 1.0),
        likelihood: lm.likelihood,
      );
    }

    return PoseSnapshot(
      points: points,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }
}

class PoseAnalysisPoc extends StatefulWidget {
  const PoseAnalysisPoc({super.key});

  @override
  State<PoseAnalysisPoc> createState() => _PoseAnalysisPocState();
}

class _PoseAnalysisPocState extends State<PoseAnalysisPoc> {
  File? _image;
  ui.Image? _decoded;
  List<PostureMetric> _metrics = const [];
  String? _status;
  bool _busy = false;

  /// 정지 사진용 — 실시간이 아니므로 single 모드 + accurate 모델.
  final _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.single,
      model: mlkit.PoseDetectionModel.accurate,
    ),
  );

  @override
  void dispose() {
    _detector.close();
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // 실제 플로우도 업로드 전 압축한다(설계 §2.2) — 같은 조건으로 시험.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() {
      _busy = true;
      _status = '분석 중…';
      _metrics = const [];
    });

    final sw = Stopwatch()..start();
    try {
      final file = File(picked.path);

      // 도메인이 정규화 좌표 + 이미지 크기를 요구하므로 크기를 먼저 얻는다.
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);

      final poses = await _detector.processImage(
        mlkit.InputImage.fromFilePath(picked.path),
      );
      sw.stop();

      if (poses.isEmpty) {
        setState(() {
          _image = file;
          _decoded?.dispose();
          _decoded = decoded;
          _status = '사람을 찾지 못했습니다 (${sw.elapsedMilliseconds}ms). '
              '전신이 나오게 다시 촬영해 보세요.';
          _busy = false;
        });
        return;
      }

      final snapshot = MlKitPoseAdapter.toSnapshot(
        poses.first,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
      final metrics = PostureMetricsCalculator.compute(snapshot);

      setState(() {
        _image = file;
        _decoded?.dispose();
        _decoded = decoded;
        _metrics = metrics;
        _status = '검출 ${poses.length}명 · ${decoded.width}×${decoded.height} · '
            '추론 ${sw.elapsedMilliseconds}ms';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _status = '분석 실패: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PoC 2 · 사진 → 자세 수치')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickAndAnalyze(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('촬영해서 분석'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _pickAndAnalyze(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('갤러리에서 분석'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_status != null)
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_image!, height: 320, fit: BoxFit.contain),
            ),
          const SizedBox(height: 16),
          if (_metrics.isNotEmpty) ...[
            Text('참고 수치', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final m in _metrics)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    switch (m.flag) {
                      PostureFlag.ok => Icons.check_circle_outline,
                      PostureFlag.watch => Icons.warning_amber_outlined,
                      PostureFlag.insufficient => Icons.help_outline,
                    },
                  ),
                  title: Text(m.describe()),
                  subtitle: Text('flag: ${m.flag.code} · json: ${m.toJson()}'),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              '⚠ 이 수치는 참고용 스크리닝이며 진단이 아닙니다. '
              '실제 기능에서는 트레이너 코멘트가 달린 뒤에만 회원에게 노출됩니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
