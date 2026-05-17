---
title: 04 - Cross-Site Request Forgery
description: "CSRF tricks a victim's authenticated browser into making state-changing requests to a trusted application from an attacker-controlled page, exploiting the browser's automatic cookie inclusion in cross-origin requests."
tags: [csrf, cross-site-request-forgery, cookies, web-security, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Cross-Site Request Forgery

> CSRF is not about stealing data — it is about making the victim's own authenticated browser perform actions the victim did not choose.

---

## Quick Reference

**Core idea:**
- Browsers automatically include cookies in requests to any origin that set them, regardless of which page initiates the request
- An attacker page on `evil.com` can trigger a form POST to `bank.com`, and the victim's browser will include the `bank.com` session cookie
- CSRF only affects state-changing operations (POST, PUT, DELETE, PATCH) — GET requests should be read-only
- The CSRF token pattern defends by requiring a secret value that the attacker's page cannot read (due to Same-Origin Policy)
- SameSite cookie attribute (`Strict` or `Lax`) is the modern defense — it prevents cookies from being sent on cross-site requests

**Tricky points:**
- SameSite=Lax (now the browser default) allows cookies on top-level navigation GET requests but blocks cross-origin POST — this stops most CSRF but still allows some attacks on GET endpoints that perform state changes
- CSRF does not require JavaScript on the attacker's page — an HTML `<img>` tag or `<form>` with `action=` is sufficient
- CSRF tokens must be tied to the user's session, not just random — a valid token from one session should not satisfy a check for another session
- APIs that use JSON request bodies are naturally somewhat resistant to CSRF because cross-origin forms cannot set `Content-Type: application/json`, but this is not a reliable defense
- Bearer token authentication (JWT in Authorization header) is immune to CSRF because browsers do not auto-include Authorization headers on cross-origin requests

---

## What It Is

Imagine you are logged into your bank's website. Your browser holds a session cookie that proves your identity. Now imagine you visit a different website in another tab — a page the attacker controls. That page contains an invisible HTML form that, the moment your browser loads the page, automatically submits itself to your bank. Your browser sends the form data to the bank, and because you are authenticated, the browser includes your session cookie. The bank receives what looks like a legitimate request from you: it has your cookie, it has valid form fields, it looks like you. But you never chose to make that request.

That is Cross-Site Request Forgery. The critical mechanism is that browsers include cookies in requests based on the destination, not based on the origin of the page making the request. This was a deliberate browser design decision that enables normal web functionality — when you click a link to another site, your browser correctly includes that site's cookies. CSRF weaponizes this behavior by initiating requests to the victim site from a page the attacker controls.

CSRF is distinct from XSS in a fundamental way: XSS injects attacker code into the trusted site so it executes in the victim's browser under the trusted site's origin; CSRF makes the victim's browser communicate with the trusted site from an untrusted origin, relying on the browser's automatic cookie inclusion to authenticate the request. You could summarize the difference as: XSS exploits the site's trust in its own code, CSRF exploits the browser's trust in the user's cookies.

---

## How It Actually Works

A minimal CSRF attack against a Python web application requires nothing more than an HTML page. Suppose `bank.com` has a transfer endpoint: `POST /transfer` with form fields `to_account` and `amount`. The attacker's page at `evil.com` contains:

```html
<form id="csrf" action="https://bank.com/transfer" method="POST">
  <input type="hidden" name="to_account" value="attacker-account-number">
  <input type="hidden" name="amount" value="5000">
</form>
<script>document.getElementById("csrf").submit();</script>
```

When the victim loads `evil.com`, the JavaScript submits the form instantly. The browser sends a POST request to `bank.com` with the victim's session cookie attached. If `bank.com` does not verify that the request originated from its own pages, the transfer executes.

The CSRF token defense interrupts this chain by requiring the POST to include a secret value that the attacker's page cannot access. The server generates a random token, embeds it in every HTML form it serves (in a hidden field), and stores the expected value in the user's session. When the form is submitted, the server compares the submitted token against the session's expected token. The attacker's page on `evil.com` cannot read the CSRF token from `bank.com` because the Same-Origin Policy prevents cross-origin JavaScript from reading responses. The attacker can trigger a request to `bank.com` but cannot read what `bank.com` sends back — so they can never learn the token to include it in the forged request.

In FastAPI or any modern Python API using JSON and Bearer token authentication, CSRF is not typically a concern because browsers do not auto-include Authorization headers on cross-origin requests. An attacker page cannot craft a request that includes `Authorization: Bearer <jwt>` — that token lives in JavaScript memory or localStorage, not in a cookie, and the attacker's page cannot read it due to Same-Origin Policy. But any endpoint that authenticates via a session cookie remains CSRF-vulnerable if the SameSite attribute is not set.

The modern defense in Python applications is `Set-Cookie: session=...; SameSite=Lax; HttpOnly; Secure`. `SameSite=Lax` tells the browser: send this cookie on top-level navigation (clicking a link to my site) but not on cross-origin subresource requests or form POSTs. `SameSite=Strict` is more restrictive — the cookie is never sent on any cross-origin request, including top-level navigation. Most applications use `Lax` because `Strict` causes the session cookie to be excluded when users arrive via links from external sites, forcing them to log in again even if they have an active session.

---

## How It Connects

CSRF exploits session cookies specifically — understanding what session cookies are and how they work makes the attack and defense clearer.

[[session-based-auth|Session-Based Authentication]]

JWT authentication in the Authorization header is immune to CSRF — this is one of the practical advantages of token-based auth that is worth understanding alongside the tradeoffs.

[[jwt|JWT]]

FastAPI middleware is the correct place to implement CSRF token validation as a cross-cutting concern.

[[fastapi-middleware|Middleware in FastAPI]]

---

## Common Misconceptions

Misconception 1: "My API uses JSON, so it's not vulnerable to CSRF."
Reality: While HTML forms cannot set `Content-Type: application/json`, this is not a reliable CSRF defense because the browser's fetch API can send JSON cross-origin (with the appropriate CORS headers on the receiving server). If the server has permissive CORS (`Access-Control-Allow-Origin: *`) and uses session cookies for authentication, it is vulnerable to CSRF via JavaScript on the attacker's page. The reliable defenses are the CSRF token pattern and SameSite cookies.

Misconception 2: "Checking the Referer or Origin header prevents CSRF."
Reality: Referer and Origin header checking is a valid defense layer but cannot be relied upon exclusively. Some browsers and privacy tools strip the Referer header. Certain proxy configurations modify or remove headers. The Origin header is more reliable but also not universally present. These checks are appropriate as additional defense depth but not as primary controls.

Misconception 3: "CSRF can steal data."
Reality: Standard CSRF cannot read response data because the Same-Origin Policy blocks the attacker's page from reading cross-origin responses. CSRF can only cause the victim to make a request — it can trigger actions (transfer money, change a password, post content) but cannot return data to the attacker. The attack that reads data is XSS. This distinction matters for understanding which operations require CSRF protection: only state-changing endpoints, not read-only ones.

---

## Why It Matters in Practice

CSRF is still being exploited against applications that authenticate via cookies and do not set the SameSite attribute. Modern browsers defaulted SameSite to Lax starting around 2020, which significantly reduced CSRF exposure in practice — but this only applies to cookies set without an explicit SameSite attribute. Applications that explicitly set `SameSite=None` (required for legitimate cross-site embedded scenarios) lose this default protection and require CSRF tokens.

Python developers building server-rendered applications with session cookies (Django, Flask with Flask-Login, FastAPI with session cookies) must verify their framework's CSRF protection is enabled and correctly scoped. Django's CSRF middleware is on by default but can be disabled per-view with `@csrf_exempt` — a decorator that should never be applied to state-changing endpoints without understanding the risk. The risk is concrete: an attacker who can get authenticated users to visit a malicious page can perform any action those users are authorized to perform.

---

## Interview Angle

Common question forms:
- "What is CSRF and how does an attack work?"
- "What is the CSRF token pattern?"
- "What is the SameSite cookie attribute and how does it help?"
- "Is a JWT-authenticated API vulnerable to CSRF?"

Answer frame:
A strong answer explains CSRF as the browser's automatic cookie inclusion being exploited — the attacker does not need to steal the cookie, they just need the victim's browser to make a request. It explains the CSRF token defense concisely: a secret embedded in forms that the attacker cannot read due to Same-Origin Policy. It correctly answers the JWT question: no, because the JWT lives in memory/localStorage and browsers do not auto-include Authorization headers on cross-origin requests.

---

## Related Notes

- [[owasp-top-10|OWASP Top 10]]
- [[xss|Cross-Site Scripting (XSS)]]
- [[session-based-auth|Session-Based Authentication]]
- [[jwt|JWT]]
- [[security-headers|Security Headers]]
