import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'mermaid_render_service.dart';
import 'mermaid_zoom_dialog.dart';
import 'theme.dart';

class MermaidDiagram extends StatefulWidget {
  final String code;
  final bool isDark;
  final double fontSize;
  final MermaidRenderService? service;

  const MermaidDiagram({
    super.key,
    required this.code,
    required this.isDark,
    this.fontSize = 14.0,
    this.service,
  });

  /// Base font size in Siren used to compute the proportional diagram scale factor.
  static const double baseFontSize = 14.0;

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  MermaidRenderResult? _result;
  bool _isHovered = false;
  int _generation = 0;

  MermaidRenderService get _service =>
      widget.service ?? MermaidRenderService.instance;

  double get _scaleFactor =>
      (widget.fontSize / MermaidDiagram.baseFontSize).clamp(0.5, 4.0);

  @override
  void initState() {
    super.initState();
    _loadDiagram();
  }

  @override
  void didUpdateWidget(covariant MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.isDark != widget.isDark ||
        oldWidget.service != widget.service) {
      _loadDiagram();
    }
  }

  void _loadDiagram() {
    final generation = ++_generation;
    final cached = _service.peek(widget.code, isDark: widget.isDark);
    if (cached != null) {
      _result = cached;
      return;
    }

    _service.render(widget.code, isDark: widget.isDark).then((result) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = result;
      });
    });
  }

  void _openZoomDialog(MermaidRenderResult result) {
    if (result is MermaidFailureResult) return;
    MermaidZoomDialog.show(
      context,
      result: result,
      code: widget.code,
      isDark: widget.isDark,
    );
  }

  void _copySource() {
    final cleanCode = widget.code.endsWith('\n')
        ? widget.code.substring(0, widget.code.length - 1)
        : widget.code;
    Clipboard.setData(ClipboardData(text: cleanCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mermaid source copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>()!;
    final containerBg =
        sirenColors.codeBlockBg ??
        sirenColors.codeBg ??
        theme.colorScheme.surface;
    final borderColor = sirenColors.divider ?? theme.colorScheme.outline;

    final result = _result;
    if (result == null) {
      return _buildPlaceholder(containerBg, borderColor, theme);
    }

    return switch (result) {
      MermaidFailureResult(:final message) => _buildFailureBlock(
        containerBg: containerBg,
        borderColor: borderColor,
        sirenColors: sirenColors,
        theme: theme,
        message: message,
      ),
      MermaidSvgRender(:final logicalSize) ||
      MermaidRasterRender(:final logicalSize) => _buildRenderedDiagram(
        result: result,
        logicalSize: logicalSize,
        containerBg: containerBg,
        borderColor: borderColor,
        sirenColors: sirenColors,
        theme: theme,
      ),
    };
  }

  Widget _buildRenderedDiagram({
    required MermaidRenderResult result,
    required Size logicalSize,
    required Color containerBg,
    required Color borderColor,
    required SirenColors sirenColors,
    required ThemeData theme,
  }) {
    final scaledSize = Size(
      logicalSize.width * _scaleFactor,
      logicalSize.height * _scaleFactor,
    );

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          key: const Key('mermaid_diagram_tap_target'),
          onTap: () => _openZoomDialog(result),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12.0),
            decoration: BoxDecoration(
              color: containerBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.6)
                    : borderColor,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        key: const Key('mermaid_scaled_box'),
                        width: scaledSize.width,
                        height: scaledSize.height,
                        child: MermaidGraphic(result: result, size: scaledSize),
                      ),
                    ),
                  ),
                ),
                if (_isHovered)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            (sirenColors.codeBlockHeaderBg ??
                                    sirenColors.sidebarBg ??
                                    containerBg)
                                .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Zoom & Pan Diagram',
                            child: InkWell(
                              key: const Key('mermaid_expand_button'),
                              onTap: () => _openZoomDialog(result),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.open_in_full_rounded,
                                      size: 13,
                                      color: sirenColors.iconColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Zoom',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: sirenColors.iconColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 16, color: borderColor),
                          Tooltip(
                            message: 'Copy Mermaid Source',
                            child: InkWell(
                              key: const Key('mermaid_copy_source_button'),
                              onTap: _copySource,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: sirenColors.iconColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    Color containerBg,
    Color borderColor,
    ThemeData theme,
  ) {
    return Container(
      key: const Key('mermaid_loading_placeholder'),
      height: 120,
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Center(
        child: Text(
          'Drawing diagram...',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildFailureBlock({
    required Color containerBg,
    required Color borderColor,
    required SirenColors sirenColors,
    required ThemeData theme,
    required String message,
  }) {
    final cleanCode = widget.code.endsWith('\n')
        ? widget.code.substring(0, widget.code.length - 1)
        : widget.code;

    return Container(
      key: const Key('mermaid_failure_block'),
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sirenColors.codeBlockHeaderBg ?? sirenColors.sidebarBg,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MERMAID',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: sirenColors.iconColor,
                  ),
                ),
                InkWell(
                  onTap: _copySource,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: sirenColors.iconColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              cleanCode,
              style: GoogleFonts.firaCode(
                fontSize: widget.fontSize * 0.9,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
              color: theme.colorScheme.error.withValues(alpha: 0.08),
            ),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
