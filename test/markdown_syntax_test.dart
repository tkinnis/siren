import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:siren/markdown_extensions.dart';
import 'package:siren/markdown_processor.dart';

void main() {
  test('AlertBlockSyntax parses simple alert', () {
    const markdown = '''> [!NOTE]
> This is a note.''';

    final document = md.Document(
      extensionSet: md.ExtensionSet([
        const AlertBlockSyntax(),
        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      ], md.ExtensionSet.gitHubFlavored.inlineSyntaxes),
    );

    final nodes = document.parseLines(markdown.split('\n'));

    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node, isA<md.Element>());
    final element = node as md.Element;
    expect(element.tag, 'blockquote');
    expect(element.attributes['class'], 'alert');
    expect(element.attributes['type'], 'NOTE');
    expect(element.attributes['_raw'], 'This is a note.');
  });

  test('AlertBlockSyntax parses indented alert', () {
    const markdown = '''   > [!TIP]
   > Indented tip.''';

    final document = md.Document(
      extensionSet: md.ExtensionSet([const AlertBlockSyntax()], []),
    );

    final nodes = document.parseLines(markdown.split('\n'));

    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node, isA<md.Element>());
    final element = node as md.Element;
    expect(element.tag, 'blockquote');
    expect(element.attributes['class'], 'alert');
    expect(element.attributes['type'], 'TIP');
    expect(element.attributes['_raw'], 'Indented tip.');
  });

  group('YamlFrontmatterBlockSyntax', () {
    test('parses leading YAML frontmatter block and extracts entries', () {
      const markdown = '''---
title: "Siren Release Notes"
author: Tyler
# comment line inside frontmatter
tags:
  - flutter
  - macos
---

# Heading 1

---
''';

      final document = md.Document(
        extensionSet: md.ExtensionSet([
          const YamlFrontmatterBlockSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ], md.ExtensionSet.gitHubFlavored.inlineSyntaxes),
      );

      final nodes = document.parseLines(markdown.split('\n'));
      expect(nodes.length, greaterThanOrEqualTo(3));

      final frontmatter = nodes.first as md.Element;
      expect(frontmatter.tag, 'frontmatter');
      expect(frontmatter.attributes['class'], 'frontmatter');

      final entries = YamlFrontmatterBlockSyntax.parseEntries(
        frontmatter.attributes['_raw']!,
      );
      expect(entries, [
        (key: 'title', value: 'Siren Release Notes'),
        (key: 'author', value: 'Tyler'),
        (key: 'tags', value: 'flutter, macos'),
      ]);

      // Trailing '---' remains a horizontal rule ('hr'), not frontmatter
      final lastElement = nodes.last as md.Element;
      expect(lastElement.tag, 'hr');
    });

    test('MarkdownProcessor.injectAnchors skips YAML frontmatter comments', () {
      const markdown = '''---
title: Doc
# Not a heading
---

# Real Heading
''';

      final processed = MarkdownProcessor.injectAnchors(markdown);
      expect(processed, isNot(contains('not-a-heading')));
      expect(processed, contains('[[@anchor:real-heading]]\n\n# Real Heading'));
    });

    test('does not parse YAML frontmatter in the middle of a document', () {
      const markdown = '''# Document Title

Some introductory paragraph.

---
title: Mid-document block
author: Should Not Be Frontmatter
---
''';

      final document = md.Document(
        extensionSet: md.ExtensionSet([
          const YamlFrontmatterBlockSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ], md.ExtensionSet.gitHubFlavored.inlineSyntaxes),
      );

      final nodes = document.parseLines(markdown.split('\n'));
      for (final node in nodes) {
        if (node is md.Element) {
          expect(node.attributes['class'], isNot('frontmatter'));
        }
      }
    });
  });

  test('GFM Footnotes parse inline references and definitions', () {
    const markdown = '''Here is a statement[^1] and another[^note].

[^1]: First footnote definition.
[^note]: Named footnote definition.''';

    final document = md.Document(
      extensionSet: md.ExtensionSet(
        [
          const YamlFrontmatterBlockSyntax(),
          const AlertBlockSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ],
        [
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
          SuperscriptSyntax(),
          SubscriptSyntax(),
        ],
      ),
    );

    final nodes = document.parseLines(markdown.split('\n'));
    expect(nodes, hasLength(2));
    final section = nodes.last as md.Element;
    expect(section.tag, 'section');
    expect(section.attributes['class'], 'footnotes');
  });
}
