---
title: 02 - Horizontal vs Vertical Scaling
description: "Scale-up vs scale-out  -  the two fundamental strategies for increasing system capacity, and when each one applies."
tags: [scaling, horizontal-scaling, vertical-scaling, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Horizontal vs Vertical Scaling

> The most foundational architectural decision in scaling is whether to grow one machine bigger or add more machines  -  and the answer changes everything downstream.

---

## Quick Reference

**Core idea:**
- Vertical scaling (scale-up): replace the current machine with a more powerful one  -  more CPU, more RAM, faster disks
- Horizontal scaling (scale-out): add more machines of the same kind and distribute load across them
- Stateless services scale horizontally with almost no friction; stateful services require additional coordination
- Vertical scaling has a hard ceiling set by available hardware; horizontal scaling is theoretically unbounded
- Most production systems use both strategies at different layers

**Tricky points:**
- Horizontal scaling is not free  -  it requires a load balancer, distributed state management, and network overhead
- Vertical scaling can be the right short-term answer even if horizontal is the long-term plan
- Making a service stateless is itself a design decision with real costs (external session store, etc.)
- "Shared nothing" architecture is the ideal but rarely fully achievable  -  databases are almost always shared
- Horizontal scaling does not help if the bottleneck is a single resource all nodes contend over (e.g., one database)

---

## What It Is

Think about a moving company. When they have a small job, one strong worker can carry everything. As the jobs get bigger, they have two choices: hire someone even stronger (vertical scaling) or hire more workers (horizontal scaling). Hiring one stronger worker is quick and simple  -  you do not need to coordinate multiple people or worry about who carries which box. But there is a limit to how strong one person can be. Eventually, no single worker exists who is strong enough. Horizontal scaling  -  more workers  -  can grow without bound, but it requires a foreman to assign tasks, workers who can hand off boxes to each other, and clear communication about what has been done.

Vertical scaling means upgrading a single server: more CPU cores, more RAM, faster NVMe storage, or a faster network interface card. A database server running on 16 cores and 64 GB of RAM gets upgraded to 64 cores and 256 GB. This works immediately, requires no code changes, and is operationally simple. But it is expensive  -  high-end hardware costs disproportionately more than commodity hardware  -  and it has a ceiling. Once you have reached the largest available machine, you cannot scale further vertically. You also have a single point of failure.

Horizontal scaling means adding more machines and distributing the workload. A single web server becomes ten identical web servers behind a load balancer. Each machine handles a portion of incoming requests. New capacity is added by provisioning another identical machine. Cloud providers make this easy: AWS Auto Scaling Groups, Kubernetes Horizontal Pod Autoscalers, and similar systems can provision new instances within minutes. The costs are distributed across commodity hardware, which is economically efficient. The challenge is that your application must be designed to support this  -  or adapted to do so.

The central constraint for horizontal scaling is state. If a service holds no state between requests (each request is fully self-contained), any instance can handle any request. This is a stateless service, and it scales horizontally with no additional complexity. If a service holds state  -  user session data, cached in-memory values, a local queue  -  then requests must be routed to the instance that holds the relevant state, or the state must be moved to a shared external store. That external store then becomes a new bottleneck, replacing the original one.

---

## How It Actually Works

In practice, most architectures use vertical scaling at the individual node level and horizontal scaling at the tier level. Database nodes are often large, powerful vertical machines because they are difficult to shard. Application servers are smaller commodity nodes scaled horizontally because they are designed to be stateless. The load balancer sits in front and routes requests across the application tier. This hybrid approach exploits the strengths of each strategy.

The concept of statelessness is worth examining precisely. A server is stateless with respect to a given type of state if retrieving or modifying that state from any server produces the same result. For user session data, this means storing sessions in a distributed cache like Redis rather than in server memory. For uploaded files, it means storing them in object storage like S3 rather than on local disk. For database connections, it means using connection pooling that is safe to use from any instance. Each of these moves state to an external system. That external system must then itself be scaled  -  and usually it is scaled vertically (the Redis primary, the database primary) until that too becomes a bottleneck.

When a system scales horizontally, coordination cost rises with the number of nodes. Any operation that requires multiple nodes to agree  -  distributed transactions, two-phase commits, leader election  -  becomes more expensive as node count increases. This is one reason that microservices architecture, while it enables independent horizontal scaling per service, introduces significant complexity around service coordination and data consistency. The "free lunch" of horizontal scaling is only free if you have designed your services to avoid distributed coordination on the hot path.

```python
# Stateful (hard to scale horizontally)
class APIServer:
    def __init__(self):
        self.sessions = {}  # stored in memory  -  tied to this instance

    def get_user(self, session_id):
        return self.sessions.get(session_id)

# Stateless (scales horizontally  -  session lives in Redis)
import redis

class APIServer:
    def __init__(self):
        self.redis = redis.Redis(host='redis-cluster')

    def get_user(self, session_id):
        return self.redis.get(f"session:{session_id}")
```

---

## Visualizer

<iframe src="/static/visualizers/horizontal-vs-vertical-scaling.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Horizontal vs Vertical Scaling Visualizer"></iframe>

---

## How It Connects

Horizontal scaling requires distributing incoming requests across multiple instances. The system that does this distribution and monitors which instances are healthy is the load balancer.

[[load-balancing|Load Balancing]]

Moving state out of application servers so they can scale horizontally usually means moving that state into a cache or database. The most common target for session state in Python systems is Redis.

[[redis-architecture|Redis Architecture]]

The reason horizontal scaling is so valuable is that it unlocks near-linear throughput growth. But actual throughput is also governed by latency  -  how long individual requests take. The relationship between these two metrics is non-trivial.

[[latency-vs-throughput|Latency vs Throughput]]

---

## Common Misconceptions

Misconception 1: "Horizontal scaling is always better than vertical scaling."
Reality: Vertical scaling is simpler, requires no code changes, and is often the correct first step. For databases especially, vertical scaling (bigger machine, more RAM for working set) can buy years of headroom before sharding is needed. The cost per unit of performance from vertical scaling is often lower up to a certain point.

Misconception 2: "I can scale horizontally by just running multiple copies of my app."
Reality: If your app stores any state locally (sessions, files, in-memory caches), multiple copies will produce inconsistent behavior. Users routed to different instances will lose their sessions, get stale data, or see errors. Horizontal scaling requires intentional stateless design first.

Misconception 3: "Horizontal scaling solves the database bottleneck."
Reality: Adding application server instances shifts the bottleneck to the database if you have not also scaled the database tier. Read replicas and caching help with read load; write load requires sharding or a distributed database, both of which introduce significant complexity.

---

## Why It Matters in Practice

The choice between horizontal and vertical scaling shapes every other design decision. A team that plans for horizontal scaling from the start builds stateless services, externalizes session state, uses object storage for files, and avoids in-process caching for shared data. A team that plans to scale vertically can defer those complexities  -  but risks hitting a ceiling at an inconvenient moment.

For Python engineers, the most common scenario is a FastAPI or Django application on a single server that needs to grow. The first step is almost always vertical (more RAM, more CPU) while you observe actual bottlenecks. The second step is usually horizontal scaling of the application tier with a load balancer, after making the application stateless. Database scaling comes third, and it is the hardest.

---

## Interview Angle

Common question forms:
- "How would you scale this service from 1,000 to 1,000,000 users?"
- "What's the difference between horizontal and vertical scaling?"
- "What design changes are needed to make a service horizontally scalable?"

Answer frame:
Define both terms clearly. Then explain that the choice is driven by the nature of the bottleneck and the statefulness of the service. Walk through making a service stateless: externalize session state, use object storage, use a connection pool. Explain the role of a load balancer. Acknowledge that the database tier usually requires vertical scaling first, then read replicas, then sharding as a last resort.

---

## Related Notes

- [[scalability-basics|Scalability Basics]]
- [[load-balancing|Load Balancing]]
- [[consistent-hashing|Consistent Hashing]]
- [[redis-architecture|Redis Architecture]]
- [[database-sharding|Database Sharding]]
