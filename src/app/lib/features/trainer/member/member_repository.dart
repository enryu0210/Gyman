/// 회원(member_profiles) CRUD repository.
///
/// **트레이너 시점만 다룬다:**
///   본 repository의 모든 메서드는 *현재 로그인한 트레이너* 시점에서
///   본인 담당 회원만 다룬다. RLS 정책 `member_by_trainer` 가 1차 방어.
///
/// **읽기 정책 (`listForCurrentTrainer`)**
///   - `member_by_trainer` RLS는 "트레이너 + 활성 계약 보유 회원" 만 노출
///   - 베타 단계엔 *계약 없는 회원* 도 표시해야 함 (계약은 1.3에서 등록)
///   - 따라서 본 메서드는 **회원이 본 트레이너의 어떤 데이터와 연결됐는가** 가
///     보장된 상태가 아니다 → 정책 추가 옵션을 1.3에서 검토 (예: created_by_trainer_id)
///   - 임시: 트레이너가 본인이 작성한 member_notes나 pt_contracts가 있는 회원만 뜸.
///     **본 단계엔 이 한계를 받아들이고, "회원 등록 후 곧바로 계약 등록" UX로 우회한다.**
///
/// 참고: docs/data_model.md §3.2 member_by_trainer 정책,
///       src/supabase/migrations/0013_member_profiles_offline_support.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/member.dart';

/// 회원 추가 시 사용하는 입력 객체.
/// 모델보다 가벼움 — id/createdAt 등 서버 생성 필드는 제외.
class NewMemberInput {
  final String name;
  final String? phone;
  final String? goal;
  final String? experience;
  final String? injuryHistory;
  final String? bodyFeatures;
  final String? lifestyle;
  final DateTime? birthDate;
  final String? centerId;

  /// AI 사용 동의. 등록 시점에 트레이너가 "회원에게 동의를 받았다"를 체크하면
  /// true. **기본 false (fail-closed)** — 신규 회원은 동의 없이 시작하고,
  /// 켜야만 이 회원 정보가 외부 LLM 으로 나간다. (수정 화면에서도 변경 가능)
  final bool aiConsent;

  /// 트레이너가 "회원 본인(미성년자면 법정대리인)에게 개인정보 수집·이용 동의를
  /// 받았다"고 확인했는지 (마이그레이션 0041).
  ///
  /// **required 인 이유:** 기본값 false 를 주면 이 값을 안 넘긴 호출부가 조용히
  /// 서버 트리거에 걸려 실패한다. 개인정보 수집의 적법 근거가 걸린 값이라
  /// 모든 등록 경로가 명시적으로 답하게 강제한다.
  ///
  /// 앱에 가입하지 않은 회원은 약관을 볼 수도, `user_consents` 에 행이 생길 수도
  /// 없다(PK 가 `auth.users.id`). 그래서 동의의 존재를 트레이너의 확인으로
  /// 대신 기록한다 — `aiConsent` 와 같은 구조다.
  final bool offlineConsentConfirmed;

  const NewMemberInput({
    required this.name,
    required this.offlineConsentConfirmed,
    this.phone,
    this.goal,
    this.experience,
    this.injuryHistory,
    this.bodyFeatures,
    this.lifestyle,
    this.birthDate,
    this.centerId,
    this.aiConsent = false,
  });
}

/// 회원 정보 수정 시 사용하는 입력 객체.
///
/// **null vs "값 비우기" 구분 정책:**
///   본 입력은 *수정 다이얼로그에서 채운 전체 값*을 그대로 전달한다.
///   - 폼에 빈 문자열이 들어오면 null로 변환해서 보내고,
///   - DB 측은 그 컬럼에 NULL을 넣어 "값 없음"으로 처리한다.
///   필드별 부분 업데이트 (예: "이름만 바꾸기")가 필요해질 때는 별도 메서드로
///   분기하거나 본 객체를 nullable 래퍼로 바꿀 것. 현재는 단순화를 우선.
class UpdateMemberInput {
  final String name;
  final String? phone;
  final String? goal;
  final String? experience;
  final String? injuryHistory;
  final String? bodyFeatures;
  final String? lifestyle;
  final DateTime? birthDate;

  /// AI 사용 동의. **required 인 이유:** 옵셔널(기본 false)로 두면 이 값을 안 넘긴
  /// 호출부가 회원의 기존 동의를 조용히 꺼뜨린다. 동의는 되돌리기 어려운 값이라
  /// 매 수정마다 명시적으로 현재 상태를 실어 보내게 강제한다.
  final bool aiConsent;

