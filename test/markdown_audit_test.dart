import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/image_zoom_dialog.dart';
import 'package:siren/outline_view.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';
import 'package:vector_graphics/vector_graphics_compat.dart';

TapGestureRecognizer? _findTapRecognizer(
  InlineSpan span,
  String targetText, [
  TapGestureRecognizer? inheritedRecognizer,
]) {
  TapGestureRecognizer? currentRecognizer = inheritedRecognizer;
  if (span is TextSpan) {
    if (span.recognizer is TapGestureRecognizer) {
      currentRecognizer = span.recognizer as TapGestureRecognizer;
    }
    if (span.text != null && span.text!.contains(targetText)) {
      return currentRecognizer;
    }
    if (span.children != null) {
      for (final child in span.children!) {
        final rec = _findTapRecognizer(child, targetText, currentRecognizer);
        if (rec != null) return rec;
      }
    }
  }
  return null;
}

class TestAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  bool showFrontmatter = true;

  @override
  String? currentFilePath = 'test.md';

  @override
  String? explorerRootPath;

  String? lastOpenedFile;
  final List<({int lineNumber, String text})> recordedScrollCalls = [];

  @override
  void setShowFrontmatter(bool show) {
    showFrontmatter = show;
    notifyListeners();
  }

  final StreamController<({int lineNumber, String text})> _navController =
      StreamController.broadcast();

  @override
  Stream<({int lineNumber, String text})> get navigationStream =>
      _navController.stream;

  @override
  void scrollTo(int lineNumber, String text) {
    final target = (lineNumber: lineNumber, text: text);
    recordedScrollCalls.add(target);
    _navController.add(target);
  }

  @override
  Future<void> openFile(String filePath, {bool inNewTab = true}) async {
    lastOpenedFile = filePath;
    notifyListeners();
  }

  @override
  double getScrollOffset(String path) => 0.0;

  @override
  void setScrollOffset(String path, double offset) {}

  @override
  String getFileContent(String path) => currentContent;

  @override
  void setContent(String content) {
    currentContent = content;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    MarkdownBuiltInRenderers.clearCaches();
  });

  group('RenderedView Feature & Extension Integration', () {
    testWidgets(
      'renders Alerts, LaTeX math, Mermaid diagrams, syntax highlighting, tables, HTML, and theme switching',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        final copiedTexts = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<dynamic, dynamic>;
                copiedTexts.add(args['text'] as String);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        const markdownData = '''# Siren Markdown Feature Verification

> [!NOTE]
> This is a **Note** alert.

> [!TIP]
> This is a **Tip** alert.

> [!IMPORTANT]
> This is an **Important** alert.

> [!WARNING]
> This is a **Warning** alert.

> [!CAUTION]
> This is a **Caution** alert.

Inline math: \$E = mc^2\$.

\$\$
\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}
\$\$

```mermaid
flowchart LR
  A[Input] --> B[Output]
```

To emphasize specific text, use ==highlighting==, H~2~O, and mc^2^.

```dart
void main() {
  print('Hello, Siren!');
}
```

| Name | Role | Location |
| :--- | :---: | ---: |
| Alice | Dev | NY |

Press <kbd>Cmd</kbd> + <kbd>P</kbd> with <abbr title="GitHub Flavored Markdown">GFM</abbr>.

<details>
  <summary>Expandable Section</summary>

  Revealed details body content.
</details>

<dl>
  <dt>Ripgrep</dt>
  <dd>Fast workspace search engine</dd>
</dl>
''';

        final appState = TestAppState()..currentContent = markdownData;

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

        expect(tester.takeException(), isNull);

        expect(
          find.textContaining('Siren Markdown Feature Verification'),
          findsWidgets,
        );
        expect(find.text('Note'), findsAtLeastNWidgets(1));
        expect(find.text('Tip'), findsAtLeastNWidgets(1));
        expect(find.text('Important'), findsAtLeastNWidgets(1));
        expect(find.text('Warning'), findsAtLeastNWidgets(1));
        expect(find.text('Caution'), findsAtLeastNWidgets(1));

        // LaTeX + Mermaid coexistence
        expect(
          find.byWidgetPredicate((w) => w.runtimeType.toString() == 'TexMath'),
          findsNWidgets(2),
        );
        expect(
          MarkdownBuiltInRenderers.mathLayoutCount,
          greaterThanOrEqualTo(2),
        );
        expect(find.byType(VectorGraphic), findsOneWidget);

        // Highlighting, syntax-highlighted code block & Copy button
        expect(find.textContaining('highlighting'), findsOneWidget);
        expect(find.byType(HighlightView), findsOneWidget);
        expect(find.text('DART'), findsOneWidget);
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(copiedTexts, <String>[
          "void main() {\n  print('Hello, Siren!');\n}",
        ]);

        // Table & embedded HTML (<kbd>, <abbr>, <details>, <dl>)
        expect(find.textContaining('Alice'), findsOneWidget);

        final scrollableFinder = find
            .descendant(
              of: find.byType(RenderedView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Cmd'),
          250.0,
          scrollable: scrollableFinder,
        );
        await tester.pumpAndSettle();

        expect(find.text('Cmd'), findsOneWidget);
        expect(find.text('GFM'), findsOneWidget);
        expect(find.text('Expandable Section'), findsOneWidget);
        expect(
          find.textContaining('Revealed details body content.'),
          findsNothing,
        );
        await tester.tap(find.text('Expandable Section'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Revealed details body content.'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.textContaining('Fast workspace search engine'),
          200.0,
          scrollable: scrollableFinder,
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Fast workspace search engine'),
          findsOneWidget,
        );

        // Switch to Dark theme cleanly
        tester.state<ScrollableState>(scrollableFinder).position.jumpTo(0.0);
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.dark,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(body: RenderedView(filePath: 'test.md')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(VectorGraphic), findsOneWidget);
      },
    );

    testWidgets(
      'supports YAML frontmatter toggle, GFM footnotes, and #anchor scrolling',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final filler = List<String>.generate(
          25,
          (i) => 'Paragraph $i with filler text for scroll testing.',
        ).join('\n\n');

        final markdownData =
            '''---
title: Architecture Spec
author: Siren Team
tags: [flutter, markdown]
---

# Overview

Jump to [Target Section](#target-section) or read footnote[^1].

$filler

## Target Section

Reached target section!

[^1]: Footnote explanation text.
''';

        final appState = TestAppState()..currentContent = markdownData;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(body: RenderedView(filePath: 'spec.md')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Frontmatter'), findsOneWidget);
        expect(find.textContaining('Architecture Spec'), findsOneWidget);
        expect(find.textContaining('flutter'), findsWidgets);
        expect(find.textContaining('markdown'), findsWidgets);
        expect(find.textContaining('[1]'), findsWidgets);

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(RenderedView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.pixels, equals(0.0));

        // Trigger #target-section link
        final linkFinder = find.textContaining(
          'Target Section',
          findRichText: true,
        );
        final linkRichText = tester.widget<RichText>(linkFinder.first);
        final recognizer = _findTapRecognizer(
          linkRichText.text,
          'Target Section',
        );
        expect(recognizer, isNotNull);
        recognizer!.onTap?.call();
        await tester.pumpAndSettle();

        expect(scrollable.position.pixels, greaterThan(0.0));

        // Toggling showFrontmatter off hides the frontmatter card
        appState.setShowFrontmatter(false);
        await tester.pumpAndSettle();
        expect(find.textContaining('Architecture Spec'), findsNothing);
      },
    );
  });

  group('Local Link Navigation', () {
    testWidgets(
      'relative links including inline code open local files and fallback to explorerRootPath',
      (WidgetTester tester) async {
        final tempDir = Directory.systemTemp.createTempSync('siren_link_test_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final targetFile = File(p.join(tempDir.path, 'docs', 'architecture.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# Architecture Documentation');
        final sourceInRoot = p.join(tempDir.path, 'README.md');
        final sourceInSubfolder = File(
          p.join(tempDir.path, 'guides', 'intro.md'),
        )..createSync(recursive: true);

        const markdownData =
            '- [`docs/architecture.md`](docs/architecture.md) — system overview';

        final appState = TestAppState()..currentContent = markdownData;

        // 1. Relative to document directory
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(body: RenderedView(filePath: sourceInRoot)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final linkFinder = find.textContaining(
          'docs/architecture.md',
          findRichText: true,
        );
        expect(linkFinder, findsOneWidget);
        final recognizer = _findTapRecognizer(
          tester.widget<RichText>(linkFinder).text,
          'docs/architecture.md',
        );
        expect(recognizer, isNotNull);
        recognizer!.onTap?.call();
        await tester.pumpAndSettle();
        expect(appState.lastOpenedFile, equals(targetFile.path));

        // 2. Fallback to explorerRootPath from nested guides/intro.md
        appState
          ..lastOpenedFile = null
          ..explorerRootPath = tempDir.path;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(
                body: RenderedView(filePath: sourceInSubfolder.path),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final nestedLinkFinder = find.textContaining(
          'docs/architecture.md',
          findRichText: true,
        );
        final nestedRecognizer = _findTapRecognizer(
          tester.widget<RichText>(nestedLinkFinder).text,
          'docs/architecture.md',
        );
        expect(nestedRecognizer, isNotNull);
        nestedRecognizer!.onTap?.call();
        await tester.pumpAndSettle();
        expect(appState.lastOpenedFile, equals(targetFile.path));
      },
    );
  });

  group('SirenImageBuilder, Relative Images, SVGs & ImageZoomDialog', () {
    testWidgets(
      'resolves local raster images, enforces link-vs-lightbox rule, handles local SVGs, and switches <picture> dark/light',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tempDir = Directory.systemTemp.createTempSync('siren_img_test_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final linkedTarget = File(p.join(tempDir.path, 'docs', 'target.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# Target');
        final pngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        );
        final localPng = File(p.join(tempDir.path, 'sample.png'))
          ..writeAsBytesSync(pngBytes);
        final localSvg = File(p.join(tempDir.path, 'badge.svg'))
          ..writeAsStringSync(
            '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20"><rect width="40" height="20" fill="#00a080"/></svg>',
          );

        const markdownData = '''
<img src="sample.png" alt="Plain Local" width="48" height="48" />

<p><a href="docs/target.md"><img src="sample.png" alt="Linked Local" width="48" height="48" /></a></p>

[![Linked Markdown](sample.png)](docs/target.md)

![Local Vector](badge.svg)

![Missing Image](missing_image.png)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://docs.flutter.dev/logo_dark.png">
  <img alt="Flutter" src="https://docs.flutter.dev/logo.png">
</picture>
''';

        final appState = TestAppState()
          ..currentContent = markdownData
          ..explorerRootPath = tempDir.path;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(
                body: RenderedView(filePath: p.join(tempDir.path, 'README.md')),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        expect(localPng.existsSync(), isTrue);
        expect(localSvg.existsSync(), isTrue);
        expect(find.byType(Image), findsNWidgets(3));
        expect(find.byType(SvgPicture), findsOneWidget);
        expect(find.text('Missing Image'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>(
              'network_image_https://docs.flutter.dev/logo.png',
            ),
          ),
          findsOneWidget,
        );

        // 1. Tapping SVG does NOT open ImageZoomDialog
        await tester.tap(find.byType(SvgPicture));
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsNothing);

        // 2. Tapping linked HTML raster image navigates link instead of opening lightbox
        await tester.tap(find.byType(Image).at(1));
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsNothing);
        expect(appState.lastOpenedFile, equals(linkedTarget.path));

        // 3. Tapping linked Markdown raster image navigates link instead of opening lightbox
        appState.lastOpenedFile = null;
        await tester.tap(
          find
              .ancestor(
                of: find.byType(Image).at(2),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsNothing);
        expect(appState.lastOpenedFile, equals(linkedTarget.path));

        // 4. Tapping unlinked local raster image opens ImageZoomDialog
        await tester.tap(find.byType(Image).at(0));
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_close_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsNothing);

        // 5. Switching to Dark theme selects <picture> dark source
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.dark,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(
                body: RenderedView(filePath: p.join(tempDir.path, 'README.md')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey<String>(
              'network_image_https://docs.flutter.dev/logo_dark.png',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'resolves ../assets/images/app_icon.png and repo-root assets/images/app_icon.png from docs/ subfolder',
      (WidgetTester tester) async {
        const markdownData = '''<p align="center">
  <img src="../assets/images/app_icon.png" alt="Siren Logo" width="72" height="72" />
</p>

<p align="center">
  <img src="assets/images/app_icon.png" alt="Siren Root Logo" width="72" height="72" />
</p>''';

        final docsDir = p.join(Directory.current.path, 'docs');
        final docFile = p.join(docsDir, 'markdown-guide.md');
        final appState = TestAppState()
          ..currentContent = markdownData
          ..explorerRootPath = docsDir;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(body: RenderedView(filePath: docFile)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsNWidgets(2));
      },
    );

    testWidgets(
      'ImageZoomDialog supports zoom in, zoom out, reset, and close',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final pngBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ImageZoomDialog.show(
                    context,
                    imageProvider: MemoryImage(pngBytes),
                    title: 'sample.png',
                  ),
                  child: const Text('Open Image'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Image'));
        await tester.pumpAndSettle();

        expect(find.text('sample.png'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_in_button')));
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_out_button')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_in_button')));
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_reset_pill')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('image_zoom_close_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ImageZoomDialog), findsNothing);
      },
    );
  });

  group('OutlineView & RenderedView Navigation Integration', () {
    testWidgets(
      'OutlineView extracts MarkdownEngine outline and navigates RenderedView to deduplicated heading slugs',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final filler = List<String>.generate(
          25,
          (i) => 'Filler paragraph $i between sections.',
        ).join('\n\n');

        final markdownData =
            '''---
title: Guide
# Comment inside frontmatter
---

# Overview

```bash
# Comment inside fenced code
```

$filler

## Overview

Second overview section.
''';

        final appState = TestAppState()..currentContent = markdownData;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(
                body: Row(
                  children: [
                    SizedBox(width: 240, child: OutlineView()),
                    Expanded(child: RenderedView(filePath: 'guide.md')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(OutlineView),
            matching: find.text('Comment inside frontmatter'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(OutlineView),
            matching: find.text('Comment inside fenced code'),
          ),
          findsNothing,
        );
        final outlineItemsFinder = find.descendant(
          of: find.byType(OutlineView),
          matching: find.text('Overview'),
        );
        expect(outlineItemsFinder, findsNWidgets(2));

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(RenderedView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.pixels, equals(0.0));

        // Tap the second 'Overview' item in OutlineView (deduplicated slug 'overview-1')
        await tester.tap(outlineItemsFinder.last);
        await tester.pumpAndSettle();

        expect(appState.recordedScrollCalls, isNotEmpty);
        expect(appState.recordedScrollCalls.last.text, equals('overview-1'));
        expect(appState.recordedScrollCalls.last.lineNumber, greaterThan(0));
        expect(scrollable.position.pixels, greaterThan(0.0));
      },
    );
  });
}
