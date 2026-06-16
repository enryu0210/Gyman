/// 센터 PT 규정 모델 — Phase 3.2 (C2).
///
/// `centers.rules` (jsonb) 와 1:1 대응하는 타입 안전 래퍼.
/// 센터마다 취소/노쇼/지각 정책이 달라 컬럼화하지 않고 JSON 으로 보관한다
/// (`src/supabase/migrations/0002_init_centers.sql` 의 rules 컬럼).
///
/// **왜 도메인에 두나:** 외부(Flutter/Supabase) 의존 없이 JSON 변환을 단위
/// 테스트할 수 있게 — 규정은 노쇼율/차감 해석에 영향을 줄 수 있는 값이라 직렬화가
/// 깨지면 곤란하다. 실제 차감 강제는 트레이너의 수동 상태 선택이 하고, 본 모델은
/// "센터가 고지하는 규정"을 담는다.
library;

class CenterRules {
  /// 며칠/몇 시간 전까지 취소해야 차감되지 않는지(시간 단위). 미설정이면 null.
  final int? lateCancelHours;

  /// 노쇼(무단 불참) 시 횟수를 차감하는가. 기본 true(가장 흔한 정책).
  final bool noShowDeduct;

  /// 몇 분까지 지각을 봐주는지(분 단위). 미설정이면 null.
  final int? lateArrivalMinutes;

  const CenterRules({
    this.lateCancelHours,
    this.noShowDeduct = true,
    this.lateArrivalMinutes,
  });

  /// 아무것도 설정되지 않은 기본 규정(신규 센터 초기값).
  static const empty = CenterRules();

  /// `centers.rules` JSON → 모델.
  ///
  /// 키가 없거나 타입이 어긋나도 터지지 않게 방어적으로 파싱한다(부분 입력 허용).
  factory CenterRules.fromJson(Map<String, dynamic> json) {
    return CenterRules(
      lateCancelHours: _asInt(json['late_cancel_hours']),
      // 키가 없으면 기본 true 유지.
      noShowDeduct: json['no_show_deduct'] is bool
          ? json['no_show_deduct'] as bool
          : true,
      lateArrivalMinutes: _asInt(json['late_arrival_minutes']),
    );
  }

  /// 모델 → `centers.rules` 에 저장할 JSON.
  ///
  /// 미설정(null) 숫자 항목은 키 자체를 빼서 JSON 을 깔끔하게 유지한다.
  Map<String, dynamic> toJson() {
    return {
      if (lateCancelHours != null) 'late_cancel_hours': lateCancelHours,
      'no_show_deduct': noShowDeduct,
      if (lateArrivalMinutes != null) 'late_arrival_minutes': lateArrivalMinutes,
    };
  }

  CenterRules copyWith({
    int? lateCancelHours,
    bool? noShowDeduct,
    int? lateArrivalMinutes,
    bool clearLateCancelHours = false,
    bool clearLateArrivalMinutes = false,
  }) {
    return CenterRules(
      lateCancelHours: clearLateCancelHours
          ? null
          : (lateCancelHours ?? this.lateCancelHours),
      noShowDeduct: noShowDeduct ?? this.noShowDeduct,
      lateArrivalMinutes: clearLateArrivalMinutes
          ? null
          : (lateArrivalMinutes ?? this.lateArrivalMinutes),
    );
  }

  /// num/문자열로 들어와도 int 로 정규화. 변환 불가/null 이면 null.
  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
