#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Quality gate for the built-in rule database. Every pull request that adds or changes a rule runs these.

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $databasePath = Join-Path $repoRoot 'src/M365DeprecationScanner/Data/deprecations.json'
    $script:RuleCases = @((Get-Content -LiteralPath $databasePath -Raw -Encoding UTF8 | ConvertFrom-Json).rules | ForEach-Object { @{ Rule = $_; Id = $_.id } })
}

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:DatabasePath = Join-Path $repoRoot 'src/M365DeprecationScanner/Data/deprecations.json'
    $script:SchemaPath = Join-Path $repoRoot 'src/M365DeprecationScanner/Data/deprecations.schema.json'
    $script:Raw = Get-Content -LiteralPath $script:DatabasePath -Raw -Encoding UTF8
    $script:Database = $script:Raw | ConvertFrom-Json
    Import-Module (Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force
}

Describe 'Rule database file' {
    It 'matches the JSON schema' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        Test-Json -Json $script:Raw -SchemaFile $script:SchemaPath | Should -BeTrue
    }

    It 'is UTF-8 without BOM' {
        $bytes = [System.IO.File]::ReadAllBytes($script:DatabasePath)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'has a lastUpdated date that is not in the future' {
        [datetime]::ParseExact($script:Database.lastUpdated, 'yyyy-MM-dd', $null) | Should -BeLessOrEqual (Get-Date).AddDays(1)
    }

    It 'has unique rule ids' {
        $duplicates = $script:Database.rules | Group-Object -Property id | Where-Object Count -GT 1
        $duplicates.Name | Should -BeNullOrEmpty
    }

    It 'has no two rules with the same kind and pattern' {
        $duplicates = $script:Database.rules | Group-Object -Property { '{0}|{1}|{2}' -f $_.kind, $_.command, $_.pattern.ToLowerInvariant() } | Where-Object Count -GT 1
        $duplicates.Name | Should -BeNullOrEmpty
    }

    It 'loads through the module without errors' {
        { Get-M365DeprecationRule } | Should -Not -Throw
        @(Get-M365DeprecationRule).Count | Should -Be @($script:Database.rules).Count
    }
}

Describe 'Rule <Id>' -ForEach $script:RuleCases {
    It 'has an id that starts with an upper-case prefix and 4 digits' {
        $Rule.id | Should -MatchExactly '^[A-Z]{2,8}\d{4}$'
    }

    It 'links only to https sources' {
        @($Rule.sources).Count | Should -BeGreaterThan 0
        foreach ($source in $Rule.sources) {
            $source | Should -Match '^https://[^\s]+$'
        }
    }

    It 'has a title that is one sentence ending with a period' {
        $Rule.title | Should -Match '\.$'
        $Rule.title.Length | Should -BeLessOrEqual 160
    }

    It 'uses a valid pattern for its kind' {
        switch ($Rule.kind) {
            'StringLiteral' { { [regex]::new($Rule.pattern) } | Should -Not -Throw }
            'Parameter' { $Rule.command | Should -Not -BeNullOrEmpty; $Rule.pattern | Should -Not -Match '^-' }
            default { $Rule.pattern | Should -Not -Match '\s' }
        }
    }

    It 'has a well-formed retirement date if one is given' {
        if ($Rule.PSObject.Properties['retirementDate']) {
            $Rule.retirementDate | Should -Match '^\d{4}-(0[1-9]|1[0-2])(-(0[1-9]|[12]\d|3[01]))?$'
        }
    }
}

Describe 'Scanner against the built-in database' {
    It 'finds nothing in modern example code' {
        $modern = Join-Path (Split-Path $PSScriptRoot -Parent) 'examples/modern-script.ps1'
        @(Invoke-M365DeprecationScan -Path $modern 6>$null).Count | Should -Be 0
    }

    It 'finds the legacy example code' {
        $legacy = Join-Path (Split-Path $PSScriptRoot -Parent) 'examples/legacy-script.ps1'
        @(Invoke-M365DeprecationScan -Path $legacy).Count | Should -BeGreaterThan 5
    }
}