  /// 개인정보 수집·이용 동의 확인을 **이번 수정에서 새로 기록할지** (0041).
  ///
  /// 0041 이전에 등록된 회원은 이 값이 비어 있다 — 소급 확인이 불가능해서
  /// NULL 을 허용했기 때문이다. 트레이너가 뒤늦게 확인했을 때 채울 수 있게
  /// 수정 화면에서도 한 번 기록할 수 있게 한다.
  ///
  /// **true 일 때만 기록하고, 지우지는 않는다.** 한 번 남긴 확인 기록을
  /// 되돌리는 경로를 두면 기록의 의미가 없어진다.
  final bool confirmOfflineConsent;

  const UpdateMemberInput({
    required this.name,
    required this.aiConsent,
    this.confirmOfflineConsent = false,
    this.phone,
    this.goal,
    this.experience,
    this.injuryHistory,
    this.bodyFeatures,
    this.lifestyle,
    this.birthDate,
  });
}

class MemberRepository {
  final SupabaseClient _client;

  MemberRepository(this._client);

  static const _table = 'member_profiles';

  /// 행 1개를 [Member] 로 변환.
  ///
  /// Supabase는 timestamptz를 ISO8601 문자열로 반환.
  /// jsonb는 List/Map 으로 반환되지만 형태 변동 가능성 → 방어적 캐스팅.
  static Member _fromRow(Map<String, dynamic> row) {
    final raw = row['available_times'];
    final List<Map<String, dynamic>>? times = (raw is List)
        ? raw.whereType<Map<String, dynamic>>().toList()
        : null;

    return Member(
      id: row['id'] as String,
      userId: row['user_id'] as String?,
      centerId: row['center_id'] as String?,
      name: row['name'] as String,
      phone: row['phone'] as String?,
      birthDate: _parseDate(row['birth_date']),
      goal: row['goal'] as String?,
      experience: row['experience'] as String?,
      injuryHistory: row['injury_history'] as String?,
      bodyFeatures: row['body_features'] as String?,
      lifestyle: row['lifestyle'] as String?,
      availableTimes: times,
      inviteCode: row['invite_code'] as String?,
      // NOT NULL DEFAULT false 지만, 구 캐시/부분 SELECT 로 키가 없을 때는
      // "동의 없음"으로 떨어뜨린다 (동의는 fail-closed 가 안전한 방향).
      aiConsent: row['ai_consent'] as bool? ?? false,
      // 회원 거부 플래그(0040). 키가 없으면 false("거부 안 함")로 두지만,
      // 그 경우 위 aiConsent 도 함께 없어서 false 가 되므로
      // Member.aiConsentEffective 는 결국 false — 쌍으로 fail-closed 다.
      // ⚠ 트레이너 쓰기 경로(_upsert)에는 이 키를 넣지 않는다. DB 트리거가
      //    회원 본인 외의 변경을 거부하므로 넣으면 수정 자체가 실패한다.
      aiConsentMemberOptout: row['ai_consent_member_optout'] as bool? ?? false,
      // 0041. NULL = 확인 기록 없음(0041 이전 등록 회원). 키가 없어도 같은 의미라
      // 별도 분기 없이 null 로 떨어뜨린다.
      offlineConsentConfirmedAt:
          _parseDate(row['offline_consent_confirmed_at']),
      createdAt: DateTime.parse(row['created_at'] as String),
      deletedAt: _parseDate(row['deleted_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  /// 현재 로그인된 트레이너가 볼 수 있는 회원 목록.
  ///
  /// RLS `member_by_trainer` (0014 갱신본) 가 노출하는 회원:
  ///   - 본인이 등록한 회원 (created_by_trainer_id = auth.uid())
  ///   - 본인이 계약을 가진 회원 (인수인계 시나리오 포함)
  ///
  /// soft delete된 회원은 제외. 이름순 정렬.
  Future<List<Member>> listForCurrentTrainer() async {
    final rows = await _client
        .from(_table)
        .select()
        .filter('deleted_at', 'is', null)
        .order('name');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  /// 회원 1명 추가. INSERT 후 RETURNING 결과를 Member로 반환.
  ///
  /// 자동 채워지는 컬럼 (DB default):
  ///   - id: gen_random_uuid()
  ///   - user_id: NULL (앱 미가입 상태로 시작 — [linkAuthUser]로 추후 매핑)
  ///   - created_by_trainer_id: auth.uid() (현재 로그인 트레이너 ID)
  ///     → 본인이 만든 회원은 RLS member_by_trainer로 항상 조회 가능
  Future<Member> addMember(NewMemberInput input) async {
    final row = await _client
        .from(_table)
        .insert({
          'name': input.name,
          'phone': input.phone,
          'goal': input.goal,
          'experience': input.experience,
          'injury_history': input.injuryHistory,
          'body_features': input.bodyFeatures,
          'lifestyle': input.lifestyle,
          'birth_date': input.birthDate?.toIso8601String(),
          'center_id': input.centerId,
          'ai_consent': input.aiConsent,
          // 동의 확인 시각 — **확인했을 때만 보낸다.** 안 보내면 서버 트리거
          // `trg_require_offline_consent`(0041)가 등록을 거부하고 한국어
          // 메시지를 돌려준다. UI 게이트가 뚫려도 여기서 막히는 2중 방어.
          //
          // ⚠ `.toUtc()` 필수 — 이 프로젝트의 "벽시계 그대로" 컨벤션(수업 시각)을
          //   여기 적용하면 안 된다. offset 없는 naive 문자열을 보내면 PG 가 UTC 로
          //   읽어 KST 기준 +9시간 미래가 되고, 트리거의 미래시각 검사에 걸린다.
          if (input.offlineConsentConfirmed)
            'offline_consent_confirmed_at':
                DateTime.now().toUtc().toIso8601String(),
          // user_id / created_by_trainer_id / offline_consent_confirmed_by 는
          // DB default가 채움(마지막 것은 DEFAULT auth.uid())
        })
        .select()
        .single();
    return _fromRow(row);
  }

  /// 회원 1명을 ID로 조회.
  ///
  /// soft delete 된 회원은 제외 (deleted_at IS NULL).
  /// RLS 가 차단해서 안 보이는 경우와 실제로 없는 경우 모두 null 반환 — 호출 측에서
  /// "회원을 찾을 수 없습니다" 안내. PostgrestException은 그대로 위로 던진다.
  Future<Member?> findById(String memberId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('id', memberId)
        .filter('deleted_at', 'is', null)
        .maybeSingle();
    if (row == null) return null;
    return _fromRow(row);
  }

  /// 회원 정보 수정. UPDATE 후 RETURNING 결과를 Member 로 반환.
  ///
  /// user_id / created_by_trainer_id / center_id 등은 본 메서드에서 건드리지 않음.
  /// (매핑은 [linkAuthUser], 인수인계는 별도 마이그레이션 시점에 처리)
  Future<Member> updateMember(
    String memberId,
    UpdateMemberInput input,
  ) async {
    final row = await _client
        .from(_table)
        .update({
          'name': input.name,
          'phone': input.phone,
          'goal': input.goal,
          'experience': input.experience,
          'injury_history': input.injuryHistory,
          'body_features': input.bodyFeatures,
          'lifestyle': input.lifestyle,
          'birth_date': input.birthDate?.toIso8601String(),
          'ai_consent': input.aiConsent,
          // 0041 이전 등록 회원의 소급 확인. 이미 값이 있으면 화면이 이 옵션을
          // 아예 안 보여주므로 덮어쓸 일이 없다. (.toUtc() 이유는 addMember 참조)
          if (input.confirmOfflineConsent)
            'offline_consent_confirmed_at':
                DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', memberId)
        .select()
        .single();
    return _fromRow(row);
  }

  /// 회원에 Supabase Auth 사용자 ID를 매핑.
  ///
  /// 사용 시점: 회원이 앱에 가입한 후, 트레이너가 "이 회원이다" 확정.
  /// 같은 user_id가 이미 다른 회원에게 매핑되어 있으면 UNIQUE 제약 위반.
  Future<Member> linkAuthUser({
    required String memberId,
    required String userId,
  }) async {
    final row = await _client
        .from(_table)
        .update({'user_id': userId})
        .eq('id', memberId)
        .select()
        .single();
    return _fromRow(row);
  }

  /// 회원 soft delete. 즉시 목록에서 사라지지만 DB row는 보존.
  Future<void> softDelete(String memberId) async {
    await _client
        .from(_table)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', memberId);
  }
}
