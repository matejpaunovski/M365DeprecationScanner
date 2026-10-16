function Get-M365DeprecationRule {
    <#
    .SYNOPSIS
        Lists the deprecation rules, or looks up what replaces a specific command or module.

    .DESCRIPTION
        Without parameters, returns every rule in the built-in database. Use -Name to answer the
        question "what do I use instead of X?" for a command or module name, or filter by -Id,
        -Area or -Status.

    .PARAMETER Name
        A command or module name to look up, for example Get-MsolUser or AzureAD. Returns the rule
        the scanner would apply (an exact rule wins over a wildcard catch-all).

    .PARAMETER Id
        One or more rule ids. Wildcards are allowed, for example 'EXO*'.

    .PARAMETER Area
        Only return rules for these product areas.

    .PARAMETER Status
        Only return rules with this status: Retired, Deprecated or Announced.

    .PARAMETER CustomRulePath
        Additional rule database files to include.

    .EXAMPLE
        Get-M365DeprecationRule -Name Get-MsolUser

        Shows that Get-MsolUser is retired and that Get-MgUser replaces it.

    .EXAMPLE
        Get-M365DeprecationRule -Area ExchangeOnline | Format-List

        Shows all Exchange Online rules with notes and source links.

    .EXAMPLE
        Get-M365DeprecationRule | Group-Object Area | Sort-Object Count -Descending

        Counts rules per product area.

    .OUTPUTS
        M365DeprecationScanner.Rule

    .LINK
        https://github.com/matejpaunovski/M365DeprecationScanner/blob/main/docs/rules.md
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType('M365DeprecationScanner.Rule')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Name', Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'Filter')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('MSOnline', 'AzureAD', 'ExchangeOnline', 'MicrosoftGraph', 'AzureADGraph', 'Azure', 'Teams', 'SharePoint', 'Intune', 'Other')]
        [string[]]$Area,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Retired', 'Deprecated', 'Announced')]
        [string[]]$Status,

        [string[]]$CustomRulePath
    )

    begin {
        $rulePaths = @(Join-Path -Path $script:ModuleRoot -ChildPath 'Data/deprecations.json')
        if ($CustomRulePath) {
            $rulePaths += $CustomRulePath
        }
        $rules = @(Get-DeprecationRuleSet -Path $rulePaths)
        $commandIndex = New-RuleIndex -Rules @($rules | Where-Object Kind -EQ 'Command')
        $moduleIndex = New-RuleIndex -Rules @($rules | Where-Object Kind -EQ 'Module')
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Name') {
            foreach ($item in $Name) {
                $bareName = $item.Substring($item.LastIndexOf('\') + 1)
                $commandRule = Select-MatchingRule -Index $commandIndex -Name $bareName
                $moduleRule = Select-MatchingRule -Index $moduleIndex -Name $bareName
                if ($commandRule) { $commandRule }
                if ($moduleRule) { $moduleRule }
                if (-not $commandRule -and -not $moduleRule) {
                    Write-Verbose "No deprecation rule matches '$item'."
                }
            }
            return
        }

        $rules | Where-Object {
            $rule = $_
            (-not $Id -or @($Id | Where-Object { $rule.Id -like $_ }).Count -gt 0) -and
            (-not $Area -or $Area -contains $rule.Area) -and
            (-not $Status -or $Status -contains $rule.Status)
        }
    }
}
