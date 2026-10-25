import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

// --- YAML Frontmatter ---

class YamlFrontmatterBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^---\s*$');

  const YamlFrontmatterBlockSyntax();

  @override
  bool canParse(md.BlockParser parser) {
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

    final element = md.Element('blockquote', []);
    element.attributes['class'] = 'frontmatter';
    element.attributes['_raw'] = yamlLines.join('\n');
    return element;
  }

  /// Parses simple YAML frontmatter lines into key-value pairs.
  static List<({String key, String value})> parseEntries(String rawYaml) {
    final entries = <({String key, String value})>[];
    final lines = rawYaml.split('\n');
    String? currentKey;
    final currentValues = <String>[];
    final keyValRegex = RegExp(r'^([A-Za-z0-9_.-]+)\s*:\s*(.*)$');

    void flushCurrent() {
      if (currentKey != null) {
        entries.add((key: currentKey!, value: currentValues.join(', ')));
        currentKey = null;
        currentValues.clear();
      }
    }

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if ((rawLine.startsWith(' ') || rawLine.startsWith('\t')) &&
          currentKey != null &&
          trimmed.startsWith('- ')) {
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
            final inner = rawVal.substring(1, rawVal.length - 1).trim();
            if (inner.isNotEmpty) {
              currentValues.addAll(
                inner.split(',').map((s) => _stripQuotes(s.trim())),
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

class AlertBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  AlertBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final elementClass = element.attributes['class'];
    if (elementClass == 'frontmatter') {
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
    final sirenColors = theme.extension<SirenColors>()!;
    final entries = YamlFrontmatterBlockSyntax.parseEntries(rawYaml);
    final baseFontSize = preferredStyle?.fontSize ?? 14.0;

    return Container(
      key: const Key('yaml_frontmatter_card'),
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: sirenColors.codeBlockBg ?? sirenColors.sidebarBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sirenColors.divider ?? theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sirenColors.codeBlockHeaderBg ?? sirenColors.sidebarBg,
              border: Border(
                bottom: BorderSide(
                  color:
                      sirenColors.divider ?? theme.colorScheme.outlineVariant,
                ),
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    children: [
                      for (final entry in entries)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 16,
                                top: 3,
                                bottom: 3,
                              ),
                              child: Text(
                                entry.key,
                                style: GoogleFonts.firaCode(
                                  fontSize: baseFontSize * 0.85,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  fontSize: baseFontSize * 0.9,
                                  color: theme.colorScheme.onSurface,
                                ),
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

  SubSupBuilder(this.isSup);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final isFootnoteRef = element.attributes['class'] == 'footnote-ref';
    final displayText = isFootnoteRef
        ? '[${element.textContent}]'
        : element.textContent;

    return Transform.translate(
      offset: Offset(0, isSup ? -4.0 : 4.0),
      child: Text(
        displayText,
        style: preferredStyle?.copyWith(
          fontSize: (preferredStyle.fontSize ?? 14) * 0.75,
          color: isFootnoteRef ? Colors.blue : preferredStyle.color,
          fontWeight: isFootnoteRef
              ? FontWeight.w600
              : preferredStyle.fontWeight,
        ),
      ),
    );
  }
}
