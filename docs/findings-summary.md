# Access Review: Findings Summary

**Environment:** Contoso Lab (Microsoft Entra ID), 28 accounts
**Review date:** October 11, 2026
**Method:** `scripts/entra/03-access-review.ps1`, which pulls users, groups, admin roles, MFA methods and sign-in history from Microsoft Graph and checks them against 10 rules.

## Results by severity

| Severity | Count |
| --- | --- |
| Critical | 3 |
| High | 27 |
| Medium | 4 |
| Low | 21 |
| **Total** | **55** |

All 8 planted access problems were detected. The review also found one issue that was not planted: the personal school account used to create the tenant was still a Global Administrator, with no department or owner recorded.

## Top 3 risks

**1. Admin rights are given out far too widely (Critical).**
There are 6 permanent Global Administrators, against Microsoft's guidance of fewer than 5. Two of them are an IT intern and a help desk technician who only need to reset passwords. An outside account (the school account that created the tenant) also has full control. If any one of these accounts is compromised, an attacker controls the entire environment.

**2. People who leave or change jobs keep their access (Critical / High).**
Ben Adler left on September 30, but his account is still active and can still reach payroll. Lucas Hall's account was disabled, but his group memberships were never removed. Hannah Scott moved from Finance to Sales and still has Finance and payroll access. The leaver and mover processes are not removing access.

**3. Almost nobody uses multi-factor authentication (High).**
23 of 26 enabled users have no MFA method registered, and Security Defaults are turned off. A single stolen password is enough to sign in as any of them, including the help desk technician with Global Administrator.

## Other findings

- A contractor (Sam Rivera) was added directly to the payroll app group.
- A shared "Front Desk" account has no owner and a password set to never expire.
- 21 accounts have never signed in. In a real company, each would need manager confirmation that it is still needed.

## Recommended fix order

1. **Today:** disable Ben Adler's account and revoke his sessions; remove Global Administrator from the intern, the help desk technician, and the school account.
2. **This week:** require MFA for all users with Conditional Access, and create a break-glass emergency account excluded from it.
3. **This week:** remove leftover group access for Lucas Hall, Hannah Scott and Sam Rivera; disable the shared Front Desk account.
4. **This month:** move remaining admins to just-in-time access with Privileged Identity Management, and schedule quarterly access reviews for the payroll group.
5. **Ongoing:** adopt a joiner/mover/leaver policy and run this review monthly.
