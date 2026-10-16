function ConvertTo-ReportRow {
    <#
    .SYNOPSIS
        Flattens a finding into the shape used by every report format (no AST objects, relative paths).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Finding,

        [string]$BasePath
    )

    [pscustomobject][ordered]@{
        RuleId            = [string]$Finding.RuleId
        Severity          = [string]$Finding.Severity
        Status            = [string]$Finding.Status
        Area              = [string]$Finding.Area
        Kind              = [string]$Finding.Kind
        File              = Get-RelativeReportPath -Path $Finding.Path -BasePath $BasePath
        Line              = [int]$Finding.Line
        Column            = [int]$Finding.Column
        EndLine           = [int]$Finding.EndLine
        EndColumn         = [int]$Finding.EndColumn
        Match             = [string]$Finding.Match
        Title             = [string]$Finding.Title
        Replacement       = [string]$Finding.Replacement
        ReplacementModule = [string]$Finding.ReplacementModule
        RetirementDate    = [string]$Finding.RetirementDate
        Notes             = [string]$Finding.Notes
        Message           = [string]$Finding.Message
        LineText          = [string]$Finding.LineText
        Sources           = @($Finding.Sources | ForEach-Object { [string]$_ })
    }
}

function Get-RelativeReportPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Path,

        [AllowNull()]
        [string]$BasePath
    )

    if ([string]::IsNullOrEmpty($Path)) {
        return '<script>'
    }
    $result = $Path
    if ($BasePath) {
        $base = $BasePath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($Path.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result = $Path.Substring($base.Length)
        }
    }
    return $result.Replace('\', '/')
}

function ConvertTo-CsvReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    if ($Rows.Count -eq 0) {
        return '"RuleId","Severity","Status","Area","Kind","File","Line","Column","EndLine","EndColumn","Match","Title","Replacement","ReplacementModule","RetirementDate","Notes","Message","LineText","Sources"'
    }
    $flat = foreach ($row in $Rows) {
        $copy = $row.PSObject.Copy()
        $copy.Sources = $row.Sources -join ' '
        # Spreadsheet apps run cells starting with = + - @ as formulas; prefix them with a quote.
        foreach ($property in $copy.PSObject.Properties) {
            if ($property.Value -is [string] -and $property.Value -match '^[=+\-@\t\r]') {
                $property.Value = "'" + $property.Value
            }
        }
        $copy
    }
    return ($flat | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
}

function Get-ReportSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    [pscustomobject]@{
        Total       = $Rows.Count
        Files       = @($Rows | Select-Object -ExpandProperty File -Unique).Count
        Error       = @($Rows | Where-Object Severity -EQ 'Error').Count
        Warning     = @($Rows | Where-Object Severity -EQ 'Warning').Count
        Information = @($Rows | Where-Object Severity -EQ 'Information').Count
        Areas       = @($Rows | Group-Object -Property Area | Sort-Object -Property Count -Descending)
    }
}

