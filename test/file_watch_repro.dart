// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

void main() async {
  final tempDir = Directory.systemTemp.createTempSync('siren_repro_');
  final targetFile = File('${tempDir.path}/test_file.txt');
  await targetFile.writeAsString('Initial content');

  print('Watching file: ${targetFile.path}');

  final events = <FileSystemEvent>[];
  StreamSubscription<FileSystemEvent>? subscription;

  void startWatcher() {
    print('Starting watcher...');
    subscription = targetFile.watch(events: FileSystemEvent.all).listen((
      event,
    ) {
      print('Event received: $event');
      events.add(event);

      if (event is FileSystemDeleteEvent) {
        print('Create/Delete detected. Checking for atomic replace...');
        // Give time for the rename to complete
        Future.delayed(const Duration(milliseconds: 100), () async {
          if (await targetFile.exists()) {
            print('File exists after delete! Restarting watcher...');
            await subscription?.cancel();
            startWatcher();
          } else {
            print('File is truly gone.');
          }
        });
      }
    }, onError: (e) => print('Error: $e'));
  }

  startWatcher();

  // Wait for watcher to initialize
  await Future.delayed(const Duration(seconds: 1));

  print('--- Test 1: Atomic Save (Rename) ---');
  // Atomic save simulation: write to temp, rename over target
  final tempFile = File('${tempDir.path}/test_file.tmp');
  await tempFile.writeAsString('Atomic content');
  await tempFile.rename(targetFile.path);

  // Wait for events and logic
  await Future.delayed(const Duration(milliseconds: 500));

  print('--- Test 2: Normal Modify (After Re-watch) ---');
  // Clear events to see if new watcher picks up modify
  events.clear();
  await targetFile.writeAsString('Appended content', mode: FileMode.append);

  // Wait for events
  await Future.delayed(const Duration(milliseconds: 500));

  if (events.any((e) => e is FileSystemModifyEvent)) {
    print('SUCCESS: Watcher fired for specific modify after re-watch.');
  } else {
    print(
      'FAILURE: Watcher did NOT fire for normal modify (after atomic save). Events: $events',
    );
  }

  await subscription?.cancel();
  await tempDir.delete(recursive: true);
}
