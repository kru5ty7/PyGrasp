---
title: 10 - RBAC, ABAC and Enterprise SSO
description: "RBAC grants through role membership (User→Role→Permission), ABAC evaluates attributes at request time - and enterprise SSO runs on OIDC (identity layered on OAuth2, JWT id_tokens) or SAML (the XML predecessor still everywhere in enterprises)."
tags: [rbac, abac, authorization, oidc, saml, sso, access-control, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-07-07
---

# RBAC, ABAC and Enterprise SSO

> Authorization models answer "may this identity do this action"; SSO protocols answer "who is this identity, according to whom." Interviews test both the models and the mapping to real systems - and the same Role→Permission shape reappears from app code to Kubernetes to IAM.

---

## Quick Reference

**Core idea:**
- **RBAC core model**: Users are *assigned* Roles; Roles *bundle* Permissions; code checks permissions (`timesheet:edit`), never roles - so role redesign doesn't touch call sites
- **ABAC**: policy evaluates *attributes* of subject, resource, action, and context at request time - "managers may edit timesheets *of their own reports* *during business hours*"; more expressive, harder to audit ("who can access X?" requires evaluation, not lookup)
- Practical systems are RBAC-first with attribute conditions where genuinely needed (AWS IAM is exactly this: role policies + `Condition` blocks)
- **OAuth2** = delegated *authorization* (access to resources); **OIDC** = *authentication* layered on OAuth2 - adds a signed JWT `id_token` (who the user is), the `/userinfo` endpoint, and standard claims (`sub`, `email`)
- **SAML**: the XML-based SSO predecessor - IdP posts a signed assertion to the service provider; browser-redirect flows, enterprise-ubiquitous (Okta/AD FS integrations)
- Enterprise flow: app → redirects to IdP (Okta/Azure AD) via OIDC or SAML → IdP authenticates (with MFA) → returns token/assertion carrying identity + group claims → app maps groups to its own roles

**Tricky points:**
- Checking roles in code (`if user.role == "admin"`) instead of permissions is the classic RBAC mistake - every role change becomes a code change
- OIDC's `id_token` proves *authentication*; the `access_token` is for *resource access* - sending the wrong one to the wrong party is a real vulnerability class
- Group claims from the IdP are the bridge: SSO delivers identity + groups; *authorization stays the app's job* - mapping `AD:Payroll-Admins` → internal `payroll_admin` role
- Role explosion is RBAC's failure mode (a role per team × env × function); attribute conditions or permission scoping fix it before ABAC-everything does

---

## What It Is

RBAC's power is the indirection. Users change jobs constantly; what a "Payroll Admin" may do changes rarely. Binding users to roles (cheap, frequent, auditable) separately from roles to permissions (deliberate, rare, reviewed) means access reviews read as "who holds Payroll Admin?" - a list - rather than per-user permission archaeology. The discipline that makes it work: application code checks *permissions* (`can(user, "timesheet:edit")`), and only the role definitions know which roles carry which permissions.

ABAC generalizes to policy over attributes: subject attributes (department, clearance), resource attributes (owner, classification), action, and context (time, IP, device). It expresses what RBAC cannot - "edit *your own reports'* timesheets" is inherently relational - but pays in auditability: answering "who can edit this timesheet?" now requires evaluating policy against every user, not reading a membership table. Mature systems therefore run hybrid: RBAC for the coarse grants, attribute conditions for the relational edges - the exact structure of AWS IAM policies with `Condition` blocks ([[iam-policies|IAM Policies]]).

On the SSO side, the protocol history explains the acronyms. OAuth2 was built for delegation - let this app read my calendar - and its access tokens deliberately say nothing about *who the user is*. OIDC closes that gap on top of OAuth2's flows ([[oauth2|OAuth2]]): the authorization-code flow additionally returns an `id_token`, a signed JWT ([[jwt|JWT]]) asserting identity claims, verifiable against the IdP's published keys. SAML solved the same problem a decade earlier in XML: the IdP posts a signed assertion through the browser to the service provider. Feature-wise they converge - redirect to IdP, authenticate centrally, return signed identity - so the practical answer is: new builds use OIDC (JSON/JWT, API-friendly); SAML persists because enterprise IdPs and legacy vendors speak it.

The full enterprise picture ties the two halves: SSO (OIDC or SAML) *authenticates* and delivers group claims; the application *authorizes* by mapping those groups onto its internal RBAC. Identity is centralized - joiners/leavers/MFA handled once at the IdP; permissions stay local to each app, where their meaning lives.

---

## How It Actually Works

```python
# RBAC done right: code checks permissions, not roles
ROLE_PERMISSIONS = {
    "payroll_admin": {"timesheet:view", "timesheet:edit", "report:run"},
    "employee":      {"timesheet:view_own", "timesheet:submit"},
}

def can(user, permission: str) -> bool:
    return any(permission in ROLE_PERMISSIONS[r] for r in user.roles)

@app.put("/timesheets/{id}")
def edit_timesheet(id: int, user=Depends(current_user)):
    if not can(user, "timesheet:edit"):
        raise HTTPException(403)
```

```python
# OIDC in one glance: validate the id_token, map IdP groups → app roles
claims = jwt.decode(id_token, idp_public_key, audience=CLIENT_ID,
                    issuer="https://login.company.com")
# claims: {"sub": "u123", "email": "...", "groups": ["AD-Payroll-Admins"]}

GROUP_ROLE_MAP = {"AD-Payroll-Admins": "payroll_admin"}
user.roles = [GROUP_ROLE_MAP[g] for g in claims["groups"] if g in GROUP_ROLE_MAP]
```

ABAC-style condition where RBAC runs out: `can_edit = "timesheet:edit" in perms and target.team_id in user.managed_team_ids`.

---

## How It Connects

The same Role→Permission model instantiates across the stack - one mental model, four systems:

- Application RBAC (this note) - User→Role→Permission
- Kubernetes RBAC - Subject→RoleBinding→Role→Rules ([[kubernetes-operations-questions|Kubernetes Operations Question Bank]])
- AWS IAM - Principal→Role→Policy ([[iam-roles|IAM Roles]], [[iam-policies|IAM Policies]])
- All governed by [[iam-least-privilege|Principle of Least Privilege]]

The token mechanics underneath OIDC are the JWT and OAuth2 notes.

[[jwt|JWT]], [[oauth2|OAuth2]], [[session-based-auth|Session-Based Authentication]], [[authentication-vs-authorization|Authentication vs Authorization]]

---

## Common Misconceptions

Misconception 1: "OAuth2 is a login protocol."
Reality: OAuth2 authorizes resource access; an access token proves *permission*, not *identity*. "Login with Google" works because OIDC adds the identity layer (`id_token`). Treating a bare access token as proof of identity is a known vulnerability pattern.

Misconception 2: "ABAC is the advanced version of RBAC, so prefer it."
Reality: ABAC trades auditability for expressiveness. In regulated environments the killer question is "who has access to X, prove it" - a membership lookup under RBAC, a policy-evaluation exercise under ABAC. Default RBAC; add attributes only where relations demand them.

Misconception 3: "SSO handles our authorization."
Reality: SSO delivers authenticated identity and group claims. What those groups may *do* in each application is still each application's model to define, map, and audit - skipping the mapping layer ("anyone in the org can log in, therefore can use everything") is a real misconfiguration class.

---

## Interview Angle

Common question forms:
- "RBAC vs ABAC - and which would you use?"
- "How does OIDC relate to OAuth2? Where does SAML fit?"
- "Walk me through how your app's RBAC actually worked."

Answer frame:
Draw the four-box RBAC model, state the check-permissions-not-roles rule, then position ABAC as the relational escape hatch with the auditability cost - hybrid as the mature answer. OIDC = authentication layered on OAuth2 via `id_token` (signed JWT); SAML = same job, XML era, still everywhere. Anchor with the real stories: Orqa's Payroll Admin → view/edit timesheets mapping, and the DAG Builder's JWT + RBAC gate - concrete User→Role→Permission implementations you own end-to-end.

---

## Related Notes

- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[jwt|JWT]]
- [[oauth2|OAuth2]]
- [[session-based-auth|Session-Based Authentication]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
