function Get-DeprecationRuleSet {
    <#
    .SYNOPSIS
        Loads one or more rule database files and returns compiled rule objects.
    .DESCRIPTION
        Reads the JSON rule database (by default the one shipped with the module), validates the
        fields the engine relies on and pre-compiles the matchers (wildcards and regular expressions)
        so scanning many files stays fast. Results are cached per file until the file changes.
    #>
    [CmdletBinding()]
    [OutputType('M365DeprecationScanner.Rule')]
    param(
        # Rule database files to load. Defaults to the database shipped with the module.
        [string[]]$Path = @(Join-Path -Path $script:ModuleRoot -ChildPath 'Data/deprecations.json')
    )

    if (-not (Test-Path -Path variable:script:RuleCache)) {
        $script:RuleCache = @{}
    }

    $seenIds = @{}
    foreach ($file in $Path) {
        $resolved = (Resolve-Path -LiteralPath $file -ErrorAction Stop).ProviderPath
        $stamp = (Get-Item -LiteralPath $resolved).LastWriteTimeUtc

        $cached = $script:RuleCache[$resolved]
        if ($null -eq $cached -or $cached.Stamp -ne $stamp) {
            $cached = @{
                Stamp = $stamp
                Rules = @(Import-DeprecationRuleFile -Path $resolved)
            }
            $script:RuleCache[$resolved] = $cached
        }

        foreach ($rule in $cached.Rules) {
            if ($seenIds.ContainsKey($rule.Id)) {
                throw "Duplicate rule id '$($rule.Id)' in '$resolved' (already defined in '$($seenIds[$rule.Id])')."
            }
            $seenIds[$rule.Id] = $resolved
            $rule
        }
    }
}

function Import-DeprecationRuleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $database = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Rule file '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if (-not $database.PSObject.Properties['rules']) {
        throw "Rule file '$Path' has no 'rules' array."
    }

    $severityByStatus = @{
        Retired    = 'Error'
        Deprecated = 'Warning'
        Announced  = 'Information'
    }

    foreach ($entry in $database.rules) {
        foreach ($required in 'id', 'kind', 'pattern', 'status', 'title', 'replacement') {
            if (-not $entry.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$entry.$required)) {
                throw "A rule in '$Path' is missing the required field '$required'."
            }
        }
        $id = [string]$entry.id
        $kind = [string]$entry.kind
        $status = [string]$entry.status

        if ($id -cnotmatch '^[A-Z]{2,8}\d{4}$') {
            throw "Rule id '$id' in '$Path' is invalid. Use 2-8 upper-case letters followed by 4 digits, for example ORG0001."
        }
        if ($kind -notin 'Command', 'Parameter', 'Module', 'StringLiteral') {
            throw "Rule '$id' in '$Path' has unknown kind '$kind'."
        }
        if (-not $severityByStatus.ContainsKey($status)) {
            throw "Rule '$id' in '$Path' has unknown status '$status'."
        }

        $pattern = [string]$entry.pattern
        $commandPattern = $null
        $regex = $null
        if ($kind -eq 'StringLiteral') {
            try {
                $options = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
                $regex = New-Object -TypeName System.Text.RegularExpressions.Regex -ArgumentList $pattern, $options, ([timespan]::FromSeconds(1))
            }
            catch {
                throw "Rule '$id' in '$Path' has an invalid regular expression: $($_.Exception.Message)"
            }
        }
        if ($kind -eq 'Parameter') {
            if (-not $entry.PSObject.Properties['command'] -or [string]::IsNullOrWhiteSpace([string]$entry.command)) {
                throw "Rule '$id' in '$Path' is a Parameter rule and needs a 'command'."
            }
            $commandPattern = [string]$entry.command
        }

        # Pre-compiled matchers keep scanning fast: no pattern is parsed again per command.
        $matcher = $null
        $commandMatcher = $null
        if ($kind -ne 'StringLiteral') {
            $matcher = New-NamePattern -Pattern $pattern
        }
        if ($commandPattern) {
            $commandMatcher = New-NamePattern -Pattern $commandPattern
        }
        $exclude = @(Get-OptionalProperty -InputObject $entry -Name 'exclude' -Default @() | ForEach-Object { [string]$_ } | Where-Object { $_ })

        [pscustomobject]@{
            PSTypeName        = 'M365DeprecationScanner.Rule'
            Id                = $id
            Kind              = $kind
            Pattern           = $pattern
            Command           = $commandPattern
            Area              = Get-OptionalProperty -InputObject $entry -Name 'area' -Default 'Other'
            Module            = Get-OptionalProperty -InputObject $entry -Name 'module'
            Status            = $status
            Severity          = $severityByStatus[$status]
            RetirementDate    = Get-OptionalProperty -InputObject $entry -Name 'retirementDate'
            Title             = [string]$entry.title
            Replacement       = [string]$entry.replacement
            ReplacementModule = Get-OptionalProperty -InputObject $entry -Name 'replacementModule'
            Notes             = Get-OptionalProperty -InputObject $entry -Name 'notes'
            Sources           = @(Get-OptionalProperty -InputObject $entry -Name 'sources' -Default @())
            Exclude           = $exclude
            IsWildcard        = ($kind -ne 'StringLiteral') -and [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($pattern)
            Regex             = $regex
            Matcher           = $matcher
            CommandMatcher    = $commandMatcher
            ExcludeMatchers   = @($exclude | ForEach-Object { New-NamePattern -Pattern $_ })
            SourceFile        = $Path
        }
    }
}

function Get-OptionalProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [object]$Default = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) {
        return $property.Value
    }
    return $Default
}
