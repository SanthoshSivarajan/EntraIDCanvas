<#
================================================================================
  EntraIDCanvas -- Paint the Full Picture of Your Entra ID Tenant
  Version: 1.0
  Author : Santhosh Sivarajan, Microsoft MVP
  Purpose: Generates a comprehensive HTML report of a Microsoft Entra ID
           (Azure AD) tenant including users, groups, apps, conditional access,
           roles, devices, licenses, domains, security settings, and more.
  License: MIT -- Free to use, modify, and distribute.
  GitHub : https://github.com/SanthoshSivarajan/EntraIDCanvas
================================================================================
#>

#Requires -Modules Microsoft.Graph.Authentication

param(
    [string]$OutputPath = $PSScriptRoot
)

$ReportDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
$OutputFile = Join-Path $OutputPath "EntraIDCanvas_$ReportDate.html"

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |                                                            |" -ForegroundColor Cyan
Write-Host "  |   EntraIDCanvas -- Entra ID Documentation Tool v1.0        |" -ForegroundColor Cyan
Write-Host "  |                                                            |" -ForegroundColor Cyan
Write-Host "  |   Author : Santhosh Sivarajan, Microsoft MVP              |" -ForegroundColor Cyan
Write-Host "  |   Web    : github.com/SanthoshSivarajan/EntraIDCanvas     |" -ForegroundColor Cyan
Write-Host "  |                                                            |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

# --- Connect to Microsoft Graph -----------------------------------------------
$RequiredScopes = @(
    'Directory.Read.All','User.Read.All','Group.Read.All','Application.Read.All',
    'Policy.Read.All','RoleManagement.Read.Directory','Device.Read.All',
    'Organization.Read.All','AuditLog.Read.All','IdentityProvider.Read.All',
    'Domain.Read.All','CrossTenantInformation.ReadBasic.All',
    'Policy.Read.ConditionalAccess','UserAuthenticationMethod.Read.All'
)

