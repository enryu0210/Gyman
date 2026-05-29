/// 한국어 날짜/시간 포맷 헬퍼 (수동 구현).
///
/// **왜 intl `DateFormat('...', 'ko')` 를 안 쓰나:**
///   한국어 로케일 포맷은 `initializeDateFormatting('ko')` 선행 호출이 필요한데
///   현재 main.dart 가 이를 초기화하지 않는다(프로젝트 지침). 초기화 전에 호출하면
///   런타임 에러. 단순 표기는 문자열 조립으로 충분하므로 의존을 피한다.
///   한국어 요일/오전·오후가 정식으로 필요해지면 main.dart 초기화 후 intl 로 전환.
library;

const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

/// "2026년 5월 30일 (토) 오후 2:00" 형태.
/// DateTime.weekday: 1=월 ~ 7=일.
String formatKoreanDateTime(DateTime dt) {
  final w = _weekdayKo[dt.weekday - 1];
  final isPm = dt.hour >= 12;
  // 12시간제 변환 (0시 → 12, 12시 → 12)
  var hour12 = dt.hour % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = isPm ? '오후' : '오전';
  return '${dt.year}년 ${dt.month}월 ${dt.day}일 ($w) $ampm $hour12:$minute';
}

/// "2026-05-30" 형태 (간단 표기용).
String formatKoreanDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}

/// 지금 기준 남은 시간을 사람 친화적으로. ("3일 뒤", "2시간 뒤", "곧 시작")
String untilLabel(DateTime target) {
  final now = DateTime.now();
  final diff = target.difference(now);
  if (diff.isNegative) return '곧 시작';

  final days = diff.inDays;
  if (days >= 1) return '$days일 뒤';

  final hours = diff.inHours;
  if (hours >= 1) return '$hours시간 뒤';

  final minutes = diff.inMinutes;
  if (minutes >= 1) return '$minutes분 뒤';
  return '곧 시작';
}
