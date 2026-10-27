import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import 'image_zoom_dialog.dart';
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

// --- Inline HTML Support ---

class HtmlAttributeParser {
  static final RegExp _attrRegex = RegExp(
    r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
  );

  static Map<String, String> parse(String rawAttributes) {
    final attrs = <String, String>{};
    for (final match in _attrRegex.allMatches(rawAttributes)) {
      final key = match.group(1)!.toLowerCase();
      final val = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attrs[key] = val;
    }
    return attrs;
  }

  static double? parseDimension(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'px$', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty || cleaned.endsWith('%')) return null;
    final val = double.tryParse(cleaned);
    return (val != null && val > 0) ? val : null;
  }

  static String extractFirstSrcsetUrl(String? srcset) {
    if (srcset == null || srcset.trim().isEmpty) return '';
    final firstCandidate = srcset.split(',').first.trim();
    if (firstCandidate.isEmpty) return '';
    return firstCandidate.split(RegExp(r'\s+')).first.trim();
  }
}

/// Strips inline `<!-- ... -->` comments.
class HtmlCommentInlineSyntax extends md.InlineSyntax {
  HtmlCommentInlineSyntax() : super(r'<!--[\s\S]*?-->');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    return true;
  }
}

/// Parses `<br>`, `<br/>`, and `<br />` into hard line breaks.
class HtmlBrInlineSyntax extends md.InlineSyntax {
  HtmlBrInlineSyntax() : super(r'<br\s*/?>', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// Parses `<picture>...</picture>` elements with optional dark/light `<source>`
/// media queries and fallback `<img>` attributes into an `html_img` element.
class HtmlPictureInlineSyntax extends md.InlineSyntax {
  HtmlPictureInlineSyntax()
    : super(r'<picture\b[^>]*>([\s\S]*?)</picture>', caseSensitive: false);

  static final RegExp _sourceRegex = RegExp(
    r'<source\b([^>]*?)/?>',
    caseSensitive: false,
  );
  static final RegExp _imgRegex = RegExp(
    r'<img\b([^>]*?)/?>',
    caseSensitive: false,
  );

  static md.Element? parsePictureElement(String innerHtml) {
    String? darkSrc;
    String? lightSrc;

    for (final sourceMatch in _sourceRegex.allMatches(innerHtml)) {
      final attrs = HtmlAttributeParser.parse(sourceMatch.group(1) ?? '');
      final media = (attrs['media'] ?? '').toLowerCase();
      final candidate = HtmlAttributeParser.extractFirstSrcsetUrl(
        attrs['srcset'] ?? attrs['src'],
      );
      if (candidate.isEmpty) continue;
      if (media.contains('prefers-color-scheme') && media.contains('dark')) {
        darkSrc ??= candidate;
      } else if (media.contains('prefers-color-scheme') &&
          media.contains('light')) {
        lightSrc ??= candidate;
      }
    }

    final imgMatch = _imgRegex.firstMatch(innerHtml);
    final imgAttrs = imgMatch != null
        ? HtmlAttributeParser.parse(imgMatch.group(1) ?? '')
        : <String, String>{};

    final fallbackSrc = imgAttrs['src'] ?? lightSrc ?? darkSrc ?? '';
    if (fallbackSrc.isEmpty && darkSrc == null && lightSrc == null) {
      return null;
    }

    final el = md.Element.empty('html_img');
    if (fallbackSrc.isNotEmpty) el.attributes['src'] = fallbackSrc;
    if (darkSrc != null && darkSrc.isNotEmpty) {
      el.attributes['dark_src'] = darkSrc;
    }
    if (lightSrc != null && lightSrc.isNotEmpty) {
      el.attributes['light_src'] = lightSrc;
    }
    for (final key in const ['alt', 'title', 'width', 'height', 'align']) {
      final val = imgAttrs[key];
      if (val != null && val.isNotEmpty) {
        el.attributes[key] = val;
      }
    }
    return el;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = parsePictureElement(match.group(1) ?? '');
    if (el == null) return false;
    parser.addNode(el);
    return true;
  }
}

/// Parses standalone `<img ...>` tags into `html_img` elements preserving
/// `src`, `alt`, `title`, `width`, `height`, and `align`.
class HtmlImgInlineSyntax extends md.InlineSyntax {
  HtmlImgInlineSyntax() : super(r'<img\b([^>]*?)/?>', caseSensitive: false);

  static md.Element? parseImgAttributes(String rawAttrs) {
    final attrs = HtmlAttributeParser.parse(rawAttrs);
    final src = attrs['src']?.trim() ?? '';
    if (src.isEmpty) return null;

    final el = md.Element.empty('html_img');
    el.attributes['src'] = src;
    for (final key in const ['alt', 'title', 'width', 'height', 'align']) {
      final val = attrs[key];
      if (val != null && val.isNotEmpty) {
        el.attributes[key] = val;
      }
    }
    return el;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = parseImgAttributes(match.group(1) ?? '');
    if (el == null) return false;
    parser.addNode(el);
    return true;
  }
}

/// Parses `<a ...>...</a>` and `<a id="..." />` tags, supporting anchor
/// registration (`id` / `name`), hyperlinked text, and hyperlinked `<img>` /
/// `<picture>` elements.
class HtmlAnchorInlineSyntax extends md.InlineSyntax {
  HtmlAnchorInlineSyntax()
    : super(r'<a\b([^>]*?)(?:/>|>([\s\S]*?)</a>)', caseSensitive: false);

  static final RegExp _headingWrapperRegex = RegExp(
    r'^\s*<h([1-6])\b([^>]*)>([\s\S]*?)</h\1>\s*$',
    caseSensitive: false,
  );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final attrs = HtmlAttributeParser.parse(match.group(1) ?? '');
    final rawInner = match.group(2) ?? '';
    final href = attrs['href']?.trim();
    final title = attrs['title']?.trim() ?? '';
    final anchorId = (attrs['id']?.trim().isNotEmpty == true)
        ? attrs['id']!.trim()
        : attrs['name']?.trim();

    if (anchorId != null && anchorId.isNotEmpty) {
      final anchorEl = md.Element('anchor', []);
      anchorEl.attributes['id'] = anchorId;
      parser.addNode(anchorEl);
    }

    if (rawInner.trim().isEmpty) {
      return true;
    }

    // Unwrap an inner <h1..h6> if <a href="..."> wraps a heading in inline context.
    String innerToParse = rawInner.trim();
    final headingMatch = _headingWrapperRegex.firstMatch(innerToParse);
    if (headingMatch != null) {
      innerToParse = headingMatch.group(3)!.trim();
    }

    final children = parser.document.parseInline(innerToParse);
    if (href != null && href.isNotEmpty) {
      _attachHrefToImages(children, href, title);

      // If the anchor solely wraps image(s) and whitespace, add the image
      // elements directly so flutter_markdown renders them with their own
      // GestureDetector link handler.
      final nonWhitespace = children.where((node) {
        if (node is md.Text) return node.text.trim().isNotEmpty;
        return true;
      }).toList();

      if (nonWhitespace.isNotEmpty &&
          nonWhitespace.every(
            (n) => n is md.Element && (n.tag == 'html_img' || n.tag == 'img'),
          )) {
        for (final imgNode in nonWhitespace) {
          parser.addNode(imgNode);
        }
        return true;
      }

      final linkEl = md.Element('a', children);
      linkEl.attributes['href'] = href;
      if (title.isNotEmpty) {
        linkEl.attributes['title'] = title;
      }
      parser.addNode(linkEl);
      return true;
    }

    for (final child in children) {
      parser.addNode(child);
    }
    return true;
  }

  static void _attachHrefToImages(
    List<md.Node>? nodes,
    String href,
    String title,
  ) {
    if (nodes == null) return;
    for (final node in nodes) {
      if (node is md.Element) {
        if (node.tag == 'html_img' || node.tag == 'img') {
          node.attributes['href'] = href;
          if (title.isNotEmpty) {
            node.attributes['link_title'] = title;
          }
        }
        _attachHrefToImages(node.children, href, title);
      }
    }
  }
}

/// Parses inline GFM HTML formatting tags (`<kbd>`, `<sub>`, `<sup>`, `<mark>`,
/// `<u>`, `<ins>`, `<s>`, `<del>`, `<strike>`, `<b>`, `<strong>`, `<i>`,
/// `<em>`, `<cite>`, `<dfn>`, `<code>`, `<samp>`, `<tt>`, `<var>`, `<small>`,
/// `<q>`, `<abbr>`, and `<span>`).
class HtmlInlineTagSyntax extends md.InlineSyntax {
  HtmlInlineTagSyntax()
    : super(
        r'<(kbd|sub|sup|mark|u|ins|s|del|strike|b|strong|i|em|cite|dfn|code|samp|tt|var|small|q|abbr|span)\b([^>]*)>([\s\S]*?)</\1>',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final rawTag = match.group(1)!.toLowerCase();
    final attrs = HtmlAttributeParser.parse(match.group(2) ?? '');
    final inner = match.group(3) ?? '';

    final anchorId = (attrs['id']?.trim().isNotEmpty == true)
        ? attrs['id']!.trim()
        : attrs['name']?.trim();
    if (anchorId != null && anchorId.isNotEmpty) {
      final anchorEl = md.Element('anchor', []);
      anchorEl.attributes['id'] = anchorId;
      parser.addNode(anchorEl);
    }

    if (rawTag == 'code' || rawTag == 'samp' || rawTag == 'tt') {
      parser.addNode(md.Element.text('code', inner));
      return true;
    }

    if (rawTag == 'var') {
      parser.addNode(md.Element('em', [md.Element.text('code', inner)]));
      return true;
    }

    final children = parser.document.parseInline(inner);
    if (rawTag == 'q') {
      parser.addNode(md.Text('“'));
      for (final child in children) {
        parser.addNode(child);
      }
      parser.addNode(md.Text('”'));
      return true;
    }

    final mappedTag = switch (rawTag) {
      'kbd' => 'kbd',
      'sub' => 'sub',
      'sup' => 'sup',
      'mark' => 'highlight',
      'u' || 'ins' => 'u',
      's' || 'del' || 'strike' => 'del',
      'b' || 'strong' => 'strong',
      'i' || 'em' || 'cite' || 'dfn' => 'em',
      'small' => 'small',
      'abbr' => 'abbr',
      _ => 'span',
    };

    if (mappedTag == 'span') {
      for (final child in children) {
        parser.addNode(child);
      }
      return true;
    }

    final el = md.Element(mappedTag, children);
    if (mappedTag == 'abbr' && attrs['title'] != null) {
      el.attributes['title'] = attrs['title']!;
    }
    parser.addNode(el);
    return true;
  }
}

/// Renders `<kbd>` elements as native desktop keycap badges.
class KbdBuilder extends MarkdownElementBuilder {
  final double baseFontSize;

