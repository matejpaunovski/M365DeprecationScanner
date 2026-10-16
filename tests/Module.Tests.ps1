#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:PublicFunctions = Get-ChildItem -Path (Join-Path $repoRoot 'src/M365DeprecationScanner/Public') -Filter '*.ps1' |
        ForEach-Object { @{ Name = $_.BaseName } }
}

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ManifestPath = Join-Path $repoRoot 'src/M365DeprecationScanner/M365DeprecationScanner.psd1'
    Import-Module $script:ManifestPath -Force
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the functions in the Public folder' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $publicFiles = (Get-ChildItem -Path (Join-Path (Split-Path $script:ManifestPath) 'Public') -Filter '*.ps1').BaseName
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($publicFiles | Sort-Object)
        @((Get-Command -Module M365DeprecationScanner).Name | Sort-Object) | Should -Be @($publicFiles | Sort-Object)
    }

    It 'has a CHANGELOG entry for the current version' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $changelog = Get-Content -Raw -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'CHANGELOG.md')
        $changelog | Should -Match ([regex]::Escape("## [$($manifest.ModuleVersion)]"))
    }
}

Describe 'Help for <Name>' -ForEach $script:PublicFunctions {
    BeforeAll {
        $script:Help = Get-Help -Name $Name -Full
        $script:Command = Get-Command -Name $Name
    }

    It 'has a synopsis and a description' {
        $script:Help.Synopsis | Should -Not -BeNullOrEmpty
        $script:Help.Synopsis | Should -Not -Match "^\s*$Name\s"
        ($script:Help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
    }

    It 'has at least one example' {
        @($script:Help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        foreach ($parameter in $script:Command.Parameters.Keys | Where-Object { $_ -notin $common }) {
            $parameterHelp = $script:Help.Parameters.Parameter | Where-Object Name -EQ $parameter
            ($parameterHelp.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty -Because "-$parameter of $Name needs a description"
        }
    }
}

Describe 'New-M365DeprecationAnalyzerSettings' {
    It 'writes a data-only settings file pointing at the rule module' {
        $target = Join-Path $TestDrive 'PSScriptAnalyzerSettings.psd1'
        New-M365DeprecationAnalyzerSettings -Path $target | Should -Not -BeNullOrEmpty
        $settings = Import-PowerShellDataFile -Path $target
        $settings.CustomRulePath | Should -Be @(Get-M365DeprecationAnalyzerRulePath)
        $settings.IncludeDefaultRules | Should -BeTrue
        Test-Path -LiteralPath $settings.CustomRulePath[0] | Should -BeTrue
    }

    It 'does not overwrite without -Force' {
        $target = Join-Path $TestDrive 'existing.psd1'
        Set-Content -LiteralPath $target -Value '@{}'
        { New-M365DeprecationAnalyzerSettings -Path $target } | Should -Throw '*already exists*'
        { New-M365DeprecationAnalyzerSettings -Path $target -Force -ExcludeDefaultRules } | Should -Not -Throw
        (Import-PowerShellDataFile -Path $target).IncludeDefaultRules | Should -BeFalse
    }
}

Describe 'Get-M365DeprecationRule' {
    It 'returns rule objects' {
        $rule = Get-M365DeprecationRule | Select-Object -First 1
        $rule.PSObject.TypeNames | Should -Contain 'M365DeprecationScanner.Rule'
    }

    It 'filters by id with wildcards' {
        $first = Get-M365DeprecationRule | Select-Object -First 1
        $prefix = $first.Id.Substring(0, $first.Id.Length - 4)
        Get-M365DeprecationRule -Id "$prefix*" | ForEach-Object { $_.Id | Should -BeLike "$prefix*" }
    }

    It 'returns nothing for a modern command name' {
        Get-M365DeprecationRule -Name 'Get-ChildItem' | Should -BeNullOrEmpty
    }
}
