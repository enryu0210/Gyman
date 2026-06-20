/// 회원 계정 연결 화면 — 초대 코드 입력 (Phase 2 회원 온보딩).
///
/// 라우트: `/member/claim`
///
/// 진입 시점: 로그인은 됐지만 아직 어떤 회원/트레이너 프로필과도 연결되지 않은 계정.
/// (회원이 막 가입한 직후가 대표 사례.)
///
/// 흐름: 트레이너가 준 초대 코드 입력 → claim_member_profile RPC →
///   성공 시 currentRoleProvider invalidate → 라우터가 /member/home 으로 보냄.
///
/// 트레이너가 실수로 이 화면에 온 경우(프로필 미설정)를 위해 로그아웃도 제공.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../settings/settings_providers.dart';
import 'auth_providers.dart';

class ClaimMemberScreen extends ConsumerStatefulWidget {
  const ClaimMemberScreen({super.key});

  @override
  ConsumerState<ClaimMemberScreen> createState() => _ClaimMemberScreenState();
}

class _ClaimMemberScreenState extends ConsumerState<ClaimMemberScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 소셜 가입자는 login_screen 의 동의 체크박스 흐름을 타지 않는다(버튼=동의 간주).
    // 세션이 생긴 뒤 첫 착지 화면인 여기서 동의 기록을 보장한다. recordConsent 는
    // upsert(멱등)라 이메일 가입자가 거쳐도 중복 무해하고, 실패해도 예외를 삼켜
    // 연결 흐름을 막지 않는다. (동의 자체는 가입 시점에 이미 게이트됨)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsRepositoryProvider).recordConsent();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '초대 코드를 입력해 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final memberId =
          await ref.read(roleRepositoryProvider).claimMemberProfile(code);
      if (memberId == null) {
        if (!mounted) return;
        setState(() => _error = '코드가 올바르지 않거나 이미 사용된 코드입니다.');
        return;
      }
      // 연결 성공 → 역할 재판정 → 라우터가 /member/home 으로 redirect.
      ref.invalidate(currentRoleProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('계정이 연결되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '연결 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('계정 연결'),
        actions: [
          // 미연결 상태에서도 설정(문의·약관·탈퇴·로그아웃)에 닿게 — U1.
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.link, size: 56, color: colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    '초대 코드 입력',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '담당 트레이너에게 받은 초대 코드를 입력하면\n내 PT 정보와 연결됩니다.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeCtrl,
                    enabled: !_busy,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _claim(),
                    decoration: const InputDecoration(
                      labelText: '초대 코드',
                      hintText: '예: A3F9C2B1',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _claim,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('연결하기'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '코드가 없으신가요? 담당 트레이너에게 문의해 주세요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
