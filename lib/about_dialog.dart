import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class _PackageLicenses {
  final String packageName;
  final List<List<LicenseParagraph>> entries;

  _PackageLicenses({
    required this.packageName,
    required this.entries,
  });
}

/// A desktop-first About and License dialog for Siren.
class AboutSirenDialog extends StatefulWidget {
  const AboutSirenDialog({super.key});

  @override
  State<AboutSirenDialog> createState() => _AboutSirenDialogState();
}

class _AboutSirenDialogState extends State<AboutSirenDialog> {
  bool _showLicenses = false;
  List<_PackageLicenses>? _allPackages;
  String _filterQuery = '';
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _packageListController = ScrollController();
  final ScrollController _licenseTextController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    final Map<String, List<List<LicenseParagraph>>> packageMap = {};

    await for (final LicenseEntry entry in LicenseRegistry.licenses) {
      for (final String package in entry.packages) {
        packageMap
            .putIfAbsent(package, () => [])
            .add(entry.paragraphs.toList());
      }
    }

    final packages = packageMap.entries
        .map((e) => _PackageLicenses(packageName: e.key, entries: e.value))
        .toList();

    packages.sort((a, b) =>
        a.packageName.toLowerCase().compareTo(b.packageName.toLowerCase()));

    if (mounted) {
      setState(() {
        _allPackages = packages;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _packageListController.dispose();
    _licenseTextController.dispose();
    super.dispose();
  }

  List<_PackageLicenses> get _filteredPackages {
    if (_allPackages == null) return [];
    if (_filterQuery.trim().isEmpty) return _allPackages!;
    final query = _filterQuery.trim().toLowerCase();
    return _allPackages!
        .where((p) => p.packageName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dialogBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 760,
        height: 520,
        child: _showLicenses ? _buildLicensesView(theme, isDark, borderColor) : _buildAboutView(theme, isDark, borderColor),
      ),
    );
  }

  Widget _buildAboutView(ThemeData theme, bool isDark, Color borderColor) {
    return Column(
      children: [
        // Top bar with close button
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.close, size: 18),
            splashRadius: 18,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        // About content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 88,
                      height: 88,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.description,
                          size: 44,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Siren',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 0.1.0',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    'A sleek, native desktop Markdown viewer with real-time preview, '
                    'LaTeX math, Mermaid diagrams, and fast workspace navigation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Released under the MIT License',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Copyright © 2026 Tony Kinnis',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom action bar
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('View Open Source Licenses'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  side: BorderSide(color: borderColor),
                ),
                onPressed: () {
                  setState(() {
                    _showLicenses = true;
                    _selectedIndex = 0;
                  });
                },
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLicensesView(ThemeData theme, bool isDark, Color borderColor) {
    final filtered = _filteredPackages;
    final selectedPackage = (filtered.isNotEmpty && _selectedIndex < filtered.length)
        ? filtered[_selectedIndex]
        : null;

    final headerBg = isDark ? const Color(0xFF181825) : const Color(0xFFF5F5F7);
    final sidebarBg = isDark ? const Color(0xFF14141E) : const Color(0xFFFAFAFC);

    return Column(
      children: [
        // Dialog-contained Top Header (Never interferes with macOS traffic lights)
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('About Siren'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onPressed: () {
                  setState(() {
                    _showLicenses = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 18, color: borderColor),
              const SizedBox(width: 12),
              const Text(
                'Open Source Licenses',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Compact Search Bar
              SizedBox(
                width: 220,
                height: 32,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Filter packages...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    suffixIcon: _filterQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            splashRadius: 14,
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _filterQuery = '';
                                _selectedIndex = 0;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: theme.colorScheme.primary),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _filterQuery = val;
                      _selectedIndex = 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                splashRadius: 18,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // Master-Detail Body
        Expanded(
          child: _allPackages == null
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Packages Sidebar
                    Container(
                      width: 240,
                      color: sidebarBg,
                      child: Column(
                        children: [
                          // Aligned Top Bar for Sidebar
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: borderColor)),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${filtered.length} ${filtered.length == 1 ? 'Package' : 'Packages'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : Colors.black45,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          // Package List
                          Expanded(
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      'No packages found',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white38 : Colors.black38,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _packageListController,
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final pkg = filtered[index];
                                      final isSelected = index == _selectedIndex;
                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedIndex = index;
                                            _licenseTextController.jumpTo(0);
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? (isDark
                                                    ? theme.colorScheme.primary.withValues(alpha: 0.18)
                                                    : theme.colorScheme.primary.withValues(alpha: 0.12))
                                                : Colors.transparent,
                                            border: Border(
                                              left: BorderSide(
                                                color: isSelected
                                                    ? theme.colorScheme.primary
                                                    : Colors.transparent,
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                pkg.packageName,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  color: isSelected
                                                      ? theme.colorScheme.primary
                                                      : (isDark ? Colors.white : Colors.black87),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${pkg.entries.length} ${pkg.entries.length == 1 ? 'license' : 'licenses'}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isDark ? Colors.white38 : Colors.black38,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    // Divider between columns
                    Container(width: 1, color: borderColor),
                    // Right Column: License Text Viewer
                    Expanded(
                      child: selectedPackage == null
                          ? Center(
                              child: Text(
                                'Select a package to view its license.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                // Aligned Top Bar for Right Column (Exact same height as left: 36px)
                                Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: borderColor)),
                                    color: isDark ? Colors.black12 : Colors.white70,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: [
                                      Text(
                                        selectedPackage.packageName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${selectedPackage.entries.length} ${selectedPackage.entries.length == 1 ? 'entry' : 'entries'}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Scrollable Monospace License Content
                                Expanded(
                                  child: Scrollbar(
                                    controller: _licenseTextController,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _licenseTextController,
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          for (int entryIdx = 0; entryIdx < selectedPackage.entries.length; entryIdx++) ...[
                                            if (entryIdx > 0) ...[
                                              const SizedBox(height: 24),
                                              Divider(color: borderColor),
                                              const SizedBox(height: 16),
                                            ],
                                            ...selectedPackage.entries[entryIdx].map((paragraph) {
                                              if (paragraph.indent == LicenseParagraph.centeredIndent) {
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  child: SelectableText(
                                                    paragraph.text,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontFamily: 'SF Mono',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return Padding(
                                                padding: EdgeInsets.only(
                                                  left: (paragraph.indent * 16.0).clamp(0.0, 80.0),
                                                  bottom: 8.0,
                                                ),
                                                child: SelectableText(
                                                  paragraph.text,
                                                  style: TextStyle(
                                                    fontFamily: 'SF Mono',
                                                    fontSize: 11,
                                                    height: 1.45,
                                                    color: isDark ? const Color(0xFFDCDFE4) : const Color(0xFF24292E),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
