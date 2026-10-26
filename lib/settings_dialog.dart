import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();
  List<String> _includes = [];
  List<String> _excludes = [];
  String? _errorText;

  bool _includePathMatch = false; // false = Name, true = Path
  bool _excludePathMatch = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _includes = List.from(appState.includePatterns);
    _excludes = List.from(appState.excludePatterns);

    _includeController.addListener(_clearError);
    _excludeController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorText != null) {
      setState(() {
        _errorText = null;
      });
    }
  }

  @override
  void dispose() {
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  void _addInclude() {
    final text = _includeController.text.trim();
    if (text.isEmpty) return;

    final pattern = _includePathMatch ? 'p:$text' : 'n:$text';

    if (_includes.contains(pattern)) {
      _includeController.clear();
      return;
    }

    try {
      RegExp(text); // Validate regex (without prefix)
      setState(() {
        _includes.add(pattern);
        _includeController.clear();
        _errorText = null;
      });
    } catch (e) {
      setState(() => _errorText = 'Invalid Regex: ${e.toString()}');
    }
  }

  void _addExclude() {
    final text = _excludeController.text.trim();
    if (text.isEmpty) return;

    final pattern = _excludePathMatch ? 'p:$text' : 'n:$text';

    if (_excludes.contains(pattern)) {
      _excludeController.clear();
      return;
    }

    try {
      RegExp(text); // Validate regex
      setState(() {
        _excludes.add(pattern);
        _excludeController.clear();
        _errorText = null;
      });
    } catch (e) {
      setState(() => _errorText = 'Invalid Regex: ${e.toString()}');
    }
  }

  void _removeInclude(String item) {
    setState(() {
      _includes.remove(item);
    });
  }

  void _removeExclude(String item) {
    setState(() {
      _excludes.remove(item);
    });
  }

  void _save() {
    // Auto-add pending text if not empty
    if (_includeController.text.trim().isNotEmpty) {
      _addInclude();
      if (_errorText != null) return; // Stop if pending text was invalid
    }
    if (_excludeController.text.trim().isNotEmpty) {
      _addExclude();
      if (_errorText != null) return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    appState.setIncludePatterns(_includes);
    appState.setExcludePatterns(_excludes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dialogBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final headerBg = isDark ? const Color(0xFF181825) : const Color(0xFFF5F5F7);
    final cardBg = isDark ? const Color(0xFF161622) : const Color(0xFFFAFAFC);
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 620,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top desktop header bar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Settings',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    splashRadius: 18,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Main settings body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'APPEARANCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'Theme Mode:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                SegmentedButton<ThemeMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: ThemeMode.system,
                                      label: Text('System'),
                                      icon: Icon(
                                        Icons.brightness_auto,
                                        size: 14,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.light,
                                      label: Text('Light'),
                                      icon: Icon(Icons.light_mode, size: 14),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.dark,
                                      label: Text('Dark'),
                                      icon: Icon(Icons.dark_mode, size: 14),
                                    ),
                                  ],
                                  selected: {appState.themeMode},
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    textStyle: WidgetStatePropertyAll(
                                      TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  onSelectionChanged:
                                      (Set<ThemeMode> newSelection) {
                                        appState.setThemeMode(
                                          newSelection.first,
                                        );
                                      },
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, thickness: 1, color: borderColor),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Show YAML Frontmatter in Preview:',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Render leading --- metadata blocks as a structured card in Preview mode',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: mutedColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 26,
                                  child: Transform.scale(
                                    scale: 0.78,
                                    alignment: Alignment.centerRight,
                                    child: Switch(
                                      key: const Key('show_frontmatter_switch'),
                                      value: appState.showFrontmatter,
                                      onChanged: (value) {
                                        appState.setShowFrontmatter(value);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'FILE INDEXING PATTERNS (REGEX)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Include Patterns (Leave empty to include all .md/.markdown)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                    _buildPatternList(
                      _includes,
                      _removeInclude,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      mutedColor: mutedColor,
                      emptyHint:
                          'All .md and .markdown files are included by default',
                    ),
                    _buildInputRow(
                      _includeController,
                      'Add include pattern...',
                      _addInclude,
                      _includePathMatch,
                      (val) => setState(() => _includePathMatch = val),
                      cardBg: cardBg,
                      borderColor: borderColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Exclude Patterns (e.g. ^node_modules\$)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                    _buildPatternList(
                      _excludes,
                      _removeExclude,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      mutedColor: mutedColor,
                      emptyHint: 'No exclude patterns configured',
                    ),
                    _buildInputRow(
                      _excludeController,
                      'Add exclude pattern...',
                      _addExclude,
                      _excludePathMatch,
                      (val) => setState(() => _excludePathMatch = val),
                      cardBg: cardBg,
                      borderColor: borderColor,
                    ),
                  ],
                ),
              ),
            ),
            // Bottom desktop action bar
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.02)
                    : Colors.black.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  if (_errorText != null)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 15,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorText!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      side: BorderSide(color: borderColor),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Save & Re-index'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow(
    TextEditingController controller,
    String hint,
    VoidCallback onAdd,
    bool isPath,
    Function(bool) onScopeChanged, {
    required Color cardBg,
    required Color borderColor,
  }) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Name')),
              ButtonSegment(value: true, label: Text('Path')),
            ],
            selected: {isPath},
            showSelectedIcon: false,
            onSelectionChanged: (Set<bool> newSelection) {
              onScopeChanged(newSelection.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: cardBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              onSubmitted: (_) => onAdd(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Add', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPatternList(
    List<String> patterns,
    Function(String) onRemove, {
    required Color cardBg,
    required Color borderColor,
    required Color mutedColor,
    required String emptyHint,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: patterns.isEmpty
            ? Center(
                child: Text(
                  emptyHint,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: mutedColor.withValues(alpha: 0.7),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: patterns.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 1, thickness: 1, color: borderColor),
                itemBuilder: (context, index) {
                  final raw = patterns[index];
                  return _PatternListItem(
                    key: ValueKey(raw),
                    pattern: raw,
                    onDelete: onRemove,
                    onEdit: (oldP, newP) {
                      setState(() {
                        final idx = patterns.indexOf(oldP);
                        if (idx != -1) {
                          patterns[idx] = newP;
                        }
                      });
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _PatternListItem extends StatefulWidget {
  final String pattern;
  final Function(String oldPattern, String newPattern) onEdit;
  final Function(String pattern) onDelete;

  const _PatternListItem({
    super.key,
    required this.pattern,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PatternListItem> createState() => _PatternListItemState();
}

class _PatternListItemState extends State<_PatternListItem> {
  bool _isEditing = false;
  late TextEditingController _controller;
  late bool _isPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    _isPath = widget.pattern.startsWith('p:');
    final rawText =
        (widget.pattern.startsWith('p:') || widget.pattern.startsWith('n:'))
        ? widget.pattern.substring(2)
        : widget.pattern;
    _controller = TextEditingController(text: rawText);
  }

  @override
  void didUpdateWidget(_PatternListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pattern != widget.pattern && !_isEditing) {
      _initValues();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Cannot be empty');
      return;
    }

    try {
      RegExp(text); // Validate
      final newPattern = _isPath ? 'p:$text' : 'n:$text';
      widget.onEdit(widget.pattern, newPattern);
      setState(() {
        _isEditing = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Invalid Regex');
    }
  }

  void _cancel() {
    setState(() {
      _isEditing = false;
      _error = null;
      _initValues(); // Reset
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (_isEditing) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Name')),
                    ButtonSegment(value: true, label: Text('Path')),
                  ],
                  selected: {_isPath},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() => _isPath = newSelection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green, size: 16),
                  onPressed: _save,
                  tooltip: 'Save',
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _cancel,
                  tooltip: 'Cancel',
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isPath = widget.pattern.startsWith('p:');
    final hasPrefix =
        widget.pattern.startsWith('p:') || widget.pattern.startsWith('n:');
    final display = hasPrefix ? widget.pattern.substring(2) : widget.pattern;
    final typeLabel = isPath ? 'PATH' : 'NAME';
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isPath
                  ? primary.withValues(alpha: isDark ? 0.18 : 0.12)
                  : Colors.blueAccent.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isPath ? primary : Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _isEditing = true),
              child: Text(
                display,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 15),
              tooltip: 'Remove pattern',
              onPressed: () => widget.onDelete(widget.pattern),
            ),
          ),
        ],
      ),
    );
  }
}
