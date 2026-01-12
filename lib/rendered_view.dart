import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'app_state.dart';
import 'mermaid_diagram.dart';

class RenderedView extends StatefulWidget {
  const RenderedView({super.key});

  @override
  State<RenderedView> createState() => _RenderedViewState();
}

class _RenderedViewState extends State<RenderedView> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _anchorKeys = {};

  @override
  void initState() {
    super.initState();
    _restoreScrollPosition();
  }

  @override
  void didUpdateWidget(RenderedView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _restoreScrollPosition() {
    final appState = context.read<AppState>();
    final path = appState.currentFilePath;
    if (path != null) {
      final offset = appState.getScrollOffset(path);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(offset);
      } else {
        // Wait for attach
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(offset);
          }
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final appState = context.read<AppState>();
    final path = appState.currentFilePath;
    if (path != null) {
      appState.setScrollOffset(path, _scrollController.offset);
    }
  }

  void _scrollToAnchor(String fragment) {
    final key = _anchorKeys[fragment];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.0, // Top of the viewport
      );
    } else {
      debugPrint('Anchor not found: $fragment');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final content = appState.currentContent;
    final fontSize = appState.fontSize;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentFilePath = appState.currentFilePath;
    final basePath =
        currentFilePath != null ? p.dirname(currentFilePath) : null;

    // Clear keys on rebuild as content might have changed
    _anchorKeys.clear();
    final headerBuilder = HeaderBuilder(_anchorKeys);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _onScroll();
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: MarkdownBody(
          data: content,
          selectable: true,
          onTapLink: (text, href, title) async {
            if (href == null) return;
            final uri = Uri.tryParse(href);
            if (uri == null) return;

            if (uri.hasScheme &&
                (uri.scheme == 'http' || uri.scheme == 'https')) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            } else if (!uri.hasScheme || uri.scheme == 'file') {
              // Check for internal anchor (fragment only)
              if (uri.path.isEmpty && uri.fragment.isNotEmpty) {
                _scrollToAnchor(uri.fragment);
                return;
              }

              // Local file navigation
              if (basePath != null) {
                // If there's a fragment, strip it for file check
                String filePath = uri.path;
                if (filePath.isEmpty) {
                   // Should have been handled above if fragment exists,
                   // but if href is just '#' or empty, ignore.
                   return;
                }
                
                var fullPath = p.join(basePath, filePath);
                fullPath = p.normalize(fullPath);
                final file = File(fullPath);
                if (await file.exists()) {
                  if (await FileSystemEntity.isFile(fullPath)) {
                    appState.openFile(fullPath);
                    // Note: If we wanted to support anchors in OTHER files,
                    // we would need to pass the fragment to openFile and handle it after load.
                  }
                }
              }
            }
          },
          imageBuilder: (uri, title, alt) {
            if (uri.hasScheme &&
                (uri.scheme == 'http' || uri.scheme == 'https')) {
              return Image.network(uri.toString());
            } else {
              // Local image
              if (basePath != null) {
                String localPath = uri.path;
                var fullPath = p.join(basePath, localPath);
                fullPath = p.normalize(fullPath);
                final file = File(fullPath);
                if (file.existsSync()) {
                  return Image.file(file);
                }
              }
              return const Icon(Icons.broken_image, size: 24);
            }
          },
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: GoogleFonts.roboto(fontSize: fontSize),
            h1: GoogleFonts.roboto(
              fontSize: fontSize * 2.0,
              fontWeight: FontWeight.bold,
            ),
            h2: GoogleFonts.roboto(
              fontSize: fontSize * 1.75,
              fontWeight: FontWeight.bold,
            ),
            h3: GoogleFonts.roboto(
              fontSize: fontSize * 1.5,
              fontWeight: FontWeight.bold,
            ),
            h4: GoogleFonts.roboto(
              fontSize: fontSize * 1.25,
              fontWeight: FontWeight.bold,
            ),
            h5: GoogleFonts.roboto(
              fontSize: fontSize * 1.15,
              fontWeight: FontWeight.bold,
            ),
            h6: GoogleFonts.roboto(
              fontSize: fontSize * 1.0,
              fontWeight: FontWeight.bold,
            ),
            code: GoogleFonts.firaCode(
              backgroundColor: isDark
                  ? const Color(0xFF282C34)
                  : const Color(0xFFF0F0F0),
              fontSize: fontSize * 0.9,
            ),
          ),
          builders: {
            'code': CodeElementBuilder(isDark: isDark, fontSize: fontSize),
            'h1': headerBuilder,
            'h2': headerBuilder,
            'h3': headerBuilder,
            'h4': headerBuilder,
            'h5': headerBuilder,
            'h6': headerBuilder,
          },
        ),
      ),
    );
  }
}

class HeaderBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> anchorKeys;

  HeaderBuilder(this.anchorKeys);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final slug = _generateSlug(text);
    final key = GlobalKey(debugLabel: slug);
    anchorKeys[slug] = key;

    return SelectableText.rich(
      TextSpan(
        children: _parseChildren(element.children),
        style: preferredStyle,
      ),
      key: key,
    );
  }

  String _generateSlug(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  List<InlineSpan>? _parseChildren(List<md.Node>? nodes) {
    if (nodes == null) return null;
    final List<InlineSpan> spans = [];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text));
      } else if (node is md.Element) {
        TextStyle? style;
        switch (node.tag) {
          case 'strong':
            style = const TextStyle(fontWeight: FontWeight.bold);
            break;
          case 'em':
            style = const TextStyle(fontStyle: FontStyle.italic);
            break;
          case 'code':
            style = GoogleFonts.firaCode(
               // Inherit color/size from parent preferredStyle if possible, 
               // but we don't have it here easily without passing it down.
               // Just adding a background hint or font family.
            );
            break;
        }
        spans.add(TextSpan(
          children: _parseChildren(node.children),
          style: style,
        ));
      }
    }
    return spans;
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final double fontSize;

  CodeElementBuilder({required this.isDark, required this.fontSize});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      String lg = element.attributes['class']!;
      if (lg.startsWith('language-')) {
        language = lg.substring(9);
      } else {
        language = lg;
      }
    }

    if (language == 'mermaid') {
      return MermaidDiagram(code: element.textContent, isDark: isDark);
    }

    // Detect if this is likely a code block or inline code.
    // Blocks usually have a language set or contain newlines.
    final bool isBlock = language.isNotEmpty || element.textContent.contains('\n');

    if (isBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF282C34) : const Color(0xFFF0F0F0),
        ),
        clipBehavior: Clip.antiAlias,
        child: HighlightView(
          element.textContent,
          language: language,
          theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
          padding: const EdgeInsets.all(16),
          textStyle: GoogleFonts.firaCode(fontSize: fontSize),
        ),
      );
    } else {
      // Inline code styling
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF383C4A) : const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isDark ? const Color(0xFF4B5263) : const Color(0xFFBDBDBD),
            width: 0.5,
          ),
        ),
        child: Text(
          element.textContent,
          style: GoogleFonts.firaCode(
            fontSize: fontSize * 0.85,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFE06C75) : const Color(0xFFC62828),
          ),
        ),
      );
    }
  }
}
