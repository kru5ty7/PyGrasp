---
title: 13 - Django Authentication
description: "Django's built-in authentication system provides user account management, session-based login, permission checking, and a customizable User model — all integrated with the ORM and middleware."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Authentication

> Django ships with a complete authentication system covering user creation, password hashing, session-based login, permission checking, and group management — and the single most important decision in any new Django project is whether to customize the User model before the first migration.

---

## Quick Reference

**Core idea:**
- Built-in `User` model: `username`, `password` (hashed), `email`, `first_name`, `last_name`, `is_staff`, `is_superuser`, `groups`
- `authenticate(request, username=..., password=...)` returns a `User` or `None`; `login(request, user)` stores the user in the session
- `logout(request)` clears the session; `request.user` is an `AnonymousUser` if not logged in
- `@login_required` redirects to `settings.LOGIN_URL` if unauthenticated; `LoginRequiredMixin` is the CBV equivalent
- `AUTH_USER_MODEL = 'myapp.CustomUser'` must be set before the first `migrate` run — changing it later requires manual migration work
- `user.has_perm('app.change_article')`, `@permission_required('app.add_article')`, and template `{% if perms.blog.change_article %}`

**Tricky points:**
- Never store passwords in plain text — Django uses PBKDF2 by default; `make_password()` and `check_password()` are the correct functions if bypassing `authenticate()`
- `is_active = False` disables the account; `authenticate()` returns `None` for inactive users by default
- `request.user` is always set — it is `AnonymousUser` (not `None`) when no one is logged in; `AnonymousUser` has `is_authenticated = False`
- The default `User` model's `username` field has a 150-character limit and uniqueness constraint — email-based auth requires a custom user model or a custom backend

---

## What It Is

Django's authentication system is a complete identity management layer baked into the framework. Think of it as a hotel's front desk: guests check in with credentials (authenticate), receive a key card (session cookie) that grants access to their room (protected views), and check out when done (logout). The front desk knows who each guest is (request.user), can verify whether they have clearance for special areas (permissions), and can group guests by membership tier for bulk access management (groups). All of this infrastructure is provided by Django without any additional packages.

The built-in `User` model stores usernames, hashed passwords, email addresses, and a set of flags that control access: `is_active` (can the user log in at all), `is_staff` (can the user access the admin), and `is_superuser` (does the user bypass all permission checks). Passwords are never stored in plain text. Django uses PBKDF2 with SHA256 by default, with a configurable number of iterations, and the stored value includes the algorithm name, iteration count, salt, and hash — making it self-describing and upgradeable as security requirements change. When Django checks a password, it reads the algorithm from the stored hash and uses the appropriate hasher, which means changing the hasher in settings automatically upgrades hashes the next time users log in.

The permission system is built around four actions per model: `add`, `change`, `delete`, and `view`. These are automatically created for every registered model in the `django.contrib.auth` migration. Users can be granted permissions directly or through groups, where a group is a named set of permissions that can be assigned to multiple users. Checking permissions — `user.has_perm('blog.change_article')` in Python or `{% if perms.blog.change_article %}` in templates — returns `True` if the user has the permission directly, through any of their groups, or is a superuser.

---

## How It Actually Works

The authentication flow involves two separate steps that are often confused. `authenticate()` is a credential verification function that takes a username and password, hashes the submitted password, and compares it against the stored hash. It returns a `User` instance if the credentials are valid, or `None` if they are not. `login()` is a session management function that takes a verified `User` instance and stores the user's primary key in the session, along with a hash of the current password that is used to invalidate sessions when the password changes. The request object carries the session from this point forward, and `AuthenticationMiddleware` reads it on every subsequent request to populate `request.user`.

The `AUTH_USER_MODEL` setting is the most consequential configuration decision in a new Django project. Django's ORM has many built-in references to `AUTH_USER_MODEL` — `ForeignKey(settings.AUTH_USER_MODEL, ...)` is the pattern used throughout `django.contrib.auth` and in third-party apps. If you start with the default `auth.User` and later decide you need email-only login, profile fields on the user, or UUIDs as primary keys, migrating away from the default `User` model after the first `migrate` run requires manual migration surgery on multiple tables. The standard advice is to always create a custom user model that inherits from `AbstractUser` at the start of every project, even if you add no customizations initially, preserving the option to extend it later.

