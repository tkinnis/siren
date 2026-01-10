# Siren Development Plan

## Phase 1: Foundation & Setup
- [ ] **Project Initialization**: Scaffold Flutter app for macOS.
- [ ] **Dependencies**: Add `flutter_markdown`, `flutter_highlighter`, `webview_flutter`, `webview_flutter_wkwebview`, `window_manager`, `file_selector`, `provider`.
- [ ] **MacOS Configuration**: Configure `Info.plist` for file associations (Markdown).

## Phase 2: Core Architecture (The Viewer)
- [ ] **State Management**: Simple state for `currentFileContent`, `viewMode` (Rendered/Raw), `fontSize`.
- [ ] **File Loading**: Implement logic to read file from disk.
- [ ] **Launch Arguments**: Handle opening file from command line / "Open with" (MethodChannel implementation).

## Phase 3: Raw View
- [ ] **UI Implementation**: Scrollable text area.
- [ ] **Syntax Highlighting**: Apply high-performance highlighting to the raw markdown text.

## Phase 4: Rendered View (Markdown + Code)
- [ ] **Markdown Rendering**: basic `flutter_markdown` setup.
- [ ] **Code Blocks**: Custom builder using `flutter_highlighter` for standard languages.

## Phase 5: Mermaid Diagrams
- [ ] **Strategy**: Implement `mermaid` code block builder.
- [ ] **Implementation**: Embed local WebView to render Mermaid to SVG/Canvas.

## Phase 6: Polish & Native Feel
- [ ] **Window Styling**: Transparent title bar, unified look.
- [ ] **Zoom Controls**: Keyboard shortcuts (Cmd+, Cmd-) handling.
- [ ] **Empty State**: Drag & drop target or "Open File" button.