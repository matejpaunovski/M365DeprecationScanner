function Invoke-M365DeprecationScan {
    <#
    .SYNOPSIS
        Scans PowerShell scripts for deprecated or retired Microsoft 365, Entra ID and Azure commands.

    .DESCRIPTION
        Parses each script (nothing is executed) and reports every use of a deprecated or retired
        command, parameter, module or endpoint - for example Get-MsolUser, Connect-AzureAD,
        Connect-ExchangeOnline -UseRPSSession or https://graph.windows.net - together with what to
        use instead.

        Each result is an object you can filter, sort, export or pipe to Export-M365DeprecationReport.

        Severity is derived from the rule status:
          Error       = Retired     (no longer works)
          Warning     = Deprecated  (still works, but support has ended or retirement is announced)
          Information = Announced   (retirement announced for a future date)

    .PARAMETER Path
        Files or folders to scan. Folders are scanned for *.ps1 and *.psm1 files.
        Defaults to the current folder. Accepts pipeline input (for example from Get-ChildItem).

    .PARAMETER ScriptDefinition
        Scan PowerShell code passed as a string instead of files.

    .PARAMETER Recurse
        Also scan sub folders.

    .PARAMETER Include
        File name patterns to scan inside folders. Default: *.ps1, *.psm1.

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
        [string[]]$Include = @('*.ps1', '*.psm1'),

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
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ScriptDefinition') {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptDefinition, [ref]$tokens, [ref]$parseErrors)
            Write-ParseErrorWarning -ParseErrors $parseErrors -Source '<ScriptDefinition>'
            Find-DeprecationInAst -Ast $ast -Rules $rules -Tokens $tokens -FilePath $null | Where-Object { & $isWanted $_ }
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
                Find-DeprecationInAst -Ast $ast -Rules $rules -Tokens $tokens -FilePath $file | Where-Object { & $isWanted $_ }
            }
        }
    }

    end {
        Write-Verbose ('Scanned {0} file(s).' -f $scannedFiles.Count)
    }
}
