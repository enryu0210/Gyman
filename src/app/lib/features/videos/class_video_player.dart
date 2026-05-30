/// 수업 영상 재생 화면 — 트레이너/회원 공용 (S 시리즈).
///
/// **순수 재생기:** Supabase/Riverpod 에 의존하지 않는다. 호출 측(트레이너 카드 ·
///   회원 화면)이 각자 provider 로 *서명 URL* 을 먼저 해석해 [url] 로 넘긴다.
///   덕분에 권한·조회 책임은 각 feature 에 남고, 본 위젯은 재생만 책임진다
///   (채팅의 공용 ChatScreen 과 같은 역할 분리).
///
/// **자원 정리:** VideoPlayerController 는 네이티브 리소스라 반드시 dispose.
///   서명 URL 은 단기(1시간)라 화면을 닫으면 컨트롤러도 해제한다.
///
/// 진입: `Navigator.push(MaterialPageRoute(... ClassVideoPlayer(url:, title:)))`.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ClassVideoPlayer extends StatefulWidget {
  const ClassVideoPlayer({super.key, required this.url, required this.title});

  /// 재생할 영상의 단기 서명 URL(호출 측이 해석해 전달).
  final String url;

  /// 상단 표시 제목.
  final String title;

  @override
  State<ClassVideoPlayer> createState() => _ClassVideoPlayerState();
}

class _ClassVideoPlayerState extends State<ClassVideoPlayer> {
  VideoPlayerController? _controller;

  /// 초기화 단계 에러(잘못된 URL/네트워크/코덱) — 사용자에게 안내.
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      // 초기화 도중 화면이 사라졌으면 컨트롤러만 정리하고 종료.
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play(); // 진입 즉시 재생
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 탭으로 재생/일시정지 토글.
  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            const Text(
              '영상을 재생할 수 없습니다.\n네트워크 상태를 확인하거나 잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 원본 비율 유지 + 탭으로 재생/일시정지.
        AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: GestureDetector(
            onTap: _togglePlay,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                // 일시정지 중일 때만 가운데 재생 아이콘 오버레이.
                if (!c.value.isPlaying)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.play_arrow,
                          size: 48, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 진행바 — 드래그로 탐색 가능.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VideoProgressIndicator(
            c,
            allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: Colors.white),
          ),
        ),
      ],
    );
  }
}
