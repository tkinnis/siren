import 'package:flutter/material.dart';

class SirenTheme {
  // Light Theme Tokens
  static const Color _lightBg = Color(0xFFf8f8fc); // --bg-surface
  static const Color _lightSurfaceContainer = Color(
    0xFFe8e8f0,
  ); // --bg-surface-container
  static const Color _lightCodeBg = Color(0xFFe8e8f0); // --bg-code

  static const Color _lightTextBody = Color(0xFF1a1a2e); // --text-body
  static const Color _lightTextMuted = Color(0xFF3a3a52); // --text-muted
  static const Color _lightTextHeading = Color(0xFF2060c0); // --text-heading

  static const Color _lightPrimary = Color(0xFF00a080); // --color-primary
  static const Color _lightBorder = Color(0xFFd0d0e0); // --color-border
  static const Color _lightDivider = Color(0xFFe0e0ec); // --color-divider
  static const Color _lightQuoteBorder = Color(
    0xFF00a080,
  ); // --color-quote-border

  // Dark Theme Tokens
  static const Color _darkBg = Color(0xFF1a1a2e); // --bg-surface
  static const Color _darkSurfaceContainer = Color(
    0xFF0f0f1a,
  ); // --bg-surface-container
  static const Color _darkCodeBg = Color(0xFF25253e); // --bg-code

  static const Color _darkTextBody = Color(0xFFe0e0f0); // --text-body
  static const Color _darkTextMuted = Color(0xFFc8c8e0); // --text-muted
  static const Color _darkTextHeading = Color(0xFF6bb8ff); // --text-heading

  static const Color _darkPrimary = Color(0xFF00d4aa); // --color-primary
  static const Color _darkBorder = Color(0xFF3d3d5c); // --color-border
  static const Color _darkDivider = Color(0xFF2d2d4a); // --color-divider
  static const Color _darkQuoteBorder = Color(
    0xFF00d4aa,
  ); // --color-quote-border

  static final ThemeData light = _buildLightTheme();
  static final ThemeData dark = _buildDarkTheme();

  static ThemeData _buildLightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _lightBg,
      colorScheme: base.colorScheme.copyWith(
        primary: _lightPrimary,
        surface: _lightBg,
        onSurface: _lightTextBody,
        onSurfaceVariant: _lightTextMuted,
        outline: _lightBorder,
        surfaceContainer: _lightSurfaceContainer,
      ),
      dividerTheme: const DividerThemeData(color: _lightDivider, thickness: 1),
      textTheme: base.textTheme.apply(
        bodyColor: _lightTextBody,
        displayColor: _lightTextBody,
        fontFamily: '.AppleSystemUIFont', // Explicitly prefer system font on macOS
      ),
      iconTheme: const IconThemeData(color: _lightTextBody, size: 20),
      extensions: [
        const SirenColors(
          sidebarBg:
              _lightSurfaceContainer, // Using container color for sidebar to distinguish
          codeBg: _lightCodeBg,
          headingColor: _lightTextHeading,
          quoteBorder: _lightQuoteBorder,
          divider: _lightDivider,
          // Restored mappings
          tabBg: _lightSurfaceContainer,
          activeTabBg: _lightBg,
          borderColor: _lightBorder,
          iconColor: _lightTextBody,
        ),
      ],
    );
  }

  static ThemeData _buildDarkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _darkBg,
      colorScheme: base.colorScheme.copyWith(
        primary: _darkPrimary,
        surface: _darkBg,
        onSurface: _darkTextBody,
        onSurfaceVariant: _darkTextMuted,
        outline: _darkBorder,
        surfaceContainer: _darkSurfaceContainer,
      ),
      dividerTheme: const DividerThemeData(color: _darkDivider, thickness: 1),
      textTheme: base.textTheme.apply(
        bodyColor: _darkTextBody,
        displayColor: _darkTextBody,
        fontFamily: '.AppleSystemUIFont',
      ),
      iconTheme: const IconThemeData(color: _darkTextBody, size: 20),
      extensions: [
        const SirenColors(
          sidebarBg: _darkSurfaceContainer,
          codeBg: _darkCodeBg,
          headingColor: _darkTextHeading,
          quoteBorder: _darkQuoteBorder,
          divider: _darkDivider,
          // Restored mappings
          tabBg: _darkSurfaceContainer,
          activeTabBg: _darkBg,
          borderColor: _darkBorder,
          iconColor: _darkTextBody,
        ),
      ],
    );
  }

  static const Map<String, TextStyle> showcaseLightTheme = {
    'root': TextStyle(backgroundColor: _lightCodeBg, color: _lightTextBody),
    'keyword': TextStyle(color: Color(0xFF8040a0)),
    'function': TextStyle(color: Color(0xFF2060c0)),
    'string': TextStyle(color: Color(0xFF208050)),
    'comment': TextStyle(color: Color(0xFF8a8aa2), fontStyle: FontStyle.italic),
    'quote': TextStyle(color: Color(0xFF8a8aa2)),
    'doctag': TextStyle(color: Color(0xFF8a8aa2)),
    'variable': TextStyle(color: Color(0xFF1a1a2e)),
    'template-variable': TextStyle(color: Color(0xFF1a1a2e)),
    'tag': TextStyle(color: Color(0xFF8040a0)),
    'name': TextStyle(color: Color(0xFF2060c0)),
    'selector-id': TextStyle(color: Color(0xFF2060c0)),
    'selector-class': TextStyle(color: Color(0xFF2060c0)),
    'regexp': TextStyle(color: Color(0xFF208050)),
    'symbol': TextStyle(color: Color(0xFF208050)),
    'number': TextStyle(color: Color(0xFFc07000)), // Fallback or distinct
    'link': TextStyle(color: Color(0xFF2060c0)),
    'attr': TextStyle(color: Color(0xFF1a1a2e)),
    'built_in': TextStyle(color: Color(0xFF2060c0)),
    'type': TextStyle(color: Color(0xFF00a080)),
    'params': TextStyle(color: Color(0xFF1a1a2e)),
    'meta': TextStyle(color: Color(0xFF3a3a52)),
    'title': TextStyle(color: Color(0xFF2060c0), fontWeight: FontWeight.bold),
    'section': TextStyle(color: Color(0xFF2060c0), fontWeight: FontWeight.bold),
  };

  static const Map<String, TextStyle> showcaseDarkTheme = {
    'root': TextStyle(backgroundColor: _darkCodeBg, color: _darkTextBody),
    'keyword': TextStyle(color: Color(0xFFb86bff)),
    'function': TextStyle(color: Color(0xFF6bb8ff)),
    'string': TextStyle(color: Color(0xFF6bffb8)),
    'comment': TextStyle(color: Color(0xFF606080), fontStyle: FontStyle.italic),
    'quote': TextStyle(color: Color(0xFF606080)),
    'doctag': TextStyle(color: Color(0xFF606080)),
    'variable': TextStyle(color: Color(0xFFe0e0f0)),
    'template-variable': TextStyle(color: Color(0xFFe0e0f0)),
    'tag': TextStyle(color: Color(0xFFb86bff)),
    'name': TextStyle(color: Color(0xFF6bb8ff)),
    'selector-id': TextStyle(color: Color(0xFF6bb8ff)),
    'selector-class': TextStyle(color: Color(0xFF6bb8ff)),
    'regexp': TextStyle(color: Color(0xFF6bffb8)),
    'symbol': TextStyle(color: Color(0xFF6bffb8)),
    'number': TextStyle(color: Color(0xFFffb86b)), // Fallback
    'link': TextStyle(color: Color(0xFF6bb8ff)),
    'attr': TextStyle(color: Color(0xFFe0e0f0)),
    'built_in': TextStyle(color: Color(0xFF6bb8ff)),
    'type': TextStyle(color: Color(0xFF00d4aa)),
    'params': TextStyle(color: Color(0xFFe0e0f0)),
    'meta': TextStyle(color: Color(0xFFc8c8e0)),
    'title': TextStyle(color: Color(0xFF6bb8ff), fontWeight: FontWeight.bold),
    'section': TextStyle(color: Color(0xFF6bb8ff), fontWeight: FontWeight.bold),
  };
}

