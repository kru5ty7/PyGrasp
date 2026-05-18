---
title: 01 - Design a URL Shortener
description: "A walkthrough of designing a URL shortener system  -  from estimation through key generation, storage choices, and the critical read-path optimization."
tags: [system-design, case-study, url-shortener, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design a URL Shortener

> The URL shortener is the canonical introductory system design problem  -  it is simple enough to cover fully in an interview but rich enough to surface all the key tradeoffs: scale estimation, ID generation, storage, and read-path optimization.

---

## Quick Reference

**Core idea:**
- Shorten long URLs to short codes (e.g., `short.ly/aB3xK9`) and redirect users
- Writes: create a mapping from short code to original URL
- Reads: look up the original URL for a short code, return 301/302 redirect
- Read-to-write ratio is typically 100:1 or higher  -  optimize heavily for reads
- Short code generation must be unique, hard to guess, and short (6-8 characters)

**Key design decisions:**
- 6 characters in base62 gives 62^6 ≈ 56 billion possible short codes  -  enough for billions of links
- 301 (permanent) redirect is cached by browsers  -  reduces server load but prevents click analytics
- 302 (temporary) redirect is not cached  -  allows analytics but every click hits your servers
- ID generation: hash-based (MD5 of URL, take first 6 chars) vs counter-based (auto-increment + base62 encode)
- Cache: Redis with LRU eviction for the hot URLs  -  80% of traffic goes to 20% of links

---

## What It Is

A URL shortener takes a long, complex URL and produces a short, memorable link. A user submits `https://www.example.com/blog/category/article-with-a-very-long-title?utm_source=newsletter&utm_campaign=spring2026`, and the system returns `https://short.ly/aB3xK9`. When a recipient clicks the short link, the system looks up the original URL and redirects them. The use cases include: social media (Twitter's old 140-character limit), marketing analytics (tracking click-through rates), QR codes (shorter = simpler QR), and general link sharing.

The requirements from a system design perspective divide into functional and non-functional. Functional requirements: shorten a URL and return a short code; redirect a short code to the original URL; optionally provide click analytics (how many times each link was clicked). Non-functional requirements: low latency redirects (P99 under 50ms), high availability (reads must never fail), durability (stored links must not disappear), and sufficient scale (handle billions of links and hundreds of millions of redirects per day).

---

## How It Actually Works

**Scale estimation** comes first. Assume 100 million daily active users creating 0.1 short URLs each per day: 10 million URL creations per day. At 100:1 read-to-write ratio: 1 billion redirects per day. Converting to QPS: writes = 10M / 86,400 ≈ 115 writes/second; reads = 1B / 86,400 ≈ 11,600 reads/second. Storage: each URL pair is roughly 500 bytes (original URL + short code + metadata). Over 5 years: 10M/day × 365 × 5 × 500 bytes ≈ 9 TB. This fits on one large database, though replicas are needed for read load.

**Short code generation** has two main approaches. The hash-based approach: compute MD5 or SHA-256 of the original URL, take the first 6 characters. Problem: collisions  -  different URLs can produce the same 6-character prefix. Collision handling requires checking the database and extending to 7, 8 characters if taken. Also, the same URL always produces the same code, which means different users cannot independently shorten the same URL with different analytics.

The counter-based approach is more robust: maintain a global auto-incrementing counter. For each new URL, increment the counter and encode the counter value in base62 (characters: a-z, A-Z, 0-9). Counter value 12345 encodes to `3D7` in base62. This guarantees uniqueness with no collision checking needed. The only concern is the global counter becoming a bottleneck  -  solved with a distributed counter (Redis INCR) or pre-allocated counter ranges per application server.

**Data model** is minimal:

```
urls table:
  - short_code: VARCHAR(8) PRIMARY KEY
  - original_url: TEXT NOT NULL
  - created_by: VARCHAR(36) NULLABLE
  - created_at: TIMESTAMP NOT NULL
  - expires_at: TIMESTAMP NULLABLE
  - click_count: BIGINT DEFAULT 0

Index: (short_code)  -  primary key, already indexed
Index: (original_url)  -  for deduplication check
```

**Read path optimization** is where the design work is. Redirects are 100x more frequent than writes. The read path must be fast. A Redis cache sits in front of the database: on a redirect request, check Redis first. If the short code is in Redis, return the original URL immediately (cache hit, ~1ms). If not (cache miss), query the database (~10-50ms), populate Redis with the result, and return. With a hot key set, 99% of redirect requests are cache hits.

```python
from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse
import redis
import hashlib
import time

app = FastAPI()
r = redis.Redis(host='redis', decode_responses=True)

def generate_short_code(url: str) -> str:
    """Counter-based code generation using Redis INCR."""
    counter = r.incr("url_counter")  # atomic, distributed counter
    return base62_encode(counter)

def base62_encode(n: int) -> str:
    chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    result = []
    while n:
        result.append(chars[n % 62])
        n //= 62
    return ''.join(reversed(result)).zfill(6)  # zero-pad to 6 chars

@app.post("/shorten")
async def create_short_url(original_url: str) -> dict:
    short_code = generate_short_code(original_url)
    db.execute(
        "INSERT INTO urls (short_code, original_url, created_at) VALUES (%s, %s, NOW())",
        short_code, original_url
    )
    # Pre-populate cache
    r.setex(f"url:{short_code}", 86400, original_url)  # 24h TTL
    return {"short_url": f"https://short.ly/{short_code}"}

@app.get("/{short_code}")
async def redirect(short_code: str):
    # Check cache first
    original_url = r.get(f"url:{short_code}")
    if not original_url:
        # Cache miss: query database
        row = db.fetchone("SELECT original_url FROM urls WHERE short_code = %s", short_code)
        if not row:
            raise HTTPException(status_code=404, detail="Short URL not found")
        original_url = row["original_url"]
        r.setex(f"url:{short_code}", 86400, original_url)  # populate cache

    # 302 for analytics (not cached by browsers); 301 for SEO (cached)
    return RedirectResponse(url=original_url, status_code=302)
```

**Analytics** (click counting) requires careful design. Incrementing a database counter on every redirect is a write on the hottest read path  -  this would bottleneck the system. The pattern is: increment a Redis counter atomically on each redirect, then batch-write the counter increments to the database periodically (every 5 minutes, or when the counter exceeds a threshold). The Redis counter is fast; the database write is infrequent.

**The three most important design decisions:** (1) Counter-based over hash-based code generation  -  avoids collisions, supports per-user distinct codes for the same URL. (2) Redis cache on the read path  -  reduces database reads by 99%, enabling 11,600 RPS with a modest database. (3) 302 vs 301 redirect  -  a business decision: 302 enables click analytics and allows changing the destination URL; 301 is cached by clients and reduces server load but loses analytics capability.

---

## Why It Matters in Practice

The URL shortener exercise teaches estimation (scale first, design second), storage choice (a simple relational DB handles the write volume easily), read optimization (cache everything hot), and the write vs read path distinction. These lessons apply to every system design problem. The specific decisions  -  302 vs 301, counter vs hash, cache TTL  -  have clear trade-offs that must be explained, not just stated.

---

## Interview Angle

Common question forms:
- "Design a URL shortening service like bit.ly."
- "How do you ensure globally unique short codes?"
- "How would you handle 10 billion URLs?"

Answer frame:
Start with estimation: 115 writes/s, 11,600 reads/s, 9 TB over 5 years. Design the short code: counter-based + base62 encoding, 6 characters = 56B possibilities. Design the data model: minimal schema with short_code primary key. Design the read path: Redis cache -> database fallback. Discuss 301 vs 302 trade-off explicitly. For analytics: Redis counter with periodic batch write to database. Scale path: single database with read replicas handles the write load; Redis cluster handles read load.

---

## Related Notes

- [[back-of-the-envelope|Back of the Envelope Estimation]]
- [[caching-basics|Caching Basics]]
- [[database-indexes|Database Indexes]]
- [[consistent-hashing|Consistent Hashing]]
