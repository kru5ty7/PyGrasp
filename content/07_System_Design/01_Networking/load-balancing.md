---
title: 02 - Load Balancing
description: "Load balancers distribute incoming traffic across multiple servers  -  understanding L4 vs L7, stickiness, and health checks determines how well this distribution works."
tags: [load-balancing, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Load Balancing

> A load balancer is the traffic cop of your infrastructure  -  and how it routes, what it checks, and what it knows about your application determines whether your fleet of servers acts as one or fails as one.

---

## Quick Reference

**Core idea:**
- A load balancer distributes incoming requests across a pool of backend servers
- L4 (transport layer) load balancing routes based on IP/TCP without inspecting the request content
- L7 (application layer) load balancing can route based on HTTP headers, URL paths, cookies, and body content
- Health checks detect unhealthy servers and remove them from the pool automatically
- Session stickiness (affinity) routes a specific client's requests always to the same backend server

**Tricky points:**
- L7 load balancing is smarter but adds latency and requires SSL termination
- Sticky sessions undermine the goal of distributing load  -  use only when the application requires it
- Health checks that are too aggressive cause false positives; too lenient checks leave dead servers in rotation
- Load balancers themselves can become a single point of failure  -  they need redundancy too
- "Active-active" vs "active-passive" describes the LB's own high-availability setup, not the backends

---

## What It Is

Imagine a popular restaurant with ten tables inside but only one hostess at the door. Every customer who arrives asks the hostess for a table. A bad hostess seats everyone at the first available table until it is completely overwhelmed and then moves to the next. A good hostess looks at all ten tables, knows which are full, which have just been seated, which are finishing their meal, and routes each customer to the table that can serve them fastest. That hostess is your load balancer.

In distributed systems, a load balancer sits between the outside world (clients, other services) and your pool of backend servers. Every incoming request arrives at the load balancer, which decides which server should handle it. This serves two purposes. First, it distributes load so no single server is overwhelmed while others sit idle. Second, it provides a single, stable address (IP or hostname) that clients connect to, hiding the complexity of the backend fleet. Servers can be added, removed, or replaced without clients ever knowing.

The distinction between L4 and L7 load balancing corresponds to which layer of the network stack the load balancer inspects. An L4 load balancer operates at the transport layer  -  it sees IP addresses and TCP ports but not the content of the packets. It makes routing decisions based purely on network-level information. This is fast and simple. AWS Network Load Balancer is an L4 balancer. An L7 load balancer operates at the application layer  -  it terminates the TCP/TLS connection, reads the HTTP request, and can inspect headers, URL paths, query strings, and cookies. This allows routing a request to `/api/v2/images` to a different backend cluster than `/api/v2/users`. AWS Application Load Balancer and Nginx are L7 balancers.

Health checks are what make a load balancer genuinely useful for availability rather than just distribution. A load balancer periodically sends a probe to each backend server  -  typically an HTTP request to a health check endpoint like `/health` or `/ping`. If the server returns a success response (2xx status code) within a timeout, it is considered healthy. If it fails consecutively a configured number of times, the load balancer removes it from the pool and stops sending traffic. When the server recovers, it is readmitted. This makes the backend fleet self-healing: a crashed or hung server stops receiving traffic without human intervention.

Session stickiness (also called session affinity or sticky sessions) is a feature that routes all requests from a given client to the same backend server. It is typically implemented by setting a cookie that encodes which server handled the first request. Subsequent requests from that client include the cookie, and the load balancer routes them to the same server. Stickiness is required when an application stores session state in server memory or on local disk  -  but this is also a code smell. The better solution is to make the application stateless (externalizing state to Redis or a database) so that any server can handle any request.

---

## How It Actually Works

L4 load balancers implement NAT (Network Address Translation) to forward packets. When a client connects to the load balancer's IP on port 80, the LB selects a backend, rewrites the destination IP and port in the packet to the backend's IP and port, and forwards it. Return traffic from the backend is rewritten back to the LB's IP before being sent to the client. The backend sees the LB's IP as the source (or with PROXY protocol enabled, the real client IP). Because L4 LBs operate below HTTP, they cannot distinguish between a health check endpoint and an API endpoint  -  they only know that the TCP connection succeeded.

L7 load balancers terminate the TLS connection (decrypting traffic), read the full HTTP request, apply routing rules, establish a new (possibly persistent) connection to the selected backend, and forward the request. Because they terminate TLS, they need access to the server certificate and private key. This is called SSL offloading  -  the backends receive plain HTTP, eliminating the need to manage TLS at every backend server. The cost is that the L7 LB must handle TLS termination at scale, which is CPU-intensive. Modern LBs use hardware acceleration for this.

Health check configuration requires tuning three parameters: interval (how often to check), healthy threshold (how many consecutive successes to move from unhealthy to healthy), and unhealthy threshold (how many consecutive failures before removal). A common configuration is: check every 5 seconds, healthy after 2 consecutive successes, unhealthy after 3 consecutive failures. This means a server failing all checks is removed within 15 seconds, and a recovered server is readmitted within 10 seconds. Too aggressive (check every second, threshold of 1) causes false positives during brief hiccups. Too lenient (check every 30 seconds, threshold of 5) means a dead server serves traffic for two and a half minutes.

```nginx
# Nginx as L7 load balancer  -  upstream configuration
upstream api_backends {
    server backend1.internal:8000 weight=3;  # weight=3 means 3x more traffic
    server backend2.internal:8000 weight=1;
    server backend3.internal:8000 backup;   # only used if others are down

    # Health checking (nginx plus / nginx open source with module)
    keepalive 32;  # maintain 32 persistent connections per worker to backends
}

server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;

    location /api/ {
        proxy_pass http://api_backends;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;  # pass original client IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

## How It Connects

The algorithm a load balancer uses to select which server gets the next request is a separate concern from the load balancer's role as infrastructure. Different algorithms optimize for different goals.

[[load-balancing-algorithms|Load Balancing Algorithms]]

When multiple servers handle the same requests, consistent hashing ensures that the same input (like a user ID or cache key) always routes to the same server, enabling efficient caching.

[[consistent-hashing|Consistent Hashing]]

Nginx is commonly deployed as both a load balancer and a reverse proxy. Understanding its configuration unlocks most of the behavior described here.

[[nginx-config|Nginx Configuration]]

---

## Common Misconceptions

Misconception 1: "A load balancer makes my application highly available by itself."
Reality: A load balancer removes unhealthy servers from the pool, which prevents requests from going to dead servers. But if the load balancer itself fails, all traffic fails. The load balancer needs its own high-availability setup: typically two LBs in active-passive or active-active mode, with a VIP (virtual IP) that floats to the healthy LB. Managed services like AWS ALB handle this for you.

Misconception 2: "Sticky sessions are fine for most applications."
Reality: Sticky sessions mean that if the target server dies, the user's session is lost (since the state was on that server). They also undermine load distribution  -  a few heavily-used sessions might always land on one server while others are idle. The correct fix is to make the application stateless and store session data in Redis or the database.

Misconception 3: "L4 load balancing is always faster than L7."
Reality: L4 is simpler and does add less processing overhead per connection. But modern L7 load balancers (like AWS ALB or Envoy) are highly optimized and the overhead is negligible for most applications. L7 also enables connection reuse and HTTP/2 multiplexing, which can actually reduce total connections and improve efficiency over naive L4 forwarding.

---

## Why It Matters in Practice

Load balancers are a foundational piece of production infrastructure. Every web-facing service with more than one instance needs one. The failure mode of not having a load balancer is a single application server that becomes a SPOF (single point of failure). The failure mode of a badly configured load balancer (wrong health check endpoint, too-lenient thresholds, no SSL termination) is traffic going to dead servers, insecure communications, or configuration that does not match what the backends expect.

For Python developers deploying FastAPI or Django, the typical stack is Nginx or AWS ALB as the L7 load balancer in front of multiple Gunicorn/Uvicorn workers. The load balancer handles SSL termination, request routing, and health checking. The application servers handle only business logic. This separation of concerns is clean and scalable.

---

## Interview Angle

Common question forms:
- "How does a load balancer contribute to high availability?"
- "What is the difference between L4 and L7 load balancing?"
- "How would you design the load balancing layer for a service with 100 instances?"

Answer frame:
Define the load balancer's two roles: distributing load and providing a single entry point. Explain L4 vs L7 with concrete examples of what each can route on. Describe health checks: how they work, what to configure, what happens on failure. Discuss SSL termination at the LB. Address the LB as a potential SPOF and explain active-passive HA. If the question is about session state, explain why statelessness is preferred over sticky sessions.

---

## Related Notes

- [[load-balancing-algorithms|Load Balancing Algorithms]]
- [[nginx-config|Nginx Configuration]]
- [[reverse-proxy|Reverse Proxy]]
- [[consistent-hashing|Consistent Hashing]]
- [[horizontal-vs-vertical-scaling|Horizontal vs Vertical Scaling]]
