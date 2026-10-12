# Joiner / Mover / Leaver Policy — Contoso Lab

**Owner:** IT Security
**Applies to:** all employee, intern and contractor accounts in Microsoft Entra ID and Active Directory
**Review:** yearly, or after any access-related incident

## 1. Joiners
- Accounts are created only from an approved HR record, never from an email or chat request.
- Access comes from department groups (`SG-*`). One-off access grants to individual users are not allowed.
- App access (`APP-*`) requires approval from the person's manager.
- Interns and contractors are flagged with Employee Type so they can be reviewed separately.
- MFA registration is required at first sign-in (Conditional Access policy CA01).

## 2. Movers
- When someone changes department, their old department group and app access are removed within **5 business days**.
- The new manager approves any new app access.
- The access review script flags anyone in a group that doesn't match their department (finding JML-03).

## 3. Leavers
- The account is disabled and all sessions revoked within **24 hours** of HR notice.
- All group memberships and admin roles are removed at the same time.
- Disabled accounts are deleted after **30 days**, unless Legal asks for a hold.
- The access review script compares the HR termination list to enabled accounts (finding JML-01).

## 4. Contractors
- Contractor accounts have an end date that matches the contract.
- Contractors do not get access to sensitive apps such as payroll, unless approved in writing for a limited time.

## 5. Privileged access
- No more than **2 permanent Global Administrators**: one named admin account and one break-glass account.
- All other admin roles are **eligible through Privileged Identity Management**, with activation limited to 4 hours and requiring MFA and a written reason.
- Interns, contractors and outside (guest) accounts never hold admin roles.
- Each person is given the narrowest role that fits their job (for example, Helpdesk Administrator instead of Global Administrator for help desk staff).

## 6. Break-glass account
- The break-glass account is excluded from Conditional Access so it works during an outage.
- Its password is long, randomly generated, and stored offline. It is never used for daily work.
- Any sign-in with this account is investigated.

## 7. Shared accounts
- Shared or generic accounts are not allowed. Every account belongs to one named person.
- Passwords are never set to "never expire."

## 8. Access reviews
- Members of every app group (`APP-*`) are reviewed **quarterly** by the app owner or the manager.
- If a reviewer doesn't respond, access is removed automatically.
- The access review script runs **monthly**. Critical findings are fixed within 24 hours, High within 7 days, and Medium within 30 days.
