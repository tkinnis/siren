# Contributing to Siren

Thank you for your interest in contributing to **Siren**! This document outlines our issue-driven workflow, development environment setup, architectural invariants, and quality gates.

---

## 1. Issue-First Workflow

All bug fixes, feature additions, and architectural improvements are tracked through [GitHub Issues](https://github.com/tkinnis/siren/issues).

1. **Search Existing Issues**: Before starting work, check [open issues](https://github.com/tkinnis/siren/issues) or run `gh issue list` to see if the bug or feature is already tracked.
2. **Create an Issue**:
   * **Bug Reports**: Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md) with reproduction steps and Siren version.
   * **Feature Requests**: Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md) describing the problem and proposed solution.
   * **Via CLI**:
     ```bash
     gh issue create --title "feat(scope): short summary" --label "enhancement" --body "..."
     ```
3. **Link Commits & Pull Requests**: Reference the tracking issue in your commit message footer or pull request description using `Closes #<id>` (to auto-close on merge) or `Refs #<id>`.

---

## 2. Development Setup

### Prerequisites
* **OS**: macOS 13.0 (Ventura) or newer
* **Flutter SDK**: Flutter 3.47+ (Dart 3.x)
* **Xcode**: Full Xcode installation with CocoaPods (`sudo gem install cocoapods`)

### Getting Started
```bash
# Clone the repository
git clone https://github.com/tkinnis/siren.git
cd siren

# Fetch Dart/Flutter dependencies and bundled ripgrep binary
flutter pub get
dart run hook/build.dart

# Run Siren in debug mode on macOS
flutter run -d macos
```

---

## 3. Core Architectural Invariants

When modifying or adding code, please preserve the following invariants (see [`AGENTS.md`](AGENTS.md) for full details):

* **State Management**: Siren uses `package:provider` with `AppState` (`ChangeNotifier`). Do not introduce secondary state management libraries.
* **Single-Tab Invariant**: An open file must **never** be duplicated into a second tab. Always inspect `appState.openFiles` and switch to the existing tab index if the file is already open.
* **Strict Asset Separation**:
  * Runtime assets bundled into the macOS app reside strictly in `assets/`.
  * Documentation and verification screenshots reside in `docs/screenshots/` and must **never** be added to `pubspec.yaml` assets.
* **Bounded Desktop Layout Constraints**: All modals, dialogs, and floating sheets must have bounded dimensions (`SizedBox` or `ConstrainedBox`). Never wrap unbounded scrolling widgets around `Expanded` or `Flexible` children without explicit height constraints.
* **Responsive Non-Blocking UI**: Expensive disk traversal, full-text searches (`rg`), and regex indexing must execute in background Dart isolates or detached processes.

---

## 4. Verification & Quality Gates

Every change must pass all three quality gates before merge:

```bash
# 1. Code Formatting
dart format --output=none --set-exit-if-changed lib test

# 2. Static Analysis (must report 0 warnings or errors)
flutter analyze

# 3. Automated Test Suite (100% pass rate required)
flutter test
```

When fixing a bug or adding a feature, include unit or widget tests in `test/` to prevent regressions, and update relevant user documentation in `docs/` (`features.md`, `shortcuts.md`, `markdown-guide.md`, `README.md`).

---

## 5. Commit & Release Conventions

* **Conventional Commits**:
  * `feat(scope): ...` for new features
  * `fix(scope): ...` for bug fixes
  * `docs(scope): ...` for documentation updates
  * `refactor(scope): ...` for structural refactors
  * `test(scope): ...` for test additions or improvements
  * `ci(scope): ...` / `chore(scope): ...` for build and repository maintenance
* **Release Naming Convention**:
  * **Git Tag**: `v<version>` (e.g., `v0.4.0`)
  * **GitHub Release Title**: `Siren v<version>` (e.g., `Siren v0.4.0`)
  * **Release Asset Archive**: `Siren-v<version>-macos.zip` (e.g., `Siren-v0.4.0-macos.zip`)

---

## 6. Code of Conduct

Participation in this project is governed by our [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
