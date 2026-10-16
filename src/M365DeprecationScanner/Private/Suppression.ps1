function Get-SuppressionMap {
    <#
    .SYNOPSIS
        Reads suppression comments from the token stream.
    .DESCRIPTION
        Supported comments (rule ids are optional and comma separated):
          # m365ds-ignore-file[: ID1, ID2]       whole file
          # m365ds-ignore-next-line[: ID1, ID2]  the line after the comment
          # m365ds-ignore[: ID1, ID2]            the line the comment is on
        Without ids, every rule is suppressed.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Management.Automation.Language.Token[]]$Tokens
    )

    $map = @{
        File  = New-Object System.Collections.Generic.List[string]
        Lines = @{}
    }
    if (-not $Tokens) {
        return $map
    }

    # The scope must be followed by a non-word character, so a typo such as 'm365ds-ignore-nextline'
    # does not silently fall back to 'ignore this line'.
    $pattern = 'm365ds-ignore(?<scope>-next-line|-file)?(?![\w-])(?:\s*:\s*(?<ids>[\w.-]+(?:\s*,\s*[\w.-]+)*))?'
    foreach ($token in $Tokens) {
        if ($token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) {
            continue
        }
        foreach ($match in [regex]::Matches($token.Text, $pattern, 'IgnoreCase')) {
            $ids = @('*')
            if ($match.Groups['ids'].Success) {
                $ids = @($match.Groups['ids'].Value -split '\s*,\s*' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
            }

            switch ($match.Groups['scope'].Value.ToLowerInvariant()) {
                '-file' {
                    $map.File.AddRange([string[]]$ids)
                }
                '-next-line' {
                    Add-SuppressedLine -Map $map -Line ($token.Extent.EndLineNumber + 1) -Ids $ids
                }
                default {
                    Add-SuppressedLine -Map $map -Line $token.Extent.StartLineNumber -Ids $ids
                }
            }
        }
    }
    return $map
}

function Add-SuppressedLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Map,

        [Parameter(Mandatory)]
        [int]$Line,

        [Parameter(Mandatory)]
        [string[]]$Ids
    )

    if (-not $Map.Lines.ContainsKey($Line)) {
        $Map.Lines[$Line] = New-Object System.Collections.Generic.List[string]
    }
    $Map.Lines[$Line].AddRange($Ids)
}

function Test-Suppressed {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SuppressionMap,

        [Parameter(Mandatory)]
        [int]$Line,

        [Parameter(Mandatory)]
        [string]$RuleId
    )

    $id = $RuleId.ToUpperInvariant()
    if ($SuppressionMap.File.Contains('*') -or $SuppressionMap.File.Contains($id)) {
        return $true
    }
    $lineIds = $SuppressionMap.Lines[$Line]
    return ($null -ne $lineIds) -and ($lineIds.Contains('*') -or $lineIds.Contains($id))
}
