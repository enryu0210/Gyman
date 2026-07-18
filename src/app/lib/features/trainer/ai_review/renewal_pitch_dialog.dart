/// AI 재등록 유도 멘트 다이얼로그 (Phase 1.7 재등록 알림 + 1.9 검수 게이트 연동).
///
/// 진입점: [showRenewalPitchDialog] — 재등록 알림 행(만료 임박/5회 이하/절반 사용)에서
/// 호출(memberId/contractId 컨텍스트 보유).
///
/// 흐름(2단계):
///   1) [분석하고 생성] → Edge Function(generate-renewal-pitch)이 회원의 운동 중량 변화 +
///      인바디 변화 + 계약 현황을 분석해 재등록 유도 멘트 초안을 만들어 검수 큐(draft)에 적재.
///   2) 생성된 멘트를 트레이너가 확인·수정 →
///      - [승인하고 발송] : 회원 "받은 안내"에 즉시 노출(approve → markSent)
///      - [검수함에 보관] : draft 로 남겨 나중에 AI 검수 화면에서 처리
///
/// 성공(회원에게 발송) 시 true 반환.
///
/// 폴백(develop_plan §7): 실패해도 앱이 멈추지 않고 사유별 안내 + [다시 시도]/[직접 작성].
///   - consent_required : 동의 필요
///   - rate_limited     : 한도 초과
///   - no_progress_data : 분석할 운동/인바디 기록 없음 → 직접 작성 유도
///   - llm_failed       : LLM 오류
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_review_providers.dart';
import 'ai_review_repository.dart';

/// 재등록 유도 멘트 다이얼로그 호출. 회원에게 발송까지 완료하면 true.
Future<bool?> showRenewalPitchDialog(
  BuildContext context, {
  required String memberId,
  required String memberName,
  String? contractId,
}) {
  return showDialog<bool>(
    context: context,
    // 생성/발송 중 바깥 탭으로 실수 닫힘 방지 — 종료는 명시 버튼으로만.
    barrierDismissible: false,
    builder: (_) => _RenewalPitchDialog(
      memberId: memberId,
      memberName: memberName,
      contractId: contractId,
    ),
  );
}

class _RenewalPitchDialog extends ConsumerStatefulWidget {
  const _RenewalPitchDialog({
    required this.memberId,
    required this.memberName,
    required this.contractId,
  });

  final String memberId;
  final String memberName;
  final String? contractId;

  @override
  ConsumerState<_RenewalPitchDialog> createState() =>
      _RenewalPitchDialogState();
}

class _RenewalPitchDialogState extends ConsumerState<_RenewalPitchDialog> {
  // State 에 두어 리빌드돼도 한글 IME 조합이 끊기지 않게 한다(CLAUDE.md 다이얼로그 패턴).
  final TextEditingController _contentCtrl = TextEditingController();

  /// 생성된 초안 id. null 이면 아직 생성 전(1단계).
  String? _draftId;

  /// 생성 직후 원본 — 트레이너가 수정했는지 판별용.
  String _originalContent = '';

  /// 생성 또는 발송 처리 중.
  bool _busy = false;

  AiGenerationException? _error;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _generated => _draftId != null;
  bool get _contentChanged =>
      _contentCtrl.text.trim() != _originalContent.trim();

  // ---------------------------------------------------------------------
  // 1단계 — 진척 분석 + 멘트 생성
  // ---------------------------------------------------------------------
  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(aiReviewRepositoryProvider).generateRenewalPitch(
                memberId: widget.memberId,
                contractId: widget.contractId,
              );
      // 초안이 draft 로 적재됐으니 검수 큐/배지 갱신.
      ref.invalidate(pendingMessagesProvider);
      if (!mounted) return;
      setState(() {
        _draftId = result.draftId;
        _originalContent = result.content;
        _contentCtrl.text = result.content;
      });
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

