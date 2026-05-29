/// 예약/수업 상태 전이 bottom sheet (Phase 1.6, 화면 5.3).
///
/// 회원 상세의 "최근 수업" 카드 또는 트레이너 본인 예약 화면의 카드 탭 시 노출.
///
/// **표시 항목:**
///   - 회원 이름 / 일시 (호출 측에서 subtitle 으로 전달)
///   - 라디오: 예정 / 완료(=수업 기록 화면) / 정상취소 / 노쇼 / (취소 시각 기준 자동 분류 X)
///       → 정상취소/지각취소는 [cancel] 흐름으로 자동 분류. 라디오엔 "취소" 한 줄.
///   - 메모 (선택) — 회원 카톡/통화 내용 등
///   - 차감 규정 안내 (DeductionPolicy.defaultPolicy 기준)
///
/// **완료(done) 라디오:**
///   탭하면 시트를 닫고 `/trainer/members/:id/session/:sid` 로 이동 — 수업 기록 화면에서
///   본문을 채워 저장하면 createDoneSession 이 status=done 까지 처리.
///   즉, 본 시트는 done 으로 직접 INSERT 하지 않는다 (기록 본문 빠진 done 방지).
///
/// 와이어프레임 출처: docs/wireframes/05_booking.md 화면 5.3.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/deduction_rule.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/session.dart';
import 'session_providers.dart';

/// 시트 호출 함수.
///
/// [memberId] / [memberName] : 호출 측이 알고 있는 회원 정보 (회원 상세에선 자명).
/// [session] : 현재 표시 중인 수업/예약.
Future<void> showBookingStatusSheet(
  BuildContext context, {
  required Session session,
  required String memberId,
  required String memberName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _BookingStatusSheet(
      session: session,
      memberId: memberId,
      memberName: memberName,
    ),
  );
}

/// 라디오 옵션 — UI 측 묶음. lateCancel 은 라디오에 안 둠 (cancel 흐름이 자동 분류).
enum _Action { keepScheduled, recordDone, cancel, noShow }

extension on _Action {
  String get label {
    switch (this) {
      case _Action.keepScheduled:
        return '예정 (변경 없음)';
      case _Action.recordDone:
        return '완료 — 수업 기록 화면으로';
      case _Action.cancel:
        return '취소 — 시점에 따라 정상/지각 자동 분류';
      case _Action.noShow:
        return '노쇼 — 1회 차감';
    }
  }
}

class _BookingStatusSheet extends ConsumerStatefulWidget {
  const _BookingStatusSheet({
    required this.session,
    required this.memberId,
    required this.memberName,
  });

  final Session session;
  final String memberId;
  final String memberName;

  @override
  ConsumerState<_BookingStatusSheet> createState() =>
      _BookingStatusSheetState();
}

class _BookingStatusSheetState extends ConsumerState<_BookingStatusSheet> {
  late _Action _selected = _initialActionFor(widget.session.status);
  final _memoCtrl = TextEditingController();
  bool _memoInitialized = false;

