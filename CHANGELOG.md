# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

Rule database changes (new or corrected rules) are listed under **Rules**.

## [Unreleased]

## [0.3.0] - 2026-10-17

### Added

- `Invoke-M365DeprecationScan` confirms a clean scan, for example "No deprecated or retired commands found in 12 file(s).", instead of returning silently. The line goes to the console, not the pipeline; hide it with `-InformationAction SilentlyContinue`.
- A warning when no files were scanned at all, for example a folder whose scripts are only in sub folders and `-Recurse` was not given.

### Changed

- The release workflow now moves the major version tag (`v0`) to each new release, so `uses: matejpaunovski/M365DeprecationScanner@v0` always gets the latest 0.x version.
- CI uses `actions/checkout@v7` and `actions/upload-artifact@v7`.

## [0.2.1] - 2026-10-16

### Fixed

- Findings no longer show the internal `Extent` property in `Format-List`, `Select-Object *` or `ConvertTo-Json` output. The syntax-tree position is still available through the `GetExtent()` method.

## [0.2.0] - 2026-10-16

### Added

- Module manifests: retired modules in `RequiredModules` and `NestedModules` of `.psd1` files are now reported, both as plain names and as `@{ ModuleName = ... }` specifications. The same applies to `New-ModuleManifest` / `Update-ModuleManifest -RequiredModules / -NestedModules`.
- Folders are now scanned for `*.psd1` files by default (`-Include` and the GitHub Action `include` input default to `*.ps1, *.psm1, *.psd1`).
- Example manifest in `examples/legacy-module`.

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

[Unreleased]: https://github.com/matejpaunovski/M365DeprecationScanner/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/matejpaunovski/M365DeprecationScanner/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/matejpaunovski/M365DeprecationScanner/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/matejpaunovski/M365DeprecationScanner/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/matejpaunovski/M365DeprecationScanner/releases/tag/v0.1.0
