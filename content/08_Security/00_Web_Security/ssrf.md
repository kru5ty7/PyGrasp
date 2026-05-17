---
title: 05 - Server-Side Request Forgery
description: "SSRF allows attackers to make the server issue HTTP requests to attacker-chosen destinations, exposing internal services, cloud metadata endpoints, and private network resources that are normally inaccessible from the internet."
tags: [ssrf, server-side-request-forgery, cloud-security, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Server-Side Request Forgery

> SSRF turns the server into a proxy for the attacker — and in cloud environments, that proxy has access to infrastructure secrets that can compromise the entire deployment.

---

## Quick Reference

**Core idea:**
- Occurs when an application fetches a URL or network resource that is fully or partially controlled by user input
- Attacker redirects fetches to internal services (`http://localhost:8080/admin`), cloud metadata (`http://169.254.169.254/latest/meta-data/`), or other private hosts
- The server makes the request with its own network identity — firewall rules that block external attackers do not block the server itself
- Defense: URL allowlisting (only permit known-good destinations), block private IP ranges, disable unnecessary HTTP-fetching features
- Cloud metadata service (IMDS) at `169.254.169.254` returns IAM credentials, which is why SSRF is critical in AWS/GCP/Azure deployments

**Tricky points:**
- DNS rebinding can bypass IP-based blocklists: the domain resolves to a safe IP at validation time but to an internal IP at fetch time
- URL redirects (301/302) allow bypassing hostname checks — an attacker controls `attacker.com` which redirects to `169.254.169.254`
- Blind SSRF: the attacker cannot see the response, but the server's behavior (timing, error messages) reveals whether the internal request succeeded
- Protocol schemes beyond HTTP can be exploited: `file://`, `gopher://`, `dict://` can interact with services differently than HTTP
- IMDSv2 on AWS is a partial mitigation — it requires a PUT request to obtain a session token before metadata can be accessed, which many simple SSRF payloads cannot handle

---

## What It Is

Imagine a company receptionist who, as part of their job, sends faxes to any number a caller dictates. The receptionist cannot leave the building — they are behind a secure locked door. But if an attacker calls and dictates an internal extension rather than an outside number, the receptionist faithfully dials it. The fax reaches the internal target, carrying whatever the attacker dictated. The locked door meant to protect the internal network did not help because the trusted person inside was manipulated into making the request.

That is Server-Side Request Forgery. The server is the receptionist — a trusted entity inside the network perimeter. When an application accepts a URL from user input and makes an HTTP request to it, the server is reaching out to whatever the user specified. If the user specifies an internal IP address, a loopback address, or a cloud provider's special link-local address, the server makes that request from its privileged network position. Security groups, network ACLs, and perimeter firewalls that block requests from the internet do not prevent the server from talking to itself or to other internal services on the same network.

SSRF entered the OWASP Top 10 in 2021 specifically because cloud deployments made it catastrophically dangerous. Every major cloud provider hosts an Instance Metadata Service (IMDS) at the well-known address `169.254.169.254`. This service responds to HTTP requests with information about the running instance, including temporary IAM credentials that grant access to cloud APIs. When an attacker exploits SSRF to fetch `http://169.254.169.254/latest/meta-data/iam/security-credentials/` from an EC2 instance, they receive the instance's AWS credentials — credentials that can be used to access S3 buckets, RDS databases, or other AWS services the instance was authorized to reach.

---

## How It Actually Works

A Python application that generates link previews might look like this:

```python
import httpx

@app.post("/preview")
async def generate_preview(url: str):
    response = await httpx.AsyncClient().get(url)
    return {"title": parse_title(response.text)}
```

An attacker submits `url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/my-role"`. The server makes the request, receives a JSON response containing `AccessKeyId`, `SecretAccessKey`, and `Token`, and the parse function returns whatever it can extract from the response. Even if the parse function fails, the attacker now controls what URL the server fetches and can see whether the request succeeds. With the returned credentials, the attacker authenticates to the AWS API and has whatever permissions the instance role granted.

The URL allowlist defense works by only permitting requests to a predefined list of domains:

```python
from urllib.parse import urlparse
import ipaddress

ALLOWED_HOSTS = {"example.com", "api.trusted-partner.com"}

def is_safe_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return False
    hostname = parsed.hostname
    if hostname in ALLOWED_HOSTS:
        return True
    # Block private/loopback addresses
    try:
        addr = ipaddress.ip_address(hostname)
        return not (addr.is_private or addr.is_loopback or addr.is_link_local)
    except ValueError:
        return False  # Not an IP — not in allowlist, so deny
```

This must also resolve the hostname and verify the resolved IP is not in a private range, because DNS rebinding can make a public-looking hostname resolve to an internal IP between the validation check and the actual request. The safest approach is to resolve the hostname once, validate the resulting IP, and then connect to that IP directly rather than re-resolving at connection time.

AWS IMDSv2 partially mitigates SSRF by requiring a session token obtained via a PUT request before metadata can be accessed. A simple GET to `169.254.169.254` returns nothing useful under IMDSv2. However, if the application code making the SSRF request follows redirects or can be induced to make a PUT request first, IMDSv2 can still be bypassed. It reduces the SSRF attack surface but does not eliminate it.

---

## How It Connects

SSRF is listed in the OWASP Top 10 as a standalone category for the first time in 2021, reflecting how cloud deployments elevated its criticality.

[[owasp-top-10|OWASP Top 10]]

Secrets returned from the cloud metadata service are IAM credentials — understanding how those secrets flow into application configuration is relevant context.

[[secrets-in-python|Handling Secrets in Python]]

---

## Common Misconceptions

Misconception 1: "I validate that the URL starts with https://, so I'm protected from SSRF."
Reality: Protocol validation alone does not prevent SSRF. `https://169.254.169.254/` is a valid HTTPS URL that still reaches the metadata service. An attacker-controlled domain can resolve to a private IP. The necessary checks are: allowlist of permitted hostnames, blocklist of private IP ranges, and resolution-time validation (check the IP the hostname resolves to, not just the hostname itself).

Misconception 2: "Our application doesn't fetch user-provided URLs."
Reality: SSRF can be introduced through less obvious paths: webhook configuration endpoints (user specifies where to send event notifications), import-from-URL features (user provides a URL to a CSV or document), image or avatar loading from user-provided URLs, PDF generators that render HTML (which can include `<img src="http://internal...">` tags), and integrations where the target URL is stored in a database field and fetched server-side on a schedule.

Misconception 3: "We use IMDSv2, so SSRF is not critical on AWS."
Reality: IMDSv2 raises the bar for SSRF exploitation of the metadata service, but does not make SSRF safe. An attacker with SSRF can still reach internal services, databases, and APIs on the same VPC or private network. The metadata service is one high-value target; the private network behind the firewall is the broader threat model.

---

## Why It Matters in Practice

The 2019 Capital One breach, which exposed over 100 million customer records, was executed via SSRF against a misconfigured web application firewall running on an AWS EC2 instance. The attacker exploited an SSRF vulnerability to retrieve AWS credentials from the metadata service, then used those credentials to access S3 buckets containing customer data. This was the real-world demonstration that motivated SSRF's inclusion in the OWASP Top 10 — a single SSRF vulnerability in a cloud-hosted application can compromise the entire cloud deployment's data and infrastructure.

For Python developers, the most common SSRF introduction patterns are: link preview or metadata fetching features, webhook endpoints where users configure callback URLs, integration features that pull data from external APIs at user-specified endpoints, and XML parsing (SSRF via XXE, where an XML parser fetches a remote DTD or entity). Any time a Python application makes an outbound HTTP request where the URL is derived from user input, the developer must ask whether the server's network position would give an attacker access to resources that should be internal-only.

---

## Interview Angle

Common question forms:
- "What is SSRF? Give an example."
- "Why is SSRF particularly dangerous in cloud environments?"
- "How would you defend against SSRF in a Python application?"

Answer frame:
A strong answer explains SSRF as the server making requests on behalf of the attacker, using its privileged network position. The cloud context answer explains the IMDS at `169.254.169.254` specifically — why that address is dangerous and what it returns. The defense answer covers URL allowlisting, private IP blocklisting, and resolution-time IP validation. Mentioning DNS rebinding as a bypass that naive hostname checks miss demonstrates depth.

---

## Related Notes

- [[owasp-top-10|OWASP Top 10]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[fastapi|FastAPI]]
- [[http-headers|HTTP Headers]]
