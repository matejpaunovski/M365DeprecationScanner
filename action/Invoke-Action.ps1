#Requires -Version 7.0
<#
.SYNOPSIS
    Entry point of the M365 Deprecation Scanner GitHub Action.
.DESCRIPTION
    All inputs arrive as environment variables (never interpolated into script text) so that
    values from pull requests cannot inject PowerShell code.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Split-ActionInput {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-AnnotationValue {
    # https://docs.github.com/actions/using-workflows/workflow-commands-for-github-actions
    param([string]$Value, [switch]$Property)
    $escaped = $Value.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    if ($Property) {
        $escaped = $escaped.Replace(':', '%3A').Replace(',', '%2C')
    }
    return $escaped
}

$actionRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path $actionRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force

$workspace = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).ProviderPath }
$workspacePrefix = $workspace.TrimEnd([char[]]@([char]92, [char]47)) + [System.IO.Path]::DirectorySeparatorChar

$severityRank = @{ Information = 0; Warning = 1; Error = 2 }
$minimumSeverity = if ($env:M365DS_MINIMUM_SEVERITY) { $env:M365DS_MINIMUM_SEVERITY } else { 'Information' }
$failOn = if ($env:M365DS_FAIL_ON) { $env:M365DS_FAIL_ON } else { 'Error' }
if (-not $severityRank.ContainsKey($minimumSeverity)) {
    throw "Input 'minimum-severity' must be Information, Warning or Error (got '$minimumSeverity')."
}
if ($failOn -ne 'None' -and -not $severityRank.ContainsKey($failOn)) {
    throw "Input 'fail-on' must be Error, Warning, Information or None (got '$failOn')."
}

$scanParameters = @{
    Path            = @(Split-ActionInput $env:M365DS_PATH | ForEach-Object { if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $workspace $_ } })
    Recurse         = $true
    MinimumSeverity = $minimumSeverity
}
if ($scanParameters.Path.Count -eq 0) { $scanParameters.Path = @($workspace) }
$include = Split-ActionInput $env:M365DS_INCLUDE
if ($include) { $scanParameters.Include = $include }
$exclude = Split-ActionInput $env:M365DS_EXCLUDE
if ($exclude) { $scanParameters.Exclude = $exclude }
$excludeIds = Split-ActionInput $env:M365DS_EXCLUDE_RULE_IDS
if ($excludeIds) { $scanParameters.ExcludeRuleId = $excludeIds }
$customRules = Split-ActionInput $env:M365DS_CUSTOM_RULE_PATH
if ($customRules) { $scanParameters.CustomRulePath = @($customRules | ForEach-Object { if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $workspace $_ } }) }

# While scanning, warnings may quote scanned code. Pause workflow-command processing so that nothing
# a scanned file contains can be interpreted as '::command::' by the runner.
$stopToken = [guid]::NewGuid().ToString('N')
Write-Host "::stop-commands::$stopToken"
try {
    $findings = @(Invoke-M365DeprecationScan @scanParameters)
}
finally {
    Write-Host "::$stopToken::"
}

$errors = @($findings | Where-Object Severity -EQ 'Error').Count
$warnings = @($findings | Where-Object Severity -EQ 'Warning').Count
Write-Host ('M365 Deprecation Scanner: {0} finding(s) - {1} retired, {2} deprecated, {3} announced.' -f $findings.Count, $errors, $warnings, ($findings.Count - $errors - $warnings))

# --- Annotations ------------------------------------------------------------------------------
if ($env:M365DS_ANNOTATIONS -ne 'false') {
    $commands = @{ Error = 'error'; Warning = 'warning'; Information = 'notice' }
    # GitHub shows at most 10 annotations per type and step; print the most severe first.
    foreach ($finding in ($findings | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] }; Descending = $true }, Path, Line)) {
        $file = $finding.Path
        if ($file -and $file.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $file = $file.Substring($workspacePrefix.Length).Replace([char]92, [char]47)
        }
        $properties = 'file={0},line={1},endLine={2},col={3},endColumn={4},title={5}' -f `
            (ConvertTo-AnnotationValue $file -Property), $finding.Line, $finding.EndLine, $finding.Column, $finding.EndColumn,
            (ConvertTo-AnnotationValue ('{0}: {1}' -f $finding.RuleId, $finding.Match) -Property)
        Write-Host ('::{0} {1}::{2}' -f $commands[$finding.Severity], $properties, (ConvertTo-AnnotationValue $finding.Message))
    }
}

# --- Reports ----------------------------------------------------------------------------------
foreach ($name in 'M365DS_SARIF_FILE', 'M365DS_HTML_FILE') {
    if ([Environment]::GetEnvironmentVariable($name) -match '[\r\n]') {
        throw "Input $name must not contain line breaks."
    }
}
$sarifFile = ''
if ($env:M365DS_SARIF_FILE) {
    $sarifFile = if ([System.IO.Path]::IsPathRooted($env:M365DS_SARIF_FILE)) { $env:M365DS_SARIF_FILE } else { Join-Path $workspace $env:M365DS_SARIF_FILE }
    $null = $findings | Export-M365DeprecationReport -Format Sarif -Path $sarifFile -BasePath $workspace -Force
    Write-Host "SARIF report: $sarifFile"
}
if ($env:M365DS_HTML_FILE) {
    $htmlFile = if ([System.IO.Path]::IsPathRooted($env:M365DS_HTML_FILE)) { $env:M365DS_HTML_FILE } else { Join-Path $workspace $env:M365DS_HTML_FILE }
    $null = $findings | Export-M365DeprecationReport -Format Html -Path $htmlFile -BasePath $workspace -Force
    Write-Host "HTML report: $htmlFile"
}
if ($env:M365DS_JOB_SUMMARY -ne 'false' -and $env:GITHUB_STEP_SUMMARY) {
    $findings | Export-M365DeprecationReport -Format Markdown -BasePath $workspace -Title 'M365 Deprecation Scan' |
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
}

# --- Outputs ----------------------------------------------------------------------------------
if ($env:GITHUB_OUTPUT) {
    @(
        "findings=$($findings.Count)"
        "errors=$errors"
        "warnings=$warnings"
        "sarif-file=$sarifFile"
    ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
}

# --- Exit code --------------------------------------------------------------------------------
if ($failOn -ne 'None') {
    $failing = @($findings | Where-Object { $severityRank[$_.Severity] -ge $severityRank[$failOn] })
    if ($failing.Count -gt 0) {
        Write-Host ("::error::{0} finding(s) with severity '{1}' or higher. Set 'fail-on: None' to only report." -f $failing.Count, $failOn)
        exit 1
    }
}
exit 0
