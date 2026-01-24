import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'app_state.dart';
import 'fuzzy_matcher.dart';

class FileSearchModal extends StatefulWidget {
  const FileSearchModal({super.key});

  @override
  State<FileSearchModal> createState() => _FileSearchModalState();
}

class _FileSearchModalState extends State<FileSearchModal> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  List<String> _allFiles = [];
  List<String> _relativePaths = [];
  List<String> _filteredFiles = [];
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _controller.addListener(_filterFiles);
  }

  void _loadFiles() {
    final appState = Provider.of<AppState>(context, listen: false);
    final files = appState.knownFiles;
    final root = appState.explorerRootPath;

    setState(() {
      _allFiles = files;
      _relativePaths = root != null
          ? files.map((f) => path.relative(f, from: root)).toList()
          : files;
      _filteredFiles = _allFiles;
      _isLoading = false;
    });
  }

  void _filterFiles() {
    final query = _controller.text;
    final appState = Provider.of<AppState>(context, listen: false);
    final root = appState.explorerRootPath;

    setState(() {
      _selectedIndex = 0;
      if (query.isEmpty) {
        _filteredFiles = _allFiles;
      } else {
        final results = FuzzyMatcher.search(_relativePaths, query);
        _filteredFiles = results.map((r) {
          if (root != null) {
            return path.join(root, r.item);
          }
          return r.item;
        }).toList();
      }
    });
  }

  void _selectFile() {
    if (_selectedIndex >= 0 && _selectedIndex < _filteredFiles.length) {
      final filePath = _filteredFiles[_selectedIndex];
      Provider.of<AppState>(context, listen: false).openFile(filePath);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final root = appState.explorerRootPath;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              setState(() {
                _selectedIndex =
                    (_selectedIndex + 1).clamp(0, _filteredFiles.length - 1);
              });
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              setState(() {
                _selectedIndex =
                    (_selectedIndex - 1).clamp(0, _filteredFiles.length - 1);
              });
            },
            const SingleActivator(LogicalKeyboardKey.enter): _selectFile,
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.of(context).pop();
            },
          },
          child: Container(
            width: 600,
            height: 400,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search files by name...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _selectFile(),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredFiles.isEmpty
                      ? Center(
                          child: Text(
                            'No matching files',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredFiles.length,
                          itemBuilder: (context, index) {
                            final filePath = _filteredFiles[index];
                            final isSelected = index == _selectedIndex;
                            final relativePath = root != null
                                ? path.relative(filePath, from: root)
                                : filePath;

                            return InkWell(
                              onTap: () {
                                _selectedIndex = index;
                                _selectFile();
                              },
                              onHover: (hovering) {
                                if (hovering) {
                                  setState(() => _selectedIndex = index);
                                }
                              },
                              child: Container(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.1)
                                    : null,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            path.basename(filePath),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            relativePath,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
