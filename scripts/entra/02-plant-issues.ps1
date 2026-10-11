# Phase 3: Plant 8 realistic access problems
# Usage: ./scripts/entra/02-plant-issues.ps1 -Domain yourdomain.onmicrosoft.com

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.Governance
param([Parameter(Mandatory)][string]$Domain)   # e.g. samyamlab.onmicrosoft.com
$ErrorActionPreference = "Stop"

Connect-MgGraph -TenantId $Domain -NoWelcome `
    -Scopes "User.ReadWrite.All","Group.ReadWrite.All","RoleManagement.ReadWrite.Directory"

function U($alias) { Get-MgUser -UserId "$alias@$Domain" }
function G($name)  { Get-MgGroup -Filter "displayName eq '$name'" }
function Add-Role($alias, $roleName) {
    $role = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$roleName'"
    New-MgRoleManagementDirectoryRoleAssignment -PrincipalId (U $alias).Id `
        -RoleDefinitionId $role.Id -DirectoryScopeId "/" | Out-Null
    Write-Host "Gave $alias the $roleName role"
}

# Problems 1-3: too many Global Admins, including an intern and help desk
"taylor.brooks","jordan.lee","raj.patel","emily.stone" | ForEach-Object { Add-Role $_ "Global Administrator" }

# Problem 4: Ben Adler left (see hr-terminations.csv), so do nothing. That IS the problem.

# Problem 5: Lucas Hall disabled, but nobody removed his groups
Update-MgUser -UserId "lucas.hall@$Domain" -AccountEnabled:$false
Write-Host "Disabled lucas.hall (groups left behind)"

# Problem 6: Hannah Scott moves to Sales; old access is never removed
Update-MgUser -UserId "hannah.scott@$Domain" -Department "Sales" -JobTitle "Sales Operations Analyst"
New-MgGroupMember -GroupId (G "SG-Sales").Id -DirectoryObjectId (U "hannah.scott").Id
Set-MgUserManagerByRef -UserId (U "hannah.scott").Id -BodyParameter @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$((U 'mia.johnson').Id)" }
Write-Host "Moved hannah.scott to Sales (kept Finance access)"

# Problem 7: contractor added to payroll "just for one task"
New-MgGroupMember -GroupId (G "APP-Payroll").Id -DirectoryObjectId (U "sam.rivera").Id
Write-Host "Added contractor sam.rivera to APP-Payroll"

# Problem 8: shared account, no owner, password never expires
$chars = (48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ }
New-MgUser -DisplayName "Front Desk" -UserPrincipalName "frontdesk@$Domain" `
    -MailNickname "frontdesk" -AccountEnabled -UsageLocation "US" `
    -PasswordPolicies "DisablePasswordExpiration" `
    -PasswordProfile @{ Password = 'Aa1!' + (-join ($chars | Get-Random -Count 14)); ForceChangePasswordNextSignIn = $false } | Out-Null
Write-Host "Created shared frontdesk account"

Write-Host "All 8 problems planted."
