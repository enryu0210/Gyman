/// 수업 영상 재생 화면 — 트레이너/회원 공용 (S 시리즈 + L2 시점 지적).
///
/// **순수 재생기:** Supabase/Riverpod 에 의존하지 않는다. 호출 측(트레이너 카드 ·
///   회원 화면)이 각자 provider 로 *서명 URL* 과 *마킹 목록* 을 먼저 해석해 넘긴다.
///   덕분에 권한·조회 책임은 각 feature 에 남고, 본 위젯은 재생·표시만 책임진다
///   (채팅의 공용 ChatScreen 과 같은 역할 분리).
///   → provider 배선은 [ClassVideoPlayerPage](class_video_player_page.dart)가 담당.
///
/// **L2 시점 지적(docs/design_movement_coaching.md §3.4):**
///   [marks] 가 있으면 ① 진행바에 눈금, ② 해당 시점에 코멘트 오버레이,
///   ③ 아래 목록에서 탭하면 그 지점으로 이동. [onAddMarkAt] 이 있으면(트레이너)
///   현재 지점에 코멘트를 남기는 버튼이 뜬다.
///
/// **자원 정리:** VideoPlayerController 는 네이티브 리소스라 반드시 dispose.
///   서명 URL 은 단기(1시간)라 화면을 닫으면 컨트롤러도 해제한다.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../domain/models/class_video_mark.dart';

class ClassVideoPlayer extends StatefulWidget {
  const ClassVideoPlayer({
    super.key,
    required this.url,
    required this.title,
    this.marks = const [],
    this.onAddMarkAt,
    this.onDeleteMark,
  });

  /// 재생할 영상의 단기 서명 URL(호출 측이 해석해 전달).
  final String url;

  /// 상단 표시 제목.
  final String title;

  /// 시점 지적 목록(시점 오름차순 가정 — 아니어도 내부에서 정렬한다).
  final List<ClassVideoMark> marks;

  /// 현재 지점에 코멘트 추가. null 이면 마킹 UI 를 숨긴다(회원 화면).
  /// 저장에 성공하면 true 를 돌려주는 계약 — 재생 재개 여부 판단에 쓴다.
  final Future<bool> Function(Duration position)? onAddMarkAt;

  /// 마킹 삭제. null 이면 삭제 버튼을 숨긴다(회원 화면).
  final Future<void> Function(ClassVideoMark mark)? onDeleteMark;

  @override
  State<ClassVideoPlayer> createState() => _ClassVideoPlayerState();
}

class _ClassVideoPlayerState extends State<ClassVideoPlayer> {
  VideoPlayerController? _controller;

  /// 초기화 단계 에러(잘못된 URL/네트워크/코덱) — 사용자에게 안내.
  Object? _initError;

  /// 마지막으로 반영한 재생 위치 틱. 프레임마다 setState 하지 않기 위한 스로틀
  /// (500ms 단위면 코멘트 오버레이·시간 표시 모두 충분하다).
  int _lastTick = -1;

  /// 현재 재생 위치(ms) — 오버레이 판정과 "이 지점" 버튼에 쓴다.
  int _positionMs = 0;

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
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play(); // 진입 즉시 재생
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  /// 재생 위치 변화를 500ms 단위로만 화면에 반영(프레임마다 rebuild 방지).
  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final ms = c.value.position.inMilliseconds;
    final tick = ms ~/ 500;
    if (tick == _lastTick) return;
    _lastTick = tick;
    if (!mounted) return;
    setState(() => _positionMs = ms);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  /// 탭으로 재생/일시정지 토글.
  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  /// 마킹 지점으로 이동 + 조금 앞에서 재생 — 지적한 동작을 놓치지 않게.
  Future<void> _seekToMark(ClassVideoMark mark) async {
    final c = _controller;
    if (c == null) return;
    // 1초 앞에서 시작해 "그 순간"이 오는 걸 보게 한다.
    final target = mark.tMs - 1000;
    await c.seekTo(Duration(milliseconds: target < 0 ? 0 : target));
    await c.play();
  }

