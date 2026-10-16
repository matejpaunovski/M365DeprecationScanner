# EXAMPLE ONLY: a module manifest that still depends on retired modules.
#
#     Invoke-M365DeprecationScan -Path .\examples\legacy-module
@{
    RootModule        = 'Contoso.LegacyTools.psm1'
    ModuleVersion     = '1.4.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Contoso IT'
    Description       = 'Helper functions for user and license administration.'

    RequiredModules   = @(
        'MSOnline'
        @{ ModuleName = 'AzureAD'; ModuleVersion = '2.0.2.140' }
        'ExchangeOnlineManagement'
    )
    NestedModules     = @('AzureRM.Profile')

    FunctionsToExport = @('Get-ContosoLicenseReport')
}
