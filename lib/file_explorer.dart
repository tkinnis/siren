import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:watcher/watcher.dart';
import 'app_state.dart';

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

class FileExplorer extends StatefulWidget {
  const FileExplorer({super.key});

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  List<ExplorerItem> _flatList = [];
  final Set<String> _expandedPaths = {};
  int _selectedIndex = -1;
  String? _currentRoot;
  bool _initialized = false;
  double _maxContentWidth = 300;
  static const double _itemHeight = 27.0;

  StreamSubscription<WatchEvent>? _watchSubscription;
  Timer? _debounceTimer;
  Isolate? _watcherIsolate;
  ReceivePort? _watcherReceivePort;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _watchSubscription?.cancel();
    _debounceTimer?.cancel();
    _watcherIsolate?.kill(priority: Isolate.immediate);
    _watcherReceivePort?.close();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.setExplorerRevealCallback(_revealPath);
      _initialized = true;
      _updateTree(appState.explorerRootPath);
    } else {
      // Watch for root changes
      final appState = Provider.of<AppState>(context);
      if (appState.explorerRootPath != _currentRoot) {
        _updateTree(appState.explorerRootPath);
      }
    }
  }

  Future<void> _updateTree(String? newRoot) async {
    if (newRoot == _currentRoot) return;
    _currentRoot = newRoot;
    _expandedPaths.clear();
    _flatList.clear();
    _selectedIndex = -1;

    // Cancel existing watcher
    await _watchSubscription?.cancel();
    _watchSubscription = null;

    if (newRoot != null) {
      _expandedPaths.add(newRoot); // Always expand root
      await _rebuildFlatList();
      _setupWatcher(newRoot);
    } else {
      setState(() {});
    }
  }

  void _setupWatcher(String path) async {
    _debounceTimer?.cancel();
    _watcherIsolate?.kill(priority: Isolate.immediate);
    _watcherReceivePort?.close();

    _watcherReceivePort = ReceivePort();
    
    try {
      _watcherIsolate = await Isolate.spawn(
        _watcherEntryPoint,
        _WatcherArgs(path, _watcherReceivePort!.sendPort),
      );

      _watcherReceivePort!.listen((message) {
        // Debounce updates to avoid flickering on mass operations
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            _rebuildFlatList();
          }
        });
      });
    } catch (e) {
      debugPrint("Failed to set up directory watcher isolate: $e");
    }
  }

  static void _watcherEntryPoint(_WatcherArgs args) {
    try {
      final watcher = DirectoryWatcher(args.path);
      watcher.events.listen((event) {
        args.sendPort.send(event.type);
      }, onError: (e) {
        debugPrint("Watcher isolate error: $e");
      });
    } catch (e) {
      debugPrint("Watcher isolate setup error: $e");
    }
  }

  Future<void> _rebuildFlatList() async {
    if (_currentRoot == null) return;

    final List<ExplorerItem> newList = [];
    await _traverse(_currentRoot!, 0, newList);

    if (mounted) {
      // Calculate max content width based on deepest item and text length
      double maxWidth = 300;
      for (final item in newList) {
        final name = path.basename(item.path);
        // Estimate: padding + depth indent + icons + text
        // paddingLeft = 8 + depth * 16, icons ~40px, text ~8px per char
        final estimatedWidth =
            8.0 + (item.depth * 16.0) + 40.0 + (name.length * 12.0) + 40.0;
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
  ) async {
    // Determine if expanded. Root is always expanded effectively (we list its children at depth 0)
    // Actually, let's treat the root content as starting at depth 0 without showing the root folder itself?
    // Or show the root folder? The design shows a header for the root.
    // So we list the children of _currentRoot.

    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();

      final filtered = entities.where((entity) {
        final name = path.basename(entity.path);
        if (entity is Directory) return true;
        if (entity is File) {
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

        // Add to synchronized list (or simple list since we await all at end of this level? No, order matters)
        // We must maintain order. 
        // Actually, for flattened tree view, we need: Item, then its children, then Next Item.
        // Parallelizing this strictly with Future.wait breaks the DFS order needed for the visual tree.
        // However, we can fetch children in parallel and then insert them.
        
        list.add(item);

        if (isDir && _expandedPaths.contains(itemPath)) {
          // We must await here to maintain DFS visual order (Folder -> Children -> Next Sibling)
          // To optimize, we could pre-fetch, but 'list' must be populated in order.
          await _traverse(itemPath, depth + 1, list);
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
      // ... existing empty state code ...
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
        // Header needs ~120px for icons, padding, and minimum text
        if (constraints.maxWidth < 120) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: 16,
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
                    icon: const Icon(Icons.close, size: 16),
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
                          final paddingLeft = 8.0 + (item.depth * 16.0);

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
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    )
                                  else
                                    const SizedBox(width: 16),
                                  const SizedBox(width: 4),
                                  Icon(
                                    item.isDirectory
                                        ? (_expandedPaths.contains(item.path)
                                              ? Icons.folder_open
                                              : Icons.folder)
                                        : Icons.description,
                                    size: 16,
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

class _WatcherArgs {
  final String path;
  final SendPort sendPort;

  _WatcherArgs(this.path, this.sendPort);
}
