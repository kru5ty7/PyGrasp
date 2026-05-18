---
title: 04 - Django Views
description: "Django views are the request-handling layer that receives an HttpRequest, applies business logic, and returns an HttpResponse — available as simple functions or powerful class hierarchies."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Views

> A Django view is the single point of responsibility for turning an HTTP request into an HTTP response — knowing when to reach for a function-based view versus a class-based view is one of the most practical skills in the Django toolkit.

---

## Quick Reference

**Core idea:**
- FBVs are plain functions: `def my_view(request, pk): return HttpResponse(...)`
- CBVs inherit from `View` and dispatch by HTTP method: `get()`, `post()`, `put()`, `delete()`
- Generic CBVs: `TemplateView`, `ListView`, `DetailView`, `CreateView`, `UpdateView`, `DeleteView`
- `render(request, 'template.html', context)` is shorthand for template loading + `HttpResponse`
- `dispatch()` is the CBV entry point — override it for logic that applies to all HTTP methods
- Mixins (`LoginRequiredMixin`, `PermissionRequiredMixin`) are placed leftmost in the class definition

**Tricky points:**
- CBVs must be connected to URLs via `MyView.as_view()`, not `MyView` directly
- `self` in a CBV is a new instance per request — CBVs are not singletons
- `get_queryset()` and `get_context_data()` are the correct overrides in generic views; avoid overriding `get()` directly
- `LoginRequiredMixin` must come before the view class in the MRO, otherwise `login_url` and `raise_exception` attributes are not found

---

## What It Is

A Django view is the traffic manager of the application. When a URL pattern matches an incoming request, Django hands the request object — containing the HTTP method, headers, body, session data, and user — to the view, and the view is responsible for everything that happens next. The view decides what data to fetch, what rules to apply, what template to render, and what status code to return. It is the equivalent of MVC's controller, even though Django calls it a view.

Function-based views are the simplest possible implementation: a Python function that takes a `request` as its first argument, optional URL-captured parameters as additional arguments, and returns an `HttpResponse`. Their simplicity is their strength. The entire logic of a FBV is visible in one linear block of code — no class hierarchy, no method resolution order, no magic attribute lookups. FBVs are easy to read, easy to test, and easy to reason about. The cost is repetition: two views that share logic (authentication check, permission check, object lookup) must either repeat that logic or extract it into a decorator.

Class-based views solve the repetition problem through inheritance and mixins. Django's generic views — `ListView`, `DetailView`, `CreateView`, `UpdateView`, `DeleteView` — codify patterns so common that writing them from scratch would be boilerplate. A `ListView` that renders a paginated list of `Article` objects requires only three lines: the model name, the template name, and the URL registration. Under the hood, `ListView` inherits from `MultipleObjectMixin` (which provides `get_queryset()` and pagination), `TemplateResponseMixin` (which provides template rendering), and `View` (which provides `dispatch()` and method routing). Mixing in `LoginRequiredMixin` before the view class adds authentication enforcement to any CBV without touching its logic.

---

## How It Actually Works

When Django calls a CBV, it calls `View.as_view()`, which returns a closure that creates a new instance of the view class on every request and calls `dispatch()`. The `dispatch()` method inspects `request.method`, lowercases it, and calls the corresponding method on the instance — `self.get()`, `self.post()`, and so on. If no method handler exists, `dispatch()` returns a 405 Method Not Allowed response. This dispatch mechanism is where cross-method logic should live: overriding `dispatch()` lets you run code before any method handler, which is how `LoginRequiredMixin` intercepts requests before `get()` or `post()` are called.

Generic views like `CreateView` operate by composing multiple mixins. When processing a `GET` request, `CreateView.get()` calls `self.get_form()` to instantiate an empty form, then `self.get_context_data(form=form)` to build the template context, then `self.render_to_response(context)` to render the template. When processing a `POST` request, `CreateView.post()` calls `self.get_form()` with `request.POST` data, validates it, and either calls `form_valid()` (which saves and redirects) or `form_invalid()` (which re-renders with errors). Every one of these steps is a method you can override individually, which is why CBVs are more extensible than FBVs for complex, shared patterns.

