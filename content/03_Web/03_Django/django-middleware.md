---
title: 10 - Django Middleware
description: "Django middleware is an ordered stack of processing layers that every request passes through on the way in and every response passes through in reverse on the way out."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Middleware

> Django middleware is a pipeline where every request and response must pass through a sequence of processing layers in a fixed order  -  understanding this pipeline is the key to understanding where authentication, CSRF protection, session management, and security headers actually come from.

---

## Quick Reference

**Core idea:**
- `settings.MIDDLEWARE` is an ordered list of dotted class paths applied top-to-bottom for requests, bottom-to-top for responses
- Modern middleware interface: `__init__(get_response)` stores the callable; `__call__(request)` processes the request and delegates to `get_response`
- Built-in: `SecurityMiddleware`, `SessionMiddleware`, `CommonMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `MessageMiddleware`, `XFrameOptionsMiddleware`
- `SessionMiddleware` must precede `AuthenticationMiddleware`  -  auth reads the session to identify the user
- Writing custom middleware: any callable that takes `get_response` and returns a callable that takes `request`

**Tricky points:**
- Middleware order is not optional for built-ins  -  swapping `SessionMiddleware` and `AuthenticationMiddleware` causes `AttributeError: 'str' object has no attribute 'pk'` on every request
- A middleware can short-circuit the entire chain by returning a response without calling `get_response`  -  this is how CSRF and basic auth middleware work
- Process-level exceptions raised in views can be caught in `process_exception()` on old-style middleware or in a `try/except` around `get_response()` in new-style
- Each middleware class is instantiated once per server process, not once per request  -  state on `self` persists across requests and causes bugs

---

## What It Is

Middleware in Django works like a series of checkpoints at an international border crossing. A request entering the country must pass through customs (security headers check), then immigration (session lookup), then identity verification (user authentication), then a document check (CSRF validation), before finally reaching its destination (the view). On the way out, the response passes back through each checkpoint in reverse  -  immigration stamps the passport (updates the session), customs seals the package (adds security headers). Every traveler  -  every request  -  goes through every checkpoint in the same order, regardless of destination.

This pipeline architecture is what makes cross-cutting concerns so clean in Django. CSRF protection does not need to be added to each individual view; it lives in `CsrfViewMiddleware` and automatically applies to every state-changing request. Security headers like `X-Content-Type-Options`, `Strict-Transport-Security`, and `Referrer-Policy` do not need to be set in every view; `SecurityMiddleware` adds them to every response. The cost of this approach is that the middleware stack is always traversed even for requests that do not need all of its processing, but the benefit  -  guaranteed cross-request consistency  -  overwhelmingly outweighs the overhead for virtually all applications.

The modern middleware interface is a composable function pattern. A middleware class's `__init__` receives `get_response`, a callable that represents the rest of the pipeline (everything beneath it in the stack, plus the view). Its `__call__` method receives a `request`, may inspect or modify it, then calls `get_response(request)` to pass the request down the chain and receive a response, which it may then inspect or modify before returning. This is precisely the decorator pattern applied to request/response cycles  -  each middleware wraps the next like nested functions, and the view is at the center.

---

## How It Actually Works

When Django starts, it instantiates each middleware class listed in `settings.MIDDLEWARE` with `get_response` set to the next middleware's callable. The innermost `get_response` is Django's URL resolver and view caller. This creates a chain of callables where calling the outermost middleware's `__call__` eventually triggers every middleware and the view. Django uses `django.core.handlers.base.BaseHandler.adapt_method_mode()` to wrap old-style middleware (which used `process_request`, `process_view`, `process_response`, and `process_exception` methods) into the new-style interface, so both styles can coexist.

The `CsrfViewMiddleware` is a concrete example of short-circuiting. Its `process_view()` hook runs after request middleware but before the view, inspects the request method, and checks whether the request carries a valid CSRF token in the POST data or the `X-CSRFToken` header. If the check fails, `process_view()` returns a `403 Forbidden` response directly, bypassing the view entirely. The `@csrf_exempt` decorator sets a flag on the view function that `CsrfViewMiddleware` reads to skip the check for that specific view, which is how DRF's API views commonly opt out.

```python
# Modern middleware interface
class TimingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response  # called once at startup

    def __call__(self, request):
        import time
        start = time.monotonic()
        response = self.get_response(request)  # call the next middleware/view
        duration = time.monotonic() - start
        response['X-Request-Duration'] = f'{duration:.3f}s'
        return response

