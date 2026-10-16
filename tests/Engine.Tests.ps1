#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1') -Force
    $script:RuleFile = Join-Path $PSScriptRoot 'Fixtures/test-rules.json'

    function Invoke-TestScan {
        param([string]$Code, [hashtable]$Extra = @{})
        Invoke-M365DeprecationScan -ScriptDefinition $Code -ExcludeDefaultRules -CustomRulePath $script:RuleFile @Extra
    }
}

Describe 'Command rules' {
    It 'finds an exact command and reports the replacement' {
        $result = @(Invoke-TestScan 'Get-LegacyUser -All')
        $result.Count | Should -Be 1
        $result[0].RuleId | Should -Be 'TEST0002'
        $result[0].Replacement | Should -Be 'Get-ModernUser'
        $result[0].Severity | Should -Be 'Error'
        $result[0].Line | Should -Be 1
        $result[0].Column | Should -Be 1
    }

    It 'is case-insensitive' {
        (Invoke-TestScan 'get-legacyuser').RuleId | Should -Be 'TEST0002'
    }

    It 'prefers the exact rule over the wildcard catch-all' {
        $result = @(Invoke-TestScan 'Get-LegacyUser')
        $result.RuleId | Should -Not -Contain 'TEST0003'
    }

    It 'uses the wildcard catch-all for commands without an exact rule' {
        (Invoke-TestScan 'Set-LegacyThing -Value 1').RuleId | Should -Be 'TEST0003'
    }

    It 'does not flag names listed in a rule''s exclude list' {
        @(Invoke-TestScan 'Remove-LegacyAlias').Count | Should -Be 0
    }

    It 'handles module-qualified command names' {
        $result = Invoke-TestScan 'LegacyModule\Get-LegacyUser'
        $result.RuleId | Should -Be 'TEST0002'
        $result.Match | Should -Be 'LegacyModule\Get-LegacyUser'
    }

    It 'finds commands inside functions, script blocks and pipelines' {
        $code = @'
function Test-Me {
    1..3 | ForEach-Object { Get-LegacyUser -Id $_ } | Where-Object { $_ }
}
'@
        $result = Invoke-TestScan $code
        $result.RuleId | Should -Be 'TEST0002'
        $result.Line | Should -Be 2
    }

    It 'does not flag commands that are only mentioned in comments' {
        @(Invoke-TestScan '# Get-LegacyUser used to be here').Count | Should -Be 0
        @(Invoke-TestScan "<# Get-LegacyUser #>`nGet-ModernUser").Count | Should -Be 0
    }

    It 'returns nothing for modern code' {
        @(Invoke-TestScan 'Get-ModernUser -All | Select-Object Id').Count | Should -Be 0
    }
}

Describe 'Parameter rules' {
    It 'finds a deprecated parameter on the right command' {
        $result = Invoke-TestScan 'Connect-Service -UseOldProtocol -Tenant x'
        $result.RuleId | Should -Be 'TEST0004'
        $result.Severity | Should -Be 'Warning'
        $result.Column | Should -Be 17
    }

    It 'ignores the same parameter name on other commands' {
        @(Invoke-TestScan 'Connect-Other -UseOldProtocol').Count | Should -Be 0
    }

    It 'finds the parameter in colon syntax' {
        (Invoke-TestScan 'Connect-Service -UseOldProtocol:$true').RuleId | Should -Be 'TEST0004'
    }
}

Describe 'Module rules' {
    It 'finds <Code>' -ForEach @(
        @{ Code = 'Import-Module LegacyModule' }
        @{ Code = 'Import-Module -Name LegacyModule' }
        @{ Code = 'Import-Module -Name:LegacyModule' }
        @{ Code = 'Import-Module -RequiredVersion 1.0 LegacyModule' }
        @{ Code = 'Install-Module LegacyModule -Scope CurrentUser' }
        @{ Code = 'Install-Module -Name Other, LegacyModule' }
        @{ Code = 'Install-PSResource LegacyModule' }
        @{ Code = 'Update-Module LegacyModule' }
        @{ Code = "#Requires -Modules LegacyModule`n'x'" }
        @{ Code = "#Requires -Modules @{ ModuleName = 'LegacyModule'; ModuleVersion = '1.0' }`n'x'" }
        @{ Code = 'using module LegacyModule' }
    ) {
        @(Invoke-TestScan $Code).RuleId | Should -Contain 'TEST0001'
    }

    It 'points #Requires findings at the #Requires line' {
        $result = Invoke-TestScan "'first'`n#Requires -Modules LegacyModule"
        $result.Line | Should -Be 2
    }

    It 'does not flag other modules or dynamic names' {
        @(Invoke-TestScan 'Import-Module ModernModule').Count | Should -Be 0
        @(Invoke-TestScan 'Import-Module $name').Count | Should -Be 0
    }
}

