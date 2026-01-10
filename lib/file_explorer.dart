import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'app_state.dart';

class FileExplorer extends StatelessWidget {
  const FileExplorer({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final rootPath = appState.explorerRootPath;

    if (rootPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No folder open',
              style: TextStyle(color: Colors.grey),
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

    return Column(
      children: [
        // Header
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: Row(
            children: [
              const Icon(Icons.folder, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path.basename(rootPath).toUpperCase(),
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
                  // TODO: Implement "Close Folder" in AppState (set root to null)
                  // For now, we can just re-open
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
        // Tree
        Expanded(
          child: SingleChildScrollView(
            child: FileTreeItem(
              dirPath: rootPath,
              level: 0,
              isRoot: true,
            ),
          ),
        ),
      ],
    );
  }
}

class FileTreeItem extends StatefulWidget {
  final String dirPath;
  final int level;
  final bool isRoot;

  const FileTreeItem({
    super.key,
    required this.dirPath,
    required this.level,
    this.isRoot = false,
  });

  @override
  State<FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends State<FileTreeItem> {
  bool _isExpanded = false;
  List<FileSystemEntity> _children = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isRoot) {
      _isExpanded = true;
      _loadChildren();
    }
  }

  Future<void> _loadChildren() async {
    final dir = Directory(widget.dirPath);
    try {
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list().toList();
        
        final filtered = entities.where((entity) {
          final name = path.basename(entity.path);
          if (name.startsWith('.')) return false;
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
          return path.basename(a.path).toLowerCase().compareTo(
                path.basename(b.path).toLowerCase(),
              );
        });

        if (mounted) {
          setState(() {
            _children = filtered;
            _loaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading directory: $e');
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded && !_loaded) {
      _loadChildren();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isRoot) {
      // For root, we just show the children (header is handled by parent)
      if (!_loaded) return const LinearProgressIndicator(minHeight: 2);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _children.map((e) {
          if (e is Directory) {
            return FileTreeItem(dirPath: e.path, level: 0);
          } else {
            return _FileNode(filePath: e.path, level: 0);
          }
        }).toList(),
      );
    }

    final name = path.basename(widget.dirPath);
    final paddingLeft = 8.0 + (widget.level * 12.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpand,
          hoverColor: Theme.of(context).hoverColor,
          child: Padding(
            padding: EdgeInsets.only(left: paddingLeft, top: 4, bottom: 4, right: 8),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Column(
            children: _children.map((e) {
              if (e is Directory) {
                return FileTreeItem(dirPath: e.path, level: widget.level + 1);
              } else {
                return _FileNode(filePath: e.path, level: widget.level + 1);
              }
            }).toList(),
          ),
      ],
    );
  }
}

class _FileNode extends StatelessWidget {
  final String filePath;
  final int level;

  const _FileNode({required this.filePath, required this.level});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final fileName = path.basename(filePath);
    final paddingLeft = 28.0 + (level * 12.0); // Indent to match folder text

    return InkWell(
      onTap: () => appState.openFile(filePath),
      onDoubleTap: () => appState.openFile(filePath), // Same action for now
      hoverColor: Theme.of(context).hoverColor,
      child: Padding(
        padding: EdgeInsets.only(left: paddingLeft, top: 4, bottom: 4, right: 8),
        child: Row(
          children: [
            const Icon(Icons.description, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                fileName,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}