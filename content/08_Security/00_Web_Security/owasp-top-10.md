---
title: 01 - OWASP Top 10
description: "The ten most critical web application security risks maintained by the Open Web Application Security Project, updated in 2021 to reflect modern attack patterns against APIs and cloud-hosted Python applications."
tags: [owasp, web-security, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# OWASP Top 10

> The authoritative list of the ten most dangerous web application vulnerabilities — every Python web developer should be able to name all ten and recognize them in code.

---

## Quick Reference

**Core idea:**
- OWASP (Open Web Application Security Project) publishes the Top 10 as a risk-awareness document, not a compliance checklist
- 2021 edition introduced three new categories: Insecure Design, Software and Data Integrity Failures, SSRF
- Broken Access Control climbed to #1 in 2021 — authorization is harder to get right than authentication
- Each category maps to real CVEs, breach reports, and measurable exploit techniques
- The list drives security training, penetration testing scope, and WAF rule sets industry-wide

**Tricky points:**
- "Injection" in 2021 was broadened beyond SQL to include command injection, LDAP injection, XPath injection, and template injection — it's a class of vulnerability, not one specific attack
- Cryptographic Failures (#2) was previously called "Sensitive Data Exposure" — the rename clarifies that the root cause is bad crypto, not just data leakage
- Insecure Design (#4) is unique — it cannot be fixed by patching; it requires architectural rethinking
- Security Misconfiguration (#5) includes default credentials, unnecessary features enabled, and verbose error messages in production
- Vulnerable and Outdated Components (#6) is almost entirely addressed by automated dependency scanning, yet it remains in the top 10

---

## What It Is

Imagine a city where the fire department publishes an annual report: "These are the ten most common ways buildings catch fire — and they are preventable." The OWASP Top 10 is that report for web applications. It is compiled from data contributed by security firms, bug bounty programs, and penetration testers who collectively analyzed hundreds of thousands of applications. The goal is not to enumerate every possible attack but to force developers to confront the categories of failure that cause the most real-world breaches.

The list is not a specification. Meeting it does not mean an application is secure, and failing one category does not mean the application is insecure in every other way. What the list does is give development teams a shared vocabulary and a prioritized starting point. When a security review says "this endpoint has an A01 issue," everyone in the room knows that means access control was not checked correctly, not that some obscure edge case was exploited.

The 2021 edition reflects a shift in how applications are built. Cloud-native deployments, microservices, and API-first architectures introduced new failure modes that were not prominent when earlier editions were written. Server-Side Request Forgery (SSRF) made the list for the first time in 2021 precisely because cloud metadata services created a high-value target that did not exist a decade ago. Understanding the list means understanding why these categories rose to prominence, not just what they are called.

---

## How It Actually Works

Each OWASP category is a pattern of failure. A01 Broken Access Control covers every situation where a user can act beyond their intended permissions — a normal user accessing admin endpoints by changing a URL parameter, a user reading another user's data by iterating a numeric ID, or a missing authorization check on a DELETE endpoint because the developer assumed only the UI would call it. In Python FastAPI apps this appears as route handlers that authenticate (verify identity) but do not authorize (check permission), particularly in auto-generated CRUD routes where access control is easy to forget.

A03 Injection covers any situation where attacker-controlled data is interpreted as code or a query directive rather than as literal data. In Python this means raw SQL built with string formatting (`"SELECT * FROM users WHERE id = " + user_id`), shell commands built with `subprocess.run("ls " + path, shell=True)`, LDAP queries, XPath expressions, or Jinja2 templates rendered with user input (`Template(user_input).render()`). The common thread is the interpreter receiving data it then parses as syntax. A03 also includes prompt injection in LLM-integrated applications, which is an emerging concern for Python developers building AI features.

A08 Software and Data Integrity Failures is the category that covers insecure deserialization, including Python's `pickle` module. When a Python application accepts a serialized object from an untrusted source and calls `pickle.loads()` on it, the attacker controls what code runs during deserialization. A09 Security Logging and Monitoring Failures is a category that developers rarely prioritize but security incident responders consider critical — when a breach occurs, the absence of logs means the organization cannot determine what was accessed, when, or by whom. Python applications that catch and silently swallow exceptions, log to stdout with no persistence, or omit request identifiers make incident response effectively impossible.

---

## How It Connects

The OWASP Top 10 is the organizing framework for everything else in this layer. Each subsequent note in this folder addresses one category in depth. Broken Access Control connects directly to how sessions and tokens are verified.

[[authentication-vs-authorization|Authentication vs Authorization]]

SQL Injection is the canonical example of A03, and understanding it mechanically is essential before the category makes complete sense.

[[sql-injection|SQL Injection]]

Insecure Deserialization (A08) has a Python-specific implementation that every developer using pickle should understand.

[[insecure-deserialization|Insecure Deserialization]]

---

## Common Misconceptions

Misconception 1: "If I use a framework like FastAPI or Django, the framework handles security for me."
Reality: Frameworks handle specific, well-defined concerns — CSRF protection in Django, request parsing in FastAPI — but authorization logic, business rule validation, and secret management are always the developer's responsibility. The framework cannot know which users are allowed to access which records.

Misconception 2: "Our application is not a high-value target, so attackers will not bother with it."
Reality: The vast majority of web application attacks are automated. Scanners probe millions of URLs for common vulnerabilities without regard for the application's business domain or size. A misconfigured application serving ten users is as likely to be found and exploited as one serving a million.

Misconception 3: "We passed a penetration test last year, so we are covered."
Reality: A penetration test is a point-in-time snapshot against a specific code version. New vulnerabilities are introduced with every deployment, every new dependency, and every configuration change. The OWASP Top 10 categories are addressed through continuous process — code review, dependency scanning, automated testing — not one-time audits.

---

## Why It Matters in Practice

Broken Access Control, the #1 category, is responsible for a disproportionate share of actual data breaches. The pattern is almost always the same: a developer builds an endpoint that requires authentication but assumes that any authenticated user is allowed to do anything. An attacker logs in with a valid account, then substitutes another user's ID in the request. The application returns data it should not. This is called an Insecure Direct Object Reference (IDOR) and it appears in bug bounty reports daily across every industry.

Injection vulnerabilities, despite being well understood for decades, continue to appear in production Python code because the failure is natural to the way developers write code. String interpolation feels simpler than parameterized queries. `subprocess.run(f"convert {filename}", shell=True)` is shorter to write than a properly constructed argument list. The consequence is that a single field without sanitization can give an attacker complete read access to a database or arbitrary code execution on the server. No amount of infrastructure hardening compensates for injection vulnerabilities in application code.

---

## Interview Angle

Common question forms:
- "Name the OWASP Top 10 categories"
- "What is the difference between A01 and A07 in the 2021 list?"
- "Which OWASP category covers SQL injection? Which covers insecure deserialization?"

Answer frame:
A strong answer names all ten categories, explains why Broken Access Control is #1 (authorization is application-specific and cannot be automated away), distinguishes Insecure Design from Security Misconfiguration (design problems require rearchitecting; misconfigs can be fixed by changing settings), and knows that A02 Cryptographic Failures renamed from "Sensitive Data Exposure" to focus on root cause rather than symptom. Mentioning that A03 Injection now includes template injection and prompt injection shows awareness of modern attack surfaces.

---

## Related Notes

- [[sql-injection|SQL Injection]]
- [[xss|Cross-Site Scripting (XSS)]]
- [[csrf|Cross-Site Request Forgery]]
- [[ssrf|Server-Side Request Forgery]]
- [[insecure-deserialization|Insecure Deserialization]]
- [[security-headers|Security Headers]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