Describe 'String literal rules' {
    It 'finds <Description>' -ForEach @(
        @{ Description = 'single-quoted strings'; Code = "`$u = 'https://old-api.example.com/v1'" }
        @{ Description = 'double-quoted strings'; Code = '$u = "https://old-api.example.com/v1/$id"' }
        @{ Description = 'here-strings'; Code = "`$u = @'`nhttps://old-api.example.com`n'@" }
        @{ Description = 'bare word arguments'; Code = 'Invoke-RestMethod -Uri https://old-api.example.com/v1' }
        @{ Description = 'hashtable values'; Code = "`$p = @{ Uri = 'https://OLD-API.example.com' }" }
    ) {
        $result = Invoke-TestScan $Code
        $result.RuleId | Should -Be 'TEST0005'
        $result.Severity | Should -Be 'Information'
    }

    It 'does not flag the string in comments' {
        @(Invoke-TestScan '# https://old-api.example.com').Count | Should -Be 0
    }
}

Describe 'Suppression comments' {
    It 'suppresses all rules on the same line' {
        @(Invoke-TestScan 'Get-LegacyUser # m365ds-ignore').Count | Should -Be 0
    }

    It 'suppresses only the listed rule ids' {
        @(Invoke-TestScan 'Get-LegacyUser # m365ds-ignore: TEST0002').Count | Should -Be 0
        @(Invoke-TestScan 'Get-LegacyUser # m365ds-ignore: TEST0005').Count | Should -Be 1
        @(Invoke-TestScan 'Get-LegacyUser # m365ds-ignore: test0001, test0002').Count | Should -Be 0
    }

    It 'suppresses the next line' {
        @(Invoke-TestScan "# m365ds-ignore-next-line`nGet-LegacyUser`nGet-LegacyUser").Count | Should -Be 1
    }

    It 'suppresses the whole file' {
        @(Invoke-TestScan "# m365ds-ignore-file`nGet-LegacyUser`nConnect-Service -UseOldProtocol").Count | Should -Be 0
        @(Invoke-TestScan "# m365ds-ignore-file: TEST0002`nGet-LegacyUser`nConnect-Service -UseOldProtocol").RuleId | Should -Be 'TEST0004'
    }
}

Describe 'Filters' {
    BeforeAll {
        $script:AllCode = "Get-LegacyUser`nConnect-Service -UseOldProtocol`n'old-api.example.com'"
    }

    It 'returns findings sorted by position' {
        (Invoke-TestScan $script:AllCode).Line | Should -Be @(1, 2, 3)
    }

    It 'filters by minimum severity' {
        (Invoke-TestScan $script:AllCode -Extra @{ MinimumSeverity = 'Warning' }).Severity | Should -Be @('Error', 'Warning')
        (Invoke-TestScan $script:AllCode -Extra @{ MinimumSeverity = 'Error' }).Severity | Should -Be @('Error')
    }

    It 'excludes rule ids' {
        (Invoke-TestScan $script:AllCode -Extra @{ ExcludeRuleId = 'test0002', 'TEST0005' }).RuleId | Should -Be @('TEST0004')
    }

    It 'filters by area' {
        @(Invoke-TestScan $script:AllCode -Extra @{ Area = 'Other' }).Count | Should -Be 3
        @(Invoke-TestScan $script:AllCode -Extra @{ Area = 'AzureAD' }).Count | Should -Be 0
    }
}

