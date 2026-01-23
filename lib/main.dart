import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app_state.dart';
import 'home_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Start loading state but don't block the first frame if we can help it
  // However, since AppState.create is currently async and needed for MainApp,
  // we'll keep it here but we've optimized its internal file loading.
  final appState = await AppState.create();

  runApp(MainApp(appState: appState));

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    minimumSize: Size(400, 300),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  // Restore saved bounds if available
  if (appState.windowBounds != null) {
    windowOptions = WindowOptions(
      size: appState.windowBounds!.size,
      minimumSize: const Size(400, 300),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
  }

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (appState.windowBounds != null) {
      await windowManager.setBounds(appState.windowBounds!);
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

class MainApp extends StatefulWidget {
  final AppState appState;

  const MainApp({super.key, required this.appState});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMove() {
    _saveWindowBounds();
  }

  @override
  void onWindowResize() {
    _saveWindowBounds();
  }

  Future<void> _saveWindowBounds() async {
    final bounds = await windowManager.getBounds();
    widget.appState.setWindowBounds(bounds);
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
