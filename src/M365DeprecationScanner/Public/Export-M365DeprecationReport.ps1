function Export-M365DeprecationReport {
    <#
    .SYNOPSIS
        Turns scan findings into an HTML, Markdown, CSV, JSON or SARIF report.

    .DESCRIPTION
        Pipe the output of Invoke-M365DeprecationScan into this command.

          Html     - a single self-contained page with summary and search box; send it to your team.
          Markdown - for GitHub job summaries, pull request comments or wikis.
          Csv      - for Excel.
          Json     - for automation.
          Sarif    - for GitHub code scanning and other security dashboards.

        Without -Path the report is returned as a string.

    .PARAMETER InputObject
        Findings from Invoke-M365DeprecationScan.

    .PARAMETER Format
        Html, Markdown, Csv, Json or Sarif.

    .PARAMETER Path
        File to write. If omitted, the report text is written to the pipeline.

    .PARAMETER Title
        Title shown in HTML and Markdown reports.

    .PARAMETER BasePath
        File paths in the report are shown relative to this folder. Default: current folder.
        SARIF requires relative paths for GitHub code scanning.

    .PARAMETER Force
        Overwrite an existing file.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html

        Creates an HTML report.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Csv -Path .\deprecations.csv

        Creates a CSV file for Excel.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Markdown

        Prints a Markdown summary, for example for a GitHub job summary.

    .OUTPUTS
        System.String or System.IO.FileInfo

    .LINK
        https://github.com/matejpaunovski/M365DeprecationScanner/blob/main/docs/reports.md
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string], [System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [psobject[]]$InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Html', 'Markdown', 'Csv', 'Json', 'Sarif')]
        [string]$Format,

        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$Title = 'M365 Deprecation Scan',

        [string]$BasePath = (Get-Location -PSProvider FileSystem).ProviderPath,

        [switch]$Force
    )

    begin {
        $findings = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($item in $InputObject) {
            if ($null -ne $item) {
                $findings.Add($item)
            }
        }
    }

    end {
        $rows = @($findings | ForEach-Object { ConvertTo-ReportRow -Finding $_ -BasePath $BasePath })

        $content = switch ($Format) {
            'Html' { ConvertTo-HtmlReport -Rows $rows -Title $Title }
            'Markdown' { ConvertTo-MarkdownReport -Rows $rows -Title $Title }
            'Csv' { ConvertTo-CsvReport -Rows $rows }
            'Json' { ConvertTo-Json -InputObject $rows -Depth 5 }
            'Sarif' { ConvertTo-SarifReport -Rows $rows }
        }

        if (-not $Path) {
            return $content
        }

        $target = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        Assert-WritableReportTarget -Path $target -Force:$Force
        if ($PSCmdlet.ShouldProcess($target, "Write $Format report")) {
            $directory = Split-Path -Path $target -Parent
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = [System.IO.Directory]::CreateDirectory($directory)
            }
            [System.IO.File]::WriteAllText($target, $content, (New-Object System.Text.UTF8Encoding($false)))
            Get-Item -LiteralPath $target
        }
    }
}
