import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class AppState extends ChangeNotifier {
  String? _currentFilePath;
  String _currentContent = '';
  bool _isRenderedView = true;
  double _fontSize = 14.0;
  bool _isLoading = false;

  String? get currentFilePath => _currentFilePath;
  String get currentContent => _currentContent;
  bool get isRenderedView => _isRenderedView;
  double get fontSize => _fontSize;
  bool get isLoading => _isLoading;

  static const MethodChannel _channel = MethodChannel(
    'com.example.siren/files',
  );

  AppState() {
    _initChannel();
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final String path = call.arguments as String;
        await openFile(path);
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  Future<void> openFile(String path) async {
    _isLoading = true;
    notifyListeners();

    try {
      final file = File(path);
      if (await file.exists()) {
        _currentContent = await file.readAsString();
        _currentFilePath = path;
        await windowManager.setTitle(_currentFilePath!.split('/').last);
      }
    } catch (e) {
      debugPrint('Error reading file: $e');
      // TODO: Handle error state
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleViewMode() {
    _isRenderedView = !_isRenderedView;
    notifyListeners();
  }

  void increaseFontSize() {
    _fontSize = (_fontSize + 2).clamp(8.0, 48.0);
    notifyListeners();
  }

  void decreaseFontSize() {
    _fontSize = (_fontSize - 2).clamp(8.0, 48.0);
    notifyListeners();
  }

  void setContent(String content) {
    _currentContent = content;
    // content changed, maybe unsaved? For read-only we might not need this unless we reload.
    notifyListeners();
  }
}
