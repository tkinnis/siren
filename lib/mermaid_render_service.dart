import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pele_dart/pele_dart.dart' as pele;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

/// Result of rendering a Mermaid diagram offscreen.
@immutable
sealed class MermaidRenderResult {
  const MermaidRenderResult();
}

/// A flattened, vector-compiled Mermaid diagram that scales losslessly.
final class MermaidSvgRender extends MermaidRenderResult {
  const MermaidSvgRender({
    required this.svg,
    required this.compiledBytes,
    required this.logicalSize,
    this.semanticsLabel,
    this.diagramType,
    this.mermaidType,
    this.links = const <pele.LinkInfo>[],
  });

  /// The flattened, self-contained SVG 1.1 markup emitted by `pele_dart`.
  final String svg;

  /// Compiled binary `vector_graphics` payload for fast native rendering.
  final Uint8List compiledBytes;

  /// Natural logical dimensions (width, height) from the diagram viewBox.
  final Size logicalSize;

  /// Accessible label extracted from `aria-label` or diagram type if present.
  final String? semanticsLabel;

  /// Canonical `pele_dart` diagram family identifier (e.g. `'flowchart'`).
  final String? diagramType;

  /// Specific Mermaid header variant (e.g. `'flowchart-v2'`).
  final String? mermaidType;

  /// Interactive links extracted from the diagram.
  final List<pele.LinkInfo> links;
}

/// Failure details when a Mermaid diagram cannot be rendered.
final class MermaidFailureResult extends MermaidRenderResult {
  const MermaidFailureResult({required this.kind, required this.message});

  final String kind;
  final String message;
}

/// Signature for overriding diagram rendering in widget/unit tests.
typedef MermaidRenderOverride = Future<MermaidRenderResult> Function(
  String code, {
  required bool isDark,
});

/// Light mode `pele_dart` palette tuned to `SirenTheme` light tokens.
const pele.PelePalette lightMermaidPalette = pele.PelePalette(
  bg: '#f8f8fc',
  fg: '#1a1a2e',
  fgOnLight: '#1a1a2e',
  fgOnDark: '#f8f8fc',
  muted: '#5a5a78',
  line: '#3a3a52',
  surface: '#eef0f8',
  surfaceAlt: '#e4e6f0',
  border: '#9494b8',
  accent: '#00a080',
  code: '#e8e8f0',
  critical: '#e45756',
  colors: <String>[
    '#2060c0',
    '#00a080',
    '#8040a0',
    '#208050',
    '#c07000',
    '#e45756',
    '#4c78a8',
    '#b279a2',
  ],
);

/// Dark mode `pele_dart` palette tuned to `SirenTheme` dark tokens.
const pele.PelePalette darkMermaidPalette = pele.PelePalette(
  bg: '#141424',
  fg: '#e0e0f0',
  fgOnLight: '#1a1a2e',
  fgOnDark: '#e0e0f0',
  muted: '#9898b8',
  line: '#c8c8e0',
  surface: '#1e1e30',
  surfaceAlt: '#25253e',
  border: '#5c5c84',
  accent: '#00d4aa',
  code: '#25253e',
  critical: '#f87171',
  colors: <String>[
    '#6bb8ff',
    '#00d4aa',
    '#b86bff',
    '#6bffb8',
    '#ffb86b',
    '#f87171',
    '#72b7b2',
    '#f5c2e7',
  ],
);

/// Compiles flattened SVG XML into binary `vector_graphics` format.
Uint8List compileMermaidSvg(String svg) {
  return vg.encodeSvg(
    xml: svg,
    debugName: 'mermaid',
    theme: const vg.SvgTheme(),
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  );
}

final RegExp _ariaLabelRegex = RegExp(r'\baria-label="([^"]+)"');