Describe 'File scanning' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'scripts'
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Root 'a.ps1') -Value 'Get-LegacyUser'
        Set-Content -LiteralPath (Join-Path $script:Root 'b.psm1') -Value 'Set-LegacyThing'
        Set-Content -LiteralPath (Join-Path $script:Root 'c.txt') -Value 'Get-LegacyUser'
        Set-Content -LiteralPath (Join-Path $script:Root 'sub/d.ps1') -Value 'Get-LegacyUser'
        Set-Content -LiteralPath (Join-Path $script:Root 'broken.ps1') -Value "Get-LegacyUser`nif ("

        function Invoke-FileScan {
            param([hashtable]$Extra = @{})
            Invoke-M365DeprecationScan -ExcludeDefaultRules -CustomRulePath $script:RuleFile -WarningAction SilentlyContinue @Extra
        }
    }

    It 'scans .ps1 and .psm1 files in a folder' {
        $files = (Invoke-FileScan -Extra @{ Path = $script:Root }).Path | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique
        $files | Should -Be @('a.ps1', 'b.psm1', 'broken.ps1')
    }

    It 'scans sub folders with -Recurse' {
        $files = (Invoke-FileScan -Extra @{ Path = $script:Root; Recurse = $true }).Path | ForEach-Object { Split-Path $_ -Leaf }
        $files | Should -Contain 'd.ps1'
    }

    It 'honours -Include and -Exclude' {
        $files = (Invoke-FileScan -Extra @{ Path = $script:Root; Recurse = $true; Include = '*.ps1'; Exclude = '*sub*' }).Path | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique
        $files | Should -Be @('a.ps1', 'broken.ps1')
    }

    It 'scans an explicitly named file whatever its extension' {
        (Invoke-FileScan -Extra @{ Path = (Join-Path $script:Root 'c.txt') }).RuleId | Should -Be 'TEST0002'
    }

    It 'accepts pipeline input from Get-ChildItem and scans each file once' {
        $result = @(Get-ChildItem -LiteralPath $script:Root -Filter '*.ps1' |
                Invoke-M365DeprecationScan -ExcludeDefaultRules -CustomRulePath $script:RuleFile -WarningAction SilentlyContinue)
        $result.Count | Should -Be 2
    }

    It 'still scans files with syntax errors and warns' {
        $warnings = $null
        $result = Invoke-M365DeprecationScan -Path (Join-Path $script:Root 'broken.ps1') -ExcludeDefaultRules -CustomRulePath $script:RuleFile -WarningVariable warnings -WarningAction SilentlyContinue
        $result.RuleId | Should -Be 'TEST0002'
        $warnings.Count | Should -BeGreaterThan 0
    }

    It 'writes an error for a missing path' {
        { Invoke-FileScan -Extra @{ Path = (Join-Path $script:Root 'nope.ps1'); ErrorAction = 'Stop' } } | Should -Throw
    }
}

