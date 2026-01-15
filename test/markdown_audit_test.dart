import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

void main() {
  testWidgets('Markdown audit test', (WidgetTester tester) async {
    const markdownData = '''
# Heading 1
- List item 1
- List item 2

1. Ordered 1
2. Ordered 2

---

- [ ] Task incomplete
- [x] Task complete

> [!NOTE]
> This is an alert.

| Header 1 | Header 2 |
| --- | --- |
| Cell 1 | Cell 2 |
''';

    await tester.pumpWidget(
      MaterialApp(
        theme: SirenTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final sirenColors = theme.extension<SirenColors>()!;
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
                    color: theme.colorScheme.onSurface,
                  ),
                  h1: GoogleFonts.inter(fontSize: fontSize * 2.25),
                  // ... (abbreviated for audit)
                  strong: GoogleFonts.inter(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // 1. Check List Bullets
    // Flutter Markdown renders bullets as text bullets usually.
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    bool foundBullet = false;
    for (var rt in richTexts) {
      if (rt.text.toPlainText().contains('•')) {
        foundBullet = true;
        debugPrint('Found bullet: ${rt.text.toPlainText()}');
        // Check style of bullet?
      }
    }
    debugPrint('Found Bullet: $foundBullet');

    // 2. Check Horizontal Rule
    // Rendered as Container with decoration? Or specialized widget?
    // Usually a Container or Divider.
    final containers = find.byType(Container);
    // Hard to pin point exact one without specific checks, but we can see if it parses.

    // 3. GitHub Alerts
    // Expectation: It parses as a Blockquote starting with "[!NOTE]".
    // It does NOT render as a special Alert widget unless we have a builder.
    final blockQuotes = find.textContaining('[!NOTE]');
    if (blockQuotes.evaluate().isNotEmpty) {
      debugPrint(
        'GitHub Alert rendered as plain text inside blockquote (Expected behavior for unsupported).',
      );
    } else {
      debugPrint('GitHub Alert text not found?');
    }

    // 4. Task List
    final checkboxes = find.byType(Checkbox);
    debugPrint('Checkboxes found: ${checkboxes.evaluate().length}');
  });
}
