---
title: 16 - Caching in Django
description: "Django's caching framework provides a unified API over multiple backends that stores computed results to avoid redundant database queries and template rendering."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Caching in Django

> Caching in Django is the discipline of storing expensive computation results — database query results, rendered template fragments, or full HTTP responses — so that subsequent requests can retrieve them instantly without repeating the work.

---

## Quick Reference

**Core idea:**
- Cache backends: `LocMemCache` (per-process, dev only), `RedisCache` (production), `MemcachedCache`, `DatabaseCache`
- Core API: `cache.set(key, value, timeout)`, `cache.get(key)`, `cache.delete(key)`, `cache.get_or_set(key, callable, timeout)`
- Per-view caching: `@cache_page(60 * 15)` caches the full response for 15 minutes, keyed by URL
- Template fragment caching: `{% cache 500 'sidebar' request.user.id %}` caches a template region
- Multiple caches: `CACHES` dict supports named backends; `cache = caches['secondary']` accesses non-default caches
- Cache versioning: `cache.set(key, value, version=2)` and `cache.incr_version(key)` for key-space invalidation

**Tricky points:**
- `LocMemCache` is process-local — two gunicorn workers do not share cache entries; never use it in production
- `cache_page` caches vary by URL but not by user by default — authenticated pages cached with `cache_page` will serve the wrong user's content to other users unless `Vary: Cookie` headers are set correctly
- Django's cache framework does not handle cache stampede (many requests simultaneously missing the same key) — `cache.get_or_set()` with a lock is required for high-traffic keys
- `cache.clear()` clears all keys in the cache — in production with Redis, this is a very dangerous operation if the cache is shared with other applications

---

## What It Is

Caching is a form of memoization applied to a web application: the first time a resource is requested, the system computes the answer and stores it; subsequent requests for the same resource return the stored answer without recomputation. Think of it as a fast-food kitchen's prep work. The kitchen does not slice tomatoes from scratch with every order; they slice a large batch at the beginning of the shift and pull from the prepared container until it runs out (cache expires), then replenish. The customer receives the tomatoes just as quickly as if they were freshly cut, but the kitchen's workload is reduced dramatically.

Django's caching framework provides a unified Python API — `cache.get()`, `cache.set()`, `cache.delete()` — that works identically regardless of the underlying storage backend. This abstraction means you can develop locally with an in-memory cache (no Redis required), switch to Redis in staging, and verify the same behavior with a different backend without changing any application code. The `CACHES` setting maps backend names to backend configurations; the default `cache` alias points to `CACHES['default']`.

Cache invalidation — deciding when to remove or refresh a cached value — is the hard part of caching. Django's framework provides the tools but not the strategy: `cache.delete(key)` removes a specific key, `cache.clear()` removes all keys, and cache versioning increments a version number so that old keys become unreachable without being physically deleted. The most reliable invalidation strategy in Django is to connect cache deletion to signal receivers on model saves and deletes, so the cache is always purged when the underlying data changes. Cache-aside (populate on miss, invalidate on write) is the most common pattern, but it requires careful key design to ensure the right cache entries are invalidated when related objects change.

---

## How It Actually Works

Django's cache backends implement the `BaseCache` interface. When you call `cache.set('article_list', qs_result, timeout=300)`, Django serializes the value using Python's `pickle` module (by default), generates the full cache key by combining the `KEY_PREFIX` setting with the provided key string and an optional version number, and calls the backend's storage method. For Redis, this translates to `SET myproject:1:article_list <pickled_data> EX 300`. When you call `cache.get('article_list')`, Django generates the same key, calls the backend's get method, and unpickles the result if it exists, or returns `None` (or the default you specify) if it does not.

The `@cache_page` decorator wraps a view function and caches the `HttpResponse` object, including headers, status code, and body. The cache key is computed from the URL and the `Vary` headers on the response. If the response has `Vary: Cookie` (which Django adds for authenticated pages), the cache key includes the session cookie value, effectively creating a per-user cache entry. This is the correct behavior for authenticated pages but means the cache provides no benefit for pages where every logged-in user sees different content. For pages that are the same for all users (homepage, category listing, public article), removing the `Vary: Cookie` header by setting `cache_control(public=True)` on the response allows a single cached entry to serve all users.

