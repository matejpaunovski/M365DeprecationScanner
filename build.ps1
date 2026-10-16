#Requires -Version 7.0
<#
.SYNOPSIS
    Build script for M365DeprecationScanner. Used locally and in CI.

.DESCRIPTION
    Tasks:
      Bootstrap  Install the tools needed to develop (Pester 5, PSScriptAnalyzer) for the current user.
      Test       Run all Pester tests.
      Analyze    Run PSScriptAnalyzer on the module source.
      Docs       Regenerate docs/rules.md from the rule database.
      All        Analyze, Test and check that docs/rules.md is up to date (what CI runs).

.EXAMPLE
    ./build.ps1 -Task Bootstrap
    ./build.ps1            # runs All
    ./build.ps1 -Task Docs
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TestResultPath', Justification = 'Used in Invoke-Test.')]
[CmdletBinding()]
param(
    [ValidateSet('Bootstrap', 'Test', 'Analyze', 'Docs', 'All')]
    [string]$Task = 'All',

    # Write test results as NUnit XML (for CI).
    [string]$TestResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = $PSScriptRoot
$moduleRoot = Join-Path $repoRoot 'src/M365DeprecationScanner'

# Exact tool versions, so CI and release builds always run the same, reviewed code.
$PesterVersion = '5.9.1'
$AnalyzerVersion = '1.25.0'

function Invoke-Bootstrap {
    if (-not (Get-Module -ListAvailable Pester | Where-Object Version -EQ $PesterVersion)) {
        Install-PSResource -Name Pester -Version $PesterVersion -Scope CurrentUser -TrustRepository
    }
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -EQ $AnalyzerVersion)) {
        Install-PSResource -Name PSScriptAnalyzer -Version $AnalyzerVersion -Scope CurrentUser -TrustRepository
    }
}

function Invoke-Test {
    # Tests run the way users run the module: without the build script's strict mode.
    Set-StrictMode -Off
    Import-Module Pester -RequiredVersion $PesterVersion
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path $repoRoot 'tests'
    $configuration.Run.Exit = $false
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    if ($TestResultPath) {
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputPath = $TestResultPath
        $configuration.TestResult.OutputFormat = 'NUnitXml'
    }
    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0) {
        throw "$($result.FailedCount) test(s) failed."
    }
}

function Invoke-Analyze {
    Import-Module PSScriptAnalyzer -RequiredVersion $AnalyzerVersion
    $settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
    $records = @(
        Invoke-ScriptAnalyzer -Path $moduleRoot -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'action') -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'build.ps1') -Settings $settings
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot 'tools') -Recurse -Settings $settings
    )
    if ($records.Count -gt 0) {
        $records | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 220 | Write-Host
        throw "PSScriptAnalyzer reported $($records.Count) issue(s)."
    }
    Write-Host 'PSScriptAnalyzer: no issues.' -ForegroundColor Green
}

function Update-RuleCatalog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal build task.')]
    [CmdletBinding()]
    param([switch]$Check)
    $target = Join-Path $repoRoot 'docs/rules.md'
    $generated = & (Join-Path $repoRoot 'tools/New-RuleCatalog.ps1')
    if ($Check) {
        $current = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
        if (($current -replace '\r\n', "`n").TrimEnd() -ne ($generated -replace '\r\n', "`n").TrimEnd()) {
            throw 'docs/rules.md is out of date. Run ./build.ps1 -Task Docs and commit the result.'
        }
        Write-Host 'docs/rules.md is up to date.' -ForegroundColor Green
        return
    }
    [System.IO.File]::WriteAllText($target, $generated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $target" -ForegroundColor Green
}

switch ($Task) {
    'Bootstrap' { Invoke-Bootstrap }
    'Test' { Invoke-Test }
    'Analyze' { Invoke-Analyze }
    'Docs' { Update-RuleCatalog }
    'All' {
        Invoke-Analyze
        Update-RuleCatalog -Check
        Invoke-Test
    }
}
