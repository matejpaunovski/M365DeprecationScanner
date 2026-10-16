# VS Code integration

See deprecated commands while you type. The scanner ships a [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) custom rule. The PowerShell extension for VS Code runs PSScriptAnalyzer in the background, so findings show up as squiggles and in the **Problems** panel.

It uses the same engine as `Invoke-M365DeprecationScan`, so you get the same findings.

## Requirements

- The [PowerShell extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell) for VS Code
- M365DeprecationScanner installed, see [Getting started](getting-started.md#install)

## Setup in two steps

1. Create a settings file. This command writes `PSScriptAnalyzerSettings.psd1` in the current folder:

   ```powershell
   New-M365DeprecationAnalyzerSettings
   ```

   To use one file for all your projects, put it in your profile folder:

   ```powershell
   New-M365DeprecationAnalyzerSettings -Path "$HOME\PSScriptAnalyzerSettings.psd1" -Force
   ```

2. Point VS Code at the file. Open your settings (`Ctrl+,`, then the **Open Settings (JSON)** icon) and add:

   ```json
   {
     "powershell.scriptAnalysis.settingsPath": "PSScriptAnalyzerSettings.psd1"
   }
   ```

   A relative path is resolved against the workspace folder. For the profile file use the full path, for example `"C:\\Users\\you\\PSScriptAnalyzerSettings.psd1"`.

## Check that it works

1. Open `examples/legacy-script.ps1` from the repository, or any script with `Get-MsolUser` in it.
2. Wait a few seconds. `Get-MsolUser` gets a squiggle.
3. Hover over it. The message starts with the rule id, for example `[MSOL0003] ...`, and names the replacement.

Nothing shows up? Run **PowerShell: Restart Session** from the command palette (`Ctrl+Shift+P`).

## What the generated file contains

```powershell
@{
    CustomRulePath      = @('C:\Users\you\Documents\PowerShell\Modules\M365DeprecationScanner\0.1.0\Rules\M365DeprecationScanner.Rules.psm1')
    IncludeDefaultRules = $true
}
```

- `CustomRulePath` is the absolute path of the rule module inside the installed module.
- `IncludeDefaultRules = $true` keeps the normal PSScriptAnalyzer rules running. Use `-ExcludeDefaultRules` if you only want the deprecation rules.

**Important:** the path contains the module version folder. After you update the module, run the command again with `-Force`:

```powershell
New-M365DeprecationAnalyzerSettings -Force
```

## Combining with an existing settings file

Already have a `PSScriptAnalyzerSettings.psd1`? Do not overwrite it. Get the rule path:

```powershell
Get-M365DeprecationAnalyzerRulePath
```

Add the path to your file under `CustomRulePath`, and set `IncludeDefaultRules = $true`. Without it, PSScriptAnalyzer runs only the custom rules once `CustomRulePath` is set.

```powershell
@{
    Severity            = @('Error', 'Warning', 'Information')
    ExcludeRules        = @('PSAvoidUsingWriteHost')
    CustomRulePath      = @('<output of Get-M365DeprecationAnalyzerRulePath>')
    IncludeDefaultRules = $true
}
```

## Using PSScriptAnalyzer from the command line

You can run the rule without VS Code, for example in an existing PSScriptAnalyzer pipeline:

```powershell
Invoke-ScriptAnalyzer -Path .\MyScript.ps1 -CustomRulePath (Get-M365DeprecationAnalyzerRulePath)
```

Deprecation rules plus all default rules:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -CustomRulePath (Get-M365DeprecationAnalyzerRulePath) -IncludeDefaultRules
```

The rule name is `M365DeprecationScanner.Rules\Measure-M365Deprecation`. Severities map 1:1: Retired is `Error`, Deprecated is `Warning`, Announced is `Information`.

## Suppressing findings

Both ways work in VS Code.

With a comment on the line (also works for `Invoke-M365DeprecationScan` and the GitHub Action):

```powershell
Get-MsolUser -All # m365ds-ignore: MSOL0003 - read-only report, replaced in Q3
```

With the PSScriptAnalyzer attribute. The second argument is the rule id:

```powershell
function Get-OldReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('M365DeprecationScanner.Rules\Measure-M365Deprecation', 'MSOL0003', Justification = 'Replaced in Q3.')]
    param()
    Get-MsolUser -All
}
```

The attribute only works in PSScriptAnalyzer. Comments work everywhere. Details: [suppressions.md](suppressions.md).

## Common problems

**No squiggles after a module update.** The settings file still points at the old version folder. Run `New-M365DeprecationAnalyzerSettings -Force`.

**The default PSScriptAnalyzer warnings disappeared.** Your settings file has `CustomRulePath` but no `IncludeDefaultRules = $true`.

**My custom rules do not show up in VS Code.** The PSScriptAnalyzer rule uses the built-in rule database only. Custom rule files work with `Invoke-M365DeprecationScan` and the GitHub Action, see [custom-rules.md](custom-rules.md).

**`New-M365DeprecationAnalyzerSettings` fails with "already exists".** Add `-Force` to overwrite the file.
