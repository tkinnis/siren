import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/mermaid_diagram.dart';
import 'package:siren/mermaid_render_service.dart';
import 'package:siren/mermaid_zoom_dialog.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

const String _sampleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 120" width="240" height="120">
  <rect x="10" y="10" width="90" height="45" rx="6" fill="#0969da" />
  <rect x="140" y="65" width="90" height="45" rx="6" fill="#2da44e" />
  <path d="M 100 32 L 140 87" stroke="#57606a" stroke-width="2" fill="none" />
</svg>
''';

// 1x1 transparent PNG
final Uint8List _samplePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _FakeAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  String? currentFilePath = 'diagram.md';

  @override
  String? explorerRootPath;

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
  void increaseFontSize() {
    if (fontSize < 32.0) {
      fontSize += 1.0;
      notifyListeners();
    }
  }

  @override
  void decreaseFontSize() {
    if (fontSize > 10.0) {
      fontSize -= 1.0;
      notifyListeners();
    }
  }

  @override
  void resetFontSize() {
    if (fontSize != 14.0) {
      fontSize = 14.0;
      notifyListeners();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Uint8List compiledSampleBytes;

  setUpAll(() {
    compiledSampleBytes = compileMermaidSvg(_sampleSvg);
  });

  setUp(() {
    MermaidRenderService.instance.clearCache();
    MermaidRenderService.instance.renderOverride =
        (String code, {required bool isDark}) async {
          return MermaidSvgRender(
            svg: _sampleSvg,
            compiledBytes: compiledSampleBytes,
            logicalSize: const Size(240, 120),
          );
        };
  });

  tearDown(() {
    MermaidRenderService.instance.renderOverride = null;
    MermaidRenderService.instance.clearCache();
  });

  group('MermaidRenderService & SVG Compilation', () {
    test('compileMermaidSvg encodes valid SVG into binary vector_graphics', () {
      expect(compiledSampleBytes, isNotEmpty);
    });

    test(
      'normalized neo stroke-dasharray preserves straight LineToCommand paths',
      () {
        const normalizedArrowSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" width="200" height="100">
  <path d="M 100 20 L 100 60" stroke="rgb(51,51,51)" stroke-width="1" fill="none" stroke-dasharray="36,4" />
  <path d="M 100 60 L 100 95" stroke="rgb(51,51,51)" stroke-width="1" fill="none" stroke-dasharray="0.01,4,27,4" />
</svg>
''';
        final instructions = vg.parseWithoutOptimizers(normalizedArrowSvg);
        expect(instructions.paths, hasLength(2));
        for (final path in instructions.paths) {
          expect(
            path.commands.whereType<vg.LineToCommand>(),
            isNotEmpty,
            reason: 'Straight edges must retain LineToCommand segments',
          );
        }
      },
    );

    test(
      'MermaidRenderService caches results by diagram source and theme',
      () async {
        int renderCount = 0;
        MermaidRenderService.instance.renderOverride =
            (String code, {required bool isDark}) async {
              renderCount++;
              return MermaidSvgRender(
                svg: _sampleSvg,
                compiledBytes: compiledSampleBytes,
                logicalSize: const Size(240, 120),
              );
            };

        const source = 'graph TD\n  A --> B';
        expect(
          MermaidRenderService.instance.peek(source, isDark: false),
          isNull,
        );

        final first = await MermaidRenderService.instance.render(
          source,
          isDark: false,
        );
        expect(first, isA<MermaidSvgRender>());
        expect(renderCount, 1);

        expect(
          MermaidRenderService.instance.peek(source, isDark: false),
          same(first),
        );

        // Subsequent render with same source + theme hits cache
        final cached = await MermaidRenderService.instance.render(
          source,
          isDark: false,
        );
        expect(cached, same(first));
        expect(renderCount, 1);

        // Different theme triggers a fresh render
        final darkRender = await MermaidRenderService.instance.render(
          source,
          isDark: true,
        );
        expect(darkRender, isA<MermaidSvgRender>());
        expect(renderCount, 2);
      },
    );
  });

  group('MermaidDiagram Rendering & Proportional Font Scaling', () {
    testWidgets(
      'renders VectorGraphic for SVG result and scales with fontSize',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  child: MermaidDiagram(
                    code: 'graph TD\n  A --> B',
                    isDark: false,
                    fontSize: 14.0,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);

        final scaledBox14 = tester.widget<SizedBox>(
          find.byKey(const Key('mermaid_scaled_box')),
        );
        expect(scaledBox14.width, closeTo(240.0, 0.01));
        expect(scaledBox14.height, closeTo(120.0, 0.01));

        // Increase fontSize to 28.0 (2x base 14.0)
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  child: MermaidDiagram(
                    code: 'graph TD\n  A --> B',
                    isDark: false,
                    fontSize: 28.0,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scaledBox28 = tester.widget<SizedBox>(
          find.byKey(const Key('mermaid_scaled_box')),
        );
        expect(scaledBox28.width, closeTo(480.0, 0.01));
        expect(scaledBox28.height, closeTo(240.0, 0.01));

        // Decrease fontSize to 10.5 (0.75x base 14.0)
        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  child: MermaidDiagram(
                    code: 'graph TD\n  A --> B',
                    isDark: false,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scaledBoxSmall = tester.widget<SizedBox>(
          find.byKey(const Key('mermaid_scaled_box')),
        );
        expect(scaledBoxSmall.width, closeTo(180.0, 0.01));
        expect(scaledBoxSmall.height, closeTo(90.0, 0.01));
      },
    );

    testWidgets('scales inside RenderedView when AppState fontSize changes', (
      WidgetTester tester,
    ) async {
      final appState = _FakeAppState()
        ..currentContent = '```mermaid\ngraph TD\n  A --> B\n```';

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(body: RenderedView(filePath: 'diagram.md')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SizedBox scaledBox = tester.widget<SizedBox>(
        find.byKey(const Key('mermaid_scaled_box')),
      );
      expect(scaledBox.width, closeTo(240.0, 0.01));

      // Increase font size 3 times (14 -> 17)
      appState.increaseFontSize();
      appState.increaseFontSize();
      appState.increaseFontSize();
      await tester.pumpAndSettle();

      scaledBox = tester.widget<SizedBox>(
        find.byKey(const Key('mermaid_scaled_box')),
      );
      expect(scaledBox.width, closeTo(240.0 * (17.0 / 14.0), 0.05));

      // Reset font size (17 -> 14)
      appState.resetFontSize();
      await tester.pumpAndSettle();

      scaledBox = tester.widget<SizedBox>(
        find.byKey(const Key('mermaid_scaled_box')),
      );
      expect(scaledBox.width, closeTo(240.0, 0.01));
    });

    testWidgets('renders Image for raster fallback result', (
      WidgetTester tester,
    ) async {
      MermaidRenderService.instance.renderOverride =
          (String code, {required bool isDark}) async {
            return MermaidRasterRender(
              pngBytes: _samplePng,
              logicalSize: const Size(300, 150),
            );
          };

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: const Scaffold(
            body: Center(
              child: MermaidDiagram(
                code: 'gitGraph\n  commit',
                isDark: false,
                fontSize: 14.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders fallback view when diagram rendering fails', (
      WidgetTester tester,
    ) async {
      MermaidRenderService.instance.renderOverride =
          (String code, {required bool isDark}) async {
            return const MermaidFailureResult(
              kind: 'parse-error',
              message: 'Syntax error in graph',
            );
          };

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: const Scaffold(
            body: Center(
              child: MermaidDiagram(
                code: 'invalid mermaid syntax',
                isDark: false,
                fontSize: 14.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mermaid_failure_block')), findsOneWidget);
      expect(find.text('Syntax error in graph'), findsOneWidget);
      expect(find.text('invalid mermaid syntax'), findsOneWidget);
    });
  });

  group('MermaidZoomDialog Interactive Zoom & Pan Modal', () {
    testWidgets('clicking diagram opens MermaidZoomDialog with zoom controls', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: const Scaffold(
            body: Center(
              child: MermaidDiagram(
                code: 'graph TD\n  Start --> Stop',
                isDark: false,
                fontSize: 14.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MermaidZoomDialog), findsNothing);

      // Tap diagram to open zoom/pan modal
      await tester.tap(find.byKey(const Key('mermaid_diagram_tap_target')));
      await tester.pumpAndSettle();

      expect(find.byType(MermaidZoomDialog), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(
        find.byKey(const Key('mermaid_zoom_copy_image_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mermaid_zoom_export_button')),
        findsOneWidget,
      );

      // Click Zoom In (+)
      await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
      await tester.pumpAndSettle();
      expect(find.text('125%'), findsOneWidget);

      // Click Zoom Out (-)
      await tester.tap(find.byKey(const Key('mermaid_zoom_out_button')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      // Zoom In twice -> 156%, then click percentage pill to reset to 100%
      await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
      await tester.pumpAndSettle();
      expect(find.text('156%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mermaid_zoom_reset_pill')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      // Close modal
      await tester.tap(find.byKey(const Key('mermaid_zoom_close_button')));
      await tester.pumpAndSettle();
      expect(find.byType(MermaidZoomDialog), findsNothing);
    });
  });
}
