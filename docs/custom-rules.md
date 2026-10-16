# Custom rules

The built-in rules cover Microsoft's deprecations. Your organisation has its own: an old helper module everyone used to import, a retired internal function, an API endpoint that moved. Put those in your own rule file and the scanner finds them too.

## Quick example

Save as `contoso-rules.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/matejpaunovski/M365DeprecationScanner/main/src/M365DeprecationScanner/Data/deprecations.schema.json",
  "schemaVersion": 1,
  "lastUpdated": "2026-10-16",
  "rules": [
    {
      "id": "CONTOSO0001",
      "kind": "Command",
      "pattern": "Get-ContosoMailbox",
      "area": "Other",
      "status": "Retired",
      "title": "Get-ContosoMailbox was removed from the Contoso.Tools module.",
      "replacement": "Get-EXOMailbox",
      "replacementModule": "ExchangeOnlineManagement",
      "notes": "Use -Properties to request extra attributes.",
      "sources": ["https://wiki.contoso.com/it/tools/retirements"]
    }
  ]
}
```

Scan with it:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -CustomRulePath .\contoso-rules.json
```

Your rules run **together with** the built-in rules. To run only your rules, add `-ExcludeDefaultRules`:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -CustomRulePath .\contoso-rules.json -ExcludeDefaultRules
```

You can pass several files: `-CustomRulePath .\team-a.json, .\team-b.json`.

## File format

The file is JSON with three top-level fields: `schemaVersion` (always `1`), `lastUpdated` (`YYYY-MM-DD`) and `rules`. The `$schema` line is optional. It gives you auto-completion and validation in VS Code.

Fields per rule:

| Field | Required | Description |
|---|---|---|
| `id` | yes | Unique id: 2-8 upper-case letters plus 4 digits, for example `CONTOSO0001`. |
| `kind` | yes | `Command`, `Parameter`, `Module` or `StringLiteral` (see below). |
| `pattern` | yes | What to match. Names for Command/Parameter/Module (wildcards `*` and `?` allowed), a regular expression for StringLiteral. Always case-insensitive. |
| `command` | for `Parameter` | The command the parameter belongs to. Wildcards allowed. |
| `exclude` | no | Command/Module rules: names (wildcards allowed) the pattern must **not** match. Useful for valid commands caught by a broad catch-all. |
| `area` | yes* | `MSOnline`, `AzureAD`, `ExchangeOnline`, `MicrosoftGraph`, `AzureADGraph`, `Azure`, `Teams`, `SharePoint`, `Intune` or `Other`. |
| `status` | yes | `Retired` (Error), `Deprecated` (Warning) or `Announced` (Information). |
| `title` | yes | One short sentence describing the problem. End it with a period. |
| `replacement` | yes | What to use instead. |
| `sources` | yes* | List of `https://` links that back the rule. |
| `module` | no | The legacy module the item comes from. |
| `retirementDate` | no | `YYYY-MM-DD` or `YYYY-MM`. Shown in the message. |
| `replacementModule` | no | Module that contains the replacement. |
| `notes` | no | Migration hints: parameter differences, permissions, output changes. |

\* The scanner itself only insists on `id`, `kind`, `pattern`, `status`, `title` and `replacement`, and defaults `area` to `Other`. The JSON schema requires `area` and `sources` too. Fill them in anyway: they appear in every report.

The message users see is built from your rule: `<title> Use <replacement> instead. (Retirement: <retirementDate>)`.

## The four kinds

### Command

Matches command calls, also module-qualified ones like `Contoso.Tools\Get-ContosoMailbox`. Only real calls count. Mentions in comments are ignored.

```json
{
  "id": "CONTOSO0002",
  "kind": "Command",
  "pattern": "*-ContosoLegacy*",
  "area": "Other",
  "status": "Deprecated",
  "title": "The ContosoLegacy functions are deprecated.",
  "replacement": "The matching functions in Contoso.Tools 3.x",
  "sources": ["https://wiki.contoso.com/it/tools/contosolegacy"]
}
```

A wildcard rule like this is a **catch-all**. If an exact rule also matches, the exact rule wins. Among several wildcard rules, the longest pattern wins. Write exact rules for the commands where you can name a specific replacement, and one catch-all for the rest.

If a catch-all also hits commands that are fine, list them in `exclude`. The built-in `*-AzureRm*` rule does this for `Enable-AzureRmAlias`, which is a valid Az.Accounts cmdlet:

