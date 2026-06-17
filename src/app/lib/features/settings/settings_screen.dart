/// 설정 화면 — 모든 역할 공통 진입(`/settings`).
///
/// 운톡 불만 대응의 집결지:
///   - 문의하기(#5)        : 앱 내 문의 → 운영자 수신
///   - 이용약관/개인정보(3.5): 약관·정책 열람
///   - 회원 탈퇴(#1)        : 익명화 탈퇴 (회원에게만 노출)
///   - 로그아웃
///
/// **U1(빈/미연결 상태에도 탈출구 보장):** 라우터에서 역할 무관 진입을 허용하므로,
///   계정 연결 전(role=null) 사용자도 여기서 탈퇴·문의에 닿을 수 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_info.dart';
import '../../domain/models/enums.dart';
import '../auth/auth_providers.dart';
import '../legal/legal_content.dart';
import '../member/notifications/reminder_setting_tile.dart';
import 'delete_account_dialog.dart';
import 'inquiry_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 역할 — 탈퇴 노출 판단용. 트레이너/관리자는 베타에서 운영자가 관리하므로 숨김.
    final role = ref.watch(currentRoleProvider).value;
    final canDelete = role != UserRole.trainer && role != UserRole.admin;
    // PT 알림은 본인 예약 기준이라 회원에게만 노출.
    final isMember = role == UserRole.member;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          if (isMember) ...[
            const _SectionLabel('알림'),
            const PtReminderSettingTile(),
            const Divider(height: 1),
          ],

          const _SectionLabel('지원'),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('문의하기'),
            subtitle: const Text('불편한 점·궁금한 점을 운영자에게 남기기'),
            onTap: () async {
              final sent = await showInquiryDialog(context);
              if (sent == true && context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text('문의가 접수되었습니다. 확인 후 처리하겠습니다.'),
                  ));
              }
            },
          ),
          const Divider(height: 1),

          const _SectionLabel('약관·정책'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('이용약관'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(LegalDoc.terms.route),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보 처리방침'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(LegalDoc.privacy.route),
          ),
          const Divider(height: 1),

          const _SectionLabel('계정'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () => ref.read(signInControllerProvider.notifier).signOut(),
          ),
          if (canDelete) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                '회원 탈퇴',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('개인정보 익명 처리 후 계정 삭제'),
              onTap: () async {
                final done = await showDeleteAccountDialog(context);
                // 성공 시 컨트롤러가 로그아웃 → 라우터가 /login 으로 보냄(별도 처리 불필요).
                if (done == true && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                      content: Text('탈퇴가 완료되었습니다.'),
                    ));
                }
              },
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              '앱 버전 $kAppVersion',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 섹션 구분 라벨 — 리스트 그룹 헤더.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