Describe 'Module manifests (.psd1)' {
    It 'finds <Description>' -ForEach @(
        @{ Description = 'RequiredModules as a single string'; Code = "@{`n    RequiredModules = 'LegacyModule'`n}" }
        @{ Description = 'RequiredModules as an array'; Code = "@{`n    RequiredModules = @('Other', 'LegacyModule')`n}" }
        @{ Description = 'RequiredModules as a list without @()'; Code = "@{`n    RequiredModules = 'Other', 'LegacyModule'`n}" }
        @{ Description = 'a module specification hashtable'; Code = "@{`n    RequiredModules = @(@{ ModuleName = 'LegacyModule'; ModuleVersion = '1.0' })`n}" }
        @{ Description = 'a mix of strings and specifications'; Code = "@{`n    RequiredModules = @('Other', @{ ModuleName = 'LegacyModule'; RequiredVersion = '2.0' })`n}" }
        @{ Description = 'NestedModules'; Code = "@{`n    NestedModules = @('LegacyModule')`n}" }
        @{ Description = 'keys in any casing'; Code = "@{`n    requiredmodules = @('LegacyModule')`n}" }
        @{ Description = 'quoted keys'; Code = "@{`n    'RequiredModules' = @('LegacyModule')`n}" }
    ) {
        $result = @(Invoke-TestScan $Code)
        $result.RuleId | Should -Contain 'TEST0001'
        ($result | Where-Object RuleId -EQ 'TEST0001').Line | Should -Be 2
    }

    It 'reports what was found in a readable way' {
        (Invoke-TestScan "@{ RequiredModules = @('LegacyModule') }").Match | Should -Be 'RequiredModules LegacyModule'
    }

    It 'points at the module name itself' {
        $result = Invoke-TestScan "@{`n    RequiredModules = @(`n        'Other'`n        'LegacyModule'`n    )`n}"
        $result.Line | Should -Be 4
        $result.Column | Should -Be 9
    }

    It 'does not flag <Description>' -ForEach @(
        @{ Description = 'RootModule or other keys'; Code = "@{ RootModule = 'LegacyModule'; ModuleToProcess = 'LegacyModule'; Description = 'LegacyModule' }" }
        @{ Description = 'modern modules'; Code = "@{ RequiredModules = @('ModernModule', @{ ModuleName = 'ModernModule'; ModuleVersion = '1.0' }) }" }
        @{ Description = 'a hashtable assigned to a variable'; Code = "`$settings = @{ RequiredModules = @('LegacyModule') }" }
        @{ Description = 'a hashtable passed to a command'; Code = "Write-Output @{ RequiredModules = @('LegacyModule') }" }
        @{ Description = 'a nested hashtable'; Code = "@{ PrivateData = @{ RequiredModules = @('LegacyModule') } }" }
        @{ Description = 'dynamic module names'; Code = "@{ RequiredModules = @(`$name) }" }
        @{ Description = 'an empty list'; Code = "@{ RequiredModules = @() }" }
    ) {
        @(Invoke-TestScan $Code | Where-Object RuleId -EQ 'TEST0001').Count | Should -Be 0
    }

    It 'honours suppression comments in a manifest' {
        @(Invoke-TestScan "@{`n    RequiredModules = @('LegacyModule') # m365ds-ignore: TEST0001`n}").Count | Should -Be 0
    }

    It 'finds <Code>' -ForEach @(
        @{ Code = "New-ModuleManifest -Path x.psd1 -RequiredModules 'LegacyModule'" }
        @{ Code = "New-ModuleManifest -Path x.psd1 -RequiredModules @('Other', 'LegacyModule')" }
        @{ Code = "Update-ModuleManifest -Path x.psd1 -NestedModules @(@{ ModuleName = 'LegacyModule'; ModuleVersion = '1.0' })" }
        @{ Code = "New-ModuleManifest -Path x.psd1 -RequiredModules:'LegacyModule'" }
    ) {
        @(Invoke-TestScan $Code).RuleId | Should -Contain 'TEST0001'
    }

    It 'scans .psd1 files in folders by default' {
        $folder = Join-Path $TestDrive 'manifests'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'My.Module.psd1') -Value "@{`n    ModuleVersion = '1.0'`n    RequiredModules = @('LegacyModule')`n}"
        $result = @(Invoke-M365DeprecationScan -Path $folder -ExcludeDefaultRules -CustomRulePath $script:RuleFile)
        $result.Count | Should -Be 1
        Split-Path $result[0].Path -Leaf | Should -Be 'My.Module.psd1'
        $result[0].Line | Should -Be 3
    }
}

