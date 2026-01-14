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
        return InkWell(
          onTap: () {
            appState.scrollTo(item.lineNumber, item.text);
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 12.0 + (item.level - 1) * 16.0,
              top: 8,
              bottom: 8,
              right: 12,
            ),
            child: Text(
              item.text,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
