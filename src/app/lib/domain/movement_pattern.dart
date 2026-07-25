/// 종목명 → 동작 패턴 매핑 (동작 습관·체형 제약 코칭 L1-b).
/// docs/design_movement_coaching.md §3.2
///
/// **왜 "운동별"이 아니라 "패턴별"인가:**
///   종목명은 자유 텍스트다(`session_records.exercises` JSON, 즐겨찾기, 셀프기록).
///   "스쿼트"/"바벨 스쿼트"/"백스쿼트"를 각각 규칙에 매핑하면 규칙이 폭발한다.
///   트레이너도 "오버헤드 동작은 조심"으로 사고하지 "밀리터리프레스만 조심"으로
///   생각하지 않는다. 그래서 8개 패턴으로 묶고, 규칙(0037)은 패턴 단위로만 쓴다.
///
/// **왜 DB 테이블이 아니라 앱 상수인가:**
///   매핑은 순수 문자열 규칙이라 서버 왕복이 필요 없고, 단위 테스트로 고정하는 편이
///   낫다. 트레이너별 보정이 실제로 필요해지면 그때 DB 로 승격한다(YAGNI).
///
/// **매칭 실패는 정상이다.** 모르는 종목은 [MovementPattern] 을 못 찾고 큐도 안 뜬다.
///   설계 원칙: **틀린 큐를 띄우느니 아무것도 안 띄운다**(§9 리스크 표).
library;

/// 동작 패턴 8종. `code` 는 DB `condition_coaching_rules.movement_pattern` 의
/// CHECK 목록(0037)과 **정확히 1:1로 일치해야 한다.**
enum MovementPattern {
  squat('squat', '스쿼트 계열'),
  hinge('hinge', '힌지 계열'),
  lunge('lunge', '런지 계열'),
  pushHorizontal('push_horizontal', '수평 밀기'),
  pushVertical('push_vertical', '수직 밀기'),
  pullHorizontal('pull_horizontal', '수평 당기기'),
  pullVertical('pull_vertical', '수직 당기기'),
  coreCarry('core_carry', '코어·운반');

  const MovementPattern(this.code, this.label);

  /// DB 에 저장되는 값.
  final String code;

  /// UI 표시명.
  final String label;

  /// DB 문자열 → enum. 모르는 값은 null(그 규칙은 무시된다).
  static MovementPattern? fromCode(String? raw) {
    if (raw == null) return null;
    for (final p in MovementPattern.values) {
      if (p.code == raw) return p;
    }
    return null;
  }
}

/// 종목명에서 동작 패턴을 찾아낸다.
class MovementPatternMatcher {
  const MovementPatternMatcher._();

  /// 키워드 → 패턴 사전.
  ///
  /// **정규화된 형태로 적을 것** — 공백·하이픈 없이 소문자([_normalize] 참조).
  /// 애매한 종목(레그컬, 딥스, 레터럴레이즈 등)은 **일부러 넣지 않았다.**
  /// 큐가 어긋나느니 안 뜨는 편이 낫기 때문(§9).
  static const _keywords = <String, MovementPattern>{
    // ── 런지 계열 (스쿼트보다 먼저 잡혀야 함 — 아래 정렬 규칙 참조) ──
    '스플릿스쿼트': MovementPattern.lunge,
    'splitsquat': MovementPattern.lunge,
    '불가리안': MovementPattern.lunge,
    'bulgarian': MovementPattern.lunge,
    '런지': MovementPattern.lunge,
    'lunge': MovementPattern.lunge,
    '스텝업': MovementPattern.lunge,
    'stepup': MovementPattern.lunge,

    // ── 스쿼트 계열 (무릎 지배) ──
    '스쿼트': MovementPattern.squat,
    '스쾃': MovementPattern.squat,
    'squat': MovementPattern.squat,
    '레그프레스': MovementPattern.squat,
    'legpress': MovementPattern.squat,

    // ── 힌지 계열 (고관절 지배) ──
    '데드리프트': MovementPattern.hinge,
    'deadlift': MovementPattern.hinge,
    '루마니안': MovementPattern.hinge,
    'romanian': MovementPattern.hinge,
    'rdl': MovementPattern.hinge,
    '굿모닝': MovementPattern.hinge,
    'goodmorning': MovementPattern.hinge,
    '힙쓰러스트': MovementPattern.hinge,
    '힙스러스트': MovementPattern.hinge,
    'hipthrust': MovementPattern.hinge,
    '케틀벨스윙': MovementPattern.hinge,

    // ── 수평 밀기 ──
    '벤치프레스': MovementPattern.pushHorizontal,
    'benchpress': MovementPattern.pushHorizontal,
    '체스트프레스': MovementPattern.pushHorizontal,
    'chestpress': MovementPattern.pushHorizontal,
    '푸시업': MovementPattern.pushHorizontal,
    '푸쉬업': MovementPattern.pushHorizontal,
    'pushup': MovementPattern.pushHorizontal,
    '팔굽혀펴기': MovementPattern.pushHorizontal,
    '플라이': MovementPattern.pushHorizontal,

    // ── 수직 밀기 ──
    '오버헤드프레스': MovementPattern.pushVertical,
    'overheadpress': MovementPattern.pushVertical,
    'ohp': MovementPattern.pushVertical,
    '밀리터리프레스': MovementPattern.pushVertical,
    'militarypress': MovementPattern.pushVertical,
    '숄더프레스': MovementPattern.pushVertical,
    'shoulderpress': MovementPattern.pushVertical,

    // ── 수평 당기기 ──
    '시티드로우': MovementPattern.pullHorizontal,
    'seatedrow': MovementPattern.pullHorizontal,
    '바벨로우': MovementPattern.pullHorizontal,
    'barbellrow': MovementPattern.pullHorizontal,
    '덤벨로우': MovementPattern.pullHorizontal,
    '케이블로우': MovementPattern.pullHorizontal,
    '페이스풀': MovementPattern.pullHorizontal,
    'facepull': MovementPattern.pullHorizontal,
    '로우': MovementPattern.pullHorizontal,

    // ── 수직 당기기 ──
    '랫풀다운': MovementPattern.pullVertical,
    'latpulldown': MovementPattern.pullVertical,
    '풀다운': MovementPattern.pullVertical,
    '풀업': MovementPattern.pullVertical,
    'pullup': MovementPattern.pullVertical,
    '턱걸이': MovementPattern.pullVertical,
    '친업': MovementPattern.pullVertical,
    'chinup': MovementPattern.pullVertical,

    // ── 코어·운반 ──
    '플랭크': MovementPattern.coreCarry,
    'plank': MovementPattern.coreCarry,
    '파머스': MovementPattern.coreCarry,
    'farmer': MovementPattern.coreCarry,
    '데드버그': MovementPattern.coreCarry,
    'deadbug': MovementPattern.coreCarry,
    '버드독': MovementPattern.coreCarry,
    'birddog': MovementPattern.coreCarry,
  };

