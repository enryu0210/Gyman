/// 회원 상세 "트레이너 전용 메모" 카드 (Phase 1.10, AI-C).
///
/// **회원에게 절대 안 보임** (RLS + visibility=trainer_only). 이 카드는 트레이너 화면 전용.
///
/// 구성:
///   - AI 초안(ai_draft): 상단에 강조 + [확정]/[수정]/[삭제] (와이어 6.4)
///   - 확정/수동 메모: 아래 목록
///   - 상단 액션: [AI 초안 생성](최근 수업 기반) / [직접 추가]
///
/// 생성/확정/수정/삭제는 [memberNoteControllerProvider] 경유. 생성 실패는 code별
/// 폴백 SnackBar(consent/rate_limited/llm_failed/no_session) — 앱이 멈추지 않음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/enums.dart';
import '../ai_review/ai_review_repository.dart' show AiGenerationException;
import 'member_note_providers.dart';
import 'member_note_repository.dart';

class MemberNotesCard extends ConsumerWidget {
  const MemberNotesCard({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final async = ref.watch(notesForMemberProvider(memberId));
    final busy = ref.watch(memberNoteControllerProvider).isLoading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('트레이너 전용 메모',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Tooltip(
                  message: '회원에게는 보이지 않습니다',
                  child: Icon(Icons.visibility_off_outlined,
                      size: 16, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 액션
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _generate(context, ref),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AI 초안 생성'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: busy ? null : () => _addManual(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('직접 추가'),
                ),
              ],
            ),
            const SizedBox(height: 4),

            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('메모를 불러오지 못했습니다.\n$e',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              data: (notes) {
                if (notes.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 메모가 없습니다. AI 초안을 생성하거나 직접 추가하세요.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                final drafts = notes.where((n) => n.isDraft).toList();
                final confirmed = notes.where((n) => n.isConfirmed).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final n in drafts)
                      _DraftNoteTile(
                          memberId: memberId, note: n),
                    for (final n in confirmed)
                      _ConfirmedNoteTile(
                          memberId: memberId, note: n),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(memberNoteControllerProvider.notifier)
          .generate(memberId: memberId);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('AI 메모 초안이 생성되었습니다. 검수 후 확정하세요.')));
    } on AiGenerationException catch (e) {
      // 폴백: 앱이 멈추지 않고 사유 안내.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('AI 메모 생성 실패: $e')));
    }
  }

  Future<void> _addManual(BuildContext context, WidgetRef ref) async {
    final content = await showNoteEditDialog(context, title: '메모 추가');
    if (content == null || content.trim().isEmpty) return;
    if (!context.mounted) return;
    await ref
        .read(memberNoteControllerProvider.notifier)
        .addManual(memberId: memberId, content: content.trim());
  }
}

// =====================================================================
// AI 초안 타일 — 확정/수정/삭제
// =====================================================================

class _DraftNoteTile extends ConsumerWidget {
  const _DraftNoteTile({required this.memberId, required this.note});
  final String memberId;
  final MemberNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(memberNoteControllerProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.tertiaryContainer),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: colors.tertiary),
              const SizedBox(width: 6),
              Text('AI 초안 — 검수 필요',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.tertiary,
                        fontWeight: FontWeight.w700,
                      )),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.content, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    controller.delete(id: note.id, memberId: memberId),
                child: Text('삭제', style: TextStyle(color: colors.error)),
              ),
              TextButton(
                onPressed: () async {
                  final edited = await showNoteEditDialog(context,
                      title: '메모 수정', initial: note.content);
                  if (edited == null || !context.mounted) return;
                  await controller.editContent(
                      id: note.id, memberId: memberId, content: edited.trim());
                },
                child: const Text('수정'),
              ),
              FilledButton(
                onPressed: () =>
                    controller.confirm(id: note.id, memberId: memberId),
                child: const Text('확정'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 확정/수동 메모 타일 — 수정/삭제
// =====================================================================

class _ConfirmedNoteTile extends ConsumerWidget {
  const _ConfirmedNoteTile({required this.memberId, required this.note});
  final String memberId;
  final MemberNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(memberNoteControllerProvider.notifier);
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.content,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${note.source == NoteSource.aiConfirmed ? 'AI 확정' : '직접 작성'}'
                  ' · ${dateFmt.format(note.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18, color: colors.onSurfaceVariant),
            onSelected: (v) async {
              if (v == 'edit') {
                final edited = await showNoteEditDialog(context,
                    title: '메모 수정', initial: note.content);
                if (edited == null || !context.mounted) return;
                await controller.editContent(
                    id: note.id, memberId: memberId, content: edited.trim());
              } else if (v == 'delete') {
                await controller.delete(id: note.id, memberId: memberId);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('수정')),
              PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 메모 편집/추가 다이얼로그
// =====================================================================

/// 메모 내용 편집 다이얼로그. 저장 시 내용 문자열 반환(취소 시 null).
///
/// 컨트롤러는 [_NoteEditDialogState] 가 소유한다 — 리빌드로 재생성되지 않아
/// 한글 IME 조합이 끊기지 않고, 폐기 시점도 위젯 수명과 정확히 맞는다.
///
/// **왜 StatefulWidget 인가 (2026-07-29 실기기 크래시):**
///   이전 구현은 `showDialog` 를 `try/finally` 로 감싸 `await` 직후
///   `ctrl.dispose()` 를 호출했다. 그런데 `showDialog` 의 Future 는
///   `Navigator.pop` 시점에 완료되고 **다이얼로그 퇴장 애니메이션은 그 뒤에도
///   계속된다** — 즉 `TextField` 가 아직 트리에 살아 있는 상태에서 컨트롤러가
///   폐기되어, 라우트가 걷힐 때 `InheritedElement.debugDeactivated()` 의
///   `'_dependents.isEmpty': is not true` assertion 으로 앱이 붉은 화면에 빠졌다.
///   `State.dispose()` 는 위젯이 트리에서 완전히 제거된 뒤에 불리므로 안전하다.
///   (이 파일 밖의 다이얼로그들은 원래 전부 이 패턴이라 영향 없었음)
Future<String?> showNoteEditDialog(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteEditDialog(title: title, initial: initial),
  );
}

class _NoteEditDialog extends StatefulWidget {
  const _NoteEditDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends State<_NoteEditDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 6,
        minLines: 3,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '트레이너 전용 메모 (회원에게 안 보임)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            // 빈 내용은 null 로 — 호출부가 "저장 안 함"과 같게 처리한다.
            final text = _ctrl.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
