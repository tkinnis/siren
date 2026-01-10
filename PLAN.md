# Siren Development Plan

## Phase 1: Foundation & Setup
- [x] **Project Initialization**: Scaffold Flutter app for macOS.
- [x] **Dependencies**: Add `flutter_markdown`, `flutter_highlighter`, `webview_flutter`, `webview_flutter_wkwebview`, `window_manager`, `file_selector`, `provider`.
- [x] **MacOS Configuration**: Configure `Info.plist` for file associations (Markdown).

## Phase 2: Core Architecture (The Viewer)
- [x] **State Management**: Simple state for `currentFileContent`, `viewMode` (Rendered/Raw), `fontSize`.
- [x] **File Loading**: Implement logic to read file from disk.
- [x] **Launch Arguments**: Handle opening file from command line / "Open with" (MethodChannel implementation).

## Phase 3: Raw View
- [x] **UI Implementation**: Scrollable text area.
- [x] **Syntax Highlighting**: Apply high-performance highlighting to the raw markdown text.

## Phase 4: Rendered View (Markdown + Code)
- [x] **Markdown Rendering**: basic `flutter_markdown` setup.
- [x] **Code Blocks**: Custom builder using `flutter_highlighter` for standard languages.

## Phase 5: Mermaid Diagrams
- [x] **Strategy**: Implement `mermaid` code block builder.
- [x] **Implementation**: Embed local WebView to render Mermaid to SVG/Canvas.

## Phase 6: Polish & Native Feel
- [x] **Window Styling**: Transparent title bar, unified look.
- [x] **Zoom Controls**: Keyboard shortcuts (Cmd+, Cmd-) handling.
- [x] **Empty State**: Drag & drop target or "Open File" button.

## Phase 7: Editor & Navigation
- [x] **File Explorer**: Sidebar to browse directories and filter `.md` files.
- [x] **Tabs System**: Manage multiple open files with drag-and-drop support.
- [x] **Split View**: Resizable or fixed sidebar layout.
- [x] **State Refactor**: Support multiple file contexts and directory tracking.