  /// **긴 키워드 우선** 정렬 목록 (매칭 시 1회 계산 대신 상수처럼 재사용).
  ///
  /// 이 정렬이 핵심이다: "불가리안 스플릿 스쿼트"는 `스플릿스쿼트`(런지)와
  /// `스쿼트`(스쿼트) 둘 다에 걸린다. 더 구체적인(=긴) 키워드가 이겨야
  /// 런지로 잡힌다. 같은 이유로 "로우바 스쿼트"는 `스쿼트`(3자)가 `로우`(2자)를
  /// 이겨 스쿼트가 된다.
  static final List<MapEntry<String, MovementPattern>> _bySpecificity = () {
    final entries = _keywords.entries.toList();
    entries.sort((a, b) => b.key.length.compareTo(a.key.length));
    return List<MapEntry<String, MovementPattern>>.unmodifiable(entries);
  }();

  /// 종목명 1개 → 패턴. 못 찾으면 null.
  static MovementPattern? match(String? exerciseName) {
    final name = _normalize(exerciseName);
    if (name.isEmpty) return null;
    for (final entry in _bySpecificity) {
      if (name.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// 여러 종목명 → 등장한 패턴 집합(중복 제거). 수업 기록처럼 종목 칸이 여러 개일 때.
  static Set<MovementPattern> matchAll(Iterable<String?> exerciseNames) {
    final result = <MovementPattern>{};
    for (final name in exerciseNames) {
      final p = match(name);
      if (p != null) result.add(p);
    }
    return result;
  }

  /// 자유 텍스트 **한 줄**에 여러 종목이 섞여 있을 때 등장하는 패턴 전부.
  /// (회원 셀프기록의 "운동 내용" 한 칸 — 예: `"하체 - 스쿼트, 레그프레스"`)
  ///
  /// **스캔-소거 방식:** 가장 긴 키워드를 찾아 패턴을 기록하고 **그 부분을 지운 뒤**
  /// 남은 문자열에서 다시 찾는다. 단순히 "포함된 키워드 전부"로 하면
  /// `불가리안스플릿스쿼트` 가 런지와 스쿼트 양쪽에 걸려 엉뚱한 큐가 붙는데,
  /// 소거하면 긴 키워드가 짧은 것을 덮어 그 문제가 사라진다.
  ///   - `"불가리안 스플릿 스쿼트"` → `스플릿스쿼트` 소거 → `불가리안` → **런지만**
  ///   - `"스쿼트 벤치프레스"` → `벤치프레스` 소거 → `스쿼트` → **수평밀기 + 스쿼트**
  static Set<MovementPattern> matchAllInText(String? text) {
    var remaining = _normalize(text);
    if (remaining.isEmpty) return const {};

    final result = <MovementPattern>{};
    // 각 반복마다 최소 1글자는 지워지므로 종료가 보장된다.
    while (remaining.isNotEmpty) {
      var matched = false;
      for (final entry in _bySpecificity) {
        final at = remaining.indexOf(entry.key);
        if (at < 0) continue;
        result.add(entry.value);
        remaining = remaining.replaceRange(at, at + entry.key.length, '');
        matched = true;
        break;
      }
      if (!matched) break; // 남은 문자열에 아는 종목이 없음 → 종료
    }
    return result;
  }

  /// 비교용 정규화 — 공백·하이픈·가운뎃점 제거 + 소문자.
  ///
  /// "Bench Press" → "benchpress", "바벨 로우" → "바벨로우" 처럼 표기 흔들림을 흡수한다.
  static String _normalize(String? raw) {
    if (raw == null) return '';
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_·・,./]'), '');
  }
}
