/// 수업 기록 입력/수정 화면 (Phase 1.4, M2).
///
/// **라우트:**
///   - `/trainer/members/:id/session/new`        → 신규 (memberId만 알면 됨)
///   - `/trainer/members/:id/session/:sid`       → 수정 (sid = sessions.id)
///
/// **1분 입력 UX 목표 (develop_plan.md §1.4 Critical):**
///   - 일시 기본값 = 현재 시각
///   - 활성 계약이 1개면 자동 선택 (드롭다운 안 띄움)
///   - 종목/세트는 인라인 입력 (모달 없음)
///   - 컨디션은 chip 1탭
///   - 저장 1탭으로 끝
///
/// **수정 모드 제약:**
///   - 계약 (contract) 은 변경 불가 — 잔여 횟수 정합성 보호
///   - 상태 (status) 도 본 화면에선 변경 안 함 (노쇼/취소는 1.6 캘린더에서)
///
/// **검증 정책:**
///   - 종목명만 비어 있는 행은 저장 시 자동 제거 (실수 방지)
///   - 종목 0개 + 컨디션/통증/메모 모두 비면 저장 막음 (빈 기록 차단)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/pt_contract.dart';
import '../../../domain/models/session_record.dart';
import '../contract/contract_providers.dart';
import 'favorite_exercise_providers.dart';
import 'manage_favorites_dialog.dart';
import 'session_providers.dart';
import 'session_repository.dart';

class SessionLogScreen extends ConsumerStatefulWidget {
  const SessionLogScreen({
    super.key,
    required this.memberId,
    this.sessionId,
  });

  /// 회원 ID — 어떤 회원의 수업인지. 경로에서 받음.
  final String memberId;

  /// 수정 모드면 sessions.id, 신규면 null.
  final String? sessionId;

  bool get isEditMode => sessionId != null;

  @override
  ConsumerState<SessionLogScreen> createState() => _SessionLogScreenState();
}

class _SessionLogScreenState extends ConsumerState<SessionLogScreen> {
  /// 선택된 계약 ID — 신규 모드에서만 사용자가 바꿀 수 있음.
  String? _contractId;
  DateTime _scheduledAt = DateTime.now();
  final List<_ExerciseDraft> _exercises = [];
  String? _condition; // 'good' / 'normal' / 'bad' / null
  final _painCtrl = TextEditingController();
  final _nextMemoCtrl = TextEditingController();

  /// 수정 모드의 초기 데이터를 한 번만 채우기 위한 가드.
  /// AsyncValue.when 의 data 콜백은 rebuild 때마다 불려서 그대로 setState 하면 무한 루프.
  bool _initialized = false;

