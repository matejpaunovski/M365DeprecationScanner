<div align="center">

# M365 Deprecation Scanner

**Find the PowerShell code that Microsoft has already switched off, or is about to.**

Scans your scripts for retired and deprecated Microsoft 365, Entra ID and Azure commands
(MSOnline, AzureAD, Exchange Online RPS, AzureRM, Azure AD Graph, ...) and tells you exactly what to use instead.

[![CI](https://github.com/matejpaunovski/M365DeprecationScanner/actions/workflows/ci.yml/badge.svg)](https://github.com/matejpaunovski/M365DeprecationScanner/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/M365DeprecationScanner?label=PSGallery)](https://www.powershellgallery.com/packages/M365DeprecationScanner)
![PowerShell 5.1 | 7+](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Quick start](#quick-start) · [VS Code](#2-in-vs-code) · [GitHub Action](#3-in-cicd-github-action) · [Rule catalog](docs/rules.md) · [Deutsch](README.de.md)

</div>

---

## Why?

Microsoft keeps retiring PowerShell modules and cmdlets: **MSOnline** and **AzureAD** are gone,
Exchange Online **Remote PowerShell** is switched off, `Get-MessageTrace` is being replaced, the
**Azure AD Graph** API is retired, **AzureRM** is history...

Most organisations still have dozens or hundreds of old scripts on file shares, in scheduled tasks
and in Azure Automation. Nobody knows which of them are broken already, or which will break next.

**M365 Deprecation Scanner answers that in seconds:**

```text
PS> Invoke-M365DeprecationScan -Path .\examples\legacy-script.ps1

File              Line Severity RuleId   Found                                 Use instead
----              ---- -------- ------   -----                                 -----------
legacy-script.ps1    9 Error    MSOL0001 #Requires -Modules MSOnline           Microsoft Graph PowerShell SDK (or Microsoft Entra PowerShell)
legacy-script.ps1   15 Error    MSOL0002 Connect-MsolService                   Connect-MgGraph
legacy-script.ps1   16 Error    AAD0003  Connect-AzureAD                       Connect-MgGraph
legacy-script.ps1   17 Error    EXO0002  Connect-ExchangeOnline -UseRPSSession Connect-ExchangeOnline (without -UseRPSSession)
legacy-script.ps1   20 Error    MSOL0003 Get-MsolUser                          Get-MgUser
legacy-script.ps1   28 Error    AAD0032  Get-AzureADGroupMember                Get-MgGroupMember
legacy-script.ps1   32 Warning  EXO0005  Get-MessageTrace                      Get-MessageTraceV2
legacy-script.ps1   36 Warning  AZ0004   Login-AzureRmAccount                  Connect-AzAccount
legacy-script.ps1   41 Error    AADG0001 graph.windows.net                     Microsoft Graph (https://graph.microsoft.com)
...
```

Try it yourself: [examples/legacy-script.ps1](examples/legacy-script.ps1) is a typical old admin script,
[examples/modern-script.ps1](examples/modern-script.ps1) does the same with current modules and has zero findings.

## What it finds

| Area | Examples (old → new) |
|---|---|
| **MSOnline** | `Connect-MsolService` → `Connect-MgGraph`, `Get-MsolUser` → `Get-MgUser` |
| **AzureAD / AzureADPreview** | `Connect-AzureAD` → `Connect-MgGraph`, `Get-AzureADGroupMember` → `Get-MgGroupMember` |
| **Exchange Online** | `Connect-ExchangeOnline -UseRPSSession`, `Get-MessageTrace` → `Get-MessageTraceV2`, `Search-AdminAuditLog` |
| **Azure AD Graph** | `https://graph.windows.net/...` → `https://graph.microsoft.com/...` |
| **AzureRM** | `Login-AzureRmAccount` → `Connect-AzAccount`, `Get-AzureRm*` → `Get-Az*` |
| **Microsoft Graph SDK v1** | `Select-MgProfile` → `Microsoft.Graph.Beta` module |
| **Teams, SharePoint** | `SkypeOnlineConnector`, `New-CsOnlineSession`, `SharePointPnPPowerShellOnline`, `Connect-PnPOnline -ClientSecret` (ACS) |

It understands PowerShell, it does not just grep. It detects:

- **commands**, also module-qualified (`MSOnline\Get-MsolUser`) and inside functions or pipelines
- **parameters** on specific commands (`Connect-ExchangeOnline -UseRPSSession`)
- **modules** in `Import-Module`, `Install-Module`, `#Requires -Modules` and `using module`
- **endpoints** in strings (`'https://graph.windows.net/...'`)

Comments are ignored. **Your scripts are never executed**, only parsed. No tenant connection and no internet access needed.

Every rule links to an **official Microsoft source**. See the full [rule catalog](docs/rules.md).

## Quick start

```powershell
Install-PSResource M365DeprecationScanner      # or: Install-Module M365DeprecationScanner -Scope CurrentUser

Invoke-M365DeprecationScan -Path C:\Scripts -Recurse
```

Want details for each finding (migration notes, retirement date, source links)?

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Format-List
```

Just want to know what replaces one command?

```powershell
Get-M365DeprecationRule -Name Get-MsolUser | Format-List
```

## Three ways to use it

### 1. As a PowerShell command

```powershell
# Only things that are already broken
Invoke-M365DeprecationScan -Path . -Recurse -MinimumSeverity Error

# HTML report for your team (open in any browser)
Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html

# Excel
Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Csv -Path .\deprecations.csv
```

### 2. In VS Code

Deprecated commands are underlined **while you type**, with the replacement in the tooltip.

```powershell
New-M365DeprecationAnalyzerSettings -Path "$HOME\PSScriptAnalyzerSettings.psd1"
```

Then set `"powershell.scriptAnalysis.settingsPath"` in VS Code to that file. Details: [docs/vscode.md](docs/vscode.md).

### 3. In CI/CD (GitHub Action)

```yaml
- uses: actions/checkout@v5
- uses: matejpaunovski/M365DeprecationScanner@v0
  with:
    path: scripts
    fail-on: Error        # fail the build for retired commands only
```

You get annotations on the changed lines, a summary on the job page and an optional SARIF file for
GitHub code scanning. Details and an Azure DevOps example: [docs/github-action.md](docs/github-action.md).

## Severity

| Severity | Rule status | Meaning |
|---|---|---|
| **Error** | Retired | No longer works. Fix now. |
| **Warning** | Deprecated | Still works, but support has ended or retirement is announced. Fix soon. |
| **Information** | Announced | Retirement announced for a future date. Plan ahead. |

## Suppressing a finding

Sometimes a line is fine on purpose (for example a migration script that *reads* old data):

```powershell
Connect-MsolService   # m365ds-ignore: MSOL0002 - legacy tenant, removed in Q1
```

Also available: `# m365ds-ignore-next-line` and `# m365ds-ignore-file`. See [docs/suppressions.md](docs/suppressions.md).

## Your own rules

Retired an internal helper function or an old API endpoint? Add your own rule file and the scanner
flags it everywhere: [docs/custom-rules.md](docs/custom-rules.md).

```powershell
Invoke-M365DeprecationScan -Path . -Recurse -CustomRulePath .\our-rules.json
```

## Documentation

| | |
|---|---|
| [Getting started](docs/getting-started.md) | Install, first scan, filters, migration workflow |
| [VS Code](docs/vscode.md) | Squiggles in the editor via PSScriptAnalyzer |
| [GitHub Action & Azure DevOps](docs/github-action.md) | Inputs, outputs, SARIF, examples |
| [Reports](docs/reports.md) | HTML, Markdown, CSV, JSON, SARIF |
| [Suppressions](docs/suppressions.md) | Ignore single lines, files or rules |
| [Custom rules](docs/custom-rules.md) | Flag your own deprecated code |
| [Rule catalog](docs/rules.md) | Every rule with replacement and source |
| [How it works](docs/how-it-works.md) | Architecture, for contributors |

## FAQ

**Does it run my scripts?**
No. Scripts are parsed with the PowerShell parser, nothing is executed or imported.

**Does it need access to my tenant or the internet?**
No. Everything runs locally against the rule database shipped with the module.

**Does it work on Windows PowerShell 5.1?**
Yes. Windows PowerShell 5.1 and PowerShell 7+ on Windows, Linux and macOS. The GitHub Action needs PowerShell 7 (pre-installed on GitHub runners).

**Can it fix my scripts automatically?**
No, on purpose. The replacements often have different parameters, permissions and output objects
(for example `Get-MsolUser` → `Get-MgUser`). A blind rename produces code that *looks* right and
fails at runtime. The scanner tells you where to look and links the migration guidance.

**How current are the rules?**
Each rule cites an official Microsoft source, and CI checks the database on every change. The
[rule catalog](docs/rules.md) shows the last update date. Found something missing or wrong?
[Open an issue](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new?template=new-rule.yml), it takes a minute.

## Contributing

Contributions are very welcome, especially **new rules**: every rule makes the tool more useful for everyone.
See [CONTRIBUTING.md](CONTRIBUTING.md). In short:

```powershell
git clone https://github.com/matejpaunovski/M365DeprecationScanner
cd M365DeprecationScanner
./build.ps1 -Task Bootstrap   # installs Pester 5 and PSScriptAnalyzer
./build.ps1                   # analyze + docs check + tests
```

## Credits

Created by **Matej**, built with the support of [Claude](https://claude.ai) (Anthropic) as an AI coding assistant.
Rule research, code reviews and the security audit were done with Claude and checked against official Microsoft sources.

## License

[MIT](LICENSE). Not affiliated with or endorsed by Microsoft. Product names are trademarks of their respective owners.
Always check the linked source before changing production scripts.
