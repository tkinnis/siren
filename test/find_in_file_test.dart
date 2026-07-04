import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siren/app_state.dart';

void main() {
  group('Find in File Logic Tests', () {
    late AppState appState;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      appState = await AppState.create();
    });

    test('findMatchOffsets finds multiple case-insensitive matches', () {
      final content = 'Hello world! hello there. HELLO again.';
      final offsets = appState.findMatchOffsets(content, 'hello');
      
      expect(offsets.length, 3);
      expect(offsets[0], 0);   // 'Hello'
      expect(offsets[1], 13);  // 'hello'
      expect(offsets[2], 26);  // 'HELLO'
    });

    test('findMatchOffsets returns empty list on empty query', () {
      final content = 'Hello world!';
      final offsets = appState.findMatchOffsets(content, '');
      
      expect(offsets.isEmpty, true);
    });

    test('getLineNumberForOffset calculates line numbers correctly', () {
      final content = 'Line 1\nLine 2\nLine 3\nLine 4';
      
      // 'Line 1' (offset 0)
      expect(appState.getLineNumberForOffset(content, 0), 1);
      
      // 'Line 2' (offset 7)
      expect(appState.getLineNumberForOffset(content, 7), 2);
      
      // 'Line 3' (offset 14)
      expect(appState.getLineNumberForOffset(content, 14), 3);
      
      // Beyond length or boundary
      expect(appState.getLineNumberForOffset(content, 100), 4);
    });

    test('findMatchOffsets finds regex matches correctly', () {
      final content = 'foo barrr baz fooo';
      final offsets = appState.findMatchOffsets(content, 'bar+', useRegex: true);
      
      expect(offsets.length, 1);
      expect(offsets[0], 4); // 'barrr'
    });
  });
}
