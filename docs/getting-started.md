# Getting started

This guide takes you from "never used it" to "I know which scripts break" in about five minutes.

M365DeprecationScanner reads your PowerShell scripts and lists every command, parameter, module or endpoint that Microsoft has retired or deprecated. For each finding it tells you what to use instead.

Your scripts are only parsed, never executed. The scanner does not connect to your tenant and does not need internet access.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 (Windows, Linux or macOS)
- No Microsoft 365 modules needed. The scanner works even if MSOnline or AzureAD are not installed.

## Install

From the PowerShell Gallery (PowerShell 7.4+ or PSResourceGet installed):

```powershell
Install-PSResource -Name M365DeprecationScanner -Scope CurrentUser
```

On Windows PowerShell 5.1 use `Install-Module` instead:

```powershell
Install-Module -Name M365DeprecationScanner -Scope CurrentUser
```

Or run it straight from a clone of the repository:

```powershell
git clone https://github.com/matejpaunovski/M365DeprecationScanner.git
```

```powershell
Import-Module ./M365DeprecationScanner/src/M365DeprecationScanner
```

## Your first scan

Scan one script:

```powershell
Invoke-M365DeprecationScan -Path .\Get-Licenses.ps1
```

Scan a whole folder including sub folders:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse
```

Without `-Path` the scanner uses the current folder. Folders are scanned for `*.ps1` and `*.psm1` files. A file you name explicitly is always scanned, whatever its extension.

Want to try it first? The repository has a deliberately old script:

```powershell
Invoke-M365DeprecationScan -Path .\examples\legacy-script.ps1
```

You can also check a snippet without saving it:

```powershell
Invoke-M365DeprecationScan -ScriptDefinition 'Connect-MsolService; Get-MsolUser -All'
```

## Reading the output

The default view is a table:

| Column | Meaning |
|---|---|
| File | File name (`<script>` for `-ScriptDefinition`) |
| Line | Line number of the finding |
| Severity | How urgent it is (see below) |
| RuleId | Stable id of the rule, for example `MSOL0003` |
| Found | What was found, for example `Get-MsolUser` or `Connect-ExchangeOnline -UseRPSSession` |
| Use instead | The replacement |

Severity comes from the rule status:

| Status | Severity | What it means |
|---|---|---|
| Retired | Error | No longer works. Fix now. |
| Deprecated | Warning | Still works, but support has ended or retirement is announced. Fix soon. |
| Announced | Information | Retirement announced for a future date. Plan ahead. |

Every finding has more details: migration notes, the replacement module, the retirement date and links to the official Microsoft source. Show them with `Format-List`:

```powershell
Invoke-M365DeprecationScan -Path .\Get-Licenses.ps1 | Format-List
```

The results are normal PowerShell objects. You can sort, group and filter them:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Group-Object Path | Sort-Object Count -Descending
```

## Filtering

| Parameter | What it does | Example |
|---|---|---|
| `-MinimumSeverity` | Only `Warning` and up, or only `Error` | `-MinimumSeverity Error` |
| `-Area` | Only certain product areas | `-Area MSOnline, AzureAD` |
| `-ExcludeRuleId` | Ignore specific rules | `-ExcludeRuleId OTHER0001` |
| `-Include` | File name patterns inside folders (default `*.ps1`, `*.psm1`) | `-Include *.ps1` |
| `-Exclude` | Wildcards matched against the full file path | `-Exclude '*\tests\*'` |
| `-Recurse` | Also scan sub folders | `-Recurse` |

Valid areas: `MSOnline`, `AzureAD`, `ExchangeOnline`, `MicrosoftGraph`, `AzureADGraph`, `Azure`, `Teams`, `SharePoint`, `Intune`, `Other`.

Only show what is already broken:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -MinimumSeverity Error
```

Skip test and archive folders:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -Exclude '*\tests\*', '*\archive\*'
```

Forward slashes work on every operating system, so `'*/tests/*'` is a safe choice for scripts that run on Windows and Linux.

## Looking up a single command

"What do I use instead of X?" Ask `Get-M365DeprecationRule`:

```powershell
Get-M365DeprecationRule -Name Get-MsolUser
```

This also works for module names:

```powershell
Get-M365DeprecationRule -Name AzureAD | Format-List
```

If nothing is returned, the scanner has no rule for that name. Browse all rules in [rules.md](rules.md) or list them by area:

```powershell
Get-M365DeprecationRule -Area ExchangeOnline
```

## Typical workflow: migrating a script folder

1. Get an overview and share it with your team:

   ```powershell
   Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html
   ```

2. Fix the errors first. Retired items are already broken:

   ```powershell
   Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -MinimumSeverity Error
   ```

3. Open one script and read the details for each finding with `Format-List`. Check the linked source before you change anything. New cmdlets often have different parameters and return different objects.
4. Rewrite the script and test it against a test tenant or with read-only commands first.
5. Scan the script again until it is clean.
6. Keep it clean: add the [VS Code integration](vscode.md) so new problems show up while you type, and the [GitHub Action](github-action.md) so they show up in pull requests.

The scanner does not rewrite code for you. That is on purpose: replacements often take different parameters and return different objects, so a blind search-and-replace would break scripts in subtle ways.

## Common problems

**`Invoke-M365DeprecationScan` is not recognised.** The module is not loaded. Run `Import-Module M365DeprecationScanner` (or the path to `src/M365DeprecationScanner` in a clone).

**Warning "has N syntax error(s), results may be incomplete".** The file does not parse cleanly. The scanner still reports what it can find. Fix the syntax error to get complete results.

**A finding is a false positive.** Suppress it narrowly, see [suppressions.md](suppressions.md), and please [open an issue](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new/choose).

**A deprecated command is not found.** Check `Get-M365DeprecationRule -Name <command>`. If there is no rule, suggest one via an issue or a pull request, see [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-changing-a-rule). The scanner also cannot resolve dynamic code such as `& $commandName` or `Import-Module $moduleName`.

## Next steps

- [VS Code integration](vscode.md)
- [GitHub Action and Azure DevOps](github-action.md)
- [Reports](reports.md)
- [Suppressing findings](suppressions.md)
- [Custom rules](custom-rules.md)
