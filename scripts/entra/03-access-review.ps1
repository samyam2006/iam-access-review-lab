# Phase 4: Access review. Checks every user, group and admin role against 10 rules
# Usage: ./scripts/entra/03-access-review.ps1 -Domain yourdomain.onmicrosoft.com
#        ./scripts/entra/03-access-review.ps1 -Domain yourdomain.onmicrosoft.com -OutDir ./reports/after

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.Governance, Microsoft.Graph.Identity.SignIns
param(
    [Parameter(Mandatory)][string]$Domain,
    [string]$OutDir = "$PSScriptRoot/../../reports/before",
    [int]$StaleDays = 90
)
$ErrorActionPreference = "Stop"

Connect-MgGraph -TenantId $Domain -NoWelcome -Scopes "User.Read.All","Group.Read.All","RoleManagement.Read.Directory","AuditLog.Read.All","UserAuthenticationMethod.Read.All"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding($Id, $Severity, $User, $Detail, $Fix) {
    $findings.Add([pscustomobject]@{
        FindingId = $Id; Severity = $Severity; User = $User; Detail = $Detail; RecommendedFix = $Fix })
}

# ---------- Collect ----------
Write-Host "Collecting users, groups and roles..."
$props = "id,displayName,userPrincipalName,department,jobTitle,employeeType,accountEnabled,passwordPolicies,createdDateTime"
try {
    $users = Get-MgUser -All -Property "$props,signInActivity"
    $haveSignIns = $true
} catch {
    Write-Warning "Sign-in data needs Entra ID P1/P2. Skipping stale-account checks."
    $users = Get-MgUser -All -Property $props
    $haveSignIns = $false
}
$byId = @{}; foreach ($u in $users) { $byId[$u.Id] = $u }

$groups = Get-MgGroup -All | Where-Object { $_.DisplayName -match '^(SG|APP)-' }
$memberships = @{}
foreach ($g in $groups) {
    foreach ($m in Get-MgGroupMember -GroupId $g.Id -All) {
        $memberships[$m.Id] = @(@($memberships[$m.Id]) + $g.DisplayName | Where-Object { $_ })
    }
}

# Who has a manager? Ask each person for their direct reports
# (an empty list is normal, unlike asking someone with no manager, which errors)
$hasManager = @{}
foreach ($u in $users) {
    foreach ($dr in Get-MgUserDirectReport -UserId $u.Id -All) { $hasManager[$dr.Id] = $true }
}

$ga    = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq 'Global Administrator'"
$gaIds = @((Get-MgRoleManagementDirectoryRoleAssignment -All -Filter "roleDefinitionId eq '$($ga.Id)'").PrincipalId)

$termUpns = Import-Csv "$PSScriptRoot/../../data/hr-terminations.csv" |
    ForEach-Object { "$($_.UserPrincipalName)@$Domain".ToLower() }

$appAccess = @{
    "APP-Payroll"      = @("Finance", "HR")
    "APP-CRM"          = @("Sales", "Executive")
    "APP-ITAdminTools" = @("IT")
}
$mfaTypes = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod',
            '#microsoft.graph.phoneAuthenticationMethod',
            '#microsoft.graph.fido2AuthenticationMethod',
            '#microsoft.graph.softwareOathAuthenticationMethod',
            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'

# ---------- Tenant-wide checks ----------
if ($gaIds.Count -ge 5) {
    Add-Finding "PRIV-01" "High" "(tenant)" "$($gaIds.Count) permanent Global Administrators" `
        "Keep 2-4 permanent; make the rest eligible through PIM"
}
foreach ($id in $gaIds) {
    $u = $byId[$id]; if (-not $u) { continue }
    if ($u.EmployeeType -in "Intern","Contractor" -or $u.JobTitle -match "Intern|Help Desk") {
        Add-Finding "PRIV-02" "Critical" $u.UserPrincipalName "Global Administrator held by: $($u.JobTitle)" `
            "Remove; assign the narrowest role that fits the job"
    }
}

# ---------- Per-user checks ----------
Write-Host "Checking $($users.Count) users..."
foreach ($u in $users) {
    $upn = $u.UserPrincipalName.ToLower()
    if ($upn -like "labadmin@*") { continue }
    $myGroups = @($memberships[$u.Id] | Where-Object { $_ })   # drop empties so "no groups" counts as 0

    if ($upn -in $termUpns -and $u.AccountEnabled) {
        Add-Finding "JML-01" "Critical" $upn "Terminated per HR but account is still enabled" "Disable, remove groups, revoke sessions"
    }
    if (-not $u.AccountEnabled -and $myGroups.Count -gt 0) {
        Add-Finding "JML-02" "Medium" $upn "Disabled but still in: $($myGroups -join ', ')" "Remove all group memberships"
    }
    foreach ($g in $myGroups | Where-Object { $_ -like "SG-*" -and $_ -ne "SG-$($u.Department)" }) {
        Add-Finding "JML-03" "High" $upn "In $g but department is $($u.Department)" "Remove from $g"
    }
    foreach ($g in $myGroups | Where-Object { $_ -like "APP-*" }) {
        if ($u.EmployeeType -eq "Contractor") {
            Add-Finding "LP-01" "High" $upn "Contractor has $g" "Remove; grant time-limited access only if approved"
        } elseif ($appAccess[$g] -notcontains $u.Department) {
            Add-Finding "LP-02" "High" $upn "Has $g, which $($u.Department) should not have" "Remove from $g"
        }
    }

    if (-not $u.Department -and -not $hasManager[$u.Id]) {
        Add-Finding "ACC-01" "Medium" $upn "No department or manager: likely shared or orphaned" "Assign an owner or replace with named accounts"
    }
    if ($u.PasswordPolicies -match "DisablePasswordExpiration") {
        Add-Finding "ACC-02" "Medium" $upn "Password set to never expire" "Remove the exception; require MFA"
    }

    if ($u.AccountEnabled) {
        $methods = Get-MgUserAuthenticationMethod -UserId $u.Id
        if (-not ($methods | Where-Object { $_.AdditionalProperties.'@odata.type' -in $mfaTypes })) {
            Add-Finding "MFA-01" "High" $upn "No MFA method registered" "Require MFA with Conditional Access"
        }
        if ($haveSignIns) {
            $last = $u.SignInActivity.LastSuccessfulSignInDateTime ?? $u.SignInActivity.LastSignInDateTime
            if (-not $last) {
                Add-Finding "STALE-01" "Low" $upn "Never signed in" "Confirm with manager; disable if not needed"
            } elseif ($last -lt (Get-Date).AddDays(-$StaleDays)) {
                Add-Finding "STALE-02" "Medium" $upn "No sign-in for $StaleDays+ days" "Disable after manager review"
            }
        }
    }
}

# ---------- Report ----------
$date = Get-Date -Format "yyyy-MM-dd"
$rank = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
$findings | Sort-Object @{ e = { $rank[$_.Severity] } }, FindingId |
    Export-Csv "$OutDir/findings-$date.csv" -NoTypeInformation

$users | Select-Object DisplayName, UserPrincipalName, Department, JobTitle, EmployeeType, AccountEnabled,
    @{ n = "Groups";      e = { @($memberships[$_.Id]) -join "; " } },
    @{ n = "GlobalAdmin"; e = { $_.Id -in $gaIds } },
    @{ n = "LastSignIn";  e = { $_.SignInActivity.LastSuccessfulSignInDateTime } } |
    Export-Csv "$OutDir/user-inventory-$date.csv" -NoTypeInformation

$findings | Group-Object Severity | Select-Object Name, Count | Format-Table
Write-Host "Report saved to $OutDir"