function ConvertTo-HtmlEncoded {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function ConvertTo-HtmlReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [string]$Title
    )

    $summary = Get-ReportSummary -Rows $Rows
    $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $sortedRows = @($Rows | Sort-Object -Property @{ Expression = { @{ Error = 0; Warning = 1; Information = 2 }[$_.Severity] } }, File, Line)

    $tableRows = New-Object System.Text.StringBuilder
    foreach ($row in $sortedRows) {
        $sourceLinks = @($row.Sources | ForEach-Object {
                $uri = $null
                if ($_ -match '^https://' -and [uri]::TryCreate($_, [System.UriKind]::Absolute, [ref]$uri)) {
                    '<a href="{0}" target="_blank" rel="noopener noreferrer">{1}</a>' -f (ConvertTo-HtmlEncoded $uri.AbsoluteUri), (ConvertTo-HtmlEncoded $uri.Host)
                }
            }) -join '<br>'
        $notes = if ($row.Notes) { '<div class="notes">{0}</div>' -f (ConvertTo-HtmlEncoded $row.Notes) } else { '' }
        $retirement = if ($row.RetirementDate) { '<div class="muted">Retirement: {0}</div>' -f (ConvertTo-HtmlEncoded $row.RetirementDate) } else { '' }
        $replacementModule = if ($row.ReplacementModule) { '<div class="muted">Module: {0}</div>' -f (ConvertTo-HtmlEncoded $row.ReplacementModule) } else { '' }

        [void]$tableRows.AppendLine(('<tr data-severity="{0}">' -f (ConvertTo-HtmlEncoded $row.Severity)))
        [void]$tableRows.AppendLine(('  <td><span class="badge {0}">{1}</span></td>' -f (ConvertTo-HtmlEncoded $row.Severity.ToLowerInvariant()), (ConvertTo-HtmlEncoded $row.Status)))
        [void]$tableRows.AppendLine(('  <td class="file"><code>{0}:{1}</code><div class="code">{2}</div></td>' -f (ConvertTo-HtmlEncoded $row.File), $row.Line, (ConvertTo-HtmlEncoded $row.LineText)))
        [void]$tableRows.AppendLine(('  <td><code>{0}</code><div class="muted">{1} &middot; {2}</div></td>' -f (ConvertTo-HtmlEncoded $row.Match), (ConvertTo-HtmlEncoded $row.RuleId), (ConvertTo-HtmlEncoded $row.Area)))
        [void]$tableRows.AppendLine(('  <td>{0}{1}{2}</td>' -f (ConvertTo-HtmlEncoded $row.Title), $retirement, $notes))
        [void]$tableRows.AppendLine(('  <td><code>{0}</code>{1}</td>' -f (ConvertTo-HtmlEncoded $row.Replacement), $replacementModule))
        [void]$tableRows.AppendLine(('  <td class="sources">{0}</td>' -f $sourceLinks))
        [void]$tableRows.AppendLine('</tr>')
    }

    $areaChips = ($summary.Areas | ForEach-Object { '<span class="chip">{0} <b>{1}</b></span>' -f (ConvertTo-HtmlEncoded $_.Name), $_.Count }) -join ' '
    $body = if ($Rows.Count -eq 0) {
        '<div class="empty">&#10004; No deprecated commands found. Nice work!</div>'
    }
    else {
        @"
<div class="toolbar">
  <input id="search" type="search" placeholder="Filter by file, command, rule ..." aria-label="Filter findings">
  <label><input type="checkbox" class="sev" value="Error" checked> Retired</label>
  <label><input type="checkbox" class="sev" value="Warning" checked> Deprecated</label>
  <label><input type="checkbox" class="sev" value="Information" checked> Announced</label>
</div>
<div class="areas">$areaChips</div>
<div class="table-wrap">
<table>
<thead><tr><th>Status</th><th>Where</th><th>Found</th><th>Problem</th><th>Use instead</th><th>Source</th></tr></thead>
<tbody>
$($tableRows.ToString())</tbody>
</table>
</div>
"@
    }

    # Inline script for the search box. It is allowed by hash in the Content-Security-Policy, so the
    # browser runs nothing else, even if a scanned value somehow got past HTML encoding.
    $filterScript = @'
