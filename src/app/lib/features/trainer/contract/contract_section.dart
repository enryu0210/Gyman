/// 회원 상세 화면의 "현재 계약" 섹션 위젯 (Phase 1.3).
///
/// 회원 1명의 활성 계약을 카드로 표시한다. 각 카드:
///   - 총 횟수 / 잔여 횟수 / D-N (만료일까지)
///   - 시작일·만료일·가격·메모
///   - 만료(잔여 0)된 계약은 회색 + "만료" 배지
///   - soft delete (확인 다이얼로그)
///
/// 신규 계약은 상단 [+ 계약 추가] 버튼.
///
/// **잔여 횟수 표시 출처:**
///   v_contract_status view (`contractStatusForMemberProvider`).
///   pt_contracts 메타(가격/메모)는 `contractsForMemberProvider`에서.
///   두 provider 결과를 contract_id로 join.
///
/// 참고: docs/wireframes/04_member_card.md 화면 4.2 "현재 계약" 카드.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/pt_contract.dart';
import '../../../domain/renewal_calculator.dart';
import '../renewal/renewal_alerts_card.dart';
import 'add_contract_dialog.dart';
import 'contract_providers.dart';
import 'contract_repository.dart';

class ContractSection extends ConsumerWidget {
  const ContractSection({super.key, required this.memberId});

  /// 회원 ID — 어떤 회원의 계약을 보여줄지 결정.
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractsForMemberProvider(memberId));
    final statusAsync = ref.watch(contractStatusForMemberProvider(memberId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(memberId: memberId),
            const SizedBox(height: 8),
            // 두 provider 가 모두 로드된 후에 화면 그림.
            // 하나라도 로딩이면 인디케이터, 하나라도 에러면 에러 텍스트.
            _buildBody(context, ref, contractsAsync, statusAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PtContract>> contractsAsync,
    AsyncValue<List<ContractStatusRow>> statusAsync,
  ) {
    if (contractsAsync.isLoading || statusAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (contractsAsync.hasError) {
      return _ErrorRow(
        message: contractsAsync.error.toString(),
        onRetry: () =>
            ref.invalidate(contractsForMemberProvider(memberId)),
      );
    }
    if (statusAsync.hasError) {
      return _ErrorRow(
        message: statusAsync.error.toString(),
        onRetry: () =>
            ref.invalidate(contractStatusForMemberProvider(memberId)),
      );
    }

    final contracts = contractsAsync.value ?? const <PtContract>[];
    final statuses = statusAsync.value ?? const <ContractStatusRow>[];

    if (contracts.isEmpty) {
      return const _EmptyView();
    }

    // contract_id → ContractStatusRow 매핑. 한 번만 생성.
    final statusById = {for (final s in statuses) s.contractId: s};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in contracts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _ContractCard(
              contract: c,
              status: statusById[c.id],
            ),
          ),
      ],
    );
  }
}

// =====================================================================
// 헤더 — 제목 + 추가 버튼
// =====================================================================

class _Header extends ConsumerWidget {
  const _Header({required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final adding = ref.watch(addContractControllerProvider).isLoading;

    return Row(
      children: [
        Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '현재 계약',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          onPressed: adding
              ? null
              : () async {
                  final added = await showAddContractDialog(
                    context,
                    memberId: memberId,
                  );
                  if (added == true && context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('계약이 등록되었습니다.')),
                      );
                  }
                },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('계약 추가'),
        ),
      ],
    );
  }
}

// =====================================================================
// 비어 있음 / 에러
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '등록된 계약이 없습니다. 오른쪽 위 [계약 추가] 버튼으로 등록하세요.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '계약 정보를 불러오지 못했습니다.\n$message',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

// =====================================================================
// 계약 1건 카드
// =====================================================================

class _ContractCard extends ConsumerWidget {
  const _ContractCard({required this.contract, required this.status});

