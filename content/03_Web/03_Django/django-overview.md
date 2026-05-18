---
title: 01 - Django Overview and MVT Pattern
description: "Django is a batteries-included Python web framework built around the Model-View-Template pattern that favors convention over configuration."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Overview and MVT Pattern

> Django is a full-stack Python web framework that ships with an ORM, admin interface, authentication system, form handling, and template engine — understanding its MVT architecture explains why every Django project looks and feels the same regardless of who wrote it.

---

## Quick Reference

**Core idea:**
- MVT separates data (Model), business logic (View), and presentation (Template)
- `manage.py` is the command-line entry point for every developer action
- `settings.py` is the single source of truth for project configuration
- `urls.py` maps URL patterns to view callables
- `wsgi.py`/`asgi.py` are the production entry points for web servers
- Convention over configuration: Django assumes a project layout and rewards following it

**Tricky points:**
- Django's "View" handles business logic — it is not the same as MVC's "View" (which is the Template)
- `manage.py` is per-project; `django-admin` is global — both run management commands
- ASGI support was added in Django 3.0, but WSGI remains the default for synchronous projects
- `DEBUG = True` must never reach production — it leaks source code and settings in error pages

---

## What It Is

Think of Django as a pre-assembled factory rather than a pile of raw materials. Flask hands you bricks and mortar and says build whatever you want. Django hands you a functioning building with rooms already labeled — the ORM room, the admin room, the auth room — and your job is to move in, furnish, and customize. This is what "batteries-included" means: the components you need for the vast majority of web applications ship with the framework and are already wired together.

The Model-View-Template pattern is Django's architectural spine. A Model is a Python class that maps directly to a database table; Django's ORM translates Python operations on that class into SQL. A View is a Python function or class that receives an HTTP request, applies business logic (often querying Models), and returns an HTTP response. A Template is an HTML file with Django Template Language tags that the View renders with data, producing the final response body. The names are deliberately different from Model-View-Controller to signal that Django's View does what MVC's Controller does — it orchestrates the response, not just presents data.

Django's convention-over-configuration philosophy means that if you follow the expected project layout, create the expected files, and use the expected names, Django automatically discovers your models, registers your URL patterns, loads your templates, and applies your migrations. The payoff is that any experienced Django developer can navigate an unfamiliar Django project within minutes. The cost is that deviating from convention requires understanding enough of Django's internals to override its defaults deliberately.

---

## How It Actually Works

When a request arrives, it enters through `wsgi.py` or `asgi.py`, which hand it to Django's WSGI/ASGI application object. That object passes the request through the middleware stack defined in `settings.MIDDLEWARE` — each middleware can inspect or mutate the request, short-circuit the response, or let it pass through. After middleware, the URL resolver reads `ROOT_URLCONF` from settings to find the top-level `urls.py`, then traverses the `urlpatterns` list to find the first matching pattern, which maps to a view callable.

The view callable receives a `HttpRequest` object and returns a `HttpResponse` (or a subclass like `JsonResponse` or `StreamingHttpResponse`). If the view renders a template, Django's template engine locates it by searching the `TEMPLATES` setting's `DIRS` and each installed app's `templates/` subdirectory, compiles the template into a node tree on first access (then caches it), and renders it with the context dictionary the view provides. The rendered string becomes the response body. On the way back out, the middleware stack processes the response in reverse order before the response is serialized and sent to the client.

```python
# The four entry points in a minimal Django project
myproject/
    manage.py          # python manage.py runserver / makemigrations / migrate
    myproject/
        settings.py    # INSTALLED_APPS, DATABASES, MIDDLEWARE, TEMPLATES
        urls.py        # ROOT_URLCONF — urlpatterns = [path('', include('myapp.urls'))]
        wsgi.py        # WSGI application for gunicorn/Apache mod_wsgi
        asgi.py        # ASGI application for uvicorn/daphne (channels, async views)
```

---

## How It Connects

Django's WSGI and ASGI entry points are what web servers actually call — understanding the protocol layer explains why gunicorn and uvicorn are involved in deployment.

[[wsgi|WSGI]]
[[asgi|ASGI]]

The request travels through middleware before reaching a view; the middleware stack is where cross-cutting concerns like sessions, auth, and CSRF protection live.

[[django-middleware|Django Middleware]]

Every URL pattern maps to a view, and views query models and render templates — those three components form the complete request cycle.

[[django-views|Django Views]]
[[django-urls|Django URL Routing]]
[[django-orm|Django ORM]]

---

## Common Misconceptions

Misconception 1: "Django follows the MVC pattern."
Reality: Django uses MVT, where the View corresponds to MVC's Controller (it handles request logic) and the Template corresponds to MVC's View (it handles presentation). Django's documentation explicitly notes this distinction to prevent confusion when developers arrive from Rails or Spring backgrounds.

Misconception 2: "Django is only for large, monolithic applications."
Reality: Django apps are designed to be reusable, self-contained components. A Django project is simply the container that wires together one or more apps, and apps can be published to PyPI and installed into any project. Many production systems run small, focused Django apps as microservices behind an API gateway.

Misconception 3: "manage.py runserver is suitable for production."
Reality: Django's development server is single-threaded, has no process management, and is not hardened for public traffic. Production deployments use gunicorn or uvicorn in front of nginx, with `DEBUG = False` and all secrets loaded from the environment.

---

## Why It Matters in Practice

Django's built-in components mean a team can go from zero to a working, authenticated, admin-equipped web application in hours rather than days. The ORM handles schema creation and migration, the admin provides immediate data inspection without building a UI, and the auth system provides hashed passwords and session management out of the box. For data-heavy applications — internal tools, CMS platforms, e-commerce backends, API services — this dramatically compresses the time from idea to deployable product.

Understanding MVT at the architectural level also matters when things go wrong. A slow response is almost always a View that is triggering too many ORM queries; knowing that Views own business logic and Models own data access tells you exactly where to look. A security vulnerability is almost always a misconfigured middleware or a missing CSRF token; knowing that the middleware stack is the first line of defense tells you where the protection should live.

---

## Interview Angle

Common question forms:
- "Explain the MVT pattern and how it differs from MVC."
- "What does 'batteries-included' mean in the context of Django?"
- "What are the four main entry point files in a Django project?"

Answer frame:
A strong answer explains that MVT is Django's naming for a pattern where Models encapsulate data and database interactions, Views contain the request-handling and business logic (equivalent to MVC's Controller), and Templates handle HTML rendering (equivalent to MVC's View). The answer should note that Django's ORM, admin, auth, forms, and template engine ship as part of the framework rather than requiring separate packages, and it should name at least three of the four entry point files and their roles.

---

## Related Notes

- [[django-project-structure|Django Project Structure]]
- [[django-views|Django Views]]
- [[django-urls|Django URL Routing]]
- [[wsgi|WSGI]]
- [[asgi|ASGI]]
- [[request-response-cycle|Request-Response Cycle]]