(function () {
  var search = document.getElementById('search');
  if (!search) { return; }
  var boxes = Array.prototype.slice.call(document.querySelectorAll('input.sev'));
  var rows = Array.prototype.slice.call(document.querySelectorAll('tbody tr'));
  function apply() {
    var q = search.value.toLowerCase();
    var allowed = boxes.filter(function (b) { return b.checked; }).map(function (b) { return b.value; });
    rows.forEach(function (r) {
      var show = allowed.indexOf(r.getAttribute('data-severity')) !== -1 && r.textContent.toLowerCase().indexOf(q) !== -1;
      r.style.display = show ? '' : 'none';
    });
  }
  search.addEventListener('input', apply);
  boxes.forEach(function (b) { b.addEventListener('change', apply); });
})();
'@
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $scriptHash = [Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($filterScript)))
    $sha256.Dispose()

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'sha256-$scriptHash'">
<title>$(ConvertTo-HtmlEncoded $Title)</title>
<style>
:root { --bg:#f7f7f8; --card:#fff; --text:#1d1d1f; --muted:#6b6b76; --border:#e3e3e8; --error:#c62828; --warning:#b26a00; --info:#1565c0; --code:#f0f0f3; }
@media (prefers-color-scheme: dark) { :root { --bg:#16161a; --card:#1f1f24; --text:#ececf1; --muted:#9a9aa6; --border:#33333b; --error:#ef5350; --warning:#ffb74d; --info:#64b5f6; --code:#2a2a31; } }
* { box-sizing:border-box; }
body { margin:0; padding:24px 16px; background:var(--bg); color:var(--text); font:14px/1.5 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
main { max-width:1280px; margin:0 auto; }
h1 { font-size:22px; margin:0 0 4px; }
.muted { color:var(--muted); font-size:12px; }
.cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin:20px 0; }
.card { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:14px; }
.card .num { font-size:26px; font-weight:600; }
.card.error .num { color:var(--error); } .card.warning .num { color:var(--warning); } .card.info .num { color:var(--info); }
.toolbar { display:flex; flex-wrap:wrap; gap:12px; align-items:center; margin-bottom:10px; }
.toolbar input[type=search] { flex:1 1 260px; padding:8px 10px; border:1px solid var(--border); border-radius:8px; background:var(--card); color:var(--text); }
.areas { margin-bottom:12px; } .chip { display:inline-block; background:var(--card); border:1px solid var(--border); border-radius:999px; padding:2px 10px; margin:0 6px 6px 0; font-size:12px; }
.table-wrap { overflow-x:auto; background:var(--card); border:1px solid var(--border); border-radius:10px; }
table { border-collapse:collapse; width:100%; min-width:980px; }
td.file { min-width:200px; } td.file code { word-break:normal; overflow-wrap:anywhere; } td:nth-child(3), td:nth-child(5) { min-width:170px; } td.sources { min-width:150px; }
th, td { text-align:left; vertical-align:top; padding:10px 12px; border-bottom:1px solid var(--border); }
th { font-size:12px; text-transform:uppercase; letter-spacing:.04em; color:var(--muted); }
code { background:var(--code); padding:1px 5px; border-radius:4px; font-family:Consolas,"Cascadia Code",Menlo,monospace; font-size:12.5px; word-break:break-word; }
.code { font-family:Consolas,"Cascadia Code",Menlo,monospace; font-size:12px; color:var(--muted); margin-top:4px; white-space:pre-wrap; word-break:break-word; }
.notes { margin-top:6px; font-size:12.5px; }
.badge { display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; font-weight:600; color:#fff; }
.badge.error { background:var(--error); } .badge.warning { background:var(--warning); } .badge.information { background:var(--info); }
.sources a { color:var(--info); font-size:12px; }
.empty { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:32px; text-align:center; font-size:16px; }
footer { margin-top:16px; }
</style>
</head>
<body>
<main>
<h1>$(ConvertTo-HtmlEncoded $Title)</h1>
<div class="muted">Generated $generated by M365DeprecationScanner</div>
<div class="cards">
  <div class="card"><div class="num">$($summary.Total)</div><div class="muted">Findings</div></div>
  <div class="card"><div class="num">$($summary.Files)</div><div class="muted">Affected files</div></div>
  <div class="card error"><div class="num">$($summary.Error)</div><div class="muted">Retired &ndash; broken today</div></div>
  <div class="card warning"><div class="num">$($summary.Warning)</div><div class="muted">Deprecated &ndash; fix soon</div></div>
  <div class="card info"><div class="num">$($summary.Information)</div><div class="muted">Announced &ndash; plan ahead</div></div>
</div>
$body
<footer class="muted">Rules are based on public Microsoft announcements. Always check the linked source before changing production scripts.</footer>
</main>
<script>$filterScript</script>
</body>
</html>
"@
}

function ConvertTo-MarkdownEscaped {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    # Backslash-escape every Markdown punctuation character so scanned content cannot create links,
    # images, emphasis or HTML in a job summary. '<' and '>' become entities.
    $singleLine = $Text -replace '[\r\n\u0085\u2028\u2029]+', ' '
    $escaped = [regex]::Replace($singleLine, '[\\`*_{}\[\]()#+\-.!|~&]', '\$0')
    return ($escaped -replace '<', '&lt;' -replace '>', '&gt;')
}

function ConvertTo-MarkdownCode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    # Code spans cannot contain backticks safely, and pipes would split the table; fall back to escaped text.
    if ($Text -match '[`|\r\n\u0085\u2028\u2029]') { return ConvertTo-MarkdownEscaped $Text }
    return '`' + $Text + '`'
}

function ConvertTo-MarkdownReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [string]$Title,

        [int]$MaxRows = 500
    )

    $summary = Get-ReportSummary -Rows $Rows
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine("## $(ConvertTo-MarkdownEscaped $Title)")
    [void]$builder.AppendLine()

    if ($Rows.Count -eq 0) {
        [void]$builder.AppendLine(':white_check_mark: No deprecated commands found.')
        return $builder.ToString()
    }

    [void]$builder.AppendLine(('**{0} finding(s)** in **{1} file(s)**: :red_circle: {2} retired &middot; :orange_circle: {3} deprecated &middot; :large_blue_circle: {4} announced' -f $summary.Total, $summary.Files, $summary.Error, $summary.Warning, $summary.Information))
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| | File | Line | Found | Use instead | Rule |')
    [void]$builder.AppendLine('|---|---|---:|---|---|---|')

    $icons = @{ Error = ':red_circle:'; Warning = ':orange_circle:'; Information = ':large_blue_circle:' }
    $sortedRows = @($Rows | Sort-Object -Property @{ Expression = { @{ Error = 0; Warning = 1; Information = 2 }[$_.Severity] } }, File, Line)
    foreach ($row in ($sortedRows | Select-Object -First $MaxRows)) {
        $rule = ConvertTo-MarkdownEscaped $row.RuleId
        $firstSource = @($row.Sources | Where-Object { $_ -match '^https://' }) | Select-Object -First 1
        if ($firstSource) {
            $rule = '[{0}]({1})' -f $rule, ($firstSource -replace '\)', '%29' -replace ' ', '%20')
        }
        [void]$builder.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $icons[$row.Severity], (ConvertTo-MarkdownCode $row.File), $row.Line, (ConvertTo-MarkdownCode $row.Match), (ConvertTo-MarkdownCode $row.Replacement), $rule))
    }
    if ($sortedRows.Count -gt $MaxRows) {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine(('_Showing the first {0} of {1} findings. Use the HTML, CSV or SARIF report for the full list._' -f $MaxRows, $sortedRows.Count))
    }
    return $builder.ToString()
}

