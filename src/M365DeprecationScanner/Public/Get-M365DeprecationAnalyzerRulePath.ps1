function Get-M365DeprecationAnalyzerRulePath {
    <#
    .SYNOPSIS
        Returns the path of the PSScriptAnalyzer custom rule module shipped with M365DeprecationScanner.

    .DESCRIPTION
        PSScriptAnalyzer (and therefore VS Code) can load custom rules. Pass this path to
        Invoke-ScriptAnalyzer -CustomRulePath, or use New-M365DeprecationAnalyzerSettings to create a
        settings file for VS Code.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path .\MyScript.ps1 -CustomRulePath (Get-M365DeprecationAnalyzerRulePath)

        Runs only the deprecation rules through PSScriptAnalyzer.

    .EXAMPLE
        Invoke-ScriptAnalyzer -Path . -Recurse -CustomRulePath (Get-M365DeprecationAnalyzerRulePath) -IncludeDefaultRules

        Runs the deprecation rules together with all default PSScriptAnalyzer rules.

    .OUTPUTS
        System.String

    .LINK
        https://github.com/matejpaunovski/M365DeprecationScanner/blob/main/docs/vscode.md
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path -Path $script:ModuleRoot -ChildPath 'Rules/M365DeprecationScanner.Rules.psm1'
}
