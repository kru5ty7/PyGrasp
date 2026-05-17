---
title: 04 - Nginx Configuration
description: "Nginx as a reverse proxy, load balancer, and rate limiter — the key directives and patterns that every Python backend engineer needs to know."
tags: [nginx, reverse-proxy, load-balancing, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Nginx Configuration

> Nginx is the Swiss Army knife of web infrastructure — and knowing how to configure it for your Python backend is the difference between a secure, scalable deployment and one that crashes or gets abused.

---

## Quick Reference

**Core idea:**
- Nginx uses an event-driven, non-blocking architecture — one master process, multiple worker processes
- `worker_processes` should match CPU core count; `worker_connections` sets max connections per worker
- `upstream` blocks define backend server pools; `proxy_pass` forwards requests to them
- `limit_req_zone` and `limit_req` implement rate limiting per IP or key
- `proxy_set_header` forwards the original client IP to backends that would otherwise see only Nginx's IP

**Tricky points:**
- `worker_processes auto` lets Nginx detect CPU count; the default of 1 is not appropriate for production
- Without `proxy_set_header X-Forwarded-For`, backends see Nginx's IP as the client — breaks logging and rate limiting
- `keepalive` in an upstream block maintains persistent connections to backends — important for performance
- `proxy_read_timeout` defaults to 60s — if your backend can be slow, this needs adjustment
- `try_files` and `location` block ordering use prefix and regex matching with specific precedence rules

---

## What It Is

Imagine a building's lobby security desk. Everyone who enters must check in at the desk. The security guard checks IDs (authentication), decides which floor each visitor can access (routing), keeps a log of who entered (access log), limits how many visitors can come in per hour (rate limiting), and forwards visitors to the right elevator (proxying). The security desk does not do the actual work happening upstairs — it manages access and routing. Nginx plays exactly this role for your web application.

Nginx (pronounced "engine-x") is a high-performance web server and reverse proxy written by Igor Sysoev and released in 2004. It was designed from the ground up to handle tens of thousands of concurrent connections efficiently, using an event-driven architecture instead of the process-per-connection model used by Apache. This architecture makes Nginx extremely efficient for I/O-bound work like serving static files, proxying requests, and terminating TLS.

For a Python backend engineer, Nginx typically sits in front of the application server — a Gunicorn process pool, Uvicorn workers, or a similar WSGI/ASGI server. Nginx handles the tasks the application server should not: TLS termination, static file serving, request buffering, connection limiting, and load balancing across multiple application instances. The application server focuses on executing Python code and returning responses. This separation makes the overall system more secure (the application server is not directly exposed to the internet), more efficient (Nginx handles slow clients by buffering), and more manageable (TLS certificates are managed in one place).

The configuration file structure in Nginx is hierarchical. The top-level context contains global directives. Inside it, `http {}` contains web-related configuration. Inside `http`, you define `server {}` blocks — each describing a virtual host that responds to a particular domain or IP. Inside `server`, you define `location {}` blocks that match URL patterns and determine how requests to those patterns are handled. The `upstream {}` blocks, which define backend server pools, live at the `http` context level.

---

## How It Actually Works

Nginx spawns one master process (which reads configuration and manages workers) and multiple worker processes (which handle actual connections). The number of worker processes should match the number of available CPU cores — `worker_processes auto` handles this automatically. Each worker runs a single-threaded event loop. The `worker_connections` directive limits how many simultaneous connections a single worker can handle. Total maximum connections is roughly `worker_processes × worker_connections`.

The upstream block defines a named pool of backend servers. When a request matches a `proxy_pass` directive pointing to an upstream, Nginx selects a server from the pool using the configured algorithm (round robin by default), forwards the request, and returns the response. The `keepalive` directive in the upstream block maintains a pool of persistent connections to backends, avoiding the TCP handshake overhead for every request. For high-throughput Python APIs, setting `keepalive 32` or higher is an important optimization.

Rate limiting in Nginx uses a token bucket algorithm implemented via `limit_req_zone` and `limit_req`. The zone directive defines a shared memory zone that tracks request counts by a given key (typically `$binary_remote_addr` for per-IP rate limiting), its size in memory, and the allowed request rate. The `limit_req` directive applies the limit within a specific location block. The `burst` parameter allows temporary spikes above the rate — requests above the base rate are queued up to the burst limit, then rejected beyond that.

```nginx
# /etc/nginx/nginx.conf — production configuration for a Python API

worker_processes auto;  # match CPU count
events {
    worker_connections 1024;  # per worker; total = workers × 1024
}

http {
    # Rate limiting: track by client IP, allow 10 req/s, 1MB shared memory zone
    limit_req_zone $binary_remote_addr zone=api_limit:1m rate=10r/s;

    # Backend pool — three Uvicorn workers
    upstream api_workers {
        least_conn;  # send to worker with fewest active connections
        server 127.0.0.1:8001;
        server 127.0.0.1:8002;
        server 127.0.0.1:8003;
        keepalive 32;  # maintain 32 persistent connections per worker
    }

    server {
        listen 443 ssl http2;
        server_name api.example.com;

        ssl_certificate     /etc/ssl/certs/example.com.crt;
        ssl_certificate_key /etc/ssl/private/example.com.key;
        ssl_protocols       TLSv1.2 TLSv1.3;

        # API routes — proxied to Python backend
        location /api/ {
            limit_req zone=api_limit burst=20 nodelay;  # allow burst of 20

            proxy_pass http://api_workers;
            proxy_http_version 1.1;
            proxy_set_header Connection "";  # required for keepalive
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_read_timeout 30s;  # kill connection if backend takes > 30s
            proxy_connect_timeout 5s;
        }

        # Static files served directly by Nginx — no Python involved
        location /static/ {
            alias /var/www/static/;
            expires 7d;  # tell browsers to cache for 7 days
        }
    }
}
```

The `proxy_set_header X-Forwarded-For` directive is critical. Without it, the backend application sees all requests as coming from `127.0.0.1` (Nginx's address). This breaks any application logic that uses the client IP for rate limiting, geolocation, or security decisions. The `X-Forwarded-For` header carries the original client IP so the application can use it. The application must be configured to trust this header only when the request comes from a known proxy (to prevent header spoofing from untrusted clients).

---

## How It Connects

Nginx is the most common implementation of a reverse proxy in Python deployments. The concepts of SSL offloading, header forwarding, and buffering are shared across all reverse proxies.

[[reverse-proxy|Reverse Proxy]]

Nginx's upstream block is a load balancer. The algorithm directives (`least_conn`, `ip_hash`, round-robin default) correspond directly to the load balancing algorithms discussed separately.

[[load-balancing-algorithms|Load Balancing Algorithms]]

API gateways extend what Nginx does — adding authentication, request transformation, and observability on top of basic proxying.

[[api-gateway|API Gateway]]

---

## Common Misconceptions

Misconception 1: "Nginx handles Python execution — it runs my app."
Reality: Nginx is a proxy server, not an application server. It forwards HTTP requests to your Python application server (Gunicorn, Uvicorn, uWSGI) and returns their responses. The Python code runs in the application server, completely separate from Nginx. This separation is the point.

Misconception 2: "The default Nginx configuration is fine for production."
Reality: The default configuration has `worker_processes 1` and `worker_connections 1024`, which is appropriate for testing. Production deployments need `worker_processes auto`, tuned `worker_connections`, SSL configuration, rate limiting, proper timeout values, and security headers. The defaults are conservative starters, not production configurations.

Misconception 3: "Setting a high `worker_connections` value is always better."
Reality: Each connection consumes memory (approximately 1 KB per connection for Nginx's internal state). Setting `worker_connections 10000` with 8 workers allocates roughly 80 MB just for connection metadata. More importantly, if your backend servers cannot handle that many concurrent requests, you have a queue buildup problem that a higher connection limit only delays. The limit should match your backend capacity, not your theoretical maximum.

---

## Why It Matters in Practice

Nginx configuration is what stands between your Python application and the public internet. Misconfiguration leads to real security and availability problems: missing rate limiting allows DDoS or credential stuffing; missing `X-Forwarded-For` breaks application-level rate limiting and logging; wrong timeouts cause request queues to build up silently; missing TLS configuration exposes data in transit. Understanding Nginx configuration well enough to review and write it is a practical requirement for deploying Python web applications.

The performance impact is also real. A properly configured Nginx with persistent upstream connections, gzip compression enabled, and static file serving handled at the proxy layer can reduce backend load by 40-60% for typical web applications. The Python application server only handles dynamic requests.

---

## Interview Angle

Common question forms:
- "How would you deploy a FastAPI application in production?"
- "How does Nginx improve the security of a Python web service?"
- "What is SSL termination and why does it happen at the proxy layer?"

Answer frame:
Describe the two-tier setup: Nginx handles TLS, static files, rate limiting, and proxying; the Python application server handles business logic. Explain SSL termination — the proxy holds the certificate, backends use plain HTTP within the internal network. Explain the `X-Forwarded-For` header and why backends need it. Describe rate limiting configuration briefly. Tie each configuration decision to a specific security or performance goal.

---

## Related Notes

- [[reverse-proxy|Reverse Proxy]]
- [[load-balancing|Load Balancing]]
- [[load-balancing-algorithms|Load Balancing Algorithms]]
- [[api-gateway|API Gateway]]
- [[fastapi|FastAPI]]