  /// 현재 지점에 코멘트 남기기 — 입력 동안엔 재생을 멈춘다.
  Future<void> _addMarkHere() async {
    final c = _controller;
    final onAdd = widget.onAddMarkAt;
    if (c == null || onAdd == null) return;

    final wasPlaying = c.value.isPlaying;
    await c.pause();
    if (mounted) setState(() {});

    final saved = await onAdd(c.value.position);

    if (!mounted) return;
    // 저장했으면 그 지점을 확인할 수 있게 멈춰 두고, 취소했으면 하던 대로 되돌린다.
    if (!saved && wasPlaying) await c.play();
    if (mounted) setState(() {});
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
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.white70),
              SizedBox(height: 12),
              Text(
                '영상을 재생할 수 없습니다.\n네트워크 상태를 확인하거나 잠시 후 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final marks = VideoMarkTimeline.sorted(widget.marks);
    final activeMark = VideoMarkTimeline.activeAt(marks, _positionMs);
    final durationMs = c.value.duration.inMilliseconds;

    return Column(
      children: [
        // ── 영상 + 코멘트 오버레이 ──
        AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: GestureDetector(
            onTap: _togglePlay,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                if (!c.value.isPlaying)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child:
                          Icon(Icons.play_arrow, size: 48, color: Colors.white),
                    ),
                  ),
                // 지금 지점에 지적이 있으면 영상 위에 띄운다 — 눈이 영상에 있으니까.
                if (activeMark != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _MarkOverlay(mark: activeMark),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── 진행바 + 마킹 눈금 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: Colors.white),
              ),
              if (durationMs > 0)
                Positioned.fill(
                  child: _MarkTicks(marks: marks, durationMs: durationMs),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _TimeRow(
          positionMs: _positionMs,
          durationMs: durationMs,
          onAddMark: widget.onAddMarkAt == null ? null : _addMarkHere,
        ),

        // ── 마킹 목록 ──
        Expanded(
          child: _MarkList(
            marks: marks,
            activeMarkId: activeMark?.id,
            onTap: _seekToMark,
            onDelete: widget.onDeleteMark,
          ),
        ),
      ],
    );
  }
}

/// 영상 위에 뜨는 지적 코멘트.
class _MarkOverlay extends StatelessWidget {
  const _MarkOverlay({required this.mark});
  final ClassVideoMark mark;

  @override
  Widget build(BuildContext context) {
    final part = mark.bodyPartLabel;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                part == null ? mark.comment : '[$part] ${mark.comment}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 진행바 위 마킹 눈금 — 어디에 지적이 있는지 한눈에.
class _MarkTicks extends StatelessWidget {
  const _MarkTicks({required this.marks, required this.durationMs});

  final List<ClassVideoMark> marks;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            for (final mark in marks)
              Positioned(
                // 눈금 너비(3)의 절반만큼 당겨 시점 위에 정확히 오게.
                left: (mark.tMs / durationMs).clamp(0.0, 1.0) * width - 1.5,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: color),
              ),
          ],
        );
      },
    );
  }
}

/// 현재 시간 / 전체 시간 + (트레이너) 이 지점에 코멘트 버튼.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.positionMs,
    required this.durationMs,
    this.onAddMark,
  });

  final int positionMs;
  final int durationMs;
  final VoidCallback? onAddMark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '${ClassVideoMark.formatMs(positionMs)} / '
            '${ClassVideoMark.formatMs(durationMs)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Spacer(),
          if (onAddMark != null)
            TextButton.icon(
              onPressed: onAddMark,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('이 지점에 코멘트'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }
}

/// 마킹 목록 — 탭하면 그 지점으로 이동.
class _MarkList extends StatelessWidget {
  const _MarkList({
    required this.marks,
    required this.activeMarkId,
    required this.onTap,
    this.onDelete,
  });

  final List<ClassVideoMark> marks;
  final String? activeMarkId;
  final void Function(ClassVideoMark) onTap;
  final Future<void> Function(ClassVideoMark)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            onDelete == null
                // 회원: 아직 지적이 없다는 사실만 담담하게.
                ? '트레이너가 남긴 지적이 아직 없습니다.'
                // 트레이너: 무엇을 하면 되는지 알려준다.
                : '재생하다가 고칠 지점에서 [이 지점에 코멘트]를 눌러 남겨보세요.\n'
                    '회원이 이 영상을 볼 때 같은 지점에서 표시됩니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: marks.length,
      itemBuilder: (context, i) {
        final mark = marks[i];
        final isActive = mark.id == activeMarkId;
        final part = mark.bodyPartLabel;

        return ListTile(
          dense: true,
          selected: isActive,
          selectedTileColor: Colors.white10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          leading: Text(
            mark.timeLabel,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          title: Text(
            mark.comment,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          subtitle: part == null
              ? null
              : Text(part,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: onDelete == null
              ? null
              : IconButton(
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.white54),
                  onPressed: () => onDelete!(mark),
                ),
          onTap: () => onTap(mark),
        );
      },
    );
  }
}