```json
"pattern": "*-ContosoLegacy*",
"exclude": ["Remove-ContosoLegacyData"],
```

### Parameter

Matches a parameter on a specific command. `pattern` is the parameter name **without** the dash.

```json
{
  "id": "CONTOSO0003",
  "kind": "Parameter",
  "command": "New-ContosoUser",
  "pattern": "LegacyLicense",
  "area": "Other",
  "status": "Deprecated",
  "retirementDate": "2027-03",
  "title": "The -LegacyLicense switch of New-ContosoUser is deprecated.",
  "replacement": "New-ContosoUser -LicenseGroup",
  "sources": ["https://wiki.contoso.com/it/tools/new-contosouser"]
}
```

This finds `New-ContosoUser -LegacyLicense` and `New-ContosoUser -LegacyLicense:$true`, but not `-LegacyLicense` on any other command. `-LegacyLicense:$false` explicitly turns the switch off and is not reported. The parameter must be written out in full. Abbreviations like `-LegacyLic` are not matched.

### Module

Matches the module name in `Import-Module`, `Install-Module`, `Update-Module`, `Save-Module`, `Install-PSResource`, `Update-PSResource`, `Save-PSResource`, `#Requires -Modules` and `using module`.

```json
{
  "id": "CONTOSO0004",
  "kind": "Module",
  "pattern": "Contoso.LegacyTools",
  "area": "Other",
  "status": "Retired",
  "title": "The Contoso.LegacyTools module is no longer distributed.",
  "replacement": "Contoso.Tools",
  "sources": ["https://wiki.contoso.com/it/tools/retirements"]
}
```

Only literal names are found. `Import-Module $name` cannot be resolved without running the script.

### StringLiteral

Matches a .NET regular expression against every string in the script, for example URLs. Comments are ignored. In JSON, escape backslashes: `\.` becomes `\\.`.

```json
{
  "id": "CONTOSO0005",
  "kind": "StringLiteral",
  "pattern": "https?://(api-old|legacy-api)\\.contoso\\.com",
  "area": "Other",
  "status": "Announced",
  "retirementDate": "2027-06-30",
  "title": "The old Contoso API host will be shut down.",
  "replacement": "https://api.contoso.com/v2",
  "notes": "v2 needs an Entra ID app registration instead of an API key.",
  "sources": ["https://wiki.contoso.com/it/api/v2-migration"]
}
```

This finds `'https://api-old.contoso.com/users'` and `"https://legacy-api.contoso.com/$tenant"`. Keep the regex specific. A loose pattern like `contoso` would flag half your scripts.

## Rule ids must be unique

Ids must be unique across **all** loaded files, including the built-in database. A duplicate stops the scan with an error that names both files.

Use your own prefix, for example `CONTOSO` or your company's short name. Never reuse an id for a different rule: people reference ids in suppression comments.

## Looking up your rules

`Get-M365DeprecationRule` accepts the same file:

```powershell
Get-M365DeprecationRule -Name Get-ContosoMailbox -CustomRulePath .\contoso-rules.json
```

## Where custom rules work

| Where | Custom rules |
|---|---|
| `Invoke-M365DeprecationScan` | Yes, with `-CustomRulePath` |
| `Get-M365DeprecationRule` | Yes, with `-CustomRulePath` |
| GitHub Action | Yes, with `custom-rule-path` (relative to the repository root) |
| VS Code / PSScriptAnalyzer | No. The analyzer rule uses the built-in rules only. |

GitHub Action example:

```yaml
      - uses: matejpaunovski/M365DeprecationScanner@v0
        with:
          custom-rule-path: .github/contoso-rules.json
```

## Common problems

**"Rule file '...' is not valid JSON".** Check commas and quotes. A missing `\\` in a regex is a common cause.

**"Rule '...' has an invalid regular expression".** Test the pattern in PowerShell first: `'https://api-old.contoso.com' -match 'https?://(api-old|legacy-api)\.contoso\.com'` (single backslashes there, double in JSON).

**"Duplicate rule id".** Two loaded files use the same id. Rename yours.

**"Rule id '...' is invalid".** Ids are 2-8 upper-case letters followed by exactly 4 digits, for example `CONTOSO0001`. This keeps them usable in suppression comments.

**"A rule in '...' is missing the required field '...'".** Add the named field.

**"is a Parameter rule and needs a 'command'".** Add `command` to the rule.

Think your rule is useful for everyone? See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-changing-a-rule).
