function New-NamePattern {
    <#
    .SYNOPSIS
        Pre-compiles a case-insensitive name pattern (exact name or * ? wildcards).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only creates an in-memory object.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.WildcardPattern])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )
    # WildcardPattern also handles exact names; escape [ and ] so they are matched literally.
    $escaped = $Pattern.Replace('`', '``').Replace('[', '`[').Replace(']', '`]')
    New-Object System.Management.Automation.WildcardPattern -ArgumentList $escaped, ([System.Management.Automation.WildcardOptions]::IgnoreCase)
}

function Test-NamePattern {
    <#
    .SYNOPSIS
        Case-insensitive name comparison that supports * and ? wildcards.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Pattern
    )
    return (New-NamePattern -Pattern $Pattern).IsMatch($Name)
}

function New-RuleIndex {
    <#
    .SYNOPSIS
        Builds a lookup structure for name-based rules (Command or Module) so matching stays fast.
    .DESCRIPTION
        Exact names go into a case-insensitive dictionary (O(1) lookup). Wildcard rules are kept in a
        short list ordered from most to least specific (longest pattern first).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only creates an in-memory object.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    $exact = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $wildcards = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $Rules) {
        if ($rule.IsWildcard) {
            $wildcards.Add($rule)
        }
        elseif (-not $exact.ContainsKey($rule.Pattern)) {
            $exact[$rule.Pattern] = $rule
        }
    }
    @{
        Exact     = $exact
        Wildcards = @($wildcards | Sort-Object -Property @{ Expression = { $_.Pattern.Length }; Descending = $true })
        Count     = $Rules.Count
    }
}

function Select-MatchingRule {
    <#
    .SYNOPSIS
        Returns the single most specific name-based rule (Command or Module) that matches a name.
    .DESCRIPTION
        An exact rule (e.g. 'Get-MsolUser') always wins over a wildcard catch-all (e.g. '*-Msol*').
        Between several wildcard rules, the longest pattern is considered the most specific.
        Names listed in a rule's 'exclude' never match that rule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Index,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ($Index.Count -eq 0 -or [string]::IsNullOrEmpty($Name)) {
        return $null
    }

    $rule = $null
    if ($Index.Exact.TryGetValue($Name, [ref]$rule) -and -not (Test-RuleExclusion -Rule $rule -Name $Name)) {
        return $rule
    }
    foreach ($candidate in $Index.Wildcards) {
        if ($candidate.Matcher.IsMatch($Name) -and -not (Test-RuleExclusion -Rule $candidate -Name $Name)) {
            return $candidate
        }
    }
    return $null
}

function Test-RuleExclusion {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Rule,

        [Parameter(Mandatory)]
        [string]$Name
    )
    foreach ($matcher in $Rule.ExcludeMatchers) {
        if ($matcher.IsMatch($Name)) {
            return $true
        }
    }
    return $false
}
