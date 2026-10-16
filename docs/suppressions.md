# Suppressing findings

Sometimes a finding is correct but you cannot fix it right now. Or it is a false positive. You can hide it in three ways:

| Way | Works in | Scope |
|---|---|---|
| `# m365ds-ignore...` comments | Command, VS Code, GitHub Action | One line, the next line, or the whole file |
| `SuppressMessageAttribute` | PSScriptAnalyzer / VS Code only | A function, script or param block |
| `-ExcludeRuleId` / `exclude-rule-ids` | Command, GitHub Action | One rule everywhere in this scan |

**Rule of thumb:** suppress as narrowly as possible, always name the rule id, and write down why.

## Suppression comments

| Comment | Suppresses |
|---|---|
| `# m365ds-ignore` | findings on the same line |
| `# m365ds-ignore-next-line` | findings on the line after the comment |
| `# m365ds-ignore-file` | findings in the whole file (place it anywhere in the file) |

Without ids, a comment suppresses **all** rules. Add a colon and one or more rule ids to suppress only those:

```powershell
Get-MsolUser -All # m365ds-ignore: MSOL0003 - read-only export, replaced in ticket IT-4711
```

```powershell
# m365ds-ignore-next-line: MSOL0003, MSOL0004 - legacy tenant, decommissioned in Q3
Get-MsolUser -All | Set-MsolUser -UsageLocation DE
```

```powershell
# m365ds-ignore-file: AADG0001 - this script documents the old API on purpose
```

Details:

- Ids are case-insensitive and separated by commas: `msol0003, MSOL0004` works.
- Find the id in the `RuleId` column of the scan output.
- The comment can be a line comment (`#`) or a block comment (`<# ... #>`).
- A finding counts for the line where it **starts**.
- A misspelled comment (for example `m365ds-ignore-nextline`) suppresses **nothing**, so typos show up instead of silently hiding findings.

### Writing the reason

Put the reason **after** the ids, separated by a dash:

```powershell
# m365ds-ignore-next-line: MSOL0003 - reason goes here
```

Do not put the reason directly after the colon. The first word after the colon is read as a rule id:

```powershell
Get-MsolUser # m365ds-ignore: legacy tenant
```

This looks like a suppression but does nothing: the scanner reads `legacy` as a rule id, and no rule has that id. The finding stays.

If you want a reason without ids, leave out the colon. This suppresses all rules on the line:

```powershell
Get-MsolUser # m365ds-ignore - legacy tenant, see IT-4711
```

## PSScriptAnalyzer attribute

In VS Code and with `Invoke-ScriptAnalyzer` you can also use the standard PSScriptAnalyzer attribute. Rule name and id:

- Rule name: `M365DeprecationScanner.Rules\Measure-M365Deprecation`
- Second argument (`RuleSuppressionId`): the rule id

```powershell
function Export-LegacyLicenseReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('M365DeprecationScanner.Rules\Measure-M365Deprecation', 'MSOL0003', Justification = 'Replaced in ticket IT-4711.')]
    param()
    Get-MsolUser -All
}
```

The attribute is ignored by `Invoke-M365DeprecationScan` and the GitHub Action. If you use more than one tool, prefer comments.

## Excluding a rule for the whole scan

On the command line:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -ExcludeRuleId OTHER0001
```

In the GitHub Action:

```yaml
      - uses: matejpaunovski/M365DeprecationScanner@v0
        with:
          exclude-rule-ids: OTHER0001
```

Excluding an exact rule does **not** make a broader wildcard rule fire instead. If you exclude the rule for `Get-MsolUser`, that command is simply not reported. See [how-it-works.md](how-it-works.md#filters-come-after-matching).

## Other ways to reduce noise

- Skip folders: `-Exclude '*\archive\*'` (GitHub Action: `exclude: '*/archive/*'`).
- Hide future announcements: `-MinimumSeverity Warning`.
- Limit to one product area: `-Area ExchangeOnline`.

## Good practice

- Name the rule id. A bare `# m365ds-ignore` also hides rules that are added later.
- Prefer `m365ds-ignore` / `-next-line` over `-file`.
- Always write a reason and, if you have one, a ticket number.
- Review suppressions now and then. Retired commands stop working whether they are suppressed or not.

## Found a false positive?

Please [open an issue](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new/choose) with a minimal script. Then the rule can be fixed for everyone.
