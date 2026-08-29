import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siren/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tab Reordering Tests', () {
    late AppState appState;
    late Directory tempDir;
    late String fileA;
    late String fileB;
    late String fileC;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('siren_tab_test_');
      fileA = p.join(tempDir.path, 'a.md');
      fileB = p.join(tempDir.path, 'b.md');
      fileC = p.join(tempDir.path, 'c.md');

      File(fileA).writeAsStringSync('# File A');
      File(fileB).writeAsStringSync('# File B');
      File(fileC).writeAsStringSync('# File C');

      appState = await AppState.create();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('reorderTabsDirect moves tab forward correctly and maintains active tab', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      await appState.openFile(fileC);

      // Active tab is fileC (index 2)
      expect(appState.openFilePaths, [fileA, fileB, fileC]);
      expect(appState.activeTabIndex, 2);

      // Move fileA (0) to position 1
      appState.reorderTabsDirect(0, 1);

      expect(appState.openFilePaths, [fileB, fileA, fileC]);
      expect(appState.activeTabIndex, 2); // fileC is still at index 2
    });

    test('reorderTabsDirect moves active tab and updates activeTabIndex', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      await appState.openFile(fileC);

      // Select fileB (index 1)
      appState.setActiveTab(1);
      expect(appState.activeTabIndex, 1);

      // Move fileB (1) to index 0
      appState.reorderTabsDirect(1, 0);

      expect(appState.openFilePaths, [fileB, fileA, fileC]);
      expect(appState.activeTabIndex, 0); // fileB moved to index 0, active index updated
    });

    test('reorderTabsDirect ignores out-of-bound indices', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);

      expect(appState.openFilePaths, [fileA, fileB]);

      // Attempt invalid reorder
      appState.reorderTabsDirect(-1, 5);

      expect(appState.openFilePaths, [fileA, fileB]);
    });
  });
}
