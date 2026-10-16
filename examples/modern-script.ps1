<#
    EXAMPLE ONLY.

    The same tasks as legacy-script.ps1, written with current modules. Scanning this file returns
    no findings:

        Invoke-M365DeprecationScan -Path .\examples\modern-script.ps1
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, ExchangeOnlineManagement, Az.Resources

# --- Connect --------------------------------------------------------------------------------
Connect-MgGraph -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All', 'Organization.Read.All' -NoWelcome
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com -ShowBanner:$false

# --- Users and licenses ----------------------------------------------------------------------
$users = Get-MgUser -All -Property Id, UserPrincipalName, AssignedLicenses -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount
foreach ($user in $users) {
    Update-MgUser -UserId $user.Id -UsageLocation 'DE'
}
$sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -EQ 'ENTERPRISEPACK'
Set-MgUserLicense -UserId 'new.hire@contoso.com' -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @()

# --- Groups ------------------------------------------------------------------------------------
$group = Get-MgGroup -Filter "displayName eq 'Sales'"
Get-MgGroupMember -GroupId $group.Id -All
New-MgGroupMember -GroupId $group.Id -DirectoryObjectId (Get-MgUser -UserId 'new.hire@contoso.com').Id

# --- Exchange ----------------------------------------------------------------------------------
Get-MessageTraceV2 -SenderAddress 'ceo@contoso.com' -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date)
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -RecordType ExchangeAdmin

# --- Azure -------------------------------------------------------------------------------------
Connect-AzAccount
Get-AzResourceGroup | Select-Object ResourceGroupName, Location

# --- Direct REST call to Microsoft Graph --------------------------------------------------------
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/users?$top=10'
