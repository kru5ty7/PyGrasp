---
title: 08 - Rate Limiting
description: "Rate limiting controls how many requests a client can make in a time window, protecting APIs from abuse and overload — algorithm choice and Redis-backed state enable correct behavior across multiple server instances."
tags: [rate-limiting, security, redis, throttling, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Rate Limiting

> Rate limiting is the doorman of your API — it decides how many requests each caller may make per time window and rejects the rest, protecting services from abuse, accidental loops, and resource exhaustion.

---

## Quick Reference

**Core idea:**
- Fixed window: count requests in a time bucket (e.g., per minute); reset counter at window boundary
- Sliding window: count requests in the past N seconds relative to the current moment — smoother than fixed window, no boundary burst
- Token bucket: bucket holds up to B tokens, refills at R tokens/second; each request costs 1 token — allows controlled bursts
- Redis as shared counter: `INCR key` + `EXPIRE key window` for fixed window; sorted set with timestamps for sliding window
- HTTP 429 Too Many Requests with `Retry-After` header is the correct response

**Tricky points:**
- Fixed window has a "boundary burst" problem: a client can make 2x the limit by sending requests at the end of one window and the start of the next
- Token bucket allows bursting up to B requests instantaneously — if this is undesirable, use a leaky bucket (constant output rate regardless of input rate)
- Rate limit keys must identify the right entity: IP address (easy but bypassed by proxies), API key (better for APIs), user ID (for authenticated endpoints)
- When using a load balancer with multiple app instances, rate limit state must be in Redis — in-process counters count only the requests reaching a single instance
- Rate limits should be clearly documented in API responses: include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers

---

## What It Is

An API without rate limiting is like a buffet without plates — guests can pile on as much as they want, and an inconsiderate few can take everything before anyone else has a chance. Rate limiting ensures that each caller gets a fair share of access and that no single client can overwhelm the system. This protection operates at multiple levels: it guards against deliberate abuse (credential stuffing, scraping, DDoS), against accidental abuse (runaway loops in client code), and against resource exhaustion from legitimate but excessive usage patterns.

The choice of algorithm matters because different algorithms have different burst characteristics. A fixed window counter is the simplest: divide time into buckets (each minute, each hour), count requests per bucket, reject once the limit is reached. The problem is the boundary: a client that sends 100 requests in the last second of minute one and 100 requests in the first second of minute two has made 200 requests in two seconds without triggering the per-minute limit of 100. Sliding window algorithms solve this by always counting requests in the past N seconds relative to the current time — there is no exploitable boundary.

The token bucket algorithm models the API as a bucket that fills with tokens over time. Each request consumes one token; if the bucket is empty, the request is rejected. The key property is that the bucket has a maximum capacity B, which means a client can burst up to B requests instantaneously (if the bucket was full) and then is limited to the refill rate R going forward. This models how real usage patterns work — a user might legitimately send a burst of requests when loading a complex page, but sustained high rates should be throttled.

---

## How It Actually Works

Redis-backed rate limiting is required for multi-instance deployments. The simplest fixed-window implementation uses `INCR` and `EXPIRE`.

```python
import redis
import time

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

def is_rate_limited(client_id: str, limit: int = 100, window: int = 60) -> bool:
    key = f"rate:{client_id}:{int(time.time()) // window}"
    count = r.incr(key)
    if count == 1:
        r.expire(key, window)  # set expiry on first increment
    return count > limit
```

A sliding window using a Redis sorted set provides more accurate counting without the boundary burst problem.

```python
def is_rate_limited_sliding(client_id: str, limit: int = 100, window: int = 60) -> bool:
    now = time.time()
    key = f"rate:{client_id}"
    pipe = r.pipeline()
    pipe.zremrangebyscore(key, 0, now - window)        # remove old entries
    pipe.zadd(key, {str(now): now})                    # add current request
    pipe.zcard(key)                                    # count requests in window
    pipe.expire(key, window)
    results = pipe.execute()
    count = results[2]
    return count > limit
```

FastAPI integration with `slowapi` (based on Flask-Limiter's API) provides a decorator-based interface.

```python
from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/api/data")
@limiter.limit("100/minute")
async def get_data(request: Request):
    return {"data": "..."}
```

The correct HTTP response for a rate-limited request is 429 Too Many Requests. The `Retry-After` header should indicate when the client may retry.

```python
from fastapi.responses import JSONResponse

return JSONResponse(
    status_code=429,
    content={"detail": "Rate limit exceeded"},
    headers={
        "Retry-After": "60",
        "X-RateLimit-Limit": "100",
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": str(int(time.time()) + 60),
    },
)
```

---

## How It Connects

Redis is the standard shared counter backend for distributed rate limiting — the sorted set and `INCR` operations used in rate limiters are core Redis commands.

[[redis-python|Redis with Python]]

Rate limiting is a security control often applied alongside authentication — authenticated endpoints can have per-user rate limits, unauthenticated endpoints have per-IP limits.

[[authentication-vs-authorization|Authentication vs Authorization]]

---

## Common Misconceptions

Misconception 1: "IP-based rate limiting is sufficient protection against abuse."
Reality: IP-based rate limiting is easy to bypass using rotating proxies, botnets, or shared NAT addresses (where many legitimate users share one IP). For API abuse prevention, rate limit on API keys or authenticated user IDs. IP-based limits are appropriate as a basic first line of defense for unauthenticated endpoints.

Misconception 2: "Rate limiting protects against DDoS attacks."
Reality: Application-layer rate limiting handles abusive clients but cannot absorb network-layer volumetric attacks. A DDoS that floods the network link or exhausts connection tables at the TCP level happens before rate limiting code executes. DDoS protection requires infrastructure-level solutions (CDN, anycast routing, upstream filtering). Rate limiting handles the application abuse case, not volumetric attacks.

---

## Why It Matters in Practice

Unprotected API endpoints are routinely abused — credential stuffing attacks, data scrapers, and accidental client loops are all common. Rate limiting is a first-class production requirement, not an optional enhancement. Understanding the algorithm trade-offs (fixed window simplicity vs sliding window accuracy), the Redis implementation pattern, and the correct HTTP response (429 + `Retry-After`) makes it possible to implement rate limiting correctly and to evaluate whether third-party solutions are applying it at the right layer.

---

## Interview Angle

Common question forms:
- "How would you implement rate limiting for a REST API?"
- "What is the difference between a token bucket and a fixed window rate limiter?"
- "How do you handle rate limiting when running multiple application instances?"

Answer frame:
Rate limiting requires shared state across all instances — Redis is the standard backend. Fixed window: count requests per time bucket, simple but has a boundary burst problem. Sliding window: count requests in the past N seconds using a sorted set, no boundary issue. Token bucket: allows burst up to B requests then enforces sustained rate. Response: HTTP 429 with `Retry-After`. FastAPI: `slowapi` library provides decorator-based rate limiting backed by Redis.

---

## Related Notes

- [[redis-python|Redis with Python]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[fastapi-security|FastAPI Security]]
- [[secret-management|Secret Management]]
