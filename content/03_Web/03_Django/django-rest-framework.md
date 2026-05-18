---
title: 14 - Django REST Framework
description: "Django REST Framework extends Django with serializers, ViewSets, authentication classes, and permission classes that together make building versioned REST APIs fast and consistent."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django REST Framework

> Django REST Framework transforms Django's view and form infrastructure into an API-first toolkit — its serializers, ViewSets, and Router together reduce an entire CRUD API surface to a few dozen lines of declarative code.

---

## Quick Reference

**Core idea:**
- Serializers: like Django forms but for API data — `ModelSerializer`, `validate_<field>()`, `create()`, `update()`
- `ModelViewSet` auto-generates list, create, retrieve, update, partial_update, destroy endpoints
- Router: `DefaultRouter().register('articles', ArticleViewSet)` wires all ViewSet actions to URL patterns automatically
- Authentication: `SessionAuthentication`, `TokenAuthentication`, `JWTAuthentication` (via `djangorestframework-simplejwt`)
- Permission classes: `IsAuthenticated`, `IsAdminUser`, `IsAuthenticatedOrReadOnly`, custom `BasePermission` subclasses
- Pagination: `PageNumberPagination`, `CursorPagination` — configured in `REST_FRAMEWORK` settings dict

**Tricky points:**
- DRF serializers validate and clean data like Django forms, but they also handle serialization of Python objects to JSON — they work both directions
- ViewSet `get_queryset()` and `get_serializer_class()` are the correct override points for per-action queryset and serializer variation
- `@action(detail=True, methods=['post'])` adds custom endpoints to a ViewSet beyond the standard CRUD
- DRF's `TokenAuthentication` uses database-stored tokens; JWT is stateless but requires token revocation logic if needed

---

## What It Is

Django REST Framework is the de-facto standard library for building REST APIs with Django. Think of it as a second skin over Django's view and form systems, optimized for content-type negotiation, serialized data exchange, and API conventions rather than HTML rendering. Where a Django view renders a template and returns HTML, a DRF view serializes a queryset and returns JSON. Where a Django form validates POST data from an HTML form, a DRF serializer validates JSON from a request body. The conceptual mapping is direct, but the execution details — authentication schemes, permission checking, content negotiation, versioning — are all replaced with API-centric implementations.

Serializers are the central abstraction. A `ModelSerializer` generates fields from a model's definition, just like `ModelForm`, but its output is a Python dictionary intended for JSON serialization rather than an HTML form. The `to_representation()` method handles the Python-to-dict direction (reading data for API responses), and `to_internal_value()` handles the dict-to-Python direction (writing data from API requests). Validation runs in `to_internal_value()` via field validators and `validate_<field>()` methods, and the `create()` and `update()` methods persist the validated data. Custom serializers that are not tied to a model override these methods directly for full control over the serialization and deserialization process.

ViewSets combine the logic for all standard CRUD operations into a single class. A `ModelViewSet` inherits `list`, `create`, `retrieve`, `update`, `partial_update`, and `destroy` actions from its mixins, each mapped to an HTTP method. The Router is the component that translates these action names into URL patterns: `list` maps to `GET /articles/`, `create` to `POST /articles/`, `retrieve` to `GET /articles/{pk}/`, and so on. This convention means a developer reading a DRF codebase immediately knows what endpoints exist by looking at the ViewSet class and its Router registration, without needing to scan through a `urlpatterns` list.

---

## How It Actually Works

DRF's `APIView` subclasses Django's `View` but replaces the request object with `rest_framework.request.Request`, which wraps Django's `HttpRequest` and adds content negotiation (parsed request body available as `request.data` regardless of content type) and authentication support. On every request, `APIView.initial()` runs authentication, permission checking, and throttle checking before the handler method (`get()`, `post()`, etc.) is called. Authentication classes are tried in order; the first one that successfully authenticates the request sets `request.user` and `request.auth`. If no authentication class succeeds, the request proceeds as anonymous.

Permission checking in DRF is a list of classes, each with `has_permission(request, view)` and `has_object_permission(request, view, obj)` methods. `has_permission()` runs before the handler, checking broad access (is the user authenticated? is this an admin?). `has_object_permission()` runs when `self.get_object()` is called inside the handler, checking object-level access (does this user own this specific object?). The view calls `get_object()` which calls `check_object_permissions()` internally, so using `self.get_object()` automatically enforces object-level permissions — calling `get()` on the queryset directly bypasses this check.

