import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:pele_dart/pele_dart.dart' as pele;
import 'package:provider/provider.dart';
import 'package:siren/app_state.dart';
import 'package:siren/mermaid_zoom_dialog.dart';
import 'package:siren/rendered_view.dart';
import 'package:siren/siren_image_builder.dart';
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

const Set<String> _expectedPeleFamilies = <String>{
  'agentflow',
  'architecture',
  'block',
  'c4',
  'class',
  'cynefin',
  'er',
  'eventmodeling',
  'flowchart',
  'gantt',
  'gitGraph',
  'info',
  'ishikawa',
  'journey',
  'kanban',
  'mindmap',
  'packet',
  'pie',
  'quadrantChart',
  'radar',
  'railroad',
  'requirement',
  'sankey',
  'sequence',
  'state',
  'swimlane',
  'timeline',
  'treeView',
  'treemap',
  'usecase',
  'venn',
  'wardley',
  'xychart',
};

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
  void increaseFontSize() {
    fontSize = (fontSize + 2.0).clamp(8.0, 48.0);
    notifyListeners();
  }

  @override
  void decreaseFontSize() {
    fontSize = (fontSize - 2.0).clamp(8.0, 48.0);
    notifyListeners();
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
    compiledSampleBytes = vg.encodeSvg(
      xml: _sampleSvg,
      debugName: 'test_sample_svg',
      theme: const vg.SvgTheme(),
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
  });

  setUp(() {
    MarkdownBuiltInRenderers.clearCaches();
  });

  tearDown(() {
    MarkdownBuiltInRenderers.clearCaches();
  });

  group('RenderedView Mermaid Rendering & Scaling', () {
    testWidgets(
      'renders Mermaid diagram via VectorGraphic in light and dark themes',
      (WidgetTester tester) async {
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

        expect(tester.takeException(), isNull);
        final vgFinder = find.byType(VectorGraphic);
        expect(vgFinder, findsOneWidget);
        expect(
          tester.widget<VectorGraphic>(vgFinder).strategy,
          RenderingStrategy.picture,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.dark,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(body: RenderedView(filePath: 'diagram.md')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(VectorGraphic), findsOneWidget);
      },
    );

    testWidgets(
      'scales Mermaid diagram inside RenderedView when AppState fontSize changes',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

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

        final initialSize = tester.getSize(find.byType(VectorGraphic));
        expect(initialSize.width, greaterThan(0));
        expect(initialSize.height, greaterThan(0));

        // Increase font size from 14 -> 20
        appState.increaseFontSize();
        appState.increaseFontSize();
        appState.increaseFontSize();
        await tester.pumpAndSettle();

        final enlargedSize = tester.getSize(find.byType(VectorGraphic));
        expect(
          enlargedSize.width,
          closeTo(initialSize.width * (20.0 / 14.0), 0.5),
        );
        expect(
          enlargedSize.height,
          closeTo(initialSize.height * (20.0 / 14.0), 0.5),
        );

        // Reset font size back to 14
        appState.resetFontSize();
        await tester.pumpAndSettle();

        final resetSize = tester.getSize(find.byType(VectorGraphic));
        expect(resetSize.width, closeTo(initialSize.width, 0.5));
        expect(resetSize.height, closeTo(initialSize.height, 0.5));
      },
    );

    testWidgets('renders fallback card when Mermaid syntax is invalid', (
      WidgetTester tester,
    ) async {
      final appState = _FakeAppState()
        ..currentContent = '```mermaid\nnot_a_mermaid_diagram\n  foo bar\n```';

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

      expect(tester.takeException(), isNull);
      expect(find.byType(VectorGraphic), findsNothing);
      expect(
        find.textContaining('not_a_mermaid_diagram', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('MermaidZoomDialog Interactive Zoom, Pan, Copy & Export', () {
    testWidgets(
      'tapping Mermaid diagram in RenderedView opens MermaidZoomDialog with zoom and copy controls',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

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

        final appState = _FakeAppState()
          ..currentContent = '```mermaid\ngraph TD\n  Start --> Stop\n```';

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

        expect(find.byType(MermaidZoomDialog), findsNothing);
        expect(find.byType(VectorGraphic), findsOneWidget);

        await tester.tap(find.byType(VectorGraphic).first);
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

        await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('mermaid_zoom_out_button')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mermaid_zoom_in_button')));
        await tester.pumpAndSettle();
        expect(find.text('156%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('mermaid_zoom_reset_pill')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const Key('mermaid_zoom_copy_button')));
        await tester.pump();
        expect(copiedTexts, <String>['graph TD\n  Start --> Stop']);

        await tester.tap(find.byKey(const Key('mermaid_zoom_close_button')));
        await tester.pumpAndSettle();
        expect(find.byType(MermaidZoomDialog), findsNothing);
      },
    );

    testWidgets(
      'MermaidZoomDialog and MermaidGraphic accept MarkdownMermaidDiagram directly',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final diagram = MarkdownMermaidDiagram(
          code: 'flowchart LR\n  A --> B',
          compiledBytes: compiledSampleBytes,
          svg: _sampleSvg,
          logicalSize: const Size(240, 120),
          semanticsLabel: 'Sample flowchart diagram',
          brightness: Brightness.dark,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      MermaidZoomDialog.show(context, diagram: diagram),
                  child: const Text('Open Diagram'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Diagram'));
        await tester.pumpAndSettle();

        expect(find.byType(MermaidZoomDialog), findsOneWidget);
        expect(find.byType(MermaidGraphic), findsOneWidget);
        expect(find.byType(VectorGraphic), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(MermaidZoomDialog), findsNothing);
      },
    );
  });

  group('SirenImageBuilder SVG Badge Compilation & Payload Detection', () {
    test('compileSvgBadge compiles modern Shields.io SVG badges with 11px scaled text and inlined base64 logos', () {
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

      final compiled = SirenImageBuilder.compileSvgBadge(modernFlutterBadgeSvg);
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
      expect(instructions.paths.length, greaterThanOrEqualTo(4));
    });

    test('isSvgPayload detects SVG by Content-Type or bytes and rejects binary raster magic bytes', () {
      final rawSvgBytes = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
      );
      final xmlPrologSvgBytes = Uint8List.fromList(
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>\n<svg viewBox="0 0 100 20"></svg>',
        ),
      );
      final pngMagicBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);

      expect(
        SirenImageBuilder.isSvgPayload(
          contentType: 'image/svg+xml; charset=utf-8',
          bytes: rawSvgBytes,
        ),
        isTrue,
      );
      expect(
        SirenImageBuilder.isSvgPayload(
          contentType: 'application/octet-stream',
          bytes: xmlPrologSvgBytes,
        ),
        isTrue,
      );
      expect(
        SirenImageBuilder.isSvgPayload(
          contentType: 'image/png',
          bytes: pngMagicBytes,
        ),
        isFalse,
      );
    });
  });

  group('docs/mermaid-examples.md Parse & Render Verification', () {
    test('parses all Mermaid code blocks via MarkdownEngine and renders all 33 families', () {
      final examplesMd = File('docs/mermaid-examples.md').readAsStringSync();
      final document = const MarkdownEngine().parse(examplesMd);
      final mermaidBlocks = document.blocks
          .whereType<CodeBlockNode>()
          .where((b) => b.language?.toLowerCase() == 'mermaid')
          .toList();

      expect(mermaidBlocks.length, greaterThanOrEqualTo(50));

      final renderedFamilies = <String>{};
      for (var i = 0; i < mermaidBlocks.length; i++) {
        final result = pele.render(
          mermaidBlocks[i].literal,
          const pele.RenderOptions(outputMode: pele.SvgOutputMode.flattened),
        );
        final encoded = vg.encodeSvg(
          xml: result.svg,
          debugName: 'doc_mermaid_$i',
          theme: const vg.SvgTheme(),
          enableClippingOptimizer: false,
          enableMaskingOptimizer: false,
          enableOverdrawOptimizer: false,
        );
        expect(encoded, isNotEmpty);
        renderedFamilies.add(result.type);
      }

      expect(
        renderedFamilies,
        equals(_expectedPeleFamilies),
        reason: 'docs/mermaid-examples.md must cover all 33 pele_dart families',
      );
    });

    testWidgets(
      'renders docs/mermaid-examples.md inside RenderedView cleanly',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final examplesMd = File('docs/mermaid-examples.md').readAsStringSync();
        final appState = _FakeAppState()..currentContent = examplesMd;

        await tester.pumpWidget(
          MaterialApp(
            theme: SirenTheme.light,
            home: ChangeNotifierProvider<AppState>.value(
              value: appState,
              child: const Scaffold(
                body: RenderedView(filePath: 'docs/mermaid-examples.md'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(VectorGraphic), findsWidgets);
      },
    );
  });
}
