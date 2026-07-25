/// 영상 시점 지적 입력 다이얼로그 (L2 — 트레이너 전용).
/// docs/design_movement_coaching.md §3.4
///
/// **입력 항목:** 부위 태그(선택) + 지적 내용(필수). 시점은 재생 위치로 자동.
///
/// **문구 톤:** 회원이 그대로 읽는 내용이다. 진단·단정이 아니라 **동작 지시**로 쓰도록
///   힌트를 준다("무릎이 안으로 말려요" → "무릎을 발끝 방향으로"). 설계 §5 안전선의
///   연장선 — 여기서 트레이너가 쓰는 문장이 곧 회원에게 가는 문장이다.
///
/// 다이얼로그 진입점 패턴: `Future<bool?> showXxxDialog(...)`, 성공 시 true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/class_video_mark.dart';
import 'video_mark_providers.dart';

/// 시점 지적 입력 — 저장 성공 시 true 반환.
Future<bool?> showAddVideoMarkDialog(
  BuildContext context, {
  required String videoId,
  required Duration position,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddVideoMarkDialog(videoId: videoId, position: position),
  );
}

class _AddVideoMarkDialog extends ConsumerStatefulWidget {
  const _AddVideoMarkDialog({required this.videoId, required this.position});

  final String videoId;
  final Duration position;

  @override
  ConsumerState<_AddVideoMarkDialog> createState() =>
      _AddVideoMarkDialogState();
}

class _AddVideoMarkDialogState extends ConsumerState<_AddVideoMarkDialog> {
  final _commentCtrl = TextEditingController();

  /// 선택된 부위 태그. null = 태그 없음(선택 항목이라 기본값 없음).
  String? _bodyPart;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final comment = _commentCtrl.text.trim();
    if (comment.isEmpty) {
      _toast('지적 내용을 입력해 주세요.');
      return;
    }

    final mark = ClassVideoMark(
      id: 'new', // DB 기본값으로 덮어씀
      videoId: widget.videoId,
      tMs: widget.position.inMilliseconds,
      bodyPart: _bodyPart,
      comment: comment,
      createdAt: DateTime.now(),
    );

    await ref.read(videoMarkControllerProvider.notifier).add(mark: mark);

    if (!mounted) return;
    final state = ref.read(videoMarkControllerProvider);
    if (state.hasError) {
      final err = state.error;
      _toast(err is StateError ? err.message : '저장에 실패했습니다.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saving = ref.watch(videoMarkControllerProvider).isLoading;
    final timeLabel =
        ClassVideoMark.formatMs(widget.position.inMilliseconds);

    return AlertDialog(
      title: Text('$timeLabel 지점에 코멘트'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('부위 (선택)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final part in VideoMarkBodyParts.items)
                    ChoiceChip(
                      label: Text(part.label),
                      selected: _bodyPart == part.code,
                      onSelected: saving
                          ? null
                          // 같은 칩을 다시 누르면 해제 — 태그는 선택 항목이다.
                          : (sel) => setState(
                              () => _bodyPart = sel ? part.code : null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                enabled: !saving,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '지적 내용 *',
                  hintText: '예: 여기서 무릎이 안쪽으로 말려요. 발끝 방향으로 밀어주세요',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '회원이 이 영상을 볼 때 $timeLabel 지점에서 그대로 표시됩니다. '
                '무엇이 잘못됐는지보다 어떻게 하면 되는지를 적어주세요.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('저장'),
        ),
      ],
    );
  }
}
