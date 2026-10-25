import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vector_graphics/vector_graphics.dart';

import 'mermaid_render_service.dart';
import 'theme.dart';

/// A [BytesLoader] that supplies pre-compiled `vector_graphics` bytes from memory.
class CompiledMermaidBytesLoader extends BytesLoader {
  const CompiledMermaidBytesLoader(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) =>
      SynchronousFuture<ByteData>(ByteData.sublistView(bytes));

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  bool operator ==(Object other) =>
      other is CompiledMermaidBytesLoader && listEquals(bytes, other.bytes);
}

/// Renders the visual graphic for a [MermaidSvgRender] or [MermaidRasterRender]
/// at the specified [size].
class MermaidGraphic extends StatelessWidget {
  const MermaidGraphic({super.key, required this.result, required this.size});

  final MermaidRenderResult result;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      MermaidSvgRender(:final compiledBytes, :final semanticsLabel) =>
        VectorGraphic(
          loader: CompiledMermaidBytesLoader(compiledBytes),
          width: size.width,
          height: size.height,
          fit: BoxFit.contain,
          semanticsLabel: semanticsLabel ?? 'Mermaid diagram',
        ),
      MermaidRasterRender(:final pngBytes, :final semanticsLabel) =>
        Image.memory(
          pngBytes,
          width: size.width,
          height: size.height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          semanticLabel: semanticsLabel ?? 'Mermaid diagram',
          gaplessPlayback: true,
        ),
      MermaidFailureResult() => const SizedBox.shrink(),
    };
  }
}

/// Modal dialog that allows interactive panning and zooming of a rendered
/// Mermaid diagram.
class MermaidZoomDialog extends StatefulWidget {
  const MermaidZoomDialog({
    super.key,
    required this.result,
    required this.code,
    required this.isDark,
  });

  final MermaidRenderResult result;
  final String code;
  final bool isDark;

  /// Opens the interactive zoom/pan modal dialog for [result].
  static Future<void> show(
    BuildContext context, {
    required MermaidRenderResult result,
    required String code,
    required bool isDark,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          MermaidZoomDialog(result: result, code: code, isDark: isDark),
    );
  }

  @override
  State<MermaidZoomDialog> createState() => _MermaidZoomDialogState();
}

class _MermaidZoomDialogState extends State<MermaidZoomDialog> {
  static const double _minScale = 0.1;
  static const double _maxScale = 10.0;
  static const double _zoomStep = 1.25;

  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _graphicBoundaryKey = GlobalKey();
  double _currentScale = 1.0;
  bool _isDragging = false;
  bool _copied = false;
  bool _copiedImage = false;
  Timer? _copiedResetTimer;
  Timer? _copiedImageResetTimer;

