import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

class AppState extends ChangeNotifier {
  // Tab Management
  final List<String> _openFilePaths = [];
  int _activeTabIndex = -1;
  final Map<String, String> _fileContents = {};

  // File Explorer
  String? _explorerRootPath;

  // View Settings
  bool _isRenderedView = true;
  double _fontSize = 14.0;
  bool _isLoading = false;
  
  // Focus & Navigation
  final FocusNode explorerFocusNode = FocusNode();
  Function(String path)? _onRevealInExplorer;

  // Getters
  List<String> get openFilePaths => List.unmodifiable(_openFilePaths);
  int get activeTabIndex => _activeTabIndex;
  String? get explorerRootPath => _explorerRootPath;
  bool get isRenderedView => _isRenderedView;
  double get fontSize => _fontSize;
  bool get isLoading => _isLoading;

  String? get currentFilePath {
    if (_activeTabIndex >= 0 && _activeTabIndex < _openFilePaths.length) {
      return _openFilePaths[_activeTabIndex];
    }
    return null;
  }

  String get currentContent {
    final path = currentFilePath;
    if (path != null) {
      return _fileContents[path] ?? '';
    }
    return '';
  }

  static const MethodChannel _channel = MethodChannel(
    'com.example.siren/files',
  );

  AppState() {
    _initChannel();
    // Default to current directory now that sandbox is disabled
    try {
      _explorerRootPath = Directory.current.path;
    } catch (e) {
      debugPrint('Could not get current directory: $e');
      // Fallback to home if possible
      final envVars = Platform.environment;
      _explorerRootPath = envVars['HOME'] ?? envVars['USERPROFILE'];
    }
  }

  @override
  void dispose() {
    explorerFocusNode.dispose();
    super.dispose();
  }

  void setExplorerRevealCallback(Function(String path) callback) {
    _onRevealInExplorer = callback;
  }

  void _revealInExplorer(String path) {
    _onRevealInExplorer?.call(path);
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

  Future<void> openDirectory() async {
    try {
      final String? directoryPath = await getDirectoryPath();
      if (directoryPath != null) {
        _explorerRootPath = directoryPath;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error opening directory: $e');
    }
  }

  Future<void> openFileAndSetDirectory(String filePath) async {
    await openFile(filePath);
    _explorerRootPath = path.dirname(filePath);
    notifyListeners();
  }

  Future<void> openFile(String path) async {
    // If already open, just switch to it
    final existingIndex = _openFilePaths.indexOf(path);
    if (existingIndex != -1) {
      _activeTabIndex = existingIndex;
      notifyListeners();
      _revealInExplorer(path);
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        _fileContents[path] = content;
        _openFilePaths.add(path);
        _activeTabIndex = _openFilePaths.length - 1;
        _revealInExplorer(path);
      }
    } catch (e) {
      debugPrint('Error reading file: $e');
      // TODO: Handle error state
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void closeFile(String path) {
    final index = _openFilePaths.indexOf(path);
    if (index == -1) return;

    _openFilePaths.removeAt(index);
    _fileContents.remove(path);

    if (_openFilePaths.isEmpty) {
      _activeTabIndex = -1;
    } else if (_activeTabIndex >= index) {
      // If we closed the active tab or a tab before it, adjust index
      _activeTabIndex = (_activeTabIndex - 1).clamp(0, _openFilePaths.length - 1);
    }
    
    notifyListeners();
  }

  void closeCurrentFile() {
    final path = currentFilePath;
    if (path != null) {
      closeFile(path);
    }
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < _openFilePaths.length) {
      _activeTabIndex = index;
      notifyListeners();
      _revealInExplorer(_openFilePaths[index]);
    }
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String item = _openFilePaths.removeAt(oldIndex);
    _openFilePaths.insert(newIndex, item);

    // Update active tab index to follow the moved item
    if (_activeTabIndex == oldIndex) {
      _activeTabIndex = newIndex;
    } else if (_activeTabIndex > oldIndex && _activeTabIndex <= newIndex) {
      _activeTabIndex--;
    } else if (_activeTabIndex < oldIndex && _activeTabIndex >= newIndex) {
      _activeTabIndex++;
    }

    notifyListeners();
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
    final path = currentFilePath;
    if (path != null) {
      _fileContents[path] = content;
      notifyListeners();
    }
  }
}
