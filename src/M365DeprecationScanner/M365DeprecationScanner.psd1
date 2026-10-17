@{
    RootModule           = 'M365DeprecationScanner.psm1'
    ModuleVersion        = '0.3.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID                 = 'b6f0a3d2-5c1e-4f7a-9d38-2e6c4a8b1f57'
    Author               = 'Matej'
    CompanyName          = 'Community'
    Copyright            = '(c) 2026 Matej. MIT License.'
    Description          = 'Finds deprecated and retired Microsoft 365, Entra ID and Azure PowerShell commands (MSOnline, AzureAD, Exchange RPS, AzureRM, Azure AD Graph, ...) in your scripts and tells you what to use instead. Works as a command, as a PSScriptAnalyzer rule in VS Code and as a GitHub Action.'
    PowerShellVersion    = '5.1'

    FunctionsToExport    = @(
        'Invoke-M365DeprecationScan'
        'Get-M365DeprecationRule'
        'Export-M365DeprecationReport'
        'Get-M365DeprecationAnalyzerRulePath'
        'New-M365DeprecationAnalyzerSettings'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    FormatsToProcess     = @('M365DeprecationScanner.Format.ps1xml')

    PrivateData          = @{
        PSData = @{
            Tags         = @('Microsoft365', 'M365', 'Entra', 'EntraID', 'AzureAD', 'MSOnline', 'MicrosoftGraph', 'ExchangeOnline', 'Azure', 'Deprecation', 'Migration', 'Linter', 'PSScriptAnalyzer', 'Windows', 'Linux', 'MacOS', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/matejpaunovski/M365DeprecationScanner/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/matejpaunovski/M365DeprecationScanner'
            ReleaseNotes = 'https://github.com/matejpaunovski/M365DeprecationScanner/blob/main/CHANGELOG.md'
        }
    }
}
