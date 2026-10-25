class MarkdownProcessor {
  static String injectAnchors(String markdown) {
    final buffer = StringBuffer();
    final lines = markdown.split('\n');
    bool inCodeBlock = false;
    bool inFrontmatter = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (i == 0 && trimmed == '---') {
        inFrontmatter = true;
        buffer.writeln(line);
        continue;
      }
      if (inFrontmatter) {
        buffer.writeln(line);
        if (trimmed == '---' || trimmed == '...') {
          inFrontmatter = false;
        }
        continue;
      }

      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
      }

      if (!inCodeBlock && line.startsWith('#')) {
        // Strip leading hashes and whitespace
        final text = line.replaceFirst(RegExp(r'^#+\s*'), '');
        final slug = generateSlug(text);
        buffer.writeln('[[@anchor:$slug]]\n');
      }
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  static String generateSlug(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }
}
