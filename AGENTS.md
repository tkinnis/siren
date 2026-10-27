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
* **Markdown Rendering**: CommonMark and GitHub Flavored Markdown (GFM) compliant with custom extensions for YAML Frontmatter cards, footnotes, GitHub Alerts, embedded GFM HTML (`<kbd>`, `<details>`, `<table>`, `<dl>`, `<picture>`, sized `<img>`, `3x` Retina SVG badges, `<p align="center">`, `<!-- comments -->`), LaTeX math typography, interactive image lightbox, offline vector Mermaid diagrams (`vector_graphics` with proportional font scaling and interactive zoom/pan/export modal), and code syntax highlighting.

---

## 2. Directory Structure

```text
siren/
├── lib/               # Application source code
│   ├── main.dart                  # Application entrypoint & multi-window handling
│   ├── home_screen.dart           # Main window shell, title bar, tabs, and menus
│   ├── app_state.dart             # Central ChangeNotifier state manager
│   ├── editor_tabs.dart           # Reorderable tab bar with right-click context menu
│   ├── rendered_view.dart         # Formatted Markdown preview
│   ├── raw_view.dart              # Raw Markdown source view with line gutter
│   ├── markdown_processor.dart    # Markdown preprocessing & extension pipeline
│   ├── markdown_extensions.dart   # Custom syntax parsers & builders (alerts, frontmatter, footnotes, GFM HTML, SVG rasterizer)
│   ├── image_zoom_dialog.dart     # Interactive zoom & pan image lightbox modal
│   ├── mermaid_diagram.dart       # Scaled Mermaid vector diagram widget
│   ├── mermaid_render_service.dart# Offscreen SVG/vector compilation engine
│   ├── mermaid_zoom_dialog.dart   # Interactive zoom, pan & export diagram modal
│   ├── outline_view.dart          # Heading hierarchy extractor & navigator
│   ├── file_explorer.dart         # File tree viewer with hidden file support
│   ├── global_search_view.dart    # Ripgrep global workspace search
│   ├── file_search_modal.dart     # Isolate-based Quick Open fuzzy file finder
│   ├── settings_dialog.dart       # Desktop settings (themes, regex index patterns)
│   └── about_dialog.dart          # Native macOS About & open-source licenses dialog
├── test/              # Unit, widget, and specification tests
├── assets/            # Bundled runtime assets ONLY (images, ripgrep binary, mermaid scripts)
├── docs/              # User documentation and markdown guides
│   └── screenshots/   # Verification screenshots (NEVER bundled into app assets)
└── tool/              # Native helper utilities and developer automation tools
    ├── SCREENSHOTS.md         # Release screenshot inventory & checklist
    └── capture_screenshots.sh # Automated UI-driven screenshot capture script
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

4. **Release Screenshots** (when cutting or updating a release):
   ```bash
   ./tool/capture_screenshots.sh
   ```
   See [`tool/SCREENSHOTS.md`](tool/SCREENSHOTS.md) for the complete inventory of screenshots in `docs/screenshots/`. If new visual features are added, add their capture steps to `tool/capture_screenshots.sh` and `tool/SCREENSHOTS.md` without adding screenshot-only flags to `lib/`.

---

## 5. Issue Tracking, Commit, Pull Request & Release Guidelines

* **Issue-First Tracking Workflow**:
  * All features, bug fixes, and architectural tasks must be tracked via [GitHub Issues](https://github.com/tkinnis/siren/issues) (`gh issue list`, `gh issue view <id>`, `gh issue create`).
  * Before implementing a new feature or bug fix, check for an existing issue or create one with appropriate labels (`bug`, `enhancement`, `documentation`, `accessibility`, `security`, `performance`).
  * Reference the issue in commit messages and pull requests using `Closes #<id>` or `Refs #<id>`.
* Follow the **Conventional Commits** specification:
  * `feat(scope): ...` for new capabilities.
  * `fix(scope): ...` for bug fixes.
  * `docs(scope): ...` for documentation or screenshot updates.
  * `refactor(scope): ...` for code structural changes without behavioral changes.
  * `test(scope): ...` for adding or improving test coverage.
* Write concise, descriptive commit messages describing the rationale and outcome.
* **Release Naming Convention**:
  * **Tag**: `v<version>` (e.g., `v0.4.0`).
  * **GitHub Release Title**: `Siren v<version>` (e.g., `Siren v0.4.0`). Never omit `Siren` or append platform suffixes like `(macOS)` to the release title.
  * **Release Asset Archive**: `Siren-v<version>-macos.zip` (e.g., `Siren-v0.4.0-macos.zip`).