  KbdBuilder({required this.baseFontSize});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sirenColors = theme.extension<SirenColors>();
    final dividerColor =
        sirenColors?.divider ?? theme.colorScheme.outlineVariant;
    final bg =
        sirenColors?.codeBlockHeaderBg ??
        sirenColors?.codeBg ??
        theme.colorScheme.surfaceContainerHighest;

    return SelectionContainer.disabled(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4.0),
          border: Border.all(color: dividerColor, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              offset: const Offset(0, 1.0),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          element.textContent,
          style: GoogleFonts.firaCode(
            fontSize: (preferredStyle?.fontSize ?? baseFontSize) * 0.85,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Renders `<u>` and `<ins>` elements with underline decoration.
class UnderlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base =
        preferredStyle ??
        parentStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle();
    return Text(
      element.textContent,
      style: base.copyWith(decoration: TextDecoration.underline),
    );
  }
}

/// Renders `<small>` elements with reduced font size.
class SmallTextBuilder extends MarkdownElementBuilder {
  final double baseFontSize;

  SmallTextBuilder({required this.baseFontSize});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base =
        preferredStyle ??
        parentStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        TextStyle(fontSize: baseFontSize);
    final resolvedSize = (base.fontSize ?? baseFontSize) * 0.85;
    return Text(
      element.textContent,
      style: base.copyWith(fontSize: resolvedSize),
    );
  }
}

/// Renders `<abbr title="...">` elements with a dotted underline and tooltip.
class AbbrBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base =
        preferredStyle ??
        parentStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle();
    final title = element.attributes['title']?.trim() ?? '';
    final textWidget = Text(
      element.textContent,
      style: base.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
      ),
    );
    if (title.isEmpty) return textWidget;
    return Tooltip(message: title, child: textWidget);
  }
}

// --- Offscreen WebKit SVG Rasterizer ---

@immutable
class _SvgRasterResult {
  const _SvgRasterResult({
    required this.pngBytes,
    required this.logicalWidth,
    required this.logicalHeight,
  });

  final Uint8List pngBytes;
  final double logicalWidth;
  final double logicalHeight;
}

class _SvgRasterJob {
  _SvgRasterJob({
    required this.cacheKey,
    required this.svgXml,
    required this.targetWidth,
    required this.targetHeight,
    required this.completer,
  });

  final String cacheKey;
  final String svgXml;
  final double? targetWidth;
  final double? targetHeight;
  final Completer<_SvgRasterResult?> completer;
}

/// Renders arbitrary SVG XML (including `img.shields.io` badges with nested
class _NetworkImagePayload {
  final Uint8List bytes;
  final String contentType;
  final bool isSvg;
  final String? svgXml;

  const _NetworkImagePayload({
    required this.bytes,
    required this.contentType,
    required this.isSvg,
    this.svgXml,
  });
}

/// Compiles SVG images (including complex Shields.io badges with embedded
/// base64 `<image>` logos, `<linearGradient>`, and `transform="scale(.1)"`
/// text) to high-DPI 3x Retina PNGs via a shared offscreen [WebViewController].
class _SvgRasterService {
  _SvgRasterService._();

  static final _SvgRasterService instance = _SvgRasterService._();

  static const int _maxCacheEntries = 128;
  static const double _rasterScale = 3.0;
  static const String _channelName = 'SirenSvgRaster';
  static const String _browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  static const String _browserAcceptHeader =
      'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

  final LinkedHashMap<String, _SvgRasterResult> _cache =
      LinkedHashMap<String, _SvgRasterResult>();
  final LinkedHashMap<String, _NetworkImagePayload> _payloadCache =
      LinkedHashMap<String, _NetworkImagePayload>();
  final Map<String, Future<_NetworkImagePayload?>> _payloadInFlight =
      <String, Future<_NetworkImagePayload?>>{};
  final Map<String, Future<_SvgRasterResult?>> _inFlight =
      <String, Future<_SvgRasterResult?>>{};
  final Queue<_SvgRasterJob> _queue = Queue<_SvgRasterJob>();

  WebViewController? _controller;
  Completer<void>? _readyCompleter;
  Completer<Map<String, dynamic>>? _pendingRequest;
  String? _pendingRequestId;
  bool _processing = false;
  int _reqCounter = 0;

  static String buildCacheKey(
    String sourceKey,
    double? targetWidth,
    double? targetHeight,
  ) => '$sourceKey|w=${targetWidth ?? 'auto'}|h=${targetHeight ?? 'auto'}';

  _SvgRasterResult? peek(String cacheKey) {
    final existing = _cache.remove(cacheKey);
    if (existing != null) {
      _cache[cacheKey] = existing;
    }
    return existing;
  }

  _NetworkImagePayload? peekPayload(String url) {
    final existing = _payloadCache.remove(url);
    if (existing != null) {
      _payloadCache[url] = existing;
    }
    return existing;
  }

  void _putCache(String key, _SvgRasterResult value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _putPayloadCache(String url, _NetworkImagePayload value) {
    _payloadCache.remove(url);
    _payloadCache[url] = value;
    while (_payloadCache.length > _maxCacheEntries) {
      _payloadCache.remove(_payloadCache.keys.first);
    }
  }

  Future<_NetworkImagePayload?> fetchNetworkPayload(String url) {
    final cached = peekPayload(url);
    if (cached != null) {
      return Future<_NetworkImagePayload?>.value(cached);
    }
    final inFlight = _payloadInFlight[url];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _doFetchNetworkPayload(url);
    _payloadInFlight[url] = future;
    return future.whenComplete(() {
      _payloadInFlight.remove(url);
    });
  }

  Future<_NetworkImagePayload?> _doFetchNetworkPayload(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      request.headers.set(HttpHeaders.acceptHeader, _browserAcceptHeader);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 10));
      if (bytes.isEmpty) {
        return null;
      }
      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final isSvg = HtmlImageBuilder.isSvgPayload(
        contentType: contentType,
        bytes: bytes,
      );
      final payload = _NetworkImagePayload(
        bytes: bytes,
        contentType: contentType,
        isSvg: isSvg,
        svgXml: isSvg ? utf8.decode(bytes, allowMalformed: true) : null,
      );
      _putPayloadCache(url, payload);
      return payload;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<_SvgRasterResult?> rasterizeSvg({
    required String cacheKey,
    required String svgXml,
    double? targetWidth,
    double? targetHeight,
  }) {
    final cached = peek(cacheKey);
    if (cached != null) {
      return Future<_SvgRasterResult?>.value(cached);
    }
    final existing = _inFlight[cacheKey];
    if (existing != null) {
      return existing;
    }
    final completer = Completer<_SvgRasterResult?>();
    _inFlight[cacheKey] = completer.future;
    _queue.add(
      _SvgRasterJob(
        cacheKey: cacheKey,
        svgXml: svgXml,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        completer: completer,
      ),
    );
    _pumpQueue();
    return completer.future;
  }

  void _pumpQueue() {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    unawaited(_processLoop());
  }

