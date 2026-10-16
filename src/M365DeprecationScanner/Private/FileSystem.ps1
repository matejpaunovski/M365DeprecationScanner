function Get-ScanTarget {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Recurse,

        [string[]]$Include,

        [string[]]$Exclude
    )

    # Literal first, so names like 'scripts[old]' work; then wildcard paths such as '.\*.ps1'.
    if (Test-Path -LiteralPath $Path) {
        $resolvedItems = @(Resolve-Path -LiteralPath $Path)
    }
    else {
        $resolvedItems = @(Resolve-Path -Path $Path -ErrorAction SilentlyContinue)
    }
    if ($resolvedItems.Count -eq 0) {
        Write-Error -Message "Path not found: $Path" -Category ObjectNotFound -TargetObject $Path
        return
    }

    foreach ($resolved in $resolvedItems) {
        $item = Get-Item -LiteralPath $resolved.ProviderPath -Force
        if ($item.PSIsContainer) {
            # Symbolic links found while walking a folder are skipped: they may point outside the
            # folder (for example a link to a secrets file committed in a pull request).
            $files = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $name = $_.Name
                    -not (Test-ReparsePoint -Item $_) -and @($Include | Where-Object { $name -like $_ }).Count -gt 0
                }
        }
        else {
            # A file passed explicitly is always scanned, whatever its extension.
            $files = @($item)
        }

        foreach ($file in $files) {
            $fullName = $file.FullName
            # Compare with forward slashes so '*/tests/*' works on Windows and Linux alike.
            $normalized = $fullName.Replace('\', '/')
            if ($Exclude -and @($Exclude | Where-Object { $normalized -like $_.Replace('\', '/') }).Count -gt 0) {
                continue
            }
            $fullName
        }
    }
}

function Write-ParseErrorWarning {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Management.Automation.Language.ParseError[]]$ParseErrors,

        [Parameter(Mandatory)]
        [string]$Source
    )

    # 'using module X' reports a parse error when X is not installed. That is expected when scanning
    # legacy scripts (the whole point is that MSOnline & co. are gone), so it is not worth a warning.
    $relevant = @($ParseErrors | Where-Object { $_ -and $_.ErrorId -ne 'ModuleNotFoundDuringParse' })
    if ($relevant.Count -gt 0) {
        $first = $relevant[0]
        $text = '{0} has {1} syntax error(s), results may be incomplete. First: line {2}: {3}' -f $Source, $relevant.Count, $first.Extent.StartLineNumber, $first.Message
        # Parse error messages quote the scanned code. Keep them on one line so scanned content can
        # never start a new log line (CI systems interpret lines such as '::warning::' as commands).
        Write-Warning (ConvertTo-SingleLine -Text $text)
    }
}


function Test-ReparsePoint {
    <#
    .SYNOPSIS
        True for symbolic links, junctions and other reparse points.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )
    return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function ConvertTo-SingleLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ($null -eq $Text) { return '' }
    return ($Text -replace '[\r\n\u0085\u2028\u2029]+', ' ')
}

function Assert-WritableReportTarget {
    <#
    .SYNOPSIS
        Refuses to write through a symbolic link or over an existing file without -Force.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $existing = Get-Item -LiteralPath $Path -Force
    if (Test-ReparsePoint -Item $existing) {
        throw "Refusing to write '$Path' because it is a symbolic link or junction."
    }
    if ($existing.PSIsContainer) {
        throw "'$Path' is a folder. Pass a file path."
    }
    if (-not $Force) {
        throw "File '$Path' already exists. Use -Force to overwrite it."
    }
}
