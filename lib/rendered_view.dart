import 'dart:async';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'mermaid_zoom_dialog.dart';
import 'siren_image_builder.dart';
import 'theme.dart';

class RenderedView extends StatefulWidget {
  final String filePath;
  const RenderedView({super.key, required this.filePath});

  @override
  State<RenderedView> createState() => _RenderedViewState();
}

class _RenderedViewState extends State<RenderedView> {
  static const MarkdownUrlPolicy _sirenUrlPolicy = MarkdownUrlPolicy(
    allowedSchemes: <String>{'http', 'https', 'mailto', 'file'},
    allowRelative: true,
    allowFragments: true,
    allowSafeImageDataUrls: true,
  );

  final ScrollController _scrollController = ScrollController();
  final MarkdownController _markdownController = MarkdownController();
  StreamSubscription<({int lineNumber, String text})>? _navSubscription;

  @override
  void initState() {
    super.initState();
    _restoreScrollPosition();
  }

  @override
  void didUpdateWidget(RenderedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _restoreScrollPosition();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navSubscription?.cancel();
    final appState = context.read<AppState>();
    _navSubscription = appState.navigationStream.listen((event) {
      if (!mounted) return;
      if (event.text.isNotEmpty) {
        unawaited(_navigateToTarget(event.text, event.lineNumber));
      } else {
        unawaited(_markdownController.scrollToLine(event.lineNumber + 1));
      }
    });
  }

  Future<void> _navigateToTarget(String text, int lineNumber) async {
    final direct = await _markdownController.scrollToAnchor(text);
    if (direct || !mounted) return;
    final lowered = text.trim().toLowerCase();
    for (final item in _markdownController.outline) {
      if (item.text.toLowerCase() == lowered) {
        final bySlug = await _markdownController.scrollToAnchor(item.slug);
        if (bySlug || !mounted) return;
        break;
      }
    }
    if (lineNumber >= 0) {
      await _markdownController.scrollToLine(lineNumber + 1);
    }
  }

