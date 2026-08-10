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

  /// 개인정보 수집·이용 동의를 회원 본인에게 받았는지 트레이너가 확인 (0041).
  ///
  /// **체크해야만 [추가] 버튼이 활성화된다.** AI 동의(선택)와 달리 이건
  /// 개인정보를 수집해도 되는지의 근거라, 없으면 등록 자체가 성립하지 않는다.
  /// 서버 트리거도 같은 조건으로 막으므로 UI 를 우회해도 통과하지 못한다.
  bool _offlineConsentConfirmed = false;

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
      offlineConsentConfirmed: _offlineConsentConfirmed,
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
            // 개인정보 동의 확인이 AI 동의보다 **위**에 온다 — 이게 등록의
            // 전제 조건이고 AI 동의는 부가 기능이라, 읽는 순서가 곧 중요도다.
            _OfflineConsentField(
              value: _offlineConsentConfirmed,
              enabled: !saving,
              onChanged: (v) =>
                  setState(() => _offlineConsentConfirmed = v ?? false),
            ),
            const SizedBox(height: 12),
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
          // 동의 확인 없이는 등록 불가 — 서버 트리거(0041)와 같은 조건을
          // 화면에서도 걸어, 눌렀다가 에러를 보는 대신 왜 안 되는지 보이게 한다.
          onPressed:
              (saving || !_offlineConsentConfirmed) ? null : _submit,
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

/// 개인정보 수집·이용 동의 확인 체크박스 (마이그레이션 0041).
///
/// **왜 스위치가 아니라 체크박스인가:** AI 동의는 켜고 끄는 설정(스위치)이지만,
/// 이건 "받았음을 확인한다"는 1회성 확인 행위다. 되돌리는 개념이 없다.
///
/// **왜 등록 화면에 있는가:** 앱에 가입하지 않은 회원은 약관을 볼 수도, 동의를
/// 남길 계정도 없다. 그런데 트레이너는 그 사람의 이름·연락처·부상 이력까지
/// 입력한다. 개인정보를 받아 적는 그 순간이 동의를 확인할 유일한 지점이다.
/// 근거: docs/legal_docs_gap_check.md §C, 이용약관 제5조 3항.
class _OfflineConsentField extends StatelessWidget {
  const _OfflineConsentField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(brightness),
        // 미확인 상태를 테두리로 드러낸다 — 등록을 막고 있는 항목이 무엇인지
        // 버튼이 회색인 이유와 눈으로 연결되게.
        border: Border.all(
          color: value ? AppTheme.menuTileBorder(brightness) : colors.error,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('개인정보 수집·이용 동의 확인 (필수)'),
        subtitle: const Text(
          '회원 본인(미성년자인 경우 법정대리인)에게 이름·연락처·부상 이력 등의 '
          '수집·이용에 대한 동의를 받았습니다. 확인한 트레이너와 시각이 '
          '기록됩니다.',
        ),
      ),
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
