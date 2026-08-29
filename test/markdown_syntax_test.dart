import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:siren/markdown_extensions.dart';

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
}
