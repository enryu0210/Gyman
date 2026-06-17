/// 설정 화면용 "PT 수업 알림" 타일 + 리드타임 선택 시트.
///
/// 회원 전용(본인 PT 예약 기준 알림). 설정 화면(`features/settings`)에서 회원일 때만
/// 노출한다. 선택 시 [PtReminderLeadController.setLead] 가 저장·권한요청·재동기화 처리.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/pt_reminder.dart';
import 'pt_reminder_providers.dart';

class PtReminderSettingTile extends ConsumerWidget {
  const PtReminderSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로딩 중엔 기본값(1시간 전)을 보여줘 깜빡임 방지.
    final lead =
        ref.watch(ptReminderLeadProvider).valueOrNull ?? PtReminderLead.hour1;

    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('PT 수업 알림'),
      subtitle: Text(
        lead.isOn ? '수업 시작 ${lead.label} 알려드려요' : '꺼짐',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            lead.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _showPicker(context, ref, lead),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    WidgetRef ref,
    PtReminderLead current,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'PT 수업 알림',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final lead in PtReminderLead.values)
              ListTile(
                title: Text(lead.label),
                trailing: lead == current
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(ptReminderLeadProvider.notifier)
                      .setLead(lead);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