  static _Action _initialActionFor(SessionStatus status) {
    switch (status) {
      case SessionStatus.scheduled:
        return _Action.keepScheduled;
      case SessionStatus.done:
        return _Action.recordDone;
      case SessionStatus.canceled:
      case SessionStatus.lateCancel:
        return _Action.cancel;
      case SessionStatus.noShow:
        return _Action.noShow;
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_memoInitialized) {
      _memoCtrl.text = widget.session.statusMemo ?? '';
      _memoInitialized = true;
    }
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final controller = ref.read(saveSessionControllerProvider.notifier);
    final memo = _memoCtrl.text.trim();
    final memoArg = memo.isEmpty ? '' : memo; // null = 미변경, '' = 비움

    switch (_selected) {
      case _Action.recordDone:
        // 시트 닫고 기록 화면으로 — 기록 본문 입력 후 저장하면 status=done 처리.
        // 예약된 수업의 id 를 그대로 들고 가서, 화면이 그 session 을 수정 모드로 연다.
        Navigator.of(context).pop();
        context.push(
          '/trainer/members/${widget.memberId}/session/${widget.session.id}',
        );
        return;

      case _Action.keepScheduled:
        // 이미 scheduled 면 status 변경 없이 메모만 동기화.
        if (widget.session.status == SessionStatus.scheduled) {
          if (memo == (widget.session.statusMemo ?? '')) {
            Navigator.of(context).pop();
            return;
          }
        }
        await controller.changeStatus(
          sessionId: widget.session.id,
          status: SessionStatus.scheduled,
          memberId: widget.memberId,
          memo: memoArg,
        );

      case _Action.cancel:
        await controller.cancel(
          sessionId: widget.session.id,
          scheduledAt: widget.session.scheduledAt,
          memberId: widget.memberId,
          memo: memoArg,
        );

      case _Action.noShow:
        await controller.changeStatus(
          sessionId: widget.session.id,
          status: SessionStatus.noShow,
          memberId: widget.memberId,
          memo: memoArg,
        );
    }

    if (!mounted) return;
    final state = ref.read(saveSessionControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.error?.toString() ?? '저장 실패')),
        );
      return;
    }
    // 차감 안내 — 노쇼/지각취소만.
    final appliedStatus = _projectedStatus();
    if (appliedStatus.deducts) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('1회 차감 처리되었습니다.')),
        );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('상태가 저장되었습니다.')),
        );
    }
    Navigator.of(context).pop();
  }

  /// 현재 선택과 시간 기준으로 *적용 후 예상되는* status. 안내 토스트 분기용.
  /// cancel 은 DeductionRule 로 즉시 분류해 본다.
  SessionStatus _projectedStatus() {
    switch (_selected) {
      case _Action.recordDone:
        return SessionStatus.done;
      case _Action.keepScheduled:
        return SessionStatus.scheduled;
      case _Action.cancel:
        return DeductionRule.classifyCancellation(
          scheduledAt: widget.session.scheduledAt,
          cancelAt: DateTime.now(),
        );
      case _Action.noShow:
        return SessionStatus.noShow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(saveSessionControllerProvider).isLoading;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.memberName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                fmt.format(widget.session.scheduledAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // ----- 라디오 -----
              // Flutter 3.32+ RadioGroup 신 API — groupValue/onChanged 가 RadioGroup
              // 로 이동. RadioListTile 은 value 만 가짐.
              //
              // 저장 중(saving) 비활성화는 onChanged 를 null 로 줄 수 없는 API 라
              // (ValueChanged<T?> 가 non-nullable) IgnorePointer 로 입력 차단.
              IgnorePointer(
                ignoring: saving,
                child: RadioGroup<_Action>(
                  groupValue: _selected,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selected = v);
                  },
                  child: Column(
                    children: [
                      for (final action in _Action.values)
                        RadioListTile<_Action>(
                          value: action,
                          title: Text(action.label),
                          dense: true,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ----- 메모 -----
              TextField(
                controller: _memoCtrl,
                enabled: !saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '메모 (선택)',
                  hintText: '예: 회원 카톡 "급한 일정" 17:30',
                ),
              ),
              const SizedBox(height: 12),

              // ----- 차감 규정 안내 -----
              _PolicyCard(scheduledAt: widget.session.scheduledAt),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : _apply,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_selected == _Action.recordDone
                      ? '수업 기록 화면으로'
                      : '저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.scheduledAt});
  final DateTime scheduledAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final policy = DeductionPolicy.defaultPolicy;
    final now = DateTime.now();
    final preview = DeductionRule.classifyCancellation(
      scheduledAt: scheduledAt,
      cancelAt: now,
      policy: policy,
    );
    final previewText = preview == SessionStatus.canceled
        ? '지금 취소 → 정상 취소 (차감 X)'
        : '지금 취소 → 지각 취소 (1회 차감)';

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.policy_outlined, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '차감 규정 (기본)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '• 수업 ${policy.cancelDeadlineHoursBefore}시간 전 이내 취소 / 노쇼: 1회 차감\n'
            '• 그보다 일찍 취소: 차감 없음\n'
            '• $previewText',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
