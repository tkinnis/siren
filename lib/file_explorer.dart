import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'app_state.dart';

class FileExplorer extends StatefulWidget {
  const FileExplorer({super.key});

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentDir = appState.currentDirectory;

    if (currentDir == null) {
      return const Center(child: Text('No directory selected'));
    }

    final directory = Directory(currentDir);
    List<FileSystemEntity> entities = [];
    try {
      if (directory.existsSync()) {
        entities = directory.listSync().where((entity) {
          final name = path.basename(entity.path);
          if (name.startsWith('.')) return false; // Hide hidden files
          if (entity is Directory) return true;
          if (entity is File) {
            return name.toLowerCase().endsWith('.md') ||
                name.toLowerCase().endsWith('.markdown');
          }
          return false;
        }).toList();

        // Sort: Directories first, then files
        entities.sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return path.basename(a.path).toLowerCase().compareTo(
                path.basename(b.path).toLowerCase(),
              );
        });
      }
    } catch (e) {
      // Handle permission errors or deleted dirs
    }

    return Column(
      children: [
        // Header with current dir name and up button
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: () {
                  final parent = directory.parent;
                  if (parent.path != directory.path) {
                    appState.setDirectory(parent.path);
                  }
                },
                tooltip: 'Up one level',
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path.basename(currentDir),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entities.length,
            itemBuilder: (context, index) {
              final entity = entities[index];
              final name = path.basename(entity.path);
              final isDir = entity is Directory;

              return ListTile(
                leading: Icon(
                  isDir ? Icons.folder : Icons.description,
                  size: 20,
                  color: isDir
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () {
                  if (isDir) {
                    appState.setDirectory(entity.path);
                  } else {
                    appState.openFile(entity.path);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
