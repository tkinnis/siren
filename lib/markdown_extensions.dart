import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

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
      // Strip the '>' and leading space. We use regex on the trimmed line or full line?
      // Standard blockquote allows 0-3 spaces before '>'.
      // stripping `^ {0,3}>\s?` from the original line is safer.
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
    if (element.attributes['class'] != 'alert') {
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
          // Use MarkdownBody to render rich text content inside the alert.
          // We don't have access to the parent context's theme easily here
          // (unless we pass it or reuse 'preferredStyle' carefully),
          // so we rely on default styles.
          MarkdownBody(
            data: rawContent,
            selectable: false, // Prevent crash with nested SelectionArea
            // The AlertBuilder itself handles the 'blockquote' tag with 'alert' class.
            // The inner MarkdownBody should not re-register the AlertBuilder for 'blockquote'
            // as that would lead to infinite recursion if the rawContent contained another alert.
            // Instead, it should just use the default styling for blockquotes or other elements.
            styleSheet: MarkdownStyleSheet.fromTheme(
              Theme.of(context),
            ).copyWith(p: preferredStyle),
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
  SuperscriptSyntax() : super(r'\^([^^]+)\^');

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
    // We use a WidgetSpan approach normally, but here we return a Widget.
    // To align properly to text, RichText with WidgetSpan is best, but
    // MarkdownElementBuilder returns a Widget which breaks the paragraph flow if not careful.
    //
    // Best effort for inline widget: Transform.translate

    return Transform.translate(
      offset: Offset(0, isSup ? -4.0 : 4.0),
      child: Text(
        element.textContent,
        style: preferredStyle?.copyWith(
          fontSize: (preferredStyle.fontSize ?? 14) * 0.7,
        ),
      ),
    );
  }
}
