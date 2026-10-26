#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Siren Release Screenshot Automation Script
# ==============================================================================
# Drives the unmodified Release build of Siren.app using the native tools in
# tool/ (find_window, click_at, splice_images), System Events menu actions, and
# macOS screencapture. See tool/SCREENSHOTS.md for the full inventory.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_BIN="$REPO_ROOT/build/macos/Build/Products/Release/Siren.app/Contents/MacOS/Siren"
SCREENSHOT_DIR="$REPO_ROOT/docs/screenshots"
BUNDLE_ID="com.tonykinnis.Siren"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Error: Release binary not found at $APP_BIN"
  echo "Run 'flutter build macos --release' first."
  exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

# Back up current user preferences so the script leaves the user's setup intact
BACKUP_PLIST="$(mktemp -t siren_prefs_backup.XXXXXX.plist)"
defaults export "$BUNDLE_ID" "$BACKUP_PLIST" 2>/dev/null || true

APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  killall Siren 2>/dev/null || true
  if [[ -f "$BACKUP_PLIST" ]]; then
    defaults import "$BUNDLE_ID" "$BACKUP_PLIST" 2>/dev/null || true
    rm -f "$BACKUP_PLIST"
  fi
}
trap cleanup EXIT

# Helper: configure deterministic workspace preferences before launching Siren
configure_prefs() {
  local theme_index="$1" # 1 = Light, 2 = Dark
  local active_tab="$2"  # 0 = markdown-guide.md, 1 = mermaid-examples.md
  defaults write "$BUNDLE_ID" "flutter.explorer_root_path" -string "$REPO_ROOT"
  defaults write "$BUNDLE_ID" "flutter.open_file_paths" -array \
    "$REPO_ROOT/docs/markdown-guide.md" \
    "$REPO_ROOT/docs/mermaid-examples.md" \
    "$REPO_ROOT/docs/features.md" \
    "$REPO_ROOT/README.md"
  defaults write "$BUNDLE_ID" "flutter.active_tab_index" -int "$active_tab"
  defaults write "$BUNDLE_ID" "flutter.font_size" -float 14.0
  defaults write "$BUNDLE_ID" "flutter.is_rendered_view" -bool true
  defaults write "$BUNDLE_ID" "flutter.show_frontmatter" -bool true
  defaults write "$BUNDLE_ID" "flutter.sidebar_width" -float 250.0
  defaults write "$BUNDLE_ID" "flutter.is_explorer_visible" -bool true
  defaults write "$BUNDLE_ID" "flutter.theme_mode" -int "$theme_index"
  defaults write "$BUNDLE_ID" "flutter.include_patterns" -array
  defaults write "$BUNDLE_ID" "flutter.exclude_patterns" -array
}

capture_window() {
  local out_file="$1"
  screencapture -o -l "$WID" "$out_file"
  echo "  ✓ Captured $(basename "$out_file")"
}

click_rel() {
  local dx="$1"
  local dy="$2"
  "$REPO_ROOT/tool/click_at" "$((WIN_X + dx))" "$((WIN_Y + dy))"
}

echo "==> Step 1: Launching Siren in Light Mode for Light theme capture..."
killall Siren 2>/dev/null || true
sleep 0.5
configure_prefs 1 0
"$APP_BIN" --standard-window >/dev/null 2>&1 &
APP_PID=$!
sleep 3.5

WIN_INFO="$("$REPO_ROOT/tool/find_window" 2>&1 | awk '/Owner: Siren ID:/{flag=1} flag{print; if (/}/) exit}')"
WID="$(echo "$WIN_INFO" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')"
WIN_X="$(echo "$WIN_INFO" | awk -F'= ' '/X =/{gsub(/;/,"",$2); print int($2)}')"
WIN_Y="$(echo "$WIN_INFO" | awk -F'= ' '/Y =/{gsub(/;/,"",$2); print int($2)}')"
echo "    Window ID=$WID at ($WIN_X, $WIN_Y)"

capture_window "$SCREENSHOT_DIR/siren_comprehensive_light.png"

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""
sleep 0.8

echo "==> Step 2: Launching Siren in Dark Mode for main views & modals..."
configure_prefs 2 0
"$APP_BIN" --standard-window >/dev/null 2>&1 &
APP_PID=$!
sleep 3.5

WIN_INFO="$("$REPO_ROOT/tool/find_window" 2>&1 | awk '/Owner: Siren ID:/{flag=1} flag{print; if (/}/) exit}')"
WID="$(echo "$WIN_INFO" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')"
WIN_X="$(echo "$WIN_INFO" | awk -F'= ' '/X =/{gsub(/;/,"",$2); print int($2)}')"
WIN_Y="$(echo "$WIN_INFO" | awk -F'= ' '/Y =/{gsub(/;/,"",$2); print int($2)}')"
echo "    Window ID=$WID at ($WIN_X, $WIN_Y)"

