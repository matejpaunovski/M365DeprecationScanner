#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Regression tests for hostile input: scanned files are untrusted (for example in pull requests).

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force
    $script:RuleFile = Join-Path $PSScriptRoot 'Fixtures/test-rules.json'
}

Describe 'Scanned code is never executed' {
    It 'does not run code from the scanned file, using module or #Requires' {
        $marker = Join-Path $TestDrive 'executed.txt'
        $evilModule = Join-Path $TestDrive 'evil.psm1'
        Set-Content -LiteralPath $evilModule -Value "Set-Content -LiteralPath '$marker' -Value 'x'"
        $script = Join-Path $TestDrive 'evil.ps1'
        Set-Content -LiteralPath $script -Value @"
using module '$evilModule'
Set-Content -LiteralPath '$marker' -Value 'x'
`$(Set-Content -LiteralPath '$marker' -Value 'x')
Get-LegacyUser
"@
        $null = Invoke-M365DeprecationScan -Path $script -ExcludeDefaultRules -CustomRulePath $script:RuleFile -WarningAction SilentlyContinue
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
}

Describe 'Warnings cannot inject CI workflow commands' {
    It 'keeps parse error warnings on a single line' {
        $code = "Get-LegacyUser`n`$a = 1 `"x`n::warning title=PWNED::injected`n`""
        $warnings = $null
        $null = Invoke-M365DeprecationScan -ScriptDefinition $code -ExcludeDefaultRules -CustomRulePath $script:RuleFile -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings.Count | Should -BeGreaterThan 0
        foreach ($warning in $warnings) {
            $warning.Message | Should -Not -Match '[\r\n]'
        }
    }
}

Describe 'Report escaping' {
    BeforeAll {
        $script:Findings = @(Invoke-M365DeprecationScan -ExcludeDefaultRules -CustomRulePath $script:RuleFile -ScriptDefinition @'
& 'Set-Legacy`[Click](https://evil.example/phish)'
& '=cmd|calc!A0;Set-LegacyX'
'@)
    }

    It 'produces findings for the hostile names' {
        $script:Findings.Count | Should -Be 2
    }

    It 'does not create Markdown links from scanned content' {
        $markdown = $script:Findings | Export-M365DeprecationReport -Format Markdown
        $markdown | Should -Not -Match '(?<!\\)\[Click(?<!\\)\]\(https://evil'
    }

    It 'neutralises spreadsheet formulas in CSV' {
        $rows = $script:Findings | Export-M365DeprecationReport -Format Csv | ConvertFrom-Csv
        foreach ($row in $rows) {
            foreach ($property in $row.PSObject.Properties) {
                [string]$property.Value | Should -Not -Match '^[=+\-@]'
            }
        }
    }

    It 'adds a Content-Security-Policy whose hash matches the inline script' {
        $html = $script:Findings | Export-M365DeprecationReport -Format Html
        $script = [regex]::Match($html, '<script>(.*?)</script>', 'Singleline').Groups[1].Value
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script)))
        $html | Should -Match ([regex]::Escape("script-src 'sha256-$hash'"))
        $html | Should -Match "default-src 'none'"
    }
}

Describe 'Symbolic links' {
    BeforeAll {
        $script:CanLink = $true
        $script:Target = Join-Path $TestDrive 'outside.txt'
        Set-Content -LiteralPath $script:Target -Value 'secret'
        $script:LinkFolder = Join-Path $TestDrive 'linked'
        New-Item -ItemType Directory -Path $script:LinkFolder | Out-Null
        $script:Link = Join-Path $script:LinkFolder 'report.sarif'
        $script:ScriptLink = Join-Path $script:LinkFolder 'linked.ps1'
        try {
            New-Item -ItemType SymbolicLink -Path $script:Link -Target $script:Target -ErrorAction Stop | Out-Null
            $legacy = Join-Path $TestDrive 'legacy.ps1'
            Set-Content -LiteralPath $legacy -Value 'Get-LegacyUser'
            New-Item -ItemType SymbolicLink -Path $script:ScriptLink -Target $legacy -ErrorAction Stop | Out-Null
        }
        catch {
            $script:CanLink = $false
        }
    }

    It 'refuses to write a report through a symbolic link' {
        if (-not $script:CanLink) { Set-ItResult -Skipped -Because 'creating symbolic links needs Developer Mode or admin rights on Windows' }
        { @() | Export-M365DeprecationReport -Format Sarif -Path $script:Link -Force } | Should -Throw '*symbolic link*'
        Get-Content -LiteralPath $script:Target | Should -Be 'secret'
    }

    It 'skips symbolic links while walking a folder' {
        if (-not $script:CanLink) { Set-ItResult -Skipped -Because 'creating symbolic links needs Developer Mode or admin rights on Windows' }
        @(Invoke-M365DeprecationScan -Path $script:LinkFolder -ExcludeDefaultRules -CustomRulePath $script:RuleFile).Count | Should -Be 0
    }
}
