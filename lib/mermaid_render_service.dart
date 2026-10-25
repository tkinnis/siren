import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;
import 'package:webview_flutter/webview_flutter.dart';

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
  });

  /// The flattened, self-contained SVG markup.
  final String svg;

  /// Compiled binary vector_graphics payload for fast native rendering.
  final Uint8List compiledBytes;

  /// Natural logical dimensions (width, height) from the Mermaid viewBox.
  final Size logicalSize;

  /// Accessible label extracted from `accTitle` / `accDescr` if present.
  final String? semanticsLabel;
}

/// High-DPI raster PNG fallback for diagrams that cannot be flattened into pure SVG primitives.
final class MermaidRasterRender extends MermaidRenderResult {
  const MermaidRasterRender({
    required this.pngBytes,
    required this.logicalSize,
    this.semanticsLabel,
  });

  /// Encoded PNG image bytes (typically rendered at 3x scale for sharp zooming).
  final Uint8List pngBytes;

  /// Natural logical dimensions (width, height) from the Mermaid viewBox.
  final Size logicalSize;

  /// Accessible label extracted from `accTitle` / `accDescr` if present.
  final String? semanticsLabel;
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

/// Service that renders Mermaid diagrams offscreen using a single shared
/// headless [WebViewController], flattens/compiles them to native vector
/// graphics (or high-DPI PNG fallback), and caches results in memory.
class MermaidRenderService {
  MermaidRenderService._();

  /// Shared singleton instance used across the application.
  static final MermaidRenderService instance = MermaidRenderService._();

  static const int _maxCacheEntries = 128;
  static const Duration _renderTimeout = Duration(seconds: 20);
  static const double _defaultRasterScale = 3.0;

  /// Optional override used by tests to bypass platform WebView creation.
  @visibleForTesting
  MermaidRenderOverride? renderOverride;

  final LinkedHashMap<String, MermaidRenderResult> _cache =
      LinkedHashMap<String, MermaidRenderResult>();
  final Map<String, Future<MermaidRenderResult>> _inFlight =
      <String, Future<MermaidRenderResult>>{};
  final Queue<_QueuedJob> _queue = Queue<_QueuedJob>();

  _HeadlessMermaidEngine? _engine;
  Future<_PreparedMermaidPage>? _preparedPageFuture;
  bool _processingQueue = false;
  int _requestCounter = 0;

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

  /// Renders [code] offscreen (or returns from cache).
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
    if (override != null) {
      final future = override(code, isDark: isDark).then((result) {
        _inFlight.remove(key);
        _putCache(key, result);
        return result;
      });
      _inFlight[key] = future;
      return future;
    }

    final completer = Completer<MermaidRenderResult>();
    _inFlight[key] = completer.future;
    _queue.add(
      _QueuedJob(key: key, code: code, isDark: isDark, completer: completer),
    );
    _pumpQueue();
    return completer.future;
  }

  void _pumpQueue() {
    if (_processingQueue || _queue.isEmpty) {
      return;
    }
    _processingQueue = true;
    unawaited(_processQueueLoop());
  }

