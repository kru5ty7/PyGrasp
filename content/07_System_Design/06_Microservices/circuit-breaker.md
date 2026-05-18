---
title: 03 - Circuit Breaker
description: "The three states of a circuit breaker  -  closed, open, half-open  -  how they prevent cascading failures, and what this means for resilience in distributed systems."
tags: [circuit-breaker, resilience, microservices, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Circuit Breaker

> A circuit breaker prevents a slow or failing downstream service from taking down your service too  -  it is the component that turns distributed failure from an avalanche into a controlled degradation.

---

## Quick Reference

**Core idea:**
- Closed state: normal operation; requests pass through; failures are counted
- Open state: downstream is considered failed; requests fail immediately without trying; recovery timer runs
- Half-open state: after the timer expires, a few test requests are allowed through to check recovery
- Failure threshold: how many consecutive failures (or what failure rate) triggers the open state
- Recovery timeout: how long to wait before moving from open to half-open

**Tricky points:**
- A circuit breaker is at the caller side, not the callee  -  each service has breakers for its downstream dependencies
- "Fail fast" in open state is intentional  -  better to immediately return an error than wait for a timeout
- Half-open allows partial recovery testing without immediately routing all traffic to a recovering service
- Circuit breakers do not prevent failures  -  they prevent cascading failures by containing the blast radius
- The breaker state is per-dependency per-service instance  -  two instances of Service A have independent breakers for Service B

---

## What It Is

Think about the circuit breakers in your home. The electrical panel has one breaker per circuit. When an appliance draws too much current (a sign of a fault), the breaker trips  -  it opens the circuit and stops current from flowing. This prevents the fault from damaging other appliances on the circuit or starting a fire. Once the problem is fixed, you reset the breaker and current flows again.

Michael Nygard described the circuit breaker pattern in "Release It!" as applying the same principle to software. When a downstream service is failing  -  returning errors, timing out, or being completely unreachable  -  calls to it should stop immediately rather than piling up. Without a circuit breaker, each call to the failing service times out after several seconds, consuming a thread or an async slot. As calls pile up waiting for timeouts, the caller's own resources are exhausted and it fails too. The failure cascades upstream.

The circuit breaker sits between the caller and the downstream service. It monitors calls to that service. In the closed state (normal operation), all calls pass through and the breaker counts failures. When failures exceed a threshold  -  a certain number of consecutive failures, or a certain percentage of failures within a time window  -  the breaker trips to the open state. In the open state, calls to the downstream service fail immediately without actually attempting the call. The breaker returns an error or a fallback value instantly. The downstream service gets no requests, allowing it to recover.

After a configured timeout (the recovery period), the breaker moves to the half-open state. It allows a small number of test requests through. If those requests succeed, the breaker closes and normal operation resumes. If they fail, the breaker opens again and the recovery timer restarts. The half-open state prevents a service that just came back up from being immediately overwhelmed with the backed-up traffic.

---

## How It Actually Works

The failure threshold has two common implementations. Count-based: after N consecutive failures, the breaker opens. This is simple but does not handle intermittent failures well  -  a 10% failure rate might never trigger a count-based breaker if failures alternate with successes. Rate-based: if the failure rate within a rolling time window exceeds a threshold (e.g., 50% of requests in the last 10 seconds fail), the breaker opens. Rate-based is more representative of actual service health.

The fallback is what the circuit breaker returns when in the open state (or when the downstream call fails). Fallback options: return a cached value (show yesterday's product recommendations), return a default value ("temporarily unavailable"), return an error to the caller, or propagate a partial response. The choice depends on the importance of the data and the user experience. For user-facing features, a degraded experience (showing cached or default data) is better than an error page.

```python
import time
from enum import Enum
from threading import Lock
from typing import Callable, Optional, Any
import logging

class CircuitState(Enum):
    CLOSED = "closed"       # Normal: calls pass through
    OPEN = "open"           # Failing: calls fail immediately
    HALF_OPEN = "half_open" # Testing: limited calls to check recovery

class CircuitBreaker:
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,  # seconds before trying again
        half_open_max_calls: int = 3,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls

        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.last_failure_time: Optional[float] = None
        self.half_open_calls = 0
        self._lock = Lock()

    def call(self, func: Callable, *args, fallback: Any = None, **kwargs) -> Any:
        with self._lock:
            if self.state == CircuitState.OPEN:
                if time.time() - self.last_failure_time >= self.recovery_timeout:
                    self.state = CircuitState.HALF_OPEN
                    self.half_open_calls = 0
                    logging.info("Circuit HALF-OPEN: testing recovery")
                else:
                    logging.warning("Circuit OPEN: failing fast")
                    return fallback  # fail immediately, no attempt

            if self.state == CircuitState.HALF_OPEN:
                if self.half_open_calls >= self.half_open_max_calls:
                    return fallback  # limit test traffic
                self.half_open_calls += 1

        try:
            result = func(*args, **kwargs)
            with self._lock:
                if self.state == CircuitState.HALF_OPEN:
                    # Success in half-open  -  close the circuit
                    self.state = CircuitState.CLOSED
                    self.failure_count = 0
                    logging.info("Circuit CLOSED: recovery confirmed")
                elif self.state == CircuitState.CLOSED:
                    self.failure_count = 0  # reset on success
            return result

        except Exception as e:
            with self._lock:
                self.failure_count += 1
                self.last_failure_time = time.time()
                if self.failure_count >= self.failure_threshold or \
                   self.state == CircuitState.HALF_OPEN:
                    self.state = CircuitState.OPEN
                    logging.error(f"Circuit OPEN: {self.failure_count} failures")
            return fallback

# Usage: wrapping an HTTP call to an external service
import httpx

inventory_breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=30.0)

def check_inventory(product_id: str) -> dict:
    def _call():
        response = httpx.get(
            f"http://inventory-service/products/{product_id}/stock",
            timeout=2.0
        )
        response.raise_for_status()
        return response.json()

    result = inventory_breaker.call(
        _call,
        fallback={"in_stock": True, "quantity": None, "source": "fallback"}
    )
    return result
```

Production circuit breaker libraries provide more sophisticated implementations. Netflix's Hystrix (now in maintenance mode) and its successor Resilience4J (Java) provided thread isolation, timeout handling, and metrics integration. Python libraries include `pybreaker` and `circuitbreaker`. Service meshes like Istio and Linkerd implement circuit breaking at the network level (in the sidecar proxy), making it transparent to application code and consistently applied across all services.

Circuit breaker metrics  -  the number of calls in each state, current failure rate, circuit state transitions  -  must be monitored. An open circuit in production is an actionable alert: something downstream is failing. Circuit breaker metrics also reveal hidden dependencies: a breaker that trips frequently between 2 - 4 PM suggests a downstream service that degrades under afternoon load.

---

## How It Connects

Circuit breakers are one component of the broader resilience pattern. Service discovery, retries with exponential backoff, timeouts, and circuit breakers work together to make a microservices system fault-tolerant.

[[service-discovery|Service Discovery]]

The Saga pattern for distributed transactions also needs circuit breakers for the compensating transaction steps  -  if a step that reverses a prior action fails, the system must have a circuit breaker to prevent it from retrying indefinitely.

[[saga-pattern|Saga Pattern]]

Circuit breakers are complementary to load balancing: the load balancer distributes load, the circuit breaker stops sending load to a failing destination.

[[load-balancing|Load Balancing]]

---

## Common Misconceptions

Misconception 1: "A circuit breaker retries the failed request automatically."
Reality: A circuit breaker does not retry. Retrying is a separate concern. In the open state, the circuit breaker fails the call immediately. Retries happen when the caller receives that failure and decides to retry. The circuit breaker says "don't bother, it won't work right now." Retries say "try again after a delay." These are separate, composable behaviors.

Misconception 2: "A circuit breaker prevents the downstream service from failing."
Reality: A circuit breaker prevents the downstream service's failure from propagating to the caller. The downstream service is still failing  -  the circuit breaker just stops sending it traffic. This gives the downstream service breathing room to recover and prevents the caller from exhausting its own resources waiting for timeouts.

Misconception 3: "One circuit breaker per service is enough."
Reality: Each caller should have a separate circuit breaker instance per downstream dependency. Service A calling Service B and Service C should have two independent circuit breakers  -  one for B, one for C. If B is failing, only the B circuit breaker opens; calls to C are unaffected. A single combined circuit breaker would open for C failures caused by B problems, which is incorrect.

---

## Why It Matters in Practice

Without circuit breakers, a single slow downstream service can cascade into a full system outage. Each call to the slow service ties up a thread or async task waiting for a timeout. As those calls pile up, the caller runs out of threads or event loop capacity. The caller starts timing out to its callers, who run out of capacity, and the failure propagates upstream to the edge service that serves users. The entire system falls down because one deep dependency was slow.

With circuit breakers, the slow service's calls fail fast. The caller returns degraded responses immediately (fallback). The slow service is no longer overwhelmed with new requests (it gets no traffic while the circuit is open). Other dependencies are not affected. The system degrades gracefully rather than failing catastrophically.

---

## Interview Angle

Common question forms:
- "What is a circuit breaker and why is it important in microservices?"
- "Describe the three states of a circuit breaker."
- "How do circuit breakers prevent cascading failures?"

Answer frame:
Describe the cascading failure problem: slow downstream -> caller threads blocked -> caller runs out of capacity -> caller fails -> upstream fails. Describe the circuit breaker as the solution: fail fast instead of blocking. Walk through three states: closed (normal), open (fail fast + recovery timer), half-open (test requests). Explain the threshold and recovery timeout configuration. Discuss fallback strategies: cached data, defaults, explicit error. Close with the importance of metrics: circuit breaker state transitions are production alerts.

---

## Related Notes

- [[microservices-basics|Microservices Basics]]
- [[service-discovery|Service Discovery]]
- [[saga-pattern|Saga Pattern]]
- [[load-balancing|Load Balancing]]
