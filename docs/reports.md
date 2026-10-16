# Reports

Turn scan results into a file you can share, open in Excel or feed into other tools. Pipe the findings into `Export-M365DeprecationReport`:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html
```

## Which format?

| Format | Use it for | What you get |
|---|---|---|
| `Html` | Sending to your team or manager | One self-contained page: summary cards, filter by severity, search box, links to Microsoft sources. Works offline. Light and dark mode. |
| `Markdown` | GitHub job summaries, pull request comments, wikis | A summary line and a table with status icons. |
| `Csv` | Excel, tracking the migration in a spreadsheet | One row per finding, all fields. |
| `Json` | Automation, dashboards, your own scripts | An array of findings. `Sources` stays an array. |
| `Sarif` | GitHub code scanning and other security dashboards | SARIF 2.1.0 with one rule entry per rule id. |

All formats contain the same fields per finding: rule id, severity, status, area, file, line and column, what was found, title, replacement, replacement module, retirement date, notes, the line of code and the source links.

## Examples

HTML report for the team:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html -Title 'Script migration - Contoso IT'
```

CSV for Excel:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Csv -Path .\deprecations.csv
```

Markdown printed to the console (without `-Path` the report is returned as a string):

```powershell
Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Markdown
```

JSON for further processing:

```powershell
Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Json -Path .\deprecations.json
```

SARIF for code scanning:

```powershell
Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Sarif -Path .\m365-deprecations.sarif
```

Only retired items, as an "act now" list:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -MinimumSeverity Error | Export-M365DeprecationReport -Format Html -Path .\retired.html -Title 'Broken today'
```

With no findings, every format still produces a valid report. HTML and Markdown say so in plain words.

## Parameters

| Parameter | Description |
|---|---|
| `-Format` | `Html`, `Markdown`, `Csv`, `Json` or `Sarif`. Required. |
| `-Path` | File to write. Missing folders are created. Without `-Path` the report text goes to the pipeline. |
| `-Title` | Title for HTML and Markdown. Default: `M365 Deprecation Scan`. |
| `-BasePath` | File paths in the report are shown relative to this folder. Default: the current folder. |
| `-Force` | Overwrite an existing file. Without it the command stops with an error. |

The command also supports `-WhatIf`.

## Relative paths with -BasePath

Findings contain full paths such as `C:\Scripts\Users\Get-Licenses.ps1`. In the report, paths below `-BasePath` are shown relative and with forward slashes, for example `Users/Get-Licenses.ps1`. Paths outside `-BasePath` stay absolute.

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Csv -Path .\deprecations.csv -BasePath C:\Scripts
```

For **SARIF** this matters: GitHub code scanning needs paths relative to the repository root. Run the export from the repository root or set `-BasePath` to it. The GitHub Action does this for you.

Findings from `-ScriptDefinition` have no file. They show up as `<script>`.

## Markdown: 500-row limit

The Markdown report shows at most 500 rows, sorted by severity (retired first), then by file and line. Below the table it says how many findings were left out. The summary line always counts all findings.

GitHub job summaries and comments have size limits, so this keeps them readable. For the full list use HTML, CSV, JSON or SARIF.

## Common problems

**"File '...' already exists. Use -Force to overwrite it."** Add `-Force`, or choose a new file name.

**Code scanning shows findings without a file location.** The SARIF paths are absolute. Export from the repository root or set `-BasePath`.

**Umlauts look broken in Excel.** Files are written as UTF-8 without BOM. In Excel use **Data > From Text/CSV** and pick UTF-8 instead of double-clicking the file.
