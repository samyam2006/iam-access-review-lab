# IAM Access Review Lab

I built a 25-person fake company in **Microsoft Entra ID** and **Active Directory**, planted 8 common access problems, wrote PowerShell scripts to find them, and fixed every one. The goal was to practice the core work of an IAM or GRC analyst: access reviews, least privilege, joiner/mover/leaver controls, and documenting it for auditors.

**Tools:** Microsoft Entra ID (P2 trial), Active Directory on Windows Server 2022 (Azure VM), PowerShell 7, Microsoft Graph, Privileged Identity Management, Conditional Access, Access Reviews

## Results

| | Before | After |
| --- | --- | --- |
| Critical findings (Entra ID) | 3 | **0** |
| Permanent Global Administrators | 6 | **2** (named admin + break-glass) |
| Leavers or movers with leftover access | 3 | **0** |
| Users covered by an MFA policy | 0% | **100%** |
| Domain Admins with risk flags (AD) | 4 | **0** |
| AD minimum password length | 7 | **14** (16 for admins) |
| AD account lockout | Never | **After 10 failed tries** |

## What I built

### 1. A fake company, created by script
`scripts/entra/01-create-company.ps1` reads `data/users.csv` and creates 25 users across 6 departments, 9 security groups, and manager relationships in Entra ID. Access comes from department groups (`SG-*`) and app groups (`APP-*`), not one-off grants.

### 2. Eight planted problems
`scripts/entra/02-plant-issues.ps1` creates the mistakes that show up in real audits:

| # | Problem | Account |
| --- | --- | --- |
| 1 | IT intern with Global Administrator | taylor.brooks |
| 2 | Help desk technician with Global Administrator | jordan.lee |
| 3 | Too many permanent Global Administrators | (tenant) |
| 4 | Employee left, account still enabled | ben.adler |
| 5 | Account disabled, but group access left behind | lucas.hall |
| 6 | Moved from Finance to Sales, kept Finance and payroll access | hannah.scott |
| 7 | Contractor added to the payroll app | sam.rivera |
| 8 | Shared account with no owner, password never expires | frontdesk |

### 3. An access review script
`scripts/entra/03-access-review.ps1` pulls users, groups, admin roles, MFA methods and sign-in history from Microsoft Graph, and checks them against 10 rules. It compares an HR termination list to enabled accounts, checks group membership against department, and flags admins whose job doesn't need admin rights. It writes a findings CSV sorted by severity and a full user inventory.

**It found all 8 planted problems, plus one I didn't plant:** the school account I used to create the tenant was still a Global Administrator, with no owner recorded. That's a real-world finding, an outside account with full control.

See [`docs/findings-summary.md`](docs/findings-summary.md) for the full write-up and [`reports/`](reports/) for the before and after reports.

### 4. Remediation
- `scripts/entra/04-remediate.ps1` removed excess admin rights, disabled the leaver and revoked his sessions, stripped leftover group access, and disabled the shared account. It refuses to run unless a break-glass account exists, so the fix can't lock out the tenant.
- **Privileged Identity Management:** the IT manager and sysadmin became *eligible* Global Admins, activated for up to 4 hours with MFA and a written reason.
- **Conditional Access:** MFA required for all users, and legacy authentication blocked, with the break-glass account excluded. Tested in report-only mode with the What If tool before turning on.
- **Access reviews:** quarterly review of the payroll group, with access removed automatically if reviewers don't respond.
- **Policy:** a joiner/mover/leaver policy in [`docs/jml-policy.md`](docs/jml-policy.md).

### 5. Active Directory
On a Windows Server 2022 domain controller in Azure:
- `scripts/ad/ad-01-build.ps1` built an OU structure and the same company, then planted classic AD mistakes, including a **hidden Domain Admin**: a help desk tech added through a nested `IT-Ops` group, so he never appears as a direct member.
- `scripts/ad/ad-02-report.ps1` reports every member of 7 privileged groups **recursively**, which revealed the hidden admin, plus leavers and the password policy.
- `scripts/ad/ad-03-remediate.ps1` removed excess admin rights, **delegated password reset only** to a help desk group instead of Domain Admin, fixed the service account, cleaned up leavers, and enforced a 14-character password policy with lockout. A fine-grained policy requires 16 characters for admins.
- I tested the delegation: the help desk account could reset a user's password, but was denied when it tried to add itself to Domain Admins.

## What went wrong (and what I learned)

- **My script printed "Created" for users it never created.** The Graph module wasn't installed, so every command failed, but the script kept going. I added `#Requires` and `$ErrorActionPreference = "Stop"` to every script, so a failure now stops at the first error.
- **The full Microsoft Graph module filled my disk.** I installed only the 6 sub-modules the project needs.
- **False positives in my own review.** The after report flagged disabled accounts as "still in groups" with an empty group list, because PowerShell counted an empty value as one item. I fixed the filter and re-ran it. Validating the tool matters as much as the findings.
- **Checking only direct group members misses admins.** The nested IT-Ops group hid a Domain Admin, and Domain Admins is itself nested in the built-in Administrators group. Recursive checks are essential.
- **The weakest AD setting wasn't the obvious one.** The default policy had no account lockout at all, which allows unlimited password guessing, a bigger risk than the 7-character minimum.

## Accepted residual risk
The after report still lists fake users with no MFA registered and accounts that have never signed in. They never sign in, and Conditional Access requires MFA registration the first time they do. The break-glass account has no owner on purpose, and the shared account is disabled pending deletion under the 30-day policy.

## Repo layout
```
iam-access-review-lab/
├── data/            fake company and HR termination list
├── scripts/entra/   create company, plant issues, access review, remediate
├── scripts/ad/      AD build, privileged access report, remediate
├── reports/         before and after findings (Entra ID and AD)
├── docs/            findings summary, joiner/mover/leaver policy
└── screenshots/
```

## Next steps
- Replace the AD service account with a group managed service account (gMSA), which rotates its own password.
- Sync AD to Entra ID with Entra Connect to manage identities in one place.
- Run the access review on a schedule and alert on new Critical findings.
