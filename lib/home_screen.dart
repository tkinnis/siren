import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app_state.dart';
import 'raw_view.dart';
import 'rendered_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () {
          appState.increaseFontSize();
        },
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () {
          appState.decreaseFontSize();
        },
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragDone: (detail) {
            if (detail.files.isNotEmpty) {
              final file = detail.files.first;
              if (file.path.endsWith('.md') ||
                  file.path.endsWith('.markdown')) {
                appState.openFile(file.path);
              }
            }
          },
          child: Scaffold(
            body: Column(
              children: [
                _buildToolbar(context, appState),
                Expanded(
                  child: appState.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : appState.currentContent.isEmpty
                      ? _buildEmptyState(context)
                      : appState.isRenderedView
                      ? const RenderedView()
                      : const MarkdownRawView(),
                ),
              ],
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
          // Centered Title
          Positioned(
            left: 80, // Space for traffic lights
            right: 80, // Space for action buttons (approx)
            child: Center(
              child: appState.currentFilePath != null
                  ? Text(
                      appState.currentFilePath!.split('/').last,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
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
                    if (file != null) {
                      appState.openFile(file.path);
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
                Provider.of<AppState>(
                  context,
                  listen: false,
                ).openFile(file.path);
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
