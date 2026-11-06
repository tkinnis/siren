import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/markdown_extensions.dart';
import 'package:siren/mermaid_diagram.dart';
import 'package:siren/mermaid_render_service.dart';
import 'package:siren/mermaid_zoom_dialog.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/theme.dart';
import 'package:vector_graphics/vector_graphics_compat.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

const String _sampleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 120" width="240" height="120">
  <rect x="10" y="10" width="90" height="45" rx="6" fill="#0969da" />
  <rect x="140" y="65" width="90" height="45" rx="6" fill="#2da44e" />
  <path d="M 100 32 L 140 87" stroke="#57606a" stroke-width="2" fill="none" />
</svg>
''';

class _FakeAppState extends ChangeNotifier implements AppState {
  @override
  String currentContent = '';

  @override
  double fontSize = 14.0;

  @override
  bool showFrontmatter = true;

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
        final vgWidget = tester.widget<VectorGraphic>(
          find.byType(VectorGraphic),
        );
        expect(vgWidget.strategy, RenderingStrategy.picture);

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

  group('Pure-Dart pele_dart Diagram Rendering & SVG Badge Compilation', () {
    test('declares all 33 vector SVG diagram families', () {
      expect(mermaidMacosSvgTypes, hasLength(33));
      expect(
        mermaidMacosSvgTypes,
        containsAll(<String>[
          'flowchart',
          'sequence',
          'class',
          'state',
          'er',
          'gantt',
          'pie',
          'gitGraph',
          'info',
          'radar',
          'treemap',
          'venn',
          'railroad',
          'ishikawa',
          'cynefin',
          'agentflow',
          'usecase',
          'swimlane',
          'eventmodeling',
          'treeView',
          'wardley',
        ]),
      );
    });

    test('renders standard, beta, and specialized diagrams end-to-end via pele_dart without overrides', () async {
      MermaidRenderService.instance.renderOverride = null;
      MermaidRenderService.instance.clearCache();

      const samples = <String, String>{
        'flowchart':
            'flowchart LR\n  A[Start] --> B{Decision}\n  B -->|Yes| C[Done]',
        'sequence': 'sequenceDiagram\n  Alice->>Bob: Hello!',
        'radar': 'radar-beta\n  axis A, B, C\n  curve c1{1, 2, 3}',
        'venn': 'venn-beta\n  set A\n  set B\n  union A, B',
        'railroad': 'railroad-ebnf-beta\n  number = [ "-" ], digit, { digit };',
        'treeView': 'treeView-beta\n  "siren"\n    "lib"\n      "main.dart"',
        'wardley': 'wardley-beta\n  component A [0.5, 0.5]',
        'eventmodeling':
            'eventmodeling\n  tf 01 ui CartView\n  tf 02 cmd AddItem ->> 01',
        'swimlane': 'swimlane-beta\n  subgraph Customer\n    Order[Place Order]\n  end\n  subgraph System\n    Confirm[Confirm]\n  end\n  Order --> Confirm',
      };

      for (final entry in samples.entries) {
        final lightResult = await MermaidRenderService.instance.render(
          entry.value,
          isDark: false,
        );
        expect(
          lightResult,
          isA<MermaidSvgRender>(),
          reason:
              'Expected ${entry.key} to render as MermaidSvgRender in light mode',
        );
        final lightSvg = lightResult as MermaidSvgRender;
        expect(lightSvg.diagramType, entry.key);
        expect(lightSvg.compiledBytes, isNotEmpty);
        expect(lightSvg.logicalSize.width, greaterThan(0));
        expect(lightSvg.logicalSize.height, greaterThan(0));

        final darkResult = await MermaidRenderService.instance.render(
          entry.value,
          isDark: true,
        );
        expect(
          darkResult,
          isA<MermaidSvgRender>(),
          reason:
              'Expected ${entry.key} to render as MermaidSvgRender in dark mode',
        );
      }

      final failure = await MermaidRenderService.instance.render(
        'not_a_mermaid_diagram\n  foo bar',
        isDark: false,
      );
      expect(failure, isA<MermaidFailureResult>());
    });

    test('renders all 33 diagram families in docs/mermaid-examples.md via the persistent worker isolate', () async {
      MermaidRenderService.instance.renderOverride = null;
      MermaidRenderService.instance.clearCache();
      await MermaidRenderService.instance.warmUp();

      final examplesMd = File('docs/mermaid-examples.md').readAsStringSync();
      final fenceRegex = RegExp(
        r'```mermaid\r?\n([\s\S]*?)```',
        multiLine: true,
      );
      final matches = fenceRegex.allMatches(examplesMd).toList();
      expect(matches.length, greaterThanOrEqualTo(50));

      final sw = Stopwatch()..start();
      final concurrentFutures = <Future<MermaidRenderResult>>[
        for (var i = 0; i < matches.length; i++)
          MermaidRenderService.instance.render(
            matches[i].group(1)!,
            isDark: false,
          ),
      ];
      final results = await Future.wait(concurrentFutures);
      sw.stop();

      final renderedFamilies = <String>{};
      for (var i = 0; i < results.length; i++) {
        final result = results[i];
        expect(
          result,
          isA<MermaidSvgRender>(),
          reason:
              'Diagram #${i + 1} in docs/mermaid-examples.md failed: '
              '${result is MermaidFailureResult ? result.message : result}',
        );
        final svgRender = result as MermaidSvgRender;
        expect(svgRender.compiledBytes, isNotEmpty);
        if (svgRender.diagramType != null) {
          renderedFamilies.add(svgRender.diagramType!);
        }
      }

      expect(
        renderedFamilies,
        equals(mermaidMacosSvgTypes),
        reason: 'docs/mermaid-examples.md must cover all 33 pele_dart families',
      );

      // Verify warm isolate pool renders all 57 diagrams in < 1500ms
      MermaidRenderService.instance.clearCache();
      final warmSw = Stopwatch()..start();
      await Future.wait(<Future<MermaidRenderResult>>[
        for (var i = 0; i < matches.length; i++)
          MermaidRenderService.instance.render(
            matches[i].group(1)!,
            isDark: false,
          ),
      ]);
      warmSw.stop();
      expect(
        warmSw.elapsedMilliseconds,
        lessThan(1500),
        reason:
            'All ${matches.length} diagrams rendered warm in ${warmSw.elapsedMilliseconds}ms',
      );

      // Verify cached pass returns all 57 diagrams synchronously in < 20ms
      final cachedSw = Stopwatch()..start();
      await Future.wait(<Future<MermaidRenderResult>>[
        for (var i = 0; i < matches.length; i++)
          MermaidRenderService.instance.render(
            matches[i].group(1)!,
            isDark: false,
          ),
      ]);
      cachedSw.stop();
      expect(
        cachedSw.elapsedMilliseconds,
        lessThan(20),
        reason:
            'All ${matches.length} cached diagrams returned in ${cachedSw.elapsedMilliseconds}ms',
      );
    });

    testWidgets(
      'viewport-aware lazy rendering only renders visible diagrams on initial mount and renders off-screen diagrams on scroll',
      (tester) async {
        final renderedCodes = <String>[];
        MermaidRenderService.instance.clearCache();
        MermaidRenderService.instance.renderOverride =
            (code, {required isDark}) async {
              renderedCodes.add(code);
              return MermaidSvgRender(
                svg: _sampleSvg,
                compiledBytes: compiledSampleBytes,
                logicalSize: const Size(240, 120),
              );
            };

        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      for (var i = 0; i < 20; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 600),
                          child: MermaidDiagram(
                            code: 'flowchart LR\n  Node$i --> End$i',
                            isDark: false,
                            fontSize: 16.0,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Only the initial quota + near-viewport diagrams should render on mount,
        // NOT all 20 diagrams.
        expect(renderedCodes.length, lessThanOrEqualTo(6));
        expect(renderedCodes, contains('flowchart LR\n  Node0 --> End0'));
        expect(
          renderedCodes,
          isNot(contains('flowchart LR\n  Node19 --> End19')),
        );

        // Scroll to the bottom and verify the bottom diagram renders on demand.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();

        expect(renderedCodes, contains('flowchart LR\n  Node19 --> End19'));
      },
    );

    test('compiles modern and classic Shields.io SVG badges with 11px scaled text and inlined base64 logos without WebView', () {
      const modernFlutterBadgeSvg =
          '<svg xmlns="http://www.w3.org/2000/svg" width="107" height="20" role="img" aria-label="Flutter: 3.47+">'
          '<title>Flutter: 3.47+</title>'
          '<filter id="blur"><feGaussianBlur stdDeviation="16"/></filter>'
          '<linearGradient id="s" x2="0" y2="100%">'
          '<stop offset="0" stop-color="#bbb" stop-opacity=".1"/>'
          '<stop offset="1" stop-opacity=".1"/>'
          '</linearGradient>'
          '<clipPath id="r"><rect width="107" height="20" rx="3"/></clipPath>'
          '<g clip-path="url(#r)">'
          '<rect width="64" height="20" fill="#555"/>'
          '<rect x="64" width="43" height="20" fill="#02569b"/>'
          '<rect width="107" height="20" fill="url(#s)"/>'
          '</g>'
          '<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">'
          '<image x="5" y="3" width="14" height="14" href="data:image/svg+xml;base64,PHN2ZyBmaWxsPSJ3aGl0ZSIgcm9sZT0iaW1nIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHRpdGxlPkZsdXR0ZXI8L3RpdGxlPjxwYXRoIGQ9Ik0xNC4zMTQgMEwyLjMgMTIgNiAxNS43IDIxLjY4NC4wMTNoLTcuMzU3em0uMDE0IDExLjA3Mkw3Ljg1NyAxNy41M2w2LjQ3IDYuNDdIMjEuN2wtNi40Ni02LjQ2OCA2LjQ2LTYuNDZoLTcuMzd6Ii8+PC9zdmc+"/>'
          '<g transform="scale(.1)">'
          '<g aria-hidden="true" fill="#010101">'
          '<text x="415" y="150" fill-opacity=".8" filter="url(#blur)" textLength="370">Flutter</text>'
          '<text x="415" y="150" fill-opacity=".3" textLength="370">Flutter</text>'
          '</g>'
          '<text x="415" y="140" textLength="370">Flutter</text>'
          '</g>'
          '<g transform="scale(.1)">'
          '<g aria-hidden="true" fill="#010101">'
          '<text x="845" y="150" fill-opacity=".8" filter="url(#blur)" textLength="330">3.47+</text>'
          '<text x="845" y="150" fill-opacity=".3" textLength="330">3.47+</text>'
          '</g>'
          '<text x="845" y="140" textLength="330">3.47+</text>'
          '</g>'
          '</g>'
          '</svg>';

      final compiled = HtmlImageBuilder.compileSvgBadge(modernFlutterBadgeSvg);
      expect(compiled, isNotNull);
      expect(compiled!.compiledBytes, isNotEmpty);
      expect(compiled.width, 107.0);
      expect(compiled.height, 20.0);

      final instructions = vg.parseWithoutOptimizers(compiled.normalizedSvg);
      expect(instructions.text, hasLength(2));
      expect(instructions.textPositions, hasLength(4));
      for (final textConfig in instructions.text) {
        expect(textConfig.fontSize, closeTo(11.0, 0.01));
        expect(textConfig.fontFamily, 'Verdana');
      }
      expect(
        instructions.textPositions.map((p) => p.x).toSet(),
        containsAll(<double>[41.5, 84.5]),
      );
      expect(
        instructions.textPositions.map((p) => p.y).toSet(),
        containsAll(<double>[14.0, 15.0]),
      );
      // 3 badge background rects + 1 Flutter logo path = 4 paths
      expect(instructions.paths.length, greaterThanOrEqualTo(4));
    });
  });
}
