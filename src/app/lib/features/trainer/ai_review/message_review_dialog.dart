/// 메시지 초안 검수 다이얼로그 (Phase 1.9, 와이어 6.2/6.3).
///
/// 진입점: [showMessageReviewDialog] — 검수 허브 카드 탭 시 호출.
///
/// **버튼 동작 (와이어 6.2):**
///   - 발송 취소  → status='canceled'
///   - 저장       → 내용 변경 시 editContent (status=draft 재검수)
///   - 발송 승인  → status='approved', approved_at=now
///
/// 승인 전엔 회원에게 전송되지 않음을 화면에 명시(안전 게이트).
/// 실제 발송 채널(FCM/회원앱)은 준비 중 — 승인은 "검수 통과" 기록까지만.
///
/// 성공(상태 변경 발생) 시 true 반환.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'ai_review_providers.dart';
import 'ai_review_repository.dart';

/// 검수 다이얼로그 호출.
Future<bool?> showMessageReviewDialog(
  BuildContext context, {
  required MessageDraft draft,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _MessageReviewDialog(draft: draft),
  );
}

class _MessageReviewDialog extends ConsumerStatefulWidget {
  const _MessageReviewDialog({required this.draft});
  final MessageDraft draft;

  @override
  ConsumerState<_MessageReviewDialog> createState() =>
      _MessageReviewDialogState();
}

class _MessageReviewDialogState extends ConsumerState<_MessageReviewDialog> {
  late final TextEditingController _contentCtrl =
      TextEditingController(text: widget.draft.content);

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _contentChanged =>
      _contentCtrl.text.trim() != widget.draft.content.trim();

  /// 공통 후처리 — 에러면 SnackBar, 성공이면 다이얼로그 닫고 true 반환.
  void _finish(String successMessage) {
    if (!mounted) return;
    final state = ref.read(messageReviewControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.error?.toString() ?? '처리 실패')),
        );
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMessage)));
    Navigator.of(context).pop(true);
  }

  Future<void> _approve() async {
    final controller = ref.read(messageReviewControllerProvider.notifier);
    // 내용이 바뀌었으면 먼저 저장(=draft 로 재검수)하고, 그 위에 승인.
    if (_contentChanged) {
      await controller.editContent(
        id: widget.draft.id,
        content: _contentCtrl.text.trim(),
      );
      if (ref.read(messageReviewControllerProvider).hasError) {
        _finish('');
        return;
      }
    }
    await controller.approve(widget.draft.id);
    _finish('발송 승인되었습니다. (실제 발송 채널 준비 후 전송)');
  }

  Future<void> _save() async {
    await ref.read(messageReviewControllerProvider.notifier).editContent(
          id: widget.draft.id,
          content: _contentCtrl.text.trim(),
        );
    _finish('내용을 저장했습니다. 다시 검수 후 승인해 주세요.');
  }

  Future<void> _cancel() async {
    await ref
        .read(messageReviewControllerProvider.notifier)
        .cancel(widget.draft.id);
    _finish('발송을 보류했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(messageReviewControllerProvider).isLoading;
    final colors = Theme.of(context).colorScheme;
    final d = widget.draft;
    final scheduled =
        DateFormat('M월 d일 HH:mm').format(d.scheduledFor);

    return AlertDialog(
      title: const Text('메시지 검수'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 메타 정보
              _MetaRow(label: '대상', value: d.memberName),
              _MetaRow(label: '트리거', value: triggerTypeLabel(d.triggerType)),
              _MetaRow(label: '발송 예정', value: scheduled),
              _MetaRow(
                label: '생성',
                value: d.aiGenerated ? 'AI 초안' : '기본 템플릿',
              ),
              const SizedBox(height: 12),

              // 내용 (수정 가능)
              TextField(
                controller: _contentCtrl,
                enabled: !busy,
                maxLines: 8,
                minLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '메시지 내용 (수정 가능)',
                ),
              ),
              const SizedBox(height: 10),

              // 안전 안내
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '이 메시지는 트레이너 승인 전까지 회원에게 전송되지 않습니다. '
                        '실제 발송 채널(FCM/회원앱)은 준비 중이라, 현재 "승인"은 검수 '
                        '통과 상태만 기록합니다.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // 버튼 3개 — 좁은 화면 대비 actionsOverflow 로 세로 정렬 허용.
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: busy ? null : _cancel,
          child: Text('발송 취소', style: TextStyle(color: colors.error)),
        ),
        TextButton(
          // 변경 없으면 저장 비활성화 — 헛 저장 방지.
          onPressed: (busy || !_contentChanged) ? null : _save,
          child: const Text('내용 저장'),
        ),
        FilledButton(
          onPressed: busy ? null : _approve,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('발송 승인'),
        ),
      ],
    );
  }
}

/// 라벨: 값 한 줄. 검수 메타 정보 표시용.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
