---
title: 05 - Reverse Proxy
description: "A reverse proxy sits between clients and backend servers, handling SSL termination, header forwarding, and request routing — and understanding it is essential for secure Python deployments."
tags: [reverse-proxy, networking, ssl-termination, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Reverse Proxy

> A reverse proxy is the unseen intermediary in every production web deployment — getting its configuration right is the difference between a secure, observable system and one that silently forwards the wrong data or leaks information.

---

## Quick Reference

**Core idea:**
- A reverse proxy accepts requests on behalf of backend servers and forwards them
- SSL termination: the proxy decrypts HTTPS connections so backends receive plain HTTP
- Header forwarding: the proxy adds headers (X-Real-IP, X-Forwarded-For, X-Forwarded-Proto) so backends know the original request context
- A reverse proxy differs from a forward proxy: a forward proxy acts on behalf of clients; a reverse proxy acts on behalf of servers
- Benefits include: TLS management, buffering, access control, observability, and hiding backend topology

**Tricky points:**
- Without proper header forwarding, backends see all requests as coming from the proxy's IP
- `X-Forwarded-Proto` tells the backend whether the original request was HTTP or HTTPS — needed for redirect logic
- Trusting `X-Forwarded-For` blindly from any source is a security vulnerability — only trust it from known proxies
- A reverse proxy adds a network hop but removes TLS overhead from each application server
- The proxy can buffer slow responses, preventing backends from being held open by slow clients

---

## What It Is

Think of a large hotel. When a guest needs room service, they do not call the kitchen directly. They call the front desk. The front desk takes the request, relays it to the kitchen, and brings back the response. The guest never interacts with the kitchen staff. The kitchen never needs to know each guest's room preferences or payment details — the front desk handles all of that. The front desk is a reverse proxy.

A reverse proxy is a server that receives requests from clients and forwards them to one or more backend servers. From the client's perspective, it is talking directly to the service. From the backend's perspective, all requests appear to come from the proxy. The proxy returns the backend's response to the client. The client and backend never communicate directly.

This is the opposite of a forward proxy. A forward proxy (like a corporate web filter or Tor) acts on behalf of clients: you configure your browser to use a forward proxy, and it makes requests on your behalf, hiding your identity from the destination server. A reverse proxy acts on behalf of servers: you configure DNS to point to the proxy, and it receives requests on behalf of your backend fleet, hiding the backend topology from clients. These are very different roles even though both are "proxy servers."

In Python deployments, the reverse proxy sits in front of the Gunicorn or Uvicorn process pool. Its responsibilities are: terminating TLS (decrypting HTTPS and re-serving over plain HTTP to localhost), buffering request bodies (so slow clients do not hold application worker threads open), forwarding the original client IP and protocol in headers, serving static files directly (without involving Python), and routing requests to appropriate backends based on URL path or host headers. Every one of these responsibilities could be placed on the application server, but doing so would make the application server slower, more complex, and harder to scale.

SSL termination deserves special emphasis. A TLS handshake involves several round trips and significant CPU work (asymmetric cryptography). If every Gunicorn worker had to perform TLS handshakes, CPU usage on the application servers would be substantially higher, and the private key would need to be present on every server. By terminating TLS at the reverse proxy, you centralize certificate management, reduce application server CPU load, and can use hardware TLS acceleration that may be available at the proxy tier.

---

## How It Actually Works

When Nginx terminates a TLS connection, it decrypts the incoming TCP stream and re-proxies the request as plain HTTP to the selected backend. The backend receives a request that looks exactly like a normal HTTP request. But now the backend has lost some information: the original IP address (replaced by Nginx's own IP) and whether the request came over HTTPS or HTTP. The proxy restores this information by injecting headers.

`X-Real-IP: <client-ip>` carries the immediate client's IP address. `X-Forwarded-For: <client-ip>[, <proxy-ip>, ...]` is a comma-separated list of IPs the request has passed through, with the original client IP first. `X-Forwarded-Proto: https` tells the backend the original connection used HTTPS, which is important for applications that need to generate absolute URLs or enforce HTTPS redirects. `X-Forwarded-Host: example.com` carries the original `Host` header before any rewriting.

Django and FastAPI both provide mechanisms to trust these headers when configured to do so. In Django, the `SECURE_PROXY_SSL_HEADER` setting makes the framework trust `X-Forwarded-Proto`. In FastAPI with Uvicorn, you configure the application behind a trusted proxy. Without these settings, the application assumes all requests are HTTP and all clients have the proxy's IP — breaking security headers, redirect logic, and logging.

The slow client problem is an important performance concern that the reverse proxy solves. Without a proxy, a Gunicorn worker process handles the full lifecycle of a request: receiving bytes from the client, processing the request, and sending bytes back to the client. If the client is on a slow 3G connection, the worker is held for seconds while it trickles bytes over the slow connection. During this time, the worker cannot handle other requests. Nginx buffers the full response from the backend (which happens over the fast internal network) and then serves it to the slow client from its own buffers. The Python worker is freed immediately after sending the response to Nginx.

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;  # forward to local app server
        proxy_http_version 1.1;
        proxy_set_header Connection "";  # allow keepalive upstream

        # Restore client context lost during proxy
        proxy_set_header X-Real-IP          $remote_addr;
        proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto  $scheme;
        proxy_set_header Host               $http_host;

        # Buffering: Nginx buffers backend response before sending to client
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
}
```

---

## How It Connects

Nginx is the most common implementation of a reverse proxy for Python applications. Its specific configuration directives are where the abstract concepts above become concrete.

[[nginx-config|Nginx Configuration]]

A CDN is essentially a globally distributed reverse proxy network. The same SSL termination and header forwarding concepts apply at the CDN edge.

[[cdn|CDN]]

An API gateway adds capabilities on top of a reverse proxy: authentication, rate limiting, request transformation, and routing by API version. It is a reverse proxy with a richer feature set.

[[api-gateway|API Gateway]]

---

## Common Misconceptions

Misconception 1: "The reverse proxy handles my application security so I don't need to think about it in the app."
Reality: The reverse proxy handles network-level security: TLS, rate limiting at the connection level, and IP filtering. Application-level security — authentication, authorization, input validation, CSRF protection — must still be implemented in the application. The proxy is one layer of a defense-in-depth strategy, not a replacement for application security.

Misconception 2: "My app sees the real client IP when behind a proxy."
Reality: Without proper `X-Forwarded-For` forwarding and application configuration to read it, your application sees the proxy's IP for every request. This means IP-based rate limiting in the application, geographic blocking, and IP-based logging all break. Every production deployment behind a proxy must configure both the proxy (to forward the header) and the application (to read and trust it).

Misconception 3: "A reverse proxy and a load balancer are different things."
Reality: They are often the same component. Nginx configured with an `upstream` block is simultaneously a reverse proxy and a load balancer. AWS Application Load Balancer is both a reverse proxy (it terminates TLS and reads HTTP) and a load balancer (it distributes requests across targets). The terms describe different functions that often coexist in the same process.

---

## Why It Matters in Practice

The reverse proxy is the front door of your production system. A misconfigured front door means your application receives incorrect client information (breaking logging and rate limiting), handles TLS incorrectly (a security risk), or does not buffer slow clients (degrading performance under load). For Python developers, understanding reverse proxy behavior is essential for debugging production issues: "Why do all requests show as coming from 127.0.0.1?" (missing `X-Forwarded-For`), "Why does my HTTPS redirect loop?" (missing `X-Forwarded-Proto`), "Why is my Gunicorn pool exhausted?" (missing response buffering for slow clients).

For deployment, the standard Python production stack is: Let's Encrypt certificate → Nginx → Gunicorn/Uvicorn on a Unix socket. Understanding each component and the role of the reverse proxy in this chain makes it possible to debug and tune each layer independently.

---

## Interview Angle

Common question forms:
- "What is the difference between a forward proxy and a reverse proxy?"
- "What is SSL termination and why do it at the proxy layer?"
- "What headers does a reverse proxy need to forward, and why?"

Answer frame:
Distinguish forward proxy (acts for clients) from reverse proxy (acts for servers). List the responsibilities of a reverse proxy: TLS termination, buffering, static files, header forwarding, routing. Explain SSL termination benefits: centralized certificate management, reduced application server CPU load. Walk through the three key forwarded headers and what breaks without each. Mention the slow client buffering benefit.

---

## Related Notes

- [[nginx-config|Nginx Configuration]]
- [[load-balancing|Load Balancing]]
- [[cdn|CDN]]
- [[api-gateway|API Gateway]]
- [[http-basics|HTTP Basics]]
