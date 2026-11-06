---
title: Siren Architecture & Development
category: Engineering Guide
tags: [architecture, flutter, isolates, ripgrep, mermaid]
---

# Siren Architecture & Development

This document describes the architectural design and implementation patterns used in **Siren**.

---

## 1. High-Level Architecture

Siren is built using Flutter for macOS desktop. It employs a reactive unidirectional data flow centered around `AppState`, combined with background Dart isolates to ensure the main UI thread remains responsive at 120 FPS.

```mermaid
graph TD
    UI[Flutter UI Widgets] -->|Action Dispatch| State[AppState ChangeNotifier]
    State -->|State Updates| UI
    State -->|Background Scan| IndexerIsolate[File Indexer Isolate]
    State -->|Parallel Anchor Injection| AnchorIsolate[Anchor Injection Isolate]
    State -->|Search Process| Ripgrep[Ripgrep Subprocess]
    State -->|File Events| Watcher[WatcherService]
    UI -->|Viewport-Aware Render| Mermaid[MermaidRenderService]
    Mermaid -->|Zero-Copy TransferableTypedData| MermaidIsolates[Mermaid Worker Isolate Pool]
```

---

## 2. Core Subsystems

### State Management (`lib/app_state.dart`)
- Centralized `AppState` extending `ChangeNotifier`.
- Manages open tabs, active document content, navigation history stacks, font sizes, themes, and search states.
- Persists critical UI state (recent files, sidebar visibility, theme, window bounds) to `SharedPreferences`.

### Background Isolates
- **File Indexer (`lib/file_indexer.dart`)**: Traverses the workspace filesystem recursively inside a separate Dart isolate, filtering via include/exclude patterns and building an index of known Markdown documents.
- **Anchor Injection (`lib/markdown_processor.dart`)**: Injects HTML anchors into heading lines in an isolate so that large documents can be indexed and jumped to without blocking user interaction.
- **Mermaid Worker Isolate Pool (`lib/mermaid_render_service.dart`)**: Pre-spawns and JIT-warms persistent background worker isolates at application startup, executing `pele_dart` layout and `vector_graphics_compiler` encoding off the UI thread and returning compiled bytecode via zero-copy `TransferableTypedData`.

### Search Services
- **Fuzzy Matcher (`lib/fuzzy_matcher.dart`)**: Multi-token fuzzy matching with word-boundary and camelCase prioritization.
- **Ripgrep Service (`lib/ripgrep_service.dart`)**: Spawns a background `rg` process with JSON output parsing for high-throughput global workspace searches.

### Live File Watching (`lib/watcher_service.dart`)
- Monitors file system modification and removal events.
- Employs debounce timers and delay strategies to handle macOS atomic saves (where editors write to a temporary file, delete the original, and rename).

### Pure-Dart Mermaid Vector & SVG Compiler Engine (`lib/mermaid_render_service.dart`, `lib/mermaid_diagram.dart`, `lib/markdown_extensions.dart`)
- Uses `pele_dart` (`obsidianmd/pele` port) to parse, lay out, and render all 33 standard, beta, and specialized Mermaid diagram families in pure Dart with zero `WebView`, DOM, or JavaScript runtime dependencies.
- Flattens `--pele-*` CSS custom properties, `color-mix()` blends, `calc()`, `currentColor`, and nested icons/math against Siren's Light and Dark `PelePalette` themes (`SvgOutputMode.flattened`) and compiles them into binary `vector_graphics` bytecode (`VectorGraphic`) in a persistent background worker isolate pool with zero-copy `TransferableTypedData` transfer.
- Employs viewport-aware lazy rendering (`lib/mermaid_diagram.dart`), rendering the initial visible quota immediately on document open and deferring off-screen diagrams until they enter the scroll viewport lookahead buffer.
- Caches compiled diagrams in an LRU memory cache (`(code, isDarkMode)`) for instant scrolling, proportional font scaling, interactive zoom/pan inspection, macOS clipboard PNG copy, and SVG/PNG file export (`lib/mermaid_zoom_dialog.dart`).
- Normalizes and compiles complex SVG badges (`img.shields.io` with nested base64 `data:image/svg+xml` `<image>` logos and `transform="scale(.1)"` typography) and local `.svg` images into `vector_graphics` bytecode in pure Dart with in-memory LRU caching.

---

## 3. Directory Structure

```text
siren/
├── assets/             # Bundled application assets (images, ripgrep binary)
├── docs/               # User and developer documentation
├── lib/                # Flutter Dart source code
│   ├── app_state.dart             # Core application state & recent items persistence
│   ├── editor_tabs.dart           # Workspace tab bar with drag-and-drop & context menus
│   ├── file_explorer.dart         # Directory tree view
│   ├── file_search_modal.dart     # Quick Open (Cmd+P) dialog
│   ├── find_in_file_bar.dart      # In-document search bar
│   ├── global_search_view.dart    # Workspace full-text search
│   ├── home_screen.dart           # Main window scaffold, menus & shortcuts
│   ├── image_zoom_dialog.dart     # Interactive image lightbox viewer
│   ├── markdown_extensions.dart   # YAML frontmatter, GFM HTML, GitHub alerts, math & SVG compiler
│   ├── markdown_processor.dart    # HTML comment stripping & background heading anchor injection
│   ├── mermaid_diagram.dart       # Scaled Mermaid vector diagram widget
│   ├── mermaid_render_service.dart# Pure-Dart pele_dart SVG/vector compilation engine
│   ├── mermaid_zoom_dialog.dart   # Interactive zoom, pan & export diagram modal
│   ├── outline_view.dart          # Heading hierarchy tree
│   ├── raw_view.dart              # Raw Markdown source view with line gutter
│   ├── rendered_view.dart         # Formatted Markdown view
│   └── theme.dart                 # Light & dark theme extensions
├── macos/              # macOS native Runner project
└── test/               # Comprehensive automated test suite
```

---

## 4. Development & Testing

### Prerequisites
- Flutter SDK `^3.47.0` (Dart `^3.13.0`)
- macOS 12.0 or newer
- Xcode and Command Line Tools

### Setup and Running
```bash
# Clone the repository
git clone https://github.com/tkinnis/siren.git
cd siren

# Install dependencies
flutter pub get

# Run on macOS desktop
flutter run -d macos
```

### Running Tests
Siren includes extensive unit and widget tests covering Markdown parsing, tab management, fuzzy matching, line number alignment, and history navigation:

```bash
# Run all unit and widget tests
flutter test

# Run static analysis
flutter analyze
```
