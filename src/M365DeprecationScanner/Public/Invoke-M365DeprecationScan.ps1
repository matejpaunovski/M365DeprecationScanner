function Invoke-M365DeprecationScan {
    <#
    .SYNOPSIS
        Scans PowerShell scripts for deprecated or retired Microsoft 365, Entra ID and Azure commands.

    .DESCRIPTION
        Parses each script or module manifest (nothing is executed) and reports every use of a
        deprecated or retired command, parameter, module or endpoint - for example Get-MsolUser, Connect-AzureAD,
        Connect-ExchangeOnline -UseRPSSession or https://graph.windows.net - together with what to
        use instead.

        Each result is an object you can filter, sort, export or pipe to Export-M365DeprecationReport.

        Severity is derived from the rule status:
          Error       = Retired     (no longer works)
          Warning     = Deprecated  (still works, but support has ended or retirement is announced)
          Information = Announced   (retirement announced for a future date)

        When nothing is found, a short confirmation is printed to the console (not to the pipeline).
        Hide it with -InformationAction SilentlyContinue.

    .PARAMETER Path
        Files or folders to scan. Folders are scanned for *.ps1, *.psm1 and *.psd1 files.
        Defaults to the current folder. Accepts pipeline input (for example from Get-ChildItem).

    .PARAMETER ScriptDefinition
        Scan PowerShell code passed as a string instead of files.

    .PARAMETER Recurse
        Also scan sub folders.

    .PARAMETER Include
        File name patterns to scan inside folders. Default: *.ps1, *.psm1, *.psd1 (module manifests).

    .PARAMETER Exclude
        Wildcard patterns matched against the full file path, for example '*\tests\*'.

    .PARAMETER MinimumSeverity
        Only return findings with at least this severity: Information (default), Warning or Error.

    .PARAMETER Area
        Only return findings for these product areas, for example MSOnline, AzureAD, ExchangeOnline.

    .PARAMETER ExcludeRuleId
        Rule ids to ignore, for example 'OTHER0001'.

    .PARAMETER CustomRulePath
        Additional rule database files (same JSON format as the built-in one), for example to flag
        your organisation's own retired helper functions.

    .PARAMETER ExcludeDefaultRules
        Do not load the built-in rule database. Use together with -CustomRulePath.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path C:\Scripts -Recurse

        Scans every .ps1 and .psm1 file below C:\Scripts and lists all findings.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path .\Get-Licenses.ps1 | Format-List

        Shows every detail of each finding, including migration notes and source links.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path . -Recurse -MinimumSeverity Error

        Lists only things that no longer work at all.

    .EXAMPLE
        Invoke-M365DeprecationScan -Path . -Recurse | Export-M365DeprecationReport -Format Html -Path .\report.html

        Creates an HTML report you can open in the browser or send to your team.

    .EXAMPLE
        Invoke-M365DeprecationScan -ScriptDefinition 'Connect-MsolService; Get-MsolUser -All'

        Checks a snippet without saving it to a file.

    .OUTPUTS
        M365DeprecationScanner.Finding

    .LINK
        https://github.com/matejpaunovski/M365DeprecationScanner
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Area', Justification = 'Used inside the $isWanted script block.')]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('M365DeprecationScanner.Finding')]
    param(
        [Parameter(ParameterSetName = 'Path', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path = @('.'),

        [Parameter(Mandatory, ParameterSetName = 'ScriptDefinition')]
        [ValidateNotNull()]
        [string]$ScriptDefinition,

        [Parameter(ParameterSetName = 'Path')]
        [switch]$Recurse,

        [Parameter(ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1'),

        [Parameter(ParameterSetName = 'Path')]
        [string[]]$Exclude,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information',

        [ValidateSet('MSOnline', 'AzureAD', 'ExchangeOnline', 'MicrosoftGraph', 'AzureADGraph', 'Azure', 'Teams', 'SharePoint', 'Intune', 'Other')]
        [string[]]$Area,

        [string[]]$ExcludeRuleId,

        [string[]]$CustomRulePath,

        [switch]$ExcludeDefaultRules
    )

    begin {
        $rulePaths = @()
        if (-not $ExcludeDefaultRules) {
            $rulePaths += Join-Path -Path $script:ModuleRoot -ChildPath 'Data/deprecations.json'
        }
        if ($CustomRulePath) {
            $rulePaths += $CustomRulePath
        }
        if ($rulePaths.Count -eq 0) {
            throw 'No rules to scan with. Remove -ExcludeDefaultRules or pass -CustomRulePath.'
        }

        $severityRank = @{ Information = 0; Warning = 1; Error = 2 }
        $minimumRank = $severityRank[$MinimumSeverity]
        $excludedIds = @($ExcludeRuleId | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() })

        # All rules take part in matching so that an exact rule still "claims" its command even when
        # it is filtered out; otherwise a wildcard catch-all would report the same line instead.
        # Filters are therefore applied to the findings, not to the rules.
        $rules = @(Get-DeprecationRuleSet -Path $rulePaths)
        Write-Verbose ('Loaded {0} rules.' -f $rules.Count)
        $isWanted = {
            param($Finding)
            $severityRank[$Finding.Severity] -ge $minimumRank -and
            $excludedIds -notcontains $Finding.RuleId.ToUpperInvariant() -and
            (-not $Area -or $Area -contains $Finding.Area)
        }

        $scannedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        # Counted so that a clean scan can say so instead of returning silently.
        $findingCount = 0
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ScriptDefinition') {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptDefinition, [ref]$tokens, [ref]$parseErrors)
            Write-ParseErrorWarning -ParseErrors $parseErrors -Source '<ScriptDefinition>'
            Find-DeprecationInAst -Ast $ast -Rules $rules -Tokens $tokens -FilePath $null |
                ForEach-Object { if (& $isWanted $_) { $findingCount++; $_ } }
            return
        }

        foreach ($item in $Path) {
            foreach ($file in Get-ScanTarget -Path $item -Recurse:$Recurse -Include $Include -Exclude $Exclude) {
                if (-not $scannedFiles.Add($file)) {
                    continue
                }
                Write-Verbose "Scanning $file"
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
                Write-ParseErrorWarning -ParseErrors $parseErrors -Source $file
                Find-DeprecationInAst -Ast $ast -Rules $rules -Tokens $tokens -FilePath $file |
                    ForEach-Object { if (& $isWanted $_) { $findingCount++; $_ } }
            }
        }
    }

    end {
        Write-Verbose ('Scanned {0} file(s).' -f $scannedFiles.Count)

        # Status lines go to the information stream, not the pipeline, so
        # '$result = Invoke-M365DeprecationScan' stays empty.
        if ($findingCount -gt 0) {
            return
        }
        if ($PSCmdlet.ParameterSetName -eq 'Path' -and $scannedFiles.Count -eq 0) {
            Write-Warning 'No files were scanned. Check -Path and -Include, or add -Recurse to scan sub folders.'
            return
        }
        $scope = if ($PSCmdlet.ParameterSetName -eq 'Path') { '{0} file(s)' -f $scannedFiles.Count } else { 'the script' }
        $filtered = $MinimumSeverity -ne 'Information' -or $Area -or $excludedIds.Count -gt 0
        $suffix = if ($filtered) { ' with the current filters' } else { '' }
        $message = 'No deprecated or retired commands found in {0}{1}.' -f $scope, $suffix
        if ($PSBoundParameters.ContainsKey('InformationAction')) {
            # Honours -InformationAction SilentlyContinue (Write-Host would ignore it).
            Write-Information -MessageData $message
        }
        else {
            Write-Host $message -ForegroundColor Green
        }
    }
}
