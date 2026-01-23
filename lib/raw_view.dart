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
    final offset = appState.getScrollOffset(path);
    // Wait for build to attach client
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(offset);
      }
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
  ) {
    if (nodes.isEmpty) {
      return TextSpan(text: source, style: theme['root']);
    }

    return TextSpan(
      style: theme['root'],
      children: nodes.map((node) {
        return _convertNode(node, theme);
      }).toList(),
    );
  }

  TextSpan _convertNode(Node node, Map<String, TextStyle> theme) {
    final style = theme[node.className] ?? const TextStyle();
    if (node.children == null) {
      return TextSpan(text: node.value, style: style);
    }
    return TextSpan(
      style: style,
      children: node.children!.map((n) => _convertNode(n, theme)).toList(),
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
                    _buildTextSpan(content, ast.nodes!, theme),
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
