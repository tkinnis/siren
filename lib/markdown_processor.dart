class MarkdownProcessor {
  /// Strips HTML comments (`<!-- ... -->`) outside of YAML frontmatter,
  /// fenced code blocks, and inline code spans.
  static String stripHtmlComments(String markdown) {
    if (!markdown.contains('<!--')) return markdown;

    final lines = markdown.split('\n');
    final guardedBuffer = StringBuffer();
    bool inFrontmatter = false;
    bool inCodeBlock = false;
    String? fenceMarker;

    // Step 1: Replace comments only in non-frontmatter, non-fenced-code chunks.
    final chunkBuffer = StringBuffer();

    void flushChunk() {
      if (chunkBuffer.isEmpty) return;
      guardedBuffer.write(_stripCommentsFromChunk(chunkBuffer.toString()));
      chunkBuffer.clear();
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      final lineWithNewline = isLast ? line : '$line\n';
      final trimmed = line.trim();

      if (i == 0 && trimmed == '---') {
        inFrontmatter = true;
        guardedBuffer.write(lineWithNewline);
        continue;
      }
      if (inFrontmatter) {
        guardedBuffer.write(lineWithNewline);
        if (trimmed == '---' || trimmed == '...') {
          inFrontmatter = false;
        }
        continue;
      }

      final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (!inCodeBlock) {
          flushChunk();
          inCodeBlock = true;
          fenceMarker = marker;
          guardedBuffer.write(lineWithNewline);
          continue;
        } else if (trimmed.startsWith(fenceMarker![0] * fenceMarker.length) &&
            trimmed.replaceAll(fenceMarker[0], '').isEmpty) {
          inCodeBlock = false;
          fenceMarker = null;
          guardedBuffer.write(lineWithNewline);
          continue;
        }
      }

      if (inCodeBlock) {
        guardedBuffer.write(lineWithNewline);
      } else {
        chunkBuffer.write(lineWithNewline);
      }
    }
    flushChunk();

    return guardedBuffer.toString();
  }

  static String _stripCommentsFromChunk(String text) {
    if (!text.contains('<!--')) return text;

    final out = StringBuffer();
    int i = 0;
    final len = text.length;

    while (i < len) {
      // Preserve inline code spans (`...` or ``...``)
      if (text[i] == '`') {
        int tickCount = 0;
        final start = i;
        while (i < len && text[i] == '`') {
          tickCount++;
          i++;
        }
        final closingTicks = '`' * tickCount;
        final closeIdx = text.indexOf(closingTicks, i);
        if (closeIdx != -1) {
          out.write(text.substring(start, closeIdx + tickCount));
          i = closeIdx + tickCount;
        } else {
          out.write(text.substring(start));
          break;
        }
        continue;
      }

      // Check for HTML comment <!-- ... -->
      if (i + 4 <= len && text.startsWith('<!--', i)) {
        final closeIdx = text.indexOf('-->', i + 4);
        final commentEnd = closeIdx != -1 ? closeIdx + 3 : len;

        // Check if this comment occupies an entire line by itself
        final currentOut = out.toString();
        int lineStartInOut = currentOut.lastIndexOf('\n') + 1;
        final prefixOnLine = currentOut.substring(lineStartInOut);
        final isOnlyWhitespaceBefore = prefixOnLine.trim().isEmpty;

        int afterIdx = commentEnd;
        while (afterIdx < len &&
            (text[afterIdx] == ' ' ||
                text[afterIdx] == '\t' ||
                text[afterIdx] == '\r')) {
          afterIdx++;
        }
        final isLineEndAfter = afterIdx >= len || text[afterIdx] == '\n';

        if (isOnlyWhitespaceBefore && isLineEndAfter) {
          // Remove leading horizontal whitespace on the line and the trailing newline
          final trimmedOut = currentOut.substring(0, lineStartInOut);
          out.clear();
          out.write(trimmedOut);
          i = (afterIdx < len && text[afterIdx] == '\n')
              ? afterIdx + 1
              : afterIdx;
        } else {
          i = commentEnd;
        }
        continue;
      }

      out.write(text[i]);
      i++;
    }

    return out.toString();
  }

  static String injectAnchors(String markdown) {
    final cleaned = stripHtmlComments(markdown);
    final buffer = StringBuffer();
    final lines = cleaned.split('\n');
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

      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inCodeBlock = !inCodeBlock;
      }

      if (!inCodeBlock && line.startsWith('#')) {
        // Strip leading hashes and whitespace
        final text = line.replaceFirst(RegExp(r'^#+\s*'), '');
        final slug = generateSlug(text);
        if (slug.isNotEmpty) {
          buffer.writeln('[[@anchor:$slug]]\n');
        }
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