  @override
  void dispose() {
    for (final e in _exercises) {
      e.dispose();
    }
    _painCtrl.dispose();
    _nextMemoCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // 초기화 — 신규/수정 분기
  // ---------------------------------------------------------------------

  /// 신규 모드 초기화: 활성 계약이 1개면 자동 선택, 종목 1개 빈 카드 추가.
  void _initNewMode(List<PtContract> contracts) {
    if (_initialized) return;
    _initialized = true;
    if (contracts.length == 1) {
      _contractId = contracts.first.id;
    }
    _exercises.add(_ExerciseDraft.empty());
  }

  /// 수정 모드 초기화: 기존 session/record 값을 폼에 채움.
  void _initEditMode(SessionWithRecord sw) {
    if (_initialized) return;
    _initialized = true;
    _contractId = sw.session.contractId;
    _scheduledAt = sw.session.scheduledAt;
    _condition = sw.record?.condition;
    _painCtrl.text = sw.record?.pain ?? '';
    _nextMemoCtrl.text = sw.record?.nextMemo ?? '';
    if (sw.record != null && sw.record!.exercises.isNotEmpty) {
      for (final e in sw.record!.exercises) {
        _exercises.add(_ExerciseDraft.fromExercise(e));
      }
    } else {
      _exercises.add(_ExerciseDraft.empty());
    }
  }

  // ---------------------------------------------------------------------
  // 폼 조작
  // ---------------------------------------------------------------------

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: '수업 일자',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
      helpText: '수업 시각',
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _addExercise() {
    setState(() => _exercises.add(_ExerciseDraft.empty()));
  }

  /// 즐겨찾기 칩 1개 탭 → 해당 이름으로 새 종목 카드 추가.
  ///
  /// 마지막 카드의 종목명이 비어 있으면 그 카드를 재사용 — 빈 카드 + 즐겨찾기 한 번
  /// 누른 직후 "빈 카드 + 채워진 카드" 두 개 나란히 뜨는 어색함 방지.
  void _addExerciseFromFavorite(String name) {
    setState(() {
      if (_exercises.isNotEmpty &&
          _exercises.last.nameCtrl.text.trim().isEmpty &&
          // 세트도 모두 비어 있을 때만 재사용 — 사용자가 세트만 먼저 채워둔 경우 보존
          _exercises.last.sets.every((s) =>
              s.weightCtrl.text.trim().isEmpty &&
              s.repsCtrl.text.trim().isEmpty)) {
        _exercises.last.nameCtrl.text = name;
      } else {
        _exercises.add(_ExerciseDraft.fromName(name));
      }
    });
  }

  /// "직전 수업 종목 복사" — 회원의 가장 최근 done 수업의 exercises 를 현재 폼에 복사.
  ///
  /// 정책:
  ///   - 컨디션/통증/메모는 *복사하지 않음* (시점 의존 정보라 오해 소지)
  ///   - 세트 무게/반복은 복사 (다음 수업 출발점으로 활용)
  ///   - 현재 폼에 입력된 내용이 있으면 덮어쓰기 전 확인
  ///   - 직전 수업이 없으면 안내
  Future<void> _copyFromLastSession() async {
    final list = await ref
        .read(recentSessionsForMemberProvider(widget.memberId).future);

    // 종목이 1개 이상 있는 done 수업 중 가장 최근.
    SessionWithRecord? source;
    for (final sw in list) {
      if (sw.record == null) continue;
      if (sw.record!.exercises.isEmpty) continue;
      source = sw;
      break;
    }
    if (!mounted) return;

    if (source == null) {
      _toast('복사할 직전 수업 기록이 없습니다.');
      return;
    }

    // 현재 폼에 의미 있는 입력이 있으면 확인.
    final hasUserInput = _exercises.any(
      (d) =>
          d.nameCtrl.text.trim().isNotEmpty ||
          d.sets.any((s) =>
              s.weightCtrl.text.trim().isNotEmpty ||
              s.repsCtrl.text.trim().isNotEmpty),
    );
    if (hasUserInput) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('현재 입력 내용 덮어쓰기'),
          content: const Text(
            '직전 수업 종목으로 현재 입력된 내용을 덮어씁니다.\n계속할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('덮어쓰기'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      // 기존 controller 모두 dispose 후 source 의 exercises 로 재구성.
      for (final e in _exercises) {
        e.dispose();
      }
      _exercises
        ..clear()
        ..addAll(
          source!.record!.exercises.map(_ExerciseDraft.fromExercise),
        );
    });
    _toast('직전 수업 종목 ${source.record!.exercises.length}개를 복사했습니다.');
  }

  void _removeExercise(int index) {
    setState(() {
      _exercises.removeAt(index).dispose();
      // 마지막 1개도 지워졌으면 자동으로 빈 카드 1개 복원 — UX 친화.
      if (_exercises.isEmpty) {
        _exercises.add(_ExerciseDraft.empty());
      }
    });
  }

  // ---------------------------------------------------------------------
  // 저장
  // ---------------------------------------------------------------------

