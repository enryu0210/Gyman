/// 트레이너 "메시지 방해금지 시간" 설정 다이얼로그 (2.3 — 사생활 경계 보호).
///
/// 토글 + 시작/끝 시각. 저장하면 회원 채팅 화면에 방해금지 안내 배너가 뜬다
/// (전송은 막지 않음). 22:00~08:00 처럼 자정을 넘겨도 됨(도메인이 처리).
///
/// 진입점: `showDndSettingsDialog(context)`, 저장되면 true 반환.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/dnd_settings.dart';
import '../../chat/dnd_providers.dart';

Future<bool?> showDndSettingsDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _DndSettingsDialog(),
  );
}

class _DndSettingsDialog extends ConsumerStatefulWidget {
  const _DndSettingsDialog();

  @override
  ConsumerState<_DndSettingsDialog> createState() => _DndSettingsDialogState();
}

class _DndSettingsDialogState extends ConsumerState<_DndSettingsDialog> {
  bool _enabled = false;
  // 기본값 22:00 ~ 08:00 (가장 흔한 야간 방해금지).
  TimeOfDay _start = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 8, minute: 0);
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    // 현재 설정으로 1회 초기화(저장된 값이 있으면 반영).
    final current = ref.watch(myDndProvider);
    if (!_initialized && current.hasValue) {
      final s = current.value!;
      _enabled = s.enabled;
      if (s.startMinute != null) _start = _toTod(s.startMinute!);
      if (s.endMinute != null) _end = _toTod(s.endMinute!);
      _initialized = true;
    }

    final saving = ref.watch(dndControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('메시지 방해금지 시간'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('방해금지 사용'),
              subtitle: const Text('이 시간대엔 회원에게 "답장이 늦을 수 있음"으로 안내됩니다.'),
              value: _enabled,
              onChanged: saving ? null : (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 8),
            // 시간 선택은 사용 중일 때만 활성.
            IgnorePointer(
              ignoring: !_enabled || saving,
              child: Opacity(
                opacity: _enabled ? 1 : 0.4,
                child: Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: '시작',
                        value: _start,
                        onTap: () => _pick(isStart: true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('~'),
                    ),
                    Expanded(
                      child: _TimeField(
                        label: '끝',
                        value: _end,
                        onTap: () => _pick(isStart: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_enabled)
              Text(
                _crossesMidnight
                    ? '자정을 넘는 시간대예요(밤~다음날 아침).'
                    : '같은 날 안의 시간대예요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
          onPressed: saving ? null : _save,
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

  bool get _crossesMidnight => _toMinute(_start) > _toMinute(_end);

  Future<void> _pick({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      helpText: isStart ? '방해금지 시작' : '방해금지 끝',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    // 사용 중인데 시작==끝이면 "구간 없음"이라 의미 없음 — 막는다.
    if (_enabled && _toMinute(_start) == _toMinute(_end)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('시작과 끝 시각이 같습니다. 다르게 설정해 주세요.')),
        );
      return;
    }

    final settings = DndSettings(
      enabled: _enabled,
      startMinute: _toMinute(_start),
      endMinute: _toMinute(_end),
    );
    await ref.read(dndControllerProvider.notifier).save(settings);

    if (!mounted) return;
    final state = ref.read(dndControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.error?.toString() ?? '저장에 실패했습니다.')),
        );
      return;
    }
    Navigator.of(context).pop(true);
  }

  static int _toMinute(TimeOfDay t) => t.hour * 60 + t.minute;
  static TimeOfDay _toTod(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
}

/// 탭하면 TimePicker 가 뜨는 시각 필드.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.schedule),
        ),
        child: Text('$hh:$mm'),
      ),
    );
  }
}
