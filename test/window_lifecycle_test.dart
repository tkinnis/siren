import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siren/app_state.dart';
import 'package:siren/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Window lifecycle and native channel safety', () {
    late AppState appState;
    late Directory tempDir;
    late String sampleFile;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('siren_window_test_');
      sampleFile = p.canonicalize(p.join(tempDir.path, 'sample.md'));
      File(sampleFile).writeAsStringSync('# Window Lifecycle Test');
      appState = await AppState.create();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'MainApp mounts and disposes cleanly without a native desktop window',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(MainApp(appState: appState));
        await tester.pump();

        expect(find.byType(MaterialApp), findsOneWidget);

        // Unmount MainApp to exercise _MainAppState.dispose() listener cleanup.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    test('openFile platform message opens target file without failing in headless VM', () async {
      const codec = StandardMethodCodec();
      final encodedCall = codec.encodeMethodCall(
        MethodCall('openFile', sampleFile),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.tonykinnis.Siren/files',
            encodedCall,
            (_) {},
          );

      expect(appState.openFilePaths, [sampleFile]);
      expect(appState.currentFilePath, sampleFile);
    });
  });
}