  /// 폼 → 입력 객체 변환. 종목명 빈 행은 자동 제거.
  /// 종목+컨디션+통증+메모가 모두 비면 null 반환 — 저장 차단.
  List<Exercise>? _collectExercises() {
    final list = <Exercise>[];
    for (final d in _exercises) {
      final ex = d.toExercise();
      if (ex == null) continue;
      list.add(ex);
    }
    return list;
  }

  Future<void> _save() async {
    if (_contractId == null) {
      _toast('계약을 선택해 주세요.');
      return;
    }
    final exercises = _collectExercises() ?? const <Exercise>[];
    final pain = _painCtrl.text.trim();
    final nextMemo = _nextMemoCtrl.text.trim();

    // 완전 빈 기록 차단 — 실수 방지
    if (exercises.isEmpty &&
        (_condition == null || _condition!.isEmpty) &&
        pain.isEmpty &&
        nextMemo.isEmpty) {
      _toast('운동 종목, 컨디션, 메모 중 최소 하나는 입력해 주세요.');
      return;
    }

    final controller = ref.read(saveSessionControllerProvider.notifier);

    if (widget.isEditMode) {
      await controller.editRecord(
        sessionId: widget.sessionId!,
        memberId: widget.memberId,
        input: UpdateSessionRecordInput(
          scheduledAt: _scheduledAt,
          exercises: exercises,
          condition: _condition,
          pain: pain.isEmpty ? null : pain,
          nextMemo: nextMemo.isEmpty ? null : nextMemo,
        ),
      );
    } else {
      await controller.createDone(
        memberId: widget.memberId,
        input: NewSessionRecordInput(
          contractId: _contractId!,
          scheduledAt: _scheduledAt,
          exercises: exercises,
          condition: _condition,
          pain: pain.isEmpty ? null : pain,
          nextMemo: nextMemo.isEmpty ? null : nextMemo,
        ),
      );
    }

    if (!mounted) return;
    final state = ref.read(saveSessionControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '저장에 실패했습니다.');
      return;
    }
    _toast(widget.isEditMode ? '수업 기록이 수정되었습니다.' : '수업 기록이 저장되었습니다.');
    if (mounted) context.pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('수업 기록 삭제'),
        content: const Text(
          '이 수업 기록을 삭제하시겠습니까?\n'
          '해당 회차가 잔여 횟수로 복구됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(saveSessionControllerProvider.notifier).delete(
          sessionId: widget.sessionId!,
          memberId: widget.memberId,
        );
    if (!mounted) return;
    final state = ref.read(saveSessionControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '삭제에 실패했습니다.');
      return;
    }
    _toast('수업 기록이 삭제되었습니다.');
    if (mounted) context.pop();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 신규: 회원의 활성 계약 watch (자동 선택용)
    // 수정: 기존 session detail watch (초기값 채움용)
    if (widget.isEditMode) {
      final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId!));
      return detailAsync.when(
        loading: () => _scaffoldLoading('수업 기록 수정'),
        error: (e, _) => _scaffoldError('수업 기록 수정', e),
        data: (sw) {
          if (sw == null) {
            return _scaffoldNotFound('수업을 찾을 수 없습니다');
          }
          _initEditMode(sw);
          return _buildForm(context, contracts: null);
        },
      );
    }

    final contractsAsync = ref.watch(contractsForMemberProvider(widget.memberId));
    return contractsAsync.when(
      loading: () => _scaffoldLoading('수업 기록'),
      error: (e, _) => _scaffoldError('수업 기록', e),
      data: (contracts) {
        if (contracts.isEmpty) {
          return _scaffoldNoContract();
        }
        _initNewMode(contracts);
        return _buildForm(context, contracts: contracts);
      },
    );
  }

  // ---------------------------------------------------------------------
  // 스캐폴드 보조 화면들
  // ---------------------------------------------------------------------

  Widget _scaffoldLoading(String title) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _scaffoldError(String title, Object e) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text('정보를 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scaffoldNotFound(String message) {
    return Scaffold(
      appBar: AppBar(title: const Text('수업 기록')),
      body: Center(child: Text(message)),
    );
  }

  Widget _scaffoldNoContract() {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('수업 기록')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 64, color: colors.outline),
              const SizedBox(height: 16),
              Text(
                '활성 계약이 없습니다',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '회원 상세에서 [계약 추가] 후 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 본 폼
  // ---------------------------------------------------------------------

  Widget _buildForm(
    BuildContext context, {
    required List<PtContract>? contracts,
  }) {
    final saving = ref.watch(saveSessionControllerProvider).isLoading;
    // 한국어 요일 표기는 intl 의 locale data 초기화가 필요해서 일단 ASCII 포맷만.
    // (한국어 요일 필요해지면 main.dart 에서 initializeDateFormatting('ko') 호출)
    final dtFmt = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? '수업 기록 수정' : '수업 기록'),
        actions: [
          if (widget.isEditMode)
            IconButton(
              tooltip: '삭제',
              onPressed: saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // ----- 계약 선택 -----
          _SectionHeader(icon: Icons.assignment_outlined, title: '계약'),
          const SizedBox(height: 8),
          _ContractPicker(
            contracts: contracts,
            isEditMode: widget.isEditMode,
            currentContractId: _contractId,
            enabled: !saving,
            onChanged: (v) => setState(() => _contractId = v),
          ),
          const SizedBox(height: 20),

          // ----- 일시 -----
          _SectionHeader(icon: Icons.schedule, title: '수업 일시'),
          const SizedBox(height: 8),
          InkWell(
            onTap: saving ? null : _pickDateTime,
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(dtFmt.format(_scheduledAt)),
            ),
          ),
          const SizedBox(height: 20),

          // ----- 운동 종목 -----
          Row(
            children: [
              Expanded(
                child: _SectionHeader(
                  icon: Icons.fitness_center,
                  title: '운동 종목',
                ),
              ),
              // 직전 수업 복사는 신규 모드 전용 — 수정 모드에선 이미 본인 데이터 표시 중.
              if (!widget.isEditMode)
                TextButton.icon(
                  onPressed: saving ? null : _copyFromLastSession,
                  icon: const Icon(Icons.content_copy, size: 16),
                  label: const Text('직전 수업 복사'),
                ),
              TextButton.icon(
                onPressed: saving ? null : _addExercise,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('종목 추가'),
              ),
            ],
          ),
          // 즐겨찾기 칩 row — 1탭으로 종목 추가. 빈 즐겨찾기면 안내 + 관리 진입 칩.
          const SizedBox(height: 4),
          _FavoritesRow(
            enabled: !saving,
            onPick: _addExerciseFromFavorite,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExerciseCard(
                key: ValueKey(_exercises[i].key),
                draft: _exercises[i],
                enabled: !saving,
                onRemove: () => _removeExercise(i),
                onChanged: () => setState(() {}),
              ),
            ),
          const SizedBox(height: 8),

          // ----- 컨디션 -----
          _SectionHeader(icon: Icons.mood, title: '컨디션'),
          const SizedBox(height: 8),
          _ConditionPicker(
            value: _condition,
            enabled: !saving,
            onChanged: (v) => setState(() => _condition = v),
          ),
          const SizedBox(height: 20),

          // ----- 통증/특이사항 -----
          _SectionHeader(icon: Icons.healing_outlined, title: '통증/특이사항'),
          const SizedBox(height: 8),
          TextField(
            controller: _painCtrl,
            enabled: !saving,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '예: 우측 어깨 통증, 무릎 불편 (선택)',
            ),
          ),
          const SizedBox(height: 20),

          // ----- 다음 메모 -----
          _SectionHeader(icon: Icons.bookmark_border, title: '다음 수업 메모'),
          const SizedBox(height: 8),
          TextField(
            controller: _nextMemoCtrl,
            enabled: !saving,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '예: 스쿼트 5kg 증량 시도 (선택)',
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(widget.isEditMode ? '수정 저장' : '수업 기록 저장'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 종목 1개 폼 상태 — TextEditingController 보관 + dispose 위해 객체화
// =====================================================================

class _ExerciseDraft {
  /// Widget key 안정성을 위한 고유 식별자. setState 후에도 카드가 같은 entity 로 인식됨.
  final int key;
  final TextEditingController nameCtrl;
  final List<_SetDraft> sets;

  _ExerciseDraft._({
    required this.key,
    required this.nameCtrl,
    required this.sets,
  });

  factory _ExerciseDraft.empty() {
    final k = _nextKey();
    return _ExerciseDraft._(
      key: k,
      nameCtrl: TextEditingController(),
      sets: [_SetDraft.empty()],
    );
  }

  /// 이름만 미리 채운 빈 세트 1개짜리 카드 — 즐겨찾기 칩 탭 진입점.
  factory _ExerciseDraft.fromName(String name) {
    return _ExerciseDraft._(
      key: _nextKey(),
      nameCtrl: TextEditingController(text: name),
      sets: [_SetDraft.empty()],
    );
  }

  factory _ExerciseDraft.fromExercise(Exercise e) {
    return _ExerciseDraft._(
      key: _nextKey(),
      nameCtrl: TextEditingController(text: e.name),
      sets: e.sets.isEmpty
          ? [_SetDraft.empty()]
          : e.sets.map((s) => _SetDraft.fromSet(s)).toList(),
    );
  }

  static int _keyCounter = 0;
  static int _nextKey() => ++_keyCounter;

  /// 입력 검증 후 Exercise 반환. 이름이 비어 있으면 null (저장 시 자동 제거).
  Exercise? toExercise() {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return null;
    final builtSets = <ExerciseSet>[];
    for (final s in sets) {
      final set = s.toSet();
      if (set != null) builtSets.add(set);
    }
    return Exercise(name: name, sets: builtSets);
  }

  void dispose() {
    nameCtrl.dispose();
    for (final s in sets) {
      s.dispose();
    }
  }
}

class _SetDraft {
  final int key;
  final TextEditingController weightCtrl;
  final TextEditingController repsCtrl;

  _SetDraft._({
    required this.key,
    required this.weightCtrl,
    required this.repsCtrl,
  });

  factory _SetDraft.empty() => _SetDraft._(
        key: _nextKey(),
        weightCtrl: TextEditingController(),
        repsCtrl: TextEditingController(),
      );

  factory _SetDraft.fromSet(ExerciseSet s) => _SetDraft._(
        key: _nextKey(),
        weightCtrl: TextEditingController(text: s.weight.toString()),
        repsCtrl: TextEditingController(text: s.reps.toString()),
      );

  static int _keyCounter = 0;
  static int _nextKey() => ++_keyCounter;

  /// 둘 다 비어 있으면 null (저장 시 자동 제거). 한 쪽만 비면 0 으로 채운다.
  ExerciseSet? toSet() {
    final w = weightCtrl.text.trim();
    final r = repsCtrl.text.trim();
    if (w.isEmpty && r.isEmpty) return null;
    return ExerciseSet(
      weight: int.tryParse(w) ?? 0,
      reps: int.tryParse(r) ?? 0,
    );
  }

  void dispose() {
    weightCtrl.dispose();
    repsCtrl.dispose();
  }
}

// =====================================================================
// 위젯 조각들
// =====================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _ContractPicker extends StatelessWidget {
  const _ContractPicker({
    required this.contracts,
    required this.isEditMode,
    required this.currentContractId,
    required this.enabled,
    required this.onChanged,
  });

  /// 신규 모드에서만 사용됨. 수정 모드면 null.
  final List<PtContract>? contracts;
  final bool isEditMode;
  final String? currentContractId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (isEditMode) {
      // 잠금: 안내만
      return InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.lock_outline),
        ),
        child: Text(
          '계약은 수정할 수 없습니다 (잔여 횟수 정합성)',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }

    final items = contracts ?? const <PtContract>[];
    return DropdownButtonFormField<String>(
      initialValue: currentContractId,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: '차감할 계약 *',
      ),
      onChanged: enabled ? onChanged : null,
      items: [
        for (final c in items)
          DropdownMenuItem(
            value: c.id,
            child: Text(_contractLabel(c)),
          ),
      ],
    );
  }

  static String _contractLabel(PtContract c) {
    final start = DateFormat('yyyy-MM-dd').format(c.startDate);
    return '${c.totalSessions}회 PT · 시작 $start';
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    super.key,
    required this.draft,
    required this.enabled,
    required this.onRemove,
    required this.onChanged,
  });

  final _ExerciseDraft draft;
  final bool enabled;
  final VoidCallback onRemove;

  /// 세트 추가/삭제 시 부모 setState 트리거용. 텍스트 변경은 controller 가 알아서.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.nameCtrl,
                    enabled: enabled,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: '종목명 (예: 스쿼트)',
                      border: InputBorder.none,
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '종목 삭제',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (var i = 0; i < draft.sets.length; i++)
              Padding(
                key: ValueKey(draft.sets[i].key),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _SetRow(
                  index: i + 1,
                  set: draft.sets[i],
                  enabled: enabled,
                  onRemove: draft.sets.length > 1
                      ? () {
                          draft.sets.removeAt(i).dispose();
                          onChanged();
                        }
                      : null,
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled
                    ? () {
                        draft.sets.add(_SetDraft.empty());
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('세트 추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.enabled,
    this.onRemove,
  });

  final int index;
  final _SetDraft set;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$index.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: TextField(
            controller: set.weightCtrl,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              labelText: '무게',
              suffixText: 'kg',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: set.repsCtrl,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              labelText: '반복',
              suffixText: '회',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          tooltip: '세트 삭제',
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
      ],
    );
  }
}

