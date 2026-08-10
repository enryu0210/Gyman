/// 약관/개인정보 처리방침 정적 표시 화면.
///
/// 라우트: `/legal/terms`, `/legal/privacy` (둘 다 본 화면 재사용 — [doc]로 분기).
///
/// 본문은 `legal_content.dart` 의 임시 초안. 버전 placeholder 는 실제 날짜로 치환해
/// 표시한다. 외부 호스팅 약관이 생기면 이 화면 대신 URL 연결로 전환 가능.
library;

import 'package:flutter/material.dart';

import '../../core/config/app_info.dart';
import 'legal_content.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // const 본문의 placeholder 를 실제 값으로 치환.
    // 운영자 성명·연락처가 미기재면 `{{운영자_성명}}` 이 화면에 그대로 보인다 —
    // 의도된 동작이다(app_info.dart 주석 참조).
    final body = doc.body
        .replaceAll(kTermsVersionPlaceholder, kTermsVersion)
        .replaceAll(kPrivacyVersionPlaceholder, kPrivacyVersion)
        .replaceAll(kOperatorNamePlaceholder, kOperatorName)
        .replaceAll(kOperatorContactPlaceholder, kOperatorContact);

    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // 초안 안내 — 법무 검토 전임을 명시(사용자 결정: 앱 내 임시 초안).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: colors.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kLegalDraftNotice,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            body.trim(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }
}
