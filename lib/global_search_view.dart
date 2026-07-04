import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'ripgrep_service.dart';
import 'theme.dart';

class GlobalSearchView extends StatefulWidget {
  const GlobalSearchView({super.key});

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  bool _matchCase = false;
  bool _wholeWord = false;
  bool _useRegex = false;
  
  bool _isSearching = false;
  List<RipgrepMatch> _results = [];
  String _errorMessage = '';
  
  Timer? _debounceTimer;
  int _lastTabIndex = -1;
  bool _lastExplorerVisible = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    final currentTabIndex = appState.sidebarTabIndex;
    final isVisible = appState.isExplorerVisible;

    if (currentTabIndex == 2 && isVisible) {
      if (_lastTabIndex != 2 || !_lastExplorerVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_focusNode.canRequestFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    }
    _lastTabIndex = currentTabIndex;
    _lastExplorerVisible = isVisible;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceSearch(_controller.text);
  }

  void _debounceSearch(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _errorMessage = '';
      });
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final rootPath = appState.explorerRootPath;
    
    if (rootPath == null) {
      setState(() {
        _results = [];
        _isSearching = false;
        _errorMessage = 'No directory open';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = '';
    });

    try {
      // Map knownFiles list to a Set for O(1) matching against search results
      final allowedFiles = Set<String>.from(appState.knownFiles);
      
      final matches = await RipgrepService.search(
        query: query,
        directoryPath: rootPath,
        allowedFiles: allowedFiles,
        matchCase: _matchCase,
        wholeWord: _wholeWord,
        useRegex: _useRegex,
      );
      
      if (mounted) {
        setState(() {
          _results = matches;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = [];
          _isSearching = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _toggleMatchCase() {
    setState(() => _matchCase = !_matchCase);
    _performSearch(_controller.text);
  }

  void _toggleWholeWord() {
    setState(() => _wholeWord = !_wholeWord);
    _performSearch(_controller.text);
  }

  void _toggleUseRegex() {
    setState(() => _useRegex = !_useRegex);
    _performSearch(_controller.text);
  }

  Map<String, List<RipgrepMatch>> _groupResultsByFile() {
    final Map<String, List<RipgrepMatch>> grouped = {};
    for (final match in _results) {
      grouped.putIfAbsent(match.filePath, () => []).add(match);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sirenColors = Theme.of(context).extension<SirenColors>()!;
    final rootPath = appState.explorerRootPath;

    if (rootPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Open a directory to search.',
            style: TextStyle(color: Theme.of(context).disabledColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final groupedResults = _groupResultsByFile();
    final fileCount = groupedResults.keys.length;
    final matchCount = _results.length;

    return Column(
      children: [
        // Search Inputs
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: sirenColors.borderColor ?? Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search files...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _controller.clear();
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: sirenColors.borderColor ?? Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  _performSearch(value);
                  _focusNode.requestFocus();
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _FilterToggle(
                    label: 'Aa',
                    tooltip: 'Match Case',
                    isActive: _matchCase,
                    onPressed: _toggleMatchCase,
                  ),
                  const SizedBox(width: 6),
                  _FilterToggle(
                    label: '[ab]',
                    tooltip: 'Match Whole Word',
                    isActive: _wholeWord,
                    onPressed: _toggleWholeWord,
                  ),
                  const SizedBox(width: 6),
                  _FilterToggle(
                    label: '.*',
                    tooltip: 'Use Regular Expression',
                    isActive: _useRegex,
                    onPressed: _toggleUseRegex,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Search Results / Loading / Guidance
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _controller.text.isEmpty
                                ? 'Type a query to search'
                                : 'No results found',
                            style: TextStyle(color: Theme.of(context).disabledColor),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: Text(
                                'Found $matchCount matches in $fileCount files',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: groupedResults.length,
                                itemBuilder: (context, index) {
                                  final filePath = groupedResults.keys.elementAt(index);
                                  final fileMatches = groupedResults[filePath]!;
                                  final relativePath = path.relative(filePath, from: rootPath);
                                  final fileName = path.basename(filePath);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // File Header
                                      InkWell(
                                        onTap: () {
                                          appState.openFile(filePath);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12.0,
                                            vertical: 6.0,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.description_outlined,
                                                size: 14,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      fileName,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      relativePath,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Matches in File
                                      ...fileMatches.map((match) {
                                        return InkWell(
                                          onTap: () {
                                            appState.setRenderedView(false);
                                            appState.openFile(match.filePath);
                                            if (_controller.text.isNotEmpty) {
                                              appState.showFindInFile();
                                              appState.setFindInFileQuery(_controller.text, useRegex: _useRegex);
                                              appState.setActiveMatchIndexToLine(match.lineNumber);
                                            }
                                            appState.scrollTo(match.lineNumber, match.lineContent);
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 28.0,
                                              right: 12.0,
                                              top: 4.0,
                                              bottom: 4.0,
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 24,
                                                  alignment: Alignment.topRight,
                                                  padding: const EdgeInsets.only(right: 6.0),
                                                  child: Text(
                                                    '${match.lineNumber}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontFamily: 'monospace',
                                                      color: Theme.of(context).disabledColor,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: _buildLineRichText(
                                                    match.lineContent.trim(),
                                                    match.submatches,
                                                    TextStyle(
                                                      fontSize: 11,
                                                      color: Theme.of(context).colorScheme.onSurface,
                                                    ),
                                                    TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Theme.of(context).colorScheme.primary,
                                                      backgroundColor: Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withValues(alpha: 0.1),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                      const Divider(height: 12, thickness: 0.5),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildLineRichText(
    String line,
    List<Submatch> submatches,
    TextStyle normalStyle,
    TextStyle matchStyle,
  ) {
    if (submatches.isEmpty) {
      return Text(line, style: normalStyle);
    }

    final sortedMatches = List<Submatch>.from(submatches)
      ..sort((a, b) => a.start.compareTo(b.start));

    final List<InlineSpan> spans = [];
    int current = 0;

    for (final sub in sortedMatches) {
      if (sub.start > current && sub.start <= line.length) {
        spans.add(TextSpan(text: line.substring(current, sub.start), style: normalStyle));
      }

      final end = sub.end.clamp(0, line.length);
      if (sub.start < line.length && end > sub.start) {
        spans.add(TextSpan(text: line.substring(sub.start, end), style: matchStyle));
      }
      current = end;
    }

    if (current < line.length) {
      spans.add(TextSpan(text: line.substring(current), style: normalStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _FilterToggle({
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? activeColor : inactiveColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
