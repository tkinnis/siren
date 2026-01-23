import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:watcher/watcher.dart';

enum WatchCommandType { watchFile, unwatchFile, watchDirectory, unwatchDirectory }

class WatchCommand {
  final WatchCommandType type;
  final String path;

  WatchCommand(this.type, this.path);
}

class WatchEventMessage {
  final String path;
  final ChangeType type;

  WatchEventMessage(this.path, this.type);
}

class WatcherService {
  Isolate? _isolate;
  SendPort? _sendPort;
  StreamSubscription? _receiveSubscription;
  final Function(String path, ChangeType type) onFileEvent;
  final Function(String path) onDirectoryEvent;

  WatcherService({
    required this.onFileEvent,
    required this.onDirectoryEvent,
  });

  Future<void> init() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_entryPoint, receivePort.sendPort);
    
    final broadcastStream = receivePort.asBroadcastStream();
    _sendPort = await broadcastStream.first as SendPort;

    _receiveSubscription = broadcastStream.listen((message) {
      if (message is WatchEventMessage) {
        onFileEvent(message.path, message.type);
      } else if (message is String) {
        // Directory change signal (we just send the root path usually)
        onDirectoryEvent(message);
      }
    });
  }

  void watchFile(String path) {
    _sendPort?.send(WatchCommand(WatchCommandType.watchFile, path));
  }

  void unwatchFile(String path) {
    _sendPort?.send(WatchCommand(WatchCommandType.unwatchFile, path));
  }

  void watchDirectory(String path) {
    _sendPort?.send(WatchCommand(WatchCommandType.watchDirectory, path));
  }

  void unwatchDirectory(String path) {
    _sendPort?.send(WatchCommand(WatchCommandType.unwatchDirectory, path));
  }

  void dispose() {
    _receiveSubscription?.cancel();
    _isolate?.kill();
  }

  static void _entryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    final Map<String, StreamSubscription> fileSubscriptions = {};
    StreamSubscription? dirSubscription;

    receivePort.listen((message) {
      if (message is WatchCommand) {
        switch (message.type) {
          case WatchCommandType.watchFile:
            if (!fileSubscriptions.containsKey(message.path)) {
              try {
                // Use PollingFileWatcher as a fallback if needed, but standard should work
                // But for single files, FileWatcher is usually fine.
                final watcher = FileWatcher(message.path);
                fileSubscriptions[message.path] = watcher.events.listen((event) {
                  mainSendPort.send(WatchEventMessage(event.path, event.type));
                }, onError: (e) {
                  debugPrint('Watcher isolate file error: $e');
                });
              } catch (e) {
                debugPrint('Watcher isolate file setup error: $e');
              }
            }
            break;

          case WatchCommandType.unwatchFile:
            fileSubscriptions[message.path]?.cancel();
            fileSubscriptions.remove(message.path);
            break;

          case WatchCommandType.watchDirectory:
            dirSubscription?.cancel();
            try {
              final watcher = DirectoryWatcher(message.path);
              dirSubscription = watcher.events.listen((event) {
                // For directory watcher, we might just need to signal "something changed"
                // or pass specific events. Current app logic debounces anyway.
                mainSendPort.send(message.path); 
              }, onError: (e) {
                debugPrint('Watcher isolate dir error: $e');
              });
            } catch (e) {
              debugPrint('Watcher isolate dir setup error: $e');
            }
            break;

          case WatchCommandType.unwatchDirectory:
            dirSubscription?.cancel();
            dirSubscription = null;
            break;
        }
      }
    });
  }
}
