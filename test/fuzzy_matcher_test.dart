import 'package:flutter_test/flutter_test.dart';
import 'package:siren/fuzzy_matcher.dart';

void main() {
  group('FuzzyMatcher', () {
    test('Subsequence matching with spaces', () {
      final items = [
        'foo/bar/baz/file.txt',
        'foo/rup/baz/file.txt',
        'other/folder/doc.md'
      ];
      
      // "foo baz f" should match both foo/... paths
      final results = FuzzyMatcher.search(items, 'foo baz f');
      
      expect(results.length, 2);
      expect(results.any((r) => r.item.contains('foo/bar/baz')), true);
      expect(results.any((r) => r.item.contains('foo/rup/baz')), true);
    });

    test('Prioritizes filename over path', () {
      final items = [
        'src/core/model.dart',
        'src/model/other.dart',
      ];
      
      // Query "model" should prefer the one where "model" is the filename
      final results = FuzzyMatcher.search(items, 'model');
      
      expect(results[0].item, 'src/core/model.dart');
    });

    test('Boundary matching (fb -> foo/bar)', () {
      final items = [
        'facebook.md',
        'foo/bar.md',
      ];
      
      final results = FuzzyMatcher.search(items, 'fb');
      
      // fb should match f in foo and b in bar (boundary) over f and b in facebook
      expect(results[0].item, 'foo/bar.md');
    });

    test('CamelCase matching', () {
      final items = [
        'UserAccountManager.dart',
        'update_user_account.dart',
      ];
      
      final results = FuzzyMatcher.search(items, 'uam');
      expect(results[0].item, 'UserAccountManager.dart');
    });

    test('Scale test: 1000 files', () {
      final items = List.generate(1000, (i) => 'folder_$i/file_$i.md');
      items.add('target/match/file.md');
      
      final stopwatch = Stopwatch()..start();
      final results = FuzzyMatcher.search(items, 'tmf');
      stopwatch.stop();
      
      expect(results[0].item, 'target/match/file.md');
      expect(stopwatch.elapsedMilliseconds, lessThan(10)); // Should be extremely fast
    });
  });
}