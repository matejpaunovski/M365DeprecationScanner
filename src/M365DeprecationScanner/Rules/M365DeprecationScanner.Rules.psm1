#Requires -Version 5.1
<#
    PSScriptAnalyzer custom rule module for M365DeprecationScanner.

    Usage:
        Invoke-ScriptAnalyzer -Path .\script.ps1 -CustomRulePath <path to this file>

    or reference this file in a PSScriptAnalyzerSettings.psd1 (see New-M365DeprecationAnalyzerSettings)
    to see findings directly in VS Code.

    This file reuses the scanner engine, so results are identical to Invoke-M365DeprecationScan.
#>

$script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1' -File) {
    . $file.FullName
}

function Measure-M365Deprecation {
    <#
    .SYNOPSIS
        Flags deprecated or retired Microsoft 365, Entra ID and Azure PowerShell commands.
    .DESCRIPTION
        Finds commands, parameters, modules and endpoints that Microsoft has deprecated or retired
        (MSOnline, AzureAD, Exchange Online RPS, AzureRM, Azure AD Graph, ...) and names the replacement.
        Suppress a single finding with [Diagnostics.CodeAnalysis.SuppressMessageAttribute('M365DeprecationScanner.Rules\Measure-M365Deprecation', '<RuleId>')]
        or with a '# m365ds-ignore: <RuleId>' comment.
    .EXAMPLE
        Measure-M365Deprecation -ScriptBlockAst $ScriptBlockAst
    .INPUTS
        [System.Management.Automation.Language.ScriptBlockAst]
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )

    # PSScriptAnalyzer calls the rule for every script block; only analyse the root once.
    if ($null -ne $ScriptBlockAst.Parent) {
        return
    }

    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($ScriptBlockAst.Extent.Text, [ref]$tokens, [ref]$parseErrors)

    $rules = @(Get-DeprecationRuleSet)
    $filePath = $ScriptBlockAst.Extent.File

    $severityMap = @{
        Error       = 'Error'
        Warning     = 'Warning'
        Information = 'Information'
    }

    foreach ($finding in Find-DeprecationInAst -Ast $ScriptBlockAst -Rules $rules -Tokens $tokens -FilePath $filePath) {
        $record = [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = '[{0}] {1}' -f $finding.RuleId, $finding.Message
            Extent   = $finding.GetExtent()
            RuleName = 'M365DeprecationScanner.Rules\Measure-M365Deprecation'
            Severity = $severityMap[$finding.Severity]
        }
        $record.RuleSuppressionID = $finding.RuleId
        $record
    }
}

Export-ModuleMember -Function 'Measure-M365Deprecation'
