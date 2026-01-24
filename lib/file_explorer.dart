import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'file_indexer.dart'; // For FilterRule

/// Represents a single item (file or directory) in the file explorer tree.
class ExplorerItem {
  final String path;
  final int depth;
  final bool isDirectory;
  bool isExpanded;

  ExplorerItem({
    required this.path,
    required this.depth,
    required this.isDirectory,
    this.isExpanded = false,
  });
}

/// A widget that displays a file system tree explorer.
///
/// It uses a virtualized [ListView] to render a flattened tree structure for performance.
/// Directory changes are watched and updated automatically.
class FileExplorer extends StatefulWidget {
  const FileExplorer({super.key});

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  // Layout Constants
  static const double _itemHeight = 27.0;
  static const double _basePadding = 8.0;
  static const double _indentPerLevel = 16.0;
  static const double _iconSize = 16.0;
  static const double _iconSpacing = 4.0;
  static const double _headerHeight = 40.0;
  static const double _minContentWidth = 120.0;
  
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  List<ExplorerItem> _flatList = [];
  final Set<String> _expandedPaths = {};
  int _selectedIndex = -1;
  String? _currentRoot;
  bool _initialized = false;
  double _maxContentWidth = 300;
  
  // Pattern tracking for refresh logic
  List<String> _lastIncludePatterns = [];
  List<String> _lastExcludePatterns = [];

