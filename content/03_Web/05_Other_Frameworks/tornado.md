---
title: 03 - Tornado
description: "Tornado is a pre-asyncio async web framework that popularized non-blocking Python web development and still sees use in legacy codebases and WebSocket-heavy services."
tags: [tornado, async, web-framework, websockets, ioloop, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Tornado

> Tornado is the Python web framework that proved non-blocking I/O was possible in Python before asyncio existed  -  now integrated with asyncio, it remains relevant in legacy systems and for its native WebSocket support.

---

## Quick Reference

**Core idea:**
- Non-blocking async web framework and networking library, originally built by FriendFeed (acquired by Facebook in 2009)
- Uses `tornado.ioloop.IOLoop` which integrates with Python's `asyncio` event loop since Tornado 5+
- Route handlers subclass `tornado.web.RequestHandler`  -  `get()`, `post()` are methods, not decorated functions
- Native WebSocket support via `tornado.websocket.WebSocketHandler` with `on_message`, `open`, and `on_close` callbacks
- `tornado.httpclient.AsyncHTTPClient` provides a built-in async HTTP client
- WSGI-based apps can be run inside Tornado via `tornado.wsgi.WSGIContainer`

**Tricky points:**
- Tornado's handler class model is fundamentally different from FastAPI/Flask decorator-based routing  -  porting code between frameworks requires restructuring, not just syntax changes
- Pre-Tornado-5 code using `@tornado.gen.coroutine` and `yield` is still common in legacy codebases; these are compatible with asyncio but look different from `async/await`
- `self.write()` buffers output; `self.finish()` flushes it and ends the response  -  forgetting `finish()` in some code paths causes hanging requests
- Tornado's `IOLoop.current()` and asyncio's event loop are the same object since Tornado 5  -  mixing them is safe but can confuse debugging
- Running Tornado with multiple processes uses its own `tornado.process.fork_processes()`, not Gunicorn workers

---

## What It Is

Consider the historical moment: in 2009, Python web development meant Apache + mod_wsgi + Django or Flask. Every request tied up an OS thread or process for its entire duration, and handling ten thousand simultaneous long-lived connections  -  the "C10K problem"  -  was computationally expensive or impractical. Node.js was emerging as evidence that a single-threaded, event-driven model could handle enormous concurrency. FriendFeed, a social aggregation startup, faced exactly this problem: their product aggregated real-time feeds from dozens of sources per user, requiring many simultaneous long-lived connections per request. They built Tornado as their solution in Python, open-sourced it when Facebook acquired them, and demonstrated that Python could do non-blocking I/O effectively.

Tornado's architecture centres on an event loop  -  the `IOLoop`  -  that manages a pool of non-blocking sockets and dispatches callbacks when I/O is ready. This is the same conceptual model that Node.js uses and that Python's asyncio later standardized. Before asyncio existed (Python 3.4, 2014), Tornado's IOLoop was the primary way to write high-concurrency Python code. Tornado introduced its own coroutine system using generator-based coroutines (`@gen.coroutine` / `yield`), which predated Python's native `async/await` syntax but worked on the same principle of suspending execution while waiting for I/O.

Since Tornado 5 (2018), `tornado.ioloop.IOLoop` wraps Python's standard `asyncio` event loop. Tornado coroutines and asyncio coroutines are now interoperable, and `async def` / `await` is the preferred syntax for new Tornado code. This convergence means Tornado applications can use asyncio libraries directly, and asyncio applications can use Tornado's higher-level networking utilities. The framework did not become obsolete by asyncio's arrival; instead, it became part of the broader asyncio ecosystem while retaining its unique features, particularly the mature WebSocket implementation and the WSGI container bridge.

---

## How It Actually Works

Tornado's routing and handler model uses explicit URL-to-class mappings and method-based dispatch:

```python
import tornado.ioloop
import tornado.web

class MainHandler(tornado.web.RequestHandler):
    async def get(self):
        name = self.get_argument("name", "World")
        self.write(f"Hello, {name}")

class UserHandler(tornado.web.RequestHandler):
    async def get(self, user_id):
        self.set_header("Content-Type", "application/json")
        self.write({"id": int(user_id), "name": "Alice"})

    async def post(self, user_id):
        data = tornado.escape.json_decode(self.request.body)
        self.write({"updated": True})

app = tornado.web.Application([
    (r"/", MainHandler),
    (r"/users/([0-9]+)", UserHandler),
])

if __name__ == "__main__":
    app.listen(8888)
    tornado.ioloop.IOLoop.current().start()
```

URL routing uses regular expressions, with capture groups passed as positional arguments to handler methods. This is more explicit but more verbose than FastAPI's path parameter syntax.

Tornado's built-in WebSocket support is one of its strongest remaining advantages. `WebSocketHandler` provides a clean callback model:

```python
class EchoWebSocket(tornado.websocket.WebSocketHandler):
    def open(self):
        print("New connection")

    def on_message(self, message):
        self.write_message(f"Echo: {message}")

    def on_close(self):
        print("Connection closed")
```

This is simpler and more battle-tested than many WebSocket abstractions built on top of more recent frameworks. Tornado has shipped production WebSocket code since 2009 and handles edge cases (pings, fragmented messages, connection timeouts) that newer implementations sometimes miss in early versions.

---

## How It Connects

Tornado's WebSocket handler model is a practical alternative to FastAPI's WebSocket support and to the standalone `websockets` library  -  all three solve the same problem with different API styles.

[[websockets|WebSockets]]

The async/await note provides the modern syntax used in Tornado 5+ handlers, replacing the older `@gen.coroutine` style that appears in legacy Tornado code.

[[async-await|Async/Await]]

The framework comparison note situates Tornado among all Python web frameworks, explaining where its historical significance and remaining strengths make it the right choice versus where FastAPI or Starlette are superior.

[[framework-comparison|Python Web Framework Comparison]]

---

## Common Misconceptions

Misconception 1: "Tornado is deprecated now that asyncio exists."
Reality: Tornado is actively maintained and integrates with asyncio rather than competing with it. The IOLoop is now a thin wrapper over the asyncio event loop. Tornado's WebSocket implementation, networking utilities, and WSGI container remain useful and continue to receive updates.

Misconception 2: "Tornado cannot use modern asyncio libraries."
Reality: Since Tornado 5, `asyncio.coroutine` and `tornado.gen.coroutine` are interoperable. Tornado handlers can `await` asyncio-based libraries (aiohttp, asyncpg, etc.) directly. The IOLoop and asyncio event loop are the same object.

Misconception 3: "I should rewrite legacy Tornado code to FastAPI immediately."
Reality: A working Tornado service that handles its load reliably does not need to be rewritten. Rewrites introduce risk. The correct trigger for migration is when Tornado's limitations (smaller ecosystem, class-based routing complexity) create actual friction  -  not simply because a newer framework exists.

---

## Why It Matters in Practice

Tornado matters primarily in two scenarios. The first is legacy system maintenance: many Python services built between 2010 and 2016 use Tornado, and developers inheriting these systems need to understand the `IOLoop`, the handler class model, and the `@gen.coroutine` pattern. The second is WebSocket-heavy applications where Tornado's mature, well-tested WebSocket implementation provides confidence that edge cases are handled correctly. A real-time notification service or a long-lived connection management layer built on `WebSocketHandler` benefits from over a decade of production hardening.

For new Python projects, FastAPI or Starlette is the better starting point in almost all cases. They offer the same async foundation with a more ergonomic API, better tooling, and larger ecosystems. Tornado's main historical contribution is demonstrating that Python's async story was viable, which directly influenced asyncio's design and the async-first Python web frameworks that followed.

---

## Interview Angle

Common question forms:
- "What is Tornado and what problem did it originally solve?"
- "How does Tornado's routing model differ from Flask's?"
- "Can Tornado and asyncio code be mixed?"

Answer frame:
A strong answer to the first question describes the C10K context  -  handling many simultaneous long-lived connections  -  and explains Tornado's event loop model as the solution, noting that this was pre-asyncio. For routing differences, the class-based `RequestHandler` model with URL regex mapping contrasts with Flask/FastAPI's decorator-on-function approach. For the asyncio compatibility question, the correct answer is yes, completely, since Tornado 5  -  and a strong answer explains that `IOLoop.current()` and `asyncio.get_event_loop()` return the same object.

---

## Related Notes

- [[websockets|WebSockets]]
- [[async-await|Async/Await]]
- [[asyncio|asyncio]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[framework-comparison|Python Web Framework Comparison]]
