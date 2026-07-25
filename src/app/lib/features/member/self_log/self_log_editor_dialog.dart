/// 회원 셀프 운동 기록 작성/수정 다이얼로그 (S4 / Phase 2.5).
///
/// 같은 다이얼로그로 신규 작성과 기존 기록 수정을 겸한다([existing] 유무로 분기).
/// "간단 입력" 원칙대로 필드는 날짜 / 운동 한 줄 / 컨디션 점수(1~10) / 선택 메모.
/// 컨디션은 자유 텍스트 대신 슬라이더 점수로 받아 마찰을 줄였다(높을수록 좋음).
/// 운동·점수·메모가 전부 비면 저장하지 않는다(DB CHECK 와 의미 일치).
///
/// 성공 시 true 반환. async gap 직후 mounted 체크는 프로젝트 다이얼로그 패턴.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/coaching_cue.dart';
import '../../../domain/models/self_workout_log.dart';
import '../../../domain/movement_pattern.dart';
import '../../coaching/coaching_cue_view.dart';
import '../../coaching/coaching_providers.dart';
import '../../self_log/self_log_providers.dart';

/// 다이얼로그 호출 — 저장 성공 시 true. [existing] 이 있으면 수정 모드.
Future<bool?> showSelfLogEditorDialog(
  BuildContext context, {
  SelfWorkoutLog? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SelfLogEditorDialog(existing: existing),
  );
}

class _SelfLogEditorDialog extends ConsumerStatefulWidget {
  const _SelfLogEditorDialog({this.existing});
  final SelfWorkoutLog? existing;

  @override
  ConsumerState<_SelfLogEditorDialog> createState() =>
      _SelfLogEditorDialogState();
}

class _SelfLogEditorDialogState extends ConsumerState<_SelfLogEditorDialog> {
  late DateTime _loggedAt;
  late final TextEditingController _workoutCtrl;
  late final TextEditingController _noteCtrl;
  // 컨디션 점수. 0 = 미입력(슬라이더 최소칸), 1~10 = 실제 점수.
  late int _conditionScore;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // 신규는 오늘, 수정은 기존 날짜.
    _loggedAt = e?.loggedAt ?? DateTime.now();
    _workoutCtrl = TextEditingController(text: e?.workout ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _conditionScore = e?.conditionScore ?? 0;
  }

  @override
  void dispose() {
    _workoutCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      // 과거 기록(빼먹은 날) 입력 허용, 미래는 막음.
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: '운동한 날짜',
    );
    if (picked == null) return;
    setState(() => _loggedAt = picked);
  }

  Future<void> _submit() async {
    final workout = _workoutCtrl.text.trim();
    final note = _noteCtrl.text.trim();
    // 운동·점수·메모가 전부 비면 빈 기록 → 막는다(DB CHECK 와 동일 의미).
    if (workout.isEmpty && note.isEmpty && _conditionScore == 0) {
      _toast('운동·컨디션 점수·메모 중 하나는 입력해 주세요.');
      return;
    }

    final controller = ref.read(selfLogControllerProvider.notifier);
    final log = SelfWorkoutLog(
      // id/memberId/createdAt 은 신규 시 무의미(서버가 채움). 수정 시엔 기존 값 유지.
      id: widget.existing?.id ?? '',
      memberId: widget.existing?.memberId ?? '',
      loggedAt: _loggedAt,
      workout: workout.isEmpty ? null : workout,
      // 0 은 미입력 → null.
      conditionScore: _conditionScore == 0 ? null : _conditionScore,
      note: note.isEmpty ? null : note,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );

    if (_isEdit) {
      await controller.editLog(widget.existing!.id, log);
    } else {
      await controller.add(log);
    }

    if (!mounted) return;
    final state = ref.read(selfLogControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '저장에 실패했습니다.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(selfLogControllerProvider).isLoading;

    return AlertDialog(
      title: Text(_isEdit ? '운동 기록 수정' : '운동 기록 남기기'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: saving ? null : _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '날짜',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(formatKoreanDate(_loggedAt)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _workoutCtrl,
                enabled: !saving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '운동 내용',
                  hintText: '예: 하체 - 스쿼트, 레그프레스',
                ),
              ),
              // 입력한 종목에 해당하는 체형 특이사항 큐(L1-b). 종목을 못 알아보거나
              // 등록된 특이사항이 없으면 아무것도 그리지 않는다.
              _WorkoutCues(controller: _workoutCtrl),
              const SizedBox(height: 16),
              _ConditionSlider(
                score: _conditionScore,
                enabled: !saving,
                onChanged: (v) => setState(() => _conditionScore = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                enabled: !saving,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '메모 (선택)',
                  hintText: '예: 스쿼트 때 왼쪽 무릎이 시큰했는데 무게를 낮추니 괜찮았어요',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '운동·컨디션 점수·메모 중 하나만 입력해도 저장됩니다. '
                '담당 트레이너가 이 기록을 볼 수 있어요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
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
              : Text(_isEdit ? '저장' : '기록'),
        ),
      ],
    );
  }
}

// =====================================================================
// 컨디션 점수 슬라이더 — 0(미입력) ~ 10. 높을수록 좋음.
// =====================================================================

/// 입력 중인 "운동 내용"에 맞는 체형 특이사항 큐 (L1-b).
///
/// **왜 [ValueListenableBuilder] 인가:** 글자마다 다이얼로그 전체를 setState 로
///   다시 그리는 대신 이 블록만 갱신한다. 한글 IME 조합 중에도 상위 위젯과
///   컨트롤러가 재생성되지 않아 입력이 끊기지 않는다(CLAUDE.md IME 주의).
///
/// 특이사항이 없거나 종목을 못 알아보면 **아무것도 그리지 않는다** —
/// 틀린 큐를 띄우느니 안 띄운다(설계 §9).
class _WorkoutCues extends ConsumerWidget {
  const _WorkoutCues({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로딩·에러는 조용히 통과 — 큐는 부가 정보라 기록 작성을 막으면 안 된다.
    final conditions = ref.watch(myConditionsProvider).value ?? const [];
    final rules = ref.watch(coachingRulesProvider).value ?? const [];
    if (conditions.isEmpty || rules.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // 한 칸에 여러 종목이 섞여 들어오므로 스캔-소거 매칭을 쓴다.
        final patterns = MovementPatternMatcher.matchAllInText(value.text);
        final cues = CoachingCueSelector.select(
          conditions: conditions,
          rules: rules,
          patterns: patterns,
        );
        if (cues.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CoachingCueView(cues: cues),
        );
      },
    );
  }
}

class _ConditionSlider extends StatelessWidget {
  const _ConditionSlider({
    required this.score,
    required this.enabled,
    required this.onChanged,
  });

  /// 0 = 미입력, 1~10 = 점수.
  final int score;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 미입력(0)이면 안내, 입력됐으면 "n / 10".
    final valueLabel = score == 0 ? '미입력' : '$score / 10';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '컨디션 (높을수록 좋음)',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            Text(
              valueLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: score == 0 ? colors.onSurfaceVariant : colors.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: score.toDouble(),
          min: 0,
          max: 10,
          // 0~10 = 11칸. 0 은 "미입력"으로 둬서 점수를 안 남길 수도 있게.
          divisions: 10,
          label: valueLabel,
          onChanged: enabled ? (v) => onChanged(v.round()) : null,
        ),
      ],
    );
  }
}