class SirenColors extends ThemeExtension<SirenColors> {
  final Color? sidebarBg;
  final Color? codeBg;
  final Color? headingColor;
  final Color? quoteBorder;
  final Color? divider;
  // Restored fields for compatibility
  final Color? tabBg;
  final Color? activeTabBg;
  final Color? borderColor;
  final Color? iconColor;

  const SirenColors({
    required this.sidebarBg,
    required this.codeBg,
    required this.headingColor,
    required this.quoteBorder,
    required this.divider,
    required this.tabBg,
    required this.activeTabBg,
    required this.borderColor,
    required this.iconColor,
  });

  @override
  SirenColors copyWith({
    Color? sidebarBg,
    Color? codeBg,
    Color? headingColor,
    Color? quoteBorder,
    Color? divider,
    Color? tabBg,
    Color? activeTabBg,
    Color? borderColor,
    Color? iconColor,
  }) {
    return SirenColors(
      sidebarBg: sidebarBg ?? this.sidebarBg,
      codeBg: codeBg ?? this.codeBg,
      headingColor: headingColor ?? this.headingColor,
      quoteBorder: quoteBorder ?? this.quoteBorder,
      divider: divider ?? this.divider,
      tabBg: tabBg ?? this.tabBg,
      activeTabBg: activeTabBg ?? this.activeTabBg,
      borderColor: borderColor ?? this.borderColor,
      iconColor: iconColor ?? this.iconColor,
    );
  }

  @override
  SirenColors lerp(ThemeExtension<SirenColors>? other, double t) {
    if (other is! SirenColors) {
      return this;
    }
    return SirenColors(
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t),
      codeBg: Color.lerp(codeBg, other.codeBg, t),
      headingColor: Color.lerp(headingColor, other.headingColor, t),
      quoteBorder: Color.lerp(quoteBorder, other.quoteBorder, t),
      divider: Color.lerp(divider, other.divider, t),
      tabBg: Color.lerp(tabBg, other.tabBg, t),
      activeTabBg: Color.lerp(activeTabBg, other.activeTabBg, t),
      borderColor: Color.lerp(borderColor, other.borderColor, t),
      iconColor: Color.lerp(iconColor, other.iconColor, t),
    );
  }
}
