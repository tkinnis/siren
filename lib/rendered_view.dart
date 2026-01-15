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
import 'markdown_extensions.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>()!;
    final currentFilePath = appState.currentFilePath;
    final basePath = currentFilePath != null
        ? p.dirname(currentFilePath)
        : null;

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
            softLineBreak: true,
            onTapLink: onTapLink,
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) {
              if (uri.hasScheme &&
                  (uri.scheme == 'http' || uri.scheme == 'https')) {
                return Image.network(
                  uri.toString(),
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.broken_image, size: 24);
                  },
                );
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
              [
                const AlertBlockSyntax(),
                ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
              ],
              [
                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                AnchorSyntax(),
                LatexSyntax(),
                HighlightSyntax(),
                SubscriptSyntax(),
                SuperscriptSyntax(),
              ],
            ),
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              blockSpacing: 12.0, // --spacing-md
              textScaleFactor: 1.0,

              // Typography
              p: GoogleFonts.inter(
                fontSize: fontSize,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              code: GoogleFonts.firaCode(
                backgroundColor: sirenColors.codeBg,
                fontSize: fontSize * 0.9,
                color: sirenColors
                    .iconColor, // Using body text color for inline code if not colored by highlighter
              ),
              strong: GoogleFonts.inter(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              em: GoogleFonts.inter(
                fontSize: fontSize,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface,
              ),
              del: GoogleFonts.inter(
                fontSize: fontSize,
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurface,
              ),
              a: GoogleFonts.inter(
                fontSize: fontSize,
                color: theme
                    .colorScheme
                    .primary, // CSS uses --color-primary (Green)
                decoration: TextDecoration.underline,
              ),

              // Headings
              // Workaround: flutter_markdown leaks the H1/H2 style to subsequent elements
              // when a custom builder is used. We set the stylesheet style to match
              // the body text (p) so that the leak is invisible. The actual styling
              // is applied by the HeadingElementBuilder.
              h1: GoogleFonts.inter(
                fontSize: fontSize, // Matching p style
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              h2: GoogleFonts.inter(
                fontSize: fontSize, // Matching p style
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              h3: GoogleFonts.inter(
                fontSize: fontSize * 1.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: sirenColors.headingColor,
              ),
              h4: GoogleFonts.inter(
                fontSize: fontSize * 1.25,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: sirenColors.headingColor,
              ),
              h5: GoogleFonts.inter(
                fontSize: fontSize * 1.0,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: 0.05,
                color: sirenColors.headingColor, // Or uppercase logic if needed
              ),
              h6: GoogleFonts.inter(
                fontSize: fontSize * 0.875,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: theme.colorScheme.onSurfaceVariant, // Muted
              ),

              // Blockquotes
              blockquote: GoogleFonts.inter(
                fontSize: fontSize,
                color: theme.colorScheme.onSurfaceVariant, // Muted
              ),
              blockquoteDecoration: BoxDecoration(
                color: sirenColors.sidebarBg, // --bg-surface-container
                border: Border(
                  left: BorderSide(
                    color:
                        sirenColors.quoteBorder ??
                        theme.colorScheme.primary, // --color-quote-border
                    width: 4.0,
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              blockquotePadding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 16.0,
              ),

              // Code block decoration (wrapper around HighlightView)
              codeblockDecoration: BoxDecoration(
                color: sirenColors.codeBg, // --bg-code
                border: Border.all(
                  color: sirenColors.divider!,
                ), // --color-border
                borderRadius: BorderRadius.circular(6),
              ),

              // Tables
              tableBody: GoogleFonts.inter(fontSize: fontSize),
              tableHead: GoogleFonts.inter(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: sirenColors.headingColor,
                backgroundColor: sirenColors
                    .sidebarBg, // Align with CSS --bg-surface-container
              ),
              tableBorder: TableBorder.all(
                color: sirenColors.divider!,
                width: 1,
              ),
              tableHeadAlign: TextAlign.left,
              tablePadding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              // Note: header background support in style sheet is limited, might need custom builder or just Accept basic style
            ),
            builders: {
              'blockquote': AlertBuilder(context),
              'latex': LatexBuilder(
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: fontSize,
                ),
              ),
              'highlight': HighlightBuilder(context),
              'sub': SubSupBuilder(false),
              'sup': SubSupBuilder(true),
              'anchor': AnchorBuilder(_anchorKeys),
              'code': CodeElementBuilder(
                isDark: isDark,
                fontSize: fontSize,
                sirenColors: sirenColors,
              ),
              // Custom heading builders for the bottom border
              'h1': HeadingElementBuilder(
                fontSize: fontSize * 2.25,
                color: sirenColors.headingColor!,
                dividerColor: sirenColors.divider!,
                topMargin: 0, // H1 has top margin 0 in CSS
                onTapLink: onTapLink,
              ),
              'h2': HeadingElementBuilder(
                fontSize: fontSize * 1.75,
                color: sirenColors.headingColor!,
                dividerColor: sirenColors.divider!,
                topMargin:
                    24, // H2 margin-top: 2em -> approx 32px, adjusted for flutter padding
                onTapLink: onTapLink,
              ),
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

class HeadingElementBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Color color;
  final Color dividerColor;
  final double topMargin;
  final void Function(String, String?, String) onTapLink;

  HeadingElementBuilder({
    required this.fontSize,
    required this.color,
    required this.dividerColor,
    required this.topMargin,
    required this.onTapLink,
  });

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return null;
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.children == null || element.children!.isEmpty) {
      return SizedBox.shrink();
    }

    final children = _parseInlineChildren(element.children, onTapLink);

    return Container(
      margin: EdgeInsets.only(top: topMargin, bottom: 16.0),
      padding: const EdgeInsets.only(bottom: 6.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 1.0)),
      ),
      width: double.infinity,
      child: Text.rich(
        TextSpan(
          children: children,
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final double fontSize;
  final SirenColors sirenColors;

  CodeElementBuilder({
    required this.isDark,
    required this.fontSize,
    required this.sirenColors,
  });

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

      return Container(
        margin: const EdgeInsets.symmetric(
          vertical: 12.0,
        ), // margin-bottom: 1.5em (approx)
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: sirenColors.codeBg,
          border: Border.all(color: sirenColors.divider!),
        ),
        clipBehavior: Clip.antiAlias,
        child: HighlightView(
          element.textContent,
          language: language,
          theme: theme,
          padding: const EdgeInsets.all(16),
          textStyle: GoogleFonts.firaCode(fontSize: fontSize * 0.9),
        ),
      );
    } else {
      // Inline code styling
      // Using default p style but tailored
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 5.0,
          vertical: 2.0,
        ), // 0.2em 0.4em
        decoration: BoxDecoration(
          color: sirenColors.sidebarBg, // --bg-surface-container
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          element.textContent,
          style: GoogleFonts.firaCode(
            fontSize: fontSize * 0.9,
            color:
                preferredStyle?.color ??
                sirenColors.iconColor, // Inherit or default
          ),
        ),
      );
    }
  }
}
