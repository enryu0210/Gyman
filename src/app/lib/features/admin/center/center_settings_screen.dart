/// 관리자 센터 설정 화면 — Phase 3.2 (C2 전반부).
///
/// 라우트: `/admin/center` (admin 또는 트레이너 겸 admin 진입 — app_router).
///
/// **두 영역:**
///   1. 센터 규정 — 취소 가능 시간 / 노쇼 차감 / 지각 허용 시간. 저장 시 centers.rules.
///   2. PT 규정 FAQ — 추가·수정·삭제. 회원/트레이너가 FAQ 화면에서 열람(2.4 자리 채움).
///
/// 데이터는 [centerSettingsProvider], 쓰기는 [centerSettingsControllerProvider].
///
/// 참고: docs/develop_plan.md §4 Phase 3.2, 0031(RLS/테이블).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/center_rules.dart';
import 'add_center_faq_dialog.dart';
import 'center_settings_providers.dart';
import 'center_settings_repository.dart';

class CenterSettingsScreen extends ConsumerWidget {
  const CenterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(centerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('센터 설정')),
      body: settings.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '센터 설정을 불러오지 못했습니다.',
          detail: e.toString(),
          onRetry: () => ref.invalidate(centerSettingsProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(centerSettingsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                data.centerName,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              // 규정 폼은 초기값(로드된 rules)로 자기 상태를 들고 있어야 하므로
              // key 에 규정을 엮어, 새로고침으로 값이 바뀌면 폼도 재생성되게 한다.
              _RulesForm(
                key: ValueKey(data.rules.toJson().toString()),
                centerId: data.centerId,
                initial: data.rules,
              ),
              const SizedBox(height: 28),
              _FaqSection(faqs: data.faqs),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 1. 센터 규정 폼
// =====================================================================

class _RulesForm extends ConsumerStatefulWidget {
  const _RulesForm({
    super.key,
    required this.centerId,
    required this.initial,
  });

  final String centerId;
  final CenterRules initial;

  @override
  ConsumerState<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends ConsumerState<_RulesForm> {
  late final TextEditingController _cancelCtrl;
  late final TextEditingController _lateCtrl;
  late bool _noShowDeduct;

  @override
  void initState() {
    super.initState();
    _cancelCtrl = TextEditingController(
      text: widget.initial.lateCancelHours?.toString() ?? '',
    );
    _lateCtrl = TextEditingController(
      text: widget.initial.lateArrivalMinutes?.toString() ?? '',
    );
    _noShowDeduct = widget.initial.noShowDeduct;
  }

  @override
  void dispose() {
    _cancelCtrl.dispose();
    _lateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rules = CenterRules(
      lateCancelHours: _parseOrNull(_cancelCtrl.text),
      noShowDeduct: _noShowDeduct,
      lateArrivalMinutes: _parseOrNull(_lateCtrl.text),
    );

    await ref
        .read(centerSettingsControllerProvider.notifier)
        .saveRules(widget.centerId, rules);

    if (!mounted) return;
    final state = ref.read(centerSettingsControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          state.hasError
              ? '저장 실패: ${state.error}'
              : '센터 규정을 저장했습니다.',
        ),
      ),
    );
  }

  static int? _parseOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(centerSettingsControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('센터 규정'),
        const SizedBox(height: 4),
        Text(
          '회원·트레이너가 공유하는 PT 운영 규정입니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _cancelCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '취소 가능 시간',
                    helperText: '수업 몇 시간 전까지 취소하면 차감 안 됨 (비우면 미설정)',
                    suffixText: '시간 전',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lateCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '지각 허용 시간',
                    helperText: '이 시간까지 지각은 봐줌 (비우면 미설정)',
                    suffixText: '분',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('노쇼 시 횟수 차감'),
                  subtitle: const Text('무단 불참(노쇼) 시 PT 횟수를 차감합니다.'),
                  value: _noShowDeduct,
                  onChanged: saving
                      ? null
                      : (v) => setState(() => _noShowDeduct = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('규정 저장'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 2. PT 규정 FAQ 섹션
// =====================================================================

class _FaqSection extends ConsumerWidget {
  const _FaqSection({required this.faqs});

  final List<CenterFaq> faqs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('PT 규정 FAQ')),
            TextButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('추가'),
            ),
          ],
        ),
        Text(
          '여기에 입력한 내용이 회원 앱의 FAQ 화면에 노출됩니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (faqs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '아직 등록된 FAQ가 없습니다. "추가"로 취소·환불·프로그램 규정을 입력해 보세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < faqs.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FaqTile(faq: faqs[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    await showCenterFaqDialog(context);
  }
}

class _FaqTile extends ConsumerWidget {
  const _FaqTile({required this.faq});

  final CenterFaq faq;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(faq.question),
      subtitle: Text(
        faq.answer,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showCenterFaqDialog(context, existing: faq),
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('FAQ 삭제'),
        content: Text('"${faq.question}" 항목을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(centerSettingsControllerProvider.notifier).deleteFaq(faq.id);

    if (!context.mounted) return;
    final state = ref.read(centerSettingsControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('삭제 실패: ${state.error}')));
    }
  }
}

// =====================================================================
// 공용 소품
// =====================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

