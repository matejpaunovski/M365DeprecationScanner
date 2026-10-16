# PSScriptAnalyzer settings for developing this repository (used by build.ps1 and CI).
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Write-Host is used on purpose in build/action scripts for CI log output.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