  Future<void> _processLoop() async {
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        final cached = _cache[job.cacheKey];
        if (cached != null) {
          _inFlight.remove(job.cacheKey);
          if (!job.completer.isCompleted) {
            job.completer.complete(cached);
          }
          continue;
        }

        _SvgRasterResult? result;
        try {
          result = await _executeJob(job);
        } catch (_) {
          result = null;
        }

        _inFlight.remove(job.cacheKey);
        if (result != null) {
          _putCache(job.cacheKey, result);
        }
        if (!job.completer.isCompleted) {
          job.completer.complete(result);
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<WebViewController> _ensureController() async {
    if (_controller != null && _readyCompleter != null) {
      await _readyCompleter!.future;
      return _controller!;
    }

    final ready = Completer<void>();
    _readyCompleter = ready;
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      _channelName,
      onMessageReceived: (JavaScriptMessage msg) {
        _handleMessage(msg.message);
      },
    );
    await controller.loadHtmlString(_bootstrapHtml);
    await ready.future.timeout(const Duration(seconds: 10));
    _controller = controller;
    return controller;
  }

  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['kind'] == 'ready') {
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
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
    } catch (_) {}
  }

  Future<_SvgRasterResult?> _executeJob(_SvgRasterJob job) async {
    final controller = await _ensureController();
    final id = 'svg_${++_reqCounter}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequest = completer;
    _pendingRequestId = id;

    final payload = jsonEncode(<String, Object?>{
      'id': id,
      'svg': job.svgXml,
      'width': job.targetWidth,
      'height': job.targetHeight,
      'scale': _rasterScale,
    });

    await controller.runJavaScript('window.sirenSvg.render($payload);');
    final response = await completer.future.timeout(
      const Duration(seconds: 10),
    );
    if (response['kind'] != 'ok') return null;

    final pngBase64 = response['png'] as String? ?? '';
    final width = (response['width'] as num?)?.toDouble() ?? 0;
    final height = (response['height'] as num?)?.toDouble() ?? 0;
    if (pngBase64.isEmpty || width <= 0 || height <= 0) return null;

    final bytes = base64Decode(pngBase64);
    return _SvgRasterResult(
      pngBytes: bytes,
      logicalWidth: width,
      logicalHeight: height,
    );
  }

  static const String _bootstrapHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;}</style>
