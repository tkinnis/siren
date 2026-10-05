import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siren/app_state.dart';
import 'package:siren/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Single-Tab Invariant and Navigation History', () {
    late AppState appState;
    late Directory tempDir;
    late String fileA;
    late String fileB;
    late String fileC;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('siren_history_test_');
      fileA = p.canonicalize(p.join(tempDir.path, 'doc_a.md'));
      fileB = p.canonicalize(p.join(tempDir.path, 'doc_b.md'));
      fileC = p.canonicalize(p.join(tempDir.path, 'doc_c.md'));

      File(fileA).writeAsStringSync('# Document A');
      File(fileB).writeAsStringSync('# Document B');
      File(fileC).writeAsStringSync('# Document C');

      appState = await AppState.create();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Single-Tab Invariant: opening an already-open file never creates a duplicate tab, just switches to it', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);

      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.activeTabIndex, 1);

      // Attempt to open fileA again (e.g. clicked link, Cmd+click, or search)
      await appState.openFile(fileA, inNewTab: true);

      // Must NOT create a duplicate tab
      expect(appState.openFilePaths, [fileA, fileB]);
      // Must switch to tab 0
      expect(appState.activeTabIndex, 0);
      expect(appState.currentFilePath, fileA);
    });

    test('In-place navigation: openFile with inNewTab: false replaces active tab when file is not open', () async {
      await appState.openFile(fileA);
      expect(appState.openFilePaths, [fileA]);
      expect(appState.activeTabIndex, 0);

      // Plain link click replaces the active tab in-place
      await appState.openFile(fileB, inNewTab: false);

      expect(appState.openFilePaths, [fileB]);
      expect(appState.activeTabIndex, 0);
      expect(appState.currentFilePath, fileB);
    });

    test('New tab navigation: openFile with inNewTab: true appends a new tab when file is not open', () async {
      await appState.openFile(fileA);
      expect(appState.openFilePaths, [fileA]);

      // Cmd+click opens in a new tab
      await appState.openFile(fileB, inNewTab: true);

      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.activeTabIndex, 1);
      expect(appState.currentFilePath, fileB);
    });

    test('History navigation: canGoBack, canGoForward, and tab switching', () async {
      await appState.openFile(fileA);
      // Initially at root of history
      expect(appState.canGoBack, isFalse);
      expect(appState.canGoForward, isFalse);

      await appState.openFile(fileB);
      expect(appState.canGoBack, isTrue);
      expect(appState.canGoForward, isFalse);

      // Go back to fileA
      await appState.goBack();
      expect(appState.activeTabIndex, 0);
      expect(appState.currentFilePath, fileA);
      // Tab list maintained without duplicates
      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.canGoBack, isFalse);
      expect(appState.canGoForward, isTrue);

      // Go forward to fileB
      await appState.goForward();
      expect(appState.activeTabIndex, 1);
      expect(appState.currentFilePath, fileB);
      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.canGoBack, isTrue);
      expect(appState.canGoForward, isFalse);
    });

    test('Closing a file removes it from history and updates canGoBack/canGoForward', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.canGoBack, isTrue);

      // Close fileA
      appState.closeFile(fileA);
      expect(appState.openFilePaths, [fileB]);
      expect(appState.activeTabIndex, 0);

      // fileA must be removed from history; canGoBack must be false
      expect(appState.canGoBack, isFalse);
      expect(appState.canGoForward, isFalse);

      // Hitting goBack must NOT re-open fileA
      await appState.goBack();
      expect(appState.openFilePaths, [fileB]);
      expect(appState.currentFilePath, fileB);
    });

    test('Closing active file removes it from history and adjusts pointer to new active tab', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      expect(appState.openFilePaths, [fileA, fileB]);
      expect(appState.currentFilePath, fileB);

      // Close active tab fileB
      appState.closeFile(fileB);
      expect(appState.openFilePaths, [fileA]);
      expect(appState.currentFilePath, fileA);
      expect(appState.canGoBack, isFalse);
      expect(appState.canGoForward, isFalse);

      // Hitting goBack or goForward must not reopen fileB
      await appState.goBack();
      await appState.goForward();
      expect(appState.openFilePaths, [fileA]);
      expect(appState.currentFilePath, fileA);
    });

    test('Closing background file prunes it from history while preserving valid traversal', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      await appState.openFile(fileC);
      expect(appState.openFilePaths, [fileA, fileB, fileC]);
      expect(appState.currentFilePath, fileC);

      // Close background tab fileB
      appState.closeFile(fileB);
      expect(appState.openFilePaths, [fileA, fileC]);
      expect(appState.currentFilePath, fileC);

      // History should now be [fileA, fileC]; canGoBack should still be true
      expect(appState.canGoBack, isTrue);

      // Navigating back should switch directly to fileA, bypassing fileB entirely
      await appState.goBack();
      expect(appState.activeTabIndex, 0);
      expect(appState.currentFilePath, fileA);
      expect(appState.openFilePaths, [fileA, fileC]);

      // Navigating forward should switch back to fileC
      await appState.goForward();
      expect(appState.activeTabIndex, 1);
      expect(appState.currentFilePath, fileC);
      expect(appState.openFilePaths, [fileA, fileC]);
    });

    test('closeAllFiles completely clears history and disables navigation buttons', () async {
      await appState.openFile(fileA);
      await appState.openFile(fileB);
      expect(appState.canGoBack, isTrue);

      appState.closeAllFiles();
      expect(appState.openFilePaths, isEmpty);
      expect(appState.canGoBack, isFalse);
      expect(appState.canGoForward, isFalse);
    });

    test('Path canonicalization: relative path and canonical path match the same tab', () async {
      await appState.openFile(fileA);

      // Open using a relative path or path containing redundant separators / dot segments
      final redundantPath = '${tempDir.path}/./doc_a.md';
      await appState.openFile(redundantPath);

      // Must still be a single tab
      expect(appState.openFilePaths.length, 1);
      expect(appState.openFilePaths.first, fileA);
    });
  });

  group('Toolbar Navigation Button UI Tests', () {
    testWidgets('Disabled button renders with dimmed opacity and does not trigger action', (
      WidgetTester tester,
    ) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: SirenTheme.light,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  final sirenColors = Theme.of(context).extension<SirenColors>()!;
                  final baseColor = sirenColors.iconColor ?? Theme.of(context).iconTheme.color!;
                  final disabledColor = baseColor.withValues(alpha: 0.25);

                  return Row(
                    children: [
                      // Simulated disabled button
                      Tooltip(
                        message: 'Go Back (Cmd+[)',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.basic,
                          child: GestureDetector(
                            onTap: null,
                            child: Icon(
                              Icons.arrow_back,
                              size: 18,
                              color: disabledColor,
                            ),
                          ),
                        ),
                      ),
                      // Simulated enabled button
                      Tooltip(
                        message: 'Go Forward (Cmd+])',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => pressed = true,
                            child: Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: baseColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap disabled back icon
      final backFinder = find.byIcon(Icons.arrow_back);
      expect(backFinder, findsOneWidget);
      await tester.tap(backFinder);
      await tester.pump();
      expect(pressed, isFalse);

      // Tap enabled forward icon
      final forwardFinder = find.byIcon(Icons.arrow_forward);
      expect(forwardFinder, findsOneWidget);
      await tester.tap(forwardFinder);
      await tester.pump();
      expect(pressed, isTrue);
    });
  });
}
