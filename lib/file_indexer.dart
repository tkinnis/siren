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

  static List<String> scan(
    String rootPath, {
    List<String> includePatterns = const [],
    List<String> excludePatterns = const [],
  }) {
    final List<String> files = [];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];

    final includes = includePatterns.map((p) => RegExp(p)).toList();
    final excludes = excludePatterns.map((p) => RegExp(p)).toList();

    _scanRecursive(dir, files, includes, excludes);
    return files;
  }

  static void _scanRecursive(
    Directory dir,
    List<String> files,
    List<RegExp> includes,
    List<RegExp> excludes,
  ) {
    try {
      final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
      
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        // 1. Check User Includes (Priority Override)
        bool isExplicitlyIncluded = false;
        for (final regex in includes) {
          if (regex.hasMatch(name)) {
            isExplicitlyIncluded = true;
            break;
          }
        }

        // 2. Check User Excludes (Only if not explicitly included)
        if (!isExplicitlyIncluded) {
          bool isExcluded = false;
          for (final regex in excludes) {
            if (regex.hasMatch(name)) {
              isExcluded = true;
              break;
            }
          }
          if (isExcluded) continue;
        }

        if (entity is Directory) {
          // If explicitly included, skip default checks
          if (isExplicitlyIncluded) {
            _scanRecursive(entity, files, includes, excludes);
          } else {
            // Default checks
            if (!_ignoredDirectories.contains(name) && !name.startsWith('.')) {
              _scanRecursive(entity, files, includes, excludes);
            }
          }
        } else if (entity is File) {
          if (isExplicitlyIncluded) {
             files.add(entity.path);
          } else {
             // Default file checks
             if ((name.endsWith('.md') || name.endsWith('.markdown')) && !name.startsWith('.')) {
               files.add(entity.path);
             }
          }
        }
      }
    } catch (e) {
      // Ignore access errors
    }
  }
}
