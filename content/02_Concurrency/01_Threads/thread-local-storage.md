---
title: 10 - Thread Local Storage
description: "threading.local() gives each thread its own independent namespace under the same attribute name — the foundation for per-thread database connections, request contexts in web frameworks, and any state that must not be shared across threads."
tags: [thread-local-storage, threading.local, per-thread-state, flask, django, thread-pool, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-18
---

# Thread Local Storage

> Thread-local storage gives every thread its own private copy of a variable under the same global name — so `connection.db` means "my database connection" to each thread, even though every thread accesses the same `connection` object.

---

## Quick Reference

**Core idea:**
- `threading.local()` creates an object where each thread sees its own attribute namespace — setting `obj.x = 1` in Thread A does not affect `obj.x` in Thread B
- CPython implementation: a `dict` keyed by thread ID, stored inside the local object, accessed on every attribute get/set
- `threading.local` attributes not set in a thread will raise `AttributeError` — there is no cross-thread default
- Use cases: per-thread database connections, per-request context in Flask/Django, per-thread random number generator state
- Thread pool danger: worker threads are reused — stale state from a previous task remains in the thread-local namespace

**Tricky points:**
- Thread-local objects have no `__init__` equivalent per thread — subclass `threading.local` and override `__init__` to initialize attributes per-thread on first access
- Thread-local storage is accessed on every attribute access — it is not free; it performs a dict lookup keyed by thread ID
- In Flask, `flask.g` and the request proxy objects are built on `werkzeug.local.Local`, which extends the thread-local concept to also support greenlets
- Attributes from a thread-local object survive for the lifetime of the thread — in long-lived worker threads, cleanup must be explicit
- `threading.local` is not a context variable — do not confuse with `contextvars.ContextVar`, which scopes to execution contexts including async tasks

---

## What It Is

Imagine a coat check at a conference. Every attendee walks in and gets their own numbered hook. All hooks are mounted on the same wall (the `threading.local` object), but each person's hook holds only their own coat. When Alice reaches for "her coat," she always gets the coat she checked in — not Bob's, even though they both hung their coat on "the conference coat check." From outside, there is one coat check. From inside, each person has exclusive access to their own slot.

Thread-local storage is that coat check. When multiple threads all access the same `threading.local()` object, each thread transparently reads and writes its own private copy of each attribute. The mechanism is built into CPython's threading machinery — there is no lock required, no manual namespace management, no prefix on the attribute name. The separation is automatic and invisible to the code that uses the attributes.

The practical motivation is ubiquitous in server programming. A web server handles many requests concurrently using a thread pool. Each request needs a database connection, a user session object, and a request ID for log correlation. These values must not be shared between requests on different threads — a connection used simultaneously by two threads produces corrupt state or database errors. Thread-local storage lets the framework put `g.db`, `g.user`, and `g.request_id` on a thread-local object so each thread's request handler reads its own values, not another thread's.

---

## How It Actually Works

`threading.local` is implemented in C in CPython (`Modules/_threadmodule.c`). The `localobject` C struct contains a `dict` member. When a thread accesses an attribute on a `threading.local` instance, the implementation calls `PyThreadState_GET()` to get the current thread's state pointer, uses that as a key, and looks up the per-thread namespace dict in the local object's `dict`. Attribute gets and sets then operate on that per-thread dict rather than on the object's `__dict__`.

```python
import threading

local_data = threading.local()

def worker(value):
    local_data.x = value          # each thread sets its own x
    import time; time.sleep(0.01) # simulate work
    print(f"{threading.current_thread().name}: x = {local_data.x}")

threads = [threading.Thread(target=worker, args=(i,)) for i in range(3)]
for t in threads: t.start()
for t in threads: t.join()
# Each thread prints its own value of x — no cross-thread contamination
```

Subclassing `threading.local` to provide per-thread initialization is the standard pattern for complex per-thread state:

```python
class ConnectionLocal(threading.local):
    def __init__(self):
        super().__init__()
        self.connection = None   # called once per thread on first access

local = ConnectionLocal()

def get_connection():
    if local.connection is None:
        local.connection = create_db_connection()
    return local.connection
```

The critical danger with thread pools — `ThreadPoolExecutor` or similar — is that threads are reused across tasks. When Task A finishes, its thread-local attributes remain set. When the same thread picks up Task B, it inherits Task A's thread-local state. In a web server context, this means Request B's handler might find Request A's user object or database connection already in the thread-local namespace. The fix is explicit cleanup: clear the relevant attributes at the end of each task, or use framework-provided per-request context mechanisms (`contextvars.ContextVar`, which Flask 2+ uses internally) that scope context to a logical execution unit rather than to a physical OS thread.

---

## How It Connects

Thread-local storage is the mechanism used by the GIL-bounded threading model to give each thread private state without locking. Understanding the thread lifecycle — how CPython spawns, runs, and joins threads — explains when thread-local state is created and when it is destroyed.

[[threads|Threads]]

Thread pool executors reuse worker threads, which means thread-local state persists between submitted tasks. This interaction between thread-local storage and the executor lifecycle is one of the most common sources of subtle concurrency bugs in Python web applications.

[[thread-pool-executor|ThreadPoolExecutor]]

`contextvars.ContextVar` is the modern alternative for async-compatible context isolation. It scopes to a `Context` object (not a thread), which makes it correct for both threaded and async code — Flask 2+ and Django's async views use `ContextVar` rather than `threading.local` for request context.

[[gil|Global Interpreter Lock]]

---

## Common Misconceptions

Misconception 1: "Thread-local storage means the variable is thread-safe — multiple threads can write without locks."
Reality: Thread-local storage means each thread has its own copy — there is no sharing and therefore no race condition on the per-thread value. But if a thread-local attribute holds a reference to a shared mutable object, that shared object still requires locking. Thread-local storage eliminates sharing of the reference itself, not of the object pointed to.

Misconception 2: "Thread-local attributes persist only for the duration of a single function call."
Reality: Thread-local attributes persist for the lifetime of the thread, not for the lifetime of any particular function. In a thread pool, this means they persist until the pool shuts down — across every task the thread executes.

Misconception 3: "`threading.local` and `contextvars.ContextVar` are interchangeable."
Reality: `threading.local` scopes to OS threads. `contextvars.ContextVar` scopes to execution contexts, which in async code are per-coroutine, not per-thread. In `asyncio`, all coroutines run on the same thread, so `threading.local` would give them all the same value — the wrong behavior. `ContextVar` correctly isolates state per coroutine.

---

## Why It Matters in Practice

Flask's `g` object and Django's per-request context are the canonical real-world examples of thread-local storage. When a request comes in on Thread 3, the framework stores the request object in `thread_local.request`. The entire call stack for that request — view functions, middleware, ORM queries — all read `thread_local.request` and transparently get the right request object without it being passed as a function argument. This is why Flask code can call `flask.request` anywhere without the request being explicitly threaded through every function.

The thread-pool reuse danger is the most common production bug in thread-local usage. An HTTP server that stores a short-lived token in `local.auth_token` during a request must clear it at the end of the request. If the server uses a fixed-size thread pool and a token is not cleared, subsequent requests on the same thread will find the previous token — creating a security vulnerability if the token is used for authorization. Always treat thread-local state in pooled environments as requiring explicit teardown.

---

## Interview Angle

Common question forms:
- "What is thread-local storage and why is it useful?"
- "What is the risk of using `threading.local` with a thread pool?"
- "How does Flask's `g` object work under the hood?"

Answer frame:
`threading.local()` gives each thread its own dict keyed by thread ID under the same attribute name. It is used for per-thread database connections, request context, and any state that must not be shared. Thread pool risk: threads are reused — state from Task A persists into Task B on the same thread; fix with explicit cleanup or `ContextVar`. Flask's `g` is built on `werkzeug.local.Local` (a thread-local wrapper) — each request thread reads its own `g`, enabling `flask.request` as a global-feeling proxy.

---

## Related Notes

- [[threads|Threads]]
- [[thread-pool-executor|ThreadPoolExecutor]]
- [[gil|Global Interpreter Lock]]
- [[race-conditions|Race Conditions]]
- [[locks|Locks]]
