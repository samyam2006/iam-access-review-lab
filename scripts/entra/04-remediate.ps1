# Phase 5: Fix the access problems found by the access review
# Usage: ./scripts/entra/04-remediate.ps1 -Domain yourdomain.onmicrosoft.com

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Users.Actions, Microsoft.Graph.Groups, Microsoft.Graph.Identity.Governance
param([Parameter(Mandatory)][string]$Domain)   # e.g. samyamlab.onmicrosoft.com
$ErrorActionPreference = "Stop"

Connect-MgGraph -TenantId $Domain -NoWelcome `
    -Scopes "User.ReadWrite.All","Group.ReadWrite.All","RoleManagement.ReadWrite.Directory"

function U($alias) { Get-MgUser -UserId "$alias@$Domain" }
function G($name)  { Get-MgGroup -Filter "displayName eq '$name'" }
function Get-RoleId($roleName) {
    (Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$roleName'").Id
}
function Remove-FromGroup($alias, $group) {
    Remove-MgGroupMemberByRef -GroupId (G $group).Id -DirectoryObjectId (U $alias).Id
    Write-Host "Removed $alias from $group"
}
function Remove-AllGroups($alias) {
    $id = (U $alias).Id
    foreach ($g in Get-MgUserMemberOf -UserId $id -All | Where-Object { $_.AdditionalProperties.displayName -match '^(SG|APP)-' }) {
        Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $id
        Write-Host "Removed $alias from $($g.AdditionalProperties.displayName)"
    }
}
function Remove-Role($principalId, $roleName, $label) {
    $a = Get-MgRoleManagementDirectoryRoleAssignment -Filter "roleDefinitionId eq '$(Get-RoleId $roleName)' and principalId eq '$principalId'"
    if ($a) {
        Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $a.Id
        Write-Host "Removed $roleName from $label"
    }
}
function Add-Role($alias, $roleName) {
    New-MgRoleManagementDirectoryRoleAssignment -PrincipalId (U $alias).Id `
        -RoleDefinitionId (Get-RoleId $roleName) -DirectoryScopeId "/" | Out-Null
    Write-Host "Gave $alias $roleName"
}

# Safety check: never run without the break-glass account in place
$bg = Get-MgUser -Filter "userPrincipalName eq 'breakglass@$Domain'"
if (-not $bg) { throw "Create breakglass@$Domain with Global Administrator first (Phase 5, Part A)." }

# Problems 1-2: least privilege for admin roles
Remove-Role (U "taylor.brooks").Id "Global Administrator" "taylor.brooks"
Remove-Role (U "jordan.lee").Id    "Global Administrator" "jordan.lee"
Add-Role    "jordan.lee" "Helpdesk Administrator"

# Extra finding: outside (#EXT#) accounts should not be Global Admins
$gaId = Get-RoleId "Global Administrator"
foreach ($a in Get-MgRoleManagementDirectoryRoleAssignment -All -Filter "roleDefinitionId eq '$gaId'") {
    $u = Get-MgUser -UserId $a.PrincipalId -ErrorAction SilentlyContinue
    if ($u -and $u.UserPrincipalName -like "*#EXT#*") {
        Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $a.Id
        Write-Host "Removed Global Administrator from outside account $($u.DisplayName)"
    }
}

# Problem 4: leaver. Disable, kill active sessions, remove access
Update-MgUser -UserId "ben.adler@$Domain" -AccountEnabled:$false
Revoke-MgUserSignInSession -UserId (U "ben.adler").Id | Out-Null
Write-Host "Disabled ben.adler and revoked his sessions"
Remove-AllGroups "ben.adler"

# Problem 5: disabled account still in groups
Remove-AllGroups "lucas.hall"

# Problem 6: mover. Remove old access, add new
Remove-FromGroup "hannah.scott" "SG-Finance"
Remove-FromGroup "hannah.scott" "APP-Payroll"
New-MgGroupMember -GroupId (G "APP-CRM").Id -DirectoryObjectId (U "hannah.scott").Id
Write-Host "Added hannah.scott to APP-CRM"

# Problem 7: contractor out of payroll
Remove-FromGroup "sam.rivera" "APP-Payroll"

# Problem 8: shared account disabled; front desk staff get named accounts
Update-MgUser -UserId "frontdesk@$Domain" -AccountEnabled:$false -PasswordPolicies "None"
Write-Host "Disabled frontdesk and removed its never-expire setting"

Write-Host "Remediation done. Raj and Emily move to PIM in the portal (Part C)."
