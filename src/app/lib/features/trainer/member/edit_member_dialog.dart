/// 회원 정보 수정 다이얼로그 (Phase 1.2-B).
///
/// 입력 항목: 이름(필수), 연락처, 생년월일, 목적/경험/부상이력/체형/생활패턴,
/// AI 사용 동의.
/// 추가 다이얼로그(add_member_dialog)와 달리 *전체 필드*를 노출해서 한 화면에서
/// 모든 정보를 채울 수 있게 한다. 회원 카드 첫 등록은 이름만으로 빠르게 만들고
/// 이 화면에서 살을 붙이는 흐름.
///
/// **빈 문자열 → null 변환 규칙:**
///   사용자가 필드를 비워두면 빈 문자열로 도착 → null로 변환 후 저장.
///   "값이 있다가 비워짐" 도 동일하게 처리 (DB의 NULL 로 덮어쓰기).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/member.dart';
import 'member_providers.dart';
import 'member_repository.dart';

/// 수정 다이얼로그 호출 — 성공 시 true.
Future<bool?> showEditMemberDialog(BuildContext context, Member member) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditMemberDialog(member: member),
  );
}

class _EditMemberDialog extends ConsumerStatefulWidget {
  const _EditMemberDialog({required this.member});
  final Member member;

  @override
  ConsumerState<_EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends ConsumerState<_EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _experienceCtrl;
  late final TextEditingController _injuryCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _lifestyleCtrl;
  DateTime? _birthDate;
  late bool _aiConsent;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _aiConsent = m.aiConsent;
    _nameCtrl = TextEditingController(text: m.name);
    _phoneCtrl = TextEditingController(text: m.phone ?? '');
    _goalCtrl = TextEditingController(text: m.goal ?? '');
    _experienceCtrl = TextEditingController(text: m.experience ?? '');
    _injuryCtrl = TextEditingController(text: m.injuryHistory ?? '');
    _bodyCtrl = TextEditingController(text: m.bodyFeatures ?? '');
    _lifestyleCtrl = TextEditingController(text: m.lifestyle ?? '');
    _birthDate = m.birthDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _goalCtrl.dispose();
    _experienceCtrl.dispose();
    _injuryCtrl.dispose();
    _bodyCtrl.dispose();
    _lifestyleCtrl.dispose();
    super.dispose();
  }

  /// 빈 문자열 → null. trim 포함.
  String? _trimToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDate ?? DateTime(now.year - 30, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '생년월일 선택',
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final input = UpdateMemberInput(
      name: _nameCtrl.text.trim(),
      phone: _trimToNull(_phoneCtrl.text),
      goal: _trimToNull(_goalCtrl.text),
      experience: _trimToNull(_experienceCtrl.text),
      injuryHistory: _trimToNull(_injuryCtrl.text),
      bodyFeatures: _trimToNull(_bodyCtrl.text),
      lifestyle: _trimToNull(_lifestyleCtrl.text),
      birthDate: _birthDate,
      aiConsent: _aiConsent,
    );

    await ref
        .read(editMemberControllerProvider.notifier)
        .updateMember(memberId: widget.member.id, input: input);

    if (!mounted) return;

    final state = ref.read(editMemberControllerProvider);
    if (state.hasError) {
      final msg = state.error?.toString() ?? '수정에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(editMemberControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('회원 정보 수정'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '이름 *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '이름을 입력해 주세요.'
                      : null,
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
                _BirthDateField(
                  birthDate: _birthDate,
                  enabled: !saving,
                  onPick: _pickBirthDate,
                  onClear: () => setState(() => _birthDate = null),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _experienceCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '운동 경험',
                    hintText: '예: 헬스 1년, PT 처음',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _injuryCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '부상 이력',
                    hintText: '예: 6개월 전 발목 인대 부상',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '체형 특징',
                    hintText: '예: 라운드숄더 경향',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lifestyleCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '생활 패턴',
                    hintText: '예: 야근 잦음, 평일 저녁만 가능',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                _AiConsentField(
                  value: _aiConsent,
                  enabled: !saving,
                  onChanged: (v) => setState(() => _aiConsent = v),
                ),
              ],
            ),
          ),
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
              : const Text('저장'),
        ),
      ],
    );
  }
}

/// AI 사용 동의 토글.
///
/// **왜 다른 필드처럼 나열하지 않고 별도 카드로 뺐나:**
///   이건 취향 설정이 아니라 *개인정보의 제3자(LLM) 제공 동의*다. 켜는 순간
///   회원의 수업 기록·인바디가 외부 API 로 나가므로, 무엇이 전송되는지 트레이너가
///   읽고 켜야 한다. 텍스트 필드 사이에 스위치 하나만 끼워 넣으면 그냥 지나친다.
///
/// 동의의 주체는 회원이고 입력 주체는 트레이너 — "회원에게 동의를 받았다"를
/// 트레이너가 대신 기록하는 형태다(영상 업로드 동의 게이트와 같은 MVP 방식,
/// 설계 §9.6). 서버 측 `ai_consent` 확인이 실제 차단선이고 이 토글은 그 값을 켠다.
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final brightness = colors.brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(brightness),
        border: Border.all(color: AppTheme.menuTileBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: value,
            onChanged: enabled ? onChanged : null,
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI 사용 동의'),
            subtitle: const Text('회원에게 동의를 받은 경우에만 켜 주세요.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              value
                  ? '이 회원의 수업 기록·인바디 정보가 이름을 가린 채 AI 에 전달되어 '
                        '메시지·메모 초안과 재등록 멘트 생성에 쓰입니다. '
                        '생성된 내용은 항상 트레이너 검수를 거친 뒤 발송됩니다.'
                  : '꺼진 상태에서는 AI 초안 생성 기능만 막히고, '
                        '수업 기록·예약 등 나머지 기능은 그대로 쓸 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 생년월일 입력 — TextField가 아니라 탭하면 DatePicker가 뜨는 InputDecorator.
/// 값이 있으면 X 버튼으로 지울 수 있음.
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.birthDate,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? birthDate;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = birthDate != null;
    final text = hasValue
        ? DateFormat('yyyy-MM-dd').format(birthDate!)
        : '선택 안 함';

    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '생년월일',
          border: const OutlineInputBorder(),
          suffixIcon: hasValue
              ? IconButton(
                  tooltip: '비우기',
                  icon: const Icon(Icons.close),
                  onPressed: enabled ? onClear : null,
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: hasValue
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
