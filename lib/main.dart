import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'home_screen.dart';
import 'theme.dart';

Window? _currentNativeWindow() {
  try {
    return WindowManager.instance.getCurrent();
  } on ArgumentError {
    return null;
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start loading state but don't block the first frame if we can help it
  // However, since AppState.create is currently async and needed for MainApp,
  // we'll keep it here but we've optimized its internal file loading.
  final appState = await AppState.create();

  for (final arg in args.where((a) => !a.startsWith('--'))) {
    final candidate = p.canonicalize(arg);
    if (File(candidate).existsSync()) {
      await appState.openFileAndSetDirectory(candidate);
    }
  }

  final isStandardWindow = args.contains('--standard-window');

  runApp(MainApp(appState: appState));

  final window = _currentNativeWindow();
  if (window != null) {
    window.titleBarStyle = TitleBarStyle.hidden;
    window.isWindowControlButtonsVisible = true;
    window.minimumSize = const Size(400, 300).toNative();
    window.backgroundColor = Colors.transparent.toNative();
    window.isVisibleInTaskbar = true;

    // Restore saved bounds if available (unless forced standard window)
    if (isStandardWindow || appState.windowBounds == null) {
      window.setSize(const Size(1200, 800).toNative(), false);
      window.center();
    } else {
      window.bounds = appState.windowBounds!.toNative();
    }

    if (window.isMinimized) {
      window.restore();
    }
    window.show();
    window.focus();
  }
}

class MainApp extends StatefulWidget {
  final AppState appState;

  const MainApp({super.key, required this.appState});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Window? _window;
  ListenerId? _windowListenerId;

  @override
  void initState() {
    super.initState();
    final window = _currentNativeWindow();
    if (window != null) {
      _window = window;
      _windowListenerId = window.addListener(_handleWindowEvent);
    }
  }

  @override
  void dispose() {
    final listenerId = _windowListenerId;
    if (listenerId != null) {
      _window?.removeListener(listenerId);
    }
    super.dispose();
  }

  void _handleWindowEvent(WindowEvent event) {
    if (event is WindowMovedEvent || event is WindowResizedEvent) {
      _saveWindowBounds();
    }
  }

  void _saveWindowBounds() {
    final window = _window ?? _currentNativeWindow();
    if (window == null) return;
    widget.appState.setWindowBounds(window.bounds.toRect());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'Siren',
            debugShowCheckedModeBanner: false,
            theme: SirenTheme.light,
            darkTheme: SirenTheme.dark,
            themeMode: appState.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
