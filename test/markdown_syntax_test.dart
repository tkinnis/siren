import 'dart:convert';
import 'dart:typed_data';

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

  group('Embedded GFM HTML Support', () {
    md.Document buildSirenDocument() {
      return md.Document(
        extensionSet: md.ExtensionSet(
          [
            const YamlFrontmatterBlockSyntax(),
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
            SuperscriptSyntax(),
            SubscriptSyntax(),
          ],
        ),
      );
    }

    test(
      'MarkdownProcessor.stripHtmlComments removes comments outside code',
      () {
        const markdown = '''<!-- Top-level hidden comment -->
# Heading
Inline <!-- secret -->text and `<!-- kept in inline code -->`.

```html
<!-- kept in fenced code block -->
```
''';

        final stripped = MarkdownProcessor.stripHtmlComments(markdown);
        expect(stripped, isNot(contains('Top-level hidden comment')));
        expect(stripped, isNot(contains('secret')));
        expect(stripped, contains('Inline text'));
        expect(stripped, contains('`<!-- kept in inline code -->`'));
        expect(stripped, contains('<!-- kept in fenced code block -->'));
      },
    );

    test('parses Flutter <a href><h1 align="center"><picture>...</picture></h1></a> block', () {
      const markdown = '''<a href="https://flutter.dev/">
  <h1 align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.flutter.dev/logo_dark.png">
      <img alt="Flutter" src="https://docs.flutter.dev/logo.png">
    </picture>
  </h1>
</a>''';

      final nodes = buildSirenDocument().parseLines(markdown.split('\n'));
      expect(nodes, hasLength(1));
      final h1 = nodes.first as md.Element;
      expect(h1.tag, 'h1');
      expect(h1.attributes['align'], 'center');
      expect(h1.children, isNotNull);

      final imgEl = h1.children!.whereType<md.Element>().firstWhere(
        (e) => e.tag == 'html_img',
      );
      expect(imgEl.attributes['alt'], 'Flutter');
      expect(imgEl.attributes['src'], 'https://docs.flutter.dev/logo.png');
      expect(
        imgEl.attributes['dark_src'],
        'https://docs.flutter.dev/logo_dark.png',
      );
      expect(imgEl.attributes['href'], 'https://flutter.dev/');
    });

    test(
      'parses Siren README <p align="center"> logo, tagline, and badges',
      () {
        const markdown = '''<p align="center">
  <img src="assets/images/app_icon.png" alt="Siren Logo" width="128" height="128" />
</p>

<p align="center">
  <strong>A sleek, high-performance desktop Markdown viewer built with Flutter.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white" alt="macOS" />
  <a href="https://github.com/tkinnis/siren/releases/latest"><img src="https://img.shields.io/github/v/release/tkinnis/siren?color=007AFF&logo=apple&logoColor=white" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" />
</p>''';

        final nodes = buildSirenDocument().parseLines(markdown.split('\n'));
        expect(nodes, hasLength(3));

        final logoBlock = nodes[0] as md.Element;
        expect(logoBlock.tag, 'html_block');
        expect(logoBlock.attributes['align'], 'center');
        final logoImg = logoBlock.children!.whereType<md.Element>().first;
        expect(logoImg.tag, 'html_img');
        expect(logoImg.attributes['src'], 'assets/images/app_icon.png');
        expect(logoImg.attributes['width'], '128');
        expect(logoImg.attributes['height'], '128');

        final taglineBlock = nodes[1] as md.Element;
        expect(taglineBlock.tag, 'html_block');
        expect(taglineBlock.attributes['align'], 'center');
        expect(
          taglineBlock.textContent,
          contains('A sleek, high-performance desktop Markdown viewer'),
        );

        final badgesBlock = nodes[2] as md.Element;
        expect(badgesBlock.tag, 'html_block');
        expect(badgesBlock.attributes['align'], 'center');
        final badgeImgs = badgesBlock.children!
            .whereType<md.Element>()
            .where((e) => e.tag == 'html_img')
            .toList();
        expect(badgeImgs, hasLength(4));
        expect(
          badgeImgs[2].attributes['href'],
          'https://github.com/tkinnis/siren/releases/latest',
        );
      },
    );

    test('parses <details> and <summary> block with open attribute', () {
      const markdown = '''<details open>
  <summary>Click to expand</summary>

  Hidden **Markdown** body.
</details>''';

      final nodes = buildSirenDocument().parseLines(markdown.split('\n'));
      expect(nodes, hasLength(1));
      final details = nodes.first as md.Element;
      expect(details.tag, 'details');
      expect(details.attributes['open'], 'true');
      expect(details.attributes['summary'], 'Click to expand');
      expect(details.attributes['body'], 'Hidden **Markdown** body.');
    });

    test('parses <table>, <ul>, <dl>, <blockquote>, <pre>, and <figure> HTML blocks', () {
      const markdown = '''<table>
  <tr><th>Key</th><th>Value</th></tr>
  <tr><td>Mode</td><td>Preview</td></tr>
</table>

<dl>
  <dt>Siren</dt>
  <dd>macOS Markdown viewer</dd>
</dl>

<pre><code class="language-dart">void main() {}</code></pre>

<figure>
  <img src="assets/images/app_icon.png" alt="Icon" width="64" />
  <figcaption>Figure 1: Application Icon</figcaption>
</figure>''';

      final nodes = buildSirenDocument().parseLines(markdown.split('\n'));
      expect(nodes, hasLength(4));
      expect((nodes[0] as md.Element).tag, 'html_table');
      expect((nodes[1] as md.Element).tag, 'html_dl');
      expect((nodes[2] as md.Element).tag, 'pre');
      final fig = nodes[3] as md.Element;
      expect(fig.tag, 'html_figure');
      expect(fig.attributes['caption'], 'Figure 1: Application Icon');
    });

    test('HtmlImageBuilder.isSvgPayload detects SVG by Content-Type or bytes and rejects binary raster magic bytes', () {
      final rawSvgBytes = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
      );
      final xmlPrologSvgBytes = Uint8List.fromList(
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>\n<svg viewBox="0 0 100 20"></svg>',
        ),
      );
      final pngMagicBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);

      // Detects SVG from Content-Type header
      expect(
        HtmlImageBuilder.isSvgPayload(
          contentType: 'image/svg+xml; charset=utf-8',
          bytes: rawSvgBytes,
        ),
        isTrue,
      );

      // Detects SVG from XML/SVG payload even when Content-Type is generic or mislabeled
      expect(
        HtmlImageBuilder.isSvgPayload(
          contentType: 'application/octet-stream',
          bytes: xmlPrologSvgBytes,
        ),
        isTrue,
      );

      // Rejects binary PNG magic bytes even if Content-Type is missing
      expect(
        HtmlImageBuilder.isSvgPayload(
          contentType: 'image/png',
          bytes: pngMagicBytes,
        ),
        isFalse,
      );
    });
  });
}
