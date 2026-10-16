#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot

foreach ($folder in 'Private', 'Public') {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}

$publicFunctions = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File |
    ForEach-Object { $_.BaseName }
Export-ModuleMember -Function $publicFunctions
