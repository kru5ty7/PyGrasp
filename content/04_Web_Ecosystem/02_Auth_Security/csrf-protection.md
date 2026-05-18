---
title: 07 - CSRF Protection
description: "Cross-Site Request Forgery (CSRF) exploits the fact that browsers automatically send cookies on cross-origin requests  -  CSRF tokens and SameSite cookie attributes prevent malicious sites from forging authenticated actions."
tags: [csrf, security, cookies, tokens, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# CSRF Protection

> CSRF is the attack where a malicious website tricks your browser into making a request to another site using your cookies  -  CSRF tokens defeat this by requiring knowledge the attacker cannot read.

---

## Quick Reference

**Core idea:**
- CSRF only affects cookie-based authentication  -  the browser sends cookies automatically, enabling forged requests
- CSRF token: server embeds a unique secret in every form; on POST the server validates it  -  an attacker cannot read the token from a different origin
- Double-submit cookie: same token in a cookie and in a form field/header; server checks they match  -  no server-side state needed
- `SameSite=Strict` cookie attribute: browser does not send the cookie on any cross-origin request  -  eliminates CSRF entirely for that cookie
- JWT sent in `Authorization: Bearer` header is immune to CSRF  -  headers are not sent automatically by browsers

**Tricky points:**
- `SameSite=Lax` (browser default) prevents cross-origin POSTs but allows cross-origin GETs  -  state-changing GET endpoints are still vulnerable
- The double-submit cookie pattern requires HTTPS  -  an attacker on the same network can read cookies over plain HTTP and forge the token
- SPAs (React, Vue) typically store CSRF tokens in a meta tag or a dedicated endpoint response, then send them in `X-CSRF-Token` header on every state-changing request
- `SameSite=Strict` breaks OAuth flows and cross-domain login redirects because the cookie is not sent even on legitimate navigations  -  `Lax` is usually the right default
- CSRF attacks require the user to be authenticated (have a valid cookie) and do not expose user data  -  they trigger unauthorized actions, not data theft

---

## What It Is

Consider a user who is logged into their bank's website. Their browser holds a session cookie for `bank.com`. They then visit `evil.com`, which contains a hidden form that points to `bank.com/transfer` with pre-filled fields: recipient `attacker`, amount `1000`. When the page loads, JavaScript automatically submits the form. The browser dutifully sends the request to `bank.com`, and because the request goes to `bank.com`, the browser attaches the session cookie. The bank's server sees a valid authenticated request from the user and processes the transfer. The user never clicked anything intentionally.

This is Cross-Site Request Forgery. The attack exploits a fundamental browser behavior: cookies are scoped by domain, not by which site initiated the request. Any page can trigger a request to any domain, and the browser will include all matching cookies. The bank's server cannot tell whether the request came from the bank's own form or from an attacker's hidden form  -  both look identical from the server's perspective.

The defense is to require proof that the request originated from the legitimate site. A CSRF token is a secret value that the server embeds in every form it renders. When the form is submitted, the server checks that the submitted token matches the one it issued. An attacker on `evil.com` cannot read the legitimate form from `bank.com` due to the Same-Origin Policy  -  they cannot retrieve the CSRF token, so they cannot forge a valid request. The token does not need to be long-lived or stored permanently; it only needs to be unique per session (or per form, for higher security) and unguessable.

---

## How It Actually Works

Traditional server-rendered applications embed the CSRF token in a hidden form field. Frameworks handle this automatically: Django's `{% csrf_token %}` template tag, Flask-WTF's `{{ form.hidden_tag() }}`, and so on.

```html
<!-- Django template -->
<form method="post" action="/transfer">
    {% csrf_token %}
    <input name="recipient" value="alice" />
    <input name="amount" value="100" />
    <button type="submit">Transfer</button>
</form>
```

For Single-Page Applications that use a JavaScript frontend with a separate API backend, the synchronizer token pattern uses custom headers. The server issues the CSRF token (often via a cookie or an API endpoint), and the JavaScript sends it back in a custom header on every mutating request.

```python
# FastAPI  -  manual CSRF token validation (no built-in CSRF middleware)
from fastapi import Request, HTTPException, Cookie
import secrets

# Issue token (e.g., on session creation)
csrf_token = secrets.token_urlsafe(32)

# Validate on state-changing endpoints
async def validate_csrf(request: Request, csrf_cookie: str = Cookie(None)):
    csrf_header = request.headers.get("X-CSRF-Token")
    if not csrf_cookie or not csrf_header or not secrets.compare_digest(csrf_cookie, csrf_header):
        raise HTTPException(status_code=403, detail="CSRF validation failed")
```

The `SameSite` cookie attribute is the modern, simpler defense. Setting `SameSite=Strict` instructs the browser to never include the cookie on cross-origin requests.

```python
response.set_cookie(
    "session_id",
    value=session_id,
    samesite="lax",    # blocks cross-origin POST, allows cross-origin GET
    httponly=True,
    secure=True,
)
```

For APIs that use JWT in the `Authorization` header rather than cookies, CSRF protection is not required. Browsers do not automatically set custom headers  -  only JavaScript running on the page can set `Authorization: Bearer ...`. An attacker's page on `evil.com` cannot use JavaScript to read another site's data (blocked by Same-Origin Policy), so it cannot construct the header. CSRF is only a concern when authentication information is in a cookie.

---

## How It Connects

CSRF attacks specifically target cookie-based sessions  -  understanding session-based authentication is a prerequisite for understanding why CSRF exists.

[[session-based-auth|Session-Based Authentication]]

JWT in the Authorization header is immune to CSRF  -  the token mechanism changes the attack surface entirely.

[[jwt|JSON Web Tokens (JWT)]]

---

## Common Misconceptions

Misconception 1: "HTTPS protects against CSRF."
Reality: CSRF does not require the attacker to read network traffic  -  it exploits the browser's automatic cookie sending behavior. A request from `evil.com` to `bank.com/transfer` over HTTPS still includes the session cookie and still reaches the bank server with valid authentication. HTTPS does not prevent this; a CSRF token or `SameSite` cookie attribute does.

Misconception 2: "Checking the `Referer` header is a reliable CSRF defense."
Reality: The `Referer` header can be missing (blocked by privacy settings, browser extensions, or corporate proxies) and was historically falsifiable. CSRF token validation is the correct primary defense. `Referer` checking may be used as an additional signal but not as the sole protection.

---

## Why It Matters in Practice

CSRF vulnerabilities have caused real financial losses and data breaches in production applications. Django and Flask include CSRF protection by default  -  and developers commonly disable it without understanding the implications (for example, to make an API "easier to test"). Knowing what CSRF is, why it exists, and what each protection mechanism defends against prevents the mistake of removing protection you do not understand.

---

## Interview Angle

Common question forms:
- "What is a CSRF attack and how do you prevent it?"
- "Is a REST API that uses JWT tokens vulnerable to CSRF?"
- "What does `SameSite=Strict` do?"

Answer frame:
CSRF exploits browser automatic cookie sending  -  an attacker page can trigger requests to other sites and the browser includes the session cookie. Defense: CSRF token embedded in forms, validated on POST  -  attacker cannot read the token due to Same-Origin Policy. Modern alternative: `SameSite=Lax/Strict` cookie attribute. JWT APIs using `Authorization` headers are not vulnerable  -  browsers do not auto-send custom headers.

---

## Related Notes

- [[session-based-auth|Session-Based Authentication]]
- [[jwt|JSON Web Tokens (JWT)]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[fastapi-security|FastAPI Security]]
