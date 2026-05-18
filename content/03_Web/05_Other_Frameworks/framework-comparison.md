---
title: 05 - Python Web Framework Comparison
description: "A structured comparison of Python web frameworks across the axes that actually drive decisions: sync vs async, opinionation level, ecosystem size, and team scale."
tags: [frameworks, comparison, flask, django, fastapi, sanic, litestar, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Python Web Framework Comparison

> Choosing a Python web framework is a product and team decision as much as a technical one — the right answer depends on your use case, your team's existing knowledge, and how much framework opinion you want enforcing your architecture.

---

## Quick Reference

**Core idea:**
- The primary axis is sync vs async: Flask and Django are sync-first; FastAPI, Sanic, and Litestar are async-first
- The secondary axis is opinionation: Django is batteries-included with strong conventions; Flask and Bottle are minimal with freedom to choose everything
- Ecosystem size matters for long-term projects: Flask and Django have larger communities and more third-party integrations than newer frameworks
- Team experience and maintenance burden often outweigh raw performance differences at typical production scales
- "Best framework" questions have no universal answer — the correct question is "best for this use case with this team"

**Tricky points:**
- Flask can use async handlers (`async def`) since Flask 2.0, but it is still WSGI — async handlers run in a thread, not a true event loop
- Django's async views exist but many of its ORM operations are still synchronous — true async Django requires `django-channels` or careful use of `sync_to_async`
- FastAPI's performance advantage over Flask is primarily in I/O-bound async workloads, not CPU-bound ones
- Switching frameworks mid-project is expensive — the first framework choice should be deliberate and based on the 12-month trajectory, not just the first sprint
- "I've always used X" is a valid input to the decision but should be weighed against the cost of that framework's gaps for the specific project

---

## What It Is

Think of Python's web frameworks as a set of vehicle options for a road trip. You are not choosing the vehicle that is objectively best — you are choosing the one that fits the roads you will travel, the passengers you are carrying, and the mechanical skills of your team. A sports car (Sanic, performance-focused) is thrilling on the motorway but miserable on a gravel track. A campervan (Django, batteries-included) carries everything you could need but takes practice to park and is overkill for a solo day trip. A reliable sedan (Flask, minimal and familiar) handles most trips competently with a known maintenance profile. A modern electric vehicle (FastAPI, async-first and type-driven) is efficient and well-instrumented but has a different operational model that requires some re-learning.

The Python web framework landscape in 2024 can be roughly divided into two generations. The first generation — Flask (2010), Bottle (2009), and Django (2005) — was built for the synchronous, WSGI world of blocking I/O and process-based concurrency. Flask prioritised simplicity and developer freedom. Django prioritised convention, completeness, and productivity for database-backed web applications. Bottle prioritised minimalism and portability. These frameworks remain extremely widely used because their ecosystems, documentation, and community knowledge are mature.

The second generation — FastAPI (2018), Sanic (2016), Litestar (2021/Starlite), and the modernised Tornado — was built for or adapted to the asyncio world. These frameworks assume that I/O-bound concurrency is the primary scaling challenge, and they expose Python's async/await model as their primary concurrency mechanism. FastAPI added a second innovation: using Python type annotations not just for documentation but for request validation, serialization, and automatic OpenAPI schema generation. This combination proved highly productive and FastAPI grew extremely fast in adoption.

---

## How It Actually Works

Understanding the comparison requires holding several dimensions simultaneously rather than ranking frameworks on a single axis.

The sync/async dimension determines what kind of concurrency your application can exploit. A Flask or Django application achieves concurrency by running many worker processes or threads — each request ties up one worker for its entire duration, including time spent waiting for database queries or external API calls. A FastAPI or Sanic application achieves concurrency within a single worker by suspending handlers at `await` points, allowing other requests to advance while one is waiting for I/O. For I/O-bound workloads with many concurrent requests, async frameworks can handle significantly more load with fewer resources. For CPU-bound workloads (image processing, heavy computation), this distinction disappears — both models block the event loop or the thread equivalently.

The opinionation dimension determines how much the framework decides for you. Django decides your project layout, your ORM, your admin interface, your migration system, your form validation, and your authentication model. For a standard database-backed web application with user management, these decisions are correct and save weeks of setup. For a JSON API service that uses a non-relational database, those decisions may be irrelevant but you still carry their weight. Flask decides almost nothing: you choose your ORM, your validation library, your serialization approach, and your project structure. This is liberating for experienced developers who know what they want, and paralyzing for teams that have not made these choices before.

```
Framework   | Async | Opinionation | Ecosystem | Primary Strength
------------|-------|--------------|-----------|-------------------
Django      | Partial| High        | Huge      | Full-stack web apps, admin
Flask       | No    | Low          | Large     | Flexible APIs, familiar
FastAPI     | Yes   | Medium       | Growing   | APIs, type safety, auto-docs
Sanic       | Yes   | Low          | Small     | Raw HTTP throughput
Litestar    | Yes   | Medium-High  | Growing   | Typed APIs, built-in features
Tornado     | Yes   | Low          | Medium    | WebSockets, legacy systems
Bottle      | No    | Very Low     | Minimal   | Zero-dependency scripts
```

---

## How It Connects

FastAPI is the framework that best exemplifies the second-generation async, type-annotated approach, and understanding it in depth provides the conceptual foundation for evaluating the others.

[[fastapi|FastAPI]]

Django's "batteries-included" model is most fully understood when you look at its ORM, admin, and authentication system — the framework comparison note summarises the trade-offs, but the Django-specific notes cover the details.

<!-- MISSING_NOTE: django-overview -->

Flask represents the first-generation sync micro-framework that still dominates a large fraction of Python web applications — understanding its extension model and application factory pattern is the practical foundation for most Flask-based codebases.

<!-- MISSING_NOTE: flask-basics -->

---

## Common Misconceptions

Misconception 1: "FastAPI is always faster than Flask."
Reality: FastAPI's throughput advantage is in I/O-bound async workloads. For a simple endpoint that does a single database query, a well-configured Flask + Gunicorn setup and a FastAPI + uvicorn setup will have similar latency at typical traffic levels. The performance difference becomes meaningful under high concurrency with slow I/O.

Misconception 2: "Django is too heavy for APIs."
Reality: Django's admin, ORM, and full-stack features add zero overhead to API responses that do not use them. `django-rest-framework` or `djangorestframework-stubs` can turn Django into a capable API server. The "too heavy" perception usually refers to developer overhead (learning the framework, navigating conventions) rather than runtime overhead.

Misconception 3: "You should always use the newest framework."
Reality: Framework adoption has network effects. A newer framework with a smaller community means fewer Stack Overflow answers, fewer tutorials, fewer job candidates with experience, and fewer third-party integrations. For teams building production systems with maintenance requirements measured in years, ecosystem maturity often outweighs technical newness.

Misconception 4: "Picking the wrong framework will doom the project."
Reality: Most Python web frameworks can be made to work for most problems. The cost of a "wrong" framework choice is usually increased development friction and some re-implementation of missing features — not project failure. The exception is picking a sync framework for a workload that genuinely requires async concurrency, where the architectural mismatch causes real operational problems.

---

## Why It Matters in Practice

The framework comparison question appears in system design interviews, architecture review discussions, and greenfield project planning meetings. Developers who can articulate the trade-offs across multiple dimensions — sync vs async, opinionation level, ecosystem maturity, team expertise — demonstrate the kind of engineering judgment that goes beyond knowing one framework deeply. The ability to say "FastAPI is appropriate here because our team already uses Pydantic, the API is the primary product, and we need OpenAPI documentation for external consumers" is more valuable than saying "FastAPI because it's fast."

Team size and long-term maintenance also deserve more weight than they receive in framework comparison discussions. Django's conventions reduce decision fatigue at scale: new engineers joining a Django project can navigate the codebase using framework knowledge before project-specific knowledge. A Flask project's freedom comes with the obligation to make and document every structural decision, and those decisions become technical debt when the original developers leave. For solo projects and small teams with low turnover, this distinction matters less.

---

## Interview Angle

Common question forms:
- "How would you choose between Flask and FastAPI for a new project?"
- "What are the trade-offs of using Django for a pure API service?"
- "Why is async important for web frameworks?"

Answer frame:
A strong answer to the Flask vs FastAPI question covers the sync/async dimension first, then asks about the team's existing knowledge of type annotations and Pydantic, then considers the need for automatic documentation and validation. For Django as a pure API service, the answer should acknowledge the weight of unused features while also noting that Django REST Framework is a strong option when you need the ORM and admin for non-API parts of the system. For the async importance question, the answer should explain I/O-bound concurrency concretely — one worker handling many requests by suspending on database queries — rather than abstractly.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[asgi|ASGI]]
- [[wsgi|WSGI]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[sanic|Sanic]]
- [[litestar|Litestar]]
- [[tornado|Tornado]]
- [[bottle|Bottle]]
