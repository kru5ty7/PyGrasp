---
title: 11 - Django Signals
description: "Django signals are an in-process publish-subscribe mechanism that lets decoupled components react to events like model saves and deletes without creating direct imports between apps."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django Signals

> Django signals solve the problem of "I want something to happen when a model is saved, but I don't want the model to know about it" — they enable decoupled side effects, but their synchronous, in-process nature means they are not a substitute for a message queue.

---

## Quick Reference

**Core idea:**
- Built-in signals: `post_save`, `pre_save`, `post_delete`, `pre_delete`, `m2m_changed` from `django.db.models.signals`
- Connect with `signal.connect(receiver_fn, sender=MyModel)` or `@receiver(post_save, sender=MyModel)` decorator
- Receiver functions take `sender`, `instance`, `created`, `**kwargs` (for `post_save`)
- Connect signals in `AppConfig.ready()` inside `apps.py` — never at module level
- Signals are synchronous: the receiver runs in the same thread and transaction as the caller

**Tricky points:**
- Signal receivers connected multiple times will fire multiple times — `dispatch_uid='unique_string'` prevents duplicate connections
- `post_save` fires after the `save()` call but the transaction may not be committed yet — use `transaction.on_commit()` for work that depends on committed data
- Signals cannot be easily unit-tested without triggering actual model saves — mock or disconnect them in tests where signals are not under test
- `pre_save` receives the instance but database row does not yet exist (for new instances); `post_save` receives `created=True` on insert, `False` on update

---

## What It Is

Django signals are a fire-and-forget notification system within a running process. The pattern they implement is publish-subscribe: a sender (typically a model) fires a signal when something happens (a save, a delete, a form submission), and any number of receivers — functions registered to listen for that signal — are called in response. The sender and receivers do not import each other. The sender does not know how many receivers are listening, or what they do. The receivers do not need to modify the sender to hook into its behavior. This decoupling is the core value of signals.

The canonical use case is cross-app side effects. Imagine a `blog` app with an `Article` model, and a `notifications` app that sends emails when new articles are published. The `blog` app should not import the `notifications` app — that would create a circular dependency if `notifications` also imports `blog`. Signals resolve this by having the `notifications` app's receiver listen for `post_save` on `Article`. The `blog` app fires the signal when saving (which Django does automatically for all model saves), and the `notifications` app's receiver runs. Neither app depends on the other directly; both depend on the signal abstraction.

The critical caveat is that signals are synchronous and in-process. When `article.save()` runs, Django calls every registered receiver before returning control to the calling code. A slow receiver blocks the save. A crashing receiver raises an exception that propagates to the caller. Receivers run in the same database transaction as the save, which means the database row may not yet be committed to disk when the receiver fires. For work that depends on committed data — sending a webhook, updating an external service, triggering an async job — the correct pattern is `django.db.transaction.on_commit(lambda: do_work())` inside the receiver, which defers the call until the transaction commits successfully.

---

## How It Actually Works

Django's `Signal` class maintains an internal list of (receiver_function, sender, dispatch_uid) tuples. When `Signal.send(sender, **kwargs)` is called, it iterates this list, filters by sender match, and calls each receiver in sequence with the signal keyword arguments. The return values of receivers are collected and returned as a list of `(receiver, return_value)` tuples, though most code ignores these. `Signal.send_robust()` is a variant that catches exceptions from each receiver rather than propagating them, useful when you want other receivers to still fire even if one fails.

The `dispatch_uid` parameter solves a subtle problem that affects long-running processes. In development with Django's auto-reloader, module imports can happen multiple times, causing `@receiver` decorators to connect the same function twice. In production, `AppConfig.ready()` is called once per process, but if signals are connected at module level rather than inside `ready()`, they may be connected again on every import of the module (e.g., during test collection). Providing a globally unique string as `dispatch_uid` ensures that connecting the same signal twice with the same UID replaces rather than duplicates the connection.

