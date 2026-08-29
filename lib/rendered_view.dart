import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'mermaid_diagram.dart';
import 'markdown_extensions.dart';
import 'markdown_processor.dart';
import 'theme.dart';

class RenderedView extends StatefulWidget {
  final String filePath;
  const RenderedView({super.key, required this.filePath});

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
      // Only scroll if we are the visible tab? 
      // Actually, navigation events are usually for the active tab.
      // But checking if we are visible is hard here without passing 'isVisible'.
      // However, scrolling an invisible controller is harmless usually.
      if (event.text.isNotEmpty) {
        final slug = MarkdownProcessor.generateSlug(event.text);
        _scrollToAnchor(slug);
      }
    });
  }

  void _restoreScrollPosition() {
    final appState = context.read<AppState>();
    final path = widget.filePath;
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final appState = context.read<AppState>();
    appState.setScrollOffset(widget.filePath, _scrollController.offset);
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
    }
  }

  void _handleTapLink(String text, String? href, String title) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;

    final appState = context.read<AppState>();
    final basePath = p.dirname(widget.filePath);

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

  @override
  void dispose() {
    _navSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Select ONLY the content for this specific file.
    // This prevents rebuilds when other tabs change or active tab changes.
    final content = context.select<AppState, String>(
      (state) => state.getProcessedContent(widget.filePath),
    );
    
    // Select font size (global preference)
    final fontSize = context.select<AppState, double>((state) => state.fontSize);
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>()!;
    final basePath = p.dirname(widget.filePath);

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
            data: content,
            softLineBreak: true,
            onTapLink: onTapLink,
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) {
              if (uri.hasScheme &&
                  (uri.scheme == 'http' || uri.scheme == 'https')) {
                return Image.network(
                  uri.toString(),
                  semanticLabel: alt,
                  errorBuilder: (context, error, stackTrace) {
                    return Semantics(
                      label: alt != null && alt.isNotEmpty
                          ? 'Image failed to load: $alt'
                          : 'Image failed to load',
                      child: const Icon(Icons.broken_image, size: 24),
                    );
                  },
                );
              } else {
                // Local image
                String localPath = uri.path;
                var fullPath = p.join(basePath, localPath);
                fullPath = p.normalize(fullPath);
                final file = File(fullPath);
                if (file.existsSync()) {
                  return Image.file(file, semanticLabel: alt);
                }
                return Semantics(
                  label: alt != null && alt.isNotEmpty
                      ? 'Image not found: $alt'
                      : 'Image not found',
                  child: const Icon(Icons.broken_image, size: 24),
                );
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

              // Typography
              p: TextStyle(
                fontSize: fontSize,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              code: GoogleFonts.firaCode(
                backgroundColor: sirenColors.codeBg,
              ),
              strong: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              em: TextStyle(
                fontSize: fontSize,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface,
              ),
              del: TextStyle(
                fontSize: fontSize,
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurface,
              ),
              a: TextStyle(
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
              h1: TextStyle(
                fontSize: fontSize, // Matching p style
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              h2: TextStyle(
                fontSize: fontSize, // Matching p style
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              h3: TextStyle(
                fontSize: fontSize * 1.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: sirenColors.headingColor,
              ),
              h4: TextStyle(
                fontSize: fontSize * 1.25,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: sirenColors.headingColor,
              ),
              h5: TextStyle(
                fontSize: fontSize * 1.0,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: 0.05,
                color: sirenColors.headingColor, // Or uppercase logic if needed
              ),
              h6: TextStyle(
                fontSize: fontSize * 0.875,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: theme.colorScheme.onSurfaceVariant, // Muted
              ),

              // Blockquotes
              blockquote: TextStyle(
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
              // Disable default decoration as it is handled by the custom builder
              codeblockDecoration: const BoxDecoration(
                color: Colors.transparent,
              ),

              // Tables
              tableBody: TextStyle(fontSize: fontSize),
              tableHead: TextStyle(
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
                codeBg: sirenColors.codeBg,
              ),
              'h2': HeadingElementBuilder(
                fontSize: fontSize * 1.75,
                color: sirenColors.headingColor!,
                dividerColor: sirenColors.divider!,
                topMargin:
                    24, // H2 margin-top: 2em -> approx 32px, adjusted for flutter padding
                onTapLink: onTapLink,
                codeBg: sirenColors.codeBg,
              ),
            },
          ),
        ),
      ),
    );
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
  void Function(String, String?, String)? onTapLink, [
  Color? codeBg,
]) {
  if (nodes == null) return null;
  final List<InlineSpan> spans = [];
  for (final node in nodes) {
    switch (node) {
      case md.Text(:final text):
        spans.add(TextSpan(text: text));
      case md.Element(:final tag, :final children, :final attributes, :final textContent):
        final style = switch (tag) {
          'strong' => const TextStyle(fontWeight: FontWeight.bold),
          'em' => const TextStyle(fontStyle: FontStyle.italic),
          'code' => GoogleFonts.firaCode(backgroundColor: codeBg),
          'a' => const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          _ => null,
        };

        TapGestureRecognizer? recognizer;
        if (tag == 'a' && onTapLink != null) {
          final href = attributes['href'];
          final title = attributes['title'] ?? '';
          recognizer = TapGestureRecognizer()
            ..onTap = () => onTapLink(textContent, href, title);
        }

        spans.add(
          TextSpan(
            children: _parseInlineChildren(children, onTapLink, codeBg),
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
  final Color? codeBg;

  HeadingElementBuilder({
    required this.fontSize,
    required this.color,
    required this.dividerColor,
    required this.topMargin,
    required this.onTapLink,
    this.codeBg,
  });

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(text.text, style: preferredStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.children == null || element.children!.isEmpty) {
      return SizedBox.shrink();
    }

    final children = _parseInlineChildren(element.children, onTapLink, codeBg);

    return Semantics(
      header: true,
      child: Container(
        margin: EdgeInsets.only(top: topMargin, bottom: 16.0),
        padding: const EdgeInsets.only(bottom: 6.0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: dividerColor, width: 1.0)),
        ),
        width: double.infinity,
        child: Text.rich(
          TextSpan(
            children: children,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.25,
            ),
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
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
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

      return _CodeBlockView(
        code: element.textContent,
        language: language,
        theme: theme,
        sirenColors: sirenColors,
        fontSize: fontSize,
      );
    }

    final TextStyle baseStyle = parentStyle ?? const TextStyle();
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: GoogleFonts.firaCode(
          backgroundColor: sirenColors.codeBg,
          textStyle: baseStyle,
        ),
      ),
    );
  }
}

class _CodeBlockView extends StatelessWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final SirenColors sirenColors;
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
    // Remove trailing newline which often comes from markdown parsing
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: sirenColors.codeBlockBg ?? sirenColors.codeBg,
        border: Border.all(color: sirenColors.divider!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: sirenColors.codeBlockHeaderBg ?? sirenColors.sidebarBg,
              border: Border(bottom: BorderSide(color: sirenColors.divider!)),
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
                      color: sirenColors.iconColor,
                    ),
                  )
                else
                  const SizedBox(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: cleanCode));
                    ScaffoldMessenger.of(context).showSnackBar(
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
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: sirenColors.iconColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 12,
                            color: sirenColors.iconColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
