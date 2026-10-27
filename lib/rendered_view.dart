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
      String filePath = Uri.decodeComponent(uri.path);
      if (filePath.isEmpty) return;

      var fullPath = p.join(basePath, filePath);
      fullPath = p.normalize(fullPath);
      var file = File(fullPath);
      if (!file.existsSync() && appState.explorerRootPath != null) {
        final rootPath = p.normalize(
          p.join(appState.explorerRootPath!, filePath),
        );
        final rootFile = File(rootPath);
        if (rootFile.existsSync()) {
          fullPath = rootPath;
          file = rootFile;
        }
      }
      if (file.existsSync()) {
        if (FileSystemEntity.isFileSync(fullPath)) {
          appState.openFile(fullPath);
          if (uri.fragment.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToAnchor(uri.fragment);
            });
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
    // Select ONLY the content for this specific file.
    // This prevents rebuilds when other tabs change or active tab changes.
    final content = context.select<AppState, String>(
      (state) => state.getProcessedContent(widget.filePath),
    );

    // Select font size (global preference)
    final fontSize = context.select<AppState, double>(
      (state) => state.fontSize,
    );
    final showFrontmatter = context.select<AppState, bool>(
      (state) => state.showFrontmatter,
    );

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>()!;
    final basePath = p.dirname(widget.filePath);
    final explorerRootPath = context.select<AppState, String?>((state) {
      try {
        return state.explorerRootPath;
      } on NoSuchMethodError {
        return null;
      }
    });

    void onTapLink(String text, String? href, String title) =>
        _handleTapLink(text, href, title);

    final htmlImageBuilder = HtmlImageBuilder(
      basePath: basePath,
      explorerRootPath: explorerRootPath,
      onTapLink: onTapLink,
    );

    final extensionSet = md.ExtensionSet(
      [
        YamlFrontmatterBlockSyntax(enabled: showFrontmatter),
        const AlertBlockSyntax(),
        const HtmlCommentBlockSyntax(),
        const HtmlHrBlockSyntax(),
        const HtmlDetailsBlockSyntax(),
        const HtmlTableBlockSyntax(),
        const HtmlListBlockSyntax(),
        const HtmlDlBlockSyntax(),
        const HtmlContainerBlockSyntax(),
        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      ],
      [
        HtmlCommentInlineSyntax(),
        HtmlBrInlineSyntax(),
        HtmlAnchorInlineSyntax(),
        HtmlPictureInlineSyntax(),
        HtmlImgInlineSyntax(),
        HtmlInlineTagSyntax(),
        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        AnchorSyntax(),
        LatexSyntax(),
        HighlightSyntax(),
        SubscriptSyntax(),
        SuperscriptSyntax(),
      ],
    );

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      blockSpacing: 12.0, // --spacing-md
      // Typography
      p: TextStyle(
        fontSize: fontSize,
        height: 1.6,
        color: theme.colorScheme.onSurface,
      ),
      code: GoogleFonts.firaCode(backgroundColor: sirenColors.codeBg),
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
        color: theme.colorScheme.primary, // CSS uses --color-primary (Green)
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
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),

      // Tables
      tableBody: TextStyle(fontSize: fontSize),
      tableHead: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: sirenColors.headingColor,
        backgroundColor:
            sirenColors.sidebarBg, // Align with CSS --bg-surface-container
      ),
      tableBorder: TableBorder.all(color: sirenColors.divider!, width: 1),
      tableHeadAlign: TextAlign.left,
      tablePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    );

    Widget buildMarkdownBodyWidget(
      BuildContext ctx,
      String markdownData, {
      Key? bodyKey,
    }) {
      Widget renderNested(BuildContext nestedCtx, String nestedMarkdown) =>
          buildMarkdownBodyWidget(nestedCtx, nestedMarkdown);

      late final Map<String, MarkdownElementBuilder> builders;
      builders = {
        'frontmatter': FrontmatterBuilder(
          ctx,
          showFrontmatter: showFrontmatter,
        ),
        'blockquote': AlertBuilder(ctx, showFrontmatter: showFrontmatter),
        'latex': LatexBuilder(
          textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: fontSize),
        ),
        'highlight': HighlightBuilder(ctx),
        'kbd': KbdBuilder(baseFontSize: fontSize),
        'u': UnderlineBuilder(),
        'small': SmallTextBuilder(baseFontSize: fontSize),
        'abbr': AbbrBuilder(),
        'html_img': htmlImageBuilder,
        'html_block': HtmlBlockBuilder(
          fontSize: fontSize,
          anchorKeys: _anchorKeys,
          htmlImageBuilder: htmlImageBuilder,
          onTapLink: onTapLink,
          nestedMarkdownBuilder: renderNested,
        ),
        'html_table': HtmlTableBuilder(
          fontSize: fontSize,
          nestedMarkdownBuilder: renderNested,
        ),
        'html_list': HtmlListBuilder(
          fontSize: fontSize,
          nestedMarkdownBuilder: renderNested,
        ),
        'html_dl': HtmlDlBuilder(
          fontSize: fontSize,
          nestedMarkdownBuilder: renderNested,
        ),
        'html_figure': HtmlFigureBuilder(
          fontSize: fontSize,
          nestedMarkdownBuilder: renderNested,
        ),
        'details': DetailsElementBuilder(
          fontSize: fontSize,
          nestedMarkdownBuilder: renderNested,
        ),
        'sub': SubSupBuilder(false, baseFontSize: fontSize),
        'sup': SubSupBuilder(
          true,
          baseFontSize: fontSize,
          anchorKeys: _anchorKeys,
          onTapLink: onTapLink,
        ),
        'section': FootnoteSectionBuilder(
          anchorKeys: _anchorKeys,
          fontSize: fontSize,
          onTapLink: onTapLink,
        ),
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
          htmlImageBuilder: htmlImageBuilder,
          anchorKeys: _anchorKeys,
        ),
        'h2': HeadingElementBuilder(
          fontSize: fontSize * 1.75,
          color: sirenColors.headingColor!,
          dividerColor: sirenColors.divider!,
          topMargin: 24, // H2 margin-top: 2em -> approx 32px, adjusted for flutter padding
          onTapLink: onTapLink,
          codeBg: sirenColors.codeBg,
          htmlImageBuilder: htmlImageBuilder,
          anchorKeys: _anchorKeys,
        ),
      };

      return MarkdownBody(
        key: bodyKey,
        data: markdownData,
        softLineBreak: false,
        onTapLink: onTapLink,
        // ignore: deprecated_member_use
        imageBuilder: (uri, title, alt) {
          return htmlImageBuilder.buildImageFromAttributes(ctx, {
            'src': uri.toString(),
            if (title != null && title.isNotEmpty) 'title': title,
            if (alt != null && alt.isNotEmpty) 'alt': alt,
          });
        },
        extensionSet: extensionSet,
        styleSheet: styleSheet,
        builders: builders,
      );
    }

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
          child: buildMarkdownBodyWidget(
            context,
            content,
            bodyKey: ValueKey<bool>(showFrontmatter),
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
      return Baseline(
        key: key,
        baseline: 0,
        baselineType: TextBaseline.alphabetic,
        child: const SizedBox.shrink(),
      );
    }
    return null;
  }
}

