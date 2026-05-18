---
title: 03 - Django URL Routing
description: "Django's URL routing system maps URL patterns to view callables using a declarative list that supports path converters, app namespaces, and reverse resolution."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django URL Routing

> Django's URL configuration is a declarative routing table that connects incoming URL strings to Python callables, and its namespace system means you can rename a URL in one place and every template and view that references it updates automatically.

---

## Quick Reference

**Core idea:**
- `urlpatterns` is the list Django searches from top to bottom to match an incoming path
- `path()` uses simple path converters; `re_path()` accepts full regular expressions
- `<int:pk>`, `<slug:slug>`, `<str:name>`, `<uuid:id>` are the built-in path converters
- `include('myapp.urls')` delegates URL matching to an app-level `urlpatterns` list
- `app_name = 'myapp'` in an app's `urls.py` sets the URL namespace
- `reverse('myapp:detail', kwargs={'pk': 1})` resolves a named URL to a string in Python code

**Tricky points:**
- `path()` converters capture and coerce the segment; the view receives a typed Python value, not a string
- `re_path()` always captures strings, regardless of the pattern — type conversion is the view's responsibility
- A trailing slash in `path('articles/', ...)` requires the request URL to include it; `APPEND_SLASH = True` redirects slash-less requests by default
- Namespace collisions are silent: if two apps use the same `app_name`, the second registration wins

---

## What It Is

URL routing in Django works like a postal sorting office. Every incoming request carries an address — the URL path. The sorting office (Django's URL resolver) reads the address against a sorted stack of labelled bins (`urlpatterns`). The moment a bin's label matches the address, the letter is delivered to the handler assigned to that bin (the view). If no bin matches, the sorting office returns a 404. The sorting office does not guess; it reads the list in order and stops at the first match.

The `path()` function creates a route with a human-readable pattern and optional typed captures. The pattern `'articles/<int:year>/<slug:title>/'` tells Django: match any URL that starts with `articles/`, is followed by digits (captured and converted to an integer named `year`), then a slash, then a slug string (captured as `title`), then a trailing slash. The view receives `request, year, title` — already typed correctly — without writing any parsing code. The `re_path()` alternative accepts a full regular expression, which is necessary for patterns that path converters cannot express but comes at the cost of readability and type safety.

Namespacing is the part of Django's URL system that unlocks serious scalability. Without namespaces, every named URL across every installed app must be globally unique, which is impossible to guarantee when combining third-party apps. The `app_name = 'blog'` declaration in `blog/urls.py` prefixes all URL names in that file with `blog:`, so `{% url 'blog:detail' pk=article.pk %}` is unambiguous regardless of how many other apps also have a URL named `detail`. This indirection also means renaming a URL in `urls.py` only requires updating the `name=` parameter — every template and `reverse()` call using the namespace resolves correctly without changes.

---

## How It Actually Works

Django's URL resolution starts from `ROOT_URLCONF` in settings (typically `myproject.urls`). The resolver loads that module, reads its `urlpatterns` list, and applies each pattern to the incoming path in sequence. When it encounters an `include()`, it strips the matched prefix from the path and recurses into the included `urlpatterns`, building up a resolver chain. This chain is cached after first resolution, so subsequent requests to the same URL do not re-parse the entire list.

The path converter system is implemented as a set of registered classes, each with a `regex` attribute (used for matching) and a `to_python(value)` method (used for conversion). `IntConverter` uses regex `[0-9]+` and calls `int()` on the matched string; `SlugConverter` uses `[-a-zA-Z0-9_]+`; `UUIDConverter` uses the full UUID pattern and calls `uuid.UUID()`. Custom converters can be registered globally via `register_converter(MyConverter, 'mytype')` and then used in `path()` patterns like `<mytype:arg>`.

```python
# myproject/urls.py
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('blog/', include('blog.urls', namespace='blog')),
    path('api/', include('api.urls', namespace='api')),
]

# blog/urls.py
app_name = 'blog'  # required when using namespace= in include()

urlpatterns = [
    path('', views.index, name='index'),
    path('<int:pk>/', views.detail, name='detail'),
    path('<int:pk>/edit/', views.edit, name='edit'),
]

# Reverse resolution
from django.urls import reverse
url = reverse('blog:detail', kwargs={'pk': 42})  # → '/blog/42/'

# In templates
# {% url 'blog:detail' pk=article.pk %}
```

---

## How It Connects

The URL configuration is the bridge between an incoming HTTP request and a view callable — understanding the HTTP request side explains why path and query parameters are separated.

[[http-basics|HTTP Basics]]
[[request-response-cycle|Request-Response Cycle]]

Every URL pattern ultimately points to a view, and CBVs expose their URL connection through the `as_view()` classmethod.

[[django-views|Django Views]]

Namespaced URL reverse resolution is particularly important in templates, where `{% url %}` is the only safe way to construct links.

[[django-templates|Django Templates]]

---

## Common Misconceptions

Misconception 1: "re_path() is the older, deprecated way to define URLs."
Reality: `re_path()` is still fully supported and is the correct choice when a URL pattern requires regex features that path converters cannot express — for example, optional trailing segments or complex character class restrictions. `path()` is preferred for common cases because of its readability, but both are current API.

Misconception 2: "include() just concatenates URL patterns from two files."
Reality: `include()` causes the URL resolver to strip the matched prefix before recursing. If the root URL is `path('blog/', include('blog.urls'))` and `blog/urls.py` has `path('<int:pk>/', ...)`, the view for a request to `/blog/42/` receives `pk=42`, not `blog/42/`. The prefix is consumed at each level of `include()`.

Misconception 3: "I can use the same app_name in two different url files that are both included."
Reality: Django uses `app_name` as the key in its namespace registry. The second `include()` that declares the same `app_name` will overwrite the first in the URL namespaces dictionary, meaning reverse resolution for the first include's URLs will silently resolve to URLs in the second include. Always use distinct namespaces per app.

---

## Why It Matters in Practice

The URL configuration is the public contract of a Django application. It defines what paths exist, what parameters they accept, and which view handles each one. Keeping URL definitions clean — using `include()` to delegate to app-level files, using `name=` on every route, and using namespaces consistently — pays dividends when URLs need to change. A URL that has a name can be renamed without touching templates or view code. A URL without a name forces a global search-and-replace through every template and Python file that hard-codes the path string.

The `reverse()` function also matters for programmatic redirect generation, email link construction, and API hypermedia. Any code that constructs a URL from a hard-coded string is a maintenance liability; `reverse()` with a namespace and name is the correct abstraction.

---

## Interview Angle

Common question forms:
- "What is the difference between path() and re_path() in Django?"
- "How does Django's URL namespacing work and why would you use it?"
- "How do you reverse a URL in Django code versus in a template?"

Answer frame:
A strong answer explains that `path()` uses named converters that capture and type-coerce URL segments, while `re_path()` uses raw regular expressions and always captures strings. It covers URL namespacing as a collision-prevention mechanism: `app_name` in the app's `urls.py` prefixes all names so `reverse('blog:detail', kwargs={'pk': pk})` is unambiguous. It distinguishes Python-side `reverse()` from template-side `{% url %}` and notes both use the same namespace:name syntax.

---

## Related Notes

- [[django-overview|Django Overview and MVT Pattern]]
- [[django-views|Django Views]]
- [[django-templates|Django Templates]]
- [[http-basics|HTTP Basics]]
- [[request-response-cycle|Request-Response Cycle]]
