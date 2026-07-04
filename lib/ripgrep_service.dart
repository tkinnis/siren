import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

class Submatch {
  final String text;
  final int start;
  final int end;

  Submatch({
    required this.text,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'start': start,
    'end': end,
  };

  factory Submatch.fromJson(Map<String, dynamic> json) => Submatch(
    text: json['text'] as String,
    start: json['start'] as int,
    end: json['end'] as int,
  );
}

class RipgrepMatch {
  final String filePath;
  final int lineNumber;
  final String lineContent;
  final List<Submatch> submatches;

  RipgrepMatch({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
    required this.submatches,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'lineNumber': lineNumber,
    'lineContent': lineContent,
    'submatches': submatches.map((s) => s.toJson()).toList(),
  };

  factory RipgrepMatch.fromJson(Map<String, dynamic> json) => RipgrepMatch(
        filePath: json['filePath'] as String,
        lineNumber: json['lineNumber'] as int,
        lineContent: json['lineContent'] as String,
        submatches: (json['submatches'] as List)
            .map((s) => Submatch.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class RipgrepService {
  static String? _extractedPath;

  /// Resolves the path to the extracted ripgrep binary.
  /// Extracts the binary from assets to Application Support if it doesn't exist yet.
  static Future<String> getExecutablePath() async {
    if (_extractedPath != null && File(_extractedPath!).existsSync()) {
      return _extractedPath!;
    }

    final home = Platform.environment['HOME']!;
    final supportDir = Directory(path.join(home, 'Library', 'Application Support', 'siren'));
    if (!supportDir.existsSync()) {
      supportDir.createSync(recursive: true);
    }

    final targetFile = File(path.join(supportDir.path, 'rg'));
    
    if (!targetFile.existsSync()) {
      final bytes = await rootBundle.load('assets/bin/rg');
      await targetFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      
      // Apply execute permissions
      await Process.run('chmod', ['+x', targetFile.path]);
    }

    _extractedPath = targetFile.path;
    return _extractedPath!;
  }

  /// Run search query using ripgrep in a background Isolate.
  static Future<List<RipgrepMatch>> search({
    required String query,
    required String directoryPath,
    required Set<String> allowedFiles,
    bool matchCase = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) async {
    if (query.isEmpty || directoryPath.isEmpty) return [];

    // Extract binary on the main isolate first, since background isolates
    // do not have direct access to rootBundle easily.
    final rgPath = await getExecutablePath();

    // Execute in a background isolate to keep UI thread fully responsive.
    return Isolate.run(() async {
      final List<String> args = ['--json'];

      if (matchCase) {
        args.add('-s');
      } else {
        args.add('-i');
      }

      if (wholeWord) {
        args.add('-w');
      }

      if (!useRegex) {
        args.add('-F');
      }

      // Restrict search to markdown files, matching Siren's focus
      args.addAll(['-g', '*.md', '-g', '*.markdown']);

      args.add(query);
      args.add(directoryPath);

      final process = await Process.run(rgPath, args);
      if (process.exitCode != 0 && process.stderr.toString().isNotEmpty) {
        if (process.exitCode != 1) { // Exit code 1 means no matches, which is normal
          throw Exception('ripgrep failed: ${process.stderr}');
        }
      }

      final List<RipgrepMatch> matches = [];
      final lines = process.stdout.toString().split('\n');

      for (final line in lines) {
        if (line.isEmpty) continue;
        try {
          final Map<String, dynamic> json = jsonDecode(line) as Map<String, dynamic>;
          if (json['type'] == 'match') {
            final data = json['data'] as Map<String, dynamic>;
            final filePath = data['path']['text'] as String;

            // Only show results for files matching Siren's file indexer (knownFiles)
            if (!allowedFiles.contains(filePath)) continue;

            final lineNumber = data['line_number'] as int;
            final lineContent = data['lines']['text'] as String;
            final submatchesJson = data['submatches'] as List;

            final submatches = submatchesJson.map((m) {
              final submatchMap = m as Map<String, dynamic>;
              return Submatch(
                text: submatchMap['match']['text'] as String,
                start: submatchMap['start'] as int,
                end: submatchMap['end'] as int,
              );
            }).toList();

            matches.add(RipgrepMatch(
              filePath: filePath,
              lineNumber: lineNumber,
              lineContent: lineContent,
              submatches: submatches,
            ));
          }
        } catch (e) {
          // Ignore individual parsing exceptions
        }
      }

      return matches;
    });
  }
}
