# Accessibility Statement

**Siren** is committed to providing an accessible, comfortable, and keyboard-navigable Markdown reading experience on macOS.

## Built-In Accessibility Features

### 1. Keyboard-First Navigation
All primary workflows in Siren can be operated directly from the keyboard without requiring pointer precision:
* **Quick Open Fuzzy Finder**: <kbd>Cmd</kbd>+<kbd>P</kbd> (with <kbd>↑</kbd>/<kbd>↓</kbd> navigation, <kbd>Enter</kbd> to open, and <kbd>Esc</kbd> to dismiss)
* **Global Workspace Search**: <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd>
* **Toggle Sidebar / Document Outline**: <kbd>Cmd</kbd>+<kbd>B</kbd> and <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>O</kbd>
* **Toggle Rendered & Raw Source Views**: <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>M</kbd>
* **History Navigation**: <kbd>Cmd</kbd>+<kbd>[</kbd> (Back) and <kbd>Cmd</kbd>+<kbd>]</kbd> (Forward)
* **Tab & Window Management**: <kbd>Cmd</kbd>+<kbd>W</kbd> (Close Tab), <kbd>Cmd</kbd>+<kbd>N</kbd> (New Window), <kbd>Cmd</kbd>+<kbd>,</kbd> (Settings)

See the [Keyboard Shortcuts Reference](docs/shortcuts.md) for the complete list.

### 2. Visual Comfort & High-Contrast Themes
Siren includes four curated color palettes accessible from **Settings** (<kbd>Cmd</kbd>+<kbd>,</kbd>):
* **Light**: Clean high-legibility daylight palette
* **Dark**: Balanced low-glare dark palette
* **High Contrast Dark**: Elevated contrast ratios for text, syntax tokens, borders, and callout alerts
* **Sepia**: Warm low-blue-light reading palette

Theme-aware `<picture>` elements and callout borders automatically adapt to the active theme brightness.

### 3. Proportional Typography & Vector Diagram Scaling
* **Global Zoom**: Press <kbd>Cmd</kbd>+<kbd>+</kbd> (Zoom In), <kbd>Cmd</kbd>+<kbd>-</kbd> (Zoom Out), or <kbd>Cmd</kbd>+<kbd>0</kbd> (Reset Zoom) to proportionally scale body typography, headings, code blocks, GFM tables, LaTeX math expressions, and inline Mermaid vector diagrams (`50%` to `300%`).
* **Interactive Lightboxes**: Click any image, badge, or Mermaid diagram to open a dedicated zoom-and-pan modal with keyboard and trackpad controls.

## Reporting Accessibility Issues

If you encounter an accessibility barrier, screen reader issue, keyboard trap, or contrast deficiency in Siren:

1. Open a [GitHub Issue](https://github.com/tkinnis/siren/issues/new?template=bug_report.md) and apply the `accessibility` label.
2. Include the macOS version, assistive technology or display setting in use, and the steps to reproduce the barrier.
