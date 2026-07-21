/// 메시지 초안 검수 다이얼로그 (Phase 1.9, 와이어 6.2/6.3).
///
/// 진입점: [showMessageReviewDialog] — 검수 허브 카드 탭 시 호출.
///
/// **버튼 동작:**
///   - 발송 취소   → status='canceled'
///   - 저장(재검수) → 내용 변경 시 editContent (status=draft 로 되돌려 재검수)
///   - 승인하고 발송 → status='sent' (approved_at+sent_at 한 번에, 회원에게 즉시 노출)
///   - 발송하기     → 과거 approved 로 남은 건만(markSent). 신규는 draft 에서 바로 발송.
///
/// 검수 전엔 회원에게 안 보임(sent 만 노출)을 화면에 명시(안전 게이트).
/// 내용을 수정하면 항상 draft 로 되돌려 재검수를 강제(수정본 무단 발송 차단).
///
/// 성공(상태 변경 발생) 시 true 반환.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/enums.dart';
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

  /// 승인하고 즉시 발송 — draft 를 곧바로 sent 로(회원 "받은 안내"에 노출).
  /// 내용이 바뀐 채로는 호출되지 않는다(버튼이 "저장(재검수)"로 전환되어 발송을 막음).
  Future<void> _approveAndSend() async {
    await ref
        .read(messageReviewControllerProvider.notifier)
        .approveAndSend(widget.draft.id);
    _finish('회원에게 발송되었습니다.');
  }

  Future<void> _save() async {
    await ref.read(messageReviewControllerProvider.notifier).editContent(
          id: widget.draft.id,
          content: _contentCtrl.text.trim(),
        );
    _finish('내용을 저장했습니다. 다시 검수 후 발송해 주세요.');
  }

  Future<void> _cancel() async {
    await ref
        .read(messageReviewControllerProvider.notifier)
        .cancel(widget.draft.id);
    _finish('발송을 보류했습니다.');
  }

  /// 발송(앱 내 전달) — 승인된 건을 sent 로 전이. 회원 "받은 안내"에 즉시 노출.
  /// 내용이 바뀐 채로는 호출되지 않는다(아래 버튼 로직이 저장을 먼저 강제).
  Future<void> _markSent() async {
    await ref
        .read(messageReviewControllerProvider.notifier)
        .markSent(widget.draft.id);
    _finish('회원에게 발송되었습니다.');
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
                        '이 메시지는 트레이너 검수를 거쳐야 회원에게 전달됩니다. '
                        '"승인하고 발송"을 누르면 회원의 "받은 안내"에 바로 '
                        '표시됩니다. (푸시 알림 없이 앱 내 전달)',
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
      // 버튼 2개 — 좁은 화면 대비 actionsOverflow 로 세로 정렬 허용.
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: busy ? null : _cancel,
          child: Text('발송 취소', style: TextStyle(color: colors.error)),
        ),
        FilledButton(
          // 주 액션은 "현재 상태 + 내용 변경 여부"로 한 가지로 결정한다:
          //   - 내용 수정됨 → 저장(재검수, draft 로). 수정한 채로 발송/승인되는 구멍 차단.
          //   - 승인됨    → 발송하기(sent 전이 → 회원 노출).
          //   - 그 외(초안) → 발송 승인(approved 전이).
          onPressed: busy ? null : _primaryAction,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_primaryLabel),
        ),
      ],
    );
  }

  /// 주 버튼 라벨 — 상태/변경 여부에 따라.
  String get _primaryLabel {
    if (_contentChanged) return '저장 (재검수)';
    // 승인됨(과거 데이터)만 남은 "발송하기" — 신규 흐름은 draft 에서 바로 발송.
    if (widget.draft.status == NotificationStatus.approved) return '발송하기';
    return '승인하고 발송';
  }

  /// 주 버튼 동작 — 라벨과 1:1.
  Future<void> _primaryAction() {
    if (_contentChanged) return _save();
    if (widget.draft.status == NotificationStatus.approved) return _markSent();
    return _approveAndSend();
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
