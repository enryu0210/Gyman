/// 회원 상세 "수업 영상" 카드 — 트레이너 (S 시리즈).
///
/// 구성:
///   - 상단: [영상 올리기] 버튼(촬영/갤러리 선택)
///   - 본문: 업로드한 영상 목록(제목/길이/날짜). 탭하면 재생, 행에서 삭제 가능.
///
/// **회원에게도 보이는 데이터:** 영상은 트레이너가 의도적으로 올린 자료라 검수 게이트
///   없이 회원 본인이 본다(0027 RLS). 그래서 인바디 카드와 같은 "회원도 볼 수 있음" 톤.
///
/// **업로드 흐름(설계 §4):** 선택(촬영/갤러리) → 길이·용량 검증(120초·250MB 상한) →
///   제목·동의 다이얼로그 → 업로드(보상 트랜잭션). 상한은 비용 방어선(설계 §0.2/§10).
///
/// 추가/삭제는 [classVideoControllerProvider] 경유. SnackBar 는 본 카드가,
/// 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/class_video.dart';
import '../../videos/class_video_player.dart';
import '../../videos/class_video_session_link.dart';
import 'class_video_providers.dart';
import 'upload_class_video_dialog.dart';

/// 클립 길이 상한(초) — 설계 §0.2. 풀세션 통영상 차단(비용 방어).
const _maxDurationSec = 120;

/// 파일 크기 상한(바이트) — 버킷 file_size_limit(0027)과 일치(250MB).
const _maxSizeBytes = 262144000;

/// 회원 1명당 보관 가능한 영상 개수 상한 — 저장비 방어선(설계 §7 B / §9.3).
///
/// **왜 차단 방식인가:** 한도 도달 시 *자동으로 오래된 영상을 지우지 않고* 업로드를
///   막는다. 회원 영상은 되돌릴 수 없는 데이터라 조용한 자동 삭제는 위험(설계 §3.4/§10
///   안전 원칙). 트레이너가 직접 오래된 영상을 지운 뒤 다시 올린다.
///
/// **비용 감각(튜닝 기준):** Pro 포함 저장 100GB. 영상 1편 ~150MB 가정 시
///   회원수 × 이 상한 × 0.15GB 가 회원 영상 저장 상한. 예) 회원 30명 × 20개 ≈ 90GB.
///   회원이 늘면 이 값을 낮추거나(또는) 압축(B-2)·기간 정리 잡 도입으로 방어.
const _maxVideosPerMember = 20;

