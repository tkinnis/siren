import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'theme.dart';

class FindInFileBar extends StatefulWidget {
  const FindInFileBar({super.key});

  @override
  State<FindInFileBar> createState() => _FindInFileBarState();
}

class _FindInFileBarState extends State<FindInFileBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _controller.text = appState.findInFileQuery;
    
    // Request focus on the input field when the bar is shown
    _focusNode.requestFocus();
    
    _controller.addListener(() {
      if (appState.findInFileQuery != _controller.text) {
        appState.setFindInFileQuery(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(FindInFileBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appState = Provider.of<AppState>(context, listen: false);
    if (_controller.text != appState.findInFileQuery) {
      _controller.text = appState.findInFileQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    final appState = Provider.of<AppState>(context, listen: false);
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        appState.hideFindInFile();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          appState.prevFindMatch();
        } else {
          appState.nextFindMatch();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sirenColors = Theme.of(context).extension<SirenColors>()!;

    final matchesCount = appState.findInFileMatchOffsets.length;
    final activeIndex = appState.findInFileActiveMatchIndex;
    final countText = matchesCount > 0
        ? '${activeIndex + 1} of $matchesCount'
        : 'No results';

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _onKey,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          border: Border(
            bottom: BorderSide(
              color: sirenColors.borderColor ?? Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 16,
              color: sirenColors.iconColor?.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Find in file...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) {
                  // Handled by KeyboardListener or standard Enter
                  appState.nextFindMatch();
                },
              ),
            ),
            if (_controller.text.isNotEmpty) ...[
              Text(
                countText,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              _IconButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Previous Match (Shift+Enter)',
                onPressed: appState.prevFindMatch,
              ),
              _IconButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Next Match (Enter)',
                onPressed: appState.nextFindMatch,
              ),
            ],
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.close,
              tooltip: 'Close (Esc)',
              onPressed: appState.hideFindInFile,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final sirenColors = Theme.of(context).extension<SirenColors>()!;
    final baseColor = sirenColors.iconColor ?? Theme.of(context).iconTheme.color!;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            decoration: BoxDecoration(
              color: _isHovering
                  ? baseColor.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovering ? baseColor : baseColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
