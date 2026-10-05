# GitHub Copilot Instructions

When assisting with the **Siren** codebase, follow the project-specific architecture, coding rules, invariants, and quality gates defined in:

👉 **[AGENTS.md](../AGENTS.md)**

Key rules at a glance:
- **Zero Analysis Issues**: Code must pass `flutter analyze` with 0 issues.
- **Pass All Tests**: Verify changes with `flutter test`.
- **Single-Tab Invariant**: Never open duplicate tabs for the same file; focus the existing tab.
- **Asset Separation**: Screenshots go in `docs/screenshots/`, not in `assets/`.
- **Bounded Constraints**: Avoid unbounded scrollviews over `Expanded` widgets.
