import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    // Extract background color from theme or fallback
    final backgroundColor =
        theme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA));

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
          child: HighlightView(
            content,
            language: 'markdown',
            theme: theme,
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            textStyle: GoogleFonts.firaCode(fontSize: fontSize),
          ),
        ),
      ),
    );
  }
}