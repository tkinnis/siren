import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

void main() {
  testWidgets('Markdown styling test for strong text', (
    WidgetTester tester,
  ) async {
    const markdownData = '**Date:** 2026-01-14';

    await tester.pumpWidget(
      MaterialApp(
        theme: SirenTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final fontSize = 14.0;

              return MarkdownBody(
                data: markdownData,
                extensionSet: md.ExtensionSet(
                  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                  [
                    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                    AnchorSyntax(),
                  ],
                ),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: GoogleFonts.inter(
                    fontSize: fontSize,
                    height: 1.6,
                    color: theme.colorScheme.onSurface,
                  ),
                  strong: GoogleFonts.inter(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  em: GoogleFonts.inter(
                    fontSize: fontSize,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface,
                  ),
                  del: GoogleFonts.inter(
                    fontSize: fontSize,
                    decoration: TextDecoration.lineThrough,
                    color: theme.colorScheme.onSurface,
                  ),
                  a: GoogleFonts.inter(
                    fontSize: fontSize,
                    color: theme
                        .colorScheme
                        .primary, // using theme primary for test simplicity
                    decoration: TextDecoration.underline,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Find the RichText
    final richTextFinder = find.byType(RichText);
    expect(richTextFinder, findsOneWidget);

    final richText = tester.widget<RichText>(richTextFinder);
    final textSpan = richText.text as TextSpan;

    // Debug print structure using debugPrint or stdio
    debugPrint('Root Span Style: ${textSpan.style}');
    printSpan(textSpan);

    // Verify 'Date:' is bold
    bool foundBold = false;
    textSpan.visitChildren((span) {
      if (span is TextSpan) {
        if (span.text == 'Date:' &&
            (span.style?.fontWeight == FontWeight.bold ||
                span.style?.fontWeight == FontWeight.w700)) {
          foundBold = true;
        }
      }
      return true;
    });

    expect(foundBold, isTrue, reason: '"Date:" should be bold');
  });
}

void printSpan(TextSpan span, [int depth = 0]) {
  final indent = '  ' * depth;
  debugPrint('${indent}Text: "${span.text}", Style: ${span.style}');
  if (span.children != null) {
    for (var child in span.children!) {
      if (child is TextSpan) {
        printSpan(child, depth + 1);
      }
    }
  }
}
