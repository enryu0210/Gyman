/// PT 시작 전 알림 — 리드타임 정의 + 발화 시각 계산(순수 도메인).
///
/// 운톡 P1 후속(회원 요청): "PT 시작 전에 알람". FCM 없이 기기 로컬 예약 알림으로
/// 구현하며, 여기서는 **언제 알릴지**만 순수 계산한다(플랫폼 의존 0 → 단위 테스트).
///
/// **벽시계 일관:** 이 앱은 수업 시각을 "벽시계 그대로" 다룬다(타임존 변환 안 함 —
///   member_attendance 시각 버그 수정에서 확정한 컨벤션). scheduled_at 은 파싱하면
///   isUtc 라도 `.hour`/`.day` 가 곧 적재된 벽시계값이라, 그 필드를 그대로 쓴다.
library;

/// PT 알림 리드타임 — "수업 몇 분/시간 전에 알릴까".
enum PtReminderLead {
  off(null, '끄기'),
  min30(Duration(minutes: 30), '30분 전'),
  hour1(Duration(hours: 1), '1시간 전'),
  hour2(Duration(hours: 2), '2시간 전'),
  dayBefore(Duration(days: 1), '하루 전');

  const PtReminderLead(this.lead, this.label);

  /// 수업 시작 기준 앞당길 시간. off 면 null.
  final Duration? lead;

  /// 설정 UI 표시 라벨.
  final String label;

  /// 켜짐 여부(off 가 아님).
  bool get isOn => lead != null;

  /// 저장값(이름) → enum. 알 수 없으면 기본 1시간 전.
  static PtReminderLead fromName(String? name) => PtReminderLead.values
      .firstWhere((e) => e.name == name, orElse: () => PtReminderLead.hour1);
}

/// 스케줄할 PT 알림 한 건.
class PtReminder {
  /// 수업 시작 시각(벽시계).
  final DateTime sessionStart;

  /// 알림 발화 시각(벽시계) = 수업시작 − 리드타임.
  final DateTime fireAt;

  const PtReminder({required this.sessionStart, required this.fireAt});

  @override
  bool operator ==(Object other) =>
      other is PtReminder &&
      other.sessionStart == sessionStart &&
      other.fireAt == fireAt;

  @override
  int get hashCode => Object.hash(sessionStart, fireAt);

  @override
  String toString() => 'PtReminder(start: $sessionStart, fire: $fireAt)';
}

/// 다가올 수업 시작 시각들 → 스케줄할 알림 목록.
///
/// - [lead] 가 off(null)면 빈 목록(알림 끔).
/// - 발화 시각 = 수업시작 − 리드타임. 이미 지난 발화([now] 이후가 아님)는 제외
///   (예: 1시간 전 알림인데 수업이 30분 뒤면 발화 시각이 과거 → 스킵).
/// - 입력 시각은 **벽시계 필드만** 사용(타임존 변환 없음, 앱 컨벤션).
/// - 발화 시각 오름차순 정렬 후 가까운 [max] 건만(iOS pending 64개 제한 등 대비).
List<PtReminder> computePtReminders({
  required List<DateTime> sessionStarts,
  required PtReminderLead lead,
  required DateTime now,
  int max = 32,
}) {
  final d = lead.lead;
  if (d == null) return const [];

  final out = <PtReminder>[];
  for (final s in sessionStarts) {
    // 벽시계 필드만 떼어 naive local 로 재구성(타임존 변환 방지).
    final wall = DateTime(s.year, s.month, s.day, s.hour, s.minute);
    final fire = wall.subtract(d);
    if (fire.isAfter(now)) {
      out.add(PtReminder(sessionStart: wall, fireAt: fire));
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > max ? out.sublist(0, max) : out;
}
