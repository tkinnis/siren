import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'app_state.dart';

class EditorTabs extends StatefulWidget {
  const EditorTabs({super.key});

  @override
  State<EditorTabs> createState() => _EditorTabsState();
}

class _EditorTabsState extends State<EditorTabs> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tabs = appState.openFilePaths;
    final activeIndex = appState.activeTabIndex;

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 36,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.black : Colors.grey.shade300,
          ),
        ),
      ),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        scrollController: _scrollController,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(left: 4),
        itemCount: tabs.length,
        onReorder: (oldIndex, newIndex) {
          appState.reorderTabs(oldIndex, newIndex);
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
            child: GestureDetector(
              onTap: () => appState.setActiveTab(index),
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 100,
                  maxWidth: 200,
                ),
                margin: const EdgeInsets.only(right: 1, top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? const Color(0xFF2D2D2D) : Colors.white)
                      : (isDark ? const Color(0xFF252526) : const Color(0xFFECECEC)),
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
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        fileName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _TabCloseButton(
                      onPressed: () => appState.closeFile(filePath),
                      isActive: isActive,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isActive;

  const _TabCloseButton({required this.onPressed, required this.isActive});

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _isHovering
                ? Theme.of(context).colorScheme.error.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.close,
            size: 14,
            color: _isHovering
                ? Theme.of(context).colorScheme.error
                : (widget.isActive ? null : Colors.grey),
          ),
        ),
      ),
    );
  }
}
