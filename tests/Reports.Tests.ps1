#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force
    $ruleFile = Join-Path $PSScriptRoot 'Fixtures/test-rules.json'

    $script:ScriptFolder = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Path (Join-Path $script:ScriptFolder 'src') -Force | Out-Null
    $script:ScriptFile = Join-Path $script:ScriptFolder 'src/legacy.ps1'
    Set-Content -LiteralPath $script:ScriptFile -Value @'
Get-LegacyUser | Where-Object { $_.Name -like '<script>alert(1)</script>|x' }
Connect-Service -UseOldProtocol
$u = 'https://old-api.example.com'
'@
    $script:Findings = @(Invoke-M365DeprecationScan -Path $script:ScriptFile -ExcludeDefaultRules -CustomRulePath $ruleFile)
}

Describe 'Export-M365DeprecationReport' {
    It 'has three findings to work with' {
        $script:Findings.Count | Should -Be 3
    }

    Context 'Html' {
        BeforeAll {
            $script:Html = $script:Findings | Export-M365DeprecationReport -Format Html -Title 'Test <Report>'
        }

        It 'is a complete HTML document' {
            $script:Html | Should -Match '^<!DOCTYPE html>'
            $script:Html | Should -Match '</html>\s*$'
        }

        It 'HTML-encodes script content and the title' {
            $script:Html | Should -Not -Match '<script>alert'
            $script:Html | Should -Match '&lt;script&gt;alert'
            $script:Html | Should -Match 'Test &lt;Report&gt;'
        }

        It 'shows a friendly message when there are no findings' {
            @() | Export-M365DeprecationReport -Format Html | Should -Match 'No deprecated commands found'
        }
    }

    Context 'Markdown' {
        It 'contains a summary and a table row per finding' {
            $markdown = $script:Findings | Export-M365DeprecationReport -Format Markdown -BasePath $script:ScriptFolder
            $markdown | Should -Match '\*\*3 finding\(s\)\*\* in \*\*1 file\(s\)\*\*'
            @($markdown -split "`n" | Where-Object { $_ -match '^\| :' }).Count | Should -Be 3
            $markdown | Should -Match '`src/legacy.ps1`'
        }

        It 'reports success for an empty scan' {
            @() | Export-M365DeprecationReport -Format Markdown | Should -Match 'No deprecated commands found'
        }
    }

    Context 'Csv' {
        It 'round-trips through ConvertFrom-Csv' {
            $rows = $script:Findings | Export-M365DeprecationReport -Format Csv | ConvertFrom-Csv
            @($rows).Count | Should -Be 3
            $rows[0].RuleId | Should -Be 'TEST0002'
            $rows[0].Sources | Should -Be 'https://example.com/get-legacyuser'
        }
    }

    Context 'Json' {
        It 'round-trips through ConvertFrom-Json and keeps sources as an array' {
            $rows = $script:Findings | Export-M365DeprecationReport -Format Json | ConvertFrom-Json
            @($rows).Count | Should -Be 3
            $rows[0].Sources | Should -Be @('https://example.com/get-legacyuser')
            $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Extent'
        }
    }

    Context 'Sarif' {
        BeforeAll {
            $script:Sarif = $script:Findings | Export-M365DeprecationReport -Format Sarif -BasePath $script:ScriptFolder | ConvertFrom-Json
        }

        It 'is SARIF 2.1.0 with one run' {
            $script:Sarif.version | Should -Be '2.1.0'
            @($script:Sarif.runs).Count | Should -Be 1
            $script:Sarif.runs[0].tool.driver.name | Should -Be 'M365DeprecationScanner'
        }

        It 'lists each rule once and maps severities to SARIF levels' {
            @($script:Sarif.runs[0].tool.driver.rules).Count | Should -Be 3
            $script:Sarif.runs[0].results.level | Should -Be @('error', 'warning', 'note')
        }

        It 'uses relative, forward-slash paths for GitHub code scanning' {
            $location = $script:Sarif.runs[0].results[0].locations[0].physicalLocation
            $location.artifactLocation.uri | Should -Be 'src/legacy.ps1'
            $location.artifactLocation.uriBaseId | Should -Be '%SRCROOT%'
            $location.region.startLine | Should -Be 1
        }

        It 'links rules to their source' {
            $script:Sarif.runs[0].tool.driver.rules[0].helpUri | Should -Be 'https://example.com/get-legacyuser'
        }

        It 'produces a valid document without findings' {
            $empty = @() | Export-M365DeprecationReport -Format Sarif | ConvertFrom-Json
            @($empty.runs[0].results).Count | Should -Be 0
        }
    }

    Context 'Writing files' {
        It 'writes the report to -Path and returns the file' {
            $target = Join-Path $TestDrive 'out/report.html'
            $file = $script:Findings | Export-M365DeprecationReport -Format Html -Path $target
            $file.FullName | Should -Be $target
            Test-Path -LiteralPath $target | Should -BeTrue
        }

        It 'refuses to overwrite without -Force' {
            $target = Join-Path $TestDrive 'exists.csv'
            Set-Content -LiteralPath $target -Value 'x'
            { $script:Findings | Export-M365DeprecationReport -Format Csv -Path $target } | Should -Throw '*already exists*'
            { $script:Findings | Export-M365DeprecationReport -Format Csv -Path $target -Force } | Should -Not -Throw
        }
    }
}
