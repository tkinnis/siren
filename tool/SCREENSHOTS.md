# Siren Release Screenshot Inventory & Automation Guide

Before cutting or updating any Siren release, **all documentation screenshots in `docs/screenshots/` must be refreshed** so they accurately reflect the current UI, version number, settings, and rendered Markdown capabilities.

> **Important Release Rule**:
> 1. Never add screenshot-only flags or test hooks to `lib/` production code. Instead, drive the unmodified `Siren.app` binary externally using the native helper utilities in `tool/` (`tool/find_window`, `tool/click_at`, and `tool/splice_images`).
> 2. Whenever a new visual feature, dialog, or viewer capability is added, add its capture step to `tool/capture_screenshots.sh` and the inventory table below.
> 3. Run `./tool/capture_screenshots.sh` after building the release binary (`flutter build macos --release`) so all screenshots in `docs/screenshots/` are regenerated in a single pass.

---

## 1. Native Manipulation Utilities in `tool/`

* **`tool/find_window`** (`tool/find_window.m`): Queries `CGWindowListCopyWindowInfo` for on-screen windows and prints each window's `Owner`, `ID` (`CGWindowNumber`), and `Bounds` (`X`, `Y`, `Width`, `Height`).
* **`tool/click_at <x> <y>`** (`tool/click_at.c`): Posts a hardware-level `CGEventCreateMouseEvent` left-click at screen coordinates `(x, y)` relative to the window's top-left `(X, Y)` bounds.
* **`tool/splice_images <light_png> <dark_png> <output_png>`** (`tool/splice_images.m`): Composites the Light Mode and Dark Mode `1200×800` captures across an angled diagonal seam to produce `docs/screenshots/siren_theme_split.png`.

Run the full capture script from the repository root after building `build/macos/Build/Products/Release/Siren.app`:

```bash
./tool/capture_screenshots.sh
```

---

## 2. Screenshot Inventory (`docs/screenshots/`)

| File in `docs/screenshots/` | UI Interaction / Tool Step | Description & State | Referenced In |
| :--- | :--- | :--- | :--- |
| `siren_comprehensive_dark.png` | Launch `Siren docs/markdown-guide.md --standard-window` in Dark Mode | Dark Mode rendered preview of `docs/markdown-guide.md` showing the YAML Frontmatter card with pill badges, headings, and GitHub Alerts | Input to `siren_theme_split.png` |
| `siren_comprehensive_light.png` | Open `Settings` -> click `Light` segment -> click `Save & Re-index` | Light Mode rendered preview of `docs/markdown-guide.md` with matching tabs and Explorer state | Input to `siren_theme_split.png` |
| `siren_theme_split.png` | `tool/splice_images` on Light & Dark captures | Diagonal Light/Dark spliced hero showcase image (`1200×800`) | `README.md`, `docs/features.md` |
| `siren_comprehensive_rendered.png` | Copy of `siren_comprehensive_dark.png` | Standard Dark Mode rendered preview of `docs/markdown-guide.md` | `docs/features.md` |
| `siren_raw_view.png` | Click top-right `View Raw Markdown` (`<>`) toolbar button | Raw Markdown source view of `docs/markdown-guide.md` with aligned line-number gutter | `README.md`, `docs/features.md` |
| `siren_outline_view.png` | Click sidebar `Outline` tab | Sidebar `Outline` tab displaying the extracted heading hierarchy of `docs/markdown-guide.md` | `README.md`, `docs/features.md` |
| `siren_search_view.png` | Click sidebar `Search` tab and enter search query | Sidebar `Search` tab running an embedded Ripgrep workspace search | `README.md`, `docs/features.md` |
| `siren_quick_open.png` | Trigger `File -> Quick Open...` (`Cmd+P`) | Isolate-powered `Quick Open` fuzzy file finder modal | `README.md`, `docs/features.md` |
| `siren_settings_dialog.png` | Click top-right `Settings` gear icon | Desktop `Settings` dialog showing `Theme Mode`, `Show YAML Frontmatter in Preview`, and `File Indexing Patterns (Regex)` | `README.md`, `docs/features.md` |
| `siren_about_dialog.png` | Click `Siren -> About Siren` menu item | Native macOS `About Siren` modal showing current release version (`Version 0.3.0`) | `README.md`, `docs/features.md` |
| `siren_licenses_view.png` | Click `Open Source Licenses` inside `About Siren` | 2-column Open Source Licenses browser inside `AboutSirenDialog` | `README.md`, `docs/features.md` |
| `siren_mermaid_viewer.png` | Open `docs/mermaid-examples.md` and click diagram fullscreen button | Interactive `MermaidZoomDialog` vector zoom, pan & PNG/SVG export inspector | `README.md`, `docs/features.md` |
