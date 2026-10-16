#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $script:HasAnalyzer = [bool](Get-Module -ListAvailable -Name PSScriptAnalyzer)
}

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force
    $script:RulePath = Get-M365DeprecationAnalyzerRulePath
    $script:LegacyExample = Join-Path $repoRoot 'examples/legacy-script.ps1'
}

Describe 'PSScriptAnalyzer custom rule' -Skip:(-not $script:HasAnalyzer) {
    BeforeAll {
        Import-Module PSScriptAnalyzer
        $script:Records = @(Invoke-ScriptAnalyzer -Path $script:LegacyExample -CustomRulePath $script:RulePath)
        $script:Findings = @(Invoke-M365DeprecationScan -Path $script:LegacyExample)
    }

    It 'reports the same findings as Invoke-M365DeprecationScan' {
        $script:Records.Count | Should -Be $script:Findings.Count
        @($script:Records | ForEach-Object { '{0}:{1}' -f $_.Line, $_.RuleSuppressionID }) |
            Should -Be @($script:Findings | ForEach-Object { '{0}:{1}' -f $_.Line, $_.RuleId })
    }

    It 'prefixes messages with the rule id and sets RuleSuppressionID' {
        foreach ($record in $script:Records) {
            $record.Message | Should -Match ('^\[{0}\] ' -f [regex]::Escape($record.RuleSuppressionID))
        }
    }

    It 'finds retired modules in a module manifest (.psd1)' {
        $manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'examples/legacy-module/Contoso.LegacyTools.psd1'
        $records = @(Invoke-ScriptAnalyzer -Path $manifest -CustomRulePath $script:RulePath)
        $records.Count | Should -Be @(Invoke-M365DeprecationScan -Path $manifest).Count
        $records.Count | Should -BeGreaterOrEqual 3
    }

    It 'can be suppressed with SuppressMessageAttribute' {
        $first = $script:Findings | Where-Object Kind -EQ 'Command' | Select-Object -First 1
        $code = @"
function Test-Suppressed {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('M365DeprecationScanner.Rules\Measure-M365Deprecation', '$($first.RuleId)')]
    param()
    $($first.Match)
}
"@
        $file = Join-Path $TestDrive 'suppressed.ps1'
        Set-Content -LiteralPath $file -Value $code
        @(Invoke-ScriptAnalyzer -Path $file -CustomRulePath $script:RulePath | Where-Object RuleSuppressionID -EQ $first.RuleId).Count | Should -Be 0
    }
}
