---
title: 02 - Design a Rate Limiter
description: "A walkthrough of designing a distributed rate limiter — algorithms, Redis-based implementation, where to place it, and handling edge cases."
tags: [system-design, case-study, rate-limiter, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design a Rate Limiter

> A rate limiter is one of the most common and instructive system design problems — it requires choosing an algorithm, making a distributed coordination decision, and reasoning about the tradeoffs between accuracy and performance.

---

## Quick Reference

**Core idea:**
- A rate limiter prevents any single client from making more requests than allowed in a time window
- Token bucket: replenish tokens at a constant rate; consume one per request; burst up to bucket capacity
- Sliding window log: maintain a timestamp log per client; count requests in the last N seconds
- Sliding window counter: divide time into fixed windows with counters; interpolate across window boundary
- Fixed window counter: simplest — count per fixed window; has edge case at window boundary

**Key design decisions:**
- Where to enforce: API gateway (centralized), application code (per-instance, not shared), or service mesh
- Redis data structures: sorted sets for sliding window log; counters + EXPIRE for fixed window
- Distributed enforcement requires shared state (Redis) — in-memory enforcement is per-instance only
- Rate limit key granularity: per user, per IP, per API key, per endpoint, or combinations
- Return 429 Too Many Requests with Retry-After and X-RateLimit-* headers for client guidance

---

## What It Is

A rate limiter enforces a policy: "this client may make at most N requests per time window." Without one, a single user (or a bot, or a misconfigured client) can send unlimited requests, consuming compute, database connections, and API quota on third-party services. A rate limiter protects services from abuse, ensures fair resource distribution, and prevents the accidental runaway of a buggy client.

The requirements divide neatly. Functional: limit clients to N requests per window (e.g., 100 requests per minute per API key). Non-functional: low latency (rate limiting check must add minimal latency to every request), high accuracy (should not allow significantly more than the configured limit), high availability (the rate limiter being unavailable must not block all requests), and horizontal scalability (must work when requests are distributed across multiple application servers).

The core challenge is the distributed enforcement problem. If you enforce rate limits in application server memory, each server has its own counters. A client sending 10 requests per second to 10 servers may see each server count only 1 request — none of which triggers the limit of 5 per second per client. The counters must be stored in a shared data store accessible by all application instances. Redis is the standard choice.

---

## How It Actually Works

**Token bucket algorithm** is the most intuitive and widely used. Each client has a "bucket" with capacity C (the burst limit). Tokens are added to the bucket at rate R (requests per second). Each request consumes one token. If the bucket is empty, the request is rejected. A client that has not made requests for a while has a full bucket and can burst up to C requests at once. This mirrors how real usage works — periodic bursts are acceptable; sustained high rates are not.

**Fixed window counter** is simplest: maintain a counter per client per time window (e.g., per minute). When the counter reaches the limit, reject the request. Reset the counter at the window boundary. Problem: a client can make N requests in the last second of window T and N requests in the first second of window T+1, effectively sending 2N requests in 2 seconds without triggering the limit in either window.

**Sliding window log** resolves this: maintain a sorted set of timestamps for each client's recent requests. On each request: remove timestamps older than the window size, count remaining, allow if under limit and add the new timestamp. This is accurate but memory-intensive — the sorted set can hold many timestamps for high-rate clients.

**Sliding window counter** (the practical compromise): maintain two counters — the current window and the previous window. Calculate the rate as: previous_window_count × (1 - elapsed_in_current_window / window_size) + current_window_count. This approximates sliding window behavior with constant memory usage.

```python
import redis
import time
from typing import Optional

r = redis.Redis()

def check_rate_limit_token_bucket(
    client_id: str,
    capacity: int = 100,     # max burst
    refill_rate: float = 10.0,  # tokens per second
) -> tuple[bool, dict]:
    """Token bucket rate limiter using Redis hash."""
    key = f"rate_limit:tb:{client_id}"
    now = time.time()

    # Lua script for atomic check-and-update
    lua_script = """
    local key = KEYS[1]
    local capacity = tonumber(ARGV[1])
    local refill_rate = tonumber(ARGV[2])
    local now = tonumber(ARGV[3])

    local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
    local tokens = tonumber(bucket[1]) or capacity
    local last_refill = tonumber(bucket[2]) or now

    -- Refill tokens based on elapsed time
    local elapsed = now - last_refill
    tokens = math.min(capacity, tokens + elapsed * refill_rate)

    if tokens >= 1 then
        -- Allow: consume one token
        redis.call('HMSET', key, 'tokens', tokens - 1, 'last_refill', now)
        redis.call('EXPIRE', key, 3600)
        return {1, math.floor(tokens - 1), capacity}  -- allowed, remaining, capacity
    else
        -- Reject: no tokens available
        redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
        redis.call('EXPIRE', key, 3600)
        return {0, 0, capacity}  -- rejected, remaining, capacity
    end
    """

    result = r.eval(lua_script, 1, key, capacity, refill_rate, now)
    allowed = bool(result[0])
    remaining = int(result[1])
    limit = int(result[2])
    return allowed, {"X-RateLimit-Remaining": remaining, "X-RateLimit-Limit": limit}

def check_rate_limit_sliding_window(
    client_id: str,
    limit: int = 100,
    window_seconds: int = 60
) -> tuple[bool, int]:
    """Sliding window log using Redis sorted set."""
    key = f"rate_limit:sw:{client_id}"
    now = time.time()
    window_start = now - window_seconds

    pipe = r.pipeline()
    pipe.zremrangebyscore(key, 0, window_start)   # remove old entries
    pipe.zadd(key, {str(now): now})                # add current timestamp
    pipe.zcard(key)                                # count entries in window
    pipe.expire(key, window_seconds + 1)
    _, _, count, _ = pipe.execute()

    allowed = count <= limit
    if not allowed:
        # Remove the entry we just added (request was denied)
        r.zrem(key, str(now))
    return allowed, limit - count

# FastAPI middleware integration
from fastapi import FastAPI, Request, HTTPException, Response

app = FastAPI()

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    client_id = request.headers.get("X-API-Key") or request.client.host
    allowed, headers = check_rate_limit_token_bucket(client_id)

    if not allowed:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded",
            headers={
                "Retry-After": "60",
                "X-RateLimit-Limit": str(headers["X-RateLimit-Limit"]),
                "X-RateLimit-Remaining": "0"
            }
        )

    response = await call_next(request)
    response.headers.update(headers)
    return response
```

**Where to enforce** rate limits is an architectural decision. Enforcing at the API gateway (Nginx, Kong, AWS API Gateway) is centralized and applies before requests reach application code — the most efficient approach. Enforcing in application middleware (as above) requires Redis shared state for distributed enforcement but allows more granular control per endpoint. Service mesh (Istio's EnvoyFilter) enforces transparently at the proxy layer without application code changes.

**The three most important design decisions:** (1) Algorithm choice: token bucket for burst tolerance, sliding window log for accuracy, fixed window for simplicity. For most APIs, token bucket is the right choice — it allows legitimate bursts while preventing sustained overuse. (2) Shared state vs in-process: always use shared state (Redis) for distributed enforcement; in-process counters only work for single-instance deployments. (3) Lua scripts for atomicity: the check-and-update must be atomic — use a Lua script in Redis, not a pipeline (pipelines are not atomic).

---

## Why It Matters in Practice

Rate limiters are foundational infrastructure for any API. They protect against DDoS attacks, prevent runaway clients from disrupting other users, enable tiered pricing (free tier: 100 req/min, paid tier: 10,000 req/min), and make API quotas enforceable. Designing them correctly requires understanding the distributed coordination problem and the tradeoffs between algorithm accuracy and implementation complexity.

---

## Interview Angle

Common question forms:
- "Design a rate limiter that handles 1 million requests per second."
- "Explain the difference between token bucket and fixed window rate limiting."
- "How do you enforce rate limits across multiple application servers?"

Answer frame:
Requirements: N requests per time window per client, low latency, distributed. Algorithm comparison: fixed window (simple, boundary problem), sliding window log (accurate, memory-heavy), token bucket (allows bursts, constant state). Distributed enforcement: Redis with Lua script for atomic check-and-update. Key design: what identifies a client (IP, API key, user ID). Response headers: 429 with Retry-After and X-RateLimit-*. Where to enforce: API gateway for simplicity, application middleware for granularity.

---

## Related Notes

- [[redis-data-structures|Redis Data Structures]]
- [[redis-architecture|Redis Architecture]]
- [[api-gateway|API Gateway]]
- [[nginx-config|Nginx Configuration]]
- [[latency-vs-throughput|Latency vs Throughput]]