  Future<void> _processQueueLoop() async {
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        final cached = _cache[job.key];
        if (cached != null) {
          _inFlight.remove(job.key);
          if (!job.completer.isCompleted) {
            job.completer.complete(cached);
          }
          continue;
        }

        MermaidRenderResult result;
        try {
          result = await _executeJob(job);
        } catch (e) {
          result = MermaidFailureResult(
            kind: 'engineFailed',
            message: 'Failed to render Mermaid diagram: $e',
          );
        }

        _inFlight.remove(job.key);
        if (result is! MermaidFailureResult || result.kind == 'syntaxError') {
          _putCache(job.key, result);
        }
        if (!job.completer.isCompleted) {
          job.completer.complete(result);
        }
      }
    } finally {
      _processingQueue = false;
    }
  }

  Future<_PreparedMermaidPage> _loadPreparedPage() {
    final existing = _preparedPageFuture;
    if (existing != null) {
      return existing;
    }
    final future = _preparePageAssets();
    _preparedPageFuture = future;
    future.catchError((Object _) {
      if (identical(_preparedPageFuture, future)) {
        _preparedPageFuture = null;
      }
      return const _PreparedMermaidPage(bootstrapHtml: '', pieces: []);
    });
    return future;
  }

  Future<_PreparedMermaidPage> _preparePageAssets() async {
    final mermaidBytes = await rootBundle.load('assets/mermaid/mermaid.min.js');
    final mermaidUint8 = mermaidBytes.buffer.asUint8List(
      mermaidBytes.offsetInBytes,
      mermaidBytes.lengthInBytes,
    );
    final elkBytes = await rootBundle.load(
      'assets/mermaid/mermaid-layout-elk.min.js',
    );
    final elkUint8 = elkBytes.buffer.asUint8List(
      elkBytes.offsetInBytes,
      elkBytes.lengthInBytes,
    );
    final pageScript = await rootBundle.loadString(
      'assets/mermaid/mermaid_page.js',
    );
    return Isolate.run(
      () => _buildPreparedPageInIsolate(mermaidUint8, elkUint8, pageScript),
    );
  }

  Future<_HeadlessMermaidEngine> _ensureEngine() async {
    final current = _engine;
    if (current != null && !current.isDisposed) {
      return current;
    }
    final prepared = await _loadPreparedPage();
    final engine = _HeadlessMermaidEngine();
    try {
      await engine.initialize(prepared);
      _engine = engine;
      return engine;
    } catch (e) {
      await engine.dispose();
      rethrow;
    }
  }

  Future<void> _resetEngine() async {
    final old = _engine;
    _engine = null;
    await old?.dispose();
  }

  Future<MermaidRenderResult> _executeJob(_QueuedJob job) async {
    _HeadlessMermaidEngine engine;
    try {
      engine = await _ensureEngine();
    } catch (e) {
      return MermaidFailureResult(
        kind: 'engineFailed',
        message: 'Mermaid engine could not start: $e',
      );
    }

    // Attempt 1: Request flattened SVG (with automatic PNG fallback inside mermaid_page.js)
    Map<String, dynamic> response;
    try {
      response = await engine
          .requestRender(
            id: 'r${++_requestCounter}',
            source: job.code,
            isDark: job.isDark,
            raster: false,
            scale: _defaultRasterScale,
          )
          .timeout(_renderTimeout);
    } on TimeoutException {
      await _resetEngine();
      return const MermaidFailureResult(
        kind: 'timeout',
        message: 'Drawing the diagram timed out.',
      );
    } catch (e) {
      await _resetEngine();
      // Retry once with a fresh engine
      try {
        engine = await _ensureEngine();
        response = await engine
            .requestRender(
              id: 'r${++_requestCounter}',
              source: job.code,
              isDark: job.isDark,
              raster: false,
              scale: _defaultRasterScale,
            )
            .timeout(_renderTimeout);
      } catch (retryError) {
        await _resetEngine();
        return MermaidFailureResult(
          kind: 'engineFailed',
          message: 'The diagram engine stopped responding: $retryError',
        );
      }
    }

    final kind = response['kind'] as String?;
    if (kind == 'svg') {
      final svg = response['svg'] as String? ?? '';
      final width = (response['width'] as num?)?.toDouble() ?? 0;
      final height = (response['height'] as num?)?.toDouble() ?? 0;
      final label = response['label'] as String?;
      if (svg.isNotEmpty && width > 0 && height > 0) {
        try {
          final compiled = await Isolate.run(() => compileMermaidSvg(svg));
          return MermaidSvgRender(
            svg: svg,
            compiledBytes: compiled,
            logicalSize: Size(width, height),
            semanticsLabel: label,
          );
        } catch (compileError) {
          debugPrint(
            'Vector compilation failed, falling back to high-DPI PNG: $compileError',
          );
          // Fall through to explicit raster request below
        }
      }
      // Fallback: request high-DPI PNG from the same engine
      try {
        response = await engine
            .requestRender(
              id: 'r${++_requestCounter}',
              source: job.code,
              isDark: job.isDark,
              raster: true,
              scale: _defaultRasterScale,
            )
            .timeout(_renderTimeout);
      } catch (e) {
        await _resetEngine();
        return MermaidFailureResult(
          kind: 'engineFailed',
          message: 'Failed to rasterize diagram: $e',
        );
      }
    }

    final finalKind = response['kind'] as String?;
    if (finalKind == 'png') {
      final pngBase64 = response['png'] as String? ?? '';
      final width = (response['width'] as num?)?.toDouble() ?? 0;
      final height = (response['height'] as num?)?.toDouble() ?? 0;
      final label = response['label'] as String?;
      if (pngBase64.isNotEmpty && width > 0 && height > 0) {
        final pngBytes = await Isolate.run(() => base64Decode(pngBase64));
        return MermaidRasterRender(
          pngBytes: pngBytes,
          logicalSize: Size(width, height),
          semanticsLabel: label,
        );
      }
    }

    final failureKind = response['failure'] as String? ?? 'syntaxError';
    final detail = response['detail'] as String? ?? 'Could not render diagram.';
    return MermaidFailureResult(kind: failureKind, message: detail);
  }
}

