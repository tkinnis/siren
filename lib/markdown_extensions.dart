import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

// --- YAML Frontmatter ---

class YamlFrontmatterBlockSyntax extends md.BlockSyntax {
  final bool enabled;

  @override
  RegExp get pattern => RegExp(r'^---\s*$');

  const YamlFrontmatterBlockSyntax({this.enabled = true});

  @override
  bool canParse(md.BlockParser parser) {
    // YAML frontmatter is only valid at the very beginning of a document.
    if (parser.lines.isEmpty ||
        !identical(parser.current, parser.lines.first)) {
      return false;
    }
    if (!pattern.hasMatch(parser.current.content)) return false;

    final firstInner = parser.peek(1);
    if (firstInner == null) return false;
    final firstTrimmed = firstInner.content.trim();
    if (firstTrimmed.isEmpty) return false;

    // Look ahead for a closing '---' or '...' fence where lines are valid YAML
    // frontmatter entries (key: value, list items, or comments).
    bool hasKeyValue = false;
    final keyPattern = RegExp(r'^[A-Za-z0-9_.-]+\s*:');
    final listItemPattern = RegExp(r'^\s*-\s+.+');
    for (int i = 1; i < 40; i++) {
      final peeked = parser.peek(i);
      if (peeked == null) return false;
      final rawLine = peeked.content;
      final line = rawLine.trim();
      if (line == '---' || line == '...') {
        return hasKeyValue && i > 1;
      }
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (keyPattern.hasMatch(rawLine)) {
        hasKeyValue = true;
      } else if (!listItemPattern.hasMatch(rawLine)) {
        return false;
      }
    }
    return false;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    // Consume opening '---'
    parser.advance();

    final yamlLines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      final trimmed = line.trim();
      parser.advance();
      if (trimmed == '---' || trimmed == '...') {
        break;
      }
      yamlLines.add(line);
    }

    if (!enabled) {
      // Returning an empty root-level Text node causes flutter_markdown to
      // skip emitting any block widget, decoration, or blockSpacing.
      return md.Text('');
    }

    final element = md.Element('frontmatter', []);
    element.attributes['class'] = 'frontmatter';
    element.attributes['_raw'] = yamlLines.join('\n');
    return element;
  }

  /// Parses simple YAML frontmatter lines into structured entries preserving
  /// whether the value is a YAML list (`[a, b]` or `- item`) vs. a scalar.
  static List<({String key, List<String> values, bool isList})>
  parseStructuredEntries(String rawYaml) {
    final entries = <({String key, List<String> values, bool isList})>[];
    final lines = rawYaml.split('\n');
    String? currentKey;
    final currentValues = <String>[];
    bool currentIsList = false;
    final keyValRegex = RegExp(r'^([A-Za-z0-9_.-]+)\s*:\s*(.*)$');

    void flushCurrent() {
      if (currentKey != null) {
        entries.add((
          key: currentKey!,
          values: List.unmodifiable(currentValues),
          isList: currentIsList,
        ));
        currentKey = null;
        currentValues.clear();
        currentIsList = false;
      }
    }

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if ((rawLine.startsWith(' ') || rawLine.startsWith('\t')) &&
          currentKey != null &&
          trimmed.startsWith('- ')) {
        currentIsList = true;
        currentValues.add(_stripQuotes(trimmed.substring(2).trim()));
        continue;
      }

      final match = keyValRegex.firstMatch(rawLine);
      if (match != null) {
        flushCurrent();
        currentKey = match.group(1)!.trim();
        final rawVal = match.group(2)!.trim();
        if (rawVal.isNotEmpty) {
          if (rawVal.startsWith('[') && rawVal.endsWith(']')) {
            currentIsList = true;
            final inner = rawVal.substring(1, rawVal.length - 1).trim();
            if (inner.isNotEmpty) {
              currentValues.addAll(
                inner
                    .split(',')
                    .map((s) => _stripQuotes(s.trim()))
                    .where((s) => s.isNotEmpty),
              );
            }
          } else {
            currentValues.add(_stripQuotes(rawVal));
          }
        }
      }
    }
    flushCurrent();
    return entries;
  }

  /// Parses simple YAML frontmatter lines into flat key-value pairs.
  static List<({String key, String value})> parseEntries(String rawYaml) {
    return parseStructuredEntries(rawYaml)
        .map((e) => (key: e.key, value: e.values.join(', ')))
        .toList();
  }

  static String _stripQuotes(String value) {
    if (value.length >= 2) {
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }
}

