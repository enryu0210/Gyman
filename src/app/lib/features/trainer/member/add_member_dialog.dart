/// 회원 추가 다이얼로그.
///
/// 입력 항목: 이름(필수), 전화번호, 운동 목적.
/// 그 외 부상이력/체형/생활패턴 등은 회원 상세 화면(Phase 1.2-B)에서 편집.
/// 1.2-A는 "빠르게 회원 명단 만들기" UX 우선 — 최소 입력으로 한 명 추가.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'member_providers.dart';
import 'member_repository.dart';

/// 다이얼로그를 열고 성공 시 true 반환.
/// 호출 측은 결과에 따라 SnackBar 등을 띄움.
Future<bool?> showAddMemberDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AddMemberDialog(),
  );
}

class _AddMemberDialog extends ConsumerStatefulWidget {
  const _AddMemberDialog();

  @override
  ConsumerState<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<_AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();

  /// AI 사용 동의. **기본 false** — 실수로 켜지지 않게 항상 꺼진 채 시작하고,
  /// 트레이너가 회원에게 동의를 받았을 때만 체크한다.
  bool _aiConsent = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final input = NewMemberInput(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      goal: _goalCtrl.text.trim().isEmpty ? null : _goalCtrl.text.trim(),
      aiConsent: _aiConsent,
    );

    await ref.read(addMemberControllerProvider.notifier).addMember(input);

    // mounted 확인 — async gap 이후 위젯 폐기 가능성
    if (!mounted) return;

    final state = ref.read(addMemberControllerProvider);
    if (state.hasError) {
      // 에러 메시지 SnackBar — 다이얼로그는 유지 (사용자가 수정 후 재시도)
      final msg = state.error?.toString() ?? '회원 추가에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(addMemberControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('회원 추가'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              enabled: !saving,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '이름 *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              enabled: !saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '연락처',
                hintText: '010-0000-0000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _goalCtrl,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '운동 목적',
                hintText: '예: 체중감량, 근력 강화',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _AiConsentField(
              value: _aiConsent,
              enabled: !saving,
              onChanged: (v) => setState(() => _aiConsent = v),
            ),
            const SizedBox(height: 12),
            Text(
              '회원 정보를 추가합니다. 회원이 앱에 가입한 뒤 매핑하면\n'
              '본인이 직접 일정/기록을 열람할 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
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
              : const Text('추가'),
        ),
      ],
    );
  }
}

/// 등록 시점 AI 사용 동의 스위치 — 회원 수정 화면의 동의 카드와 같은 톤을
/// 쓰되(SwitchListTile + 강조 표면), 등록 화면의 "최소 입력" 성격에 맞춰
/// 긴 설명 문단은 생략한 간결형.
///
/// **개인정보의 제3자(LLM) 제공 동의라 텍스트 필드 사이에 스위치 하나만
/// 끼우지 않고 별도 카드로 구분한다** — 그래야 트레이너가 그냥 지나치지 않는다.
/// 상세 설명·되돌리기는 회원 상세의 [수정] 동의 카드에서. 기본은 꺼짐.
class _AiConsentField extends StatelessWidget {
  const _AiConsentField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).colorScheme.brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(brightness),
        border: Border.all(color: AppTheme.menuTileBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: const Icon(Icons.auto_awesome_outlined),
        title: const Text('AI 사용 동의'),
        subtitle: const Text(
          '회원에게 동의를 받았다면 켜 주세요. 켜면 이 회원 정보로 '
          'AI 초안·재등록 멘트를 생성할 수 있습니다.',
        ),
      ),
    );
  }
}
