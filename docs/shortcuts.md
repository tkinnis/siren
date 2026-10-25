---
title: Siren Keyboard Shortcuts
category: User Manual
version: 0.3.0
tags: [shortcuts, macos, menu-bar, navigation]
---

# Siren Keyboard Shortcuts

Siren is built with a keyboard-first philosophy and a standard macOS menu bar (**Siren**, **File**, **Edit**, **View**, **History**, **Window**). This document lists all available keyboard shortcuts for macOS.

---

## Navigation & Workspace

| Action | Shortcut | Menu / Location | Description |
| :--- | :---: | :--- | :--- |
| **Toggle Render / Raw View** | `Cmd+E` or `Cmd+Shift+P` | `View > Toggle Preview / Raw View` | Switch between formatted rendered view and raw Markdown with line gutter |
| **Toggle Dark / Light Theme** | `Cmd+Shift+D` | `View > Toggle Dark/Light Mode` | Instantly switch between light and dark themes |
| **Toggle Sidebar** | `Cmd+B` | `View > Show/Hide Sidebar` | Show or hide the sidebar (Explorer, Outline, Search) |
| **Show Explorer in Sidebar** | `Cmd+Shift+E` | `View > Show Explorer` | Open the sidebar and switch to the File Explorer tab |
| **Show Outline in Sidebar** | `Cmd+Ctrl+O` | `View > Show Outline` | Open the sidebar and switch to the Document Outline tab |
| **Focus File Explorer Tree** | `Cmd+L` | Sidebar | Focus the File Explorer for arrow-key navigation |
| **Back in History** | `Cmd+[` | `History > Back` | Navigate to the previous document in tab history |
| **Forward in History** | `Cmd+]` | `History > Forward` | Navigate forward in tab history |
| **Open Settings** | `Cmd+,` | `Siren > Settings...` | Configure appearance, theme mode, and file indexing patterns |

---

## File & Tab Management

| Action | Shortcut | Menu / Location | Description |
| :--- | :---: | :--- | :--- |
| **Open File** | `Cmd+O` | `File > Open...` | Open a Markdown file via system file picker |
| **Open Folder** | `Cmd+Shift+O` | `File > Open Folder...` | Open a directory as the workspace root |
| **Reload File** | `Cmd+R` | `File > Reload File` | Reload the active document, images, and diagrams from disk |
| **Close Tab** | `Cmd+W` | `File > Close Tab` | Close the currently active document tab |
| **Close Other Tabs** | `Cmd+Option+W` | `File > Close Other Tabs` | Close all tabs except the active tab |
| **Close All Tabs** | `Cmd+Shift+W` | `File > Close All Tabs` | Close all open tabs |
| **Reopen Closed Tab** | `Cmd+Shift+T` | `File > Reopen Closed Tab` | Restore the most recently closed tab |
| **Show Previous Tab** | `Cmd+Shift+[` | `Window > Show Previous Tab` | Switch to the previous open tab |
| **Show Next Tab** | `Cmd+Shift+]` | `Window > Show Next Tab` | Switch to the next open tab |
| **Switch to Tab 1–9** | `Cmd+1` – `Cmd+9` | Keyboard | Jump directly to the tab at the given index |

---

## Search & Discovery

| Action | Shortcut | Description |
| :--- | :---: | :--- |
| **Quick Open (Fuzzy Finder)** | `Cmd+P` | Search and open files across the workspace |
| **Find in File** | `Cmd+F` | Open the in-document search bar |
| **Find Next Match** | `Cmd+G` or `Enter` | Jump to the next match in Find in File |
| **Find Previous Match** | `Cmd+Shift+G` or `Shift+Enter` | Jump to the previous match in Find in File |
| **Global Workspace Search** | `Cmd+Shift+F` | Full-text search across all workspace Markdown files |
| **Dismiss Search / Modals** | `Escape` | Close the find bar, Quick Open, or Zoom modal |

---

## View, Zoom & Reload

| Action | Shortcut | Description |
| :--- | :---: | :--- |
| **Increase Font & Diagram Scale** | `Cmd++` or `Cmd+=` | Enlarge document body, raw text font, and Mermaid diagrams |
| **Decrease Font & Diagram Scale** | `Cmd+-` | Reduce document body, raw text font, and Mermaid diagrams |
| **Reset Font & Diagram Scale** | `Cmd+0` | Reset font size and diagram scale to default (14.0) |
| **Reload File** | `Cmd+R` | Reload active document from disk |

---

## Document & Tab Interactions

| Action | Interaction |
| :--- | :--- |
| **Jump to Heading** | Click any heading in the **Outline View** |
| **Open Link** | Click any relative Markdown link |
| **Follow In-Document Anchor** | Click an anchor link (e.g. `#section-heading`) to scroll smoothly |
| **Inspect / Export Mermaid Diagram** | Click any rendered Mermaid diagram to open the Zoom & Pan viewer (`+`, `-`, `Cmd+0`, double-click, Copy PNG, Export SVG/PNG) |
| **Inspect Image in Lightbox** | Click any rendered Markdown image to open the interactive Image Viewer lightbox |
| **Tab Context Menu** | Right-click any tab to Close, Close Others, Close All, Show in Finder, or Copy Path |
| **File Explorer Context Menu** | Right-click any file or folder in the Explorer to Show in Finder, Copy Path, or Copy Relative Path |
