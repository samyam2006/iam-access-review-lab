# Phase 6: Build the Contoso company in Active Directory and plant the classic AD mistakes
# Run on DC01 in PowerShell as Administrator:  C:\Lab\ad-01-build.ps1

Import-Module ActiveDirectory
$ErrorActionPreference = "Stop"
$domain = Get-ADDomain
$root   = "OU=Contoso,$($domain.DistinguishedName)"

function New-OUIfMissing($Name, $Path) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false
        Write-Host "Created OU $Name"
    }
}
function New-GroupIfMissing($Name, $Path) {
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'")) {
        New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path $Path
        Write-Host "Created group $Name"
    }
}
function New-TempPassword {
    $chars = (48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ }
    ConvertTo-SecureString ('Aa1!' + (-join ($chars | Get-Random -Count 14))) -AsPlainText -Force
}

# OU structure
New-OUIfMissing "Contoso" $domain.DistinguishedName
"Users","Groups","Admins","Service Accounts","Disabled Users" | ForEach-Object { New-OUIfMissing $_ $root }
$users = Import-Csv C:\Lab\users.csv
$depts = $users.Department | Sort-Object -Unique
$depts | ForEach-Object { New-OUIfMissing $_ "OU=Users,$root" }

# Department groups
foreach ($d in $depts) { New-GroupIfMissing "SG-$d" "OU=Groups,$root" }

# Users
foreach ($u in $users) {
    $sam = "$($u.FirstName).$($u.LastName)".ToLower()
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") { continue }
    New-ADUser -Name "$($u.FirstName) $($u.LastName)" -GivenName $u.FirstName -Surname $u.LastName `
        -SamAccountName $sam -UserPrincipalName "$sam@$($domain.DNSRoot)" `
        -Department $u.Department -Title $u.JobTitle -Description $u.EmployeeType `
        -Path "OU=$($u.Department),OU=Users,$root" `
        -AccountPassword (New-TempPassword) -Enabled $true -ChangePasswordAtLogon $true
    Add-ADGroupMember "SG-$($u.Department)" -Members $sam
    Write-Host "Created $sam"
}
foreach ($u in $users | Where-Object Manager) {
    Set-ADUser "$($u.FirstName).$($u.LastName)".ToLower() -Manager $u.Manager
}

# ---------- Plant the AD problems ----------
Add-ADGroupMember "Domain Admins" -Members "taylor.brooks","jordan.lee"     # intern + help desk
New-GroupIfMissing "IT-Ops" "OU=Groups,$root"
Add-ADGroupMember "IT-Ops" -Members "chris.moreno"
Add-ADGroupMember "Domain Admins" -Members "IT-Ops"                         # hidden nested admin

if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc-backup'")) {
    New-ADUser -Name "svc-backup" -SamAccountName "svc-backup" -Path "OU=Service Accounts,$root" `
        -AccountPassword (New-TempPassword) -Enabled $true -PasswordNeverExpires $true -Description "Backup service"
}
Add-ADGroupMember "Domain Admins" -Members "svc-backup"                     # service account as admin

Disable-ADAccount "lucas.hall"                                              # disabled, groups left behind
# ben.adler left the company but stays enabled: that IS the problem

Write-Host "AD company built and problems planted."
