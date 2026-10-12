# Phase 6: Fix the Active Directory problems
# Run on DC01 in PowerShell as Administrator:  C:\Lab\ad-03-remediate.ps1

Import-Module ActiveDirectory
$domain = Get-ADDomain
$root   = "OU=Contoso,$($domain.DistinguishedName)"
$nb     = $domain.NetBIOSName

# Remove excess admin rights, including the nested IT-Ops group
foreach ($m in "taylor.brooks","jordan.lee","IT-Ops","svc-backup") {
    Remove-ADGroupMember "Domain Admins" -Members $m -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed $m from Domain Admins"
}

# Help desk: delegate password reset only, on the Users OU
if (-not (Get-ADGroup -Filter "Name -eq 'Helpdesk-PasswordReset'")) {
    New-ADGroup -Name "Helpdesk-PasswordReset" -GroupScope Global -GroupCategory Security -Path "OU=Groups,$root"
}
Add-ADGroupMember "Helpdesk-PasswordReset" -Members "jordan.lee","chris.moreno"
dsacls "OU=Users,$root" /I:S /G "$nb\Helpdesk-PasswordReset:CA;Reset Password;user" | Out-Null
dsacls "OU=Users,$root" /I:S /G "$nb\Helpdesk-PasswordReset:WP;pwdLastSet;user"    | Out-Null
Write-Host "Delegated password reset on the Users OU to Helpdesk-PasswordReset"

# Service account: no admin rights, password must rotate
Set-ADUser "svc-backup" -PasswordNeverExpires $false
Write-Host "svc-backup password now expires"

# Leavers: disable, strip groups, move to Disabled Users
foreach ($sam in "ben.adler","lucas.hall") {
    $u = Get-ADUser $sam -Properties MemberOf
    Disable-ADAccount $u
    $u.MemberOf | ForEach-Object { Remove-ADGroupMember $_ -Members $u -Confirm:$false }
    Move-ADObject $u.DistinguishedName -TargetPath "OU=Disabled Users,$root"
    Write-Host "Disabled $sam, removed groups, moved to Disabled Users"
}

# Domain password policy
Set-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot -MinPasswordLength 14 -ComplexityEnabled $true `
    -PasswordHistoryCount 24 -MaxPasswordAge 365.00:00:00 `
    -LockoutThreshold 10 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00
Write-Host "Domain password policy: 14 characters, lockout after 10 tries"

# Stricter policy just for admins (fine-grained password policy)
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'PSO-Admins'")) {
    New-ADFineGrainedPasswordPolicy -Name "PSO-Admins" -Precedence 10 -MinPasswordLength 16 `
        -ComplexityEnabled $true -PasswordHistoryCount 24 -MaxPasswordAge 180.00:00:00 `
        -LockoutThreshold 5 -LockoutDuration 00:30:00 -LockoutObservationWindow 00:30:00
    Add-ADFineGrainedPasswordPolicySubject "PSO-Admins" -Subjects "Domain Admins"
}
Write-Host "Admin password policy: 16 characters, lockout after 5 tries"

Write-Host "AD remediation done. Now run: C:\Lab\ad-02-report.ps1 -OutDir C:\Lab\reports\after"