List<InlineSpan>? _parseInlineChildren(
  List<md.Node>? nodes,
  void Function(String, String?, String)? onTapLink, [
  Color? codeBg,
  BuildContext? context,
  HtmlImageBuilder? htmlImageBuilder,
]) {
  if (nodes == null) return null;
  final List<InlineSpan> spans = [];
  for (final node in nodes) {
    switch (node) {
      case md.Text(:final text):
        spans.add(TextSpan(text: text));
      case md.Element(
        :final tag,
        :final children,
        :final attributes,
        :final textContent,
      ):
        if (tag == 'anchor') {
          continue;
        }
        if (tag == 'br') {
          spans.add(const TextSpan(text: '\n'));
          continue;
        }
        if (tag == 'html_img' && context != null && htmlImageBuilder != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: htmlImageBuilder.buildImageFromAttributes(
                context,
                attributes,
              ),
            ),
          );
          continue;
        }
        final style = switch (tag) {
          'strong' => const TextStyle(fontWeight: FontWeight.bold),
          'em' => const TextStyle(fontStyle: FontStyle.italic),
          'del' => const TextStyle(decoration: TextDecoration.lineThrough),
          'u' => const TextStyle(decoration: TextDecoration.underline),
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
            children: _parseInlineChildren(
              children,
              onTapLink,
              codeBg,
              context,
              htmlImageBuilder,
            ),
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
  final HtmlImageBuilder? htmlImageBuilder;
  final Map<String, GlobalKey>? anchorKeys;

  HeadingElementBuilder({
    required this.fontSize,
    required this.color,
    required this.dividerColor,
    required this.topMargin,
    required this.onTapLink,
    this.codeBg,
    this.htmlImageBuilder,
    this.anchorKeys,
  });

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(text.text, style: preferredStyle);
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.children == null || element.children!.isEmpty) {
      return const SizedBox.shrink();
    }

    final align = element.attributes['align']?.toLowerCase();
    final textAlign = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.start,
    };
    final boxAlignment = switch (align) {
      'center' => Alignment.center,
      'right' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

    final anchorWidgets = <Widget>[];
    final nonWhitespace = <md.Node>[];
    for (final node in element.children!) {
      if (node is md.Element && node.tag == 'anchor') {
        final slug = node.attributes['id'];
        if (slug != null && slug.isNotEmpty && anchorKeys != null) {
          final key = GlobalKey(debugLabel: slug);
          anchorKeys![slug] = key;
          anchorWidgets.add(SizedBox.shrink(key: key));
        }
        continue;
      }
      if (node is md.Text && node.text.trim().isEmpty) continue;
      nonWhitespace.add(node);
    }

    final isPureImageHeading =
        htmlImageBuilder != null &&
        nonWhitespace.isNotEmpty &&
        nonWhitespace.every(
          (n) => n is md.Element && (n.tag == 'html_img' || n.tag == 'img'),
        );

    if (isPureImageHeading) {
      return Semantics(
        header: true,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          child: Container(
            margin: EdgeInsets.only(top: topMargin, bottom: 4.0),
            padding: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: dividerColor, width: 1.0),
              ),
            ),
            width: double.infinity,
            alignment: boxAlignment,
            child: Wrap(
              alignment: switch (align) {
                'center' => WrapAlignment.center,
                'right' => WrapAlignment.end,
                _ => WrapAlignment.start,
              },
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                ...anchorWidgets,
                for (final node in nonWhitespace)
                  htmlImageBuilder!.buildImageFromAttributes(
                    context,
                    (node as md.Element).attributes,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final children = _parseInlineChildren(
      element.children,
      onTapLink,
      codeBg,
      context,
      htmlImageBuilder,
    );

    return Semantics(
      header: true,
      child: Container(
        margin: EdgeInsets.only(top: topMargin, bottom: 4.0),
        padding: const EdgeInsets.only(bottom: 6.0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: dividerColor, width: 1.0)),
        ),
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...anchorWidgets,
            Text.rich(
              TextSpan(
                children: children,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1.25,
                ),
              ),
              textAlign: textAlign,
            ),
          ],
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
      return MermaidDiagram(
        code: element.textContent,
        isDark: isDark,
        fontSize: fontSize,
      );
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

    // If parent is a link, return null so flutter_markdown attaches the link's
    // gesture recognizer to the inline text span.
    if (parentStyle?.decoration == TextDecoration.underline) {
      return null;
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