class _QueuedJob {
  _QueuedJob({
    required this.key,
    required this.code,
    required this.isDark,
    required this.completer,
  });

  final String key;
  final String code;
  final bool isDark;
  final Completer<MermaidRenderResult> completer;
}

@immutable
class _PagePiece {
  const _PagePiece(this.name, this.literal);
  final String name;
  final String literal;
}

@immutable
class _PreparedMermaidPage {
  const _PreparedMermaidPage({
    required this.bootstrapHtml,
    required this.pieces,
  });

  final String bootstrapHtml;
  final List<_PagePiece> pieces;
}

/// Runs in a background isolate to decode `mermaid.min.js` and `mermaid-layout-elk.min.js`
/// and slice scripts into ASCII-safe JS string literal chunks so loading never stalls the UI isolate.
_PreparedMermaidPage _buildPreparedPageInIsolate(
  Uint8List mermaidScriptBytes,
  Uint8List elkScriptBytes,
  String pageScript,
) {
  final mermaidScript = utf8.decode(mermaidScriptBytes);
  final elkScript = utf8.decode(elkScriptBytes);
  final config = <String, Object?>{
    'family': 'Helvetica Neue',
    'faces': const <Object>[],
    'limits': const <String, int>{
      'maxSourceChars': 50000,
      'maxEdges': 500,
      'maxElements': 10000,
      'maxDepth': 64,
      'maxSvgChars': 4 * 1024 * 1024,
      'maxImageChars': 8 * 1024 * 1024,
      'maxImageSide': 4096,
      'maxImagePixels': 4096 * 4096,
      'maxSide': 8192,
      'maxPixels': 16 * 1024 * 1024,
      'maxPathChars': 256 * 1024,
      'maxTextChars': 2000,
      'maxDashEntries': 16,
      'minDashPeriod': 2,
      'maxDashSegments': 50000,
    },
  };

  final configJson = jsonEncode(config).replaceAll('<', r'\u003c');
  final bootstrapHtml =
      '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      overflow: hidden;
    }
  </style>
  <script type="application/json" id="finch-config">
$configJson
  </script>
  <script>
(function () {
  'use strict';
  var parts = {};
  function text(name) { return (parts[name] || []).join(''); }
  function run(name) {
    var script = document.createElement('script');
    script.textContent = text(name);
    document.head.appendChild(script);
  }
  Object.defineProperty(window, 'finchBoot', {
    configurable: true,
    value: Object.freeze({
      add: function (name, piece) {
        (parts[name] = parts[name] || []).push(piece);
      },
      commit: function () {
        run('mermaid');
        run('elk');
        run('page');
        delete window.finchBoot;
      }
    })
  });
})();
  </script>
