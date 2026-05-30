/// 트레이너 "메시지 방해금지(DND) 시간" 설정 (2.3 — 사생활 경계 보호).
///
/// trainer_profiles 의 dnd_enabled / dnd_start / dnd_end 와 1:1 대응.
///
/// **자정을 넘기는 구간(예: 22:00~08:00) 처리가 핵심:**
///   start <= end (예: 09:00~18:00) 면 [start, end) 안일 때 활성.
///   start >  end (예: 22:00~08:00) 면 자정을 넘는 구간 → start 이후 또는 end 이전이면 활성.
///   분 단위(minute of day, 0~1439)로 환산해 비교하면 시/분 경계가 단순해진다.
///
/// 순수 Dart(테스트 대상). 시각은 분 단위 정수로 보관.
library;

class DndSettings {
  /// 방해금지 기능 on/off.
  final bool enabled;

  /// 시작 시각(자정 기준 분, 0~1439). null 이면 미설정.
  final int? startMinute;

  /// 끝 시각(자정 기준 분). null 이면 미설정.
  final int? endMinute;

  const DndSettings({
    required this.enabled,
    this.startMinute,
    this.endMinute,
  });

  /// 기능이 켜져 있고 시작/끝이 모두 설정된 "유효한" 상태인가.
  bool get isConfigured =>
      enabled && startMinute != null && endMinute != null;

  /// [now] 시점이 방해금지 구간 안인가.
  ///
  /// 미설정/비활성이면 항상 false. start==end 는 "구간 없음"으로 보고 false.
  bool isActiveAt(DateTime now) {
    if (!isConfigured) return false;
    final s = startMinute!;
    final e = endMinute!;
    if (s == e) return false; // 빈 구간

    final m = now.hour * 60 + now.minute;
    if (s < e) {
      // 같은 날 안의 구간: [s, e)
      return m >= s && m < e;
    }
    // 자정을 넘는 구간: [s, 24:00) ∪ [0, e)
    return m >= s || m < e;
  }

  /// trainer_profiles 행(일부 컬럼) → DndSettings.
  /// time 컬럼은 'HH:mm:ss'(또는 'HH:mm') 문자열로 온다.
  factory DndSettings.fromRow(Map<String, dynamic> row) {
    return DndSettings(
      enabled: (row['dnd_enabled'] as bool?) ?? false,
      startMinute: _parseMinute(row['dnd_start']),
      endMinute: _parseMinute(row['dnd_end']),
    );
  }

  /// INSERT/UPDATE payload. 시각은 'HH:mm' 문자열로(초는 불필요).
  Map<String, dynamic> toUpdatePayload() => {
        'dnd_enabled': enabled,
        'dnd_start': startMinute == null ? null : _formatMinute(startMinute!),
        'dnd_end': endMinute == null ? null : _formatMinute(endMinute!),
      };

  DndSettings copyWith({bool? enabled, int? startMinute, int? endMinute}) =>
      DndSettings(
        enabled: enabled ?? this.enabled,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  /// 'HH:mm:ss' / 'HH:mm' → 분. 형식 이상/공백/null 은 null.
  static int? _parseMinute(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// 분 → 'HH:mm'.
  static String _formatMinute(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "22:00 ~ 08:00" 표시용. 미설정이면 빈 문자열.
  String get rangeLabel {
    if (startMinute == null || endMinute == null) return '';
    return '${_formatMinute(startMinute!)} ~ ${_formatMinute(endMinute!)}';
  }
}