```python
# apps.py — the correct place to connect signals
from django.apps import AppConfig

class NotificationsConfig(AppConfig):
    name = 'notifications'

    def ready(self):
        import notifications.signals  # noqa — triggers @receiver decorators

# notifications/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.db import transaction
from blog.models import Article

@receiver(post_save, sender=Article, dispatch_uid='notifications.article_saved')
def notify_on_publish(sender, instance, created, **kwargs):
    if instance.published:
        # Defer until after transaction commits
        transaction.on_commit(lambda: send_publication_email(instance.pk))

# Custom signal
from django.dispatch import Signal
order_completed = Signal()  # fire with: order_completed.send(sender=Order, order=obj)
```

---

## How It Connects

Signals are connected in `AppConfig.ready()`, which is explained in the project structure note — this is the prescribed initialization point for any side-effect-carrying startup code.

[[django-project-structure|Django Project Structure]]

The `transaction.on_commit()` pattern used inside signal receivers connects directly to how Django manages database transactions; understanding transaction scoping prevents data races.

[[django-orm|Django ORM]]

Signals are one tool for post-save side effects; Celery tasks triggered from signals are the production pattern for heavier work.

[[django-celery|Celery with Django]]

---

## Common Misconceptions

Misconception 1: "Signals are like a message queue — they deliver work asynchronously."
Reality: Signals are synchronous and in-process. The sender blocks until all receivers complete. There is no retry, no durability, no background worker. For asynchronous task delivery, use Celery with Redis or RabbitMQ. Signals are appropriate for lightweight, immediate side effects that should succeed or fail with the triggering operation.

Misconception 2: "post_save fires after the database transaction commits."
Reality: `post_save` fires after Django calls `cursor.execute(INSERT/UPDATE ...)`, but the surrounding transaction may not be committed yet. If the view's transaction rolls back after the signal fires, any external side effects already triggered by the signal (emails sent, APIs called) cannot be undone. Use `transaction.on_commit()` inside the receiver for any side effect that must not happen unless the database change is permanent.

Misconception 3: "I should use signals for everything that happens after a save."
Reality: Django's core developers have explicitly advised restraint with signals. If the sender and receiver are in the same app, a direct method call or an overridden `save()` method is clearer and easier to trace. Signals make code flow non-obvious — a developer reading the save call has no way to know what receivers will fire without searching the entire codebase. Reserve signals for genuine cross-app decoupling where a direct import would create a dependency problem.

---

## Why It Matters in Practice

Signals are a double-edged tool. Used appropriately — for cross-app side effects where a direct import would create circular dependencies — they enable clean architecture. Used as a general "run this after every save" mechanism, they make the application's behavior impossible to trace and debug. A codebase with twenty signal receivers attached to a single model's `post_save` becomes a maintenance burden where changing the model has unpredictable cascading effects.

The practical guidance is to default to overriding `save()` or using direct method calls when the sender and receiver are in the same app, and to reach for signals only when decoupling across app boundaries is genuinely needed. When signals are used, `dispatch_uid`, `AppConfig.ready()`, and `transaction.on_commit()` are the three patterns that prevent the most common signal-related bugs in production.

---

## Interview Angle

Common question forms:
- "What are Django signals and when would you use them?"
- "What is the difference between post_save and using transaction.on_commit()?"
- "What is dispatch_uid and why does it matter?"

Answer frame:
A strong answer describes signals as a synchronous, in-process pub-sub mechanism for decoupling cross-app side effects, distinguishes them from message queues (no async, no retry, no durability), explains that `post_save` fires before transaction commit and that `transaction.on_commit()` is required for external side effects, and notes that `dispatch_uid` prevents duplicate receiver connections in processes where modules are imported multiple times.

---

## Related Notes

- [[django-project-structure|Django Project Structure]]
- [[django-orm|Django ORM]]
- [[django-celery|Celery with Django]]
- [[django-testing|Testing Django Apps]]
