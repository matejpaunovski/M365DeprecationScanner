# GitHub Action (and Azure DevOps)

Check every push and pull request for retired and deprecated Microsoft 365 commands. The Action:

- shows findings as **annotations** on the code,
- writes a **job summary** table,
- writes a **SARIF** file for GitHub code scanning,
- can write an **HTML** report,
- **fails the job** when it finds retired commands (configurable).

It runs the same engine as `Invoke-M365DeprecationScan`. Scripts are only parsed, never executed. The Action does not need tenant credentials or secrets.

## Requirements

- A runner with PowerShell 7 (`pwsh`). All GitHub-hosted runners have it. Self-hosted runners need it installed.
- `actions/checkout` before the scan step, so there are files to scan.

## Minimal workflow

Save as `.github/workflows/m365-deprecations.yml`:

```yaml
name: M365 deprecations

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: matejpaunovski/M365DeprecationScanner@v0
```

This scans the whole repository and fails the job if it finds anything with status Retired.

## Full example: code scanning and HTML report

```yaml
name: M365 deprecations

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  security-events: write   # needed to upload SARIF

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Scan for deprecated M365 commands
        id: scan
        uses: matejpaunovski/M365DeprecationScanner@v0
        with:
          path: scripts
          exclude: '*/tests/*'
          fail-on: Error
          sarif-file: m365-deprecations.sarif
          html-file: m365-deprecations.html

      - name: Upload to code scanning
        if: ${{ !cancelled() }}
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: m365-deprecations.sarif
          category: m365-deprecations

      - name: Upload HTML report
        if: ${{ !cancelled() }}
        uses: actions/upload-artifact@v4
        with:
          name: m365-deprecation-report
          path: m365-deprecations.html
```

`if: ${{ !cancelled() }}` makes sure the reports are uploaded even when the scan step fails because of findings.

Code scanning (SARIF upload) is free for public repositories. Private repositories need GitHub Code Security (Advanced Security).

## Inputs

All inputs are optional. Lists are separated by commas (for `path` also by new lines).

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Files or folders to scan. Folders are always scanned recursively. Relative paths start at the repository root. |
| `include` | `*.ps1,*.psm1` | File name patterns to scan inside folders. |
| `exclude` | (empty) | Wildcard patterns matched against the full file path. Example: `*/tests/*` |
| `minimum-severity` | `Information` | Report findings with at least this severity: `Information`, `Warning` or `Error`. |
| `fail-on` | `Error` | Fail the step when a finding with at least this severity exists: `Error`, `Warning`, `Information` or `None`. |
| `exclude-rule-ids` | (empty) | Rule ids to ignore. |
| `custom-rule-path` | (empty) | Additional rule files (JSON), see [custom-rules.md](custom-rules.md). |
| `sarif-file` | `m365-deprecations.sarif` | Where to write the SARIF report. Empty = no SARIF file. |
| `html-file` | (empty) | Where to write the HTML report. Empty = no HTML file. |
| `job-summary` | `true` | Write a Markdown table to the job summary page. |
| `annotations` | `true` | Show findings as annotations on the files. |

## Outputs

| Output | Description |
|---|---|
| `findings` | Total number of findings. |
| `errors` | Number of findings for retired items (severity Error). |
| `warnings` | Number of findings for deprecated items (severity Warning). |
| `sarif-file` | Path of the SARIF report, if written. |

Use them in later steps, for example:

```yaml
      - name: Show result
        if: ${{ !cancelled() }}
        env:
          FINDINGS: ${{ steps.scan.outputs.findings }}
        run: echo "Found $FINDINGS deprecated items"
```

## When does the job fail?

`fail-on` sets the threshold. `minimum-severity` decides what is reported at all.

| `fail-on` | The step fails when there is at least one ... |
|---|---|
| `Error` (default) | retired item |
| `Warning` | retired or deprecated item |
| `Information` | finding of any kind |
| `None` | never. Report only. |

Findings filtered out by `minimum-severity`, `exclude-rule-ids` or a suppression comment never fail the job.

Tip: introducing the scanner into an old repository? Start with `fail-on: None`, look at the report, clean up, then switch to `Error`.

## Notes

- GitHub shows a limited number of annotations per step. The Action prints the most severe findings first. The job summary, SARIF and HTML reports always contain all findings (the job summary shows at most 500 rows, see [reports.md](reports.md)).
- Pin a version: `@v0` follows the latest 0.x release. For full reproducibility pin a release tag such as `@v0.1.0` or a commit SHA.

## Azure DevOps Pipelines

There is no Azure DevOps extension. Install the module from the PowerShell Gallery in a `pwsh` step and run it yourself:

```yaml
trigger:
  - main

pool:
  vmImage: ubuntu-latest

steps:
  - checkout: self

  - pwsh: |
      Install-PSResource -Name M365DeprecationScanner -Scope CurrentUser -TrustRepository
      Import-Module M365DeprecationScanner

      $findings = @(Invoke-M365DeprecationScan -Path $env:BUILD_SOURCESDIRECTORY -Recurse)
      $findings | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

      # Show each finding as a warning or error in the pipeline UI
      foreach ($f in $findings) {
        $type = if ($f.Severity -eq 'Error') { 'error' } else { 'warning' }
        Write-Host "##vso[task.logissue type=$type;sourcepath=$($f.Path);linenumber=$($f.Line);columnnumber=$($f.Column)]$($f.RuleId): $($f.Message)"
      }

      $null = $findings | Export-M365DeprecationReport -Format Html -Path "$env:BUILD_ARTIFACTSTAGINGDIRECTORY/m365-deprecations.html" -BasePath $env:BUILD_SOURCESDIRECTORY -Force

      # Fail on retired items only
      $retired = @($findings | Where-Object Severity -eq 'Error').Count
      if ($retired -gt 0) {
        Write-Host "##vso[task.logissue type=error]$retired retired command(s) found."
        exit 1
      }
    displayName: Scan for deprecated M365 commands

  - task: PublishPipelineArtifact@1
    condition: succeededOrFailed()
    inputs:
      targetPath: $(Build.ArtifactStagingDirectory)/m365-deprecations.html
      artifact: m365-deprecation-report
```

To fail on deprecated items too, change the filter to `Where-Object Severity -in 'Error', 'Warning'`.

## Common problems

**The SARIF upload fails with "Resource not accessible by integration".** Add `security-events: write` to `permissions`.

**The upload step is skipped when the scan fails.** Add `if: ${{ !cancelled() }}` to the upload steps.

**Findings in files I don't care about.** Use `exclude`, for example `exclude: '*/tests/*,*/archive/*'`.

**The job fails and I only want a report.** Set `fail-on: None`.