$graphContext = Get-MgContext -ErrorAction SilentlyContinue
if (-not $graphContext) {
    Write-Host "  [*] Connecting to Microsoft Graph ..." -ForegroundColor Yellow
    try {
        Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -ErrorAction Stop
        $graphContext = Get-MgContext
    } catch {
        Write-Host "  [!] Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "      Install module: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [*] Using existing Microsoft Graph session." -ForegroundColor Yellow
}

Write-Host "  [*] Tenant ID   : $($graphContext.TenantId)" -ForegroundColor White
Write-Host "  [*] Account     : $($graphContext.Account)" -ForegroundColor White
Write-Host "  [*] Timestamp   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""
Write-Host "  Collecting Entra ID data ..." -ForegroundColor Yellow
Write-Host ""

# --- Helpers ------------------------------------------------------------------
Add-Type -AssemblyName System.Web
function HtmlEncode($s) { if ($null -eq $s) { return "--" }; return [System.Web.HttpUtility]::HtmlEncode([string]$s) }
function ConvertTo-HtmlTable {
    param([Parameter(Mandatory)]$Data,[string[]]$Properties)
    if (-not $Data -or @($Data).Count -eq 0) { return '<p class="empty-note">No data found.</p>' }
    $rows = @($Data)
    if (-not $Properties) { $Properties = ($rows[0].PSObject.Properties).Name }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<div class="table-wrap"><table><thead><tr>')
    foreach ($p in $Properties) { [void]$sb.Append("<th>$(HtmlEncode $p)</th>") }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($row in $rows) {
        [void]$sb.Append('<tr>')
        foreach ($p in $Properties) {
            $val = $row.$p
            if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) { $val = ($val | ForEach-Object { [string]$_ }) -join ", " }
            [void]$sb.Append("<td>$(HtmlEncode $val)</td>")
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table></div>')
    return $sb.ToString()
}
function Safe-GraphCall {
    param([scriptblock]$Call, [string]$Label)
    try {
        $result = & $Call
        if ($Label) { Write-Host "  [+] $Label" -ForegroundColor Green }
        return $result
    } catch {
        if ($Label) { Write-Host "  [i] Could not collect: $Label -- $($_.Exception.Message)" -ForegroundColor Gray }
        return $null
    }
}

# ==============================================================================
# DATA COLLECTION
# ==============================================================================

# --- Tenant / Organization ----------------------------------------------------
$Org = Safe-GraphCall { Get-MgOrganization -ErrorAction Stop } "Tenant organization info collected."
$TenantName    = $Org.DisplayName
$TenantId      = $Org.Id
$TenantCreated = $Org.CreatedDateTime
$VerifiedDomains = $Org.VerifiedDomains
$TechContacts  = $Org.TechnicalNotificationMails -join ', '
$ProvisioningState = $Org.OnPremisesSyncEnabled

# --- Domains ------------------------------------------------------------------
$Domains = Safe-GraphCall {
    Get-MgDomain -All -ErrorAction Stop | Select-Object Id, AuthenticationType, IsDefault, IsInitial, IsVerified, SupportedServices
} "Domains collected."

# --- SKUs / Licenses ----------------------------------------------------------
$Licenses = Safe-GraphCall {
    Get-MgSubscribedSku -All -ErrorAction Stop | Select-Object SkuPartNumber, @{N='Total';E={$_.PrepaidUnits.Enabled}}, ConsumedUnits, @{N='Available';E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}, CapabilityStatus
} "License / SKU data collected."

# --- Users --------------------------------------------------------------------
$AllUsers = Safe-GraphCall {
    Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AccountEnabled,UserType,CreatedDateTime,SignInActivity,AssignedLicenses,OnPremisesSyncEnabled,Mail -ErrorAction Stop
} "User data collected."
$TotalUsers    = @($AllUsers).Count
$EnabledUsers  = @($AllUsers | Where-Object { $_.AccountEnabled -eq $true }).Count
$DisabledUsers = @($AllUsers | Where-Object { $_.AccountEnabled -eq $false }).Count
$MemberUsers   = @($AllUsers | Where-Object { $_.UserType -eq 'Member' }).Count
$GuestUsers    = @($AllUsers | Where-Object { $_.UserType -eq 'Guest' }).Count
$SyncedUsers   = @($AllUsers | Where-Object { $_.OnPremisesSyncEnabled -eq $true }).Count
$CloudOnlyUsers = $TotalUsers - $SyncedUsers
$LicensedUsers = @($AllUsers | Where-Object { $_.AssignedLicenses -and @($_.AssignedLicenses).Count -gt 0 }).Count
$UnlicensedUsers = $TotalUsers - $LicensedUsers

# Inactive users (no sign-in in 90 days)
$InactiveUsers = 0
$NeverSignedIn = 0
try {
    $cutoff = (Get-Date).AddDays(-90)
    foreach ($u in $AllUsers) {
        if ($u.SignInActivity -and $u.SignInActivity.LastSignInDateTime) {
            if ([datetime]$u.SignInActivity.LastSignInDateTime -lt $cutoff) { $InactiveUsers++ }
        } elseif ($u.AccountEnabled -eq $true) {
            $NeverSignedIn++
        }
    }
} catch { }

# --- Groups -------------------------------------------------------------------
$AllGroups = Safe-GraphCall {
    Get-MgGroup -All -Property Id,DisplayName,GroupTypes,SecurityEnabled,MailEnabled,MembershipRule,OnPremisesSyncEnabled,CreatedDateTime -ErrorAction Stop
} "Group data collected."
$TotalGroups     = @($AllGroups).Count
$SecurityGroups  = @($AllGroups | Where-Object { $_.SecurityEnabled -eq $true -and -not ($_.GroupTypes -contains 'Unified') }).Count
$M365Groups      = @($AllGroups | Where-Object { $_.GroupTypes -contains 'Unified' }).Count
$DistGroups      = @($AllGroups | Where-Object { $_.MailEnabled -eq $true -and $_.SecurityEnabled -eq $false }).Count
$DynamicGroups   = @($AllGroups | Where-Object { $_.GroupTypes -contains 'DynamicMembership' }).Count
$AssignedGroups  = $TotalGroups - $DynamicGroups
$SyncedGroups    = @($AllGroups | Where-Object { $_.OnPremisesSyncEnabled -eq $true }).Count
$CloudGroups     = $TotalGroups - $SyncedGroups

# --- Applications (App Registrations) -----------------------------------------
$AppRegistrations = Safe-GraphCall {
    Get-MgApplication -All -Property Id,DisplayName,AppId,CreatedDateTime,SignInAudience,PublisherDomain,PasswordCredentials,KeyCredentials -ErrorAction Stop
} "App registrations collected."
$TotalApps = @($AppRegistrations).Count

# Apps with expiring/expired secrets
$AppsWithExpSecrets = @()
$now = Get-Date
foreach ($app in $AppRegistrations) {
    foreach ($cred in $app.PasswordCredentials) {
        if ($cred.EndDateTime -and [datetime]$cred.EndDateTime -lt $now.AddDays(30)) {
            $AppsWithExpSecrets += [PSCustomObject]@{
                AppName=$app.DisplayName; AppId=$app.AppId; CredType='Secret';
                Expiry=[datetime]$cred.EndDateTime; Status=if([datetime]$cred.EndDateTime -lt $now){'EXPIRED'}else{'Expiring Soon'}
            }
        }
    }
    foreach ($cred in $app.KeyCredentials) {
        if ($cred.EndDateTime -and [datetime]$cred.EndDateTime -lt $now.AddDays(30)) {
            $AppsWithExpSecrets += [PSCustomObject]@{
                AppName=$app.DisplayName; AppId=$app.AppId; CredType='Certificate';
                Expiry=[datetime]$cred.EndDateTime; Status=if([datetime]$cred.EndDateTime -lt $now){'EXPIRED'}else{'Expiring Soon'}
            }
        }
    }
}

# --- Service Principals (Enterprise Apps) -------------------------------------
$ServicePrincipals = Safe-GraphCall {
    Get-MgServicePrincipal -All -Property Id,DisplayName,AppId,ServicePrincipalType,AccountEnabled,CreatedDateTime,AppOwnerOrganizationId,PublisherName -ErrorAction Stop
} "Service principals (Enterprise Apps) collected."
$TotalSPs     = @($ServicePrincipals).Count
$ManagedIdSPs = @($ServicePrincipals | Where-Object { $_.ServicePrincipalType -eq 'ManagedIdentity' }).Count

# Microsoft's tenant ID for first-party apps
$MicrosoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

# Categorize service principals
$MSFirstPartySPs  = @($ServicePrincipals | Where-Object {
    $_.AppOwnerOrganizationId -eq $MicrosoftTenantId -and $_.ServicePrincipalType -ne 'ManagedIdentity'
}).Count
$ThirdPartySPs = @($ServicePrincipals | Where-Object {
    $_.AppOwnerOrganizationId -and
    $_.AppOwnerOrganizationId -ne $MicrosoftTenantId -and
    $_.AppOwnerOrganizationId -ne $TenantId -and
    $_.ServicePrincipalType -ne 'ManagedIdentity'
}).Count
$CustomSPs = @($ServicePrincipals | Where-Object {
    ($_.AppOwnerOrganizationId -eq $TenantId -or -not $_.AppOwnerOrganizationId) -and
    $_.ServicePrincipalType -ne 'ManagedIdentity'
}).Count
$DisabledSPs = @($ServicePrincipals | Where-Object { $_.AccountEnabled -eq $false }).Count
$EnabledSPs  = @($ServicePrincipals | Where-Object { $_.AccountEnabled -eq $true }).Count

# Build Enterprise App summary table (non-Microsoft, top 50)
$EntAppSummary = $ServicePrincipals |
    Where-Object { $_.AppOwnerOrganizationId -ne $MicrosoftTenantId } |
    ForEach-Object {
        $category = if ($_.ServicePrincipalType -eq 'ManagedIdentity') { 'Managed Identity' }
                    elseif ($_.AppOwnerOrganizationId -eq $TenantId -or -not $_.AppOwnerOrganizationId) { 'Custom (Your Tenant)' }
                    else { 'Third-Party' }
        [PSCustomObject]@{
            DisplayName = $_.DisplayName
            AppId       = $_.AppId
            Category    = $category
            Type        = $_.ServicePrincipalType
            Enabled     = $_.AccountEnabled
            Created     = $_.CreatedDateTime
        }
    } | Sort-Object Created -Descending | Select-Object -First 50

# --- Conditional Access Policies ----------------------------------------------
$CAPolicies = @()
$CARawPolicies = @()
try {
    $CARawPolicies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)
    foreach ($ca in $CARawPolicies) {
        $includeUsers = '--'; $includeGroups = '--'; $includeApps = '--'; $grantControls = '--'
        try { if ($ca.Conditions.Users.IncludeUsers) { $includeUsers = ($ca.Conditions.Users.IncludeUsers) -join ', ' } } catch { }
        try { if ($ca.Conditions.Users.IncludeGroups) { $includeGroups = ($ca.Conditions.Users.IncludeGroups) -join ', ' } } catch { }
        try { if ($ca.Conditions.Applications.IncludeApplications) { $includeApps = ($ca.Conditions.Applications.IncludeApplications) -join ', ' } } catch { }
        try { if ($ca.GrantControls.BuiltInControls) { $grantControls = ($ca.GrantControls.BuiltInControls) -join ', ' } } catch { }
        $CAPolicies += [PSCustomObject]@{
            DisplayName   = $ca.DisplayName
            State         = $ca.State
            IncludeUsers  = $includeUsers
            IncludeApps   = $includeApps
            GrantControls = $grantControls
            Created       = $ca.CreatedDateTime
        }
    }
    Write-Host "  [+] Conditional Access policies collected ($(@($CAPolicies).Count))." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect Conditional Access policies: $($_.Exception.Message)" -ForegroundColor Gray
    # Fallback: try Graph API directly
    try {
        $caResult = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -ErrorAction Stop
        if ($caResult.value) {
            foreach ($ca in $caResult.value) {
                $CAPolicies += [PSCustomObject]@{
                    DisplayName   = $ca.displayName
                    State         = $ca.state
                    IncludeUsers  = if ($ca.conditions.users.includeUsers) { ($ca.conditions.users.includeUsers) -join ', ' } else { '--' }
                    IncludeApps   = if ($ca.conditions.applications.includeApplications) { ($ca.conditions.applications.includeApplications) -join ', ' } else { '--' }
                    GrantControls = if ($ca.grantControls.builtInControls) { ($ca.grantControls.builtInControls) -join ', ' } else { '--' }
                    Created       = $ca.createdDateTime
                }
            }
            Write-Host "  [+] Conditional Access policies collected via Graph API fallback ($(@($CAPolicies).Count))." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [i] Fallback also failed: $($_.Exception.Message)" -ForegroundColor Gray
    }
}
$TotalCA     = @($CAPolicies).Count
$EnabledCA   = @($CAPolicies | Where-Object { $_.State -eq 'enabled' }).Count
$DisabledCA  = @($CAPolicies | Where-Object { $_.State -eq 'disabled' }).Count
$ReportOnlyCA = @($CAPolicies | Where-Object { $_.State -eq 'enabledForReportingButNotEnforced' }).Count

# --- Named Locations ----------------------------------------------------------
$NamedLocations = @()
try {
    $rawLocations = @(Get-MgIdentityConditionalAccessNamedLocation -All -ErrorAction Stop)
    foreach ($loc in $rawLocations) {
        $locType = '--'
        try { if ($loc.AdditionalProperties.'@odata.type') { $locType = $loc.AdditionalProperties.'@odata.type' -replace '#microsoft.graph.','' } } catch { }
        $NamedLocations += [PSCustomObject]@{
            DisplayName = $loc.DisplayName
            Type        = $locType
            Created     = $loc.CreatedDateTime
        }
    }
    Write-Host "  [+] Named locations collected ($(@($NamedLocations).Count))." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect named locations." -ForegroundColor Gray
}

# --- Directory Roles ----------------------------------------------------------
$DirectoryRoles = @()
try {
    $roles = Get-MgDirectoryRole -All -ErrorAction Stop
    foreach ($role in $roles) {
        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -ErrorAction SilentlyContinue
        $DirectoryRoles += [PSCustomObject]@{
            RoleName    = $role.DisplayName
            Description = $role.Description
            MemberCount = @($members).Count
            Members     = ($members | ForEach-Object { $_.AdditionalProperties.displayName }) -join ', '
        }
    }
    Write-Host "  [+] Directory roles collected ($(@($DirectoryRoles).Count) active roles)." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect directory roles." -ForegroundColor Gray
}

# Global Admins
$GlobalAdmins = $DirectoryRoles | Where-Object { $_.RoleName -eq 'Global Administrator' }
$GlobalAdminCount = if ($GlobalAdmins) { $GlobalAdmins.MemberCount } else { 0 }

# --- Devices ------------------------------------------------------------------
$Devices = Safe-GraphCall {
    Get-MgDevice -All -Property Id,DisplayName,OperatingSystem,OperatingSystemVersion,TrustType,IsCompliant,IsManaged,AccountEnabled,ApproximateLastSignInDateTime,CreatedDateTime -ErrorAction Stop
} "Device data collected."
$TotalDevices     = @($Devices).Count
$EntraJoined      = @($Devices | Where-Object { $_.TrustType -eq 'AzureAd' }).Count
$HybridJoined     = @($Devices | Where-Object { $_.TrustType -eq 'ServerAd' }).Count
$EntraRegistered  = @($Devices | Where-Object { $_.TrustType -eq 'Workplace' }).Count
$CompliantDevices = @($Devices | Where-Object { $_.IsCompliant -eq $true }).Count
$ManagedDevices   = @($Devices | Where-Object { $_.IsManaged -eq $true }).Count

# Device OS distribution
$DeviceOSDist = @{}
$Devices | Where-Object { $_.OperatingSystem } | ForEach-Object {
    $os = $_.OperatingSystem
    if ($DeviceOSDist.ContainsKey($os)) { $DeviceOSDist[$os]++ } else { $DeviceOSDist[$os] = 1 }
}

# --- Administrative Units -----------------------------------------------------
$AdminUnits = @()
try {
    $AdminUnits = Get-MgDirectoryAdministrativeUnit -All -Property Id,DisplayName,Description,MembershipType -ErrorAction Stop |
        Select-Object DisplayName, Description, MembershipType
    Write-Host "  [+] Administrative units collected ($(@($AdminUnits).Count))." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect administrative units." -ForegroundColor Gray
}

# --- Security Defaults --------------------------------------------------------
$SecurityDefaults = $null
try {
    $SecurityDefaults = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy -ErrorAction Stop
    Write-Host "  [+] Security defaults status collected." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect security defaults." -ForegroundColor Gray
}

# --- Authorization Policy -----------------------------------------------------
$AuthPolicy = $null
try {
    $AuthPolicy = Get-MgPolicyAuthorizationPolicy -ErrorAction Stop
    Write-Host "  [+] Authorization policy collected." -ForegroundColor Green
} catch { }

# --- Cross-Tenant Access Settings ---------------------------------------------
$CrossTenantPolicy = $null
try {
    $CrossTenantPolicy = Get-MgPolicyCrossTenantAccessPolicyDefault -ErrorAction Stop
    Write-Host "  [+] Cross-tenant access policy collected." -ForegroundColor Green
} catch {
    Write-Host "  [i] Could not collect cross-tenant access settings." -ForegroundColor Gray
}

# --- Hybrid Config (on-prem sync) ---------------------------------------------
$OnPremSyncEnabled = if ($Org.OnPremisesSyncEnabled) { "Yes" } else { "No" }
$DirSyncStatus     = if ($Org.OnPremisesLastSyncDateTime) { "Last sync: $($Org.OnPremisesLastSyncDateTime)" } else { "Never synced" }

Write-Host ""
Write-Host "  [+] Data collection complete." -ForegroundColor Green

# ==============================================================================
# BUILD TABLES
# ==============================================================================
$DomainTable    = if ($Domains)          { ConvertTo-HtmlTable -Data $Domains -Properties Id, AuthenticationType, IsDefault, IsInitial, IsVerified, SupportedServices } else { '<p class="empty-note">No domains.</p>' }
$LicenseTable   = if ($Licenses)         { ConvertTo-HtmlTable -Data $Licenses -Properties SkuPartNumber, Total, ConsumedUnits, Available, CapabilityStatus } else { '<p class="empty-note">No license data.</p>' }
$CATable        = if ($CAPolicies.Count -gt 0) { ConvertTo-HtmlTable -Data $CAPolicies -Properties DisplayName, State, IncludeUsers, IncludeApps, GrantControls, Created } else { '<p class="empty-note">No Conditional Access policies.</p>' }
$NamedLocTable  = if ($NamedLocations.Count -gt 0) { ConvertTo-HtmlTable -Data $NamedLocations -Properties DisplayName, Type, Created } else { '<p class="empty-note">No named locations.</p>' }
$RoleTable      = if ($DirectoryRoles.Count -gt 0) { ConvertTo-HtmlTable -Data ($DirectoryRoles | Sort-Object MemberCount -Descending) -Properties RoleName, MemberCount, Members } else { '<p class="empty-note">No directory roles.</p>' }
$AdminUnitTable = if ($AdminUnits.Count -gt 0) { ConvertTo-HtmlTable -Data $AdminUnits -Properties DisplayName, Description, MembershipType } else { '<p class="empty-note">No administrative units.</p>' }
$ExpSecretTable = if ($AppsWithExpSecrets.Count -gt 0) { ConvertTo-HtmlTable -Data $AppsWithExpSecrets -Properties AppName, AppId, CredType, Expiry, Status } else { '<p class="empty-note">No expiring or expired credentials.</p>' }

# Enterprise App (non-Microsoft) table
$EntAppTable = if ($EntAppSummary.Count -gt 0) { ConvertTo-HtmlTable -Data $EntAppSummary -Properties DisplayName, AppId, Category, Type, Enabled, Created } else { '<p class="empty-note">No custom or third-party enterprise apps found.</p>' }

# App Registration summary table (top 50)
$AppSummary = $AppRegistrations | Select-Object DisplayName, AppId, SignInAudience, CreatedDateTime | Sort-Object CreatedDateTime -Descending | Select-Object -First 50
$AppTable = if ($AppSummary.Count -gt 0) { ConvertTo-HtmlTable -Data $AppSummary -Properties DisplayName, AppId, SignInAudience, CreatedDateTime } else { '<p class="empty-note">No app registrations.</p>' }

# Chart data
$UserChartJSON    = '{"Enabled":' + $EnabledUsers + ',"Disabled":' + $DisabledUsers + ',"Members":' + $MemberUsers + ',"Guests":' + $GuestUsers + '}'
$UserSourceJSON   = '{"Cloud-Only":' + $CloudOnlyUsers + ',"Synced (On-Prem)":' + $SyncedUsers + '}'
$UserLicJSON      = '{"Licensed":' + $LicensedUsers + ',"Unlicensed":' + $UnlicensedUsers + '}'
$GroupChartJSON   = '{"Security":' + $SecurityGroups + ',"M365":' + $M365Groups + ',"Distribution":' + $DistGroups + '}'
$GroupTypeJSON    = '{"Dynamic":' + $DynamicGroups + ',"Assigned":' + $AssignedGroups + '}'
$GroupSourceJSON  = '{"Cloud":' + $CloudGroups + ',"Synced":' + $SyncedGroups + '}'
$CAChartJSON      = '{"Enabled":' + $EnabledCA + ',"Disabled":' + $DisabledCA + ',"Report-Only":' + $ReportOnlyCA + '}'
$DeviceChartJSON  = '{"Entra Joined":' + $EntraJoined + ',"Hybrid Joined":' + $HybridJoined + ',"Registered":' + $EntraRegistered + '}'
$DeviceCompJSON   = '{"Compliant":' + $CompliantDevices + ',"Non-Compliant":' + ($TotalDevices - $CompliantDevices) + '}'
$SPChartJSON      = '{"Microsoft First-Party":' + $MSFirstPartySPs + ',"Custom (Your Tenant)":' + $CustomSPs + ',"Third-Party":' + $ThirdPartySPs + ',"Managed Identity":' + $ManagedIdSPs + '}'
$DeviceOSJSON     = '{' + (($DeviceOSDist.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { '"' + $_.Key + '":' + $_.Value }) -join ',') + '}'
if ($DeviceOSJSON -eq '{}') { $DeviceOSJSON = '{"None":0}' }

# Role chart (top 10 by member count)
$RoleChartData = ($DirectoryRoles | Where-Object { $_.MemberCount -gt 0 } | Sort-Object MemberCount -Descending | Select-Object -First 10)
$RoleChartJSON = '{' + (($RoleChartData | ForEach-Object { '"' + ($_.RoleName -replace '"','') + '":' + $_.MemberCount }) -join ',') + '}'
if ($RoleChartJSON -eq '{}') { $RoleChartJSON = '{"None":0}' }

# ==============================================================================
# HTML REPORT
# ==============================================================================
$HTML = @"
<!--
================================================================================
  EntraIDCanvas -- Entra ID Documentation Report
  Generated : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Author    : Santhosh Sivarajan, Microsoft MVP
  GitHub    : https://github.com/SanthoshSivarajan/EntraIDCanvas
================================================================================
-->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<meta name="author" content="Santhosh Sivarajan, Microsoft MVP"/>
<title>EntraIDCanvas -- $TenantName</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0f172a;--surface:#1e293b;--surface2:#273548;--border:#334155;
  --text:#e2e8f0;--text-dim:#94a3b8;--accent:#60a5fa;--accent2:#22d3ee;
  --green:#34d399;--red:#f87171;--amber:#fbbf24;--purple:#a78bfa;
  --pink:#f472b6;--orange:#fb923c;--accent-bg:rgba(96,165,250,.1);
  --radius:8px;--shadow:0 1px 3px rgba(0,0,0,.3);
  --font-body:'Segoe UI',system-ui,-apple-system,sans-serif;
}
html{scroll-behavior:smooth;font-size:15px}
body{font-family:var(--font-body);background:var(--bg);color:var(--text);line-height:1.65;min-height:100vh}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.wrapper{display:flex;min-height:100vh}
.sidebar{position:fixed;top:0;left:0;width:260px;height:100vh;background:var(--surface);border-right:1px solid var(--border);overflow-y:auto;padding:20px 0;z-index:100;box-shadow:2px 0 12px rgba(0,0,0,.3)}
.sidebar::-webkit-scrollbar{width:4px}.sidebar::-webkit-scrollbar-thumb{background:var(--border);border-radius:4px}
.sidebar .logo{padding:0 18px 14px;border-bottom:1px solid var(--border);margin-bottom:8px}
.sidebar .logo h2{font-size:1.05rem;color:var(--accent);font-weight:700}
.sidebar .logo p{font-size:.68rem;color:var(--text-dim);margin-top:2px}
.sidebar nav a{display:block;padding:5px 18px 5px 22px;font-size:.78rem;color:var(--text-dim);border-left:3px solid transparent;transition:all .15s}
.sidebar nav a:hover,.sidebar nav a.active{color:var(--accent);background:rgba(96,165,250,.08);border-left-color:var(--accent);text-decoration:none}
.sidebar nav .nav-group{font-size:.62rem;text-transform:uppercase;letter-spacing:.08em;color:var(--accent2);padding:10px 18px 2px;font-weight:700}
.main{margin-left:260px;flex:1;padding:24px 32px 50px;max-width:1200px}
.section{margin-bottom:36px}
.section-title{font-size:1.25rem;font-weight:700;color:var(--text);margin-bottom:4px;padding-bottom:8px;border-bottom:2px solid var(--border);display:flex;align-items:center;gap:8px}
.section-title .icon{width:24px;height:24px;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:.8rem;flex-shrink:0}
.sub-header{font-size:.92rem;color:var(--text);margin:16px 0 8px;padding-bottom:4px;border-bottom:1px solid var(--border)}
.section-desc{color:var(--text-dim);font-size:.84rem;margin-bottom:14px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-bottom:16px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:14px 16px;box-shadow:var(--shadow)}.card:hover{border-color:var(--accent)}
.card .card-val{font-size:1.5rem;font-weight:800;line-height:1.1}
.card .card-label{font-size:.68rem;color:var(--text-dim);margin-top:2px;text-transform:uppercase;letter-spacing:.05em}
.info-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:8px}
.info-card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:10px 14px;box-shadow:var(--shadow)}
.info-label{display:block;font-size:.68rem;color:var(--text-dim);text-transform:uppercase;letter-spacing:.05em;margin-bottom:2px}
.info-value{font-size:.95rem;font-weight:600;color:var(--text)}
.table-wrap{overflow-x:auto;margin-bottom:8px;border-radius:var(--radius);border:1px solid var(--border);box-shadow:var(--shadow)}
table{width:100%;border-collapse:collapse;font-size:.78rem}
thead{background:var(--accent-bg)}
th{text-align:left;padding:8px 10px;font-weight:600;color:var(--accent);white-space:nowrap;border-bottom:2px solid var(--border)}
td{padding:7px 10px;border-bottom:1px solid var(--border);color:var(--text-dim);max-width:360px;overflow:hidden;text-overflow:ellipsis}
tbody tr:hover{background:rgba(96,165,250,.06)}
tbody tr:nth-child(even){background:var(--surface2)}
.empty-note{color:var(--text-dim);font-style:italic;padding:8px 0}
.exec-summary{background:linear-gradient(135deg,#1e293b 0%,#1e3a5f 100%);border:1px solid #334155;border-radius:var(--radius);padding:22px 26px;margin-bottom:28px;box-shadow:var(--shadow)}
.exec-summary h2{font-size:1.1rem;color:var(--accent);margin-bottom:8px}
.exec-summary p{color:var(--text-dim);font-size:.86rem;line-height:1.7;margin-bottom:6px}
.exec-kv{display:inline-block;background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:2px 8px;margin:2px;font-size:.78rem;color:var(--text)}
.exec-kv strong{color:var(--accent2)}
.footer{margin-top:36px;padding:18px 0;border-top:1px solid var(--border);text-align:center;color:var(--text-dim);font-size:.74rem}
.footer a{color:var(--accent)}
@media print{.sidebar{display:none}.main{margin-left:0}body{background:#fff;color:#222}
  .card,.info-card,.exec-summary{background:#f9f9f9;border-color:#ccc;color:#222}
  .card-val,.info-value,.section-title{color:#222}.card-label,.info-label,.section-desc{color:#555}
  th{color:#333;background:#eee}td{color:#444}}
@media(max-width:900px){.sidebar{display:none}.main{margin-left:0;padding:14px}}
</style>
</head>
<body>
<div class="wrapper">
<aside class="sidebar">
  <div class="logo">
    <h2>EntraIDCanvas</h2>
    <p>Developed by Santhosh Sivarajan</p>
    <p style="margin-top:6px">Tenant: <strong style="color:#e2e8f0">$TenantName</strong></p>
  </div>
  <nav>
    <div class="nav-group">Overview</div>
    <a href="#exec-summary">Executive Summary</a>
    <a href="#tenant-config">Tenant Configuration</a>
    <a href="#domains">Domains</a>
    <a href="#licenses">Licenses</a>
    <div class="nav-group">Identity</div>
    <a href="#users">Users</a>
    <a href="#groups">Groups</a>
    <a href="#devices">Devices</a>
    <a href="#directory-roles">Directory Roles</a>
    <a href="#admin-units">Administrative Units</a>
    <div class="nav-group">Applications</div>
    <a href="#app-registrations">App Registrations</a>
    <a href="#enterprise-apps">Enterprise Apps</a>
    <a href="#expiring-creds">Expiring Credentials</a>
    <div class="nav-group">Security</div>
    <a href="#conditional-access">Conditional Access</a>
    <a href="#named-locations">Named Locations</a>
    <a href="#security-config">Security Configuration</a>
    <div class="nav-group">Visuals</div>
    <a href="#charts">Charts</a>
  </nav>
</aside>
<main class="main">

<!-- EXECUTIVE SUMMARY -->
<div id="exec-summary" class="section">
  <div class="exec-summary">
    <h2>Executive Summary -- $TenantName</h2>
    <p>Point-in-time documentation of the Microsoft Entra ID tenant <strong>$TenantName</strong>, generated on <strong>$(Get-Date -Format "MMMM dd, yyyy 'at' HH:mm")</strong>.</p>
    <p>
      <span class="exec-kv"><strong>Tenant:</strong> $TenantName</span>
      <span class="exec-kv"><strong>Tenant ID:</strong> $TenantId</span>
      <span class="exec-kv"><strong>Users:</strong> $TotalUsers</span>
      <span class="exec-kv"><strong>Guests:</strong> $GuestUsers</span>
      <span class="exec-kv"><strong>Groups:</strong> $TotalGroups</span>
      <span class="exec-kv"><strong>Devices:</strong> $TotalDevices</span>
      <span class="exec-kv"><strong>App Registrations:</strong> $TotalApps</span>
      <span class="exec-kv"><strong>Enterprise Apps:</strong> $TotalSPs</span>
      <span class="exec-kv"><strong>CA Policies:</strong> $TotalCA</span>
      <span class="exec-kv"><strong>Licenses:</strong> $(@($Licenses).Count) SKU(s)</span>
      <span class="exec-kv"><strong>Dir Sync:</strong> $OnPremSyncEnabled</span>
      <span class="exec-kv"><strong>Global Admins:</strong> $GlobalAdminCount</span>
      <span class="exec-kv"><strong>Security Defaults:</strong> $(if($SecurityDefaults -and $SecurityDefaults.IsEnabled){'Enabled'}else{'Disabled'})</span>
    </p>
  </div>
</div>

<!-- TENANT CONFIG -->
<div id="tenant-config" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(96,165,250,.15);color:var(--accent)">&#127760;</span> Tenant Configuration</h2>
  <div class="info-grid">
    <div class="info-card"><span class="info-label">Tenant Name</span><span class="info-value">$TenantName</span></div>
    <div class="info-card"><span class="info-label">Tenant ID</span><span class="info-value">$TenantId</span></div>
    <div class="info-card"><span class="info-label">Created</span><span class="info-value">$TenantCreated</span></div>
    <div class="info-card"><span class="info-label">Directory Sync</span><span class="info-value">$OnPremSyncEnabled</span></div>
    <div class="info-card"><span class="info-label">Last Sync</span><span class="info-value">$DirSyncStatus</span></div>
    <div class="info-card"><span class="info-label">Technical Contacts</span><span class="info-value">$(if($TechContacts){$TechContacts}else{'(none)'})</span></div>
    <div class="info-card"><span class="info-label">Security Defaults</span><span class="info-value">$(if($SecurityDefaults -and $SecurityDefaults.IsEnabled){'Enabled'}else{'Disabled'})</span></div>
    <div class="info-card"><span class="info-label">Guest Access</span><span class="info-value">$(if($AuthPolicy){"$($AuthPolicy.GuestUserRoleId)"}else{'--'})</span></div>
    <div class="info-card"><span class="info-label">User Can Register Apps</span><span class="info-value">$(if($AuthPolicy){$AuthPolicy.DefaultUserRolePermissions.AllowedToCreateApps}else{'--'})</span></div>
  </div>
</div>

<!-- DOMAINS -->
<div id="domains" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(167,139,250,.15);color:var(--purple)">&#127760;</span> Domains</h2>
  $DomainTable
</div>

<!-- LICENSES -->
<div id="licenses" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(52,211,153,.15);color:var(--green)">&#128179;</span> Licenses &amp; SKUs</h2>
  $LicenseTable
</div>

<!-- USERS -->
<div id="users" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(96,165,250,.15);color:var(--accent)">&#128100;</span> Users</h2>
  <div class="cards">
    <div class="card"><div class="card-val" style="color:var(--accent)">$TotalUsers</div><div class="card-label">Total</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$EnabledUsers</div><div class="card-label">Enabled</div></div>
    <div class="card"><div class="card-val" style="color:var(--red)">$DisabledUsers</div><div class="card-label">Disabled</div></div>
    <div class="card"><div class="card-val" style="color:var(--accent2)">$MemberUsers</div><div class="card-label">Members</div></div>
    <div class="card"><div class="card-val" style="color:var(--purple)">$GuestUsers</div><div class="card-label">Guests</div></div>
    <div class="card"><div class="card-val" style="color:var(--amber)">$SyncedUsers</div><div class="card-label">Synced</div></div>
    <div class="card"><div class="card-val" style="color:var(--pink)">$CloudOnlyUsers</div><div class="card-label">Cloud-Only</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$LicensedUsers</div><div class="card-label">Licensed</div></div>
    <div class="card"><div class="card-val" style="color:var(--orange)">$UnlicensedUsers</div><div class="card-label">Unlicensed</div></div>
    <div class="card"><div class="card-val" style="color:var(--text-dim)">$InactiveUsers</div><div class="card-label">Inactive 90d+</div></div>
    <div class="card"><div class="card-val" style="color:var(--text-dim)">$NeverSignedIn</div><div class="card-label">Never Signed In</div></div>
  </div>
</div>

<!-- GROUPS -->
<div id="groups" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(251,146,60,.15);color:var(--orange)">&#128101;</span> Groups</h2>
  <div class="cards">
    <div class="card"><div class="card-val" style="color:var(--accent)">$TotalGroups</div><div class="card-label">Total</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$SecurityGroups</div><div class="card-label">Security</div></div>
    <div class="card"><div class="card-val" style="color:var(--accent2)">$M365Groups</div><div class="card-label">Microsoft 365</div></div>
    <div class="card"><div class="card-val" style="color:var(--purple)">$DistGroups</div><div class="card-label">Distribution</div></div>
    <div class="card"><div class="card-val" style="color:var(--amber)">$DynamicGroups</div><div class="card-label">Dynamic</div></div>
    <div class="card"><div class="card-val" style="color:var(--pink)">$AssignedGroups</div><div class="card-label">Assigned</div></div>
    <div class="card"><div class="card-val" style="color:var(--orange)">$SyncedGroups</div><div class="card-label">Synced</div></div>
    <div class="card"><div class="card-val" style="color:var(--text-dim)">$CloudGroups</div><div class="card-label">Cloud-Only</div></div>
  </div>
</div>

<!-- DEVICES -->
<div id="devices" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(52,211,153,.15);color:var(--green)">&#128187;</span> Devices</h2>
  <div class="cards">
    <div class="card"><div class="card-val" style="color:var(--accent)">$TotalDevices</div><div class="card-label">Total</div></div>
    <div class="card"><div class="card-val" style="color:var(--accent2)">$EntraJoined</div><div class="card-label">Entra Joined</div></div>
    <div class="card"><div class="card-val" style="color:var(--purple)">$HybridJoined</div><div class="card-label">Hybrid Joined</div></div>
    <div class="card"><div class="card-val" style="color:var(--amber)">$EntraRegistered</div><div class="card-label">Registered</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$CompliantDevices</div><div class="card-label">Compliant</div></div>
    <div class="card"><div class="card-val" style="color:var(--orange)">$ManagedDevices</div><div class="card-label">Managed</div></div>
  </div>
</div>

<!-- DIRECTORY ROLES -->
<div id="directory-roles" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(248,113,113,.15);color:var(--red)">&#128737;</span> Directory Roles</h2>
  <p class="section-desc">Active Entra ID directory roles with assigned members.</p>
  $RoleTable
</div>

<!-- ADMIN UNITS -->
<div id="admin-units" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(167,139,250,.15);color:var(--purple)">&#128193;</span> Administrative Units</h2>
  $AdminUnitTable
</div>

<!-- APP REGISTRATIONS -->
<div id="app-registrations" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(96,165,250,.15);color:var(--accent)">&#128736;</span> App Registrations ($TotalApps)</h2>
  <p class="section-desc">Showing most recent 50 registrations.</p>
  $AppTable
</div>

<!-- ENTERPRISE APPS -->
<div id="enterprise-apps" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(34,211,238,.15);color:var(--accent2)">&#9881;</span> Enterprise Applications</h2>
  <p class="section-desc">Service principals categorized by ownership. Microsoft first-party apps are auto-provisioned by Microsoft in every tenant.</p>
  <div class="cards">
    <div class="card"><div class="card-val" style="color:var(--accent)">$TotalSPs</div><div class="card-label">Total Service Principals</div></div>
    <div class="card"><div class="card-val" style="color:var(--text-dim)">$MSFirstPartySPs</div><div class="card-label">Microsoft First-Party</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$CustomSPs</div><div class="card-label">Custom (Your Tenant)</div></div>
    <div class="card"><div class="card-val" style="color:var(--amber)">$ThirdPartySPs</div><div class="card-label">Third-Party</div></div>
    <div class="card"><div class="card-val" style="color:var(--purple)">$ManagedIdSPs</div><div class="card-label">Managed Identities</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$EnabledSPs</div><div class="card-label">Enabled</div></div>
    <div class="card"><div class="card-val" style="color:var(--red)">$DisabledSPs</div><div class="card-label">Disabled</div></div>
  </div>
  <h3 class="sub-header">Custom &amp; Third-Party Apps (excluding Microsoft first-party)</h3>
  $EntAppTable
</div>

<!-- EXPIRING CREDENTIALS -->
<div id="expiring-creds" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(248,113,113,.15);color:var(--red)">&#9888;</span> Expiring / Expired Credentials</h2>
  <p class="section-desc">App registration secrets and certificates expiring within 30 days or already expired.</p>
  $ExpSecretTable
</div>

<!-- CONDITIONAL ACCESS -->
<div id="conditional-access" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(251,191,36,.15);color:var(--amber)">&#128274;</span> Conditional Access Policies</h2>
  <div class="cards">
    <div class="card"><div class="card-val" style="color:var(--accent)">$TotalCA</div><div class="card-label">Total Policies</div></div>
    <div class="card"><div class="card-val" style="color:var(--green)">$EnabledCA</div><div class="card-label">Enabled</div></div>
    <div class="card"><div class="card-val" style="color:var(--red)">$DisabledCA</div><div class="card-label">Disabled</div></div>
    <div class="card"><div class="card-val" style="color:var(--amber)">$ReportOnlyCA</div><div class="card-label">Report-Only</div></div>
  </div>
  $CATable
</div>

<!-- NAMED LOCATIONS -->
<div id="named-locations" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(34,211,238,.15);color:var(--accent2)">&#127760;</span> Named Locations</h2>
  $NamedLocTable
</div>

<!-- SECURITY CONFIG -->
<div id="security-config" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(52,211,153,.15);color:var(--green)">&#9889;</span> Security Configuration</h2>
  <div class="info-grid">
    <div class="info-card"><span class="info-label">Security Defaults</span><span class="info-value">$(if($SecurityDefaults -and $SecurityDefaults.IsEnabled){'Enabled'}else{'Disabled'})</span></div>
    <div class="info-card"><span class="info-label">Directory Sync (Hybrid)</span><span class="info-value">$OnPremSyncEnabled ($DirSyncStatus)</span></div>
    <div class="info-card"><span class="info-label">Global Admins</span><span class="info-value">$GlobalAdminCount</span></div>
    <div class="info-card"><span class="info-label">Conditional Access Policies</span><span class="info-value">$TotalCA (Enabled: $EnabledCA)</span></div>
    <div class="info-card"><span class="info-label">Expiring/Expired App Creds</span><span class="info-value">$($AppsWithExpSecrets.Count)</span></div>
    <div class="info-card"><span class="info-label">Guest Users</span><span class="info-value">$GuestUsers</span></div>
    <div class="info-card"><span class="info-label">Users Can Register Apps</span><span class="info-value">$(if($AuthPolicy){$AuthPolicy.DefaultUserRolePermissions.AllowedToCreateApps}else{'--'})</span></div>
    <div class="info-card"><span class="info-label">Compliant Devices</span><span class="info-value">$CompliantDevices / $TotalDevices</span></div>
  </div>
</div>

<!-- CHARTS -->
<div id="charts" class="section">
  <h2 class="section-title"><span class="icon" style="background:rgba(96,165,250,.15);color:var(--accent)">&#128202;</span> Charts</h2>
  <div id="chartsContainer" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:14px"></div>
</div>

<!-- FOOTER -->
<div class="footer">
  EntraIDCanvas v1.0 -- Entra ID Documentation Report -- $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
  Developed by <a href="https://github.com/SanthoshSivarajan">Santhosh Sivarajan</a>, Microsoft MVP --
  <a href="https://github.com/SanthoshSivarajan/EntraIDCanvas">github.com/SanthoshSivarajan/EntraIDCanvas</a>
</div>

</main>
</div>

<script>
var COLORS=['#60a5fa','#34d399','#f87171','#fbbf24','#a78bfa','#f472b6','#22d3ee','#fb923c','#a3e635','#e879f9'];
function buildBarChart(t,d,c){var b=document.createElement('div');b.style.cssText='background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px;box-shadow:var(--shadow)';var h=document.createElement('h3');h.style.cssText='font-size:.86rem;margin-bottom:10px;color:#e2e8f0';h.textContent=t;b.appendChild(h);var tot=Object.values(d).reduce(function(a,b){return a+b},0);if(!tot){b.innerHTML+='<p style="color:#94a3b8;font-style:italic">No data.</p>';c.appendChild(b);return}var g=document.createElement('div');g.style.cssText='display:flex;flex-direction:column;gap:6px';var e=Object.entries(d),ci=0;for(var i=0;i<e.length;i++){var p=((e[i][1]/tot)*100).toFixed(1);var r=document.createElement('div');r.style.cssText='display:flex;align-items:center;gap:8px';r.innerHTML='<span style="width:110px;font-size:.74rem;color:#94a3b8;text-align:right;flex-shrink:0">'+e[i][0]+'</span><div style="flex:1;height:20px;background:#273548;border-radius:4px;overflow:hidden;border:1px solid #334155"><div style="height:100%;border-radius:3px;width:'+p+'%;background:'+COLORS[ci%COLORS.length]+';display:flex;align-items:center;padding:0 6px;font-size:.66rem;font-weight:600;color:#fff;white-space:nowrap">'+p+'%</div></div><span style="width:44px;font-size:.74rem;color:#94a3b8;text-align:right">'+e[i][1]+'</span>';g.appendChild(r);ci++}b.appendChild(g);c.appendChild(b)}
function buildDonut(t,d,c){var b=document.createElement('div');b.style.cssText='background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px;box-shadow:var(--shadow)';var h=document.createElement('h3');h.style.cssText='font-size:.86rem;margin-bottom:10px;color:#e2e8f0';h.textContent=t;b.appendChild(h);var tot=Object.values(d).reduce(function(a,b){return a+b},0);if(!tot){b.innerHTML+='<p style="color:#94a3b8;font-style:italic">No data.</p>';c.appendChild(b);return}var dc=document.createElement('div');dc.style.cssText='display:flex;align-items:center;gap:18px;flex-wrap:wrap';var sz=130,cx=65,cy=65,r=48,cf=2*Math.PI*r;var s='<svg width="'+sz+'" height="'+sz+'" viewBox="0 0 '+sz+' '+sz+'">';var off=0,ci=0,e=Object.entries(d);for(var i=0;i<e.length;i++){var pc=e[i][1]/tot,da=pc*cf,ga=cf-da;s+='<circle cx="'+cx+'" cy="'+cy+'" r="'+r+'" fill="none" stroke="'+COLORS[ci%COLORS.length]+'" stroke-width="14" stroke-dasharray="'+da.toFixed(2)+' '+ga.toFixed(2)+'" stroke-dashoffset="'+(-off).toFixed(2)+'" transform="rotate(-90 '+cx+' '+cy+')" />';off+=da;ci++}s+='<text x="'+cx+'" y="'+cy+'" text-anchor="middle" dominant-baseline="central" fill="#e2e8f0" font-size="18" font-weight="700">'+tot+'</text></svg>';dc.innerHTML=s;var lg=document.createElement('div');lg.style.cssText='display:flex;flex-direction:column;gap:3px';ci=0;for(var i=0;i<e.length;i++){var pc=((e[i][1]/tot)*100).toFixed(1);var it=document.createElement('div');it.style.cssText='display:flex;align-items:center;gap:6px;font-size:.74rem;color:#94a3b8';it.innerHTML='<span style="width:10px;height:10px;border-radius:2px;background:'+COLORS[ci%COLORS.length]+';flex-shrink:0"></span>'+e[i][0]+': '+e[i][1]+' ('+pc+'%)';lg.appendChild(it);ci++}dc.appendChild(lg);b.appendChild(dc);c.appendChild(b)}
(function(){var c=document.getElementById('chartsContainer');if(!c)return;
buildDonut('User Status',$UserChartJSON,c);
buildDonut('User Source',$UserSourceJSON,c);
buildDonut('User Licensing',$UserLicJSON,c);
buildDonut('Group Types',$GroupChartJSON,c);
buildDonut('Group Membership Type',$GroupTypeJSON,c);
buildDonut('Group Source',$GroupSourceJSON,c);
buildDonut('Device Join Type',$DeviceChartJSON,c);
buildDonut('Device Compliance',$DeviceCompJSON,c);
buildDonut('Device OS',$DeviceOSJSON,c);
buildDonut('CA Policy Status',$CAChartJSON,c);
buildDonut('Service Principal Types',$SPChartJSON,c);
buildBarChart('Directory Roles (Top 10)',$RoleChartJSON,c);
})();
(function(){var lk=document.querySelectorAll('.sidebar nav a');var sc=[];for(var i=0;i<lk.length;i++){var id=lk[i].getAttribute('href');if(id&&id.charAt(0)==='#'){var el=document.querySelector(id);if(el)sc.push({el:el,link:lk[i]})}}window.addEventListener('scroll',function(){var cur=sc[0];for(var i=0;i<sc.length;i++){if(sc[i].el.getBoundingClientRect().top<=120)cur=sc[i]}for(var i=0;i<lk.length;i++)lk[i].classList.remove('active');if(cur)cur.link.classList.add('active')})})();
</script>
</body>
</html>
<!--
================================================================================
  EntraIDCanvas -- Entra ID Documentation Report
  Author : Santhosh Sivarajan, Microsoft MVP
  GitHub : https://github.com/SanthoshSivarajan/EntraIDCanvas
================================================================================
-->
"@

# --- Write Report -------------------------------------------------------------
$HTML | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
$FileSize = [math]::Round((Get-Item $OutputFile).Length / 1KB, 1)

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host "  |   EntraIDCanvas -- Report Generation Complete              |" -ForegroundColor Green
Write-Host "  +============================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  TENANT SUMMARY" -ForegroundColor White
Write-Host "  --------------" -ForegroundColor Gray
Write-Host "    Tenant             : $TenantName ($TenantId)" -ForegroundColor White
Write-Host "    Users              : $TotalUsers (Members: $MemberUsers, Guests: $GuestUsers)" -ForegroundColor White
Write-Host "    Groups             : $TotalGroups (Security: $SecurityGroups, M365: $M365Groups)" -ForegroundColor White
Write-Host "    Devices            : $TotalDevices" -ForegroundColor White
Write-Host "    App Registrations  : $TotalApps" -ForegroundColor White
Write-Host "    Enterprise Apps    : $TotalSPs" -ForegroundColor White
Write-Host "    CA Policies        : $TotalCA (Enabled: $EnabledCA)" -ForegroundColor White
Write-Host "    Directory Roles    : $($DirectoryRoles.Count) active" -ForegroundColor White
Write-Host "    Global Admins      : $GlobalAdminCount" -ForegroundColor White
Write-Host "    Expiring Creds     : $($AppsWithExpSecrets.Count)" -ForegroundColor White
Write-Host ""
Write-Host "  OUTPUT" -ForegroundColor White
Write-Host "  ------" -ForegroundColor Gray
Write-Host "    Report File : $OutputFile" -ForegroundColor White
Write-Host "    File Size   : $FileSize KB" -ForegroundColor White
Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |  This report was generated using EntraIDCanvas v1.0        |" -ForegroundColor Cyan
Write-Host "  |  Developed by Santhosh Sivarajan, Microsoft MVP            |" -ForegroundColor Cyan
Write-Host "  |  https://github.com/SanthoshSivarajan/EntraIDCanvas        |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""

<#
================================================================================
  EntraIDCanvas v1.0 -- Entra ID Documentation Report Generator
  Author : Santhosh Sivarajan, Microsoft MVP
  GitHub : https://github.com/SanthoshSivarajan/EntraIDCanvas
================================================================================
#>