</head>
<body></body>
</html>
''';

  return _PreparedMermaidPage(
    bootstrapHtml: bootstrapHtml,
    pieces: [
      ..._chunkScript('mermaid', mermaidScript),
      ..._chunkScript('elk', elkScript),
      ..._chunkScript('page', pageScript),
    ],
  );
}

const int _pieceChars = 192 * 1024;

List<_PagePiece> _chunkScript(String name, String text) {
  final pieces = <_PagePiece>[];
  var start = 0;
  while (start < text.length) {
    var end = start + _pieceChars;
    if (end >= text.length) {
      end = text.length;
    } else {
      final unit = text.codeUnitAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        end -= 1;
      }
    }
    pieces.add(_PagePiece(name, _jsAsciiLiteral(text.substring(start, end))));
    start = end;
  }
  return pieces;
}

String _jsAsciiLiteral(String text) {
  final out = StringBuffer('"');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case < 0x20 || > 0x7e:
        out
          ..write(r'\u')
          ..write(unit.toRadixString(16).padLeft(4, '0'));
      default:
        out.writeCharCode(unit);
    }
  }
  return (out..write('"')).toString();
}

/// Manages a single offscreen [WebViewController] that is never attached to a
/// widget tree.
class _HeadlessMermaidEngine {
  static const String _channelName = 'FinchMermaid';

  late final WebViewController _controller;
  final Completer<void> _pageLoaded = Completer<void>();
  final Completer<void> _engineReady = Completer<void>();

  Completer<Map<String, dynamic>>? _pendingRequest;
  String? _pendingRequestId;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future<void> initialize(_PreparedMermaidPage prepared) async {
    _controller = WebViewController();
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.addJavaScriptChannel(
      _channelName,
      onMessageReceived: (JavaScriptMessage message) {
        _handleChannelMessage(message.message);
      },
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!_pageLoaded.isCompleted) {
            _pageLoaded.complete();
          }
        },
        onWebResourceError: (WebResourceError error) {
          if (error.errorType ==
              WebResourceErrorType.webContentProcessTerminated) {
            _failPending('WebView content process terminated');
            dispose();
          }
        },
      ),
    );

    await _controller.loadHtmlString(prepared.bootstrapHtml);
    await _pageLoaded.future.timeout(const Duration(seconds: 15));

    for (final piece in prepared.pieces) {
      if (_disposed) {
        throw StateError('Mermaid engine disposed during initialization');
      }
      // Yield between chunks so UI frames are never starved
      await Future.delayed(Duration.zero);
      await _controller.runJavaScript(
        'finchBoot.add("${piece.name}",${piece.literal});',
      );
    }

    await Future.delayed(Duration.zero);
    await _controller.runJavaScript('finchBoot.commit();');
    await _engineReady.future.timeout(const Duration(seconds: 20));
  }

  void _handleChannelMessage(String rawMessage) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['kind'] == 'ready') {
        if (!_engineReady.isCompleted) {
          _engineReady.complete();
        }
        return;
      }

      final id = decoded['id'] as String?;
      final pending = _pendingRequest;
      if (id != null &&
          id == _pendingRequestId &&
          pending != null &&
          !pending.isCompleted) {
        _pendingRequest = null;
        _pendingRequestId = null;
        pending.complete(decoded);
      }
    } catch (e) {
      debugPrint('Error decoding Mermaid channel message: $e');
    }
  }

  Future<Map<String, dynamic>> requestRender({
    required String id,
    required String source,
    required bool isDark,
    required bool raster,
    required double scale,
  }) async {
    if (_disposed) {
      throw StateError('Mermaid engine has been disposed');
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequest = completer;
    _pendingRequestId = id;

    final payload = jsonEncode(<String, Object?>{
      'id': id,
      'source': source,
      'dark': isDark,
      'width': 1024,
      'scale': scale,
      'raster': raster,
    });

    await _controller.runJavaScript('window.finchMermaid.run($payload);');
    return completer.future;
  }

  void _failPending(String message) {
    final pending = _pendingRequest;
    _pendingRequest = null;
    _pendingRequestId = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError(message));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failPending('Mermaid engine disposed');
  }
}