function ConvertTo-SarifReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $levels = @{ Error = 'error'; Warning = 'warning'; Information = 'note' }
    $version = '0.0.0'
    if ($ExecutionContext.SessionState.Module) {
        $version = $ExecutionContext.SessionState.Module.Version.ToString()
    }

    $ruleIndex = @{}
    $sarifRules = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        if ($ruleIndex.ContainsKey($row.RuleId)) {
            continue
        }
        $ruleIndex[$row.RuleId] = $sarifRules.Count
        $helpText = 'Use {0} instead.' -f $row.Replacement
        if ($row.Notes) { $helpText += ' ' + $row.Notes }
        $rule = [ordered]@{
            id                   = $row.RuleId
            name                 = $row.RuleId
            shortDescription     = @{ text = $row.Title }
            fullDescription      = @{ text = $row.Message }
            help                 = @{ text = $helpText }
            defaultConfiguration = @{ level = $levels[$row.Severity] }
            properties           = @{ tags = @('deprecation', $row.Area, $row.Status) }
        }
        $firstSource = @($row.Sources | Where-Object { $_ -match '^https://' }) | Select-Object -First 1
        if ($firstSource) {
            $rule.helpUri = $firstSource
        }
        $sarifRules.Add($rule)
    }

    $results = foreach ($row in $Rows) {
        $location = [ordered]@{
            physicalLocation = [ordered]@{
                artifactLocation = [ordered]@{ uri = $row.File }
                region           = [ordered]@{
                    startLine   = [Math]::Max(1, $row.Line)
                    startColumn = [Math]::Max(1, $row.Column)
                    endLine     = [Math]::Max(1, $row.EndLine)
                    endColumn   = [Math]::Max(1, $row.EndColumn)
                }
            }
        }
        if ($row.File -eq '<script>') {
            $location.physicalLocation.artifactLocation.uri = 'script.ps1'
        }
        elseif ([System.IO.Path]::IsPathRooted($row.File)) {
            $location.physicalLocation.artifactLocation.uri = ([uri]$row.File).AbsoluteUri
        }
        else {
            $location.physicalLocation.artifactLocation.uri = (($row.File -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
            $location.physicalLocation.artifactLocation.uriBaseId = '%SRCROOT%'
        }
        [ordered]@{
            ruleId    = $row.RuleId
            ruleIndex = $ruleIndex[$row.RuleId]
            level     = $levels[$row.Severity]
            message   = @{ text = $row.Message }
            locations = @($location)
        }
    }

    $sarif = [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            [ordered]@{
                tool    = @{
                    driver = [ordered]@{
                        name           = 'M365DeprecationScanner'
                        informationUri = 'https://github.com/matejpaunovski/M365DeprecationScanner'
                        version        = $version
                        rules          = $sarifRules.ToArray()
                    }
                }
                results = [object[]]@($results)
            }
        )
    }
    return ConvertTo-Json -InputObject $sarif -Depth 20
}