  final PtContract contract;
  final ContractStatusRow? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isExhausted = status?.isExhausted ?? false;
    final fmtDate = DateFormat('yyyy-MM-dd');
    final fmtPrice = NumberFormat('#,###');

    final remaining = status?.remainingSessions ?? contract.totalSessions;
    final used = status?.usedSessions ?? 0;

    // 알림 단계 계산 — view 집계값 기반(가벼운 변종). 본 카드는 회원 1명/계약 1건
    // 컨텍스트라 페이스 기반 estimate 까지는 불필요.
    final alertLevel = RenewalCalculator.getAlertLevelFromCounts(
      total: contract.totalSessions,
      used: used,
      remaining: remaining,
      endDate: contract.endDate,
    );

    return Container(
      decoration: BoxDecoration(
        color: isExhausted
            ? colors.surfaceContainerLow
            : colors.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${contract.totalSessions}회 PT · 잔여 $remaining회',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isExhausted ? colors.onSurfaceVariant : null,
                  ),
                ),
              ),
              // 알림 chip — none 이면 안 그림. expiring 시 "만료" chip 과 겹치는데
              // expiring 라벨 자체가 "만료 임박" 이라 만료된 계약도 동일하게 표시됨.
              if (alertLevel != RenewalAlertLevel.none)
                _AlertChip(level: alertLevel)
              else if (isExhausted)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('만료'),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                  backgroundColor: colors.surfaceContainerHighest,
                  side: BorderSide.none,
                ),
              _ContractMenu(contract: contract),
            ],
          ),
          const SizedBox(height: 6),
          _MetaLine(
            icon: Icons.event_outlined,
            text:
                '시작 ${fmtDate.format(contract.startDate)}'
                '${contract.endDate != null ? ' · 만료 ${fmtDate.format(contract.endDate!)}' : ''}',
          ),
          _MetaLine(
            icon: Icons.bar_chart_outlined,
            text: '사용 $used · 잔여 $remaining (총 ${contract.totalSessions})',
          ),
          if (contract.price != null)
            _MetaLine(
              icon: Icons.payments_outlined,
              text: '${fmtPrice.format(contract.price)}원',
            ),
          if ((contract.memo ?? '').isNotEmpty)
            _MetaLine(
              icon: Icons.sticky_note_2_outlined,
              text: contract.memo!,
            ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractMenu extends ConsumerWidget {
  const _ContractMenu({required this.contract});
  final PtContract contract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ContractMenuAction>(
      tooltip: '계약 메뉴',
      iconSize: 20,
      padding: EdgeInsets.zero,
      onSelected: (action) async {
        switch (action) {
          case _ContractMenuAction.delete:
            final confirmed = await _confirmDelete(context, contract);
            if (confirmed != true || !context.mounted) return;
            await ref
                .read(addContractControllerProvider.notifier)
                .softDelete(
                  contractId: contract.id,
                  memberId: contract.memberId,
                );
            if (!context.mounted) return;
            final state = ref.read(addContractControllerProvider);
            if (state.hasError) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      state.error?.toString() ?? '계약 삭제에 실패했습니다.',
                    ),
                  ),
                );
              return;
            }
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('계약이 삭제되었습니다.')),
              );
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _ContractMenuAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('삭제', style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, PtContract c) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계약 삭제'),
        content: Text(
          '${c.totalSessions}회 PT 계약을 삭제하시겠습니까?\n'
          '잔여 횟수 계산에서 즉시 제외되지만 기록은 보존됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

enum _ContractMenuAction { delete }

/// 알림 단계 chip — renewal_alerts_card 의 [renewalAlertStyle] 재사용해서
/// 홈 카드와 동일한 색/라벨 톤 유지.
class _AlertChip extends StatelessWidget {
  const _AlertChip({required this.level});
  final RenewalAlertLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = renewalAlertStyle(level, colors);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 12, color: style.fg),
            const SizedBox(width: 3),
            Text(
              style.label,
              style: TextStyle(
                fontSize: 11,
                color: style.fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