/// 즐겨찾기 종목 칩 row.
///
/// 본 트레이너의 즐겨찾기를 가로로 나열. 칩 탭 → onPick(name) 콜백.
/// 마지막 칩은 [관리] — 다이얼로그로 추가/삭제. 즐겨찾기 0개여도 안내 + 관리 진입 보장.
class _FavoritesRow extends ConsumerWidget {
  const _FavoritesRow({required this.enabled, required this.onPick});

  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoriteExercisesProvider);
    final colors = Theme.of(context).colorScheme;

    final manageChip = ActionChip(
      avatar: const Icon(Icons.settings_outlined, size: 16),
      label: const Text('관리'),
      onPressed: enabled ? () => showManageFavoritesDialog(context) : null,
    );

    return async.when(
      // 로딩/에러는 줄 자체를 숨기기엔 손해 — 관리 칩이라도 보여서 진입은 가능하게.
      loading: () => _wrap([manageChip]),
      error: (_, _) => _wrap([manageChip]),
      data: (list) {
        if (list.isEmpty) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  '즐겨찾기 종목을 등록하면 1탭으로 추가됩니다',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
              manageChip,
            ],
          );
        }
        return _wrap([
          for (final fav in list)
            ActionChip(
              avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
              label: Text(fav.name),
              onPressed: enabled ? () => onPick(fav.name) : null,
            ),
          manageChip,
        ]);
      },
    );
  }

  Widget _wrap(List<Widget> chips) =>
      Wrap(spacing: 8, runSpacing: 4, children: chips);
}

class _ConditionPicker extends StatelessWidget {
  const _ConditionPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  static const _options = [
    ('good', '좋음 😊'),
    ('normal', '보통 🙂'),
    ('bad', '나쁨 😣'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final opt in _options)
          ChoiceChip(
            label: Text(opt.$2),
            selected: value == opt.$1,
            onSelected: enabled
                ? (selected) => onChanged(selected ? opt.$1 : null)
                : null,
          ),
      ],
    );
  }
}
