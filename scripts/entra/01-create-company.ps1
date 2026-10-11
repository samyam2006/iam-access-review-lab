# Phase 2: Build the fake company in Entra ID
# Usage: ./scripts/entra/01-create-company.ps1 -Domain yourdomain.onmicrosoft.com

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups
param([Parameter(Mandatory)][string]$Domain)   # e.g. samyamlab.onmicrosoft.com

# Stop at the first error instead of carrying on and printing misleading messages
$ErrorActionPreference = "Stop"

# -TenantId makes sure you sign in to Contoso Lab, not your school directory
Connect-MgGraph -TenantId $Domain -Scopes "User.ReadWrite.All","Group.ReadWrite.All" -NoWelcome
$users = Import-Csv "$PSScriptRoot/../../data/users.csv"

function Get-OrCreateGroup($Name, $Description) {
    $g = Get-MgGroup -Filter "displayName eq '$Name'"
    if (-not $g) {
        $g = New-MgGroup -DisplayName $Name -Description $Description `
             -MailEnabled:$false -MailNickname $Name.ToLower() -SecurityEnabled
        Write-Host "Created group $Name"
    }
    return $g
}

function New-TempPassword {
    $chars = (48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ }
    'Aa1!' + (-join ($chars | Get-Random -Count 14))
}

# Department groups
$deptGroups = @{}
foreach ($d in ($users.Department | Sort-Object -Unique)) {
    $deptGroups[$d] = Get-OrCreateGroup "SG-$d" "All $d staff"
}

# App-access groups and which departments should be in them
$appAccess = @{
    "APP-Payroll"      = @("Finance", "HR")
    "APP-CRM"          = @("Sales", "Executive")
    "APP-ITAdminTools" = @("IT")
}
$appGroups = @{}
foreach ($app in $appAccess.Keys) {
    $appGroups[$app] = Get-OrCreateGroup $app "Access to $app"
}

# Users
$created = @{}
foreach ($u in $users) {
    $alias = "$($u.FirstName).$($u.LastName)".ToLower()
    $upn   = "$alias@$Domain"
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) { $created[$alias] = $existing; continue }

    $new = New-MgUser -DisplayName "$($u.FirstName) $($u.LastName)" `
        -GivenName $u.FirstName -Surname $u.LastName `
        -UserPrincipalName $upn -MailNickname $alias `
        -Department $u.Department -JobTitle $u.JobTitle `
        -EmployeeType $u.EmployeeType -UsageLocation "US" `
        -AccountEnabled `
        -PasswordProfile @{ Password = (New-TempPassword); ForceChangePasswordNextSignIn = $true }
    $created[$alias] = $new
    Write-Host "Created $upn"

    New-MgGroupMember -GroupId $deptGroups[$u.Department].Id -DirectoryObjectId $new.Id
    foreach ($app in $appAccess.Keys) {
        if ($appAccess[$app] -contains $u.Department -and $u.EmployeeType -ne "Contractor") {
            New-MgGroupMember -GroupId $appGroups[$app].Id -DirectoryObjectId $new.Id
        }
    }
}

# Managers (second pass, once everyone exists)
foreach ($u in $users | Where-Object Manager) {
    $alias = "$($u.FirstName).$($u.LastName)".ToLower()
    $mgr = $created[$u.Manager]
    Set-MgUserManagerByRef -UserId $created[$alias].Id -BodyParameter @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($mgr.Id)"
    }
}
Write-Host "Done: $($users.Count) users."
