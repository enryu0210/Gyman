/// 설정 화면용 "AI 사용" 타일 — 회원 전용.
///
/// **왜 스위치 하나가 아니라 상태를 설명하는가:** 이 값은 두 사실의 조합이다.
///   ① 트레이너가 "동의를 받았다"고 기록했는가 (트레이너만 변경)
///   ② 회원 본인이 거부했는가            (회원만 변경)
/// 스위치만 보이면 회원이 "왜 꺼져 있는지"를 알 수 없다. ①이 아직 없어서 꺼진
/// 것과, 본인이 껐기 때문에 꺼진 것은 회원에게 전혀 다른 의미다.
///
/// 회원의 거부는 **항상 이긴다** — DB 트리거가 트레이너의 되돌리기를 막는다(0040).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'member_ai_consent_providers.dart';
import 'member_ai_consent_repository.dart';

class AiConsentSettingTile extends ConsumerWidget {
  const AiConsentSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAiConsentProvider);

    // 로딩·에러·미연결은 타일 자체를 숨긴다 — 설정 목록 한 칸에 에러 뷰를
    // 띄우면 다른 항목까지 못 쓰는 것처럼 보인다.
    final state = async.valueOrNull;
    if (state == null) return const SizedBox.shrink();

    return _Tile(state: state);
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.state});

  final MemberAiConsentState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = ref.watch(memberAiConsentControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: const Text('AI 기능 사용'),
          subtitle: Text(_subtitle()),
          // 스위치가 켜짐 = 전송 허용. 회원이 끄면 곧바로 거부로 기록된다.
          value: state.isActive,
          // 트레이너 동의 기록이 없으면 켤 대상이 없다 → 조작 불가.
          // (회원이 혼자 켜봐야 서버가 ai_consent 로 막는다)
          onChanged: (!state.trainerRecorded || busy)
              ? null
              : (allow) => _apply(context, ref, allow),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 20, 12),
          child: Text(
            '켜면 수업 기록·인바디 등이 이름을 가린 채 외부 AI 서비스로 전달되어 '
            '트레이너의 메모·안내 초안 작성에 쓰입니다. 언제든 끌 수 있고, '
            '끄면 트레이너가 다시 켤 수 없습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  String _subtitle() {
    if (state.memberOptedOut) return '거부함 — 전달되지 않습니다';
    if (!state.trainerRecorded) return '트레이너가 아직 동의를 등록하지 않았습니다';
    return '사용 중 — 이름을 가린 기록이 전달됩니다';
  }

  Future<void> _apply(BuildContext context, WidgetRef ref, bool allow) async {
    // 스위치 ON = 허용 = 거부 해제. 의미가 반대라 여기서 뒤집는다.
    await ref
        .read(memberAiConsentControllerProvider.notifier)
        .changeOptOut(!allow);

    if (!context.mounted) return;
    final result = ref.read(memberAiConsentControllerProvider);
    final message = result.hasError
        ? 'AI 사용 설정을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.'
        : (allow ? 'AI 기능 사용에 동의했습니다.' : 'AI 기능 사용을 거부했습니다.');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
