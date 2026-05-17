---
title: HTTP Basics
description: HTTP is the request-response protocol that powers the web — understanding its structure, methods, headers, and status codes is the prerequisite for understanding every Python web framework, from WSGI to FastAPI.
tags: [http, protocol, request, response, headers, status-codes, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# HTTP Basics

> HTTP is the request-response protocol that powers the web — understanding its structure, methods, headers, and status codes is the prerequisite for understanding every Python web framework, from WSGI to FastAPI.

---

## Quick Reference

**Core idea:**
- HTTP is a **stateless, text-based, request-response protocol** over TCP
- A request has: **method** (GET/POST/PUT/DELETE/PATCH) + **path** + **headers** + optional **body**
- A response has: **status code** (200/404/500…) + **headers** + optional **body**
- **Headers** carry metadata: `Content-Type`, `Authorization`, `Content-Length`, `Accept`, `Cookie`, `Set-Cookie`
- HTTP/1.1 uses persistent connections by default; HTTP/2 multiplexes many requests over one TCP connection

**Tricky points:**
- HTTP is **stateless** — the server has no memory of previous requests; state (sessions, auth) must be carried in cookies, headers, or request bodies
- `GET` requests **should not** have a body (technically allowed, but many clients/proxies strip it) — use query parameters instead
- `PUT` replaces the entire resource; `PATCH` applies a partial update — they are not interchangeable
- A `200 OK` with an error message in the body is wrong — use `4xx`/`5xx` status codes to signal errors
- `Content-Type: application/json` tells the **receiver** what format the body is in; `Accept: application/json` tells the **server** what format the client wants back

---

## What It Is

Think of the postal system. You write a letter (the request), put it in an envelope with a specific format (the protocol), and address it to a recipient (the server). The recipient reads your letter and sends a reply (the response) in the same standardized envelope format. Both sides follow the same rules for how envelopes are addressed and structured, so any sender can communicate with any recipient. HTTP is that standardized envelope format for the web. Every web browser, every API client, every Python web framework speaks HTTP — the same protocol, the same rules.

HTTP stands for HyperText Transfer Protocol. It is a protocol for communication between a client (typically a browser or an API client like `requests` or `httpx`) and a server (a Python web application, an Nginx server, a cloud service). The client sends a request; the server sends a response. That exchange is the entirety of HTTP. After the response is sent, the server forgets the client existed — HTTP is stateless. Each new request arrives as if from a stranger.

Every HTTP request has three essential parts. The first is the method, which describes the intent: `GET` requests data, `POST` creates something, `PUT` replaces something, `DELETE` removes something, `PATCH` partially updates something. The second is the URL — the address of the resource being requested, including the path and optional query string. The third is a set of headers — key-value pairs that carry metadata: what content type the body is, what authentication credentials are being sent, what formats the client accepts. Optionally, a request also has a body — the actual data being sent, used with `POST`, `PUT`, and `PATCH`.

---

## How It Actually Works

An HTTP exchange over TCP begins with a connection being established. For HTTP/1.1, the client opens a TCP socket to the server's IP and port (80 for HTTP, 443 for HTTPS), performs a TCP handshake, and then sends the HTTP request as a stream of bytes. The request starts with the request line: `GET /path HTTP/1.1`. Below that, each header is on its own line as `Name: Value`. A blank line separates the headers from the body. The server reads bytes until it has the full request, processes it, and writes back the response in the same format: status line (`HTTP/1.1 200 OK`), headers, blank line, body.

HTTP/1.1 introduced persistent connections (`Connection: keep-alive`). After a response, the TCP connection stays open for the next request to the same server, avoiding the cost of a new TCP handshake for every resource. HTTP/2 went further: it multiplexes multiple requests and responses over a single TCP connection as independent streams, allowing a browser to request ten CSS files simultaneously without waiting for each to complete before starting the next.

HTTPS adds TLS (Transport Layer Security) over the TCP layer. The client and server negotiate a cryptographic session before any HTTP bytes are exchanged. From the application's perspective, the HTTP protocol is identical — the TLS layer handles encryption and decryption transparently. Python's `ssl` module wraps standard sockets with TLS; frameworks like FastAPI rely on the server (Uvicorn, Gunicorn) to handle TLS, so application code sees plain HTTP internally.

Status codes are organized into ranges by meaning. `1xx` is informational (rare in practice). `2xx` is success: `200 OK`, `201 Created`, `204 No Content`. `3xx` is redirection: `301 Moved Permanently`, `302 Found`, `304 Not Modified`. `4xx` is client error: `400 Bad Request`, `401 Unauthorized`, `403 Forbidden`, `404 Not Found`, `422 Unprocessable Entity`. `5xx` is server error: `500 Internal Server Error`, `502 Bad Gateway`, `503 Service Unavailable`. The choice of status code is the primary signal about what happened — a correct status code makes an API debuggable; a wrong one makes it opaque.

---

## How It Connects

WSGI (Web Server Gateway Interface) is the Python specification that defines how a web server passes an HTTP request to a Python application. To understand WSGI, you must first understand what an HTTP request looks like — what fields it has, what the method and path mean, what headers carry. WSGI translates an HTTP request into a Python dictionary.
[[wsgi|WSGI]]

ASGI is the async successor to WSGI, designed for HTTP/2 and WebSockets. It extends the HTTP model to include long-lived connections that do not fit the simple request-response model. Understanding basic HTTP is the prerequisite for understanding where ASGI extends it.
[[asgi|ASGI]]

---

## Common Misconceptions

Misconception 1: "GET and POST are the only HTTP methods that matter."
Reality: REST APIs rely on the full method vocabulary. `PUT` and `PATCH` have distinct semantics — `PUT` replaces a resource wholesale; `PATCH` updates specific fields. `DELETE` removes a resource. `HEAD` retrieves only the response headers without the body (useful for checking if a resource exists or has changed). Using `POST` for everything (as some older APIs did) makes the intent of each endpoint ambiguous and breaks caching, which HTTP's method semantics enable.

Misconception 2: "A 200 status code means everything worked correctly."
Reality: Status codes reflect the HTTP-level outcome, not necessarily the business-logic outcome. An API that returns `200 OK` with `{"error": "user not found"}` in the body is misusing the protocol. A client cannot distinguish success from failure without parsing the body, which breaks HTTP-aware tools like reverse proxies, load balancers, and monitoring systems that use status codes for routing and alerting. Use `404` when a resource is not found, `422` when input validation fails, `500` when an unexpected error occurs.

---

## Why It Matters in Practice

Every Python web framework — Flask, Django, FastAPI — is ultimately a machine for translating HTTP requests into Python function calls and Python return values back into HTTP responses. Knowing HTTP means knowing what the framework is doing beneath its abstractions. When a FastAPI route handler receives a `Request` object, that object's attributes map directly to parts of the HTTP request: `request.method`, `request.url`, `request.headers`, `request.body`. When you return a response, FastAPI is constructing an HTTP response with a status code, headers, and a JSON body.

HTTP knowledge also makes debugging faster. When an API call fails, the status code tells you who is at fault (4xx = client; 5xx = server) and roughly why (401 = missing auth; 404 = wrong path; 422 = bad request data; 500 = server crash). The `Content-Type` header tells you how to parse the body. The `Location` header tells you where a `201 Created` resource lives. Reading raw HTTP is a skill that pays off every time you use `curl`, read server logs, or inspect browser developer tools.

---

## Interview Angle

Common question forms:
- "What is the difference between GET and POST?"
- "What do HTTP status codes mean?"
- "What is the difference between PUT and PATCH?"

Answer frame: Define HTTP as a stateless request-response protocol over TCP. Describe the parts of a request (method, URL, headers, optional body) and response (status code, headers, optional body). Explain method semantics: GET retrieves (no body), POST creates, PUT replaces, PATCH partially updates, DELETE removes. Walk through status code ranges: 2xx success, 3xx redirect, 4xx client error, 5xx server error. Emphasize statelessness: each request is independent; session state must be carried explicitly.

---

## Related Notes

- [[wsgi|WSGI]]
- [[asgi|ASGI]]
