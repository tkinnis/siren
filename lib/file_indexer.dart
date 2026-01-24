import 'dart:io';
import 'package:path/path.dart' as path;

class FilterRule {
  final RegExp regex;
  final bool matchPath; // true = relative path, false = basename

  FilterRule(this.regex, this.matchPath);
}

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

  /// Files/Folders that are almost never desired even in broad path-based included trees.
  static const Set<String> _systemJunk = {
    '.DS_Store',
    'Thumbs.db',
    '.git',
    '.hg',
    '.svn',
  };

  static List<String> scan(
    String rootPath, {
    List<String> includePatterns = const [],
    List<String> excludePatterns = const [],
  }) {
    final List<String> files = [];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];

    List<FilterRule> parsePatterns(List<String> patterns) {
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

    final includes = parsePatterns(includePatterns);
    final excludes = parsePatterns(excludePatterns);

    _scanRecursive(dir, files, includes, excludes, rootPath);
    return files;
  }

  static void _scanRecursive(
    Directory dir,
    List<String> files,
    List<FilterRule> includes,
    List<FilterRule> excludes,
    String rootPath,
  ) {
    try {
      final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
      
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        String? _relativePath; 
        String getRelativePath() => _relativePath ??= path.relative(entity.path, from: rootPath);

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
        if (isExcluded) continue;

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

        // 3. Smart Filtering
        bool shouldShow = false;
        if (isIncludedByName) {
          // Specifically named -> overrides everything
          shouldShow = true;
        } else if (isIncludedByPath) {
          // Broad path match -> Show unless it's system junk or common heavy dir
          if (_systemJunk.contains(name) || _ignoredDirectories.contains(name)) {
            shouldShow = false;
          } else {
            shouldShow = true;
          }
        } else {
          // Default logic: hide dots and heavy dirs
          if (!_ignoredDirectories.contains(name) && !name.startsWith('.')) {
            shouldShow = true;
          }
        }

        if (!shouldShow) continue;

        if (entity is Directory) {
          _scanRecursive(entity, files, includes, excludes, rootPath);
        } else if (entity is File) {
          // Default file check: include if user rules matched OR if it's markdown
          if (isIncludedByName || isIncludedByPath || 
              (name.toLowerCase().endsWith('.md') || name.toLowerCase().endsWith('.markdown'))) {
             files.add(entity.path);
          }
        }
      }
    } catch (e) {
      // Ignore access errors
    }
  }
}
