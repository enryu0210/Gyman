/// AI 안내 메시지 초안 생성 다이얼로그 (Phase 1.9 LLM 연동, 와이어 6.3 톤 옵션).
///
/// 진입점: [showGenerateDraftDialog] — 회원 상세 등에서 호출(memberId 컨텍스트 보유).
///
/// 흐름:
///   트리거/톤 선택 → [생성] → Edge Function 호출 → 성공 시 검수 큐(draft)에 적재.
///   성공하면 true 반환(호출 측이 SnackBar + AI 검수 이동 안내).
///
/// 폴백(develop_plan §7 / 와이어 6.5):
///   실패해도 앱이 멈추지 않고 다이얼로그 안에서 사유별 안내 + [다시 시도]/[직접 작성].
///   - consent_required : 동의 필요 → 회원 수정에서 동의 후 재시도 안내
///   - rate_limited     : 한도 초과
///   - llm_failed       : LLM 오류 → 다시 시도 또는 직접 작성
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_review_providers.dart';
import 'ai_review_repository.dart';

/// 생성 다이얼로그 호출. 생성 성공 시 true.
Future<bool?> showGenerateDraftDialog(
  BuildContext context, {
  required String memberId,
  required String memberName,
  String defaultTrigger = 'manual',
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _GenerateDraftDialog(
      memberId: memberId,
      memberName: memberName,
      defaultTrigger: defaultTrigger,
    ),
  );
}

/// 트리거 선택지 — (value=DB trigger_type, label=표시).
const _triggerOptions = <(String, String)>[
  ('manual', '일반 안내'),
  ('pre_session', '내일 수업 안내'),
  ('renewal_five_left', '잔여 5회 안내'),
  ('renewal_half', '절반 사용 안내'),
  ('renewal_expiring', '만료 임박 안내'),
];

/// 톤 선택지 — 그대로 서버로 전달(프롬프트에 반영).
const _toneOptions = <String>['친근하게', '격식 있게', '짧게', '자세하게'];

class _GenerateDraftDialog extends ConsumerStatefulWidget {
  const _GenerateDraftDialog({
    required this.memberId,
    required this.memberName,
    required this.defaultTrigger,
  });

  final String memberId;
  final String memberName;
  final String defaultTrigger;

  @override
  ConsumerState<_GenerateDraftDialog> createState() =>
      _GenerateDraftDialogState();
}

class _GenerateDraftDialogState extends ConsumerState<_GenerateDraftDialog> {
  late String _trigger = widget.defaultTrigger;
  String _tone = _toneOptions.first;
  bool _busy = false;
  AiGenerationException? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(aiReviewRepositoryProvider).generateMessageDraft(
            memberId: widget.memberId,
            triggerType: _trigger,
            tone: _tone,
          );
      // 검수 큐/배지 갱신.
      ref.invalidate(pendingMessagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AiGenerationException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (e) {
      // 예상 못한 오류도 앱이 멈추지 않게 흡수.
      if (!mounted) return;
      setState(() => _error =
          AiGenerationException(code: 'unknown', message: e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('AI 안내 메시지 초안'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.memberName} 회원에게 보낼 안내 메시지 초안을 AI 가 작성합니다. '
              '생성된 초안은 검수 큐에 쌓이고, 승인 전엔 회원에게 전송되지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            // 트리거 선택 — Flutter 3.32+ 는 value → initialValue.
            DropdownButtonFormField<String>(
              initialValue: _trigger,
              decoration: const InputDecoration(
                labelText: '안내 종류',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final (value, label) in _triggerOptions)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) setState(() => _trigger = v);
                    },
            ),
            const SizedBox(height: 12),

            // 톤 선택
            DropdownButtonFormField<String>(
              initialValue: _tone,
              decoration: const InputDecoration(
                labelText: '톤',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in _toneOptions)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) setState(() => _tone = v);
                    },
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(error: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _busy ? null : _generate,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_error == null ? '생성' : '다시 시도'),
        ),
      ],
    );
  }
}

/// 실패 사유별 안내 박스. code 로 추가 가이드를 분기.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});
  final AiGenerationException error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // code 별 보조 안내 — 트레이너가 다음에 뭘 할지 알려준다.
    String? hint;
    switch (error.code) {
      case 'consent_required':
        hint = '회원 상세 → 수정에서 AI 사용 동의를 받은 뒤 다시 시도하거나, 직접 작성해 주세요.';
      case 'rate_limited':
        hint = '오늘 한도가 찼습니다. 내일 다시 시도하거나 직접 작성해 주세요.';
      case 'llm_failed':
        hint = '잠시 후 [다시 시도] 하거나, 메시지를 직접 작성해 주세요.';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
