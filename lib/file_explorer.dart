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
  // iconSpacing used in _FileExplorerItemView but here it is unused in State.
  // Actually, _FileExplorerItemView defines its own constants.
  static const double _headerHeight = 40.0;
  static const double _minContentWidth = 120.0;

  // System Junk List (matches FileIndexer)
  static const Set<String> _systemJunk = {
    '.DS_Store',
    'Thumbs.db',
    '.git',
    '.hg',
    '.svn',
  };

  // Directories that are heavy and usually ignored unless explicitly included
  static const Set<String> _ignoredDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'node_modules',
  };

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

  late AppState _appState;

  @override
  void dispose() {
    _dirChangeSubscription?.cancel();
    _debounceTimer?.cancel();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _appState.setExplorerRevealCallback(null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = Provider.of<AppState>(context);
    final appState = _appState;

    if (!_initialized) {
      _lastIncludePatterns = List.from(_appState.includePatterns);
      _lastExcludePatterns = List.from(_appState.excludePatterns);

      _appState.setExplorerRevealCallback(_revealPath);

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
    if (!mounted) return;
    if (_currentRoot == null) return;

    final appState = Provider.of<AppState>(context, listen: false);

    // Parse patterns into FilterRules
    List<FilterRule> parse(List<String> patterns) {
      return patterns
          .map((p) {
            try {
              final matchPath = p.startsWith('p:');
              final pattern = (p.startsWith('p:') || p.startsWith('n:'))
                  ? p.substring(2)
                  : p;
              return FilterRule(RegExp(pattern), matchPath);
            } catch (e) {
              return null;
            }
          })
          .whereType<FilterRule>()
          .toList();
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
        // Estimate width
        final estimatedWidth =
            _basePadding +
            (item.depth * _indentPerLevel) +
            _iconSize * 2 +
            (name.length * 8.0) +
            20.0;
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
        String? relativePathStr;
        String getRelativePath() =>
            relativePathStr ??= path.relative(entity.path, from: _currentRoot!);

        bool matchesRule(FilterRule rule) {
          if (rule.matchPath) {
            return rule.regex.hasMatch(getRelativePath());
          } else {
            return rule.regex.hasMatch(name);
          }
        }

        // 1. Check User Excludes (Absolute Priority)
        for (final rule in excludes) {
          if (matchesRule(rule)) return false;
        }

        // 2. Check User Includes
        bool isIncludedByName = false;
        bool isIncludedByPath = false;
        for (final rule in includes) {
          if (matchesRule(rule)) {
            if (rule.matchPath) {
              isIncludedByPath = true;
            } else {
              isIncludedByName = true;
            }
            break;
          }
        }

        // 3. Smart Filtering Logic
        if (isIncludedByName) {
          return true; // Specifically named
        }

        if (isIncludedByPath) {
          // Broad path match -> Hide if it's generic junk
          if (_systemJunk.contains(name) ||
              _ignoredDirectories.contains(name)) {
            return false;
          }
          return true;
        }

        // Default logic
        if (entity is Directory) {
          if (name.startsWith('.')) return false;
          if (_ignoredDirectories.contains(name)) return false;
          return true;
        }

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
    if (!mounted) return;
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

  void _showContextMenu(
    BuildContext context,
    Offset position,
    ExplorerItem item,
  ) {
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    late OverlayEntry overlayEntry;

    // Estimate menu size or measure it?
    // Hardcoding width is safe as Container has width 200.
    // Height is variable but we can estimate: ~120px.
    const double menuWidth = 200.0;
    const double menuHeight = 130.0; // 4 items * ~30 + padding

    double dx = position.dx;
    double dy = position.dy;

    // Adjust horizontal
    if (dx + menuWidth > screenSize.width) {
      dx = screenSize.width - menuWidth - 8; // 8px margin
    }

    // Adjust vertical
    if (dy + menuHeight > screenSize.height) {
      dy = screenSize.height - menuHeight - 8;
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss layer
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => overlayEntry.remove(),
              onSecondaryTapDown: (_) =>
                  overlayEntry.remove(), // Dismiss on right-click elsewhere
            ),
          ),
          // Menu
          Positioned(
            left: dx,
            top: dy,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: menuWidth,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MenuItem(
                      label: Platform.isMacOS
                          ? 'Show in Finder'
                          : (Platform.isWindows
                                ? 'Show in Explorer'
                                : 'Show in File Manager'),
                      onTap: () {
                        overlayEntry.remove();
                        _revealInSystem(item.path);
                      },
                    ),
                    const Divider(height: 1, thickness: 1),
                    _MenuItem(
                      label: 'Copy Path',
                      onTap: () {
                        overlayEntry.remove();
                        Clipboard.setData(ClipboardData(text: item.path));
                      },
                    ),
                    _MenuItem(
                      label: 'Copy Relative Path',
                      onTap: () {
                        overlayEntry.remove();
                        if (_currentRoot != null) {
                          Clipboard.setData(
                            ClipboardData(
                              text: path.relative(
                                item.path,
                                from: _currentRoot!,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
  }

  Future<void> _revealInSystem(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isLinux) {
        // Fallback to opening directory
        final dir = Directory(filePath).existsSync()
            ? filePath
            : path.dirname(filePath);
        await Process.run('xdg-open', [dir]);
      }
    } catch (e) {
      debugPrint('Failed to reveal file: $e');
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
                  child: ClipRect(
                    child: SingleChildScrollView(
                      clipBehavior: Clip.hardEdge,
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

                            return _FileExplorerItemView(
                              item: item,
                              isSelected: isSelected,
                              onTap: () {
                                appState.explorerFocusNode.requestFocus();
                                setState(() => _selectedIndex = index);
                                if (item.isDirectory) {
                                  _toggleExpansion(index);
                                } else {
                                  appState.openFile(item.path);
                                }
                              },
                              onSecondaryTapUp: (details) {
                                appState.explorerFocusNode.requestFocus();
                                setState(() => _selectedIndex = index);
                                _showContextMenu(
                                  context,
                                  details.globalPosition,
                                  item,
                                );
                              },
                            );
                          },
                        ),
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

class _FileExplorerItemView extends StatefulWidget {
  final ExplorerItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(TapUpDetails) onSecondaryTapUp;

  const _FileExplorerItemView({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onSecondaryTapUp,
  });

  @override
  State<_FileExplorerItemView> createState() => _FileExplorerItemViewState();
}

class _FileExplorerItemViewState extends State<_FileExplorerItemView> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // Layout Constants
    const double basePadding = 8.0;
    const double indentPerLevel = 16.0;
    const double iconSize = 16.0;
    const double iconSpacing = 4.0;

    final paddingLeft = basePadding + (widget.item.depth * indentPerLevel);
    final name = path.basename(widget.item.path);

    final color = widget.isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
        : _isHovering
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: color,
          padding: EdgeInsets.only(
            left: paddingLeft,
            top: 4,
            bottom: 4,
            right: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.item.isDirectory)
                Icon(
                  widget.item.isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: iconSpacing),
              Icon(
                widget.item.isDirectory
                    ? (widget.item.isExpanded
                          ? Icons.folder_open
                          : Icons.folder)
                    : Icons.description,
                size: iconSize,
                color: widget.item.isDirectory
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: widget.isSelected
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
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _MenuItem({required this.label, required this.onTap});

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _isHovering
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(widget.label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}
