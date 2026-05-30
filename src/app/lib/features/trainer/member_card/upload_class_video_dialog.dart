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