```python
# Function-based view
from django.shortcuts import render, get_object_or_404
from django.contrib.auth.decorators import login_required

@login_required
def article_detail(request, pk):
    article = get_object_or_404(Article, pk=pk)
    return render(request, 'blog/detail.html', {'article': article})

# Equivalent class-based view
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import DetailView

class ArticleDetailView(LoginRequiredMixin, DetailView):
    model = Article
    template_name = 'blog/detail.html'
    # auto context key: 'article' (lowercased model name)
```

---

## How It Connects

Views connect to URLs through `urlpatterns` — the URL resolver calls the view callable directly.

[[django-urls|Django URL Routing]]

Views render templates by passing a context dictionary — understanding DTL and context processors explains what data is available inside the template automatically.

[[django-templates|Django Templates]]

Generic views query models through the ORM; `get_queryset()` is the override point for filtering the default queryset.

[[django-orm|Django ORM]]
[[django-orm-queries|Django ORM Queries]]

---

## Common Misconceptions

Misconception 1: "Class-based views are always better than function-based views."
Reality: CBVs are better for standard CRUD patterns where generic views eliminate boilerplate. FBVs are clearer for views with unusual logic flows, multiple conditional branches, or non-standard HTTP method handling. The Django documentation explicitly states both are valid, and many experienced Django developers prefer FBVs for their transparency.

Misconception 2: "self in a CBV holds state between requests."
Reality: `as_view()` creates a new instance of the CBV class for every single request. Setting instance attributes in `dispatch()` is safe precisely because the instance is not shared. Storing state in class-level attributes (not instance-level) would be shared and would cause race conditions in multi-threaded servers.

Misconception 3: "LoginRequiredMixin can go anywhere in the class definition."
Reality: Python resolves the MRO (method resolution order) left to right. `LoginRequiredMixin` must appear before the view class in the inheritance list so its `dispatch()` override is called before the view's `dispatch()`. Writing `class MyView(DetailView, LoginRequiredMixin)` means `DetailView.dispatch()` runs first, bypassing the authentication check entirely.

---

## Why It Matters in Practice

Views are the most-touched files in any Django project. Getting the FBV vs CBV decision right — and knowing the generic view API well enough to avoid re-implementing it — is what separates productive Django developers from those who struggle with repetition and inconsistency. A team that uses `CreateView`, `UpdateView`, and `DeleteView` consistently for CRUD operations writes less code, tests less code, and produces fewer bugs in the standard paths, freeing attention for the application-specific logic that actually differentiates the product.

Understanding `dispatch()` and the mixin system also matters for security. Authentication and permission checks that live in a mixin are guaranteed to run before any method handler; checks placed inside `get()` or `post()` are easily forgotten when a new HTTP method handler is added. The architectural discipline of "use mixins for cross-cutting concerns" is the direct consequence of understanding how CBV dispatch works.

---

## Interview Angle

Common question forms:
- "What is the difference between FBVs and CBVs in Django? When would you use each?"
- "How does Django's class-based view dispatch mechanism work?"
- "Where does LoginRequiredMixin need to go in the class definition and why?"

Answer frame:
A strong answer describes FBVs as simple functions best suited to unique logic, and CBVs as class hierarchies best suited to standard CRUD patterns where generic views remove boilerplate. It explains that `dispatch()` routes by HTTP method and is the correct override point for cross-method logic, that each request creates a fresh CBV instance so instance attributes are safe, and that mixin order in the inheritance list determines MRO and therefore which `dispatch()` runs first.

---

## Related Notes

- [[django-overview|Django Overview and MVT Pattern]]
- [[django-urls|Django URL Routing]]
- [[django-templates|Django Templates]]
- [[django-forms|Django Forms]]
- [[django-auth|Django Authentication]]
- [[decorators|Decorators]]