  Size get _logicalSize => switch (widget.result) {
    MermaidSvgRender(:final logicalSize) => logicalSize,
    MermaidRasterRender(:final logicalSize) => logicalSize,
    MermaidFailureResult() => const Size(400, 300),
  };

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    _copiedImageResetTimer?.cancel();
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.005 && mounted) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  Size _getViewportSize() {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.size;
    }
    return const Size(800, 600);
  }

  void _zoomBy(double factor) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final actualFactor = targetScale / currentScale;
    if ((actualFactor - 1.0).abs() < 1e-4) return;

    final viewportSize = _getViewportSize();
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);

    final matrix = Matrix4.copy(_transformationController.value);
    // Zoom around the center of the viewport
    final translateToOrigin = Matrix4.translationValues(
      center.dx,
      center.dy,
      0,
    );
    final scaleMatrix = Matrix4.diagonal3Values(
      actualFactor,
      actualFactor,
      1.0,
    );
    final translateBack = Matrix4.translationValues(-center.dx, -center.dy, 0);

    _transformationController.value =
        translateToOrigin * scaleMatrix * translateBack * matrix;
  }

  void _zoomIn() => _zoomBy(_zoomStep);

  void _zoomOut() => _zoomBy(1.0 / _zoomStep);

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _copySource() {
    final cleanCode = widget.code.endsWith('\n')
        ? widget.code.substring(0, widget.code.length - 1)
        : widget.code;
    Clipboard.setData(ClipboardData(text: cleanCode));
    _copiedResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  Future<Uint8List?> _capturePngBytes() async {
    if (widget.result case MermaidRasterRender(:final pngBytes)) {
      return pngBytes;
    }
    try {
      final boundary = _graphicBoundaryKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (byteData != null) {
          return byteData.buffer.asUint8List();
        }
      }
    } catch (e) {
      debugPrint('Failed to capture Mermaid PNG bytes: $e');
    }
    return null;
  }

  Future<void> _copyImage() async {
    final pngBytes = await _capturePngBytes();
    if (pngBytes == null) return;

    try {
      if (Platform.isMacOS) {
        final tempFile = File(
          '${Directory.systemTemp.path}/siren_mermaid_clipboard_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await tempFile.writeAsBytes(pngBytes, flush: true);
        try {
          await Process.run('osascript', [
            '-e',
            'set the clipboard to (read (POSIX file "${tempFile.path}") as «class PNGf»)',
          ]);
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      }
      _copiedImageResetTimer?.cancel();
      if (mounted) {
        setState(() {
          _copiedImage = true;
        });
      }
      _copiedImageResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _copiedImage = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to copy image to clipboard: $e');
    }
  }

  Future<void> _exportDiagram() async {
    final hasSvg = widget.result is MermaidSvgRender;
    final typeGroups = <XTypeGroup>[
      const XTypeGroup(label: 'PNG Image', extensions: <String>['png']),
      if (hasSvg)
        const XTypeGroup(label: 'SVG Vector', extensions: <String>['svg']),
    ];

    final saveLocation = await getSaveLocation(
      suggestedName: hasSvg ? 'mermaid-diagram.svg' : 'mermaid-diagram.png',
      acceptedTypeGroups: typeGroups,
    );
    if (saveLocation == null) return;

    try {
      final targetPath = saveLocation.path;
      if (targetPath.toLowerCase().endsWith('.svg') &&
          widget.result is MermaidSvgRender) {
        final svgContent = (widget.result as MermaidSvgRender).svg;
        await File(targetPath).writeAsString(svgContent, flush: true);
      } else {
        final pngBytes = await _capturePngBytes();
        if (pngBytes != null) {
          await File(targetPath).writeAsBytes(pngBytes, flush: true);
        }
      }
    } catch (e) {
      debugPrint('Failed to export Mermaid diagram: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>()!;
    final screenSize = MediaQuery.sizeOf(context);

    final dialogWidth = math.max(
      320.0,
      math.min(screenSize.width * 0.88, 1400.0),
    );
    final dialogHeight = math.max(
      260.0,
      math.min(screenSize.height * 0.86, 960.0),
    );

    final canvasBg = sirenColors.codeBlockBg ?? theme.colorScheme.surface;
    final headerBg =
        sirenColors.codeBlockHeaderBg ?? sirenColors.sidebarBg ?? canvasBg;
    final borderColor = sirenColors.divider ?? theme.colorScheme.outline;

    final zoomPercent = (_currentScale * 100).round();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.equal, meta: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.add, meta: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.equal): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.minus, meta: true): _zoomOut,
          const SingleActivator(LogicalKeyboardKey.minus): _zoomOut,
          const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
              _resetZoom,
          const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Container(
              decoration: BoxDecoration(
                color: canvasBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Toolbar
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: headerBg,
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_tree_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Diagram Viewer',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Drag to pan • Scroll or pinch to zoom',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // Zoom Out
                        IconButton(
                          key: const Key('mermaid_zoom_out_button'),
                          icon: const Icon(Icons.remove_rounded, size: 18),
                          tooltip: 'Zoom Out (Cmd+-)',
                          visualDensity: VisualDensity.compact,
                          onPressed: _currentScale > _minScale
                              ? _zoomOut
                              : null,
                        ),
                        // Zoom percentage indicator / Reset button
                        Tooltip(
                          message: 'Reset Zoom to 100% (Cmd+0)',
                          child: InkWell(
                            key: const Key('mermaid_zoom_reset_pill'),
                            onTap: _resetZoom,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 54),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: canvasBg.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '$zoomPercent%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Zoom In
                        IconButton(
                          key: const Key('mermaid_zoom_in_button'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          tooltip: 'Zoom In (Cmd+=)',
                          visualDensity: VisualDensity.compact,
                          onPressed: _currentScale < _maxScale ? _zoomIn : null,
                        ),
                        // Fit to screen button
                        IconButton(
                          key: const Key('mermaid_zoom_fit_button'),
                          icon: const Icon(Icons.fit_screen_rounded, size: 18),
                          tooltip: 'Fit to View (Cmd+0)',
                          visualDensity: VisualDensity.compact,
                          onPressed: _resetZoom,
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 20, color: borderColor),
                        const SizedBox(width: 4),
                        // Copy diagram image button
                        IconButton(
                          key: const Key('mermaid_zoom_copy_image_button'),
                          icon: Icon(
                            _copiedImage
                                ? Icons.check_rounded
                                : Icons.image_outlined,
                            size: 16,
                            color: _copiedImage
                                ? theme.colorScheme.primary
                                : sirenColors.iconColor,
                          ),
                          tooltip: _copiedImage
                              ? 'Image Copied!'
                              : 'Copy Diagram Image (PNG)',
                          visualDensity: VisualDensity.compact,
                          onPressed: _copyImage,
                        ),
                        // Export diagram (SVG/PNG) button
                        IconButton(
                          key: const Key('mermaid_zoom_export_button'),
                          icon: Icon(
                            Icons.download_rounded,
                            size: 17,
                            color: sirenColors.iconColor,
                          ),
                          tooltip: 'Export Diagram (SVG / PNG)...',
                          visualDensity: VisualDensity.compact,
                          onPressed: _exportDiagram,
                        ),
                        // Copy source button
                        IconButton(
                          key: const Key('mermaid_zoom_copy_button'),
                          icon: Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 16,
                            color: _copied
                                ? theme.colorScheme.primary
                                : sirenColors.iconColor,
                          ),
                          tooltip: _copied ? 'Copied!' : 'Copy Mermaid Source',
                          visualDensity: VisualDensity.compact,
                          onPressed: _copySource,
                        ),
                        const SizedBox(width: 4),
                        // Close button
                        IconButton(
                          key: const Key('mermaid_zoom_close_button'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Close (Esc)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  // Interactive Pan/Zoom Viewport
                  Expanded(
                    child: MouseRegion(
                      cursor: _isDragging
                          ? SystemMouseCursors.grabbing
                          : SystemMouseCursors.grab,
                      child: GestureDetector(
                        onDoubleTap: () {
                          if ((_currentScale - 1.0).abs() < 0.1) {
                            _zoomBy(2.0);
                          } else {
                            _resetZoom();
                          }
                        },
                        child: InteractiveViewer(
                          key: _viewportKey,
                          transformationController: _transformationController,
                          panEnabled: true,
                          scaleEnabled: true,
                          minScale: _minScale,
                          maxScale: _maxScale,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          onInteractionStart: (_) {
                            setState(() => _isDragging = true);
                          },
                          onInteractionEnd: (_) {
                            setState(() => _isDragging = false);
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: RepaintBoundary(
                                  key: _graphicBoundaryKey,
                                  child: SizedBox.fromSize(
                                    size: _logicalSize,
                                    child: MermaidGraphic(
                                      result: widget.result,
                                      size: _logicalSize,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