String? _extractAriaLabel(String svg) {
  final match = _ariaLabelRegex.firstMatch(svg);
  if (match == null) return null;
  final raw = match.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// Pure-Dart helper that runs `pele_dart` layout + `vector_graphics_compiler`
/// encoding without any DOM or WebView dependencies.
MermaidRenderResult renderMermaidWithPele(String code, {required bool isDark}) {
  try {
    final palette = isDark ? darkMermaidPalette : lightMermaidPalette;
    final rendered = pele.render(
      code,
      pele.RenderOptions(
        outputMode: pele.SvgOutputMode.flattened,
        palette: palette,
      ),
    );
    final compiled = compileMermaidSvg(rendered.svg);
    final label = _extractAriaLabel(rendered.svg) ?? '${rendered.type} diagram';
    return MermaidSvgRender(
      svg: rendered.svg,
      compiledBytes: compiled,
      logicalSize: Size(rendered.width, rendered.height),
      semanticsLabel: label,
      diagramType: rendered.type,
      mermaidType: rendered.mermaidType,
      links: rendered.links,
    );
  } on pele.PeleError catch (e) {
    return MermaidFailureResult(kind: e.code, message: e.message);
  } catch (e) {
    return MermaidFailureResult(
      kind: 'engineFailed',
      message: 'Failed to render Mermaid diagram: $e',
    );
  }
}

typedef _TransferableSvgReply = (
  int,
  String,
  TransferableTypedData,
  double,
  double,
  String?,
  String?,
  String?,
  List<pele.LinkInfo>,
);

void _mermaidWorkerMain(SendPort initPort) {
  final commandPort = ReceivePort();
  // Warm up pele_dart's diagram registry, dagre layout engine, and
  // vector_graphics_compiler inside the persistent worker isolate.
  renderMermaidWithPele('flowchart LR\n  A --> B', isDark: false);
  initPort.send(commandPort.sendPort);

  commandPort.listen((dynamic message) {
    if (message is (int, String, bool, SendPort)) {
      final (id, code, isDark, replyPort) = message;
      final result = renderMermaidWithPele(code, isDark: isDark);
      if (result is MermaidSvgRender) {
        final reply = (
          id,
          result.svg,
          TransferableTypedData.fromList(<Uint8List>[result.compiledBytes]),
          result.logicalSize.width,
          result.logicalSize.height,
          result.semanticsLabel,
          result.diagramType,
          result.mermaidType,
          result.links,
        );
        replyPort.send(reply);
      } else {
        replyPort.send((id, result));
      }
    }
  });
}

class _MermaidIsolateWorker {
  static const int _poolSize = 2;

  static Future<List<SendPort>>? _workerPoolFuture;
  static ReceivePort? _replyPort;
  static int _nextRequestId = 0;
  static int _nextWorkerIndex = 0;
  static final Map<int, Completer<MermaidRenderResult>> _pending =
      <int, Completer<MermaidRenderResult>>{};

  static Future<SendPort> _spawnOneWorker(int index) {
    final completer = Completer<SendPort>();
    final initPort = RawReceivePort((dynamic message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
      }
    });

    Isolate.spawn(
      _mermaidWorkerMain,
      initPort.sendPort,
      debugName: 'SirenMermaidWorker-$index',
    ).then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        initPort.close();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    return completer.future.whenComplete(initPort.close);
  }

  static Future<List<SendPort>> ensureInitialized() {
    final existing = _workerPoolFuture;
    if (existing != null) return existing;

    final future =
        Future.wait<SendPort>(<Future<SendPort>>[
          for (var i = 0; i < _poolSize; i++) _spawnOneWorker(i),
        ]).catchError((Object error) {
          _workerPoolFuture = null;
          throw error;
        });
    _workerPoolFuture = future;
    return future;
  }

  static void _ensureReplyPort() {
    if (_replyPort != null) return;
    final port = ReceivePort();
    _replyPort = port;
    port.listen((dynamic message) {
      int? id;
      MermaidRenderResult? result;
      if (message is _TransferableSvgReply) {
        final (
          msgId,
          svg,
          transferableBytes,
          width,
          height,
          semanticsLabel,
          diagramType,
          mermaidType,
          links,
        ) = message;
        id = msgId;
        result = MermaidSvgRender(
          svg: svg,
          compiledBytes: transferableBytes.materialize().asUint8List(),
          logicalSize: Size(width, height),
          semanticsLabel: semanticsLabel,
          diagramType: diagramType,
          mermaidType: mermaidType,
          links: links,
        );
      } else if (message is (int, MermaidRenderResult)) {
        final (msgId, msgResult) = message;
        id = msgId;
        result = msgResult;
      }
      if (id != null && result != null) {
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(result);
        }
        if (_pending.isEmpty) {
          _replyPort?.close();
          _replyPort = null;
        }
      }
    });
  }

  static Future<MermaidRenderResult> render(
    String code, {
    required bool isDark,
  }) async {
    final workerPorts = await ensureInitialized();
    _ensureReplyPort();
    final requestId = ++_nextRequestId;
    final workerPort = workerPorts[_nextWorkerIndex % workerPorts.length];
    _nextWorkerIndex = (_nextWorkerIndex + 1) % workerPorts.length;
    final completer = Completer<MermaidRenderResult>();
    _pending[requestId] = completer;
    workerPort.send((requestId, code, isDark, _replyPort!.sendPort));
    return completer.future;
  }
}

