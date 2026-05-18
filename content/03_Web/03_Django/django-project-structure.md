---
title: 02 - Django Project Structure
description: "A Django project is a configuration container that wires together one or more self-contained apps, each responsible for a specific slice of application functionality."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Project Structure

> Django's two-level project/app split is not bureaucratic overhead  -  it is the mechanism that lets teams build reusable components, publish them to PyPI, and install them into any Django project with a single line in `INSTALLED_APPS`.

---

## Quick Reference

**Core idea:**
- `django-admin startproject myproject` scaffolds the outer project shell
- `manage.py startapp myapp` scaffolds a new app inside the project
- `INSTALLED_APPS` is the registry Django reads to discover models, admin classes, template directories, and management commands
- `settings.py` controls `DEBUG`, `DATABASES`, `ALLOWED_HOSTS`, `STATIC_ROOT`, `MEDIA_ROOT`
- App-level files: `models.py`, `views.py`, `urls.py`, `admin.py`, `apps.py`, `migrations/`
- Reusable apps follow a convention that lets them be installed with `pip install` and added to any project

**Tricky points:**
- The project directory and the inner configuration package share the same name by default  -  this trips up newcomers
- An app must appear in `INSTALLED_APPS` for Django to discover its models and run its migrations
- `apps.py` defines the `AppConfig` class; the `ready()` method is where signal connections should be registered
- `STATIC_ROOT` is where `collectstatic` writes files; it is not where you put your source static files

---

## What It Is

A Django project is like a city, and Django apps are the buildings within it. The city provides infrastructure  -  road networks (URL routing), power grids (settings), emergency services (middleware, auth)  -  but it does not dictate what any individual building does. Each building is self-contained: it has its own floor plan (models), its own staff (views), its own signage (URLs), and its own records (migrations). Buildings can be picked up and moved to another city; a `blog` app built for one project can be installed into an entirely different project by adding it to `INSTALLED_APPS`.

The outer project directory holds the configuration package, which shares its name with the project. Inside that package, `settings.py` is the central configuration file that controls every aspect of Django's behavior. `urls.py` is the root URL configuration; all app-level URL files are pulled in via `include()`. `wsgi.py` and `asgi.py` are the entry points for the web server. The `manage.py` file at the root of the project wraps `django-admin` commands with the project's settings already loaded, so every management command runs in the context of the correct project.

Reusable apps are Django's unit of code sharing. A well-written app declares its own `AppConfig` subclass in `apps.py`, keeps all database interaction inside its own models, defines its own URL namespace, ships its own migrations, and has no hard imports of other project-specific apps. This is why third-party packages like `django-rest-framework`, `django-allauth`, and `django-celery-results` can be installed and dropped into any project  -  they are just well-structured Django apps.

---

## How It Actually Works

When Django starts, it reads `INSTALLED_APPS` and imports each app's `AppConfig`. The app registry (`django.apps.apps`) builds a map of every model class keyed by `app_label.ModelName`. This registry is what allows `ForeignKey('auth.User', ...)` to reference a model by string rather than importing it directly, which avoids circular imports. The registry also controls the order in which `migrate` processes migrations  -  an app can only be migrated after all of its dependencies are already migrated.

The `AppConfig.ready()` hook runs once, after all apps are loaded, and is the canonical place to connect signal receivers. Without `ready()`, a signal connection placed at module level in `models.py` would be executed the moment Django imports that module  -  which can cause the receiver to fire before the full app registry is available, leading to subtle `AppRegistryNotReady` errors. The `apps.py` pattern centralizes this initialization explicitly.

```
myproject/                  <- outer project root (git repo root)
    manage.py
    myproject/              <- configuration package (same name)
        __init__.py
        settings.py         <- INSTALLED_APPS, DATABASES, MIDDLEWARE, TEMPLATES
        urls.py             <- ROOT_URLCONF
        wsgi.py
        asgi.py
    myapp/                  <- a Django app
        __init__.py
        apps.py             <- AppConfig subclass, ready() for signals
        models.py           <- Model subclasses
        views.py            <- View functions / CBVs
        urls.py             <- app-level urlpatterns
        admin.py            <- ModelAdmin registrations
        migrations/
            __init__.py
            0001_initial.py
        templates/
            myapp/          <- templates namespaced under app name
        static/
            myapp/          <- static files namespaced under app name
```

---

## How It Connects

Every model defined in an app's `models.py` becomes visible to the rest of Django only after that app appears in `INSTALLED_APPS`  -  this is how the ORM and migrations discover the schema.

[[django-orm|Django ORM]]
[[django-migrations|Django Migrations]]

The app's `urls.py` is included into the root URL configuration via `include()`, which is how Django routes requests to the correct app without every app needing to know about every other app.

[[django-urls|Django URL Routing]]

The admin, signals, and custom management commands are all app-level constructs that Django discovers through the app registry.

[[django-admin|Django Admin]]
[[django-signals|Django Signals]]

---

## Common Misconceptions

Misconception 1: "The project directory and the app directory are the same thing."
Reality: The project is the outer shell; the inner configuration package (which shares the project's name) is just one of several directories inside the project. Apps are separate directories at the same level as the configuration package, not inside it.

Misconception 2: "I can skip adding my app to INSTALLED_APPS if I import its models directly."
Reality: Django will import the module, but the model will not be registered in the app registry. This means `makemigrations` will not detect it, `migrate` will not create its table, and the admin will not recognize it. `INSTALLED_APPS` is the required registration step.

Misconception 3: "STATIC_ROOT is where I put my CSS and JavaScript source files."
Reality: `STATIC_ROOT` is the destination directory that `collectstatic` writes to when preparing for deployment. Source static files live in each app's `static/` subdirectory or in a project-level directory listed in `STATICFILES_DIRS`. Django copies them all into `STATIC_ROOT` for the web server to serve directly.

---

## Why It Matters in Practice

Teams that understand the project/app split build systems that are easier to test, easier to reuse, and easier to reason about. When an app is genuinely self-contained  -  its own models, URLs, views, and migrations  -  it can be extracted into its own package and published, or it can be swapped out without touching the rest of the project. This modularity becomes critical in larger codebases where different teams own different functional areas.

The `INSTALLED_APPS` list is also a lightweight dependency graph. Reading it tells you immediately which third-party libraries the project uses, which internal apps are active, and  -  by looking at which apps `AppConfig.ready()` hooks run  -  what side effects occur at startup. Keeping this list clean and minimal is one of the most impactful things a team can do to keep startup time and cognitive load manageable.

---

## Interview Angle

Common question forms:
- "What is the difference between a Django project and a Django app?"
- "What does INSTALLED_APPS do and why does it matter?"
- "How would you structure a Django project for a team of five developers?"

Answer frame:
A strong answer distinguishes project (configuration container, single per deployment) from app (reusable functional unit, multiple per project), explains that `INSTALLED_APPS` drives model discovery, migration detection, and app-level resource loading, and describes the standard app-level file layout. Bonus points for mentioning `AppConfig.ready()` as the right place to connect signals and for explaining why `STATIC_ROOT` is separate from static source directories.

---

## Related Notes

- [[django-overview|Django Overview and MVT Pattern]]
- [[django-orm|Django ORM]]
- [[django-migrations|Django Migrations]]
- [[django-urls|Django URL Routing]]
- [[django-admin|Django Admin]]