// --- GitHub Alerts ---

class AlertBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern =>
      RegExp(r'^ {0,3}>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]');

  const AlertBlockSyntax();

  @override
  bool canParse(md.BlockParser parser) {
    return pattern.hasMatch(parser.current.content);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    final type = match?.group(1)?.toUpperCase() ?? 'NOTE';

    // Consume the first line (the alert marker)
    parser.advance();

    // Parse the remaining lines as a blockquote
    final childLines = <String>[];

    // Continue consuming lines until the blockquote ends
    while (!parser.isDone) {
      final line = parser.current.content;
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('>')) {
        break;
      }
      childLines.add(line.replaceFirst(RegExp(r'^\s{0,3}>\s?'), ''));
      parser.advance();
    }

    // Parse the inner content
    // Use 'blockquote' because it is a recognized block tag in flutter_markdown.
    // 'div' and custom tags are treated as inline, causing crashes.
    final element = md.Element('blockquote', []);
    element.attributes['class'] = 'alert';
    element.attributes['type'] = type;
    element.attributes['_raw'] = childLines.join('\n');
    return element;
  }
}

class FrontmatterBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool showFrontmatter;

  FrontmatterBuilder(this.context, {this.showFrontmatter = true});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (!showFrontmatter) {
      return const SizedBox.shrink();
    }
    return AlertBuilder(
      context,
      showFrontmatter: showFrontmatter,
    )._buildFrontmatter(element.attributes['_raw'] ?? '', preferredStyle);
  }
}

class AlertBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool showFrontmatter;

  AlertBuilder(this.context, {this.showFrontmatter = true});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final elementClass = element.attributes['class'];
    if (elementClass == 'frontmatter') {
      if (!showFrontmatter) {
        return const SizedBox.shrink();
      }
      return _buildFrontmatter(
        element.attributes['_raw'] ?? '',
        preferredStyle,
      );
    }
    if (elementClass != 'alert') {
      return null;
    }

    final type = element.attributes['type'] ?? 'NOTE';
    final rawContent = element.attributes['_raw'] ?? '';

    final (color, icon, title) = switch (type) {
      'TIP' => (Colors.green, Icons.lightbulb_outline, 'Tip'),
      'IMPORTANT' => (Colors.purple, Icons.info_outline, 'Important'),
      'WARNING' => (Colors.orange, Icons.warning_amber_rounded, 'Warning'),
      'CAUTION' => (Colors.red, Icons.error_outline, 'Caution'),
      _ => (Colors.blue, Icons.info_outline, 'Note'),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(left: BorderSide(color: color, width: 4.0)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MarkdownBody(
            data: rawContent,
            selectable: false,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: preferredStyle,
                  code: GoogleFonts.firaCode(
                    backgroundColor: Theme.of(context)
                        .extension<SirenColors>()
                        ?.codeBg,
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrontmatter(String rawYaml, TextStyle? preferredStyle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>()!;
    final entries = YamlFrontmatterBlockSyntax.parseStructuredEntries(rawYaml);
    final baseFontSize = preferredStyle?.fontSize ?? 14.0;
    final dividerColor =
        sirenColors.divider ?? theme.colorScheme.outlineVariant;

    return Container(
      key: const Key('yaml_frontmatter_card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: sirenColors.codeBlockBg ?? sirenColors.sidebarBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sirenColors.codeBlockHeaderBg ?? sirenColors.sidebarBg,
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'FRONTMATTER',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: entries.isEmpty
                ? Text(
                    rawYaml,
                    style: GoogleFonts.firaCode(
                      fontSize: baseFontSize * 0.85,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: FlexColumnWidth(),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: dividerColor.withValues(alpha: 0.45),
                        width: 1,
                      ),
                    ),
                    children: [
                      for (final entry in entries)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 20,
                                top: 6,
                                bottom: 6,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 96),
                                child: Text(
                                  entry.key,
                                  softWrap: false,
                                  style: GoogleFonts.firaCode(
                                    fontSize: baseFontSize * 0.84,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: _buildFrontmatterValue(
                                entry,
                                theme: theme,
                                isDark: isDark,
                                sirenColors: sirenColors,
                                baseFontSize: baseFontSize,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrontmatterValue(
    ({String key, List<String> values, bool isList}) entry, {
    required ThemeData theme,
    required bool isDark,
    required SirenColors sirenColors,
    required double baseFontSize,
  }) {
    if (entry.isList && entry.values.isNotEmpty) {
      final primary = theme.colorScheme.primary;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in entry.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: primary.withValues(alpha: isDark ? 0.35 : 0.25),
                ),
              ),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: baseFontSize * 0.82,
                  fontWeight: FontWeight.w500,
                  color: primary,
                ),
              ),
            ),
        ],
      );
    }

    final scalar = entry.values.join(', ');
    final lower = scalar.toLowerCase();
    if (lower == 'true' || lower == 'false') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: sirenColors.codeBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            scalar,
            style: GoogleFonts.firaCode(
              fontSize: baseFontSize * 0.82,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return Text(
      scalar,
      style: TextStyle(
        fontSize: baseFontSize * 0.9,
        fontWeight: entry.key == 'title' ? FontWeight.w600 : FontWeight.w400,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

// --- LaTeX Math ---

class LatexSyntax extends md.InlineSyntax {
  LatexSyntax() : super(r'(\$\$[\s\S]*?\$\$)|(\$[^$]*\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0)!;
    bool isBlock = raw.startsWith('\$\$');
    final content = isBlock
        ? raw.substring(2, raw.length - 2)
        : raw.substring(1, raw.length - 1);

    final el = md.Element('latex', [md.Text(content)]);
    el.attributes['mode'] = isBlock ? 'block' : 'inline';
    parser.addNode(el);
    return true;
  }
}

class LatexBuilder extends MarkdownElementBuilder {
  final TextStyle? textStyle;

  LatexBuilder({this.textStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final content = element.textContent;
    final mode = element.attributes['mode'];

    if (mode == 'block') {
      return Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            content,
            textStyle: textStyle?.copyWith(
              fontSize: (textStyle?.fontSize ?? 14) * 1.2,
            ),
          ),
        ),
      );
    } else {
      return Math.tex(
        content,
        textStyle: textStyle ?? preferredStyle,
        mathStyle: MathStyle.text,
      );
    }
  }
}

// --- Highlight ---

class HighlightSyntax extends md.InlineSyntax {
  HighlightSyntax() : super(r'==([^=]+)==');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    final el = md.Element('highlight', [md.Text(content)]);
    parser.addNode(el);
    return true;
  }
}

class HighlightBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  HighlightBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final theme = Theme.of(context);
    // Use a yellow tint or primary tint
    final color = theme.brightness == Brightness.dark
        ? Colors.yellow.withValues(alpha: 0.3)
        : Colors.yellow.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(element.textContent, style: preferredStyle),
    );
  }
}

// --- Sub/Superscript ---

class SubscriptSyntax extends md.InlineSyntax {
  SubscriptSyntax() : super(r'~([^~]+)~');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    final el = md.Element('sub', [md.Text(content)]);
    parser.addNode(el);
    return true;
  }
}

class SuperscriptSyntax extends md.InlineSyntax {
  SuperscriptSyntax() : super(r'\^([^^\s\]]+)\^');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    final el = md.Element('sup', [md.Text(content)]);
    parser.addNode(el);
    return true;
  }
}

