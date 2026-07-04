import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_highlighter/themes/github.dart';
import 'package:flutter_highlighter/themes/dracula.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlighter/highlighter.dart' show highlight, Node;
import 'package:provider/provider.dart';
import 'app_state.dart';

class MarkdownRawView extends StatefulWidget {
  final String filePath;
  const MarkdownRawView({super.key, required this.filePath});

  @override
  State<MarkdownRawView> createState() => _MarkdownRawViewState();
}

class _MarkdownRawViewState extends State<MarkdownRawView> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _navSubscription;

  @override
  void initState() {
    super.initState();
    _restoreScrollPosition();
  }

  @override
  void didUpdateWidget(MarkdownRawView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _restoreScrollPosition();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navSubscription?.cancel();
    final appState = context.read<AppState>();
    _navSubscription = appState.navigationStream.listen((event) {
      if (_scrollController.hasClients) {
        final lineHeight = appState.fontSize * 1.5;
        // Center the target line if possible
        final viewportHeight = _scrollController.position.viewportDimension;
        final targetOffset =
            (event.lineNumber * lineHeight) - (viewportHeight / 3);

        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _restoreScrollPosition() {
    final appState = context.read<AppState>();
    final path = widget.filePath;
    
    // Wait for build to attach client
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      
      final pending = appState.pendingScrollTarget;
      if (pending != null) {
        final lineHeight = appState.fontSize * 1.5;
        final viewportHeight = _scrollController.position.viewportDimension;
        final targetOffset =
            (pending.lineNumber * lineHeight) - (viewportHeight / 3);

        _scrollController.jumpTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
        appState.clearPendingScrollTarget();
        return;
      }
      
      final offset = appState.getScrollOffset(path);
      _scrollController.jumpTo(offset);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final appState = context.read<AppState>();
    appState.setScrollOffset(widget.filePath, _scrollController.offset);
  }


  // Helper to convert highlighter nodes to TextSpan
  TextSpan _buildTextSpan(
    String source,
    List<Node> nodes,
    Map<String, TextStyle> theme,
    _SearchState? searchState,
  ) {
    if (nodes.isEmpty) {
      if (searchState != null && searchState.query.isNotEmpty) {
        return TextSpan(
          style: theme['root'],
          children: _buildSearchHighlightSpans(
            source,
            searchState.query,
            theme['root'] ?? const TextStyle(),
            searchState.activeIndex,
            () => searchState.matchCounter++,
            useRegex: searchState.useRegex,
          ),
        );
      }
      return TextSpan(text: source, style: theme['root']);
    }

    return TextSpan(
      style: theme['root'],
      children: nodes.map((node) {
        return _convertNode(node, theme, searchState);
      }).toList(),
    );
  }

  TextSpan _convertNode(
    Node node,
    Map<String, TextStyle> theme,
    _SearchState? searchState,
  ) {
    final style = theme[node.className] ?? const TextStyle();
    if (node.children == null) {
      final value = node.value;
      if (value == null) return const TextSpan();
      if (searchState != null && searchState.query.isNotEmpty) {
        return TextSpan(
          children: _buildSearchHighlightSpans(
            value,
            searchState.query,
            style,
            searchState.activeIndex,
            () => searchState.matchCounter++,
            useRegex: searchState.useRegex,
          ),
        );
      }
      return TextSpan(text: value, style: style);
    }
    return TextSpan(
      style: style,
      children: node.children!.map((n) => _convertNode(n, theme, searchState)).toList(),
    );
  }

  @override
  void dispose() {
    _navSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.select<AppState, String>(
      (state) => state.getFileContent(widget.filePath),
    );
    final fontSize = context.select<AppState, double>((state) => state.fontSize);
    final findQuery = context.select<AppState, String>((state) => state.findInFileQuery);
    final activeMatchIndex = context.select<AppState, int>((state) => state.findInFileActiveMatchIndex);
    final isFindVisible = context.select<AppState, bool>((state) => state.isFindInFileVisible);
    final useRegex = context.select<AppState, bool>((state) => state.findInFileUseRegex);

    final searchState = (isFindVisible && findQuery.isNotEmpty)
        ? _SearchState(findQuery, activeMatchIndex, useRegex)
        : null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use standard themes directly instead of SirenTheme.showcase...
    // because we need the raw map for manual span building
    final Map<String, TextStyle> baseTheme = isDark
        ? draculaTheme
        : githubTheme;

    // Extract background color from theme or fallback
    final backgroundColor =
        baseTheme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF1a1a2e) : const Color(0xFFf8f8fc));

    // Create a modified theme where the root style has no background color.
    // This is critical because SelectableText paints selection BEHIND the text.
    // If the text has an opaque background, the selection is hidden.
    final Map<String, TextStyle> theme = Map.from(baseTheme);
    if (theme.containsKey('root')) {
      theme['root'] = theme['root']!.copyWith(
        backgroundColor: Colors.transparent,
      );
    }

    // Parse syntax
    final ast = highlight.parse(content, language: 'markdown');

    // Create text style merging font and theme root style
    final baseTextStyle = GoogleFonts.firaCode(fontSize: fontSize);
    final textStyle = baseTextStyle.merge(theme['root']).copyWith(height: 1.5);
    final gutterStyle = baseTextStyle.copyWith(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
      height: 1.5,
    );

    final lineCount = content.split('\n').length;
    final lineNumbers = List.generate(
      lineCount,
      (i) => (i + 1).toString(),
    ).join('\n');

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _onScroll();
        }
        return false;
      },
      child: Container(
        color: backgroundColor,
        constraints: const BoxConstraints.expand(),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gutter
              Container(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 24.0,
                  bottom: 24.0,
                ),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.grey).withValues(
                    alpha: 0.05,
                  ),
                  border: Border(
                    right: BorderSide(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.1,
                      ),
                    ),
                  ),
                ),
                child: Text(
                  lineNumbers,
                  style: gutterStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 24.0,
                  ),
                  child: SelectableText.rich(
                    _buildTextSpan(content, ast.nodes!, theme, searchState),
                    style: textStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchState {
  final String query;
  final int activeIndex;
  final bool useRegex;
  int matchCounter = 0;
  _SearchState(this.query, this.activeIndex, this.useRegex);
}

List<InlineSpan> _buildSearchHighlightSpans(
  String text,
  String query,
  TextStyle style,
  int activeIndex,
  int Function() getAndIncrementMatchIndex, {
  bool useRegex = false,
}) {
  if (query.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  // Parse regex if needed
  RegExp? regExp;
  if (useRegex) {
    try {
      regExp = RegExp(query, caseSensitive: false);
    } catch (_) {
      // Fallback to verbatim
    }
  }

  final List<InlineSpan> spans = [];

  if (regExp != null) {
    final matches = regExp.allMatches(text);
    int start = 0;

    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: style));
      }

      final matchText = match.group(0) ?? '';
      final currentMatchIdx = getAndIncrementMatchIndex();
      final isActive = currentMatchIdx == activeIndex;

      spans.add(TextSpan(
        text: matchText,
        style: style.copyWith(
          backgroundColor: isActive
              ? Colors.orange.withValues(alpha: 0.8)
              : Colors.yellow.withValues(alpha: 0.4),
          color: Colors.black,
        ),
      ));

      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return spans;
  }

  // Verbatim search fallback
  final List<InlineSpan> spansVerbatim = [];
  final lowercaseText = text.toLowerCase();
  final lowercaseQuery = query.toLowerCase();
  int start = 0;

  while (true) {
    final index = lowercaseText.indexOf(lowercaseQuery, start);
    if (index == -1) {
      spansVerbatim.add(TextSpan(text: text.substring(start), style: style));
      break;
    }

    if (index > start) {
      spansVerbatim.add(TextSpan(text: text.substring(start, index), style: style));
    }

    final matchText = text.substring(index, index + query.length);
    final currentMatchIdx = getAndIncrementMatchIndex();
    final isActive = currentMatchIdx == activeIndex;

    spansVerbatim.add(TextSpan(
      text: matchText,
      style: style.copyWith(
        backgroundColor: isActive
            ? Colors.orange.withValues(alpha: 0.8)
            : Colors.yellow.withValues(alpha: 0.4),
          color: Colors.black,
        ),
      ));

    start = index + query.length;
  }

  return spansVerbatim;
}

