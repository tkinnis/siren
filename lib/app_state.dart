import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class _PersistenceKeys {
  static const explorerRootPath = 'explorer_root_path';
  static const openFilePaths = 'open_file_paths';
  static const activeTabIndex = 'active_tab_index';
  static const fontSize = 'font_size';
  static const isRenderedView = 'is_rendered_view';
  static const sidebarWidth = 'sidebar_width';
  static const isExplorerVisible = 'is_explorer_visible';
}

class AppState extends ChangeNotifier {
  // Persistence
  final SharedPreferences _prefs;

  // Tab Management
  final List<String> _openFilePaths = [];
  int _activeTabIndex = -1;
  final Map<String, String> _fileContents = {};
  final Map<String, double> _scrollOffsets = {};

  // File Explorer
  String? _explorerRootPath;

  // View Settings
  bool _isRenderedView = true;
  double _fontSize = 14.0;
  bool _isLoading = false;

  // Sidebar State
  double _sidebarWidth = 250.0;
  bool _isExplorerVisible = true;

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
  double get sidebarWidth => _sidebarWidth;
  bool get isExplorerVisible => _isExplorerVisible;

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

  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final appState = AppState._internal(prefs);
    await appState._loadPersistedState();
    return appState;
  }

  AppState._internal(this._prefs) {
    _initChannel();
  }

  Future<void> _loadPersistedState() async {
    // Load explorer root (validate it still exists)
    final savedRoot = _prefs.getString(_PersistenceKeys.explorerRootPath);
    if (savedRoot != null &&
        savedRoot.isNotEmpty &&
        Directory(savedRoot).existsSync()) {
      _explorerRootPath = savedRoot;
    } else {
      // Fallback to current directory or home
      try {
        _explorerRootPath = Directory.current.path;
      } catch (e) {
        final envVars = Platform.environment;
        _explorerRootPath = envVars['HOME'] ?? envVars['USERPROFILE'];
      }
    }

    // Load view preferences
    _fontSize = _prefs.getDouble(_PersistenceKeys.fontSize) ?? 14.0;
    _isRenderedView = _prefs.getBool(_PersistenceKeys.isRenderedView) ?? true;
    _sidebarWidth = _prefs.getDouble(_PersistenceKeys.sidebarWidth) ?? 250.0;
    _isExplorerVisible =
        _prefs.getBool(_PersistenceKeys.isExplorerVisible) ?? true;

    // Load open files (validate they still exist)
    final savedPaths =
        _prefs.getStringList(_PersistenceKeys.openFilePaths) ?? [];
    for (final filePath in savedPaths) {
      if (File(filePath).existsSync()) {
        try {
          final content = await File(filePath).readAsString();
          _fileContents[filePath] = content;
          _openFilePaths.add(filePath);
        } catch (e) {
          debugPrint('Error loading persisted file: $e');
        }
      }
    }

    // Restore active tab
    final savedIndex = _prefs.getInt(_PersistenceKeys.activeTabIndex) ?? -1;
    if (savedIndex >= 0 && savedIndex < _openFilePaths.length) {
      _activeTabIndex = savedIndex;
    } else if (_openFilePaths.isNotEmpty) {
      _activeTabIndex = 0;
    }

    notifyListeners();
  }

  Future<void> _persistState() async {
    await _prefs.setString(
      _PersistenceKeys.explorerRootPath,
      _explorerRootPath ?? '',
    );
    await _prefs.setStringList(_PersistenceKeys.openFilePaths, _openFilePaths);
    await _prefs.setInt(_PersistenceKeys.activeTabIndex, _activeTabIndex);
    await _prefs.setDouble(_PersistenceKeys.fontSize, _fontSize);
    await _prefs.setBool(_PersistenceKeys.isRenderedView, _isRenderedView);
    await _prefs.setDouble(_PersistenceKeys.sidebarWidth, _sidebarWidth);
    await _prefs.setBool(
      _PersistenceKeys.isExplorerVisible,
      _isExplorerVisible,
    );
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
        _persistState();
      }
    } catch (e) {
      debugPrint('Error opening directory: $e');
    }
  }

  Future<void> openFileAndSetDirectory(String filePath) async {
    await openFile(filePath);
    _explorerRootPath = path.dirname(filePath);
    notifyListeners();
    _persistState();
  }

  Future<void> openFile(String filePath) async {
    // If already open, just switch to it
    final existingIndex = _openFilePaths.indexOf(filePath);
    if (existingIndex != -1) {
      _activeTabIndex = existingIndex;
      notifyListeners();
      _revealInExplorer(filePath);
      _persistState();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        _fileContents[filePath] = content;
        _openFilePaths.add(filePath);
        _activeTabIndex = _openFilePaths.length - 1;
        _revealInExplorer(filePath);
        _persistState();
      }
    } catch (e) {
      debugPrint('Error reading file: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void closeFile(String filePath) {
    final index = _openFilePaths.indexOf(filePath);
    if (index == -1) return;

    _openFilePaths.removeAt(index);
    _fileContents.remove(filePath);
    _scrollOffsets.remove(filePath);

    if (_openFilePaths.isEmpty) {
      _activeTabIndex = -1;
    } else if (_activeTabIndex >= index) {
      // If we closed the active tab or a tab before it, adjust index
      _activeTabIndex = (_activeTabIndex - 1).clamp(
        0,
        _openFilePaths.length - 1,
      );
    }

    notifyListeners();
    _persistState();
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
      _persistState();
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
    _persistState();
  }

  void increaseFontSize() {
    _fontSize = (_fontSize + 2).clamp(8.0, 48.0);
    notifyListeners();
    _persistState();
  }

  void decreaseFontSize() {
    _fontSize = (_fontSize - 2).clamp(8.0, 48.0);
    notifyListeners();
    _persistState();
  }

  void setSidebarWidth(double width) {
    _sidebarWidth = width.clamp(150.0, 500.0);
    notifyListeners();
  }

  void saveSidebarWidth() {
    _persistState();
  }

  void toggleExplorerVisibility() {
    _isExplorerVisible = !_isExplorerVisible;
    notifyListeners();
    _persistState();
  }

  void setContent(String content) {
    final path = currentFilePath;
    if (path != null) {
      _fileContents[path] = content;
      notifyListeners();
    }
  }

  double getScrollOffset(String path) => _scrollOffsets[path] ?? 0.0;

  void setScrollOffset(String path, double offset) {
    _scrollOffsets[path] = offset;
  }
}
