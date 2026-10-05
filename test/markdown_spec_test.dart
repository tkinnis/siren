import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

TapGestureRecognizer? _findTapRecognizer(InlineSpan span, String targetText, [TapGestureRecognizer? inheritedRecognizer]) {
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
    testWidgets('Soft line breaks in paragraphs render as spaces, not linebreaks', (
      WidgetTester tester,
    ) async {
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
        reason: 'Soft line break should not contain a literal newline character',
      );
    });

    testWidgets('Hard line breaks with trailing two spaces render with newline', (
      WidgetTester tester,
    ) async {
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
    });

    testWidgets('Hard line breaks with trailing backslash render with newline', (
      WidgetTester tester,
    ) async {
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
    });
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
        const markdownData = '- [`docs/architecture.md`](docs/architecture.md) — system overview';

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
        final linkFinder = find.textContaining('docs/architecture.md', findRichText: true);
        expect(linkFinder, findsOneWidget);

        final richText = tester.widget<RichText>(linkFinder);
        final recognizer = _findTapRecognizer(richText.text, 'docs/architecture.md');
        expect(recognizer, isNotNull, reason: 'Inline code in link must have a TapGestureRecognizer');

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

    testWidgets('Relative links fallback to explorerRootPath if not found relative to file', (
      WidgetTester tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync('siren_workspace_');
      final workspaceRoot = tempDir.path;
      final targetFile = File('$workspaceRoot/docs/architecture.md');
      targetFile.createSync(recursive: true);

      // Source file in a subfolder like guides/
      final sourceFile = File('$workspaceRoot/guides/intro.md');
      sourceFile.createSync(recursive: true);

      try {
        const markdownData = 'Check out [`docs/architecture.md`](docs/architecture.md)';

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

        final linkFinder = find.textContaining('docs/architecture.md', findRichText: true);
        expect(linkFinder, findsOneWidget);

        final richText = tester.widget<RichText>(linkFinder);
        final recognizer = _findTapRecognizer(richText.text, 'docs/architecture.md');
        expect(recognizer, isNotNull);

        recognizer!.onTap?.call();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(appState.lastOpenedFile, equals(targetFile.path));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