class SubSupBuilder extends MarkdownElementBuilder {
  final bool isSup;
  final double? baseFontSize;
  final Map<String, GlobalKey>? anchorKeys;
  final void Function(String text, String? href, String title)? onTapLink;

  SubSupBuilder(
    this.isSup, {
    this.baseFontSize,
    this.anchorKeys,
    this.onTapLink,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final isFootnoteRef = element.attributes['class'] == 'footnote-ref';
    final displayText = isFootnoteRef
        ? '[${element.textContent}]'
        : element.textContent;

    String? href;
    String? anchorId;
    if (isFootnoteRef && element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'a') {
          href = child.attributes['href'];
          anchorId = child.attributes['id'];
          break;
        }
      }
    }

    GlobalKey? key;
    if (anchorId != null && anchorKeys != null) {
      key = GlobalKey(debugLabel: anchorId);
      anchorKeys![anchorId] = key;
    }

    final effectiveBaseStyle =
        preferredStyle ??
        parentStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    final resolvedBaseSize =
        baseFontSize ?? effectiveBaseStyle.fontSize ?? 14.0;
    final linkColor = theme.colorScheme.primary;

    final textStyle = effectiveBaseStyle.copyWith(
      fontSize: resolvedBaseSize * (isFootnoteRef ? 0.78 : 0.75),
      color: isFootnoteRef ? linkColor : effectiveBaseStyle.color,
      fontWeight: isFootnoteRef
          ? FontWeight.w600
          : effectiveBaseStyle.fontWeight,
      decoration: isFootnoteRef
          ? TextDecoration.underline
          : effectiveBaseStyle.decoration,
      decorationColor: isFootnoteRef ? linkColor : null,
    );

    Widget badge = Transform.translate(
      offset: Offset(0, isSup ? -4.0 : 4.0),
      child: Text(displayText, style: textStyle),
    );

    if (isFootnoteRef && href != null && onTapLink != null) {
      final targetHref = href;
      badge = SelectionContainer.disabled(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => onTapLink!(displayText, targetHref, ''),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: badge,
            ),
          ),
        ),
      );
    } else if (key != null) {
      badge = KeyedSubtree(key: key, child: badge);
    }

    return badge;
  }
}

