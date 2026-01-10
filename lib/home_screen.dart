import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app_state.dart';
import 'editor_tabs.dart';
import 'file_explorer.dart';
import 'raw_view.dart';
import 'rendered_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _sidebarWidth = 250.0;
  bool _isResizing = false;

  void _handleResize(DragUpdateDetails details) {
    setState(() {
      _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(150.0, 500.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Siren',
          menus: [
            if (Platform.isMacOS)
              PlatformMenuItemGroup(
                members: [
                  PlatformMenuItem(
                    label: 'About Siren',
                    onSelected: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Siren',
                        applicationVersion: '0.1.0',
                      );
                    },
                  ),
                ],
              ),
            if (Platform.isMacOS)
              PlatformMenuItemGroup(
                members: [
                  PlatformMenuItem(
                    label: 'Quit Siren',
                    shortcut:
                        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
                    onSelected: () {
                      exit(0);
                    },
                  ),
                ],
              ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'Open...',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: () async {
                 const XTypeGroup typeGroup = XTypeGroup(
                  label: 'Markdown',
                  extensions: <String>['md', 'markdown'],
                );
                final XFile? file = await openFile(
                  acceptedTypeGroups: <XTypeGroup>[typeGroup],
                );
                if (file != null && mounted) {
                  // Open file AND set explorer root to parent
                  context.read<AppState>().openFileAndSetDirectory(file.path);
                }
              },
            ),
             PlatformMenuItem(
              label: 'Open Folder...',
              onSelected: () async {
                 if (mounted) {
                  context.read<AppState>().openDirectory();
                 }
              },
            ),
            PlatformMenuItem(
              label: 'Close Tab',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
              onSelected: () {
                 if (mounted) {
                  context.read<AppState>().closeCurrentFile();
                 }
              },
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Toggle Preview',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true),
              onSelected: () {
                if (mounted) {
                  context.read<AppState>().toggleViewMode();
                }
              },
            ),
             PlatformMenuItem(
              label: 'Zoom In',
              shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
              onSelected: () {
                if (mounted) {
                  context.read<AppState>().increaseFontSize();
                }
              },
            ),
            PlatformMenuItem(
              label: 'Zoom Out',
              shortcut: const SingleActivator(LogicalKeyboardKey.minus, meta: true),
              onSelected: () {
                if (mounted) {
                  context.read<AppState>().decreaseFontSize();
                }
              },
            ),
          ],
        ),
      ],
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.equal, meta: true): () {
            appState.increaseFontSize();
          },
          const SingleActivator(LogicalKeyboardKey.minus, meta: true): () {
            appState.decreaseFontSize();
          },
           const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            appState.closeCurrentFile();
          },
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () async {
             const XTypeGroup typeGroup = XTypeGroup(
                label: 'Markdown',
                extensions: <String>['md', 'markdown'],
              );
              final XFile? file = await openFile(
                acceptedTypeGroups: <XTypeGroup>[typeGroup],
              );
              if (file != null && mounted) {
                appState.openFileAndSetDirectory(file.path);
              }
          },
        },
        child: Focus(
          autofocus: true,
          child: DropTarget(
            onDragDone: (detail) {
              if (detail.files.isNotEmpty) {
                for (final file in detail.files) {
                  if (file.path.endsWith('.md') ||
                      file.path.endsWith('.markdown')) {
                    appState.openFile(file.path);
                  }
                }
              }
            },
            child: Scaffold(
              body: Column(
                children: [
                  _buildToolbar(context, appState),
                  Expanded(
                    child: Row(
                      children: [
                        // File Explorer Sidebar
                        SizedBox(
                          width: _sidebarWidth,
                          child: const FileExplorer(),
                        ),
                        // Resizer
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            onHorizontalDragUpdate: _handleResize,
                            onHorizontalDragStart: (_) => setState(() => _isResizing = true),
                            onHorizontalDragEnd: (_) => setState(() => _isResizing = false),
                            child: Container(
                              width: 5,
                              color: _isResizing 
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.5) 
                                : Colors.transparent,
                                child: const VerticalDivider(width: 1, thickness: 1),
                            ),
                          ),
                        ),
                        // Main Editor Area
                        Expanded(
                          child: Column(
                            children: [
                              const EditorTabs(),
                              Expanded(
                                child: appState.isLoading
                                    ? const Center(child: CircularProgressIndicator())
                                    : appState.activeTabIndex == -1
                                        ? _buildEmptyState(context)
                                        : appState.isRenderedView
                                            ? const RenderedView()
                                            : const MarkdownRawView(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282828) : const Color(0xFFF5F5F5),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.black26 : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background and Drag Area
          Positioned.fill(
            child: DragToMoveArea(child: Container(color: Colors.transparent)),
          ),
          // Centered Breadcrumbs (replacing simple title)
          Positioned(
            left: 80, // Space for traffic lights
            right: 180, // Space for action buttons
            child: _Breadcrumbs(filePath: appState.currentFilePath),
          ),
          // Action Buttons on the Right
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                 _DesktopIconButton(
                  icon: Icons.folder_open,
                  tooltip: 'Open File',
                  onPressed: () async {
                    const XTypeGroup typeGroup = XTypeGroup(
                      label: 'Markdown',
                      extensions: <String>['md', 'markdown'],
                    );
                    final XFile? file = await openFile(
                      acceptedTypeGroups: <XTypeGroup>[typeGroup],
                    );
                    if (file != null && mounted) {
                      appState.openFileAndSetDirectory(file.path);
                    }
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 20,
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                const SizedBox(width: 8),
                _DesktopIconButton(
                  icon: appState.isRenderedView ? Icons.code : Icons.visibility,
                  tooltip: appState.isRenderedView
                      ? 'Show Source'
                      : 'Show Preview',
                  onPressed: appState.toggleViewMode,
                ),
                const SizedBox(width: 8),
                _DesktopIconButton(
                  icon: Icons.remove,
                  tooltip: 'Decrease Font Size',
                  onPressed: appState.decreaseFontSize,
                ),
                _DesktopIconButton(
                  icon: Icons.add,
                  tooltip: 'Increase Font Size',
                  onPressed: appState.increaseFontSize,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No file open',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).disabledColor,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              const XTypeGroup typeGroup = XTypeGroup(
                label: 'Markdown',
                extensions: <String>['md', 'markdown'],
              );
              final XFile? file = await openFile(
                acceptedTypeGroups: <XTypeGroup>[typeGroup],
              );
              if (file != null) {
                if(context.mounted) {
                   Provider.of<AppState>(
                    context,
                    listen: false,
                  ).openFileAndSetDirectory(file.path);
                }
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Markdown File'),
          ),
        ],
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  final String? filePath;

  const _Breadcrumbs({this.filePath});

  @override
  Widget build(BuildContext context) {
    if (filePath == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parts = path.split(filePath!);
    // Show last 3 parts if too long, or all if short
    final displayParts = parts.length > 4 ? ['...', ...parts.sublist(parts.length - 3)] : parts;

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
             for (int i = 0; i < displayParts.length; i++) ...[
               if (i > 0)
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 4),
                   child: Icon(
                     Icons.chevron_right,
                     size: 14,
                     color: isDark ? Colors.white30 : Colors.black26,
                   ),
                 ),
               Text(
                 displayParts[i],
                 style: TextStyle(
                   fontSize: 12,
                   color: i == displayParts.length - 1
                       ? (isDark ? Colors.white : Colors.black87)
                       : (isDark ? Colors.white54 : Colors.black54),
                   fontWeight: i == displayParts.length - 1
                       ? FontWeight.w600
                       : FontWeight.normal,
                 ),
               ),
             ],
          ],
        ),
      ),
    );
  }
}

class _DesktopIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _DesktopIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_DesktopIconButton> createState() => _DesktopIconButtonState();
}

class _DesktopIconButtonState extends State<_DesktopIconButton> {
  bool _isHovering = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final pressedColor = isDark
        ? Colors.white24
        : Colors.black.withOpacity(0.1);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onPressed,
          child: Container(
            decoration: BoxDecoration(
              color: _isPressed
                  ? pressedColor
                  : _isHovering
                  ? hoverColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(6.0),
            child: Icon(
              widget.icon,
              size: 18,
              color: _isPressed || _isHovering ? color : color.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }
}