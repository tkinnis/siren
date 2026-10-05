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
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              const Text(
                'Appearance',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Theme Mode:'),
                  const SizedBox(width: 16),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto, size: 16),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode, size: 16),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode, size: 16),
                      ),
                    ],
                    selected: {appState.themeMode},
                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                      appState.setThemeMode(newSelection.first);
                    },
                  ),
                ],
              ),
              const Divider(height: 28),
              const Text(
                'File Indexing Patterns (Regex)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            const Text(
              'Include Patterns (Leave empty to include all .md/.markdown)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            _buildPatternList(_includes, _removeInclude),
            _buildInputRow(
              _includeController,
              'Add include pattern...',
              _addInclude,
              _includePathMatch,
              (val) => setState(() => _includePathMatch = val),
            ),
            const Divider(height: 32),
            const Text(
              'Exclude Patterns (e.g. ^node_modules\$)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            _buildPatternList(_excludes, _removeExclude),
            _buildInputRow(
              _excludeController,
              'Add exclude pattern...',
              _addExclude,
              _excludePathMatch,
              (val) => setState(() => _excludePathMatch = val),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save & Re-index'),
        ),
      ],
    );
  }

  Widget _buildInputRow(
    TextEditingController controller,
    String hint,
    VoidCallback onAdd,
    bool isPath,
    Function(bool) onScopeChanged,
  ) {
    return Row(
      children: [
        // Scope Selector
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Name')),
              ButtonSegment(value: true, label: Text('Path')),
            ],
            selected: {isPath},
            onSelectionChanged: (Set<bool> newSelection) {
              onScopeChanged(newSelection.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: onAdd,
        ),
      ],
    );
  }

  Widget _buildPatternList(List<String> patterns, Function(String) onRemove) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListView.builder(
          itemCount: patterns.length,
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
    final rawText = (widget.pattern.startsWith('p:') || widget.pattern.startsWith('n:')) 
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
    if (_isEditing) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    style: const TextStyle(fontFamily: 'monospace'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: _save,
                  tooltip: 'Save',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
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
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isPath = widget.pattern.startsWith('p:');
    final hasPrefix = widget.pattern.startsWith('p:') || widget.pattern.startsWith('n:');
    final display = hasPrefix ? widget.pattern.substring(2) : widget.pattern;
    final typeLabel = isPath ? 'PATH' : 'NAME';

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isPath 
              ? Theme.of(context).colorScheme.primaryContainer 
              : Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          typeLabel,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
      title: GestureDetector(
        onDoubleTap: () => setState(() => _isEditing = true),
        child: Text(display, style: const TextStyle(fontFamily: 'monospace')),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete, size: 16),
        onPressed: () => widget.onDelete(widget.pattern),
      ),
      dense: true,
    );
  }
}