/// Renders `<section class="footnotes">` at the bottom of a document in a
/// GitHub-style separated footnotes block with a top border, muted smaller
/// typography, registered `fn-...` anchors, and non-emoji typographic backlinks.
class FootnoteSectionBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> anchorKeys;
  final double fontSize;
  final void Function(String text, String? href, String title) onTapLink;

  FootnoteSectionBuilder({
    required this.anchorKeys,
    required this.fontSize,
    required this.onTapLink,
  });

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.attributes['class'] != 'footnotes') return null;
    final children = element.children;
    if (children == null || children.isEmpty) return null;

    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>();
    final dividerColor =
        sirenColors?.divider ??
        theme.colorScheme.outline.withValues(alpha: 0.3);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    final linkColor = theme.colorScheme.primary;
    final codeBg = sirenColors?.codeBg;
    final footnoteFontSize = fontSize * 0.875;

    final baseStyle = TextStyle(
      fontSize: footnoteFontSize,
      height: 1.55,
      color: mutedColor,
    );

    final itemWidgets = <Widget>[];
    int itemIndex = 1;

    for (final child in children) {
      if (child is md.Element && child.tag == 'ol' && child.children != null) {
        for (final li in child.children!) {
          if (li is md.Element && li.tag == 'li') {
            final fnId = li.attributes['id'];
            GlobalKey? itemKey;
            if (fnId != null && fnId.isNotEmpty) {
              itemKey = GlobalKey(debugLabel: fnId);
              anchorKeys[fnId] = itemKey;
            }

            final spans = _buildFootnoteItemSpans(
              li.children,
              baseStyle: baseStyle,
              linkColor: linkColor,
              codeBg: codeBg,
              footnoteFontSize: footnoteFontSize,
            );

            itemWidgets.add(
              Padding(
                key: itemKey,
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 28.0,
                      child: Text(
                        '$itemIndex.',
                        textAlign: TextAlign.right,
                        style: baseStyle.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Text.rich(
                        TextSpan(style: baseStyle, children: spans),
                      ),
                    ),
                  ],
                ),
              ),
            );
            itemIndex++;
          }
        }
      }
    }

    if (itemWidgets.isEmpty) return null;

    return Container(
      key: const Key('footnotes_section'),
      margin: const EdgeInsets.only(top: 28.0),
      padding: const EdgeInsets.only(top: 16.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: itemWidgets,
      ),
    );
  }

  List<InlineSpan> _buildFootnoteItemSpans(
    List<md.Node>? nodes, {
    required TextStyle baseStyle,
    required Color linkColor,
    required Color? codeBg,
    required double footnoteFontSize,
  }) {
    if (nodes == null || nodes.isEmpty) return const [];
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      if (node is md.Text) {
        final cleaned = node.text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
        if (cleaned.isNotEmpty) {
          spans.add(TextSpan(text: cleaned));
        }
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'p':
            if (spans.isNotEmpty) {
              spans.add(const TextSpan(text: ' '));
            }
            spans.addAll(
              _buildFootnoteItemSpans(
                node.children,
                baseStyle: baseStyle,
                linkColor: linkColor,
                codeBg: codeBg,
                footnoteFontSize: footnoteFontSize,
              ),
            );
          case 'code':
            spans.add(
              TextSpan(
                text: node.textContent,
                style: GoogleFonts.firaCode(
                  fontSize: footnoteFontSize * 0.92,
                  backgroundColor: codeBg,
                  color: baseStyle.color,
                ),
              ),
            );
          case 'strong':
            spans.add(
              TextSpan(
                style: const TextStyle(fontWeight: FontWeight.bold),
                children: _buildFootnoteItemSpans(
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                  footnoteFontSize: footnoteFontSize,
                ),
              ),
            );
          case 'em':
            spans.add(
              TextSpan(
                style: const TextStyle(fontStyle: FontStyle.italic),
                children: _buildFootnoteItemSpans(
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                  footnoteFontSize: footnoteFontSize,
                ),
              ),
            );
          case 'del':
            spans.add(
              TextSpan(
                style: const TextStyle(decoration: TextDecoration.lineThrough),
                children: _buildFootnoteItemSpans(
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                  footnoteFontSize: footnoteFontSize,
                ),
              ),
            );
          case 'a':
            final href = node.attributes['href'];
            final title = node.attributes['title'] ?? '';
            final isBackref = node.attributes['class'] == 'footnote-backref';
            if (isBackref) {
              // Replace '\u21a9' with '\u21a9\uFE0E' so macOS renders a crisp
              // typographic return arrow instead of the 3D color emoji.
              final rawLabel = node.textContent.replaceAll(
                '\u21a9',
                '\u21a9\uFE0E',
              );
              spans.add(
                TextSpan(
                  text: rawLabel,
                  style: TextStyle(
                    color: linkColor,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => onTapLink(rawLabel, href, title),
                ),
              );
            } else {
              final linkText = node.textContent;
              spans.add(
                TextSpan(
                  text: linkText,
                  style: TextStyle(
                    color: linkColor,
                    decoration: TextDecoration.underline,
                    decorationColor: linkColor,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => onTapLink(linkText, href, title),
                ),
              );
            }
          default:
            if (node.children != null && node.children!.isNotEmpty) {
              spans.addAll(
                _buildFootnoteItemSpans(
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                  footnoteFontSize: footnoteFontSize,
                ),
              );
            } else if (node.textContent.isNotEmpty) {
              spans.add(TextSpan(text: node.textContent));
            }
        }
      }
    }
    return spans;
  }
}
