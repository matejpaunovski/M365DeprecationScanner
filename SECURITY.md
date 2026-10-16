# Security policy

## What the scanner does and does not do

M365DeprecationScanner is a read-only static analysis tool.

- **It never executes the scripts it scans.** Scripts are parsed with the PowerShell parser (`System.Management.Automation.Language.Parser`). No code from a scanned file runs, and no module named in it is imported.
- **It makes no network calls.** The rule database ships with the module. No telemetry, no update checks.
- **It needs no tenant access.** No credentials, tokens or connections to Microsoft 365, Entra ID or Azure.
- **It only writes files you ask for**: reports via `Export-M365DeprecationReport -Path` and settings files via `New-M365DeprecationAnalyzerSettings`. Existing files are only overwritten with `-Force`.

### GitHub Action

- All Action inputs are passed to the PowerShell script as **environment variables**. They are never inserted into script text, so values from a pull request cannot inject PowerShell code.
- The Action needs no secrets. `contents: read` is enough. Add `security-events: write` only if you upload SARIF.
- Pin the Action to a release tag or a commit SHA if your policy requires it.

### Custom rule files

`StringLiteral` rules are .NET regular expressions. Each match has a 1 second timeout, so a badly written pattern cannot hang a scan. Only load rule files you trust, as you would with any configuration.

## Supported versions

Security fixes go into the latest release. Please update before reporting.

## Reporting a vulnerability

Please **do not open a public issue**.

Report it privately through GitHub: [Report a vulnerability](https://github.com/matejpaunovski/M365DeprecationScanner/security/advisories/new) (repository **Security** tab, then **Report a vulnerability**).

Please include:

- what you found and the impact,
- steps or a minimal script to reproduce,
- module version (`(Get-Module M365DeprecationScanner).Version`) and `$PSVersionTable.PSVersion`.

Remove tenant names, credentials and other secrets from anything you send.

The maintainer aims to answer within a few days. Once fixed, the advisory is published and you are credited, unless you prefer not to be.
