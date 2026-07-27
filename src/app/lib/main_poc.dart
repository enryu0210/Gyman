/// [PoC] CV 트랙 실현성 검증 전용 진입점.
///
/// 실행: `cd src/app && flutter run -t lib/main_poc.dart`
///       (실기기 필수 — 카메라·ML Kit 은 에뮬레이터에서 의미 있는 수치가 안 나온다)
///
/// **프로덕션 코드를 전혀 건드리지 않는다.** 라우터·`main.dart`·기존 화면과 분리돼
/// 있어, PoC 결과가 나쁘면 `lib/poc/` 와 이 파일만 지우면 끝난다.
///
/// 검증 대상(docs/develop_plan.md §4 "CV·개인화 트랙 실행 순서" 0단계):
///   PoC 1 — 카메라 프리뷰 + 영상 동시 렌더 (고스트 4.7 의 관문) ✅ 통과(2026-07-27)
///   PoC 2 — 정지 사진 → ML Kit Pose → 참고 수치 (체형분석 4.2 B단계의 관문)
///   PoC 3 — 영상 → 표본 프레임 → ML Kit (영상 트래킹 4.6 / 자동검출 L3 의 관문)
///
/// PoC 3 는 새 플러그인 대신 **플랫폼 채널 + MediaMetadataRetriever** 로 갔다 —
/// 의존성 추가는 늦을수록 좋고(CLAUDE.md), camera 에서 이미 AGP 9 전이 의존성에
/// 물린 터라 네이티브 플러그인을 하나 더 늘리는 쪽이 리스크가 컸다.
library;

import 'package:flutter/material.dart';

import 'poc/frame_extract_poc.dart';
import 'poc/ghost_render_poc.dart';
import 'poc/pose_analysis_poc.dart';

void main() {
  runApp(const PocApp());
}

class PocApp extends StatelessWidget {
  const PocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gyman PoC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC6FF00)),
        useMaterial3: true,
      ),
      home: const _PocMenu(),
    );
  }
}

class _PocMenu extends StatelessWidget {
  const _PocMenu();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gyman — CV 트랙 PoC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '이 앱은 실현성 검증 전용입니다. 각 PoC 를 실기기에서 돌려보고 '
                '화면에 표시되는 수치를 기록하세요.\n\n'
                '판정 기준\n'
                '· PoC 1: raster 평균이 16.7ms 이하면 60fps 통과\n'
                '· PoC 2: 정면 전신 사진에서 어깨·골반 수치가 나오면 통과',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('PoC 1 · 카메라 + 영상 동시 렌더'),
              subtitle: const Text('고스트 오버레이(4.7) 실현성 — 두 네이티브 텍스처 합성'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GhostRenderPoc()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.accessibility_new_outlined),
              title: const Text('PoC 2 · 사진 → 자세 수치'),
              subtitle: const Text('체형분석(4.2) B단계 — ML Kit + 도메인 어댑터'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PoseAnalysisPoc()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('PoC 3 · 영상 → 프레임 → ML Kit'),
              subtitle: const Text('영상 트래킹(4.6)·자동검출(L3) 관문 — 네이티브 프레임 추출'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FrameExtractPoc()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
