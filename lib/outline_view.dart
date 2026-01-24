import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';

class OutlineItem {
  final String text;
  final int level;
  final int lineNumber;

  OutlineItem({
    required this.text,
    required this.level,
    required this.lineNumber,
  });
}

class OutlineView extends StatelessWidget {
  const OutlineView({super.key});

  List<OutlineItem> _parseOutline(String content) {
    final List<OutlineItem> items = [];
    final lines = content.split('\n');
    final regex = RegExp(r'^(#{1,6})\s+(.*)');

    for (int i = 0; i < lines.length; i++) {
      final match = regex.firstMatch(lines[i]);
      if (match != null) {
        items.add(
          OutlineItem(
            text: match.group(2)!.trim(),
            level: match.group(1)!.length,
            lineNumber: i,
          ),
        );
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final content = appState.currentContent;

    if (content.isEmpty) {
      return Center(
        child: Text(
          'No content',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final outlineItems = _parseOutline(content);

    if (outlineItems.isEmpty) {
      return Center(
        child: Text(
          'No headings found',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: outlineItems.length,
      itemBuilder: (context, index) {
        final item = outlineItems[index];
        return _HoverableOutlineItem(
          item: item,
          onTap: () => appState.scrollTo(item.lineNumber, item.text),
        );
      },
    );
  }
}

class _HoverableOutlineItem extends StatefulWidget {
  final OutlineItem item;
  final VoidCallback onTap;

  const _HoverableOutlineItem({required this.item, required this.onTap});

  @override
  State<_HoverableOutlineItem> createState() => _HoverableOutlineItemState();
}

class _HoverableOutlineItemState extends State<_HoverableOutlineItem> {
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
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)
              : null,
          padding: EdgeInsets.only(
            left: 12.0 + (widget.item.level - 1) * 16.0,
            top: 8,
            bottom: 8,
            right: 12,
          ),
          child: Text(
            widget.item.text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