# settings.MIDDLEWARE order matters
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',       # 1st: add security headers
    'django.contrib.sessions.middleware.SessionMiddleware', # 2nd: load session
    'django.middleware.common.CommonMiddleware',            # 3rd: URL normalization
    'django.middleware.csrf.CsrfViewMiddleware',           # 4th: CSRF check
    'django.contrib.auth.middleware.AuthenticationMiddleware', # 5th: set request.user
    'django.contrib.messages.middleware.MessageMiddleware', # 6th: flash messages
    'django.middleware.clickjacking.XFrameOptionsMiddleware', # 7th: X-Frame-Options
]
```

---

## How It Connects

The middleware stack is the first place requests land after entering through the WSGI or ASGI interface  -  understanding where middleware sits in the overall request lifecycle gives context for why its ordering has hard constraints.

[[django-overview|Django Overview and MVT Pattern]]
[[wsgi|WSGI]]

Authentication middleware populates `request.user` by reading the session, which is why session middleware must come first  -  the auth system and its relationship to middleware is detailed in the auth note.

[[django-auth|Django Authentication]]

Channels adds async middleware concepts for WebSocket connections, where the middleware stack operates over a different protocol.

[[django-channels|Django Channels]]

---

## Common Misconceptions

Misconception 1: "I can put my middleware anywhere in the MIDDLEWARE list."
Reality: The built-in middleware classes have documented ordering requirements. `SessionMiddleware` sets `request.session` which `AuthenticationMiddleware` reads to set `request.user`. `CsrfViewMiddleware` must run before views to intercept unsafe requests. `SecurityMiddleware` should be first to apply security headers as early as possible. Django's documentation explicitly lists the correct ordering with explanations for each dependency.

Misconception 2: "Middleware is instantiated per request."
Reality: Each middleware class is instantiated once when Django starts, with `get_response` baked in. The same instance handles all requests. Storing request-specific data on `self` (e.g., `self.current_user = request.user`) creates a race condition in multi-threaded servers where two concurrent requests share the same middleware instance. Request-specific state must be passed through the function call chain, not stored on the middleware instance.

Misconception 3: "Writing a custom middleware requires knowing the old process_request/process_response API."
Reality: The new-style middleware is simpler. Any class or function that takes `get_response` in `__init__` and returns a callable that takes `request` and returns a response is a valid middleware. Many custom middlewares are just 10-15 lines. The old-style API still works but is considered legacy.

---

## Why It Matters in Practice

The middleware stack is where Django's security guarantees live. CSRF protection, clickjacking protection, HTTPS enforcement, content-type sniffing protection, and Strict-Transport-Security are all middleware. Removing or reordering middleware incorrectly removes these protections silently  -  the application continues to function, but security properties are lost. This is why `manage.py check --deploy` specifically validates the middleware configuration against Django's recommended security settings.

Custom middleware is also the right tool for cross-cutting operational concerns: request timing, request ID injection for distributed tracing, rate limiting, A/B test flag injection, and tenant identification in multi-tenant SaaS applications. Any behavior that must apply to every request (or a well-defined subset of requests) and that does not belong in business logic belongs in middleware.

---

## Interview Angle

Common question forms:
- "How does Django middleware work and what is the request/response cycle through the stack?"
- "Why does SessionMiddleware need to come before AuthenticationMiddleware?"
- "How would you write a custom middleware to add a request timing header?"

Answer frame:
A strong answer describes middleware as a pipeline where request processing goes top-to-bottom and response processing goes bottom-to-top, with each middleware wrapping the next via `get_response`. It explains that `SessionMiddleware` must precede `AuthenticationMiddleware` because auth reads `request.session` (which session middleware sets) to identify the user. For custom middleware, it describes the `__init__(get_response)` / `__call__(request)` pattern and notes that middleware is instantiated once per process, not per request.

---

## Related Notes

- [[django-overview|Django Overview and MVT Pattern]]
- [[django-auth|Django Authentication]]
- [[django-views|Django Views]]
- [[wsgi|WSGI]]
- [[asgi|ASGI]]
- [[request-response-cycle|Request-Response Cycle]]
