/// 역할별 하단 탭을 담는 **공통 앱 셸** (UI 1차 개편 단계 A).
///
/// **왜 별도 위젯인가:**
///   트레이너 셸을 먼저 적용하고 회원 셸은 후속 적용이지만(ui_renewal_phase1_plan §3.3),
///   두 역할이 같은 하단 바를 써야 톤이 어긋나지 않는다. 그래서 "탭 목록 + 가운데
///   강조 액션" 만 받는 역할 무관 컴포넌트로 만들어 둔다. 역할별 셸(trainer_shell 등)은
///   탭 스펙과 배지 데이터만 채워 넣는다.
///
/// **왜 Material [NavigationBar] 가 아닌가:**
///   가운데 "기록하기"를 다른 탭보다 강조(볼트 라임 채우기)해야 하는데,
///   NavigationBar 는 모든 목적지를 같은 무게로 그린다. 커스텀 Row 로 만들면
///   강조 슬롯 + 안전 영역 + 터치 영역을 직접 통제할 수 있다.
///
/// **디자인(리포 루트 `DESIGN.md` 준수):**
///   - 볼트 라임은 "채우기 배경 + 그 위 잉크 글씨"로만 — 선택된 탭 라벨을 라임
///     텍스트로 쓰면 밝은 배경에서 대비가 무너지므로 선택 색은 `onSurface` 를 쓴다.
///   - 바는 그림자 대신 상단 1px 경계선으로 본문과 구획.
///   - 이모지 금지, Material `*_outlined` 라인 아이콘.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 하단 탭 1개의 표시 스펙.
class AppShellTab {
  const AppShellTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  /// 비선택 상태 아이콘(`*_outlined` 라인).
  final IconData icon;

  /// 선택 상태 아이콘(채워진 형태) — 색만으로 구분하지 않기 위한 두 번째 신호.
  final IconData selectedIcon;

  final String label;

  /// >0 이면 아이콘 우상단에 카운트 배지(안읽음·승인 대기 등).
  final int badgeCount;
}

/// 하단 바 가운데에 놓이는 **강조 액션**. 탭이 아니라 즉시 실행 동작이다.
///
/// 탭(=화면 전환)이 아닌 이유: "기록하기"는 머무는 화면이 아니라 *어느 회원의*
/// 기록을 시작할지 고르고 바로 빠지는 동작이다. 탭으로 두면 돌아올 곳 없는
/// 빈 탭이 하나 생긴다.
class AppShellAction {
  const AppShellAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// 하단 탭 + (선택) 가운데 강조 액션을 가진 셸 Scaffold.
///
/// [child] 는 보통 `StatefulNavigationShell` — 탭별 Navigator 를 IndexedStack 으로
/// 유지해 탭 전환 후에도 스크롤 위치·목록 상태가 보존된다.
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    super.key,
    required this.child,
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    this.centerAction,
  });

  final Widget child;
  final List<AppShellTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  /// null 이면 가운데 강조 버튼 없이 탭만 균등 배치.
  final AppShellAction? centerAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _ShellBottomBar(
        tabs: tabs,
        currentIndex: currentIndex,
        onTabSelected: onTabSelected,
        centerAction: centerAction,
      ),
    );
  }
}

// =====================================================================
// 하단 바
// =====================================================================

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.centerAction,
  });

  final List<AppShellTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final AppShellAction? centerAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 강조 액션은 탭 목록의 정확히 가운데에 끼워 넣는다(탭 4개 → 2번째와 3번째 사이).
    final action = centerAction;
    final slots = <Widget>[];
    final middle = tabs.length ~/ 2;
    for (var i = 0; i < tabs.length; i++) {
      if (action != null && i == middle) {
        slots.add(Expanded(child: _CenterActionButton(action: action)));
      }
      slots.add(
        Expanded(
          child: _TabButton(
            tab: tabs[i],
            selected: i == currentIndex,
            onTap: () => onTabSelected(i),
          ),
        ),
      );
    }
    if (action != null && tabs.length <= middle) {
      // 탭이 0개인 방어적 경우 — 강조 버튼만 그린다.
      slots.add(Expanded(child: _CenterActionButton(action: action)));
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        // 그림자 대신 얇은 선으로 본문과 구획(카드 톤과 동일 색).
        border: Border(
          top: BorderSide(color: AppTheme.lineColor(theme.brightness)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(children: slots),
        ),
      ),
    );
  }
}

/// 일반 탭 버튼 — 아이콘(+배지) 위, 라벨 아래.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 선택 색은 라임이 아니라 onSurface — 밝은 배경 위 라임 텍스트는 대비 실패
    // (DESIGN.md: 라임은 채우기 전용). 아이콘 모양(outlined→filled)이 보조 신호.
    final fg = selected ? colors.onSurface : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkResponse(
        onTap: onTap,
        // 작은 화면에서도 손가락이 닿는 넓은 반응 영역.
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconWithBadge(
              icon: selected ? tab.selectedIcon : tab.icon,
              color: fg,
              badgeCount: tab.badgeCount,
            ),
            const SizedBox(height: 3),
            _BarLabel(
              text: tab.label,
              color: fg,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }
}

/// 가운데 강조 버튼 — 볼트 라임 채우기 + 잉크 아이콘.
///
/// 하단 바 위로 튀어나오게 하지 않은 이유: 작은 화면·제스처 내비게이션 기기에서
/// 겹침/클리핑과 터치 영역 문제가 생기기 쉽다. 주변이 전부 무채색이라 라임 채우기
/// 하나만으로도 충분히 강조된다(계획서 §3.1 "볼트 라임의 가운데 버튼" 안).
class _CenterActionButton extends StatelessWidget {
  const _CenterActionButton({required this.action});
  final AppShellAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      child: InkResponse(
        onTap: action.onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.volt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(action.icon, size: 20, color: AppTheme.onVolt),
            ),
            const SizedBox(height: 3),
            _BarLabel(
              text: action.label,
              color: Theme.of(context).colorScheme.onSurface,
              weight: FontWeight.w700,
            ),
          ],
        ),
      ),
    );
  }
}

/// 하단 바 라벨 — 글자 확대 설정에서도 바가 넘치지 않게 배율을 제한한다.
///
/// 시스템 글자 크기를 크게 쓰는 사용자에게도 라벨이 잘리지 않게 하되, 바 높이가
/// 고정이라 무제한 확대는 오버플로가 된다 → 1.2배까지만 따른다.
class _BarLabel extends StatelessWidget {
  const _BarLabel({
    required this.text,
    required this.color,
    required this.weight,
  });

  final String text;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.2,
    );
    return Text(
      text,
      textScaler: scaler,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, fontWeight: weight, color: color),
    );
  }
}

/// 아이콘 + 우상단 카운트 배지(안읽음·승인 대기).
class _IconWithBadge extends StatelessWidget {
  const _IconWithBadge({
    required this.icon,
    required this.color,
    required this.badgeCount,
  });

  final IconData icon;
  final Color color;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (badgeCount <= 0) {
      return Icon(icon, size: 23, color: color);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 23, color: color),
        Positioned(
          top: -4,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              // 홈 격자·채팅 목록 배지와 동일 톤(errorContainer)으로 통일.
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.onErrorContainer,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