class ClassVideosCard extends ConsumerStatefulWidget {
  const ClassVideosCard({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  ConsumerState<ClassVideosCard> createState() => _ClassVideosCardState();
}

class _ClassVideosCardState extends ConsumerState<ClassVideosCard> {
  final _picker = ImagePicker();

  /// 최근 몇 건까지 카드에 펼쳐 보일지.
  static const _visibleCount = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final async = ref.watch(videosForMemberProvider(widget.memberId));
    final busy = ref.watch(classVideoControllerProvider).isLoading;

    // 현재 보관 개수(로드 완료 시에만). 한도 도달이면 업로드를 막는다(자동삭제 X).
    final count = async.valueOrNull?.length;
    final atCap = count != null && count >= _maxVideosPerMember;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.videocam_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // 보관 현황(N/상한)을 제목에 같이 — 한도 감각을 트레이너가 바로 봄.
                    count == null
                        ? '수업 영상'
                        : '수업 영상 ($count/$_maxVideosPerMember)',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Tooltip(
                  message: '회원도 앱에서 볼 수 있습니다',
                  child: Icon(Icons.visibility_outlined,
                      size: 16, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                // 한도 도달 시 비활성 — 차단 방식(자동삭제 X). 아래 안내문으로 사유 표시.
                onPressed: (busy || atCap) ? null : _startUpload,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload, size: 18),
                label: Text(busy ? '업로드 중…' : '영상 올리기'),
              ),
            ),
            // 보관 한도 도달 안내 — 오래된 영상을 지우면 다시 올릴 수 있음.
            if (atCap)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '보관 한도($_maxVideosPerMember개)에 도달했습니다. 아래에서 오래된 영상을 지우면 다시 올릴 수 있어요.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ),
            const SizedBox(height: 4),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('영상 목록을 불러오지 못했습니다.\n$e',
                    style: theme.textTheme.bodySmall),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 올린 영상이 없습니다. [영상 올리기]로 짧은 자세/폼 체크 클립을 공유하세요. (최대 $_maxDurationSec초)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final shown = list.take(_visibleCount).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final v in shown)
                      _VideoTile(memberId: widget.memberId, video: v),
                    if (list.length > shown.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '외 ${list.length - shown.length}건 더 있음',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 영상 올리기: 촬영/갤러리 선택 → 검증 → 업로드 다이얼로그.
  Future<void> _startUpload() async {
    // 방어적 가드 — 버튼은 한도 시 비활성이지만, 목록이 갱신되는 사이의 stale 호출 대비.
    final current = ref.read(videosForMemberProvider(widget.memberId)).valueOrNull;
    if (current != null && current.length >= _maxVideosPerMember) {
      _snack('보관 한도($_maxVideosPerMember개)에 도달했습니다. 오래된 영상을 지운 뒤 올려 주세요.');
      return;
    }

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await _picker.pickVideo(
        source: source,
        // 촬영 시 길이 상한(플랫폼이 지원하면 캡처 단계에서 차단). 갤러리 선택은
        // 측정 후 한 번 더 거른다.
        maxDuration: const Duration(seconds: _maxDurationSec),
      );
    } catch (e) {
      _snack('영상을 불러오지 못했습니다. 권한을 확인해 주세요.');
      return;
    }
    if (picked == null || !mounted) return; // 사용자가 취소

    final file = File(picked.path);

    // 1) 길이 검증 — 컨트롤러로 실제 길이를 재서 상한 초과를 거른다(비용 방어).
    final durationSec = await _measureDurationSec(file);
    if (!mounted) return;
    if (durationSec != null && durationSec > _maxDurationSec) {
      _snack('영상이 너무 깁니다. 최대 $_maxDurationSec초까지 올릴 수 있어요.');
      return;
    }

    // 2) 용량 검증 — 버킷 상한과 동일(250MB).
    final size = await file.length();
    if (!mounted) return;
    if (size > _maxSizeBytes) {
      _snack('영상 용량이 너무 큽니다. 250MB 이하로 올려 주세요.');
      return;
    }

    // 3) 제목·동의 다이얼로그 → 업로드.
    final ok = await showUploadClassVideoDialog(
      context,
      memberId: widget.memberId,
      file: file,
      durationSec: durationSec,
    );
    if (ok == true && mounted) {
      _snack('영상이 업로드되었습니다.');
    }
  }

  /// 촬영/갤러리 선택 바텀시트. 취소 시 null.
  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('촬영하기'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// 로컬 영상 파일의 길이(초)를 측정. 실패하면 null(메타 누락 허용).
  /// VideoPlayerController 는 네이티브 리소스라 측정 후 반드시 dispose.
  Future<int?> _measureDurationSec(File file) async {
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
      final d = c.value.duration;
      return d.inSeconds;
    } catch (_) {
      return null; // 코덱/포맷 문제 등 — 길이 검증은 건너뛰고 업로드는 진행
    } finally {
      await c.dispose();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 영상 1건 행 — 제목 + 길이/날짜 + 재생/삭제.
class _VideoTile extends ConsumerWidget {
  const _VideoTile({required this.memberId, required this.video});

  final String memberId;
  final ClassVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final v = video;

    final meta = <String>[
      if (v.durationLabel != null) v.durationLabel!,
      formatKoreanDate(v.createdAt),
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(Icons.play_arrow, color: colors.onPrimaryContainer),
      ),
      title: Text(v.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      isThreeLine: v.sessionScheduledAt != null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta, style: theme.textTheme.bodySmall),
          // 특정 수업과 연결된 영상이면 그 수업 일시를 함께 표시(0027 session_id).
          if (v.sessionScheduledAt != null)
            ClassVideoSessionLink(date: v.sessionScheduledAt!),
        ],
      ),
      trailing: IconButton(
        tooltip: '삭제',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.delete_outline, size: 20, color: colors.error),
        onPressed: () => _confirmDelete(context, ref),
      ),
      onTap: () => _play(context, ref),
    );
  }

  /// 서명 URL 을 발급해 공용 재생기로 이동.
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final String url;
    try {
      url = await ref.read(classVideoSignedUrlProvider(video.storagePath).future);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('영상을 불러오지 못했습니다.')));
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClassVideoPlayer(url: url, title: video.displayTitle),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('영상 삭제'),
        content: Text('"${video.displayTitle}" 영상을 삭제하시겠습니까?\n회원도 더 이상 볼 수 없게 됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(classVideoControllerProvider.notifier).remove(
          id: video.id,
          storagePath: video.storagePath,
          memberId: memberId,
        );

    if (!context.mounted) return;
    final state = ref.read(classVideoControllerProvider);
    final msg = state.hasError
        ? (state.error?.toString() ?? '삭제에 실패했습니다.')
        : '영상이 삭제되었습니다.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
