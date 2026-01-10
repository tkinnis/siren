import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:markdown/markdown.dart' as md;
import 'app_state.dart';
import 'mermaid_diagram.dart';

class RenderedView extends StatelessWidget {
  const RenderedView({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final content = appState.currentContent;
    final fontSize = appState.fontSize;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: GoogleFonts.roboto(fontSize: fontSize),
          h1: GoogleFonts.roboto(
            fontSize: fontSize * 2.0,
            fontWeight: FontWeight.bold,
          ),
          h2: GoogleFonts.roboto(
            fontSize: fontSize * 1.75,
            fontWeight: FontWeight.bold,
          ),
          h3: GoogleFonts.roboto(
            fontSize: fontSize * 1.5,
            fontWeight: FontWeight.bold,
          ),
          h4: GoogleFonts.roboto(
            fontSize: fontSize * 1.25,
            fontWeight: FontWeight.bold,
          ),
          h5: GoogleFonts.roboto(
            fontSize: fontSize * 1.15,
            fontWeight: FontWeight.bold,
          ),
          h6: GoogleFonts.roboto(
            fontSize: fontSize * 1.0,
            fontWeight: FontWeight.bold,
          ),
          code: GoogleFonts.firaCode(
            backgroundColor: isDark
                ? const Color(0xFF282C34)
                : const Color(0xFFF0F0F0),
            fontSize: fontSize * 0.9,
          ),
        ),
        builders: {
          'code': CodeElementBuilder(isDark: isDark, fontSize: fontSize),
        },
      ),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final double fontSize;

  CodeElementBuilder({required this.isDark, required this.fontSize});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      String lg = element.attributes['class']!;
      if (lg.startsWith('language-')) {
        language = lg.substring(9);
      } else {
        language = lg;
      }
    }

    if (language == 'mermaid') {
      return MermaidDiagram(code: element.textContent, isDark: isDark);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: HighlightView(
        element.textContent,
        language: language,
        theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
        padding: const EdgeInsets.all(8),
        textStyle: GoogleFonts.firaCode(fontSize: fontSize),
      ),
    );
  }
}
