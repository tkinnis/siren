# Security Policy

## Supported Versions

Security updates are applied to the latest minor release of **Siren**.

| Version | Supported |
| :--- | :--- |
| `0.4.x` | :white_check_mark: |
| `< 0.4.0` | :x: |

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, report vulnerabilities privately through GitHub's **Private Vulnerability Reporting**:

1. Navigate to the [**Report a vulnerability**](https://github.com/tkinnis/siren/security/advisories/new) page on the `tkinnis/siren` repository.
2. Provide a clear description of the vulnerability, affected version(s), and a minimal proof-of-concept or Markdown payload demonstrating the issue.
3. You will receive an acknowledgment within **72 hours**, followed by an assessment and remediation timeline.

## Security Architecture Notes

* **Local-First Execution**: Siren operates locally on your macOS filesystem and does not transmit workspace contents or telemetry to external servers.
* **Markdown & HTML Rendering**: Embedded GFM HTML constructs (`<kbd>`, `<details>`, `<table>`, `<dl>`, `<picture>`, `<img>`) are converted into native Flutter widgets or Markdown AST nodes rather than executing arbitrary browser DOM scripts.
* **Subprocess Isolation**: Workspace full-text search executes the bundled `rg` (ripgrep) binary directly via `Process.start` with explicit argument arrays (never via shell interpolation) to prevent command injection.
