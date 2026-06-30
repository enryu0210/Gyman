/// 비동기 상태(로딩·에러·빈 상태) 공용 위젯 모음.
///
/// 왜 한곳에 모으나:
/// 거의 같은 "에러 아이콘 + 안내 문구 + [다시 시도]" 화면이 20개 넘는 파일에
/// 복붙돼 있었다(운톡 개선 U7). 아이콘이 어떤 화면은 `cloud_off`, 어떤 화면은
/// 빨간 `error_outline` 으로 제각각이라 일관성도 깨졌다. 레이아웃·기본 카피·아이콘을
/// 여기로 모아 한 번만 정의하고, 화면별로 다른 부분(문구·액션)만 파라미터로 받는다.
///
/// 사용 원칙(운톡 §3 UI/UX):
/// - 에러 카피에 "오류가 발생했습니다" 같은 막연한 문구 금지 → 무엇을 못 했는지 + 다음 행동.
/// - 빈 상태는 행동 유도 문구를 준다("첫 기록을 남겨보세요").
/// - 로딩은 빈 화면 대신 스피너(긴 목록은 화면별 스켈레톤을 따로 둘 수 있음).
library;

import 'package:flutter/material.dart';

/// 전체 화면용 에러 뷰. `AsyncValue.error` 분기에서 사용.
///
/// - [message] : 사용자용 안내. 비우면 일반 폴백 카피.
/// - [detail]  : 기술적 원인(예: 예외 문자열). 작은 회색 글씨로 덧붙인다. null 이면 숨김.
/// - [onRetry] : null 이면 [다시 시도] 버튼을 숨긴다(재시도 수단이 없는 화면).
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    this.message,
    this.detail,
    this.onRetry,
    this.icon = Icons.cloud_off,
  });

  final String? message;
  final String? detail;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message ?? '정보를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 전체 화면용 빈 상태 뷰. 목록/조회 결과가 없을 때 사용.
///
/// 화면별로 다른 [message]·[icon]·[action] 만 받아 레이아웃은 공통화한다.
/// - [title]  : 굵은 한 줄 제목(선택). 비우면 [message] 만 보여준다.
/// - [action] : 행동 유도 버튼(선택). 예: [등록하기].
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colors.outline),
            const SizedBox(height: 12),
            if (title != null) ...[
              Text(title!, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 로딩 — 중앙 스피너. 빈 화면 대신 항상 이 위젯으로 로딩을 표시한다.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// 카드/섹션 안에 들어가는 컴팩트 에러 행. 전체 화면을 차지하지 않는 부분 위젯
/// (예: 회원 상세 안의 계약/측정 카드)이 조회에 실패했을 때 사용.
class AppInlineError extends StatelessWidget {
  const AppInlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: theme.textTheme.bodySmall),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
