import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siren/app_state.dart';
import 'package:siren/main.dart';
import 'package:siren/markdown_extensions.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

class _TestAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  bool showFrontmatter = true;

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

Future<void> _ensureFontLoaded(WidgetTester tester) async {
  if (TexMathFontBundle.cachedMathFont != null) {
    return;
  }
  await tester.runAsync(TexMathFontBundle.loadMathFont);
}

Widget _buildRenderedViewApp({
  required AppState appState,
  required ThemeData theme,
}) {
  return MaterialApp(
    theme: theme,
    home: ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const Scaffold(body: RenderedView(filePath: 'test.md')),
    ),
  );
}

void main() {
  testWidgets(
    'Inline math renders TexMath inside paragraph RichText with alphabetic baseline',
    (WidgetTester tester) async {
      await _ensureFontLoaded(tester);

      final appState = _TestAppState()
        ..currentContent = r'Mass-energy equivalence is $E = mc^2$.';

      await tester.pumpWidget(
        _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
      );
      await tester.pumpAndSettle();

      final texMathFinder = find.byType(TexMath);
      expect(texMathFinder, findsOneWidget);

      final texMath = tester.widget<TexMath>(texMathFinder);
      expect(texMath.displayMode, TexMathDisplayMode.inline);
      expect(texMath.source, 'E = mc^2');

      final ancestorRichTexts = find
          .ancestor(of: texMathFinder, matching: find.byType(RichText))
          .evaluate()
          .map((e) => e.widget as RichText)
          .where((rt) => rt.text.toPlainText().contains('Mass-energy'))
          .toList();
      expect(ancestorRichTexts, isNotEmpty);
    },
  );

  testWidgets(
    'Display math renders TexMath in display mode with scroll overflow',
    (WidgetTester tester) async {
      await _ensureFontLoaded(tester);

      final appState = _TestAppState()
        ..currentContent = r'''$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$''';

      await tester.pumpWidget(
        _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
      );
      await tester.pumpAndSettle();

      final texMathFinder = find.byType(TexMath);
      expect(texMathFinder, findsOneWidget);

      final texMath = tester.widget<TexMath>(texMathFinder);
      expect(texMath.displayMode, TexMathDisplayMode.display);
      expect(texMath.overflow, TexMathOverflow.scroll);
      expect(texMath.effectiveOverflow, TexMathOverflow.scroll);

      final scrollFinder = find.descendant(
        of: texMathFinder,
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollFinder, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(scrollFinder).scrollDirection,
        Axis.horizontal,
      );
    },
  );

  testWidgets(
    'Toggling light and dark themes recolors math with zero new path or layout cache builds',
    (WidgetTester tester) async {
      await _ensureFontLoaded(tester);
      SirenMathLayoutCache.shared.clear();

      final appState = _TestAppState()
        ..currentContent = r'''Inline $E = mc^2$ and display:

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$''';

      await tester.pumpWidget(
        _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TexMath), findsNWidgets(2));
      final lightThemeWidget = tester.widget<TexMathTheme>(
        find.byType(TexMathTheme),
      );
      expect(
        lightThemeWidget.data.foreground,
        SirenTheme.light.colorScheme.onSurface,
      );
      expect(
        lightThemeWidget.data.accent,
        SirenTheme.light.colorScheme.primary,
      );

      final buildsAfterLight = TexMathPathCache.shared.buildCount;
      final hitsAfterLight = TexMathPathCache.shared.hitCount;
      final layoutsAfterLight = SirenMathLayoutCache.shared.layoutCount;
      expect(buildsAfterLight, greaterThan(0));
      expect(layoutsAfterLight, 2);

      await tester.pumpWidget(
        _buildRenderedViewApp(appState: appState, theme: SirenTheme.dark),
      );
      await tester.pumpAndSettle();

      final darkThemeWidget = tester.widget<TexMathTheme>(
        find.byType(TexMathTheme),
      );
      expect(
        darkThemeWidget.data.foreground,
        SirenTheme.dark.colorScheme.onSurface,
      );
      expect(darkThemeWidget.data.accent, SirenTheme.dark.colorScheme.primary);
      expect(TexMathPathCache.shared.buildCount, buildsAfterLight);
      expect(TexMathPathCache.shared.hitCount, greaterThan(hitsAfterLight));
      expect(SirenMathLayoutCache.shared.layoutCount, layoutsAfterLight);

      final hitsAfterDark = TexMathPathCache.shared.hitCount;
      await tester.pumpWidget(
        _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
      );
      await tester.pumpAndSettle();

      expect(TexMathPathCache.shared.buildCount, buildsAfterLight);
      expect(TexMathPathCache.shared.hitCount, greaterThan(hitsAfterDark));
      expect(SirenMathLayoutCache.shared.layoutCount, layoutsAfterLight);
    },
  );

  testWidgets(
    'MainApp disables theme fade interpolation for instant switching',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});
      final realAppState = (await tester.runAsync(AppState.create))!;
      try {
        await tester.pumpWidget(MainApp(appState: realAppState));
        await tester.pump();

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.themeAnimationDuration, Duration.zero);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        realAppState.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Unclosed double dollar delimiters render safely as plain text', (
    WidgetTester tester,
  ) async {
    await _ensureFontLoaded(tester);

    final appState = _TestAppState()
      ..currentContent = r'Here is an unclosed $$ delimiter in prose.';

    await tester.pumpWidget(
      _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TexMath), findsNothing);
    expect(find.byType(TexMathErrorWidget), findsNothing);
    expect(find.textContaining('unclosed', findRichText: true), findsOneWidget);
  });

  testWidgets('Malformed TeX renders TexMathErrorWidget without throwing', (
    WidgetTester tester,
  ) async {
    await _ensureFontLoaded(tester);

    final appState = _TestAppState()
      ..currentContent = r'Broken formula: $\frac{1}{$ here.';

    await tester.pumpWidget(
      _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TexMathErrorWidget), findsOneWidget);
    expect(
      find.textContaining(r'\frac{1}{', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
    r'Tapping \href forwards destination URI to LatexBuilder.onLinkTap',
    (WidgetTester tester) async {
      await _ensureFontLoaded(tester);

      final tapped = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: Scaffold(
            body: SelectionArea(
              child: Center(
                child: MarkdownBody(
                  data: r'See $\href{https://example.org}{E = mc^2}$ here.',
                  extensionSet: md.ExtensionSet(
                    [...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                    [
                      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                      LatexSyntax(),
                    ],
                  ),
                  builders: {'latex': LatexBuilder(onLinkTap: tapped.add)},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final texMathFinder = find.byType(TexMath);
      expect(texMathFinder, findsOneWidget);

      await tester.tapAt(tester.getCenter(texMathFinder));
      await tester.pumpAndSettle();

      expect(tapped, ['https://example.org']);
    },
  );

  testWidgets('Inline math inside H1 heading renders scaled TexMath', (
    WidgetTester tester,
  ) async {
    await _ensureFontLoaded(tester);

    final appState = _TestAppState()..currentContent = r'# Heading $E = mc^2$';

    await tester.pumpWidget(
      _buildRenderedViewApp(appState: appState, theme: SirenTheme.light),
    );
    await tester.pumpAndSettle();

    final texMathFinder = find.byType(TexMath);
    expect(texMathFinder, findsOneWidget);

    final headerAncestor = find.ancestor(
      of: texMathFinder,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.header ?? false),
      ),
    );
    expect(headerAncestor, findsOneWidget);

    final texMath = tester.widget<TexMath>(texMathFinder);
    final sirenColors = SirenTheme.light.extension<SirenColors>()!;
    expect(texMath.textStyle?.fontSize, 14.0 * 2.25);
    expect(texMath.textStyle?.color, sirenColors.headingColor);
  });
}
