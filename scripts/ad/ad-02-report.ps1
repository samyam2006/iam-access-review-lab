# Phase 6: Privileged access report for Active Directory
# Run on DC01:  C:\Lab\ad-02-report.ps1                      (before)
#               C:\Lab\ad-02-report.ps1 -OutDir C:\Lab\reports\after

param([string]$OutDir = "C:\Lab\reports\before")
Import-Module ActiveDirectory
New-Item -ItemType Directory -Force $OutDir | Out-Null
$date = Get-Date -Format yyyy-MM-dd

# 1. Privileged group members, including nested ones
$privGroups = "Domain Admins","Enterprise Admins","Schema Admins","Administrators",
              "Account Operators","Backup Operators","Server Operators"
$priv = foreach ($g in $privGroups) {
    $direct = @(Get-ADGroupMember $g | Select-Object -ExpandProperty SamAccountName)
    foreach ($m in Get-ADGroupMember $g -Recursive | Where-Object objectClass -eq "user") {
        $u = Get-ADUser $m -Properties Title, PasswordNeverExpires, LastLogonTimestamp
        $risk = @()
        if ($u.Title -match "Intern|Help Desk") { $risk += "Too much access for the job" }
        if ($u.SamAccountName -notin $direct)   { $risk += "Hidden: via nested group" }
        if ($u.SamAccountName -like "svc-*")    { $risk += "Service account in admin group" }
        if ($u.PasswordNeverExpires)            { $risk += "Password never expires" }
        if (-not $u.Enabled)                    { $risk += "Disabled but still privileged" }
        [pscustomobject]@{
            Group      = $g
            User       = $u.SamAccountName
            Title      = $u.Title
            Enabled    = $u.Enabled
            Membership = if ($u.SamAccountName -in $direct) { "Direct" } else { "Nested" }
            LastLogon  = if ($u.LastLogonTimestamp) { [datetime]::FromFileTime($u.LastLogonTimestamp) } else { "Never" }
            Risk       = $risk -join "; "
        }
    }
}
$priv | Export-Csv "$OutDir\privileged-members-$date.csv" -NoTypeInformation

# 2. Leavers who are still enabled or still in groups
$leavers = Import-Csv C:\Lab\hr-terminations.csv | ForEach-Object {
    $u = Get-ADUser -Filter "SamAccountName -eq '$($_.UserPrincipalName)'" -Properties MemberOf
    if ($u -and ($u.Enabled -or $u.MemberOf.Count -gt 0)) {
        [pscustomobject]@{
            User = $u.SamAccountName; Enabled = $u.Enabled; TerminatedOn = $_.TerminationDate
            Groups = ($u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) -join '; '
        }
    }
}
$leavers | Export-Csv "$OutDir\leavers-$date.csv" -NoTypeInformation

# 3. Password policy
Get-ADDefaultDomainPasswordPolicy |
    Select-Object MinPasswordLength, ComplexityEnabled, PasswordHistoryCount, MaxPasswordAge, LockoutThreshold, LockoutDuration |
    Export-Csv "$OutDir\password-policy-$date.csv" -NoTypeInformation

Write-Host "`nPrivileged accounts with risks:"
$priv | Where-Object Risk | Format-Table Group, User, Membership, Risk -AutoSize
Write-Host "Leavers still active or in groups:"
$leavers | Format-Table -AutoSize
Get-ADDefaultDomainPasswordPolicy | Format-List MinPasswordLength, LockoutThreshold, PasswordHistoryCount

# Copy reports to the Mac through the redirected lab-transfer folder
Copy-Item $OutDir "\\tsclient\lab-transfer\" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Reports saved to $OutDir (and copied to lab-transfer if connected)"