<script>
(function() {
  'use strict';
  const PNG_PREFIX = 'data:image/png;base64,';
  const XLINK_NS = 'http://www.w3.org/1999/xlink';

  function send(obj) {
    const text = JSON.stringify(obj);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.SirenSvgRaster) {
      window.webkit.messageHandlers.SirenSvgRaster.postMessage(text);
    } else if (window.SirenSvgRaster) {
      window.SirenSvgRaster.postMessage(text);
    }
  }

  function parsePositiveNum(val) {
    if (!val) return 0;
    const s = String(val).trim();
    if (s.endsWith('%')) return 0;
    const n = parseFloat(s);
    return (Number.isFinite(n) && n > 0) ? n : 0;
  }

  async function reencodeNestedImages(root, scale) {
    const images = Array.from(root.querySelectorAll('image'));
    for (const imgEl of images) {
      const href = imgEl.getAttribute('href') ||
                   imgEl.getAttribute('xlink:href') ||
                   imgEl.getAttributeNS(XLINK_NS, 'href') || '';
      if (!href.startsWith('data:image/')) continue;
      const inner = new Image();
      inner.src = href;
      try {
        await inner.decode();
      } catch (_) {
        continue;
      }
      const w = parsePositiveNum(imgEl.getAttribute('width')) || inner.naturalWidth || 14;
      const h = parsePositiveNum(imgEl.getAttribute('height')) || inner.naturalHeight || 14;
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.ceil(w * scale));
      c.height = Math.max(1, Math.ceil(h * scale));
      c.getContext('2d').drawImage(inner, 0, 0, c.width, c.height);
      const pngUrl = c.toDataURL('image/png');
      imgEl.setAttribute('href', pngUrl);
      imgEl.setAttributeNS(XLINK_NS, 'xlink:href', pngUrl);
    }
  }

  async function renderRequest(req) {
    const scale = Math.max(1, Number(req.scale) || 3);
    const parser = new DOMParser();
    const doc = parser.parseFromString(req.svg, 'image/svg+xml');
    if (doc.getElementsByTagName('parsererror').length > 0) {
      throw new Error('Malformed SVG');
    }
    const root = doc.documentElement;
    if (!root.getAttribute('xmlns')) {
      root.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    }
    if (!root.getAttribute('xmlns:xlink')) {
      root.setAttribute('xmlns:xlink', XLINK_NS);
    }

    await reencodeNestedImages(root, scale);

    let naturalW = parsePositiveNum(root.getAttribute('width'));
    let naturalH = parsePositiveNum(root.getAttribute('height'));
    const vbAttr = root.getAttribute('viewBox');
    if (vbAttr) {
      const parts = vbAttr.trim().split(/[\\s,]+/).map(Number);
      if (parts.length === 4 && parts[2] > 0 && parts[3] > 0) {
        if (!naturalW) naturalW = parts[2];
        if (!naturalH) naturalH = parts[3];
      }
    } else if (naturalW > 0 && naturalH > 0) {
      root.setAttribute('viewBox', '0 0 ' + naturalW + ' ' + naturalH);
    }

    if (!naturalW) naturalW = 100;
    if (!naturalH) naturalH = 20;

    let logicalW = Number(req.width) > 0 ? Number(req.width) : 0;
    let logicalH = Number(req.height) > 0 ? Number(req.height) : 0;
    if (logicalW > 0 && logicalH <= 0) {
      logicalH = logicalW * (naturalH / naturalW);
    } else if (logicalH > 0 && logicalW <= 0) {
      logicalW = logicalH * (naturalW / naturalH);
    } else if (logicalW <= 0 && logicalH <= 0) {
      logicalW = naturalW;
      logicalH = naturalH;
    }

    root.setAttribute('width', String(logicalW));
    root.setAttribute('height', String(logicalH));

    const serialized = new XMLSerializer().serializeToString(root);
    const outerImg = new Image();
    outerImg.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(serialized);
    await outerImg.decode();

    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.ceil(logicalW * scale));
    canvas.height = Math.max(1, Math.ceil(logicalH * scale));
    const ctx = canvas.getContext('2d');
    ctx.drawImage(outerImg, 0, 0, canvas.width, canvas.height);
    const dataUrl = canvas.toDataURL('image/png');
    if (!dataUrl.startsWith(PNG_PREFIX)) {
      throw new Error('Failed to encode PNG');
    }
    return {
      id: req.id,
      kind: 'ok',
      png: dataUrl.slice(PNG_PREFIX.length),
      width: logicalW,
      height: logicalH
    };
  }

  window.sirenSvg = {
    render: async function(req) {
      try {
        send(await renderRequest(req));
      } catch (e) {
        send({id: req && req.id, kind: 'error', message: String(e)});
      }
    }
  };
  send({kind: 'ready'});
})();
</script>
</head>
<body></body>
</html>
''';
}

/// Renders a browser/GitHub-style broken image fallback that preserves the
/// `alt` text in the surrounding typography (such as inside an `<h1>`).
class _BrokenImageFallback extends StatelessWidget {
  final String? altText;
  final String? semanticsLabel;

  const _BrokenImageFallback({this.altText, this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final cleanAlt = altText?.trim() ?? '';
    final label = semanticsLabel?.trim() ?? cleanAlt;
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final iconColor =
        inheritedStyle.color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      label: label.isNotEmpty
          ? 'Image failed to load: $label'
          : 'Image failed to load',
      child: cleanAlt.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: (inheritedStyle.fontSize ?? 16.0).clamp(16.0, 28.0),
                  color: iconColor.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 6.0),
                Flexible(child: Text(cleanAlt, style: inheritedStyle)),
              ],
            )
          : Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: iconColor.withValues(alpha: 0.65),
            ),
    );
  }
}

/// Loads network images (raster or SVG) by inspecting the HTTP `Content-Type`
/// header and payload bytes rather than guessing from URL extensions or domains.
class _BrowserSvgImage extends StatefulWidget {
  final String? networkUrl;
  final File? localFile;
  final double? width;
  final double? height;
  final String? semanticsLabel;
  final String? altText;

  const _BrowserSvgImage({
    this.networkUrl,
    this.localFile,
    this.width,
    this.height,
    this.semanticsLabel,
    this.altText,
  });

  @override
  State<_BrowserSvgImage> createState() => _BrowserSvgImageState();
}

class _BrowserSvgImageState extends State<_BrowserSvgImage> {
  _SvgRasterResult? _svgResult;
  Uint8List? _rasterBytes;
  String? _fallbackSvgXml;
  bool _failed = false;
  bool _loading = true;

  String get _cacheKey => _SvgRasterService.buildCacheKey(
    widget.networkUrl ?? widget.localFile?.path ?? '',
    widget.width,
    widget.height,
  );

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _BrowserSvgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.localFile?.path != widget.localFile?.path ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final key = _cacheKey;
    final cachedSvg = _SvgRasterService.instance.peek(key);
    if (cachedSvg != null) {
      setState(() {
        _svgResult = cachedSvg;
        _rasterBytes = null;
        _fallbackSvgXml = null;
        _loading = false;
        _failed = false;
      });
      return;
    }

    if (widget.networkUrl != null) {
      final cachedPayload = _SvgRasterService.instance.peekPayload(
        widget.networkUrl!,
      );
      if (cachedPayload != null && !cachedPayload.isSvg) {
        setState(() {
          _rasterBytes = cachedPayload.bytes;
          _svgResult = null;
          _fallbackSvgXml = null;
          _loading = false;
          _failed = false;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _failed = false;
      _svgResult = null;
      _rasterBytes = null;
      _fallbackSvgXml = null;
    });

    String? svgXml;
    if (widget.networkUrl != null) {
      final payload = await _SvgRasterService.instance.fetchNetworkPayload(
        widget.networkUrl!,
      );
      if (!mounted) return;
      if (payload == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      if (!payload.isSvg) {
        setState(() {
          _rasterBytes = payload.bytes;
          _loading = false;
          _failed = false;
        });
        return;
      }
      svgXml = payload.svgXml;
    } else if (widget.localFile != null) {
      try {
        svgXml = await widget.localFile!.readAsString();
      } catch (_) {
        svgXml = null;
      }
    }

    if (!mounted) return;
    if (svgXml == null || svgXml.trim().isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    final raster = await _SvgRasterService.instance.rasterizeSvg(
      cacheKey: key,
      svgXml: svgXml,
      targetWidth: widget.width,
      targetHeight: widget.height,
    );

    if (!mounted) return;
    if (raster != null) {
      setState(() {
        _svgResult = raster;
        _loading = false;
        _failed = false;
      });
    } else {
      setState(() {
        _fallbackSvgXml = svgXml;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_svgResult != null) {
      return Image.memory(
        _svgResult!.pngBytes,
        width: _svgResult!.logicalWidth,
        height: _svgResult!.logicalHeight,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: widget.semanticsLabel,
      );
    }

    if (_rasterBytes != null) {
      return Image.memory(
        _rasterBytes!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: widget.semanticsLabel,
        errorBuilder: (context, error, stackTrace) => _BrokenImageFallback(
          altText: widget.altText,
          semanticsLabel: widget.semanticsLabel,
        ),
      );
    }

    if (_fallbackSvgXml != null) {
      return SvgPicture.string(
        _fallbackSvgXml!,
        width: widget.width,
        height: widget.height,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    if (_loading) {
      return SizedBox(
        width: widget.width ?? 80.0,
        height: widget.height ?? 20.0,
      );
    }

    if (_failed) {
      return _BrokenImageFallback(
        altText: widget.altText,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    return const SizedBox.shrink();
  }
}

/// Renders `html_img` (`<img>` and `<picture>`) elements as well as standard
/// Markdown images with support for `width`/`height` attributes, dark/light
/// theme `<picture>` sources, HTTP Content-Type/payload SVG detection,
/// offscreen 3x WebKit SVG rasterization, hyperlink wrapping, and the
/// interactive `ImageZoomDialog` lightbox.
class HtmlImageBuilder extends MarkdownElementBuilder {
  final String basePath;
  final String? explorerRootPath;
  final void Function(String text, String? href, String title) onTapLink;

  HtmlImageBuilder({
    required this.basePath,
    required this.explorerRootPath,
    required this.onTapLink,
  });

  /// Determines whether an HTTP response or file payload is SVG XML by
  /// inspecting the MIME `Content-Type` and leading bytes (ignoring URL paths
  /// or file extensions).
  static bool isSvgPayload({
    required String? contentType,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty) return false;

    // Fast path for binary raster magic bytes (PNG, JPEG, GIF, WebP)
    if (bytes.length >= 4) {
      // PNG: 89 50 4E 47
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return false;
      }
      // JPEG: FF D8 FF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return false;
      }
      // GIF: 'GIF8'
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return false;
      }
      // WebP: 'RIFF'....'WEBP'
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return false;
      }
    }

    final lowerType = (contentType ?? '').toLowerCase();
    if (lowerType.contains('image/svg+xml')) {
      return true;
    }

    final sampleLen = bytes.length > 2048 ? 2048 : bytes.length;
    final head = utf8
        .decode(bytes.sublist(0, sampleLen), allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trimLeft();

    if (head.isEmpty) return false;
    if (RegExp(r'^<svg[\s>]', caseSensitive: false).hasMatch(head)) {
      return true;
    }
    if ((head.startsWith('<?xml') ||
            RegExp(r'^<!DOCTYPE\s+svg', caseSensitive: false).hasMatch(head) ||
            head.startsWith('<!--')) &&
        RegExp(r'<svg[\s>]', caseSensitive: false).hasMatch(head) &&
        !RegExp(
          r'<!DOCTYPE\s+html|<html[\s>]',
          caseSensitive: false,
        ).hasMatch(head)) {
      return true;
    }
    return false;
  }

  static bool _isLocalSvgFile(File file) {
    if (file.path.toLowerCase().endsWith('.svg')) {
      return true;
    }
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final sample = raf.readSync(512);
        return isSvgPayload(contentType: null, bytes: sample);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  File? _resolveLocalFile(String localPath) {
    final decoded = Uri.decodeComponent(localPath);
    if (decoded.isEmpty) return null;
    final cleanRel = decoded.startsWith('/') ? decoded.substring(1) : decoded;
    final primaryPath = p.normalize(p.join(basePath, decoded));
    final primaryFile = File(primaryPath);
    if (primaryFile.existsSync()) return primaryFile;

    if (explorerRootPath != null && explorerRootPath!.isNotEmpty) {
      final rootCandidate = p.normalize(p.join(explorerRootPath!, cleanRel));
      final rootFile = File(rootCandidate);
      if (rootFile.existsSync()) return rootFile;
    }

    // Walk up ancestor directories (up to 4 levels or repository root) so
    // repo-root-relative paths (e.g. 'assets/images/...') resolve even when a
    // subfolder like 'docs/' is opened as the Explorer workspace root.
    if (basePath.isNotEmpty) {
      String currentDir = p.normalize(p.absolute(basePath));
      for (int depth = 0; depth < 4; depth++) {
        final parentDir = p.dirname(currentDir);
        if (parentDir == currentDir) break;
        currentDir = parentDir;
        final candidate = File(p.normalize(p.join(currentDir, cleanRel)));
        if (candidate.existsSync()) return candidate;
        if (Directory(p.join(currentDir, '.git')).existsSync()) {
          break;
        }
      }
    }
    return null;
  }

  Widget buildImageFromAttributes(
    BuildContext context,
    Map<String, String> attributes,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final darkSrc = attributes['dark_src'];
    final lightSrc = attributes['light_src'];
    final fallbackSrc = attributes['src'] ?? '';

    final String activeSrc;
    if (isDark && darkSrc != null && darkSrc.isNotEmpty) {
      activeSrc = darkSrc;
    } else if (!isDark && lightSrc != null && lightSrc.isNotEmpty) {
      activeSrc = lightSrc;
    } else {
      activeSrc = fallbackSrc;
    }

    final uri = Uri.tryParse(activeSrc);
    final alt = attributes['alt'];
    final title = attributes['title'];
    final href = attributes['href'];
    final linkTitle = attributes['link_title'] ?? title ?? '';
    final width = HtmlAttributeParser.parseDimension(attributes['width']);
    final height = HtmlAttributeParser.parseDimension(attributes['height']);

    if (uri == null || activeSrc.isEmpty) {
      return const SizedBox.shrink();
    }

    final label = (alt != null && alt.trim().isNotEmpty)
        ? alt.trim()
        : (title != null && title.trim().isNotEmpty
              ? title.trim()
              : p.basename(uri.path));

    final isInFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
    Widget imageWidget;
    File? resolvedLocalFile;
    bool isLocalSvg = false;
    final isNetwork =
        uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');

    if (isNetwork) {
      final urlStr = uri.toString();
      if (isInFlutterTest) {
        imageWidget = Semantics(
          key: ValueKey<String>('network_image_$urlStr'),
          label: alt ?? label,
          image: true,
          child: SizedBox(
            width: width,
            height: height ?? 20.0,
            child: Text(alt ?? label),
          ),
        );
      } else {
        imageWidget = _BrowserSvgImage(
          networkUrl: urlStr,
          width: width,
          height: height,
          semanticsLabel: alt ?? label,
          altText: alt,
        );
      }
    } else {
      resolvedLocalFile = _resolveLocalFile(uri.path);
      if (resolvedLocalFile != null) {
        isLocalSvg = _isLocalSvgFile(resolvedLocalFile);
        if (isLocalSvg) {
          if (isInFlutterTest) {
            imageWidget = SvgPicture.file(
              resolvedLocalFile,
              width: width,
              height: height,
              semanticsLabel: alt,
            );
          } else {
            imageWidget = _BrowserSvgImage(
              localFile: resolvedLocalFile,
              width: width,
              height: height,
              semanticsLabel: alt ?? label,
              altText: alt,
            );
          }
        } else {
          imageWidget = Image.file(
            resolvedLocalFile,
            width: width,
            height: height,
            semanticLabel: alt,
            errorBuilder: (context, error, stackTrace) => _BrokenImageFallback(
              altText: alt,
              semanticsLabel: alt ?? label,
            ),
          );
        }
      } else {
        return _BrokenImageFallback(altText: alt, semanticsLabel: alt ?? label);
      }
    }

    if (href != null && href.isNotEmpty) {
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onTapLink(label, href, linkTitle),
              child: imageWidget,
            ),
          ),
        ),
      );
    }

    if (isNetwork || isLocalSvg) {
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          child: imageWidget,
        ),
      );
    }

    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          onTap: () {
            if (resolvedLocalFile != null) {
              ImageZoomDialog.showFile(
                context,
                file: resolvedLocalFile,
                title: label,
              );
            }
          },
          child: imageWidget,
        ),
      ),
    );
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return buildImageFromAttributes(context, element.attributes);
  }
}

// --- Block HTML Support ---

String _unescapeHtmlEntities(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

/// Consumes block-level `<!-- ... -->` comments and emits an empty root Text
/// node so `flutter_markdown_plus` renders nothing.
class HtmlCommentBlockSyntax extends md.BlockSyntax {
  const HtmlCommentBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<!--');

  @override
  md.Node parse(md.BlockParser parser) {
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (line.contains('-->')) {
        break;
      }
    }
    return md.Text('');
  }
}

/// Parses standalone `<hr>` / `<hr/>` lines into standard `hr` elements.
class HtmlHrBlockSyntax extends md.BlockSyntax {
  const HtmlHrBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<hr\b[^>]*/?>\s*$', caseSensitive: false);

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty('hr');
  }
}

/// Parses collapsible `<details><summary>...</summary>...</details>` blocks.
class HtmlDetailsBlockSyntax extends md.BlockSyntax {
  const HtmlDetailsBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<details\b([^>]*)>', caseSensitive: false);

  static final RegExp _openDetailsRegex = RegExp(
    r'<details\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _closeDetailsRegex = RegExp(
    r'</details\s*>',
    caseSensitive: false,
  );
  static final RegExp _summaryRegex = RegExp(
    r'<summary\b[^>]*>([\s\S]*?)</summary\s*>',
    caseSensitive: false,
  );

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final openMatch = pattern.firstMatch(firstLine);
    final openAttrs = openMatch != null
        ? HtmlAttributeParser.parse(openMatch.group(1) ?? '')
        : <String, String>{};
    final isOpen = openAttrs.containsKey('open');

    final lines = <String>[];
    int depth = 0;

    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      depth += _openDetailsRegex.allMatches(line).length;
      depth -= _closeDetailsRegex.allMatches(line).length;
      parser.advance();
      if (depth <= 0) {
        break;
      }
    }

    String fullHtml = lines.join('\n').trim();
    // Strip outer <details ...> and </details>
    fullHtml = fullHtml.replaceFirst(
      RegExp(r'^\s*<details\b[^>]*>', caseSensitive: false),
      '',
    );
    fullHtml = fullHtml.replaceFirst(
      RegExp(r'</details\s*>\s*$', caseSensitive: false),
      '',
    );

    String summaryText = 'Details';
    String bodyMarkdown = fullHtml.trim();

    final summaryMatch = _summaryRegex.firstMatch(fullHtml);
    if (summaryMatch != null) {
      summaryText = summaryMatch.group(1)!.trim();
      bodyMarkdown =
          (fullHtml.substring(0, summaryMatch.start) +
                  fullHtml.substring(summaryMatch.end))
              .trim();
    }

    final el = md.Element('details', []);
    el.attributes['summary'] = summaryText;
    el.attributes['body'] = bodyMarkdown;
    el.attributes['open'] = isOpen ? 'true' : 'false';
    if (openAttrs['id'] != null && openAttrs['id']!.isNotEmpty) {
      el.attributes['id'] = openAttrs['id']!;
    }
    return el;
  }
}

/// Parses raw HTML `<table>...</table>` blocks (`<thead>`, `<tbody>`, `<tfoot>`,
/// `<tr>`, `<th>`, `<td>`, and `<caption>`) into `html_table` elements.
class HtmlTableBlockSyntax extends md.BlockSyntax {
  const HtmlTableBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<table\b([^>]*)>', caseSensitive: false);

  static final RegExp _openTableRegex = RegExp(
    r'<table\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _closeTableRegex = RegExp(
    r'</table\s*>',
    caseSensitive: false,
  );

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final openMatch = pattern.firstMatch(firstLine);
    final openAttrs = openMatch != null
        ? HtmlAttributeParser.parse(openMatch.group(1) ?? '')
        : <String, String>{};

    final lines = <String>[];
    int depth = 0;
    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      depth += _openTableRegex.allMatches(line).length;
      depth -= _closeTableRegex.allMatches(line).length;
      parser.advance();
      if (depth <= 0) break;
    }

    final el = md.Element('html_table', []);
    el.attributes['_raw'] = lines.join('\n').trim();
    if (openAttrs['align'] != null && openAttrs['align']!.isNotEmpty) {
      el.attributes['align'] = openAttrs['align']!;
    }
    return el;
  }
}

/// Parses raw HTML `<ul>...</ul>` and `<ol>...</ol>` list blocks into
/// `html_list` elements.
class HtmlListBlockSyntax extends md.BlockSyntax {
  const HtmlListBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<(ul|ol)\b([^>]*)>', caseSensitive: false);

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final match = pattern.firstMatch(firstLine)!;
    final listTag = match.group(1)!.toLowerCase();
    final attrs = HtmlAttributeParser.parse(match.group(2) ?? '');

    final openRegex = RegExp('<$listTag\\b[^>]*>', caseSensitive: false);
    final closeRegex = RegExp('</$listTag\\s*>', caseSensitive: false);

    final lines = <String>[];
    int depth = 0;
    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      depth += openRegex.allMatches(line).length;
      depth -= closeRegex.allMatches(line).length;
      parser.advance();
      if (depth <= 0) break;
    }

    String inner = lines.join('\n').trim();
    inner = inner.replaceFirst(
      RegExp('^\\s*<$listTag\\b[^>]*>', caseSensitive: false),
      '',
    );
    inner = inner.replaceFirst(
      RegExp('</$listTag\\s*>\\s*\$', caseSensitive: false),
      '',
    );

    final el = md.Element('html_list', []);
    el.attributes['ordered'] = listTag == 'ol' ? 'true' : 'false';
    if (attrs['start'] != null && attrs['start']!.isNotEmpty) {
      el.attributes['start'] = attrs['start']!;
    }
    el.attributes['_raw'] = inner.trim();
    return el;
  }
}

/// Parses raw HTML `<dl>...</dl>` description lists (`<dt>` and `<dd>`) into
/// `html_dl` elements.
class HtmlDlBlockSyntax extends md.BlockSyntax {
  const HtmlDlBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<dl\b([^>]*)>', caseSensitive: false);

  static final RegExp _openDlRegex = RegExp(
    r'<dl\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _closeDlRegex = RegExp(r'</dl\s*>', caseSensitive: false);

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = <String>[];
    int depth = 0;
    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      depth += _openDlRegex.allMatches(line).length;
      depth -= _closeDlRegex.allMatches(line).length;
      parser.advance();
      if (depth <= 0) break;
    }

    String inner = lines.join('\n').trim();
    inner = inner.replaceFirst(
      RegExp(r'^\s*<dl\b[^>]*>', caseSensitive: false),
      '',
    );
    inner = inner.replaceFirst(
      RegExp(r'</dl\s*>\s*$', caseSensitive: false),
      '',
    );

    final el = md.Element('html_dl', []);
    el.attributes['_raw'] = inner.trim();
    return el;
  }
}

/// Parses block-level HTML containers (`<p>`, `<div>`, `<center>`, `<section>`,
/// `<article>`, `<header>`, `<footer>`, `<nav>`, `<main>`, `<aside>`,
/// `<h1>`–`<h6>`, `<picture>`, `<img>`, `<blockquote>`, `<pre>`, `<figure>`,
/// and multi-line/block-wrapping `<a>` tags) into native Markdown AST elements.
class HtmlContainerBlockSyntax extends md.BlockSyntax {
  const HtmlContainerBlockSyntax();

  @override
  RegExp get pattern => RegExp(
    r'^\s*<(p|div|center|section|article|header|footer|nav|main|aside|h[1-6]|picture|a|img|blockquote|pre|figure)\b([^>]*)>',
    caseSensitive: false,
  );

  static final RegExp _outerAnchorRegex = RegExp(
    r'^\s*<a\b([^>]*)>([\s\S]*?)</a>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerHeadingRegex = RegExp(
    r'^\s*<h([1-6])\b([^>]*)>([\s\S]*?)</h\1>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerBlockquoteRegex = RegExp(
    r'^\s*<blockquote\b([^>]*)>([\s\S]*?)</blockquote>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerPreRegex = RegExp(
    r'^\s*<pre\b([^>]*)>([\s\S]*?)</pre>\s*$',
    caseSensitive: false,
  );
  static final RegExp _innerCodeRegex = RegExp(
    r'^\s*<code\b([^>]*)>([\s\S]*?)</code>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerFigureRegex = RegExp(
    r'^\s*<figure\b([^>]*)>([\s\S]*?)</figure>\s*$',
    caseSensitive: false,
  );
  static final RegExp _figcaptionRegex = RegExp(
    r'<figcaption\b[^>]*>([\s\S]*?)</figcaption\s*>',
    caseSensitive: false,
  );
  static final RegExp _outerContainerRegex = RegExp(
    r'^\s*<(p|div|center|section|article|header|footer|nav|main|aside)\b([^>]*)>([\s\S]*?)</\1>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerPictureRegex = RegExp(
    r'^\s*<picture\b[^>]*>([\s\S]*?)</picture>\s*$',
    caseSensitive: false,
  );
  static final RegExp _outerImgRegex = RegExp(
    r'^\s*<img\b([^>]*?)/?>\s*$',
    caseSensitive: false,
  );
  static final RegExp _nestedBlockHintRegex = RegExp(
    r'<(p|div|center|section|article|h[1-6]|ul|ol|dl|table|blockquote|pre|details|figure|hr)\b|^\s*#{1,6}\s+|^\s*```',
    caseSensitive: false,
    multiLine: true,
  );

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content;
    final match = pattern.firstMatch(line);
    if (match == null) return false;

    final tag = match.group(1)!.toLowerCase();
    final trimmed = line.trim();

    if (tag == 'img') {
      // Only treat <img> as a standalone block if the line is solely an <img> tag.
      return _outerImgRegex.hasMatch(trimmed);
    }

    if (tag == 'section') {
      // Do not intercept GFM footnote <section class="footnotes">
      final attrs = HtmlAttributeParser.parse(match.group(2) ?? '');
      if (attrs['class'] == 'footnotes') return false;
    }

    if (tag == 'a') {
      // Treat <a> as a block when it spans multiple lines or wraps a block/image tag.
      final closesOnSameLine = RegExp(
        r'</a>\s*$',
        caseSensitive: false,
      ).hasMatch(trimmed);
      if (!closesOnSameLine) return true;
      final wrapsBlockOrMedia = RegExp(
        r'<(h[1-6]|p|div|center|picture|img)\b',
        caseSensitive: false,
      ).hasMatch(trimmed);
      return wrapsBlockOrMedia;
    }

    return true;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final match = pattern.firstMatch(firstLine)!;
    final tag = match.group(1)!.toLowerCase();

    final lines = <String>[];
    if (tag == 'img') {
      lines.add(firstLine);
      parser.advance();
    } else {
      final openTagRegex = RegExp('<$tag\\b[^>]*>', caseSensitive: false);
      final selfClosingRegex = RegExp('<$tag\\b[^>]*/>', caseSensitive: false);
      final closeTagRegex = RegExp('</$tag\\s*>', caseSensitive: false);

      int depth = 0;
      while (!parser.isDone) {
        final line = parser.current.content;
        lines.add(line);
        final opens =
            openTagRegex.allMatches(line).length -
            selfClosingRegex.allMatches(line).length;
        final closes = closeTagRegex.allMatches(line).length;
        depth += opens - closes;
        parser.advance();
        if (depth <= 0) {
          break;
        }
      }
    }

    String rawBlock = lines.join('\n').trim();
    String? outerHref;
    String outerTitle = '';
    String? outerId;

    // 1. Unwrap outer <a ...>...</a> if present
    final anchorMatch = _outerAnchorRegex.firstMatch(rawBlock);
    if (anchorMatch != null) {
      final aAttrs = HtmlAttributeParser.parse(anchorMatch.group(1) ?? '');
      outerHref = aAttrs['href']?.trim();
      outerTitle = aAttrs['title']?.trim() ?? '';
      outerId = (aAttrs['id']?.trim().isNotEmpty == true)
          ? aAttrs['id']!.trim()
          : aAttrs['name']?.trim();
      rawBlock = anchorMatch.group(2)!.trim();
    }

    // 2. Check if inner/current block is <h1..h6>
    final headingMatch = _outerHeadingRegex.firstMatch(rawBlock);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!;
      final hAttrs = HtmlAttributeParser.parse(headingMatch.group(2) ?? '');
      final innerHtml = headingMatch.group(3)!.trim();
      final align = hAttrs['align']?.trim();
      final headingId =
          outerId ??
          ((hAttrs['id']?.trim().isNotEmpty == true)
              ? hAttrs['id']!.trim()
              : hAttrs['name']?.trim());

      final inlineNodes = md.InlineParser(innerHtml, parser.document).parse();
      if (outerHref != null && outerHref.isNotEmpty) {
        HtmlAnchorInlineSyntax._attachHrefToImages(
          inlineNodes,
          outerHref,
          outerTitle,
        );
      }
      if (headingId != null && headingId.isNotEmpty) {
        final anchorEl = md.Element('anchor', []);
        anchorEl.attributes['id'] = headingId;
        inlineNodes.insert(0, anchorEl);
      }

      final hEl = md.Element('h$level', inlineNodes);
      if (align != null && align.isNotEmpty) {
        hEl.attributes['align'] = align;
      }
      return hEl;
    }

    // 3. Check if block is <blockquote>...</blockquote>
    final blockquoteMatch = _outerBlockquoteRegex.firstMatch(rawBlock);
    if (blockquoteMatch != null) {
      final inner = blockquoteMatch.group(2)!.trim();
      final children = parser.document.parseLines(inner.split('\n'));
      return md.Element('blockquote', children);
    }

    // 4. Check if block is <pre>...</pre>
    final preMatch = _outerPreRegex.firstMatch(rawBlock);
    if (preMatch != null) {
      final preAttrs = HtmlAttributeParser.parse(preMatch.group(1) ?? '');
      String codeContent = preMatch.group(2)!;
      String? langClass = preAttrs['class'];
      final codeMatch = _innerCodeRegex.firstMatch(codeContent);
      if (codeMatch != null) {
        final codeAttrs = HtmlAttributeParser.parse(codeMatch.group(1) ?? '');
        langClass = codeAttrs['class'] ?? langClass;
        codeContent = codeMatch.group(2)!;
      }
      if (codeContent.startsWith('\n')) {
        codeContent = codeContent.substring(1);
      }
      if (codeContent.endsWith('\n')) {
        codeContent = codeContent.substring(0, codeContent.length - 1);
      }
      final unescaped = _unescapeHtmlEntities(codeContent);
      final codeEl = md.Element.text('code', '$unescaped\n');
      if (langClass != null && langClass.isNotEmpty) {
        codeEl.attributes['class'] = langClass;
      }
      return md.Element('pre', [codeEl]);
    }

    // 5. Check if block is <figure>...</figure>
    final figureMatch = _outerFigureRegex.firstMatch(rawBlock);
    if (figureMatch != null) {
      final fAttrs = HtmlAttributeParser.parse(figureMatch.group(1) ?? '');
      String inner = figureMatch.group(2)!.trim();
      String caption = '';
      final capMatch = _figcaptionRegex.firstMatch(inner);
      if (capMatch != null) {
        caption = capMatch.group(1)!.trim();
        inner =
            (inner.substring(0, capMatch.start) + inner.substring(capMatch.end))
                .trim();
      }
      final figEl = md.Element('html_figure', []);
      figEl.attributes['body'] = inner;
      if (caption.isNotEmpty) {
        figEl.attributes['caption'] = caption;
      }
      if (fAttrs['align'] != null && fAttrs['align']!.isNotEmpty) {
        figEl.attributes['align'] = fAttrs['align']!;
      }
      return figEl;
    }

    // 6. Check if block is <picture>...</picture>
    final pictureMatch = _outerPictureRegex.firstMatch(rawBlock);
    if (pictureMatch != null) {
      final picEl = HtmlPictureInlineSyntax.parsePictureElement(
        pictureMatch.group(1) ?? '',
      );
      if (picEl != null) {
        if (outerHref != null && outerHref.isNotEmpty) {
          picEl.attributes['href'] = outerHref;
          if (outerTitle.isNotEmpty) {
            picEl.attributes['link_title'] = outerTitle;
          }
        }
        final blockEl = md.Element('html_block', [picEl]);
        blockEl.attributes['tag'] = 'picture';
        if (picEl.attributes['align'] != null) {
          blockEl.attributes['align'] = picEl.attributes['align']!;
        }
        return blockEl;
      }
    }

    // 7. Check if block is standalone <img .../>
    final imgMatch = _outerImgRegex.firstMatch(rawBlock);
    if (imgMatch != null) {
      final imgEl = HtmlImgInlineSyntax.parseImgAttributes(
        imgMatch.group(1) ?? '',
      );
      if (imgEl != null) {
        if (outerHref != null && outerHref.isNotEmpty) {
          imgEl.attributes['href'] = outerHref;
          if (outerTitle.isNotEmpty) {
            imgEl.attributes['link_title'] = outerTitle;
          }
        }
        final blockEl = md.Element('html_block', [imgEl]);
        blockEl.attributes['tag'] = 'img';
        if (imgEl.attributes['align'] != null) {
          blockEl.attributes['align'] = imgEl.attributes['align']!;
        }
        return blockEl;
      }
    }

    // 8. Check if block is <p ...>, <div ...>, <center>, <section>, etc.
    final containerMatch = _outerContainerRegex.firstMatch(rawBlock);
    if (containerMatch != null) {
      final containerTag = containerMatch.group(1)!.toLowerCase();
      final cAttrs = HtmlAttributeParser.parse(containerMatch.group(2) ?? '');
      final innerHtml = containerMatch.group(3)!.trim();
      final align = containerTag == 'center'
          ? 'center'
          : (cAttrs['align']?.trim() ?? '');
      final blockId =
          outerId ??
          ((cAttrs['id']?.trim().isNotEmpty == true)
              ? cAttrs['id']!.trim()
              : cAttrs['name']?.trim());

      // If this is a multi-block container (e.g. <div> or <center> wrapping
      // nested <p>, <h1>, <table>, lists, or multiple paragraphs), mark it as
      // multi_block so HtmlBlockBuilder delegates to nestedMarkdownBuilder.
      final isMultiBlock =
          containerTag != 'p' &&
          (_nestedBlockHintRegex.hasMatch(innerHtml) ||
              innerHtml.contains('\n\n'));
      if (isMultiBlock) {
        final blockEl = md.Element('html_block', []);
        blockEl.attributes['tag'] = containerTag;
        blockEl.attributes['multi_block'] = 'true';
        blockEl.attributes['_raw'] = innerHtml;
        if (align.isNotEmpty) {
          blockEl.attributes['align'] = align;
        }
        if (blockId != null && blockId.isNotEmpty) {
          blockEl.attributes['id'] = blockId;
        }
        return blockEl;
      }

      final inlineNodes = md.InlineParser(innerHtml, parser.document).parse();
      if (outerHref != null && outerHref.isNotEmpty) {
        HtmlAnchorInlineSyntax._attachHrefToImages(
          inlineNodes,
          outerHref,
          outerTitle,
        );
      }
      if (blockId != null && blockId.isNotEmpty) {
        final anchorEl = md.Element('anchor', []);
        anchorEl.attributes['id'] = blockId;
        inlineNodes.insert(0, anchorEl);
      }

      final blockEl = md.Element('html_block', inlineNodes);
      blockEl.attributes['tag'] = containerTag;
      blockEl.attributes['_raw'] = innerHtml;
      if (align.isNotEmpty) {
        blockEl.attributes['align'] = align;
      }
      return blockEl;
    }

    // Fallback: parse inline content inside an html_block
    final inlineNodes = md.InlineParser(rawBlock, parser.document).parse();
    if (outerHref != null && outerHref.isNotEmpty) {
      HtmlAnchorInlineSyntax._attachHrefToImages(
        inlineNodes,
        outerHref,
        outerTitle,
      );
    }
    final fallbackEl = md.Element('html_block', inlineNodes);
    fallbackEl.attributes['tag'] = tag;
    return fallbackEl;
  }
}

/// Renders `<p align="...">`, `<div align="...">`, `<center>`, and standalone
/// HTML media blocks with proper alignment, badge wrapping, and typography.
class HtmlBlockBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Map<String, GlobalKey> anchorKeys;
  final HtmlImageBuilder htmlImageBuilder;
  final void Function(String text, String? href, String title) onTapLink;
  final Widget Function(BuildContext context, String markdownData)?
  nestedMarkdownBuilder;

  HtmlBlockBuilder({
    required this.fontSize,
    required this.anchorKeys,
    required this.htmlImageBuilder,
    required this.onTapLink,
    this.nestedMarkdownBuilder,
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
    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>();
    final alignAttr = (element.attributes['align'] ?? '').toLowerCase();
    final alignment = switch (alignAttr) {
      'center' => Alignment.center,
      'right' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    final wrapAlignment = switch (alignAttr) {
      'center' => WrapAlignment.center,
      'right' => WrapAlignment.end,
      _ => WrapAlignment.start,
    };
    final textAlign = switch (alignAttr) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.start,
    };

    if (element.attributes['multi_block'] == 'true' &&
        nestedMarkdownBuilder != null) {
      String rawBody = element.attributes['_raw'] ?? '';
      if (alignAttr.isNotEmpty) {
        // Propagate align attribute to direct child <p>, <div>, <h1..h6> tags
        // that do not already specify their own align attribute.
        rawBody = rawBody.replaceAllMapped(
          RegExp(
            r'<(p|div|h[1-6])\b(?![^>]*\balign=)([^>]*)>',
            caseSensitive: false,
          ),
          (m) => '<${m.group(1)} align="$alignAttr"${m.group(2)}>',
        );
      }
      final blockId = element.attributes['id'];
      GlobalKey? idKey;
      if (blockId != null && blockId.isNotEmpty) {
        idKey = GlobalKey(debugLabel: blockId);
        anchorKeys[blockId] = idKey;
      }
      return Container(
        key: idKey,
        width: double.infinity,
        alignment: alignment,
        child: nestedMarkdownBuilder!(context, rawBody),
      );
    }

    final children = element.children ?? const <md.Node>[];
    final anchorWidgets = <Widget>[];
    final nonWhitespace = <md.Node>[];

    for (final node in children) {
      if (node is md.Element && node.tag == 'anchor') {
        final slug = node.attributes['id'];
        if (slug != null && slug.isNotEmpty) {
          final key = GlobalKey(debugLabel: slug);
          anchorKeys[slug] = key;
          anchorWidgets.add(SizedBox.shrink(key: key));
        }
        continue;
      }
      if (node is md.Text && node.text.trim().isEmpty) {
        continue;
      }
      nonWhitespace.add(node);
    }

    if (nonWhitespace.isEmpty) {
      if (anchorWidgets.isNotEmpty) {
        return Column(mainAxisSize: MainAxisSize.min, children: anchorWidgets);
      }
      return const SizedBox.shrink();
    }

    // If all non-whitespace children are images/badges, render them in a
    // clean Wrap row (ideal for centered logos and shields.io badge rows).
    final allImages = nonWhitespace.every(
      (n) => n is md.Element && (n.tag == 'html_img' || n.tag == 'img'),
    );
    if (allImages) {
      final imageWidgets = <Widget>[
        ...anchorWidgets,
        for (final node in nonWhitespace)
          htmlImageBuilder.buildImageFromAttributes(
            context,
            (node as md.Element).attributes,
          ),
      ];

      return Container(
        width: double.infinity,
        alignment: alignment,
        child: Wrap(
          alignment: wrapAlignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4.0,
          runSpacing: 4.0,
          children: imageWidgets,
        ),
      );
    }

    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );

    final spans = _buildInlineSpans(
      context,
      children,
      baseStyle: baseStyle,
      linkColor: theme.colorScheme.primary,
      codeBg: sirenColors?.codeBg,
    );

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: switch (alignAttr) {
          'center' => CrossAxisAlignment.center,
          'right' => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.start,
        },
        children: [
          ...anchorWidgets,
          Text.rich(
            TextSpan(style: baseStyle, children: spans),
            textAlign: textAlign,
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _buildInlineSpans(
    BuildContext context,
    List<md.Node>? nodes, {
    required TextStyle baseStyle,
    required Color linkColor,
    required Color? codeBg,
  }) {
    if (nodes == null || nodes.isEmpty) return const [];
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      if (node is md.Text) {
        final normalized = node.text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
        if (normalized.isNotEmpty) {
          spans.add(TextSpan(text: normalized));
        }
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'anchor':
            break;
          case 'br':
            spans.add(const TextSpan(text: '\n'));
          case 'html_img' || 'img':
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: htmlImageBuilder.buildImageFromAttributes(
                  context,
                  node.attributes,
                ),
              ),
            );
          case 'kbd':
            final kbdWidget = KbdBuilder(
              baseFontSize: fontSize,
            ).visitElementAfterWithContext(context, node, baseStyle, baseStyle);
            if (kbdWidget != null) {
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: kbdWidget,
                ),
              );
            }
          case 'highlight':
            final markWidget = HighlightBuilder(context)
                .visitElementAfter(node, baseStyle);
            if (markWidget != null) {
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: markWidget,
                ),
              );
            }
          case 'sub':
            final subWidget = SubSupBuilder(
              false,
              baseFontSize: fontSize,
            ).visitElementAfterWithContext(context, node, baseStyle, baseStyle);
            if (subWidget != null) {
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: subWidget,
                ),
              );
            }
          case 'sup':
            final supWidget = SubSupBuilder(
              true,
              baseFontSize: fontSize,
              anchorKeys: anchorKeys,
              onTapLink: onTapLink,
            ).visitElementAfterWithContext(context, node, baseStyle, baseStyle);
            if (supWidget != null) {
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: supWidget,
                ),
              );
            }
          case 'small':
            spans.add(
              TextSpan(
                style: TextStyle(fontSize: fontSize * 0.85),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          case 'abbr':
            final abbrWidget = AbbrBuilder().visitElementAfterWithContext(
              context,
              node,
              baseStyle,
              baseStyle,
            );
            if (abbrWidget != null) {
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: abbrWidget,
                ),
              );
            }
          case 'strong':
            spans.add(
              TextSpan(
                style: const TextStyle(fontWeight: FontWeight.bold),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          case 'em':
            spans.add(
              TextSpan(
                style: const TextStyle(fontStyle: FontStyle.italic),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          case 'del':
            spans.add(
              TextSpan(
                style: const TextStyle(decoration: TextDecoration.lineThrough),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          case 'u':
            spans.add(
              TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          case 'code':
            spans.add(
              TextSpan(
                text: node.textContent,
                style: GoogleFonts.firaCode(
                  fontSize: fontSize * 0.92,
                  backgroundColor: codeBg,
                ),
              ),
            );
          case 'a':
            final href = node.attributes['href'];
            final title = node.attributes['title'] ?? '';
            final linkText = node.textContent;
            spans.add(
              TextSpan(
                style: TextStyle(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => onTapLink(linkText, href, title),
                children: _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
                ),
              ),
            );
          default:
            if (node.children != null && node.children!.isNotEmpty) {
              spans.addAll(
                _buildInlineSpans(
                  context,
                  node.children,
                  baseStyle: baseStyle,
                  linkColor: linkColor,
                  codeBg: codeBg,
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

/// Renders HTML `<figure>` and `<figcaption>` blocks.
class HtmlFigureBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  HtmlFigureBuilder({
    required this.fontSize,
    required this.nestedMarkdownBuilder,
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
    final theme = Theme.of(context);
    final body = element.attributes['body'] ?? '';
    final caption = element.attributes['caption'] ?? '';
    final align = (element.attributes['align'] ?? 'center').toLowerCase();
    final crossAxis = switch (align) {
      'left' => CrossAxisAlignment.start,
      'right' => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxis,
        children: [
          if (body.isNotEmpty) nestedMarkdownBuilder(context, body),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                caption.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
                style: TextStyle(
                  fontSize: fontSize * 0.875,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Renders raw HTML `<table>` blocks with support for `<thead>`, `<tbody>`,
/// `<tr>`, `<th>`, `<td>`, `<caption>`, cell alignment, and nested Markdown/HTML.
class HtmlTableBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  HtmlTableBuilder({
    required this.fontSize,
    required this.nestedMarkdownBuilder,
  });

  static final RegExp _captionRegex = RegExp(
    r'<caption\b[^>]*>([\s\S]*?)</caption>',
    caseSensitive: false,
  );
  static final RegExp _trRegex = RegExp(
    r'<tr\b([^>]*)>([\s\S]*?)</tr>',
    caseSensitive: false,
  );
  static final RegExp _cellRegex = RegExp(
    r'<(th|td)\b([^>]*)>([\s\S]*?)</\1>',
    caseSensitive: false,
  );

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final raw = element.attributes['_raw'] ?? '';
    if (raw.isEmpty) return null;

    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>();
    final dividerColor =
        sirenColors?.divider ?? theme.colorScheme.outlineVariant;
    final headerBg =
        sirenColors?.sidebarBg ?? theme.colorScheme.surfaceContainerLow;

    final captionMatch = _captionRegex.firstMatch(raw);
    final captionText = captionMatch
        ?.group(1)
        ?.replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();

    final parsedRows =
        <List<({bool isHeader, String align, String content})>>[];
    int maxCols = 0;

    for (final trMatch in _trRegex.allMatches(raw)) {
      final trAttrs = HtmlAttributeParser.parse(trMatch.group(1) ?? '');
      final rowAlign = trAttrs['align'] ?? '';
      final trInner = trMatch.group(2) ?? '';
      final cells = <({bool isHeader, String align, String content})>[];

      for (final cellMatch in _cellRegex.allMatches(trInner)) {
        final isHeader = cellMatch.group(1)!.toLowerCase() == 'th';
        final cellAttrs = HtmlAttributeParser.parse(cellMatch.group(2) ?? '');
        final align = (cellAttrs['align'] ?? rowAlign).toLowerCase();
        final content = cellMatch.group(3)!.trim();
        cells.add((isHeader: isHeader, align: align, content: content));
      }

      if (cells.isNotEmpty) {
        if (cells.length > maxCols) maxCols = cells.length;
        parsedRows.add(cells);
      }
    }

    if (parsedRows.isEmpty || maxCols == 0) return null;

    final tableRows = <TableRow>[];
    for (final row in parsedRows) {
      final isHeaderRow = row.every((c) => c.isHeader);
      final rowChildren = <Widget>[];
      for (int c = 0; c < maxCols; c++) {
        if (c < row.length) {
          final cell = row[c];
          final alignment = switch (cell.align) {
            'center' => Alignment.center,
            'right' => Alignment.centerRight,
            _ => cell.isHeader ? Alignment.centerLeft : Alignment.topLeft,
          };
          final wrappedContent = cell.isHeader
              ? '**${cell.content}**'
              : cell.content;
          rowChildren.add(
            Container(
              alignment: alignment,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: nestedMarkdownBuilder(context, wrappedContent),
            ),
          );
        } else {
          rowChildren.add(const SizedBox.shrink());
        }
      }
      tableRows.add(
        TableRow(
          decoration: isHeaderRow ? BoxDecoration(color: headerBg) : null,
          children: rowChildren,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (captionText != null && captionText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text(
                captionText,
                style: TextStyle(
                  fontSize: fontSize * 0.9,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Table(
            border: TableBorder.all(color: dividerColor, width: 1.0),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: tableRows,
          ),
        ],
      ),
    );
  }
}

/// Renders raw HTML `<ul>` and `<ol>` lists.
class HtmlListBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  HtmlListBuilder({
    required this.fontSize,
    required this.nestedMarkdownBuilder,
  });

  static final RegExp _liRegex = RegExp(
    r'<li\b[^>]*>([\s\S]*?)</li>',
    caseSensitive: false,
  );

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final raw = element.attributes['_raw'] ?? '';
    final ordered = element.attributes['ordered'] == 'true';
    final start = int.tryParse(element.attributes['start'] ?? '1') ?? 1;
    final theme = Theme.of(context);

    final items = <Widget>[];
    int idx = start;
    for (final match in _liRegex.allMatches(raw)) {
      final itemContent = match.group(1)!.trim();
      final marker = ordered ? '$idx.' : '•';
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24.0,
                child: Text(
                  marker,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.6,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(child: nestedMarkdownBuilder(context, itemContent)),
            ],
          ),
        ),
      );
      idx++;
    }

    if (items.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }
}

/// Renders raw HTML `<dl>` description lists (`<dt>` terms and `<dd>` definitions).
class HtmlDlBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  HtmlDlBuilder({required this.fontSize, required this.nestedMarkdownBuilder});

  static final RegExp _itemRegex = RegExp(
    r'<(dt|dd)\b[^>]*>([\s\S]*?)</\1>',
    caseSensitive: false,
  );

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final raw = element.attributes['_raw'] ?? '';
    final children = <Widget>[];

    for (final match in _itemRegex.allMatches(raw)) {
      final tag = match.group(1)!.toLowerCase();
      final content = match.group(2)!.trim();
      if (tag == 'dt') {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
            child: nestedMarkdownBuilder(context, '**$content**'),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 20.0, bottom: 8.0),
            child: nestedMarkdownBuilder(context, content),
          ),
        );
      }
    }

    if (children.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Renders collapsible `<details><summary>...</summary>...</details>` blocks.
class DetailsElementBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  DetailsElementBuilder({
    required this.fontSize,
    required this.nestedMarkdownBuilder,
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
    final summary = element.attributes['summary'] ?? 'Details';
    final body = element.attributes['body'] ?? '';
    final initiallyOpen = element.attributes['open'] == 'true';

    return _CollapsibleDetailsBlock(
      summary: summary,
      body: body,
      initiallyOpen: initiallyOpen,
      fontSize: fontSize,
      nestedMarkdownBuilder: nestedMarkdownBuilder,
    );
  }
}

class _CollapsibleDetailsBlock extends StatefulWidget {
  final String summary;
  final String body;
  final bool initiallyOpen;
  final double fontSize;
  final Widget Function(BuildContext context, String markdownData)
  nestedMarkdownBuilder;

  const _CollapsibleDetailsBlock({
    required this.summary,
    required this.body,
    required this.initiallyOpen,
    required this.fontSize,
    required this.nestedMarkdownBuilder,
  });

  @override
  State<_CollapsibleDetailsBlock> createState() =>
      _CollapsibleDetailsBlockState();
}

class _CollapsibleDetailsBlockState extends State<_CollapsibleDetailsBlock> {
  late bool _isOpen;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.initiallyOpen;
  }

  @override
  void didUpdateWidget(covariant _CollapsibleDetailsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyOpen != widget.initiallyOpen) {
      _isOpen = widget.initiallyOpen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sirenColors = theme.extension<SirenColors>();
    final dividerColor =
        sirenColors?.divider ?? theme.colorScheme.outlineVariant;
    final headerBg =
        sirenColors?.codeBlockHeaderBg ??
        sirenColors?.sidebarBg ??
        theme.colorScheme.surfaceContainerLow;
    final bodyBg =
        sirenColors?.codeBlockBg ?? theme.colorScheme.surfaceContainerLowest;
    final cleanSummary = widget.summary
        .replaceAll(RegExp(r'</?(strong|b|em|i|code|span)\b[^>]*>'), '')
        .trim();

    return Container(
      key: ValueKey<String>('details_${widget.summary}'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: bodyBg,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: headerBg,
            child: InkWell(
              onTap: () => setState(() => _isOpen = !_isOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 10.0,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isOpen
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cleanSummary.isEmpty ? 'Details' : cleanSummary,
                        style: TextStyle(
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isOpen && widget.body.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: dividerColor)),
              ),
              padding: const EdgeInsets.all(14.0),
              child: widget.nestedMarkdownBuilder(context, widget.body),
            ),
        ],
      ),
    );
  }
}