# 2a. Dark Mode Rendered Preview & Spliced Hero Banner
capture_window "$SCREENSHOT_DIR/siren_comprehensive_dark.png"
cp "$SCREENSHOT_DIR/siren_comprehensive_dark.png" "$SCREENSHOT_DIR/siren_comprehensive_rendered.png"
echo "  ✓ Copied siren_comprehensive_rendered.png"

"$REPO_ROOT/tool/splice_images" \
  "$SCREENSHOT_DIR/siren_comprehensive_light.png" \
  "$SCREENSHOT_DIR/siren_comprehensive_dark.png" \
  "$SCREENSHOT_DIR/siren_theme_split.png"
echo "  ✓ Spliced siren_theme_split.png"

# 2b. Outline View (click Sidebar 'Outline' tab at dx=125, dy=68)
click_rel 125 68
sleep 1.0
capture_window "$SCREENSHOT_DIR/siren_outline_view.png"

# 2c. Global Search View (click Sidebar 'Search' tab at dx=208, dy=68)
click_rel 208 68
sleep 0.8
osascript -e 'tell application "System Events" to keystroke "Mermaid"'
sleep 1.2
capture_window "$SCREENSHOT_DIR/siren_search_view.png"

# Return Sidebar to 'Explorer' tab (dx=42, dy=68)
click_rel 42 68
sleep 0.6

# 2d. Raw Markdown View (click 'Show Source' <> button in toolbar at dx=1054, dy=24)
click_rel 1054 24
sleep 1.0
capture_window "$SCREENSHOT_DIR/siren_raw_view.png"

# Return to Rendered Preview (dx=1054, dy=24)
click_rel 1054 24
sleep 0.8

# 2e. Quick Open Modal (File -> Go to File...)
osascript -e 'tell application "System Events" to tell process "Siren" to click menu item "Go to File..." of menu "File" of menu bar 1'
sleep 0.8
osascript -e 'tell application "System Events" to keystroke "guide"'
sleep 0.8
capture_window "$SCREENSHOT_DIR/siren_quick_open.png"
# Dismiss Quick Open by clicking outside the modal backdrop (dx=100, dy=700)
click_rel 100 700
sleep 0.8

# 2f. Desktop Settings Dialog (Siren -> Settings...)
osascript -e 'tell application "System Events" to tell process "Siren" to click menu item "Settings..." of menu "Siren" of menu bar 1'
sleep 1.0
capture_window "$SCREENSHOT_DIR/siren_settings_dialog.png"
# Close Settings Dialog via top-right X button (dx=882, dy=134)
click_rel 882 134
sleep 0.8

# 2g. About Siren Dialog & Open Source Licenses View (Siren -> About Siren)
osascript -e 'tell application "System Events" to tell process "Siren" to click menu item "About Siren" of menu "Siren" of menu bar 1'
sleep 1.0
capture_window "$SCREENSHOT_DIR/siren_about_dialog.png"

# Click 'View Open Source Licenses' button inside AboutSirenDialog (dx=330, dy=632)
click_rel 330 632
sleep 1.5
capture_window "$SCREENSHOT_DIR/siren_licenses_view.png"

# Close About Dialog via top-right X button (dx=952, dy=164)
click_rel 952 164
sleep 0.8

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""
sleep 0.8

echo "==> Step 3: Launching Siren on docs/mermaid-examples.md for Mermaid Inspector..."
configure_prefs 2 1
"$APP_BIN" --standard-window >/dev/null 2>&1 &
APP_PID=$!
sleep 4.5

WIN_INFO="$("$REPO_ROOT/tool/find_window" 2>&1 | awk '/Owner: Siren ID:/{flag=1} flag{print; if (/}/) exit}')"
WID="$(echo "$WIN_INFO" | head -n 1 | sed -E 's/.*ID: ([0-9]+).*/\1/')"
WIN_X="$(echo "$WIN_INFO" | awk -F'= ' '/X =/{gsub(/;/,"",$2); print int($2)}')"
WIN_Y="$(echo "$WIN_INFO" | awk -F'= ' '/Y =/{gsub(/;/,"",$2); print int($2)}')"

# Click inside the rendered Flowchart diagram card to open MermaidZoomDialog (dx=700, dy=580)
click_rel 700 580
sleep 1.2
capture_window "$SCREENSHOT_DIR/siren_mermaid_viewer.png"

echo "==> All 12 release screenshots captured in $SCREENSHOT_DIR!"
