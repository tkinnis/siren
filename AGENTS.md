# Agent Guidelines for Siren

This document provides operational context, architectural invariants, and workflow requirements for AI coding assistants (Claude Code, Gemini CLI, Cursor, GitHub Copilot, Codex, etc.) contributing to **Siren**.

---

## 1. Project Overview & Tech Stack

**Siren** is a sleek, high-performance desktop Markdown viewer built with Flutter, targeting macOS.

* **Framework**: Flutter 3.47+ (Dart 3.x).
* **Target Platform**: macOS desktop (native menu bar, title bar safe areas, keyboard shortcuts).
* **State Management**: `package:provider` with `AppState` (`ChangeNotifier`). Do not introduce secondary state managers (e.g. Riverpod, BLoC, GetX).
* **Search Architecture**: 
  * Full-text search: Embedded `rg` (ripgrep) binary (`assets/bin/rg`) executed via `Process.start`.
  * Fuzzy file finding: Background Dart isolate (`quick_open.dart`) for asynchronous search without UI stutter.
* **Markdown Rendering**: CommonMark compliant with custom extensions for GitHub Alerts, LaTeX math typography, Mermaid diagrams, and code syntax highlighting.

---

## 2. Directory Structure

```text
siren/
├── lib/               # Application source code
│   ├── main.dart             # Application entrypoint & multi-window handling
│   ├── home_screen.dart      # Main window shell, title bar, tabs, and menus
│   ├── app_state.dart        # Central ChangeNotifier state manager
│   ├── markdown_view.dart    # Dual-mode viewer (Rendered & Raw source)
│   ├── outline_view.dart     # Heading hierarchy extractor & navigator
│   ├── file_explorer.dart    # File tree viewer with hidden file support
│   ├── search_view.dart      # Ripgrep global workspace search
│   ├── quick_open.dart       # Isolate-based fuzzy file finder
│   ├── settings_dialog.dart  # Desktop settings (themes, regex index patterns)
│   └── about_dialog.dart     # Native macOS About & open-source licenses dialog
├── test/              # Unit, widget, and specification tests
├── assets/            # Bundled runtime assets ONLY (images, ripgrep binary)
├── docs/              # User documentation and markdown guides
│   └── screenshots/   # Verification screenshots (NEVER bundled into app assets)
└── tool/              # Native helper utilities and developer automation tools
```

---

## 3. Core Architectural Invariants & Rules

When modifying or adding code, you must respect the following project invariants:

### A. Single-Tab Invariant
* An open file must **never** be duplicated into a second tab.
* Whether opened from the File Explorer, Quick Open fuzzy finder, relative link navigation, or history traversal, always inspect `appState.openFiles` and switch to the existing tab index if the file is already open.

### B. Strict Asset Separation
* Runtime assets bundled into the macOS application bundle reside strictly in `assets/`.
* Documentation screenshots and feature captures reside in `docs/screenshots/`. **Never** place documentation screenshots in `assets/` or add them to `pubspec.yaml` assets.

### C. Bounded Desktop Layout Constraints
* All modals, dialogs, and floating sheets must have bounded dimensions (e.g. `SizedBox(width: ..., height: ...)` or `ConstrainedBox`).
* **Never** wrap unbounded scrolling widgets (`SingleChildScrollView`, `ListView`) around children containing `Expanded` or `Flexible` widgets without explicit height constraints. Doing so causes fatal layout assertions in Flutter.

### D. Responsive Non-Blocking UI
* Expensive disk traversal, full-text searches, and regex indexing must execute in background Dart isolates or detached processes. Never block the main UI isolate.

### E. Documentation & Comment Integrity
* Maintain existing code comments and docstrings.
* If a feature, shortcut, or UI behavior changes, update the corresponding documentation files in `docs/` (`features.md`, `shortcuts.md`, `markdown-guide.md`, `README.md`).

---

## 4. Verification & Quality Gates

Before completing any task or proposing changes, you must run and pass the following quality gates:

1. **Static Analysis**:
   ```bash
   flutter analyze
   ```
   Must produce **0** warnings, errors, or lint violations.

2. **Test Suite**:
   ```bash
   flutter test
   ```
   All tests in `test/` must pass (100% pass rate). When fixing bugs or adding features, add unit or widget tests to prevent regressions.

3. **Code Formatting**:
   ```bash
   dart format lib test
   ```
   Ensure all Dart code adheres to standard formatting.

---

## 5. Commit & Pull Request Guidelines

* Follow the **Conventional Commits** specification:
  * `feat(scope): ...` for new capabilities.
  * `fix(scope): ...` for bug fixes.
  * `docs(scope): ...` for documentation or screenshot updates.
  * `refactor(scope): ...` for code structural changes without behavioral changes.
  * `test(scope): ...` for adding or improving test coverage.
* Write concise, descriptive commit messages describing the rationale and outcome.
