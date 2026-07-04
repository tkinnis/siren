import 'dart:io';

void main(List<String> args) async {
  // Parse config path to determine the directory where output.json must be written
  String? configPath;
  for (final arg in args) {
    if (arg.startsWith('--config=')) {
      configPath = arg.substring(9);
    }
  }

  if (configPath != null) {
    final configFile = File(configPath);
    final outDir = configFile.parent;
    final outFile = File('${outDir.path}/output.json');
    
    // Write a minimal valid output.json mapping schema
    outFile.writeAsStringSync(
      '{"timestamp":"${DateTime.now().toUtc().toIso8601String()}",'
      '"assets":[],"version":"1.0.0"}'
    );
  }

  // Still run the download code
  final version = '14.1.0';
  final targetFileName = 'assets/bin/rg';
  
  if (File(targetFileName).existsSync()) {
    return;
  }

  final tempDir = Directory('build/ripgrep_temp');
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
  tempDir.createSync(recursive: true);

  final url = 'https://github.com/BurntSushi/ripgrep/releases/download/$version/ripgrep-$version-aarch64-apple-darwin.tar.gz';
  final tarPath = '${tempDir.path}/rg_arm64.tar.gz';

  try {
    final binDir = Directory('assets/bin');
    if (!binDir.existsSync()) {
      binDir.createSync(recursive: true);
    }

    final downloadResult = await Process.run('curl', ['-L', '-o', tarPath, url]);
    if (downloadResult.exitCode != 0) {
      return;
    }

    final extractResult = await Process.run('tar', ['-xzf', tarPath, '-C', tempDir.path]);
    if (extractResult.exitCode != 0) {
      return;
    }

    final extractedBinary = '${tempDir.path}/ripgrep-$version-aarch64-apple-darwin/rg';
    final targetFile = File(targetFileName);
    
    if (File(extractedBinary).existsSync()) {
      await File(extractedBinary).copy(targetFile.path);
      await Process.run('chmod', ['+x', targetFile.path]);
    }
  } catch (e) {
    // Ignore errors
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