  // ---------------------------------------------------------------------
  // 2단계 — 승인하고 발송 (회원 "받은 안내"에 즉시 노출)
  //   수정됨 → 저장(editContent) → 승인(approve) → 발송(markSent) 순.
  //   Supabase 는 다중 테이블 트랜잭션 미지원이라 단계별로 확인하며 진행하되,
  //   중간 실패해도 draft/approved 로 남아 AI 검수 화면에서 복구 가능(무결성 유지).
  // ---------------------------------------------------------------------
  Future<void> _approveAndSend() async {
    final id = _draftId;
    if (id == null) return;
    setState(() => _busy = true);
    final controller = ref.read(messageReviewControllerProvider.notifier);

    // 컨트롤러 액션 1회 실행 후 에러 확인. 실패면 busy 해제 + 안내 후 false.
    Future<bool> step(Future<void> Function() run) async {
      await run();
      if (!mounted) return false;
      if (ref.read(messageReviewControllerProvider).hasError) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('처리에 실패했습니다. 잠시 후 다시 시도해 주세요.'),
          ));
        return false;
      }
      return true;
    }

    if (_contentChanged) {
      final ok = await step(
        () => controller.editContent(id: id, content: _contentCtrl.text.trim()),
      );
      if (!ok) return;
    }
    if (!await step(() => controller.approve(id))) return;
    if (!await step(() => controller.markSent(id))) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('재등록 유도 멘트를 회원에게 발송했습니다.'),
      ));
    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------
  // 2단계 — 검수함에 보관 (draft 유지, 나중에 AI 검수 화면에서 처리)
  //   수정분이 있으면 저장만 하고 닫는다.
  // ---------------------------------------------------------------------
  Future<void> _keepAsDraft() async {
    final id = _draftId;
    if (id == null) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_contentChanged) {
        await ref
            .read(messageReviewControllerProvider.notifier)
            .editContent(id: id, content: _contentCtrl.text.trim());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('AI 검수함에 보관했습니다.'),
        ));
      Navigator.of(context).pop(false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('AI 재등록 유도 멘트'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _generated ? _reviewChildren(colors) : _introChildren(colors),
          ),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: _generated ? _reviewActions() : _introActions(),
    );
  }

  // ----- 1단계 본문/버튼 -----
  List<Widget> _introChildren(ColorScheme colors) {
    return [
      Text(
        '${widget.memberName} 회원의 운동 중량 변화와 인바디 변화를 AI 가 분석해 '
        '재등록 유도 멘트 초안을 만듭니다. 생성된 멘트는 트레이너 검수·승인 전엔 '
        '회원에게 전송되지 않습니다.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _ErrorBox(error: _error!),
      ],
    ];
  }

  List<Widget> _introActions() {
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('닫기'),
      ),
      FilledButton(
        onPressed: _busy ? null : _generate,
        child: _busy
            ? const _BtnSpinner()
            : Text(_error == null ? '분석하고 생성' : '다시 시도'),
      ),
    ];
  }

  // ----- 2단계 본문/버튼 -----
  List<Widget> _reviewChildren(ColorScheme colors) {
    return [
      TextField(
        controller: _contentCtrl,
        enabled: !_busy,
        maxLines: 8,
        minLines: 5,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: '재등록 유도 멘트 (수정 가능)',
        ),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '"승인하고 발송"을 누르면 회원의 "받은 안내"에 바로 표시됩니다. '
                '나중에 처리하려면 "검수함에 보관"을 눌러 AI 검수 화면에서 다룰 수 있어요.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _ErrorBox(error: _error!),
      ],
    ];
  }

  List<Widget> _reviewActions() {
    return [
      TextButton(
        onPressed: _busy ? null : _keepAsDraft,
        child: const Text('검수함에 보관'),
      ),
      FilledButton(
        onPressed: _busy ? null : _approveAndSend,
        child: _busy ? const _BtnSpinner() : const Text('승인하고 발송'),
      ),
    ];
  }
}

/// 버튼 안 스피너 — 다크 배경 대비 확보를 위해 onPrimary 색.
class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// 실패 사유별 안내 박스. code 로 트레이너가 다음에 뭘 할지 안내.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});
  final AiGenerationException error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    String? hint;
    switch (error.code) {
      case 'consent_required':
        hint = '회원 상세 → 수정에서 AI 사용 동의를 받은 뒤 다시 시도하거나, 직접 작성해 주세요.';
      case 'rate_limited':
        hint = '오늘 한도가 찼습니다. 내일 다시 시도하거나 직접 작성해 주세요.';
      case 'no_progress_data':
        hint = '분석할 운동/인바디 기록이 아직 없어요. 수업 기록이나 인바디 측정을 남긴 뒤 다시 시도해 주세요.';
      case 'llm_failed':
      case 'network':
        hint = '잠시 후 [다시 시도] 하거나, 멘트를 직접 작성해 주세요.';
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
