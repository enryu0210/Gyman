/// 수업 영상 업로드 세부정보 다이얼로그 (S 시리즈).
///
/// 영상 *선택·검증* 은 카드(class_videos_card)가 먼저 끝내고, 본 다이얼로그는
/// **제목 입력 + 동의 확인**만 받아 업로드를 실행한다.
///
/// **동의 게이트(설계 §3.4):** 영상 = 민감 개인정보. 회원의 촬영·보관 동의 없이는
///   업로드를 막아야 한다. 동의 *메커니즘*(플래그 vs 이력 테이블, 온보딩 vs 업로드 시점)은
///   설계 §9.6 미해결 + Phase 3.5 약관과 연계 예정 → MVP 에선 **트레이너가 "회원 동의를
///   받았음"을 확인하는 체크박스**를 게이트로 둔다(체크 전엔 업로드 비활성). 약관 확정 시
///   서버측 플래그로 승격.
///
/// 다이얼로그 진입점 패턴: `Future<bool?> showXxxDialog(...)`, 성공 시 true(=업로드 완료).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/enums.dart';
import '../session_log/session_providers.dart';
import '../session_log/session_repository.dart';
import 'class_video_providers.dart';

/// 업로드 다이얼로그 — 성공 시 true 반환.
/// [file] 선택·검증 완료된 영상, [durationSec] 측정된 길이(초, 없으면 null).
Future<bool?> showUploadClassVideoDialog(
  BuildContext context, {
  required String memberId,
  required File file,
  int? durationSec,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UploadClassVideoDialog(
      memberId: memberId,
      file: file,
      durationSec: durationSec,
    ),
  );
}

class _UploadClassVideoDialog extends ConsumerStatefulWidget {
  const _UploadClassVideoDialog({
    required this.memberId,
    required this.file,
    required this.durationSec,
  });

  final String memberId;
  final File file;
  final int? durationSec;

  @override
  ConsumerState<_UploadClassVideoDialog> createState() =>
      _UploadClassVideoDialogState();
}

class _UploadClassVideoDialogState
    extends ConsumerState<_UploadClassVideoDialog> {
  final _titleCtrl = TextEditingController();

  /// 회원 동의 확인 — 체크해야 업로드 활성(설계 §3.4 게이트).
  bool _consent = false;

  /// 연결할 수업(sessions.id). null = 연결 안 함(회원 단위로만 보관).
  String? _sessionId;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(classVideoControllerProvider.notifier).upload(
          memberId: widget.memberId,
          file: widget.file,
          title: _titleCtrl.text,
          durationSec: widget.durationSec,
          sessionId: _sessionId,
        );

    if (!mounted) return;
    final state = ref.read(classVideoControllerProvider);
    if (state.hasError) {
      final msg = state.error?.toString() ?? '영상 업로드에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final uploading = ref.watch(classVideoControllerProvider).isLoading;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('수업 영상 업로드'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                enabled: !uploading,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '제목 (선택)',
                  hintText: '예: 스쿼트 폼 체크',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // 특정 수업과 연결(선택). 연결하면 회원/트레이너 화면에서 "어느 수업의
              // 영상인지" 라벨로 보인다. session_id 컬럼은 0027 에 이미 존재.
              _SessionPicker(
                memberId: widget.memberId,
                selectedId: _sessionId,
                enabled: !uploading,
                onChanged: (id) => setState(() => _sessionId = id),
              ),
              const SizedBox(height: 4),
              // 동의 게이트 — 체크 전엔 업로드 버튼 비활성.
              CheckboxListTile(
                value: _consent,
                onChanged: uploading
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '회원에게 영상 촬영·보관 동의를 받았습니다.',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  '업로드한 영상은 해당 회원만 앱에서 볼 수 있습니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: uploading ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          // 동의 미체크면 업로드 불가(설계 §3.4).
          onPressed: (uploading || !_consent) ? null : _submit,
          child: uploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('업로드'),
        ),
      ],
    );
  }
}

/// 영상을 연결할 수업 선택 드롭다운(선택). 최근 수업을 불러와 "연결 안 함"과 함께 제시.
///
/// **신청(requested)은 제외:** 아직 트레이너가 승인하지 않은 회원 신청이라
///   "진행된/예정된 수업"이 아니므로 영상 연결 대상에서 뺀다.
///
/// 수업 목록 로딩 중이거나 연결 가능한 수업이 없으면 드롭다운을 숨긴다 —
/// 연결은 어디까지나 선택이라 없을 때 굳이 빈 컨트롤을 띄우지 않는다.
class _SessionPicker extends ConsumerWidget {
  const _SessionPicker({
    required this.memberId,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final String memberId;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentSessionsForMemberProvider(memberId));

    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (sessions) {
        // 연결 대상 후보: 신청(requested) 제외.
        final selectable = sessions
            .where((s) => s.session.status != SessionStatus.requested)
            .toList(growable: false);
        if (selectable.isEmpty) return const SizedBox.shrink();

        return DropdownButtonFormField<String?>(
          // Flutter 3.32+: value → initialValue (CLAUDE.md Dart 패턴).
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '연결할 수업 (선택)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('연결 안 함'),
            ),
            for (final s in selectable)
              DropdownMenuItem<String?>(
                value: s.session.id,
                child: Text(_sessionLabel(s), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        );
      },
    );
  }

  /// "2026-05-30 · 완료" 형태의 짧은 라벨.
  static String _sessionLabel(SessionWithRecord s) {
    final date = formatKoreanDate(s.session.scheduledAt);
    return '$date · ${_statusLabel(s.session.status)}';
  }

  static String _statusLabel(SessionStatus status) {
    switch (status) {
      case SessionStatus.scheduled:
        return '예약';
      case SessionStatus.done:
        return '완료';
      case SessionStatus.noShow:
        return '노쇼';
      case SessionStatus.canceled:
        return '취소';
      case SessionStatus.lateCancel:
        return '당일취소';
      case SessionStatus.requested:
        return '신청'; // 후보에서 제외되지만 switch 완전성 위해 둠
    }
  }
}