/// Renders and compiles [code] with `pele_dart` on a persistent, pre-warmed
/// background worker isolate.
Future<MermaidRenderResult> renderMermaidInIsolate(
  String code, {
  required bool isDark,
}) {
  return _MermaidIsolateWorker.render(code, isDark: isDark);
}

/// Service that renders Mermaid diagrams in pure Dart using `pele_dart`,
/// compiles them to native `vector_graphics` bytecode, and caches results
/// in an in-memory LRU cache.
class MermaidRenderService {
  MermaidRenderService._();

  /// Shared singleton instance used across the application.
  static final MermaidRenderService instance = MermaidRenderService._();

  static const int _maxCacheEntries = 128;

  /// Optional override used by tests to customize diagram rendering.
  @visibleForTesting
  MermaidRenderOverride? renderOverride;

  final LinkedHashMap<String, MermaidRenderResult> _cache =
      LinkedHashMap<String, MermaidRenderResult>();
  final Map<String, Future<MermaidRenderResult>> _inFlight =
      <String, Future<MermaidRenderResult>>{};

  /// Pre-spawns and JIT-warms the persistent background worker isolate so the
  /// first diagram document opens without cold isolate startup overhead.
  Future<void> warmUp() async {
    await _MermaidIsolateWorker.ensureInitialized();
  }

  String _cacheKey(String code, bool isDark) =>
      '${isDark ? 'dark' : 'light'}|${code.trim()}';

  /// Synchronously returns a cached [MermaidRenderResult] if available.
  MermaidRenderResult? peek(String code, {required bool isDark}) {
    final key = _cacheKey(code, isDark);
    final existing = _cache.remove(key);
    if (existing != null) {
      // Refresh LRU order
      _cache[key] = existing;
    }
    return existing;
  }

  void _putCache(String key, MermaidRenderResult result) {
    _cache.remove(key);
    _cache[key] = result;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Clears the in-memory diagram cache.
  void clearCache() {
    _cache.clear();
  }

  /// Synchronously renders and compiles [code] using `pele_dart` (or returns
  /// from cache).
  MermaidRenderResult renderSync(String code, {required bool isDark}) {
    final cached = peek(code, isDark: isDark);
    if (cached != null) {
      return cached;
    }
    final key = _cacheKey(code, isDark);
    final result = renderMermaidWithPele(code, isDark: isDark);
    _putCache(key, result);
    return result;
  }

  /// Renders [code] off the UI isolate (or returns from cache).
  Future<MermaidRenderResult> render(String code, {required bool isDark}) {
    final cached = peek(code, isDark: isDark);
    if (cached != null) {
      return SynchronousFuture<MermaidRenderResult>(cached);
    }

    final key = _cacheKey(code, isDark);
    final existingFuture = _inFlight[key];
    if (existingFuture != null) {
      return existingFuture;
    }

    final override = renderOverride;
    final Future<MermaidRenderResult> computeFuture = override != null
        ? override(code, isDark: isDark)
        : renderMermaidInIsolate(code, isDark: isDark);

    final future = computeFuture.then((result) {
      _inFlight.remove(key);
      _putCache(key, result);
      return result;
    });
    _inFlight[key] = future;
    return future;
  }
}

/// All 33 diagram families rendered as native vector SVGs (`vector_graphics`)
/// via `pele_dart`.
const Set<String> mermaidMacosSvgTypes = {
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
