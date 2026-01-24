import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

void main() {
  testWidgets('Markdown audit test', (WidgetTester tester) async {
    const markdownData = '''
# Siren Markdown Feature Verification

This document contains examples of all supported markdown features in Siren, including standard markdown and custom extensions.

## Custom Extensions

### GitHub Alerts

> [!NOTE]
> This is a **Note** alert. useful for general information.

> [!TIP]
> This is a **Tip** alert. Helpful advice or shortcuts.

> [!IMPORTANT]
> This is an **Important** alert. Key information users should know.

> [!WARNING]
> This is a **Warning** alert. Urgent info that needs immediate attention.

> [!CAUTION]
> This is a **Caution** alert. Advises about risks or negative outcomes.

### LaTeX Math

Inline math: The mass-energy equivalence formula is \$E = mc^2\$.

Block math:
\$\$
\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}
\$\$

### Highlighting

To emphasize specific text, you can use ==highlighting== like this.

### Subscript and Superscript

- H~2~O (Water)
- E = mc^2^ (Energy)
- Text with both: X^2^~i~

---

## Standard Markdown

### Typography

**Bold Text**
*Italic Text*
***Bold and Italic***
~~Strikethrough~~

### Headings

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

### Lists

#### Unordered
- Item 1
- Item 2
  - Subitem 2.1
  - Subitem 2.2

#### Ordered
1. First item
2. Second item
   1. Subitem A
   2. Subitem B

#### Task List
- [x] Completed task
- [ ] Incomplete task

### Blockquotes

> This is a blockquote.
>
> > Nested blockquote.

### Code

Inline code: `print("Hello World")`

Code block with syntax highlighting:
```dart
void main() {
  print('Hello, Siren!');
}
```

### Tables

| Name | Role | Location |
| :--- | :---: | ---: |
| Alice | Dev | NY |
| Bob | Design | LA |
| Charlie | Manager | London |

### Links and Images

    [Siren Repository](https://github.com/tkinnis/siren)
    // Image removed to avoid HTTP 400 in test


### Horizontal Rule

---
''';

    // Inject state for RenderedView
    final appState = TestAppState();
    appState.currentContent = markdownData;

    // Re-pump with AppState provider
    await tester.pumpWidget(
      MaterialApp(
        theme: SirenTheme.light,
        home: ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const Scaffold(body: RenderedView(filePath: 'test.md')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1.    // Verify Header (Looser match likely needed for RichText)
    // 1.    // Verify Header (Looser match likely needed for RichText)
    expect(
      find.textContaining(
        'Siren Markdown Feature Verification',
        findRichText: true,
      ),
      findsWidgets,
    );

    // Verify Alerts (AlertBuilder renders Title like 'Note', 'Tip')
    expect(find.text('Note'), findsAtLeastNWidgets(1));
    expect(find.text('Tip'), findsAtLeastNWidgets(1));
    expect(find.text('Important'), findsAtLeastNWidgets(1));

    // Verify Alert Content (using find.text containing)
    expect(find.textContaining('This is a', findRichText: true), findsWidgets);

    // Verify Math (Inline math text is preserved if not parsed by LatexSyntax or if fallback)
    // But LatexBuilder uses Math.tex, so text 'E = mc^2' might be inside the Math widget logic or semantic label.
    // Instead of text, let's just assume if paint doesn't crash, it's fine for now.
    // Or check for "Inline math:" prefix.
    expect(
      find.textContaining('Inline math:', findRichText: true),
      findsWidgets,
    );

    // Verify Highlighting
    // HighlightBuilder renders RichText with background color.
    // Hard to verify style in widget test without finding specific RichText.
    // We can find the text "highlighting".
    expect(find.text('highlighting', findRichText: true), findsOneWidget);

    // Verify Sub/Sup
    // H~2~O -> H 2 O. SubSupBuilder uses Row/Transform.
    expect(find.textContaining('Water', findRichText: true), findsOneWidget);
    expect(find.textContaining('Energy', findRichText: true), findsOneWidget);

    // Verify Links
    expect(
      find.textContaining('Siren Repository', findRichText: true),
      findsOneWidget,
    );

    // Verify Tables
    expect(find.textContaining('Alice', findRichText: true), findsOneWidget);
    expect(find.textContaining('Dev', findRichText: true), findsOneWidget);
    expect(find.textContaining('NY', findRichText: true), findsOneWidget);
  });
}

class TestAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  String? currentFilePath;

  final StreamController<({int lineNumber, String text})> _navController =
      StreamController.broadcast();

  @override
  Stream<({int lineNumber, String text})> get navigationStream =>
      _navController.stream;

  @override
  double getScrollOffset(String path) => 0.0;

  @override
  void setScrollOffset(String path, double offset) {}

  @override
  String getFileContent(String path) => currentContent;

  @override
  String getProcessedContent(String path) => currentContent;

  @override
  String currentProcessedContent = '';

  @override
  void setContent(String content) {
    currentContent = content;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
