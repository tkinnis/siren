import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';

class _TestAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  String? currentFilePath = 'test.md';

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
  testWidgets('Inline code in H3 heading inherits heading font size, color, and weight', (
    WidgetTester tester,
  ) async {
    const markdownData = '### 7.2 `runFinished` gains a verdict, and it leads the exit code';

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

    RichText? h3RichText;
    for (final element in richTextFinder.evaluate()) {
      final widget = element.widget as RichText;
      if (widget.text.toPlainText().contains('runFinished')) {
        h3RichText = widget;
        break;
      }
    }

    expect(h3RichText, isNotNull);
    final rootSpan = h3RichText!.text as TextSpan;
    final sirenColors = SirenTheme.light.extension<SirenColors>()!;

    TextSpan? codeSpan;
    void findCodeSpan(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == 'runFinished') {
          codeSpan = span;
          return;
        }
        if (span.children != null) {
          for (final child in span.children!) {
            findCodeSpan(child);
          }
        }
      }
    }

    findCodeSpan(rootSpan);
    expect(codeSpan, isNotNull);

    // Verify code span inherits H3 size (21.0), headingColor, and w600 font weight
    expect(codeSpan!.style?.fontSize, equals(14.0 * 1.5));
    expect(codeSpan!.style?.color, equals(sirenColors.headingColor));
    expect(codeSpan!.style?.fontWeight, equals(FontWeight.w600));
    expect(codeSpan!.style?.fontFamily, contains('FiraCode'));
    expect(codeSpan!.style?.backgroundColor, equals(sirenColors.codeBg));
  });

  testWidgets('Inline code in H1 heading renders with heading style, code background, and monospace font', (
    WidgetTester tester,
  ) async {
    const markdownData = '# Overview of `SirenEngine`';

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

    final textFinder = find.byType(Text);
    final rootSpan = (textFinder.evaluate().last.widget as Text).textSpan as TextSpan;
    final sirenColors = SirenTheme.light.extension<SirenColors>()!;

    // Verify H1 root span has 14 * 2.25 = 31.5 and headingColor
    expect(rootSpan.style?.fontSize, equals(14.0 * 2.25));
    expect(rootSpan.style?.color, equals(sirenColors.headingColor));

    TextSpan? codeSpan;
    void findCodeSpan(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.fontFamily != null && span.style!.fontFamily!.contains('FiraCode')) {
          codeSpan = span;
          return;
        }
        if (span.children != null) {
          for (final child in span.children!) {
            findCodeSpan(child);
          }
        }
      }
    }

    findCodeSpan(rootSpan);
    expect(codeSpan, isNotNull);
    expect(codeSpan!.style?.fontFamily, contains('FiraCode'));
    expect(codeSpan!.style?.backgroundColor, equals(sirenColors.codeBg));
  });

  testWidgets('Inline code in paragraph renders with monospace font and code background', (
    WidgetTester tester,
  ) async {
    const markdownData = 'This is `plainCode` in body text.';

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
    RichText? pRichText;
    for (final element in richTextFinder.evaluate()) {
      final widget = element.widget as RichText;
      if (widget.text.toPlainText().contains('plainCode')) {
        pRichText = widget;
        break;
      }
    }

    expect(pRichText, isNotNull);
    final rootSpan = pRichText!.text as TextSpan;
    final sirenColors = SirenTheme.light.extension<SirenColors>()!;

    TextSpan? codeSpan;
    void findCodeSpan(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == 'plainCode') {
          codeSpan = span;
          return;
        }
        if (span.children != null) {
          for (final child in span.children!) {
            findCodeSpan(child);
          }
        }
      }
    }

    findCodeSpan(rootSpan);
    expect(codeSpan, isNotNull);
    expect(codeSpan!.style?.fontSize, equals(14.0));
    expect(codeSpan!.style?.fontFamily, contains('FiraCode'));
    expect(codeSpan!.style?.backgroundColor, equals(sirenColors.codeBg));
  });
}
