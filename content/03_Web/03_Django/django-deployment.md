---
title: 19 - Django Deployment
description: "Deploying Django to production requires disabling debug mode, securing secrets, configuring a production-grade WSGI or ASGI server, running collectstatic, and applying migrations before traffic arrives."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Deployment

> Deploying Django is not just running the development server on a VM — it requires a specific checklist of security settings, a production WSGI or ASGI server, a reverse proxy, collected static files, applied migrations, and environment-based configuration to be correct and safe.

---

## Quick Reference

**Core idea:**
- `DEBUG = False`, `ALLOWED_HOSTS = ['yourdomain.com']`, `SECRET_KEY` from environment — the three mandatory production settings
- `manage.py collectstatic` gathers all static files into `STATIC_ROOT` for nginx to serve
- WSGI stack: gunicorn (app server) behind nginx (reverse proxy + static file server)
- ASGI stack: uvicorn or daphne behind nginx for async views or Django Channels
- `manage.py check --deploy` runs Django's built-in security checklist
- `DATABASE_URL` via `django-environ` or `dj-database-url` — twelve-factor app configuration pattern

**Tricky points:**
- `ALLOWED_HOSTS` must list the actual domain(s); an empty list with `DEBUG = False` rejects all requests with a 400 Bad Request
- `CONN_MAX_AGE` controls how long database connections are reused; setting it too high can exhaust the database's connection limit under high concurrency
- `manage.py migrate` must run before the new code serves traffic — running it after causes `django.db.utils.OperationalError` on new fields
- `SECRET_KEY` rotation invalidates all existing sessions and CSRF tokens — coordinate with a maintenance window or use multiple valid keys

---

## What It Is

Deploying a Django application to production is a checklist of interlocking steps rather than a single action. Think of it as preparing a professional kitchen for opening service: the health inspector checks (security settings), the equipment must be industrial-grade (production server, not the dev server), the prep work must be done (migrations, static files), and the supply chain must be reliable (secrets from environment, not hardcoded). Any one of these missing — `DEBUG = True` in production, migrations not applied, `SECRET_KEY` hardcoded in a public repository — creates a failure mode that ranges from a degraded user experience to a serious security breach.

The twelve-factor app methodology defines how environment-specific configuration should work: configuration that differs between environments (development, staging, production) belongs in environment variables, not in source code. Django's `settings.py` reads these values with `os.environ.get('SECRET_KEY')` or via libraries like `django-environ` or `python-decouple` that add `.env` file support for local development. The `DATABASE_URL` pattern condenses all database connection parameters (host, port, name, user, password) into a single connection string that `dj-database-url` parses into Django's `DATABASES` dict format. This approach keeps production credentials out of version control and makes each environment's configuration explicit and independent.

Static files are a point of confusion for developers deploying Django for the first time. In development, `DEBUG = True` enables Django's built-in static file server, which serves files directly from each app's `static/` directory. In production, `DEBUG = False` disables this server — Django intentionally does not serve static files in production because it is inefficient compared to nginx. The `collectstatic` management command copies all static files from all app directories and `STATICFILES_DIRS` locations into `STATIC_ROOT`. nginx is configured to serve requests to `STATIC_URL` directly from `STATIC_ROOT`, bypassing Django entirely for static assets. This split — nginx handles static, gunicorn handles dynamic — is the standard production architecture.

---

## How It Actually Works

The gunicorn + nginx deployment stack works as follows: nginx listens on port 80/443, handles SSL termination (decrypting HTTPS), serves static and media files from disk without touching Django, and proxies all other requests to gunicorn's UNIX socket or TCP port. gunicorn spawns multiple worker processes (typically `2 * CPU_count + 1`) that each run the Django WSGI application. Each worker handles one request at a time using its own database connections. The `--workers` flag controls the process count; the `--threads` flag adds threads per process for I/O-bound workloads; `--worker-class gevent` switches to async workers for high-concurrency scenarios.

`manage.py check --deploy` runs a set of security checks against the current settings and reports warnings and errors. Common checks include: `SECURE_SSL_REDIRECT` should be `True` (redirect all HTTP to HTTPS), `SESSION_COOKIE_SECURE = True` (cookies only sent over HTTPS), `CSRF_COOKIE_SECURE = True`, `SECURE_HSTS_SECONDS` should be set (instructs browsers to only use HTTPS), `X_FRAME_OPTIONS` should be `DENY` or `SAMEORIGIN` (clickjacking protection), and `DEBUG` must be `False`. These settings are individually documented in Django's security guide, and `check --deploy` provides a single command that verifies all of them.