  StreamSubscription<String>? _dirChangeSubscription;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _dirChangeSubscription?.cancel();
    _debounceTimer?.cancel();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    
    if (!_initialized) {
      _lastIncludePatterns = List.from(appState.includePatterns);
      _lastExcludePatterns = List.from(appState.excludePatterns);
      
      appState.setExplorerRevealCallback(_revealPath);
      
      // Listen for directory changes from the unified watcher service
      _dirChangeSubscription = appState.directoryChangeStream.listen((path) {
        // Debounce updates
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            _rebuildFlatList();
          }
        });
      });

      _initialized = true;
      _updateTree(appState.explorerRootPath);
    } else {
      // Check if filtering patterns changed
      bool patternsChanged = false;
      if (appState.includePatterns.length != _lastIncludePatterns.length ||
          appState.excludePatterns.length != _lastExcludePatterns.length) {
        patternsChanged = true;
      } else {
        // Deep compare
        for (int i = 0; i < appState.includePatterns.length; i++) {
          if (appState.includePatterns[i] != _lastIncludePatterns[i]) {
            patternsChanged = true;
            break;
          }
        }
        if (!patternsChanged) {
          for (int i = 0; i < appState.excludePatterns.length; i++) {
            if (appState.excludePatterns[i] != _lastExcludePatterns[i]) {
              patternsChanged = true;
              break;
            }
          }
        }
      }

      if (patternsChanged) {
        _lastIncludePatterns = List.from(appState.includePatterns);
        _lastExcludePatterns = List.from(appState.excludePatterns);
        _rebuildFlatList();
      }

      if (appState.explorerRootPath != _currentRoot) {
        _updateTree(appState.explorerRootPath);
      }
    }
  }

  Future<void> _updateTree(String? newRoot) async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    if (newRoot == _currentRoot) return;
    
    // Unwatch old root
    if (_currentRoot != null) {
      appState.unwatchDirectory(_currentRoot!);
    }

    _currentRoot = newRoot;
    _expandedPaths.clear();
    _flatList.clear();
    _selectedIndex = -1;

    if (newRoot != null) {
      _expandedPaths.add(newRoot); // Always expand root
      await _rebuildFlatList();
      // Watch new root
      appState.watchDirectory(newRoot);
    } else {
      setState(() {});
    }
  }

  Future<void> _rebuildFlatList() async {
    if (_currentRoot == null) return;

    final appState = Provider.of<AppState>(context, listen: false);
    
    // Parse patterns into FilterRules
    List<FilterRule> parse(List<String> patterns) {
      return patterns.map((p) {
        try {
          final matchPath = p.startsWith('p:');
          final pattern = (p.startsWith('p:') || p.startsWith('n:')) ? p.substring(2) : p;
          return FilterRule(RegExp(pattern), matchPath);
        } catch (e) {
          return null;
        }
      }).whereType<FilterRule>().toList();
    }

    final includes = parse(appState.includePatterns);
    final excludes = parse(appState.excludePatterns);

    final List<ExplorerItem> newList = [];
    await _traverse(_currentRoot!, 0, newList, includes, excludes);

    if (mounted) {
      // Calculate max content width based on deepest item and text length
      double maxWidth = 300;
      for (final item in newList) {
        final name = path.basename(item.path);
        // Estimate width: padding + depth indent + icons + text length
        final estimatedWidth =
            _basePadding + (item.depth * _indentPerLevel) + _iconSize * 2 + (name.length * 8.0) + 20.0;
        if (estimatedWidth > maxWidth) {
          maxWidth = estimatedWidth;
        }
      }

      setState(() {
        _flatList = newList;
        _maxContentWidth = maxWidth;
      });
    }
  }

  Future<void> _traverse(
    String dirPath,
    int depth,
    List<ExplorerItem> list,
    List<FilterRule> includes,
    List<FilterRule> excludes,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();

      final filtered = entities.where((entity) {
        final name = path.basename(entity.path);
        
        // Only calculate relative path if needed by a rule (optimization)
        String? _relativePath; 
        String getRelativePath() => _relativePath ??= path.relative(entity.path, from: _currentRoot!);

        bool matchesRule(FilterRule rule) {
          if (rule.matchPath) {
            return rule.regex.hasMatch(getRelativePath());
          } else {
            return rule.regex.hasMatch(name);
          }
        }
        
        // 1. Check User Excludes (Absolute Priority)
        bool isExcluded = false;
        for (final rule in excludes) {
          if (matchesRule(rule)) {
            isExcluded = true;
            break;
          }
        }
        if (isExcluded) return false;

        // 2. Check User Includes (Overrides defaults)
        bool isExplicitlyIncluded = false;
        for (final rule in includes) {
          if (matchesRule(rule)) {
            isExplicitlyIncluded = true;
            break;
          }
        }

        if (entity is Directory) {
          if (isExplicitlyIncluded) return true;
          
          // Default: hide all dotfolders
          if (name.startsWith('.')) return false;
          return true;
        }
        if (entity is File) {
          if (isExplicitlyIncluded) return true;
          
          return name.toLowerCase().endsWith('.md') ||
              name.toLowerCase().endsWith('.markdown');
        }
        return false;
      }).toList();

      // Sort: Directories first, then files
      filtered.sort((a, b) {
        if (a is Directory && b is File) return -1;
        if (a is File && b is Directory) return 1;
        return path
            .basename(a.path)
            .toLowerCase()
            .compareTo(path.basename(b.path).toLowerCase());
      });

      for (final entity in filtered) {
        final isDir = entity is Directory;
        final itemPath = entity.path;
        final item = ExplorerItem(
          path: itemPath,
          depth: depth,
          isDirectory: isDir,
          isExpanded: _expandedPaths.contains(itemPath),
        );

        list.add(item);

        if (isDir && _expandedPaths.contains(itemPath)) {
          await _traverse(itemPath, depth + 1, list, includes, excludes);
        }
      }
    } catch (e) {
      debugPrint("Error traversing $dirPath: $e");
    }
  }

  Future<void> _toggleExpansion(int index) async {
    final item = _flatList[index];
    if (!item.isDirectory) return;

    if (_expandedPaths.contains(item.path)) {
      _expandedPaths.remove(item.path);
    } else {
      _expandedPaths.add(item.path);
    }

    await _rebuildFlatList();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_selectedIndex < _flatList.length - 1) {
        setState(() => _selectedIndex++);
        _scrollToSelected();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_selectedIndex > 0) {
        setState(() => _selectedIndex--);
        _scrollToSelected();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_selectedIndex >= 0 && _selectedIndex < _flatList.length) {
        final item = _flatList[_selectedIndex];
        if (item.isDirectory) {
          if (!_expandedPaths.contains(item.path)) {
            _toggleExpansion(_selectedIndex);
          } else {
            // Select first child
            if (_selectedIndex + 1 < _flatList.length) {
              final nextItem = _flatList[_selectedIndex + 1];
              if (nextItem.depth > item.depth) {
                setState(() => _selectedIndex++);
                _scrollToSelected();
              }
            }
          }
        }
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_selectedIndex >= 0 && _selectedIndex < _flatList.length) {
        final item = _flatList[_selectedIndex];
        if (item.isDirectory && _expandedPaths.contains(item.path)) {
          _toggleExpansion(_selectedIndex);
        } else {
          // Jump to parent
          // Iterate backwards to find item with depth - 1
          for (int i = _selectedIndex - 1; i >= 0; i--) {
            if (_flatList[i].depth < item.depth) {
              setState(() => _selectedIndex = i);
              _scrollToSelected();
              break;
            }
          }
        }
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _flatList.length) {
        final item = _flatList[_selectedIndex];
        if (item.isDirectory) {
          _toggleExpansion(_selectedIndex);
        } else {
          Provider.of<AppState>(context, listen: false).openFile(item.path);
        }
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    if (_selectedIndex < 0 || !_verticalScrollController.hasClients) return;

    final targetOffset = _selectedIndex * _itemHeight;
    final viewportHeight = _verticalScrollController.position.viewportDimension;
    final currentOffset = _verticalScrollController.offset;
    final maxOffset = _verticalScrollController.position.maxScrollExtent;

    // Check if already visible
    if (targetOffset >= currentOffset &&
        targetOffset + _itemHeight <= currentOffset + viewportHeight) {
      return;
    }

    // Calculate new scroll position
    double newOffset;
    if (targetOffset < currentOffset) {
      // Scrolling up - align to top
      newOffset = targetOffset;
    } else {
      // Scrolling down - align to bottom
      newOffset = targetOffset - viewportHeight + _itemHeight;
    }

    _verticalScrollController.animateTo(
      newOffset.clamp(0.0, maxOffset),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  Future<void> _revealPath(String filePath) async {
    if (_currentRoot == null) return;

    // Check if path is within root
    if (!path.isWithin(_currentRoot!, filePath)) return;

    // Expand all parents
    var parent = path.dirname(filePath);
    bool changed = false;
    while (path.isWithin(_currentRoot!, parent) ||
        path.equals(_currentRoot!, parent)) {
      // Stop if we reach root or go above
      if (parent.length < _currentRoot!.length) break;

      if (parent != _currentRoot && !_expandedPaths.contains(parent)) {
        _expandedPaths.add(parent);
        changed = true;
      }
      if (parent == _currentRoot) break;
      parent = path.dirname(parent);
    }

    if (changed) {
      await _rebuildFlatList();
    }

    // Find index
    final index = _flatList.indexWhere((item) => item.path == filePath);
    if (index != -1) {
      setState(() => _selectedIndex = index);
      _scrollToSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (_currentRoot == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No folder open',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: appState.openDirectory,
              child: const Text('Open Folder'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Don't render content when width is too small (during animation)
        if (constraints.maxWidth < _minContentWidth) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            // Header
            Container(
              height: _headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: _iconSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path.basename(_currentRoot!).toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: _iconSize),
                    onPressed: () {
                      appState.openDirectory();
                    },
                    tooltip: 'Change Folder',
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: appState.explorerFocusNode,
                onKeyEvent: _onKeyEvent,
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  notificationPredicate: (notification) =>
                      notification.depth == 1,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _maxContentWidth,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: _flatList.length,
                        itemExtent: _itemHeight,
                        itemBuilder: (context, index) {
                          final item = _flatList[index];
                          final isSelected = index == _selectedIndex;
                          final name = path.basename(item.path);
                          final paddingLeft = _basePadding + (item.depth * _indentPerLevel);

                          return InkWell(
                            onTap: () {
                              appState.explorerFocusNode.requestFocus();
                              setState(() => _selectedIndex = index);
                              if (item.isDirectory) {
                                _toggleExpansion(index);
                              } else {
                                appState.openFile(item.path);
                              }
                            },
                            child: Container(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.15)
                                  : null,
                              padding: EdgeInsets.only(
                                left: paddingLeft,
                                top: 4,
                                bottom: 4,
                                right: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.isDirectory)
                                    Icon(
                                      _expandedPaths.contains(item.path)
                                          ? Icons.keyboard_arrow_down
                                          : Icons.keyboard_arrow_right,
                                      size: _iconSize,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    )
                                  else
                                    const SizedBox(width: 16),
                                  const SizedBox(width: _iconSpacing),
                                  Icon(
                                    item.isDirectory
                                        ? (_expandedPaths.contains(item.path)
                                              ? Icons.folder_open
                                              : Icons.folder)
                                        : Icons.description,
                                    size: _iconSize,
                                    color: item.isDirectory
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : null,
                                        fontWeight: isSelected
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
