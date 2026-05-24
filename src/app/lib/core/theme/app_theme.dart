import 'package:flutter/material.dart';

/// 앱 전역 테마 정의 (Material 3 기반).
///
/// 디자인 시스템 확정 전 임시 시드 컬러(Indigo)를 사용한다.
/// 추후 디자인 가이드가 정해지면 [seedColor]와 폰트만 교체해서 전체 톤을 바꿀 수 있다.
class AppTheme {
  // 임시 시드 컬러 — develop_plan.md 데모 단계 이후 디자인 확정 시 교체
  static const Color _seed = Color(0xFF3F51B5); // Indigo 500

  /// 라이트 모드 테마
  static ThemeData get light => _build(Brightness.light);

  /// 다크 모드 테마 (시스템 설정에 따라 자동 적용)
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // 한국어 가독성 확보 — 시스템 폰트 사용. 추후 Pretendard 등 추가 가능
      // (asset 등록 후 fontFamily 지정)
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