  void _restoreScrollPosition() {
    final appState = context.read<AppState>();
    final path = widget.filePath;
    final offset = appState.getScrollOffset(path);

    void applyJump() {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasContentDimensions) return;
      final clamped = offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - clamped).abs() > 0.5) {
        _scrollController.jumpTo(clamped);
      }
    }

    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      applyJump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => applyJump());
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final appState = context.read<AppState>();
    appState.setScrollOffset(widget.filePath, _scrollController.offset);
  }

  String? _safeExplorerRootPath(AppState appState) {
    try {
      return appState.explorerRootPath;
    } on NoSuchMethodError {
      return null;
    }
  }

  Future<void> _handleTapLink(String destination, String? title) async {
    final uri = Uri.tryParse(destination);
    if (uri == null) return;

    final appState = context.read<AppState>();
    final basePath = p.dirname(widget.filePath);

    if (uri.hasScheme &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'mailto')) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
      return;
    }

    if (!uri.hasScheme || uri.scheme == 'file') {
      if (uri.path.isEmpty && uri.fragment.isNotEmpty) {
        unawaited(_markdownController.scrollToAnchor(uri.fragment));
        return;
      }

      final filePath = Uri.decodeComponent(uri.path);
      if (filePath.isEmpty) return;

      var fullPath = p.normalize(p.join(basePath, filePath));
      var file = File(fullPath);
      final explorerRoot = _safeExplorerRootPath(appState);
      if (!file.existsSync() &&
          explorerRoot != null &&
          explorerRoot.isNotEmpty) {
        final rootPath = p.normalize(p.join(explorerRoot, filePath));
        final rootFile = File(rootPath);
        if (rootFile.existsSync()) {
          fullPath = rootPath;
          file = rootFile;
        }
      }
      if (file.existsSync() && FileSystemEntity.isFileSync(fullPath)) {
        await appState.openFile(fullPath);
        if (uri.fragment.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_markdownController.scrollToAnchor(uri.fragment));
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _navSubscription?.cancel();
    _markdownController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.select<AppState, String>(
      (state) => state.getFileContent(widget.filePath),
    );
    final fontSize = context.select<AppState, double>(
      (state) => state.fontSize,
    );
    final showFrontmatter = context.select<AppState, bool>(
      (state) => state.showFrontmatter,
    );
    final explorerRootPath = context.select<AppState, String?>(
      _safeExplorerRootPath,
    );

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>();
    final basePath = p.dirname(widget.filePath);

    final sirenImageBuilder = SirenImageBuilder(
      basePath: basePath,
      explorerRootPath: explorerRootPath,
    );

    final codeBg =
        sirenColors?.codeBg ?? theme.colorScheme.surfaceContainerHighest;
    final dividerColor = sirenColors?.divider ?? theme.colorScheme.outline;
    final sidebarBg =
        sirenColors?.sidebarBg ?? theme.colorScheme.surfaceContainer;
    final quoteBorder = sirenColors?.quoteBorder ?? theme.colorScheme.primary;

    final markdownTheme = MarkdownThemeData(
      brightness: theme.brightness,
      foreground: theme.colorScheme.onSurface,
      muted: theme.colorScheme.onSurfaceVariant,
      accent: theme.colorScheme.primary,
      linkColor: theme.colorScheme.primary,
      codeBackground: codeBg,
      codeForeground: theme.colorScheme.onSurface,
      border: dividerColor,
      blockquoteBorder: quoteBorder,
      blockquoteBackground: sidebarBg,
      tableBorder: dividerColor,
      tableHeaderBackground: sidebarBg,
      tableStripeBackground: sidebarBg.withValues(alpha: 0.45),
      highlightFill: isDark
          ? Colors.yellow.withValues(alpha: 0.3)
          : Colors.yellow.withValues(alpha: 0.5),
      alertPalette: isDark
          ? const MarkdownAlertPalette.dark()
          : const MarkdownAlertPalette.light(),
      fontSize: fontSize,
      lineHeight: 1.6,
      codeFontSize: fontSize * 0.9,
      codeLineHeight: 1.45,
      blockSpacing: 12.0,
      h1Scale: 2.25,
      h2Scale: 1.75,
      h3Scale: 1.5,
      h4Scale: 1.25,
      h5Scale: 1.0,
      h6Scale: 0.875,
      headingLineHeight: 1.25,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      codeFontFamily: GoogleFonts.firaCode().fontFamily,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _onScroll();
        }
        return false;
      },
      child: MarkdownView(
        content,
        options: const MarkdownOptions(urlPolicy: _sirenUrlPolicy),
        controller: _markdownController,
        theme: markdownTheme,
        showFrontmatter: showFrontmatter,
        selectable: true,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        scrollController: _scrollController,
        delegates: MarkdownBuilderDelegates(
          imagePolicy: MarkdownImagePolicy.load,
          urlPolicy: _sirenUrlPolicy,
          autoScrollToAnchors: true,
          onTapLink: (destination, title) {
            unawaited(_handleTapLink(destination, title));
          },
          imageBuilder: sirenImageBuilder.build,
          codeBlockBuilder: (ctx, node) {
            final codeTheme = isDark
                ? SirenTheme.showcaseDarkTheme
                : SirenTheme.showcaseLightTheme;
            return _CodeBlockView(
              code: node.literal,
              language: node.language ?? '',
              theme: codeTheme,
              sirenColors: sirenColors,
              fontSize: fontSize,
            );
          },
          onTapMermaid: (ctx, diagram) {
            unawaited(MermaidZoomDialog.show(ctx, diagram: diagram));
          },
        ),
      ),
    );
  }
}

class _CodeBlockView extends StatelessWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final SirenColors? sirenColors;
  final double fontSize;

  const _CodeBlockView({
    required this.code,
    required this.language,
    required this.theme,
    required this.sirenColors,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final cleanCode = code.endsWith('\n')
        ? code.substring(0, code.length - 1)
        : code;

    // Use transparent background for the highlight view so selection is visible
    final Map<String, TextStyle> transparentTheme = Map.from(theme);
    if (transparentTheme.containsKey('root')) {
      transparentTheme['root'] = transparentTheme['root']!.copyWith(
        backgroundColor: Colors.transparent,
      );
    }

    final dividerColor =
        sirenColors?.divider ?? materialTheme.colorScheme.outline;
    final codeBlockBg =
        sirenColors?.codeBlockBg ??
        sirenColors?.codeBg ??
        materialTheme.colorScheme.surfaceContainerHighest;
    final headerBg =
        sirenColors?.codeBlockHeaderBg ??
        sirenColors?.sidebarBg ??
        materialTheme.colorScheme.surfaceContainer;
    final iconColor =
        sirenColors?.iconColor ?? materialTheme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: codeBlockBg,
        border: Border.all(color: dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(bottom: BorderSide(color: dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (language.isNotEmpty)
                    Text(
                      language.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    )
                  else
                    const SizedBox(),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: cleanCode));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: iconColor),
                          const SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: TextStyle(fontSize: 12, color: iconColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          HighlightView(
            cleanCode,
            language: language,
            theme: transparentTheme,
            padding: const EdgeInsets.all(16),
            textStyle: GoogleFonts.firaCode(fontSize: fontSize * 0.9),
          ),
        ],
      ),
    );
  }
}
