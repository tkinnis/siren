import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart'
    show MarkdownEngine, MarkdownOutlineItem;
import 'package:provider/provider.dart';

import 'app_state.dart';

class OutlineView extends StatelessWidget {
  const OutlineView({super.key});

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

    final outlineItems = const MarkdownEngine().parse(content).outline;

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
          onTap: () => appState.scrollTo(math.max(0, item.line - 1), item.slug),
        );
      },
    );
  }
}

class _HoverableOutlineItem extends StatefulWidget {
  final MarkdownOutlineItem item;
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
