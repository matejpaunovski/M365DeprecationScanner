<#
    EXAMPLE ONLY - DO NOT RUN.

    A typical "old" admin script, the kind that still lives on many file shares and scheduled tasks.
    Almost every line uses something Microsoft has retired or deprecated. Scan it with:

        Invoke-M365DeprecationScan -Path .\examples\legacy-script.ps1
#>
#Requires -Modules MSOnline

Import-Module AzureAD
Import-Module ExchangeOnlineManagement

# --- Connect --------------------------------------------------------------------------------
Connect-MsolService
Connect-AzureAD
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com -UseRPSSession

# --- Users and licenses ----------------------------------------------------------------------
$users = Get-MsolUser -All | Where-Object { $_.IsLicensed }
foreach ($user in $users) {
    Set-MsolUser -UserPrincipalName $user.UserPrincipalName -UsageLocation 'DE'
}
Set-MsolUserLicense -UserPrincipalName 'new.hire@contoso.com' -AddLicenses 'contoso:ENTERPRISEPACK'

# --- Groups ------------------------------------------------------------------------------------
$group = Get-AzureADGroup -SearchString 'Sales'
Get-AzureADGroupMember -ObjectId $group.ObjectId -All $true
Add-AzureADGroupMember -ObjectId $group.ObjectId -RefObjectId (Get-AzureADUser -ObjectId 'new.hire@contoso.com').ObjectId

# --- Exchange ----------------------------------------------------------------------------------
Get-MessageTrace -SenderAddress 'ceo@contoso.com' -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date)
Search-AdminAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date)

# --- Azure -------------------------------------------------------------------------------------
Login-AzureRmAccount
Get-AzureRmResourceGroup | Select-Object ResourceGroupName, Location

# --- Direct REST call to the old Azure AD Graph -------------------------------------------------
$token = 'eyJ...'
Invoke-RestMethod -Uri 'https://graph.windows.net/contoso.onmicrosoft.com/users?api-version=1.6' -Headers @{ Authorization = "Bearer $token" }
