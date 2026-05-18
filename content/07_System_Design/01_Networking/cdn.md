---
title: 06 - CDN
description: "Content Delivery Networks cache assets at globally distributed edge nodes, reducing latency and origin load  -  understanding cache-control headers and invalidation determines how well this works."
tags: [cdn, caching, networking, edge, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# CDN

> A CDN is a globally distributed cache for your content  -  understanding how edge nodes decide what to cache, how long to keep it, and when to go back to origin is what determines whether your CDN helps or creates subtle consistency problems.

---

## Quick Reference

**Core idea:**
- A CDN caches content at edge nodes distributed around the world, serving users from the nearest node
- Origin server is the source of truth; edge nodes serve cached copies
- `Cache-Control` headers (max-age, s-maxage, no-cache, no-store) control what CDNs cache and for how long
- Cache invalidation allows removing or updating cached content before TTL expires
- CDNs reduce latency (shorter physical distance), reduce origin load, and improve availability

**Tricky points:**
- `Cache-Control: no-cache` does not mean "do not cache"  -  it means "revalidate before using the cached copy"
- `Cache-Control: no-store` means "never store this response"  -  this is what "do not cache" actually means
- CDN cache invalidation propagates across all edge nodes, which can take 30 - 60 seconds globally
- Setting very long TTLs requires a robust invalidation strategy, or stale content will persist
- CDNs can also serve as DDoS protection by absorbing traffic at the edge before it reaches origin

---

## What It Is

Imagine a newspaper publisher in New York. Every day they print the paper and mail it to subscribers across the country. A subscriber in Los Angeles waits two days for delivery. The solution: print the paper in New York and ship bulk copies to regional distribution centers in Los Angeles, Chicago, and Miami. Local subscribers get same-day delivery from their nearest distribution center. The publisher's New York printing press (the origin server) only needs to print once; the distribution centers (edge nodes) handle local delivery. This is a CDN.

A Content Delivery Network is a geographically distributed network of servers  -  called edge nodes, PoPs (Points of Presence), or edge locations  -  that cache copies of content. When a user requests a resource, the CDN routes the request to the nearest edge node. If that node has a cached copy, it serves it immediately. If not (a cache miss), it fetches the content from the origin server, caches it, and serves it. Subsequent requests from that region are served from the edge cache.

The latency benefit comes from physics: the speed of light limits how fast data can travel. A user in Tokyo requesting content from a New York origin server experiences at minimum 150ms of round-trip latency just from propagation delay. If the CDN has an edge node in Tokyo with a cached copy, the round-trip might be 10ms. For static assets  -  images, CSS, JavaScript, fonts  -  this difference is immediately perceivable. For large file downloads, it also means better bandwidth utilization since local network infrastructure is used instead of intercontinental links.

The origin load benefit is equally important for scaling. Without a CDN, every request for every image, stylesheet, and script hits your origin servers. With a CDN, a popular asset cached at edge nodes means thousands of requests served without the origin ever knowing. Your origin only handles cache misses and requests for content that cannot be cached (dynamic HTML, API responses, authenticated content). This can reduce origin traffic by 80 - 95% for media-heavy applications.

Modern CDNs have expanded far beyond static assets. Cloudflare, AWS CloudFront, Fastly, and Akamai all offer programmable edge execution (running code at edge nodes), DDoS mitigation, Web Application Firewall (WAF), bot management, and full HTTPS certificate management. They have become an integral layer of production web infrastructure rather than just a caching service.

---

## How It Actually Works

The CDN decides whether to cache a response based primarily on the `Cache-Control` response header sent by the origin. The most relevant directives for CDN behavior are:

`max-age=<seconds>`: the response may be cached by any cache (browser, CDN, proxy) for this many seconds. For a CDN, this controls how long the edge node keeps the asset before re-fetching from origin.

`s-maxage=<seconds>`: same as `max-age`, but applies only to shared caches (CDNs and proxies), not the browser's private cache. This allows setting a long CDN cache TTL while having the browser revalidate more frequently, or vice versa.

`no-cache`: the response may be stored in cache, but the cache must revalidate with the origin before serving it. This does not mean "do not cache." A CDN receiving this will cache the response but will check with origin on every subsequent request using a conditional request (sending the `If-None-Match` or `If-Modified-Since` header). If the content has not changed, origin returns 304 Not Modified and the cached copy is served. This is much more efficient than a full fetch.

`no-store`: the response must not be stored anywhere. This is what you use for sensitive data like authentication tokens or personal information. A CDN receiving `no-store` passes every request to origin.

Cache invalidation is how you update cached content before its TTL expires. CDNs provide APIs to invalidate by URL, path prefix, or cache tag. Cloudflare's Cache API allows invalidating by URL. AWS CloudFront supports wildcard invalidation (e.g., `/images/*`). Invalidation is not instantaneous  -  it typically takes 30 - 60 seconds to propagate to all edge nodes globally. During this window, some users may receive stale content from edge nodes that have not yet been purged.

```python
import boto3

def invalidate_cloudfront_cache(distribution_id: str, paths: list[str]):
    """Invalidate specific paths in CloudFront cache."""
    cf = boto3.client('cloudfront')
    response = cf.create_invalidation(
        DistributionId=distribution_id,
        InvalidationBatch={
            'Paths': {
                'Quantity': len(paths),
                'Items': paths,  # e.g. ['/static/logo.png', '/api/config.json']
            },
            'CallerReference': str(time.time())  # unique ID for this invalidation
        }
    )
    return response['Invalidation']['Id']

# After deploying new static assets:
invalidate_cloudfront_cache(
    distribution_id='E1ABCDEFGHIJKL',
    paths=['/static/*']  # wildcard to clear all static files
)
```

CDNs determine cache key from the URL by default. Two requests to the same URL get the same cached response. If your responses vary by request header (for example, Accept-Language for localization, or Accept-Encoding for compression), you must configure the CDN to include those headers in the cache key. Failing to do so means a French user might receive the English-language version cached for a previous English user.

---

## How It Connects

CDNs work because the content being served is the same for many users  -  it can be cached. Understanding what can and cannot be cached, and how cache control headers communicate this, is the foundation of caching strategy.

[[caching-strategies|Caching Strategies]]

A CDN is essentially a network of reverse proxies. The same concepts of SSL termination, header forwarding, and request routing apply at the edge, just at a global scale.

[[reverse-proxy|Reverse Proxy]]

Cache invalidation at the CDN level faces the same fundamental challenge as cache invalidation everywhere: stale data persists until TTL expires or an explicit invalidation is triggered.

[[cache-invalidation|Cache Invalidation]]

---

## Common Misconceptions

Misconception 1: "CDNs are only for static files  -  my API doesn't need one."
Reality: CDNs can cache API responses with appropriate `Cache-Control` headers. Read-heavy API endpoints that return the same data to all users (e.g., product catalog, public configuration) benefit enormously from CDN caching. Personalized or authenticated endpoints cannot be cached at the CDN layer without careful attention to cache keys.

Misconception 2: "Cache-Control: no-cache means the response will not be cached."
Reality: `no-cache` means "cache it, but check with origin before using the cached copy." The response is stored, but served conditionally. This is more efficient than `no-store` (never cache) for responses that change occasionally but are frequently requested  -  the CDN only fetches the full response when it has changed, using `304 Not Modified` otherwise.

Misconception 3: "After I invalidate the cache, all users immediately see the new content."
Reality: Cache invalidation propagates across edge nodes over 30 - 60 seconds. During this window, users served by edge nodes that have not yet received the invalidation will still receive stale content. For time-sensitive updates, the safer pattern is cache busting: including a hash of the content in the filename (e.g., `logo.a3b4c5.png`) so the URL itself changes when the content changes, bypassing the old cache entirely.

---

## Why It Matters in Practice

CDNs are both a performance tool and a resilience tool. When your origin has an outage, a CDN serving cached content can continue serving users for the duration of the cache TTL. This "stale-while-revalidate" behavior means partial origin outages are invisible to users for cached content. But it also means you need to think carefully about what TTL to set: a 24-hour cache TTL on configuration data means an outage lasts up to 24 hours from the user's perspective even after the origin is fixed.

For Python engineers, the most important CDN-related skills are: setting correct `Cache-Control` headers on responses (knowing when to use max-age vs s-maxage vs no-cache vs no-store), implementing cache busting for versioned assets (content hash in filename), and calling invalidation APIs as part of deployment pipelines.

---

## Interview Angle

Common question forms:
- "How would you use a CDN to improve the performance of this web application?"
- "What is the difference between Cache-Control: no-cache and no-store?"
- "How do you ensure users see new content immediately after a deployment?"

Answer frame:
Explain the CDN architecture: edge nodes, origin server, cache miss flow. Describe the latency and origin load benefits. Walk through `Cache-Control` directives  -  especially the no-cache vs no-store confusion. Explain cache busting (content hash in filename) as the most reliable invalidation strategy. Discuss what should and should not be cached: static assets (long TTL + cache busting), public API responses (moderate TTL with invalidation), authenticated content (no CDN caching).

---

## Related Notes

- [[caching-basics|Caching Basics]]
- [[caching-strategies|Caching Strategies]]
- [[cache-invalidation|Cache Invalidation]]
- [[reverse-proxy|Reverse Proxy]]
- [[dns|DNS]]
