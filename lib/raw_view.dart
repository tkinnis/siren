import 'package:flutter/material.dart';
import 'package:flutter_highlighter/themes/github.dart';
import 'package:flutter_highlighter/themes/dracula.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlighter/highlighter.dart' show highlight, Node;
import 'package:provider/provider.dart';
import 'app_state.dart';

class MarkdownRawView extends StatefulWidget {
  const MarkdownRawView({super.key});

  @override
  State<MarkdownRawView> createState() => _MarkdownRawViewState();
}

class _MarkdownRawViewState extends State<MarkdownRawView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _restoreScrollPosition();
  }

  void _restoreScrollPosition() {
    final appState = context.read<AppState>();
    final path = appState.currentFilePath;
    if (path != null) {
      final offset = appState.getScrollOffset(path);
      // Wait for build to attach client
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(offset);
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final appState = context.read<AppState>();
    final path = appState.currentFilePath;
    if (path != null) {
      appState.setScrollOffset(path, _scrollController.offset);
    }
  }

  // Helper to convert highlighter nodes to TextSpan
  TextSpan _buildTextSpan(String source, List<Node> nodes, Map<String, TextStyle> theme) {
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final content = appState.currentContent;
    final fontSize = appState.fontSize;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Use standard themes directly instead of SirenTheme.showcase... 
    // because we need the raw map for manual span building
    final Map<String, TextStyle> theme = isDark ? draculaTheme : githubTheme;

    // Extract background color from theme or fallback
    final backgroundColor =
        theme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF1a1a2e) : const Color(0xFFf8f8fc));

    // Parse syntax
    final ast = highlight.parse(content, language: 'markdown');
    
    // Create text style merging font and theme root style
    final textStyle = GoogleFonts.firaCode(fontSize: fontSize).merge(theme['root']);

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
          padding: const EdgeInsets.symmetric(
            horizontal: 32.0,
            vertical: 24.0,
          ),
          child: SelectableText.rich(
            _buildTextSpan(content, ast.nodes!, theme),
            style: textStyle,
            showCursor: true,
            cursorColor: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }
}
