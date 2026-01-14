import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_state.dart';
import 'mermaid_diagram.dart';
import 'theme.dart';

class RenderedView extends StatefulWidget {
  const RenderedView({super.key});

  @override
  State<RenderedView> createState() => _RenderedViewState();
}

class _RenderedViewState extends State<RenderedView> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _anchorKeys = {};
  StreamSubscription? _navSubscription;

  @override
  void initState() {
    super.initState();
    _restoreScrollPosition();
  }

  @override
  void didUpdateWidget(RenderedView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navSubscription?.cancel();
    final appState = context.read<AppState>();
    _navSubscription = appState.navigationStream.listen((event) {
      if (event.text.isNotEmpty) {
        final slug = _generateSlug(event.text);
        _scrollToAnchor(slug);
      }
    });
  }

  String _generateSlug(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
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

  void _handleTapLink(String text, String? href, String title) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;

    final appState = context.read<AppState>();
    final currentFilePath = appState.currentFilePath;
    final basePath = currentFilePath != null
        ? p.dirname(currentFilePath)
        : null;

    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
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
        String filePath = uri.path;
        if (filePath.isEmpty) return;

        var fullPath = p.join(basePath, filePath);
        fullPath = p.normalize(fullPath);
        final file = File(fullPath);
        if (await file.exists()) {
          if (await FileSystemEntity.isFile(fullPath)) {
            appState.openFile(fullPath);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _navSubscription?.cancel();
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
    final basePath = currentFilePath != null
        ? p.dirname(currentFilePath)
        : null;

    final codeBg = isDark ? const Color(0xFF2d2d4a) : const Color(0xFFe0e0ec);

    // Clear keys on rebuild as content might have changed
    _anchorKeys.clear();

    final processedContent = _injectAnchors(content);

    void onTapLink(String text, String? href, String title) =>
        _handleTapLink(text, href, title);

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
        child: SelectionArea(
          child: MarkdownBody(
            data: processedContent,
            onTapLink: onTapLink,
            // ignore: deprecated_member_use
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
            extensionSet: md.ExtensionSet(
              md.ExtensionSet.gitHubFlavored.blockSyntaxes,
              [
                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                AnchorSyntax(),
              ],
            ),
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  blockSpacing: 8.0,
                  h1Padding: const EdgeInsets.only(top: 32.0, bottom: 16.0),
                  h2Padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                  h3Padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
                  h4Padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  h5Padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  h6Padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  p: GoogleFonts.inter(fontSize: fontSize, height: 1.6),
                  h1: GoogleFonts.inter(
                    fontSize: fontSize * 2.2,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  h2: GoogleFonts.inter(
                    fontSize: fontSize * 1.8,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  h3: GoogleFonts.inter(
                    fontSize: fontSize * 1.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  h4: GoogleFonts.inter(
                    fontSize: fontSize * 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                  h5: GoogleFonts.inter(
                    fontSize: fontSize * 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                  h6: GoogleFonts.inter(
                    fontSize: fontSize * 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                  code: GoogleFonts.firaCode(
                    backgroundColor: codeBg,
                    fontSize: fontSize * 0.9,
                  ),
                ),
            builders: {
              'code': CodeElementBuilder(isDark: isDark, fontSize: fontSize),
              'anchor': AnchorBuilder(_anchorKeys),
            },
          ),
        ),
      ),
    );
  }

  String _injectAnchors(String markdown) {
    final buffer = StringBuffer();
    final lines = markdown.split('\n');
    bool inCodeBlock = false;

    for (final line in lines) {
      if (line.trim().startsWith('```')) {
        inCodeBlock = !inCodeBlock;
      }

      if (!inCodeBlock && line.startsWith('#')) {
        final text = line.replaceFirst(RegExp(r'^#+\s*'), '');
        final slug = _generateSlug(text);
        buffer.writeln('[[@anchor:$slug]]');
      }
      buffer.writeln(line);
    }
    return buffer.toString();
  }
}

class AnchorSyntax extends md.InlineSyntax {
  AnchorSyntax() : super(r'\[\[@anchor:([a-z0-9-]+)\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final slug = match[1]!;
    final el = md.Element('anchor', []);
    el.attributes['id'] = slug;
    parser.addNode(el);
    return true;
  }
}

class AnchorBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> anchorKeys;
  AnchorBuilder(this.anchorKeys);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final slug = element.attributes['id'];
    if (slug != null) {
      final key = GlobalKey(debugLabel: slug);
      anchorKeys[slug] = key;
      return SizedBox(key: key, width: 0, height: 0);
    }
    return null;
  }
}

List<InlineSpan>? _parseInlineChildren(
  List<md.Node>? nodes,
  void Function(String, String?, String)? onTapLink,
) {
  if (nodes == null) return null;
  final List<InlineSpan> spans = [];
  for (final node in nodes) {
    if (node is md.Text) {
      spans.add(TextSpan(text: node.text));
    } else if (node is md.Element) {
      TextStyle? style;
      TapGestureRecognizer? recognizer;

      switch (node.tag) {
        case 'strong':
          style = const TextStyle(fontWeight: FontWeight.bold);
          break;
        case 'em':
          style = const TextStyle(fontStyle: FontStyle.italic);
          break;
        case 'code':
          style = GoogleFonts.firaCode();
          break;
        case 'a':
          style = const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          );
          final href = node.attributes['href'];
          final title = node.attributes['title'] ?? '';
          if (onTapLink != null) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => onTapLink(node.textContent, href, title);
          }
          break;
      }
      spans.add(
        TextSpan(
          children: _parseInlineChildren(node.children, onTapLink),
          style: style,
          recognizer: recognizer,
        ),
      );
    }
  }
  return spans;
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
    final bool isBlock =
        language.isNotEmpty || element.textContent.contains('\n');

    if (isBlock) {
      final theme = isDark
          ? SirenTheme.showcaseDarkTheme
          : SirenTheme.showcaseLightTheme;
      final bgColor = isDark
          ? const Color(0xFF0f0f1a)
          : const Color(0xFFe8e8f0);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: bgColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: HighlightView(
          element.textContent,
          language: language,
          theme: theme,
          padding: const EdgeInsets.all(16),
          textStyle: GoogleFonts.firaCode(fontSize: fontSize),
        ),
      );
    } else {
      // Inline code styling
      final bgColor = isDark
          ? const Color(0xFF2d2d4a)
          : const Color(0xFFe0e0ec);
      final borderColor = isDark
          ? const Color(0xFF3d3d5c)
          : const Color(0xFFd0d0e0);
      final textColor = isDark
          ? const Color(0xFFff6b8a)
          : const Color(0xFFd03050);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Text(
          element.textContent,
          style: GoogleFonts.firaCode(
            fontSize: fontSize * 0.85,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      );
    }
  }
}