```python
# views.py — manual authentication
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect, render

def login_view(request):
    if request.method == 'POST':
        user = authenticate(
            request,
            username=request.POST['username'],
            password=request.POST['password'],
        )
        if user is not None:
            login(request, user)
            return redirect('dashboard')
        else:
            return render(request, 'auth/login.html', {'error': 'Invalid credentials'})
    return render(request, 'auth/login.html')

@login_required
def dashboard(request):
    return render(request, 'dashboard.html', {'user': request.user})

# myapp/models.py — custom user model (start of every project)
from django.contrib.auth.models import AbstractUser

class User(AbstractUser):
    bio = models.TextField(blank=True)
    avatar = models.ImageField(upload_to='avatars/', null=True, blank=True)

# settings.py
AUTH_USER_MODEL = 'myapp.User'
```

---

## How It Connects

`AuthenticationMiddleware` is what populates `request.user` on every request — it depends on `SessionMiddleware` being earlier in the stack, and understanding middleware ordering is prerequisite.

[[django-middleware|Django Middleware]]

The `LoginRequiredMixin` and `PermissionRequiredMixin` are view-level tools that enforce authentication as part of the CBV dispatch chain.

[[django-views|Django Views]]

Django REST Framework requires a different approach to authentication — session auth still works, but token and JWT auth are common for APIs, and the permission system is reimplemented as DRF permission classes.

[[django-rest-framework|Django REST Framework]]

---

## Common Misconceptions

Misconception 1: "I can change AUTH_USER_MODEL after running the first migration."
Reality: Changing `AUTH_USER_MODEL` after the first migration requires manual migration surgery: renaming the auth user table, updating all foreign keys pointing to it across all apps (including third-party apps like `django-allauth`), and carefully managing the migration history. The Django documentation explicitly warns against this. Always set a custom `AUTH_USER_MODEL` at project creation, before running any migrations.

Misconception 2: "request.user is None when the user is not logged in."
Reality: `request.user` is always populated by `AuthenticationMiddleware`. For unauthenticated requests, it is set to an `AnonymousUser` instance — a sentinel object that has `is_authenticated = False`, `is_active = False`, and `is_staff = False`. Checking `request.user is None` will always be `False`; the correct check is `request.user.is_authenticated`.

Misconception 3: "Django stores passwords in a reversible format."
Reality: Django stores passwords using a one-way hash function (PBKDF2 by default). The stored value is `algorithm$iterations$salt$hash` — the plain text password cannot be recovered from it. The `check_password(raw_password, stored_hash)` function rehashes the submitted password and compares. If you need to "reset" a password, you generate a new one — you cannot retrieve the old one.

---

## Why It Matters in Practice

Authentication is the security foundation of any web application, and Django's built-in system gets the hard parts right by default: passwords are hashed with a work factor that can be tuned as hardware improves, sessions are invalidated when passwords change, inactive users cannot log in, and the ORM protects against SQL injection in credential queries. Implementing these properties from scratch is non-trivial and error-prone; using Django's system means inheriting years of security hardening.

The `AUTH_USER_MODEL` decision has the largest long-term impact on a project's codebase. A custom user model that simply inherits from `AbstractUser` with no additions costs nothing initially and preserves full flexibility for future extension. A project that starts with the default `auth.User` and later needs to add a `phone_number` field, switch to UUID primary keys, or enforce email-uniqueness faces a painful migration effort. This is one of the few Django configuration decisions that is genuinely difficult to reverse.

---

## Interview Angle

Common question forms:
- "How does Django's authentication system work — authenticate() vs login()?"
- "What is the difference between the default User model and AbstractUser?"
- "Why should you set AUTH_USER_MODEL at the start of a project?"

Answer frame:
A strong answer distinguishes `authenticate()` (credential verification, returns User or None) from `login()` (session management, stores user ID in session). It explains `AbstractUser` as the correct base for a custom user model that preserves all built-in fields while allowing extension, and contrasts with `AbstractBaseUser` for full custom implementations. It articulates the migration cost of changing `AUTH_USER_MODEL` after the first migration and recommends always creating a custom model at project start, even without immediate customization.

---

## Related Notes

- [[django-middleware|Django Middleware]]
- [[django-views|Django Views]]
- [[django-forms|Django Forms]]
- [[django-rest-framework|Django REST Framework]]
- [[session-based-auth|Session-Based Auth]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[hashing-and-passwords|Hashing and Passwords]]
