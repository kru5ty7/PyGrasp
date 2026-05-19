---
title: 06 - LLD Rate Limiter
description: A low-level design case study for a rate limiter, implementing token bucket, sliding window, and fixed window algorithms with thread-safe and async-safe designs for API protection.
tags: [lld, case-study, rate-limiter, concurrency, strategy, layer-7]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Rate Limiter

> Design a rate limiter that controls the number of requests a client can make within a time window, using interchangeable algorithms and supporting both synchronous and asynchronous workloads.

---

## Quick Reference

**Requirements:**
- Limit requests per client (by IP, API key, or user ID)
- Support multiple algorithms: token bucket, sliding window, fixed window
- Thread-safe for multi-threaded web servers
- Configurable limits per endpoint or globally
- Return appropriate HTTP 429 response with Retry-After header

**Key patterns used:**
- **Strategy** for rate limiting algorithms
- **Factory** for creating limiters based on configuration
- **Decorator** for applying rate limiting to endpoints

---

## Algorithm Overview

Three common rate limiting algorithms:

**Fixed Window**: Count requests in fixed time intervals (e.g., 100 requests per minute). Simple but allows burst at window boundaries - a client can send 100 requests at 0:59 and 100 more at 1:00.

**Sliding Window Log**: Track timestamps of all requests. Count requests within the last N seconds. Precise but memory-intensive for high-traffic APIs.

**Token Bucket**: A bucket holds tokens that refill at a steady rate. Each request costs one token. If the bucket is empty, the request is rejected. Allows controlled bursts up to the bucket's capacity.

---

## Class Design

