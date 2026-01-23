import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';
import 'package:window_manager/window_manager.dart';

class _PersistenceKeys {
  static const explorerRootPath = 'explorer_root_path';
  static const openFilePaths = 'open_file_paths';
  static const activeTabIndex = 'active_tab_index';
  static const fontSize = 'font_size';
  static const isRenderedView = 'is_rendered_view';
  static const sidebarWidth = 'sidebar_width';
  static const isExplorerVisible = 'is_explorer_visible';
  static const windowBounds = 'window_bounds';
  static const themeMode = 'theme_mode';
}

class AppState extends ChangeNotifier {
  // Persistence
  final SharedPreferences _prefs;

  // Window State
  Rect? _windowBounds;
  Rect? get windowBounds => _windowBounds;

  // Theme State
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // Tab Management
  final List<String> _openFilePaths = [];
  int _activeTabIndex = -1;
  final Map<String, String> _fileContents = {};
  final Map<String, double> _scrollOffsets = {};
  final Map<String, StreamSubscription<WatchEvent>> _fileWatchers = {};

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

  // Navigation Events
  final StreamController<({int lineNumber, String text})>
  _navigationController = StreamController.broadcast();
  Stream<({int lineNumber, String text})> get navigationStream =>
      _navigationController.stream;

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
    await appState._initialize();
    return appState;
  }

  AppState._internal(this._prefs) {
    _initChannel();
  }

  Future<void> _initialize() async {
    // 1. Load Critical UI State (Fast, sync/prefs)
    _loadCriticalState();

    // 2. Load Non-Critical State (Background)
    // We don't await this to let the UI show up immediately
    _loadNonCriticalState();
  }

  void _loadCriticalState() {
    // Load explorer root (validate it still exists)
    final savedRoot = _prefs.getString(_PersistenceKeys.explorerRootPath);
    if (savedRoot != null &&
        savedRoot.isNotEmpty &&
        Directory(savedRoot).existsSync()) {
      _explorerRootPath = savedRoot;
    } else {
      try {
        _explorerRootPath = Directory.current.path;
      } catch (e) {
        final envVars = Platform.environment;
        _explorerRootPath = envVars['HOME'] ?? envVars['USERPROFILE'];
      }
    }

    _fontSize = _prefs.getDouble(_PersistenceKeys.fontSize) ?? 14.0;
    _isRenderedView = _prefs.getBool(_PersistenceKeys.isRenderedView) ?? true;
    _sidebarWidth = _prefs.getDouble(_PersistenceKeys.sidebarWidth) ?? 250.0;
    _isExplorerVisible =
        _prefs.getBool(_PersistenceKeys.isExplorerVisible) ?? true;

    final themeIndex = _prefs.getInt(_PersistenceKeys.themeMode);
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    }

    final boundsList = _prefs.getStringList(_PersistenceKeys.windowBounds);
    if (boundsList != null && boundsList.length == 4) {
      try {
        _windowBounds = Rect.fromLTWH(
          double.parse(boundsList[0]),
          double.parse(boundsList[1]),
          double.parse(boundsList[2]),
          double.parse(boundsList[3]),
        );
      } catch (e) {
        debugPrint('Error loading window bounds: $e');
      }
    }
  }

  Future<void> _loadNonCriticalState() async {
    final savedPaths =
        _prefs.getStringList(_PersistenceKeys.openFilePaths) ?? [];
    final savedActiveIndex =
        _prefs.getInt(_PersistenceKeys.activeTabIndex) ?? -1;

    if (savedPaths.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      // Run file loading and decoding in a separate isolate.
      // Isolate.run uses Isolate.exit() internally to transfer the result
      // to the main thread without copying (zero-copy), eliminating UI jank.
      final loadedFiles = await Isolate.run(
        () => _readFilesFromDisk(savedPaths),
      );

      // Apply results to state on main thread
      for (final filePath in savedPaths) {
        if (loadedFiles.containsKey(filePath)) {
          _fileContents[filePath] = loadedFiles[filePath]!;
          _openFilePaths.add(filePath);
        }
      }

      // Update UI immediately so user sees content
      notifyListeners();

      // Only watch the currently active file to avoid startup bottlenecks
      if (_activeTabIndex >= 0 && _activeTabIndex < _openFilePaths.length) {
        final activePath = _openFilePaths[_activeTabIndex];
        _startWatching(activePath);
      }
    } catch (e) {
      debugPrint('Error loading files in background: $e');
    }

    // Restore active tab
    if (savedActiveIndex >= 0 && savedActiveIndex < _openFilePaths.length) {
      _activeTabIndex = savedActiveIndex;
    } else if (_openFilePaths.isNotEmpty) {
      _activeTabIndex = 0;
    }

    // Ensure active tab is watched if not already
    if (_activeTabIndex >= 0 && _activeTabIndex < _openFilePaths.length) {
      _startWatching(_openFilePaths[_activeTabIndex]);
    }

    notifyListeners();
  }

  /// Static method to run in the isolate. Reads multiple files in parallel.
  static Future<Map<String, String>> _readFilesFromDisk(
    List<String> paths,
  ) async {
    final Map<String, String> results = {};
    await Future.wait(
      paths.map((path) async {
        try {
          final file = File(path);
          if (await file.exists()) {
            results[path] = await file.readAsString();
          }
        } catch (e) {
          // Ignore individual file errors in the isolate
          // The main thread just won't receive content for this file
        }
      }),
    );
    return results;
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

  void setWindowBounds(Rect bounds) {
    _windowBounds = bounds;
    _prefs.setStringList(_PersistenceKeys.windowBounds, [
      bounds.left.toString(),
      bounds.top.toString(),
      bounds.width.toString(),
      bounds.height.toString(),
    ]);
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setInt(_PersistenceKeys.themeMode, mode.index);
    notifyListeners();
  }

  void setExplorerRevealCallback(Function(String path) callback) {
    _onRevealInExplorer = callback;
  }

  void _revealInExplorer(String path) {
    _onRevealInExplorer?.call(path);
  }

  void _startWatching(String path) {
    if (_fileWatchers.containsKey(path)) return;

    try {
      final watcher = FileWatcher(path);
      _fileWatchers[path] = watcher.events.listen(
        (event) {
          if (event.type == ChangeType.REMOVE) {
            // File was deleted or atomic save started
            // We'll try to re-establish watch after a short delay
            Future.delayed(const Duration(milliseconds: 200), () async {
              if (await File(path).exists()) {
                _stopWatching(path);
                _startWatching(path);
                _onFileModified(path);
              }
            });
          } else if (event.type == ChangeType.MODIFY) {
            _onFileModified(path);
          }
        },
        onError: (e) {
          debugPrint('Error watching file $path: $e');
        },
      );
    } catch (e) {
      debugPrint('Failed to watch file $path: $e');
    }
  }

  void _stopWatching(String path) {
    _fileWatchers[path]?.cancel();
    _fileWatchers.remove(path);
  }

  Future<void> _onFileModified(String path) async {
    // Debounce or just reload?
    // For now, simple reload.
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        // Only notify if content actually changed to avoid spurious rebuilds
        if (_fileContents[path] != content) {
          _fileContents[path] = content;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error reloading modified file $path: $e');
    }
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

        // Stop watching previous active file
        if (_activeTabIndex >= 0 && _activeTabIndex < _openFilePaths.length) {
          _stopWatching(_openFilePaths[_activeTabIndex]);
        }

        _openFilePaths.add(filePath);
        _activeTabIndex = _openFilePaths.length - 1;
        _revealInExplorer(filePath);

        // Start watching the new file
        _startWatching(filePath);

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
    _stopWatching(filePath);

    if (_openFilePaths.isEmpty) {
      _activeTabIndex = -1;
    } else {
      // If we closed the active tab, or a tab before it, adjust index
      if (_activeTabIndex >= index) {
        _activeTabIndex = (_activeTabIndex - 1).clamp(0, _openFilePaths.length - 1);
      }
      // Start watching the new active tab
      if (_activeTabIndex >= 0) {
        final newActivePath = _openFilePaths[_activeTabIndex];
        _startWatching(newActivePath);
        _onFileModified(newActivePath); // Refresh content
      }
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
      // Stop watching old tab (if any)
      if (_activeTabIndex >= 0 && _activeTabIndex < _openFilePaths.length) {
        _stopWatching(_openFilePaths[_activeTabIndex]);
      }

      _activeTabIndex = index;
      final newPath = _openFilePaths[index];

      // Start watching new tab
      _startWatching(newPath);

      // Refresh content immediately in case it changed while backgrounded
      _onFileModified(newPath);

      notifyListeners();
      _revealInExplorer(newPath);
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

  void scrollTo(int lineNumber, String text) {
    _navigationController.add((lineNumber: lineNumber, text: text));
  }

  @override
  void dispose() {
    _navigationController.close();
    for (final subscription in _fileWatchers.values) {
      subscription.cancel();
    }
    _fileWatchers.clear();
    explorerFocusNode.dispose();
    super.dispose();
  }
}
