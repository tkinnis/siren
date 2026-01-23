import 'dart:io';
import 'package:path/path.dart' as path;

class FileIndexer {
  static const Set<String> _ignoredDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'node_modules',
    'ios/Pods',
    'macos/Pods',
    'android/app/build',
    'web/build',
  };

  static List<String> scan(String rootPath) {
    final List<String> files = [];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];

    _scanRecursive(dir, files);
    return files;
  }

  static void _scanRecursive(Directory dir, List<String> files) {
    try {
      final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
      
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        if (entity is Directory) {
          if (!_ignoredDirectories.contains(name) && !name.startsWith('.')) {
            _scanRecursive(entity, files);
          }
        } else if (entity is File) {
          if ((name.endsWith('.md') || name.endsWith('.markdown')) && !name.startsWith('.')) {
            files.add(entity.path);
          }
        }
      }
    } catch (e) {
      // Ignore access errors
    }
  }
}
