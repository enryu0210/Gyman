import 'package:flutter/material.dart';

/// 앱 전역 테마 — "블랙 + 볼트 라임" 에너제틱 스포츠 디자인 시스템.
///
/// 설계 원칙(자세한 근거는 리포 루트 `DESIGN.md`):
///   - 에너지는 **볼트 라임(#C6FF00) 한 색**으로만. 나머지 무게는 잉크 블랙과 여백이 잡는다.
///   - **볼트 라임은 "채우기(fill) 배경 + 그 위 검은 글씨"로만** 쓴다. 밝은 배경에 라임을
///     텍스트/아이콘 색으로 쓰면 대비(WCAG)가 무너져 안 보이기 때문. (리서치 결론)
///   - 라이트 모드: 강조는 잉크(차분) → 트레이너의 데이터 화면이 시끄럽지 않다.
///   - 다크 모드: 강조는 볼트(전기적) → 다크 배경 위에서 라임이 가장 살아난다.
///
/// 색·형태 값은 여기 [ColorScheme] + 컴포넌트 테마 한 곳에 모여 있어, 화면 코드를
/// 거의 건드리지 않고 앱 전체 톤을 바꿀 수 있다.
class AppTheme {
  AppTheme._();

  // ── 브랜드 상수 (위젯에서 볼트 블록을 직접 그릴 때 참조) ──
  /// 잉크 블랙 — 텍스트·기본 버튼·라이트 강조.
  static const Color ink = Color(0xFF16181D);

  /// 볼트 라임 — 강조 "채우기" 전용. 이 위에 얹는 글씨는 항상 [ink].
  static const Color volt = Color(0xFFC6FF00);

  /// 볼트 블록 위 글씨/아이콘 색(= 잉크). 의미를 드러내려 별칭으로 둔다.
  static const Color onVolt = ink;

  /// 잉크 블록(트레이너 홈 히어로 등) 위에 얹는 밝은 글씨 기본색.
  /// 다크 모드 onSurface 와 같은 톤 — 라이트/다크 상관없이 잉크 배경에서 안전.
  static const Color onInk = Color(0xFFECEEE9);

  /// 카드/타일 경계선 색 — [cardTheme] 과 동일 값. 위젯에서 카드 톤의
  /// 얇은 테두리를 직접 그릴 때 참조(예: 메뉴 그리드 타일)해 카드와 어긋나지 않게.
  static Color lineColor(Brightness brightness) =>
      brightness == Brightness.dark ? _lineDark : _lineLight;

  // ── 라이트/다크 표면 값 ──
  static const Color _canvasLight = Color(0xFFF4F5F3); // 앱 배경(살짝 웜한 그레이)
  static const Color _surfaceLight = Color(0xFFFFFFFF); // 카드
  static const Color _lineLight = Color(0xFFE6E7E3); // 경계선

  static const Color _canvasDark = Color(0xFF0F1012);
  static const Color _surfaceDark = Color(0xFF16181D);
  static const Color _lineDark = Color(0xFF262930);

  static const String _fontFamily = 'Pretendard';

  /// 라이트 모드 테마.
  static ThemeData get light => _build(Brightness.light);

  /// 다크 모드 테마 (시스템 설정에 따라 자동 적용).
  static ThemeData get dark => _build(Brightness.dark);

  /// 라임 CTA가 필요한 버튼에 쓰는 스타일(예: "수업 예약하기").
  /// 기본 [FilledButton]은 잉크색이므로, 강조가 필요한 곳에서만 이걸 지정한다.
  static ButtonStyle get voltButtonStyle => FilledButton.styleFrom(
        backgroundColor: volt,
        foregroundColor: onVolt,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark ? _canvasDark : _canvasLight;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final line = isDark ? _lineDark : _lineLight;
    final scheme = _scheme(brightness, surface);

    // 버튼 라운드/여백은 앱 전체에서 반복되므로 한 번만 정의해 재사용한다.
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const buttonText = TextStyle(
      fontFamily: _fontFamily,
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: canvas,

      // 앱바는 배경(canvas)과 자연스럽게 이어지도록 — 스크롤 시 M3 틴트도 끈다.
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 19,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),

      // 카드 = 흰(다크는 어두운) 표면 + 얇은 경계선 + 큰 라운드. 그림자 대신 선으로 구획.
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: line),
        ),
      ),

      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 12.5,
          color: scheme.onSurfaceVariant,
        ),
      ),

      // 기본 CTA = 잉크(라이트)/볼트(다크). 형태만 통일하고 색은 ColorScheme가 잡는다.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: buttonText,
          side: BorderSide(color: line),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: buttonText),
      ),

      // 폼 입력칸 — 채워진 배경 + 큰 라운드 + 포커스 시 강조색 테두리.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _surfaceDark : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  /// 브랜드 역할을 씌운 [ColorScheme]. `fromSeed`로 중립 표면 계열을 생성한 뒤
  /// 핵심 역할(primary/tertiary/surface/error)만 브랜드 값으로 덮어쓴다.
  static ColorScheme _scheme(Brightness brightness, Color surface) {
    final isDark = brightness == Brightness.dark;
    // 시드: 라이트는 잉크(중립 회색 계열), 다크는 볼트(라임이 강조로 살아나게).
    final base = ColorScheme.fromSeed(
      seedColor: isDark ? volt : ink,
      brightness: brightness,
    );

    if (isDark) {
      return base.copyWith(
        primary: volt,
        onPrimary: ink,
        primaryContainer: const Color(0xFF2C3300),
        onPrimaryContainer: volt,
        tertiary: volt,
        onTertiary: ink,
        tertiaryContainer: volt,
        onTertiaryContainer: ink,
        surface: surface,
        onSurface: const Color(0xFFECEEE9),
        error: const Color(0xFFFF6169),
        onError: ink,
      );
    }
    return base.copyWith(
      primary: ink,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE9EBE6),
      onPrimaryContainer: ink,
      secondary: const Color(0xFF3B3F45),
      onSecondary: Colors.white,
      // 라임을 텍스트로 써야 하는 극히 드문 경우를 위한 "읽히는 볼트"(딥 올리브).
      tertiary: const Color(0xFF5B6B00),
      onTertiary: Colors.white,
      // 볼트 "채우기" 역할 — 그 위 글씨는 onTertiaryContainer(잉크).
      tertiaryContainer: volt,
      onTertiaryContainer: ink,
      surface: surface,
      onSurface: ink,
      error: const Color(0xFFE5484D),
      onError: Colors.white,
    );
  }
}
