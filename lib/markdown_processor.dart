class MarkdownProcessor {
  static String injectAnchors(String markdown) {
    final buffer = StringBuffer();
    // Using simple split might be memory intensive for huge files but efficient enough for logic
    // A LineSplitter might be better but split('\n') is standard.
    final lines = markdown.split('\n');
    bool inCodeBlock = false;

    for (final line in lines) {
      final trimmed = line.trim();
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

