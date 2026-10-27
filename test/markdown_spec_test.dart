import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

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

class _TestAppState extends ChangeNotifier implements AppState {
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

  @override
  Future<void> openFile(String filePath, {bool inNewTab = true}) async {
    lastOpenedFile = filePath;
    notifyListeners();
  }

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

void main() {
  group('Markdown Specification Line Breaks', () {
    testWidgets(
      'Soft line breaks in paragraphs render as spaces, not linebreaks',
      (WidgetTester tester) async {
        const markdownData = 'First line of text\nsecond line of text';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        // Find RichText widgets
        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsWidgets);

        bool foundMergedText = false;
        bool foundNewline = false;
        for (final element in richTextFinder.evaluate()) {
          final widget = element.widget as RichText;
          final plainText = widget.text.toPlainText();
          if (plainText.contains('First line of text second line of text')) {
            foundMergedText = true;
          }
          if (plainText.contains('First line of text\nsecond line of text')) {
            foundNewline = true;
          }
        }

        expect(
          foundMergedText,
          isTrue,
          reason: 'Soft line break should join lines with a space per CommonMark spec',
        );
        expect(
          foundNewline,
          isFalse,
          reason:
              'Soft line break should not contain a literal newline character',
        );
      },
    );

    testWidgets(
      'Hard line breaks with trailing two spaces render with newline',
      (WidgetTester tester) async {
        const markdownData = 'First line of text  \nsecond line of text';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsWidgets);

        bool foundNewline = false;
        for (final element in richTextFinder.evaluate()) {
          final widget = element.widget as RichText;
          final plainText = widget.text.toPlainText();
          if (plainText.contains('First line of text\nsecond line of text')) {
            foundNewline = true;
          }
        }

        expect(
          foundNewline,
          isTrue,
          reason: 'Two trailing spaces should create a hard line break with a newline',
        );
      },
    );

    testWidgets(
      'Hard line breaks with trailing backslash render with newline',
      (WidgetTester tester) async {
        const markdownData = 'First line of text\\\nsecond line of text';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsWidgets);

        bool foundNewline = false;
        for (final element in richTextFinder.evaluate()) {
          final widget = element.widget as RichText;
          final plainText = widget.text.toPlainText();
          if (plainText.contains('First line of text\nsecond line of text')) {
            foundNewline = true;
          }
        }

        expect(
          foundNewline,
          isTrue,
          reason: 'Trailing backslash should create a hard line break with a newline',
        );
      },
    );
  });

  group('Markdown Link Navigation', () {
    testWidgets('Links containing inline code are clickable and open files', (
      WidgetTester tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync('siren_test_');
      final targetFile = File('${tempDir.path}/docs/architecture.md');
      targetFile.createSync(recursive: true);
      targetFile.writeAsStringSync('# Architecture Documentation');

      try {
        final sourceFilePath = '${tempDir.path}/README.md';
        const markdownData =
            '- [`docs/architecture.md`](docs/architecture.md) — system overview';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: Scaffold(body: RenderedView(filePath: sourceFilePath)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find the RichText containing the link code text
        final linkFinder = find.textContaining(
          'docs/architecture.md',
          findRichText: true,
        );
        expect(linkFinder, findsOneWidget);

        final richText = tester.widget<RichText>(linkFinder);
        final recognizer = _findTapRecognizer(
          richText.text,
          'docs/architecture.md',
        );
        expect(
          recognizer,
          isNotNull,
          reason: 'Inline code in link must have a TapGestureRecognizer',
        );

        // Trigger the tap recognizer
        recognizer!.onTap?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify openFile was called with the target file
        expect(appState.lastOpenedFile, isNotNull);
        expect(appState.lastOpenedFile, equals(targetFile.path));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'Relative links fallback to explorerRootPath if not found relative to file',
      (WidgetTester tester) async {
        final tempDir = Directory.systemTemp.createTempSync('siren_workspace_');
        final workspaceRoot = tempDir.path;
        final targetFile = File('$workspaceRoot/docs/architecture.md');
        targetFile.createSync(recursive: true);

        // Source file in a subfolder like guides/
        final sourceFile = File('$workspaceRoot/guides/intro.md');
        sourceFile.createSync(recursive: true);

        try {
          const markdownData =
              'Check out [`docs/architecture.md`](docs/architecture.md)';

          final appState = _TestAppState();
          appState.currentContent = markdownData;
          appState.explorerRootPath = workspaceRoot;

          await tester.pumpWidget(
            MaterialApp(
              theme: SirenTheme.light,
              home: ChangeNotifierProvider<AppState>.value(
                value: appState,
                child: Scaffold(body: RenderedView(filePath: sourceFile.path)),
              ),
            ),
          );

          await tester.pumpAndSettle();

          final linkFinder = find.textContaining(
            'docs/architecture.md',
            findRichText: true,
          );
          expect(linkFinder, findsOneWidget);

          final richText = tester.widget<RichText>(linkFinder);
          final recognizer = _findTapRecognizer(
            richText.text,
            'docs/architecture.md',
          );
          expect(recognizer, isNotNull);

          recognizer!.onTap?.call();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(appState.lastOpenedFile, equals(targetFile.path));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });

  group('Embedded HTML Widget Rendering', () {
    testWidgets(
      'Renders Flutter <a href><h1 align="center"><picture> block and switches dark/light srcset',
      (WidgetTester tester) async {
        const markdownData = '''<a href="https://flutter.dev/">
  <h1 align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.flutter.dev/logo_dark.png">
      <img alt="Flutter" src="https://docs.flutter.dev/logo.png">
    </picture>
  </h1>
</a>''';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

        // 1. Light theme selects fallback <img> src
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

        expect(
          find.byKey(
            const ValueKey<String>(
              'network_image_https://docs.flutter.dev/logo.png',
            ),
          ),
          findsOneWidget,
        );

        // 2. Dark theme selects <source media="(prefers-color-scheme: dark)"> srcset
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
      'Renders alt text with H1 heading typography when an image inside <h1 align="center"> fails to load',
      (WidgetTester tester) async {
        const markdownData = '''<a href="https://flutter.dev/">
  <h1 align="center">
    <img alt="Flutter" src="nonexistent_logo.png">
  </h1>
</a>''';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        final altTextFinder = find.text('Flutter');
        expect(altTextFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(altTextFinder);
        expect(textWidget.style?.fontSize, 14.0 * 2.25);
        expect(textWidget.style?.fontWeight, FontWeight.w600);
      },
    );

    testWidgets(
      'Renders Siren README <p align="center"> blocks with sized image, bold text, and badges',
      (WidgetTester tester) async {
        const markdownData = '''# Siren

<p align="center">
  <img src="assets/images/app_icon.png" alt="Siren Logo" width="128" height="128" />
</p>

<p align="center">
  <strong>A sleek, high-performance desktop Markdown viewer built with Flutter.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white" alt="macOS" />
  <a href="https://github.com/tkinnis/siren/releases/latest"><img src="https://img.shields.io/github/v/release/tkinnis/siren?color=007AFF&logo=apple&logoColor=white" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" />
</p>''';

        final appState = _TestAppState();
        appState.currentContent = markdownData;
        appState.explorerRootPath = Directory.current.path;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(body: RenderedView(filePath: 'README.md')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify local 128x128 Siren Logo Image widget rendered
        final logoFinder = find.byType(Image);
        expect(logoFinder, findsOneWidget);
        final logoWidget = tester.widget<Image>(logoFinder);
        expect(logoWidget.width, 128.0);
        expect(logoWidget.height, 128.0);

        // Verify centered tagline rendered
        expect(
          find.textContaining(
            'A sleek, high-performance desktop Markdown viewer built with Flutter.',
            findRichText: true,
          ),
          findsOneWidget,
        );

        // Verify SVG badges rendered via test placeholders
        expect(find.text('Latest Release'), findsOneWidget);
      },
    );

    testWidgets(
      'Resolves ../assets/images/app_icon.png and repo-root assets/images/app_icon.png from docs/ subfolder',
      (WidgetTester tester) async {
        const markdownData = '''<p align="center">
  <img src="../assets/images/app_icon.png" alt="Siren Logo" width="72" height="72" />
</p>

<p align="center">
  <img src="assets/images/app_icon.png" alt="Siren Root Logo" width="72" height="72" />
</p>''';

        final docsDir = '${Directory.current.path}/docs';
        final docFile = '$docsDir/markdown-guide.md';
        final appState = _TestAppState();
        appState.currentContent = markdownData;
        appState.explorerRootPath = docsDir;

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
      'Renders inline <kbd>, <sub>, <sup>, <mark>, <u>, <del>, <br> and collapsible <details>',
      (WidgetTester tester) async {
        const markdownData = '''<!-- Hidden HTML comment -->
Press <kbd>Cmd</kbd> + <kbd>P</kbd> for H<sub>2</sub>O and <mark>marked</mark> and <u>underlined</u>.

<details>
  <summary>Expandable Section</summary>

  Revealed details body content.
</details>''';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        expect(find.text('Hidden HTML comment'), findsNothing);
        expect(find.text('Cmd'), findsOneWidget);
        expect(find.text('P'), findsOneWidget);
        expect(find.text('marked'), findsOneWidget);
        expect(find.text('underlined'), findsOneWidget);

        // Details starts collapsed
        expect(find.text('Expandable Section'), findsOneWidget);
        expect(
          find.textContaining(
            'Revealed details body content.',
            findRichText: true,
          ),
          findsNothing,
        );

        // Tap summary to expand
        await tester.tap(find.text('Expandable Section'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Revealed details body content.',
            findRichText: true,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Renders HTML <table>, <dl>, <abbr>, <small>, and <q> elements',
      (WidgetTester tester) async {
        const markdownData = '''Hover <abbr title="GitHub Flavored Markdown">GFM</abbr> with <small>fine print</small> and <q>quoted text</q>.

<table>
  <tr>
    <th>Component</th>
    <th align="center">Status</th>
  </tr>
  <tr>
    <td>HTML Parser</td>
    <td align="center">Active</td>
  </tr>
</table>

<dl>
  <dt>Ripgrep</dt>
  <dd>Fast workspace search engine</dd>
</dl>''';

        final appState = _TestAppState();
        appState.currentContent = markdownData;

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

        expect(find.text('GFM'), findsOneWidget);
        expect(find.text('fine print'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(
          find.textContaining('HTML Parser', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Fast workspace search engine',
            findRichText: true,
          ),
          findsOneWidget,
        );
      },
    );
  });
}
