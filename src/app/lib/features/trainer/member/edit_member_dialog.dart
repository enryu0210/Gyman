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

  /// 0041 이전에 등록돼 동의 확인 기록이 없는 회원을 **이번 수정에서 소급
  /// 확인**할지. 기록이 이미 있으면 이 항목 자체가 화면에 안 나온다.
  bool _confirmOfflineConsent = false;

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
      confirmOfflineConsent: _confirmOfflineConsent,
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
                // 동의 확인 기록이 없는 옛 회원에게만 노출. 이미 확인된 회원에게
                // 다시 물으면 "언제 확인했는가"의 기록만 흐려진다.
                if (widget.member.needsConsentConfirmation) ...[
                  _MissingConsentField(
                    value: _confirmOfflineConsent,
                    enabled: !saving,
                    onChanged: (v) =>
                        setState(() => _confirmOfflineConsent = v ?? false),
                  ),
                  const SizedBox(height: 12),
                ],
                _AiConsentField(
                  value: _aiConsent,
                  // 회원이 앱에서 직접 거부했는지(0040). 거부 상태면 이 스위치를
                  // 켜도 서버가 막으므로, 그 사실을 트레이너에게 보여준다.
                  memberOptedOut: widget.member.aiConsentMemberOptout,
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

/// 동의 확인 기록이 없는 옛 회원의 소급 확인 (마이그레이션 0041).
///
/// 0041 이전에 등록된 회원은 "동의를 받았는지" 자체가 기록돼 있지 않다. 소급
/// 확인은 불가능하므로 DB 는 NULL 을 허용했고, 대신 트레이너가 지금이라도
/// 확인해 채울 수 있게 수정 화면에 노출한다.
///
/// **체크 안 해도 저장은 된다.** 여기서 저장을 막으면 이름 한 글자 고치려던
/// 트레이너가 동의 확인을 강요당하고, 급하면 그냥 체크해 버린다 — 기록의
/// 신뢰도만 떨어진다. 대신 경고색으로 남겨 눈에 걸리게 둔다.
class _MissingConsentField extends StatelessWidget {
  const _MissingConsentField({
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(colors.brightness),
        border: Border.all(
          color: value
              ? AppTheme.menuTileBorder(colors.brightness)
              : colors.error,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('개인정보 수집·이용 동의 확인 기록 없음'),
        subtitle: const Text(
          '이 회원은 동의 확인 기록이 없습니다. 회원 본인(미성년자인 경우 '
          '법정대리인)에게 동의를 받으셨다면 체크해 주세요. 확인한 트레이너와 '
          '시각이 기록됩니다.',
        ),
      ),
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
    required this.memberOptedOut,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;

  /// 회원이 앱에서 직접 거부했는지(0040). true 면 이 스위치를 켜도 전송되지 않는다.
  final bool memberOptedOut;

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

          // 회원이 앱에서 직접 거부한 경우 — 이 스위치를 켜도 서버가 막는다.
          // 알리지 않으면 트레이너는 "켰는데 왜 AI 가 안 되지"로 헤맨다.
          if (memberOptedOut)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block_outlined, size: 18, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '회원이 앱에서 AI 사용을 거부했습니다. 이 스위치를 켜도 '
                      'AI 초안은 생성되지 않습니다. 해제는 회원 본인만 할 수 있습니다.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
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