```python
# settings/production.py (using django-environ)
import environ

env = environ.Env(
    DEBUG=(bool, False),
    ALLOWED_HOSTS=(list, []),
)
environ.Env.read_env()  # reads .env in development

SECRET_KEY = env('SECRET_KEY')
DEBUG = env('DEBUG')
ALLOWED_HOSTS = env('ALLOWED_HOSTS')

DATABASES = {
    'default': env.db('DATABASE_URL')  # postgresql://user:pass@host/dbname
}

STATIC_URL = '/static/'
STATIC_ROOT = '/var/www/myapp/static/'
MEDIA_URL = '/media/'
MEDIA_ROOT = '/var/www/myapp/media/'

# Production security settings
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# Database connection pooling
CONN_MAX_AGE = 60  # reuse connections for 60 seconds

# gunicorn invocation (in Procfile or systemd service)
# gunicorn myproject.wsgi:application --bind 0.0.0.0:8000 --workers 4 --timeout 30
```

---

## How It Connects

The WSGI interface is what gunicorn calls to invoke Django — understanding what `wsgi.py` does and how WSGI works explains why gunicorn is needed and what it provides.

[[wsgi|WSGI]]
[[gunicorn|Gunicorn]]

For projects using Django Channels or async views, uvicorn replaces gunicorn as the app server — the ASGI standard is the prerequisite.

[[asgi|ASGI]]
[[uvicorn|Uvicorn]]

Migrations must be applied as part of the deployment pipeline, before new code that depends on new schema changes goes live.

[[django-migrations|Django Migrations]]

---

## Common Misconceptions

Misconception 1: "I can set DEBUG = True in production for easier debugging."
Reality: `DEBUG = True` in production exposes full Django error pages, including the complete stack trace and the full contents of `settings.py`, to anyone who triggers an error. This leaks secret keys, database passwords, and internal architecture details. It also disables several security features. Production errors should be captured by a service like Sentry; `DEBUG` must be `False`.

Misconception 2: "Django can serve static files in production with DEBUG = False using WhiteNoise."
Reality: WhiteNoise is a legitimate production static file serving middleware for Django that does not require nginx. It is appropriate for simpler deployments (PaaS platforms like Heroku where nginx configuration is limited) and for applications where the static file load is modest. For high-traffic sites, a CDN in front of nginx or S3/CloudFront for static files performs better than WhiteNoise, but WhiteNoise is not a bad choice — it is a deliberate one.

Misconception 3: "manage.py migrate can safely run after new code starts serving traffic."
Reality: If the new code references a database column or table that does not yet exist (because migrations have not been applied), every request to that code path will raise `OperationalError`. The correct deployment order for schema-additive changes is: apply migrations first, then deploy new code. For schema-destructive changes (removing columns), the correct order is: deploy code that no longer reads the column, then remove the column in a separate deployment. This blue-green migration strategy prevents downtime during schema changes.

---

## Why It Matters in Practice

Deployment is where configuration errors, security misconfigurations, and missing steps produce production incidents. Django's `check --deploy` command exists precisely because the security-relevant settings are spread across multiple configuration keys and it is easy to miss one. Teams that build deployment as a repeatable, automated process — a CI/CD pipeline that runs `check --deploy`, applies migrations, runs `collectstatic`, and deploys code in the correct order — ship with confidence. Teams that deploy manually and skip steps produce incidents.

The twelve-factor approach to configuration management is not just a best practice for organization — it is a prerequisite for containerized deployments (Docker, Kubernetes) where the same image is used across environments and configuration is injected via environment variables at runtime. A Django `settings.py` that reads all environment-specific values from environment variables is ready for container deployment without modification.

---

## Interview Angle

Common question forms:
- "What are the minimum required changes when deploying a Django application to production?"
- "What is the role of gunicorn and nginx in a Django deployment?"
- "What does manage.py check --deploy check for?"

Answer frame:
A strong answer covers the mandatory production settings (`DEBUG = False`, `ALLOWED_HOSTS`, `SECRET_KEY` from environment), the gunicorn + nginx architecture (gunicorn runs WSGI workers, nginx handles SSL termination and static files), and the deployment steps sequence (migrate, collectstatic, restart workers). For `check --deploy`, it lists SSL redirect, secure cookies, HSTS, and `X-Frame-Options` as representative checks. Bonus for mentioning the twelve-factor app pattern for environment-based configuration.

---

## Related Notes

- [[wsgi|WSGI]]
- [[asgi|ASGI]]
- [[gunicorn|Gunicorn]]
- [[uvicorn|Uvicorn]]
- [[django-migrations|Django Migrations]]
- [[django-middleware|Django Middleware]]
- [[django-overview|Django Overview and MVT Pattern]]