```python
# serializers.py
from rest_framework import serializers
from .models import Article

class ArticleSerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = Article
        fields = ['id', 'title', 'body', 'published', 'author_name', 'created_at']
        read_only_fields = ['id', 'created_at']

    def get_author_name(self, obj):
        return obj.author.get_full_name()

    def validate_title(self, value):
        if len(value) < 5:
            raise serializers.ValidationError('Title must be at least 5 characters.')
        return value

# views.py
from rest_framework.viewsets import ModelViewSet
from rest_framework.permissions import IsAuthenticatedOrReadOnly
from rest_framework.decorators import action
from rest_framework.response import Response

class ArticleViewSet(ModelViewSet):
    queryset = Article.objects.select_related('author').filter(published=True)
    serializer_class = ArticleSerializer
    permission_classes = [IsAuthenticatedOrReadOnly]

    @action(detail=True, methods=['post'], url_path='publish')
    def publish(self, request, pk=None):
        article = self.get_object()  # triggers has_object_permission
        article.published = True
        article.save()
        return Response({'status': 'published'})

# urls.py
from rest_framework.routers import DefaultRouter
router = DefaultRouter()
router.register('articles', ArticleViewSet, basename='article')
urlpatterns = router.urls
```

---

## How It Connects

DRF serializers replace Django forms for API use cases but share the same validation philosophy — understanding Django forms first makes DRF serializers immediately intuitive.

[[django-forms|Django Forms]]

DRF's `ModelSerializer` generates fields from model definitions the same way `ModelForm` does — ORM knowledge transfers directly.

[[django-orm|Django ORM]]
[[django-orm-queries|Django ORM Queries]]

DRF's authentication system integrates with Django's session auth but adds token and JWT options — the authentication concepts connect directly to Django's auth system.

[[django-auth|Django Authentication]]

---

## Common Misconceptions

Misconception 1: "DRF serializers are just JSON converters."
Reality: Serializers handle both directions: serializing Python objects to JSON-compatible data (for responses) and deserializing and validating incoming JSON data (for requests). They also handle nested relationships, `SerializerMethodField` for computed values, field-level validation, and object creation/updating. They are the API equivalent of Django's form+model combination.

Misconception 2: "ModelViewSet always requires all six CRUD endpoints."
Reality: `ModelViewSet` inherits all six actions, but you can restrict them using the `http_method_names` attribute or by inheriting from specific mixins: `ReadOnlyModelViewSet` provides only `list` and `retrieve`. Alternatively, using `mixins.CreateModelMixin` + `mixins.ListModelMixin` + `GenericViewSet` composes exactly the endpoints you need without unwanted ones.

Misconception 3: "DRF's token authentication is the same as JWT."
Reality: DRF's built-in `TokenAuthentication` stores one token per user in the database table `authtoken_token`. Every API request queries this table to validate the token. JWT is stateless — the token contains a signed payload that the server verifies cryptographically without a database lookup. JWT tokens can be invalidated only by maintaining a blocklist (which re-introduces the database lookup) or by using short expiry times with refresh tokens.

---

## Why It Matters in Practice

DRF is present in the overwhelming majority of Django codebases that expose an API. Its serializer/ViewSet/Router pattern is so standardized that a developer familiar with DRF can contribute to any DRF-based codebase immediately. The ViewSet convention also creates a natural structure for API versioning (namespace the router under `v1/`), throttling (per-view or per-user rate limits via throttle classes), and OpenAPI schema generation (DRF's `spectacular` integration auto-generates Swagger docs from ViewSets).

The permission class system is where API security lives in practice. Understanding that `has_permission()` checks broad access and `has_object_permission()` checks row-level access — and that the latter only runs if you use `self.get_object()` — prevents a common class of authorization bugs where developers implement object ownership checks but call `get()` directly, accidentally exposing other users' data.

---

## Interview Angle

Common question forms:
- "What is the difference between a DRF serializer and a Django form?"
- "How does ViewSet + Router work in DRF?"
- "What is the difference between has_permission() and has_object_permission()?"

Answer frame:
A strong answer explains serializers as bidirectional (serialize to JSON for responses, validate and deserialize from JSON for requests), contrasting with forms which only validate incoming data for HTML workflows. It describes ViewSets as action containers that Routers translate into URL patterns automatically. For permissions, it distinguishes `has_permission()` (called on every request, checks broad access) from `has_object_permission()` (called when `get_object()` is invoked, checks row-level access), and notes that bypassing `get_object()` bypasses object-level permission checks.

---

## Related Notes

- [[django-views|Django Views]]
- [[django-forms|Django Forms]]
- [[django-auth|Django Authentication]]
- [[django-orm-queries|Django ORM Queries]]
- [[rest|REST]]
- [[http-methods|HTTP Methods]]
- [[jwt|JWT]]
