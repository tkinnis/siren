import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SirenTheme {
  // Light Theme Colors
  static const Color _lightBg = Color(0xFFf8f8fc); // ui.editor.background
  static const Color _lightSurface = Color(0xFFf0f0f6); // ui.sidebar.background
  static const Color _lightSurfaceHighlight = Color(0xFFe8e8f0); // ui.activityBar.background
  static const Color _lightSurfaceVariant = Color(0xFFe0e0ec);
  static const Color _lightPrimary = Color(0xFF00a080);
  static const Color _lightOnSurface = Color(0xFF1a1a2e);
  static const Color _lightOnSurfaceVariant = Color(0xFF3a3a52);
  static const Color _lightBorder = Color(0xFFd0d0e0);
  
  static const Color _lightTabActiveBg = Color(0xFFf8f8fc);
  static const Color _lightTabInactiveBg = Color(0xFFf0f0f6);
  static const Color _lightIconColor = Color(0xFF1a1a2e); // ui.activityBar.foreground

  // Showcase Theme - Dark
  static const Color _darkBg = Color(0xFF1a1a2e); // ui.editor.background
  static const Color _darkSurface = Color(0xFF141428); // ui.sidebar.background
  static const Color _darkSurfaceHighlight = Color(0xFF0f0f1a); // ui.activityBar.background
  static const Color _darkSurfaceVariant = Color(0xFF2d2d4a);
  static const Color _darkPrimary = Color(0xFF00d4aa);
  static const Color _darkOnSurface = Color(0xFFe0e0f0);
  static const Color _darkOnSurfaceVariant = Color(0xFFc8c8e0);
  static const Color _darkBorder = Color(0xFF3d3d5c);

  static const Color _darkTabActiveBg = Color(0xFF1a1a2e);
  static const Color _darkTabInactiveBg = Color(0xFF141428);
  static const Color _darkIconColor = Color(0xFFe0e0f0); // ui.activityBar.foreground


  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _lightBg,
      colorScheme: base.colorScheme.copyWith(
        primary: _lightPrimary,
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        onSurfaceVariant: _lightOnSurfaceVariant,
        outline: _lightBorder,
        surfaceContainer: _lightSurfaceHighlight,
        surfaceContainerHighest: _lightSurfaceVariant,
      ),
      dividerTheme: const DividerThemeData(
        color: _lightBorder,
        thickness: 1,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: _lightOnSurface,
        displayColor: _lightOnSurface,
      ),
      iconTheme: const IconThemeData(
        color: _lightIconColor,
        size: 20,
      ),
      extensions: [
        const SirenColors(
          sidebarBg: _lightSurface,
          tabBg: _lightTabInactiveBg,
          activeTabBg: _lightTabActiveBg,
          borderColor: _lightBorder,
          iconColor: _lightIconColor,
        ),
      ],
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _darkBg,
      colorScheme: base.colorScheme.copyWith(
        primary: _darkPrimary,
        surface: _darkSurface,
        onSurface: _darkOnSurface,
        onSurfaceVariant: _darkOnSurfaceVariant,
        outline: _darkBorder,
        surfaceContainer: _darkSurfaceHighlight,
        surfaceContainerHighest: _darkSurfaceVariant,
      ),
      dividerTheme: const DividerThemeData(
        color: _darkBorder,
        thickness: 1,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: _darkOnSurface,
        displayColor: _darkOnSurface,
      ),
      iconTheme: const IconThemeData(
        color: _darkIconColor,
        size: 20,
      ),
      extensions: [
        const SirenColors(
          sidebarBg: _darkSurface,
          tabBg: _darkTabInactiveBg,
          activeTabBg: _darkTabActiveBg,
          borderColor: _darkBorder,
          iconColor: _darkIconColor,
        ),
      ],
    );
  }

  static const Map<String, TextStyle> showcaseLightTheme = {
    'root': TextStyle(backgroundColor: _lightBg, color: _lightOnSurface),
    'comment': TextStyle(color: Color(0xFF8a8aa2)),
    'quote': TextStyle(color: Color(0xFF8a8aa2)),
    'variable': TextStyle(color: Color(0xFF1a1a2e)),
    'keyword': TextStyle(color: Color(0xFF8040a0)),
    'selector-tag': TextStyle(color: Color(0xFF8040a0)),
    'built_in': TextStyle(color: Color(0xFF2060c0)),
    'name': TextStyle(color: Color(0xFF2060c0)), // function/method
    'string': TextStyle(color: Color(0xFF208050)),
    'number': TextStyle(color: Color(0xFFc07000)),
    'attribute': TextStyle(color: Color(0xFF1a1a2e)),
    'meta': TextStyle(color: Color(0xFFa09000)), // annotation
    'link': TextStyle(color: Color(0xFF2060c0)),
    'doctag': TextStyle(color: Color(0xFFa09000)),
    'type': TextStyle(color: Color(0xFFa09000)),
    'symbol': TextStyle(color: Color(0xFF2060c0)),
    'bullet': TextStyle(color: Color(0xFF208050)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
  };

  static const Map<String, TextStyle> showcaseDarkTheme = {
    'root': TextStyle(backgroundColor: _darkBg, color: _darkOnSurface),
    'comment': TextStyle(color: Color(0xFF606080)),
    'quote': TextStyle(color: Color(0xFF606080)),
    'variable': TextStyle(color: Color(0xFFe0e0f0)),
    'keyword': TextStyle(color: Color(0xFFb86bff)),
    'selector-tag': TextStyle(color: Color(0xFFb86bff)),
    'built_in': TextStyle(color: Color(0xFF6bb8ff)),
    'name': TextStyle(color: Color(0xFF6bb8ff)),
    'string': TextStyle(color: Color(0xFF6bffb8)),
    'number': TextStyle(color: Color(0xFFffb86b)),
    'attribute': TextStyle(color: Color(0xFFe0e0f0)),
    'meta': TextStyle(color: Color(0xFFffd86b)),
    'link': TextStyle(color: Color(0xFF6bb8ff)),
    'doctag': TextStyle(color: Color(0xFFffd86b)),
    'type': TextStyle(color: Color(0xFFffd86b)),
    'symbol': TextStyle(color: Color(0xFF6bb8ff)),
    'bullet': TextStyle(color: Color(0xFF6bffb8)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
  };
}

@immutable
class SirenColors extends ThemeExtension<SirenColors> {
  final Color? sidebarBg;
  final Color? tabBg;
  final Color? activeTabBg;
  final Color? borderColor;
  final Color? iconColor;

  const SirenColors({
    required this.sidebarBg,
    required this.tabBg,
    required this.activeTabBg,
    required this.borderColor,
    required this.iconColor,
  });

  @override
  SirenColors copyWith({
    Color? sidebarBg,
    Color? tabBg,
    Color? activeTabBg,
    Color? borderColor,
    Color? iconColor,
  }) {
    return SirenColors(
      sidebarBg: sidebarBg ?? this.sidebarBg,
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
      tabBg: Color.lerp(tabBg, other.tabBg, t),
      activeTabBg: Color.lerp(activeTabBg, other.activeTabBg, t),
      borderColor: Color.lerp(borderColor, other.borderColor, t),
      iconColor: Color.lerp(iconColor, other.iconColor, t),
    );
  }
}