Describe 'Edge cases found in review' {
    It 'does not crash on an empty module name' {
        { Invoke-TestScan "Import-Module ''`nImport-Module `"`"" } | Should -Not -Throw
    }

    It 'finds module names in <Code>' -ForEach @(
        @{ Code = 'Install-Module -AcceptLicense LegacyModule' }
        @{ Code = 'Import-Module -EA Stop LegacyModule' }
        @{ Code = 'Import-Module -ProgressAction SilentlyContinue LegacyModule' }
        @{ Code = "Import-Module -Name @('LegacyModule')" }
        @{ Code = "Import-Module -Name ('LegacyModule')" }
        @{ Code = "Import-Module @('Other', 'LegacyModule')" }
        @{ Code = 'Import-Module -Force -Global -PassThru LegacyModule' }
    ) {
        @(Invoke-TestScan $Code).RuleId | Should -Contain 'TEST0001'
    }

    It 'points #Requires at the exact module, not a module with a longer dotted name' {
        $result = Invoke-TestScan "#Requires -Modules LegacyModule.Extra`n#Requires -Modules LegacyModule`n'x'"
        @($result | Where-Object Match -EQ '#Requires -Modules LegacyModule').Line | Should -Be 2
    }

    It 'treats a misspelled suppression scope as no suppression' {
        @(Invoke-TestScan "Get-LegacyUser # m365ds-ignore-nextline`nGet-LegacyUser").Count | Should -Be 2
    }

    It 'accepts rule ids for custom rules in suppression comments' {
        @(Invoke-TestScan 'Get-LegacyUser # m365ds-ignore: TEST0002 - reason here').Count | Should -Be 0
    }

    It 'ignores a deprecated switch that is explicitly turned off' {
        @(Invoke-TestScan 'Connect-Service -UseOldProtocol:$false').Count | Should -Be 0
    }

    It 'reports a URL inside a nested string only once' {
        @(Invoke-TestScan "`"`$('https://old-api.example.com')`"").Count | Should -Be 1
    }

    It 'scans a large script quickly' {
        $code = (1..2000 | ForEach-Object { "Get-ChildItem -Path C:\x$_ | Select-Object -First 1; Write-Output 'a'" }) -join "`n"
        $elapsed = Measure-Command { $null = Invoke-TestScan $code }
        $elapsed.TotalSeconds | Should -BeLessThan 15
    }
}

Describe 'Paths' {
    It 'handles folder names with square brackets' {
        $folder = Join-Path $TestDrive 'scripts[old]'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'a.ps1') -Value 'Get-LegacyUser'
        @(Invoke-M365DeprecationScan -Path $folder -ExcludeDefaultRules -CustomRulePath $script:RuleFile).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $folder | Invoke-M365DeprecationScan -ExcludeDefaultRules -CustomRulePath $script:RuleFile).Count | Should -Be 1
    }

    It 'accepts forward-slash -Exclude patterns on every OS' {
        $folder = Join-Path $TestDrive 'excl'
        New-Item -ItemType Directory -Path (Join-Path $folder 'tests') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'tests/a.ps1') -Value 'Get-LegacyUser'
        Set-Content -LiteralPath (Join-Path $folder 'b.ps1') -Value 'Get-LegacyUser'
        $result = @(Invoke-M365DeprecationScan -Path $folder -Recurse -Exclude '*/tests/*' -ExcludeDefaultRules -CustomRulePath $script:RuleFile)
        $result.Count | Should -Be 1
        Split-Path $result[0].Path -Leaf | Should -Be 'b.ps1'
    }
}

Describe 'Rule loading' {
    It 'rejects rule ids that do not follow the id format' {
        $file = Join-Path $TestDrive 'badid.json'
        Set-Content -LiteralPath $file -Value '{"schemaVersion":1,"lastUpdated":"2026-01-01","rules":[{"id":"org-1","kind":"Command","pattern":"Foo","status":"Retired","title":"Foo is gone.","replacement":"Bar","sources":["https://example.com"]}]}'
        { Invoke-M365DeprecationScan -ScriptDefinition 'x' -ExcludeDefaultRules -CustomRulePath $file } | Should -Throw '*invalid*'
    }

    It 'throws a clear error for invalid JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ not json'
        { Invoke-M365DeprecationScan -ScriptDefinition 'x' -ExcludeDefaultRules -CustomRulePath $bad } | Should -Throw '*not valid JSON*'
    }

    It 'throws for duplicate rule ids across files' {
        { Invoke-M365DeprecationScan -ScriptDefinition 'x' -ExcludeDefaultRules -CustomRulePath $script:RuleFile, $script:RuleFile } | Should -Throw '*Duplicate rule id*'
    }

    It 'throws when there are no rules at all' {
        { Invoke-M365DeprecationScan -ScriptDefinition 'x' -ExcludeDefaultRules } | Should -Throw '*No rules*'
    }

    It 'rejects a Parameter rule without a command' {
        $file = Join-Path $TestDrive 'param.json'
        Set-Content -LiteralPath $file -Value '{"schemaVersion":1,"lastUpdated":"2026-01-01","rules":[{"id":"XX0001","kind":"Parameter","pattern":"Foo","status":"Retired","title":"Foo is gone.","replacement":"Bar","sources":["https://example.com"]}]}'
        { Invoke-M365DeprecationScan -ScriptDefinition 'x' -ExcludeDefaultRules -CustomRulePath $file } | Should -Throw '*needs a*command*'
    }
}