```python
# settings.py
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': 'redis://127.0.0.1:6379/1',
        'KEY_PREFIX': 'myproject',
        'TIMEOUT': 300,
    }
}

# Low-level cache API
from django.core.cache import cache

def get_article_list():
    cached = cache.get('article_list')
    if cached is None:
        articles = list(Article.objects.filter(published=True).select_related('author'))
        cache.set('article_list', articles, timeout=300)
        return articles
    return cached

# Signal-based invalidation
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

@receiver([post_save, post_delete], sender=Article)
def invalidate_article_cache(sender, **kwargs):
    cache.delete('article_list')

# Per-view caching
from django.views.decorators.cache import cache_page

@cache_page(60 * 15)
def article_list(request):
    articles = Article.objects.filter(published=True)
    return render(request, 'blog/list.html', {'articles': articles})
```

---

## How It Connects

Caching is most effective when applied to the output of expensive ORM queries — understanding which queries are slow is the prerequisite for knowing what to cache.

[[django-orm-queries|Django ORM Queries]]

Signal-based cache invalidation connects to Django's signal system — the `post_save` signal is the hook for clearing stale cache entries.

[[django-signals|Django Signals]]

Redis is the standard production cache backend in Django; understanding Redis data structures and expiry semantics helps when diagnosing cache behavior.

[[redis-python|Redis with Python]] *(MISSING_NOTE)*

---

## Common Misconceptions

Misconception 1: "LocMemCache works fine for development and scales to production with more workers."
Reality: `LocMemCache` is stored in the Python process's memory. Each gunicorn or Celery worker has its own independent cache. A `cache.set()` in worker A is invisible to worker B. In production with multiple workers, `LocMemCache` provides no sharing and gives the false impression that caching is working during single-worker development. Redis is the correct default for anything beyond single-process development.

Misconception 2: "cache_page is always safe to use on any view."
Reality: `cache_page` caches the full HTTP response, including the rendered HTML. If the response contains user-specific content (the user's name, their cart count, personalized recommendations), caching at the view level will serve one user's content to a different user when the cache key matches (same URL, same cookies). Use template fragment caching (`{% cache %}`) for pages where only some content is user-specific.

Misconception 3: "Caching solves slow queries permanently."
Reality: Caching hides slow queries behind a TTL. When the cache expires, the slow query runs again. Caching is appropriate for data that can tolerate some staleness; for frequently-changing data, it only reduces query frequency. The permanent fix for slow queries is index optimization, query optimization, or schema refactoring. Caching is a supplement to query optimization, not a replacement.

---

## Why It Matters in Practice

Caching is one of the most effective performance improvements available to a Django application without architectural changes. A homepage that runs 15 database queries on every request, serving 1000 requests per minute, hits the database 15,000 times per minute. The same homepage with a 60-second `cache_page` caches the response after the first request, reducing database load to 15 queries per minute — a 1000x reduction for the same throughput. This is why caching is always in the conversation when a Django application's database becomes the bottleneck.

The operational complexity of caching — cache invalidation logic, TTL tuning, monitoring cache hit rates, handling cache stampedes — is real, but it is substantially lower than the operational complexity of scaling the database. Teams that instrument their cache hit rates (Redis `INFO` stats or a Django cache middleware that adds `X-Cache` headers) can measure caching effectiveness and tune TTLs with data rather than guesswork.

---

## Interview Angle

Common question forms:
- "What caching backends does Django support and which is appropriate for production?"
- "How do you invalidate a cache entry in Django?"
- "When would you use cache_page versus template fragment caching?"

Answer frame:
A strong answer identifies Redis as the standard production backend and `LocMemCache` as development-only. For invalidation, it describes `cache.delete()` for explicit key removal and signal-based invalidation (connecting `post_save`/`post_delete` to delete affected keys) as the reliable pattern. It distinguishes `cache_page` (full response caching, appropriate for fully public, uniform-content pages) from template fragment caching (partial rendering, appropriate for pages with mixed user-specific and shared content).

---

## Related Notes

- [[django-orm-queries|Django ORM Queries]]
- [[django-signals|Django Signals]]
- [[django-views|Django Views]]
- [[django-templates|Django Templates]]
- [[redis-python|Redis with Python]] *(MISSING_NOTE)*
