import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Colours of the Claude-like look (warm neutral tones + terracotta accent).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.userBubble,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentHover,
    required this.code,
    required this.hover,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color userBubble;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentHover;
  final Color code;
  final Color hover;
  final Color success;
  final Color warning;
  final Color danger;

  static const light = AppColors(
    background: Color(0xFFFAF9F5),
    sidebar: Color(0xFFF3F1EA),
    surface: Color(0xFFFFFFFF),
    userBubble: Color(0xFFF0EEE6),
    border: Color(0xFFE3E1D7),
    text: Color(0xFF141413),
    textSecondary: Color(0xFF5E5D59),
    textTertiary: Color(0xFF8A8982),
    accent: Color(0xFFC96442),
    accentHover: Color(0xFFB05730),
    code: Color(0xFFF5F4EF),
    hover: Color(0xFFEAE8DF),
    success: Color(0xFF3D8A5A),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFC0392B),
  );

  static const dark = AppColors(
    background: Color(0xFF262624),
    sidebar: Color(0xFF1F1E1D),
    surface: Color(0xFF30302E),
    userBubble: Color(0xFF141413),
    border: Color(0xFF3E3E38),
    text: Color(0xFFF5F4EE),
    textSecondary: Color(0xFFC2C0B6),
    textTertiary: Color(0xFF9C9A92),
    accent: Color(0xFFD97757),
    accentHover: Color(0xFFE08A6D),
    code: Color(0xFF1E1D1B),
    hover: Color(0xFF353532),
    success: Color(0xFF6CC28C),
    warning: Color(0xFFE0B054),
    danger: Color(0xFFE5776A),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Primary serif family per platform (always installed there) - generic
/// names such as "serif" resolve unpredictably on Linux.
String get serifFamily => switch (defaultTargetPlatform) {
  TargetPlatform.windows => 'Georgia',
  TargetPlatform.macOS || TargetPlatform.iOS => 'Georgia',
  TargetPlatform.android || TargetPlatform.fuchsia => 'serif',
  TargetPlatform.linux => 'DejaVu Serif',
};

/// Primary monospace family per platform.
String get monoFamily => switch (defaultTargetPlatform) {
  TargetPlatform.windows => 'Consolas',
  TargetPlatform.macOS || TargetPlatform.iOS => 'Menlo',
  TargetPlatform.android || TargetPlatform.fuchsia => 'monospace',
  TargetPlatform.linux => 'DejaVu Sans Mono',
};

const List<String> serifFonts = [
  'Georgia',
  'Cambria',
  'Noto Serif',
  'DejaVu Serif',
  'Liberation Serif',
  'Times New Roman',
  'serif',
];

const List<String> monoFonts = [
  'Cascadia Mono',
  'Consolas',
  'SF Mono',
  'Menlo',
  'JetBrains Mono',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Noto Sans Mono',
  'Roboto Mono',
  'monospace',
];

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

TextStyle monoStyle(BuildContext context, {double size = 12.5, Color? color}) =>
    TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFonts,
      fontSize: size,
      height: 1.45,
      color: color ?? context.colors.text,
    );

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: Colors.white,
        surface: c.background,
        onSurface: c.text,
        outline: c.border,
        outlineVariant: c.border,
        error: c.danger,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    extensions: [c],
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    iconTheme: IconThemeData(color: c.textSecondary, size: 20),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: brightness == Brightness.dark ? c.surface : c.text,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: brightness == Brightness.dark ? c.text : c.background,
        fontSize: 12,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.accent, width: 1.4),
      ),
      labelStyle: TextStyle(color: c.textSecondary),
      hintStyle: TextStyle(color: c.textTertiary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : null,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      thumbColor: c.accent,
      inactiveTrackColor: c.border,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.25),
      selectionHandleColor: c.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.textTertiary.withValues(alpha: 0.4)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.accent.withValues(alpha: 0.14),
        selectedForegroundColor: c.text,
        side: BorderSide(color: c.border),
      ),
    ),
  );
}
