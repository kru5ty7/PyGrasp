---
title: 01 - DNS
description: "How the Domain Name System translates human-readable hostnames into IP addresses, and how it is used as a primitive for load distribution and traffic control."
tags: [dns, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# DNS

> DNS is the internet's phone book, but it is also a distributed caching system, a load balancer, and a single point of failure — and understanding all three roles is what makes it a system design topic.

---

## Quick Reference

**Core idea:**
- DNS translates domain names (api.example.com) into IP addresses
- Resolution involves a chain: client → recursive resolver → root nameserver → TLD nameserver → authoritative nameserver
- TTL (time-to-live) controls how long resolvers and clients cache a record
- A records map names to IPv4; AAAA to IPv6; CNAME to another name; MX to mail servers
- DNS can distribute load by returning multiple A records or using geo-based routing

**Tricky points:**
- Low TTL means faster propagation of changes but more DNS query load
- DNS changes do not take effect immediately — existing caches hold old records until TTL expires
- DNS-based load balancing is not true load balancing — it operates at the IP level before connection
- CNAME records add a round-trip hop; avoid chains of CNAMEs
- DNS hijacking and poisoning are real attacks; DNSSEC mitigates them but is not universally deployed

---

## What It Is

Imagine you want to call a friend named Alex, but you only know their name, not their phone number. You look up "Alex" in a contact book. The contact book does not hold all the world's phone numbers — it holds the number for a local directory, which knows how to reach a regional directory, which eventually reaches the right person's number. You get Alex's number, call them, and the next time you call you still remember the number. This is DNS.

DNS, the Domain Name System, is a hierarchical distributed naming system that translates human-friendly names like `api.example.com` into machine-friendly IP addresses like `192.0.2.1`. Every time your browser loads a page, your mobile app calls an API, or your server connects to a database by hostname, DNS resolution happens first. It is invisible when it works and catastrophically visible when it fails.

The system is hierarchical. At the top are the root nameservers — there are 13 logical root nameservers (operated by multiple physical machines using anycast). They know which nameservers are authoritative for each top-level domain (TLD) like `.com`, `.org`, or `.io`. TLD nameservers know which nameservers are authoritative for each second-level domain like `example.com`. The authoritative nameserver for `example.com` knows the actual IP addresses for all of its subdomains.

Your computer does not talk to all these servers directly. Instead, your operating system sends queries to a recursive resolver — usually provided by your ISP, by Google (8.8.8.8), or by Cloudflare (1.1.1.1). The recursive resolver does the legwork: it walks the hierarchy from root to TLD to authoritative nameserver and returns the final answer to your client. It also caches results so it does not need to repeat this walk for every query. Your operating system caches the result too, for the duration of the TTL.

TTL is the most operationally significant parameter in DNS. When an authoritative nameserver returns an A record with TTL=300, it is saying "this answer is valid for 300 seconds." Recursive resolvers and clients will not re-query for that hostname for five minutes. If you change the IP address in your DNS record, clients holding cached copies will not learn about the change until their TTL expires. This is why DNS changes appear to "take time to propagate" — they do not propagate; old caches expire. Lowering TTL before a planned change (say, from 3600 to 60) reduces the propagation window at the cost of increased query load on your nameservers.

---

## How It Actually Works

The full resolution chain for a cold cache query to `api.example.com` from a client proceeds as follows. The client's operating system checks its local DNS cache — not found. It sends a recursive query to the configured recursive resolver (say 8.8.8.8). The resolver checks its cache — not found. The resolver queries a root nameserver, which responds with "I don't know, but here are the `.com` TLD nameservers." The resolver queries a `.com` TLD nameserver, which responds with "I don't know, but here are the authoritative nameservers for `example.com`." The resolver queries one of those authoritative nameservers, which finally responds with the A record for `api.example.com` and its TTL. The resolver caches this, returns it to the client, and the client caches it. Total time: typically 50–200ms for an uncached query.

DNS is used in system design beyond simple name lookup. DNS-based load balancing returns multiple A records for the same hostname. When a client receives multiple IPs, it typically uses the first one, but many load balancers and CDNs use round-robin DNS — cycling through IPs so different clients connect to different servers. This is crude: it does not account for server health or load, and it is not real load balancing. But it is simple and operates below the application layer.

More sophisticated is GeoDNS or latency-based routing. AWS Route 53, for example, can return different A records depending on the geographic origin of the DNS query. Users in Europe resolve to a European CDN edge. Users in Asia resolve to an Asian edge. This happens transparently at the DNS level. Health check integration means that if a server fails Route 53's health check, its IP is removed from rotation. The TTL determines how quickly this removal propagates.

```python
import socket
import dns.resolver  # dnspython library

# Basic DNS lookup
ip = socket.gethostbyname('api.example.com')
print(f"IP: {ip}")

# Inspect DNS record details including TTL
resolver = dns.resolver.Resolver()
answers = resolver.resolve('api.example.com', 'A')
for rdata in answers:
    print(f"IP: {rdata.address}, TTL: {answers.ttl}")

# Check multiple A records (DNS load balancing)
answers = resolver.resolve('multi-region.example.com', 'A')
ips = [str(rdata) for rdata in answers]
print(f"Available IPs: {ips}")  # may return several for different servers
```

---

## How It Connects

DNS-based routing is one of the first techniques used to direct traffic across multiple servers or regions. But for real load distribution within a region, a proper load balancer is needed.

[[load-balancing|Load Balancing]]

CDNs rely heavily on DNS. When you request a CDN-hosted asset, DNS resolves the hostname to the nearest edge node using GeoDNS or anycast. The CDN layer is what makes assets fast globally.

[[cdn|CDN]]

Reverse proxies often sit behind a single DNS entry. The DNS record points to the reverse proxy, which then routes traffic to backend services.

[[reverse-proxy|Reverse Proxy]]

---

## Common Misconceptions

Misconception 1: "DNS changes propagate immediately."
Reality: DNS changes propagate when existing caches expire, which takes as long as the current TTL. If your A record has TTL=3600 (one hour) and you change the IP, some clients will continue using the old IP for up to an hour. To reduce this window, lower your TTL to 60–300 seconds well in advance of any planned IP change.

Misconception 2: "DNS-based load balancing distributes load evenly."
Reality: DNS returns a list of IPs. The client picks one (usually the first). Different clients cache different answers. There is no feedback mechanism — DNS does not know if one server is overloaded. Real load balancing requires infrastructure that monitors server health and distributes connections actively.

Misconception 3: "A CNAME record is equivalent to an A record."
Reality: A CNAME is an alias to another name, not an IP. Resolving a CNAME requires an additional DNS query to resolve the target name. CNAME chains (A → B → C) add multiple lookups. Additionally, CNAME records cannot coexist with other records for the same name at the zone apex (root domain), which is why many DNS providers offer "ALIAS" or "ANAME" records as an alternative.

---

## Why It Matters in Practice

DNS is often the first thing to check when a system appears to be down. If DNS resolution fails or returns wrong answers, every part of your stack that uses hostnames stops working — your application servers cannot reach the database, your load balancers cannot route traffic, and your clients cannot reach your API. Monitoring DNS resolution latency and availability is a baseline operational practice.

DNS TTL strategy is important during migrations. Moving from one server to another, rotating certificates, or changing CDN providers all require DNS updates. The standard practice is to lower TTL to 60–300 seconds 48 hours before the planned change, make the change, verify it is working, and then restore the TTL to a higher value. This ensures that during the migration window, any reversal takes only minutes rather than hours.

---

## Interview Angle

Common question forms:
- "Walk me through what happens when a user types a URL into their browser."
- "How does DNS contribute to load balancing and high availability?"
- "What is a TTL and why does it matter operationally?"

Answer frame:
Trace the full resolution chain from client to authoritative nameserver. Explain caching at each level and the role of TTL. Describe DNS-based load balancing (round-robin, GeoDNS) and its limitations compared to a real load balancer. Discuss TTL as a knob for controlling propagation speed vs. query load. Mention DNS as a dependency and the operational importance of monitoring it.

---

## Related Notes

- [[load-balancing|Load Balancing]]
- [[cdn|CDN]]
- [[reverse-proxy|Reverse Proxy]]
- [[http-basics|HTTP Basics]]
