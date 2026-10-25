import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'app_state.dart';

import 'theme.dart';

class EditorTabs extends StatefulWidget {
  const EditorTabs({super.key});

  @override
  State<EditorTabs> createState() => _EditorTabsState();
}

class _EditorTabsState extends State<EditorTabs> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveTab(int activeIndex) {
    if (!_scrollController.hasClients || activeIndex < 0) return;

    final tabWidth = 150.0;
    final targetOffset = activeIndex * tabWidth;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    final viewportWidth = _scrollController.position.viewportDimension;

    final scrollPosition = targetOffset - (viewportWidth / 2) + (tabWidth / 2);

    _scrollController.animateTo(
      scrollPosition.clamp(minScroll, maxScroll),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _revealInSystem(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path.dirname(filePath)]);
      }
    } catch (e) {
      debugPrint('Failed to reveal file: $e');
    }
  }

  void _showTabContextMenu(
    BuildContext context,
    Offset position,
    String filePath,
    AppState appState,
  ) {
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    late OverlayEntry overlayEntry;

    const double menuWidth = 210.0;
    const double menuHeight = 200.0;

    double dx = position.dx;
    double dy = position.dy;

    if (dx + menuWidth > screenSize.width) {
      dx = screenSize.width - menuWidth - 8;
    }
    if (dy + menuHeight > screenSize.height) {
      dy = screenSize.height - menuHeight - 8;
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => overlayEntry.remove(),
              onSecondaryTapDown: (_) => overlayEntry.remove(),
            ),
          ),
          Positioned(
            left: dx,
            top: dy,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: menuWidth,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline
                        .withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TabMenuItem(
                      label: 'Close',
                      onTap: () {
                        overlayEntry.remove();
                        appState.closeFile(filePath);
                      },
                    ),
                    _TabMenuItem(
                      label: 'Close Others',
                      onTap: () {
                        overlayEntry.remove();
                        appState.closeOtherFilesFor(filePath);
                      },
                    ),
                    _TabMenuItem(
                      label: 'Close All',
                      onTap: () {
                        overlayEntry.remove();
                        appState.closeAllFiles();
                      },
                    ),
                    const Divider(height: 1, thickness: 1),
                    _TabMenuItem(
                      label: Platform.isMacOS
                          ? 'Show in Finder'
                          : 'Show in File Manager',
                      onTap: () {
                        overlayEntry.remove();
                        _revealInSystem(filePath);
                      },
                    ),
                    _TabMenuItem(
                      label: 'Copy Path',
                      onTap: () {
                        overlayEntry.remove();
                        Clipboard.setData(ClipboardData(text: filePath));
                      },
                    ),
                    if (appState.explorerRootPath != null)
                      _TabMenuItem(
                        label: 'Copy Relative Path',
                        onTap: () {
                          overlayEntry.remove();
                          Clipboard.setData(
                            ClipboardData(
                              text: path.relative(
                                filePath,
                                from: appState.explorerRootPath!,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tabs = appState.openFilePaths;
    final activeIndex = appState.activeTabIndex;

    if (activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveTab(activeIndex);
      });
    }

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final sirenColors = Theme.of(context).extension<SirenColors>()!;

    return Container(
      height: 36,
      width: double.infinity,
      decoration: BoxDecoration(
        color: sirenColors.tabBg,
        border: Border(
          bottom: BorderSide(
            color: sirenColors.borderColor ?? Colors.transparent,
          ),
        ),
      ),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        scrollController: _scrollController,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(left: 4),
        itemCount: tabs.length,
        onReorderItem: (oldIndex, newIndex) {
          appState.reorderTabsDirect(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            child: child, // Provide feedback style if needed
          );
        },
        itemBuilder: (context, index) {
          final filePath = tabs[index];
          final fileName = path.basename(filePath);
          final isActive = index == activeIndex;

          return ReorderableDragStartListener(
            key: ValueKey(filePath),
            index: index,
            child: Semantics(
              button: true,
              selected: isActive,
              label: '$fileName tab${isActive ? ", active" : ""}',
              child: GestureDetector(
                onTap: () => appState.setActiveTab(index),
                onSecondaryTapUp: (details) => _showTabContextMenu(
                  context,
                  details.globalPosition,
                  filePath,
                  appState,
                ),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 100,
                    maxWidth: 200,
                  ),
                  margin: const EdgeInsets.only(right: 1, top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? sirenColors.activeTabBg
                        : sirenColors.tabBg,
                    border: isActive
                        ? Border(
                            top: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description,
                        size: 14,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : sirenColors.iconColor,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive
                                ? Theme.of(context).textTheme.bodyMedium?.color
                                : sirenColors.iconColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _TabCloseButton(
                        onPressed: () => appState.closeFile(filePath),
                        isActive: isActive,
                        fileName: fileName,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabMenuItem extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TabMenuItem({required this.label, required this.onTap});

  @override
  State<_TabMenuItem> createState() => _TabMenuItemState();
}

class _TabMenuItemState extends State<_TabMenuItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _isHovering
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(widget.label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isActive;
  final String fileName;

  const _TabCloseButton({
    required this.onPressed,
    required this.isActive,
    required this.fileName,
  });

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final sirenColors = Theme.of(context).extension<SirenColors>()!;

    return Semantics(
      button: true,
      label: 'Close ${widget.fileName}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Tooltip(
          message: 'Close tab',
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              decoration: BoxDecoration(
                color: _isHovering
                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: _isHovering
                    ? Theme.of(context).colorScheme.error
                    : (widget.isActive
                          ? sirenColors.iconColor
                          : sirenColors.iconColor?.withValues(alpha: 0.7)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
