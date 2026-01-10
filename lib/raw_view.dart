import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';

class MarkdownRawView extends StatelessWidget {
  const MarkdownRawView({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final content = appState.currentContent;
    final fontSize = appState.fontSize;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    // Extract background color from theme or fallback
    final backgroundColor = theme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA));

    return Container(
      color: backgroundColor,
      constraints: const BoxConstraints.expand(),
      child: SingleChildScrollView(
        child: HighlightView(
          content,
          language: 'markdown',
          theme: theme,
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          textStyle: GoogleFonts.firaCode(fontSize: fontSize),
        ),
      ),
    );
  }
}