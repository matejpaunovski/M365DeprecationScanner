# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

Rule database changes (new or corrected rules) are listed under **Rules**.

## [Unreleased]

## [0.1.0] - 2026-10-16

### Added

- `Invoke-M365DeprecationScan`: scans files, folders or code strings for deprecated and retired commands, parameters, modules and endpoints. Nothing is executed; scripts are only parsed.
- `Get-M365DeprecationRule`: lists rules and answers "what replaces X?" (`Get-M365DeprecationRule -Name Get-MsolUser`).
- `Export-M365DeprecationReport`: HTML, Markdown, CSV, JSON and SARIF reports.
- PSScriptAnalyzer custom rule (`Measure-M365Deprecation`) so findings appear directly in VS Code, plus `New-M365DeprecationAnalyzerSettings` and `Get-M365DeprecationAnalyzerRulePath` for one-command setup.
- GitHub Action with annotations, job summary, SARIF for code scanning and a configurable failure threshold.
- Suppression comments: `# m365ds-ignore`, `# m365ds-ignore-next-line`, `# m365ds-ignore-file`, each optionally limited to rule ids.
- Custom rule files (`-CustomRulePath`) for organisation-specific deprecations.
- Works on Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS.

### Rules

- Initial rule database covering MSOnline, AzureAD/AzureADPreview, Exchange Online, Azure AD Graph, AzureRM, Microsoft Graph PowerShell SDK, Teams and SharePoint. See [docs/rules.md](docs/rules.md).

[Unreleased]: https://github.com/matejpaunovski/M365DeprecationScanner/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/matejpaunovski/M365DeprecationScanner/releases/tag/v0.1.0