```python
import time
import threading
from abc import ABC, abstractmethod
from collections import deque
from dataclasses import dataclass
from typing import Protocol


# --- Rate Limiter Protocol ---
class RateLimiter(Protocol):
    def allow(self, client_id: str) -> bool:
        """Returns True if the request should be allowed."""
        ...

    def retry_after(self, client_id: str) -> float:
        """Returns seconds until the client can retry."""
        ...


# --- Token Bucket ---
class TokenBucket:
    """Per-client token bucket."""
    def __init__(self, capacity: int, refill_rate: float):
        self._capacity = capacity
        self._refill_rate = refill_rate  # tokens per second
        self._tokens = float(capacity)
        self._last_refill = time.monotonic()

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self._last_refill
        self._tokens = min(self._capacity, self._tokens + elapsed * self._refill_rate)
        self._last_refill = now

    def consume(self) -> bool:
        self._refill()
        if self._tokens >= 1:
            self._tokens -= 1
            return True
        return False

    def time_until_available(self) -> float:
        self._refill()
        if self._tokens >= 1:
            return 0.0
        deficit = 1 - self._tokens
        return deficit / self._refill_rate


class TokenBucketLimiter:
    """Thread-safe token bucket rate limiter for multiple clients."""

    def __init__(self, capacity: int, refill_rate: float):
        self._capacity = capacity
        self._refill_rate = refill_rate
        self._buckets: dict[str, TokenBucket] = {}
        self._lock = threading.Lock()

    def _get_bucket(self, client_id: str) -> TokenBucket:
        if client_id not in self._buckets:
            self._buckets[client_id] = TokenBucket(self._capacity, self._refill_rate)
        return self._buckets[client_id]

    def allow(self, client_id: str) -> bool:
        with self._lock:
            return self._get_bucket(client_id).consume()

    def retry_after(self, client_id: str) -> float:
        with self._lock:
            return self._get_bucket(client_id).time_until_available()


# --- Fixed Window ---
class FixedWindowLimiter:
    """Thread-safe fixed window rate limiter."""

    def __init__(self, max_requests: int, window_seconds: float):
        self._max = max_requests
        self._window = window_seconds
        self._counters: dict[str, tuple[float, int]] = {}  # client -> (window_start, count)
        self._lock = threading.Lock()

    def allow(self, client_id: str) -> bool:
        with self._lock:
            now = time.monotonic()
            window_start, count = self._counters.get(client_id, (now, 0))

            # Check if we are in a new window
            if now - window_start >= self._window:
                self._counters[client_id] = (now, 1)
                return True

            if count < self._max:
                self._counters[client_id] = (window_start, count + 1)
                return True

            return False

    def retry_after(self, client_id: str) -> float:
        with self._lock:
            if client_id not in self._counters:
                return 0.0
            window_start, count = self._counters[client_id]
            if count < self._max:
                return 0.0
            elapsed = time.monotonic() - window_start
            return max(0, self._window - elapsed)


# --- Sliding Window Log ---
class SlidingWindowLimiter:
    """Thread-safe sliding window log rate limiter."""

    def __init__(self, max_requests: int, window_seconds: float):
        self._max = max_requests
        self._window = window_seconds
        self._logs: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, client_id: str) -> bool:
        with self._lock:
            now = time.monotonic()
            if client_id not in self._logs:
                self._logs[client_id] = deque()

            log = self._logs[client_id]

            # Remove expired timestamps
            cutoff = now - self._window
            while log and log[0] <= cutoff:
                log.popleft()

            if len(log) < self._max:
                log.append(now)
                return True

            return False

    def retry_after(self, client_id: str) -> float:
        with self._lock:
            if client_id not in self._logs:
                return 0.0
            log = self._logs[client_id]
            if len(log) < self._max:
                return 0.0
            oldest = log[0]
            return max(0, self._window - (time.monotonic() - oldest))


# --- Rate Limiter Decorator ---
def rate_limit(limiter: RateLimiter, client_id_func=None):
    """Decorator that applies rate limiting to a function."""
    def decorator(func):
        def wrapper(*args, **kwargs):
            cid = client_id_func(*args, **kwargs) if client_id_func else "default"
            if not limiter.allow(cid):
                retry = limiter.retry_after(cid)
                raise RateLimitExceeded(retry)
            return func(*args, **kwargs)
        wrapper.__name__ = func.__name__
        return wrapper
    return decorator


class RateLimitExceeded(Exception):
    def __init__(self, retry_after: float):
        self.retry_after = retry_after
        super().__init__(f"Rate limit exceeded. Retry after {retry_after:.1f}s")


# --- Usage ---
# Token bucket: 10 requests capacity, refills 2 per second
tb_limiter = TokenBucketLimiter(capacity=10, refill_rate=2.0)

# Fixed window: 5 requests per 10 seconds
fw_limiter = FixedWindowLimiter(max_requests=5, window_seconds=10.0)

# Sliding window: 5 requests per 10 seconds
sw_limiter = SlidingWindowLimiter(max_requests=5, window_seconds=10.0)


def demo(limiter: RateLimiter, name: str) -> None:
    print(f"\n--- {name} ---")
    client = "user_123"
    for i in range(8):
        allowed = limiter.allow(client)
        status = "allowed" if allowed else f"BLOCKED (retry in {limiter.retry_after(client):.2f}s)"
        print(f"  Request {i+1}: {status}")

demo(tb_limiter, "Token Bucket (cap=10)")
demo(fw_limiter, "Fixed Window (5/10s)")
demo(sw_limiter, "Sliding Window (5/10s)")


# Decorator usage
limiter = TokenBucketLimiter(capacity=3, refill_rate=1.0)

@rate_limit(limiter, client_id_func=lambda user_id: user_id)
def process_request(user_id: str) -> str:
    return f"Processed request for {user_id}"

for i in range(5):
    try:
        result = process_request("user_456")
        print(f"  {result}")
    except RateLimitExceeded as e:
        print(f"  {e}")
```

---

## Algorithm Comparison

| Algorithm | Precision | Memory | Burst | Complexity |
|---|---|---|---|---|
| Fixed Window | Low (boundary burst) | O(1) per client | 2x burst at boundary | Simple |
| Sliding Window Log | High (exact window) | O(N) per client | None | Moderate |
| Token Bucket | Medium (controlled burst) | O(1) per client | Up to bucket capacity | Moderate |

---

## SOLID Analysis

- **SRP**: Each limiter class handles one algorithm. The decorator handles HTTP integration. The exception handles response formatting.
- **OCP**: New algorithms are new classes implementing the `RateLimiter` Protocol. No existing code changes.
- **Strategy**: The limiter algorithm is interchangeable via the Protocol.
- **Thread safety**: All limiters use `threading.Lock` for concurrent request handling.

---

## Related Notes

- [[strategy-pattern|Strategy Pattern]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[decorator-pattern|Decorator Pattern]]
- [[solid-principles|SOLID Principles]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[api-design-principles|API Design Principles]]
