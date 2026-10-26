---
title: Siren Documentation
category: User Manual
version: 0.3.0
tags: [documentation, overview, quick-start]
---

# Siren Documentation

Welcome to the **Siren** documentation. Siren is a fast, keyboard-friendly Markdown viewer designed for macOS, built with Flutter.

Whether you are browsing documentation, reviewing technical specifications, or reading notes, Siren provides an instant rendered preview alongside a dedicated raw source view with a line number gutter.

---

## Documentation Sections

Explore the documentation guides below:

- **[Features Overview](features.md)** — A comprehensive breakdown of Siren's core features, including dual-mode viewing, document outline, multi-tab workspace, fuzzy search, and live file system watching.
- **[Markdown Syntax Guide](markdown-guide.md)** — Complete reference for standard Markdown and extended features supported by Siren, such as GitHub Alerts, LaTeX Math, Mermaid diagrams, YAML frontmatter, footnotes, highlighting, and task lists.
- **[Mermaid Diagram Examples Gallery](mermaid-examples.md)** — Comprehensive 52-diagram gallery across all 20 Mermaid v11 diagram categories rendered offline with the ELK + `neo` engine.
- **[Keyboard Shortcuts](shortcuts.md)** — Quick reference guide for all keyboard shortcuts and navigation commands.
- **[Architecture & Development](architecture.md)** — Technical deep-dive into Siren's internals, isolate-powered indexing, Ripgrep integration, offline vector Mermaid engine, and development instructions.

---

## Quick Start

### Opening a Workspace
When launching Siren, you can open any folder or Markdown file:
- **Open File**: Press `Cmd+O` or select **File > Open...**
- **Open Folder**: Press `Cmd+Shift+O` or select **File > Open Folder...** (or drag a folder directly from Finder) to set your workspace root. The sidebar File Explorer will automatically index and display all documents in that folder.
- **Open Recent**: Select **File > Open Recent** to quickly reopen recent Markdown files or switch between recent workspace folders.

### Switching Between Rendered and Raw Views
- Press `Cmd+E` (or click the toggle icon in the top toolbar) to switch between **Rendered Mode** and **Raw Markdown Mode**.

### Quick Open (Fuzzy Finder)
- Press `Cmd+P` anywhere in Siren to open the fuzzy file finder. Type any part of a filename or path to jump directly to that document.

### Scaling Text & Inspecting Mermaid Diagrams / Images
- Use the toolbar **`+` / `-`** buttons (or `Cmd+=`, `Cmd+-`, `Cmd+0`) to scale document typography and Mermaid vector diagrams proportionally.
- Click any rendered **Mermaid diagram** (or its hover **Zoom** button) to open the interactive **Diagram Viewer** modal with drag-to-pan, pinch/scroll zoom, **Copy Image (PNG)**, and **Export Diagram (SVG / PNG)**.
- Click any rendered **Markdown image** to inspect it in the interactive **Image Viewer** lightbox modal.

---

## Next Steps
Continue reading the **[Features Overview](features.md)** to learn more about Siren's capabilities, or visit the **[Siren GitHub Repository](https://github.com/tkinnis/siren)** to download the latest macOS release.

---

*Siren is an open-source macOS Markdown viewer created by [Tony Kinnis](https://github.com/tkinnis).*

