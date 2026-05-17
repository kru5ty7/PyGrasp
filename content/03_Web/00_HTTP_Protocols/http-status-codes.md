---
title: 03 - HTTP Status Codes
description: "HTTP status codes are 3-digit integers in 5 classes: 1xx informational, 2xx success, 3xx redirection, 4xx client error, 5xx server error — the most important are 200 OK, 201 Created, 204 No Content, 301/302 redirect, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 422 Unprocessable Entity, 500 Internal Server Error."
tags: [http, status-codes, 200, 201, 404, 422, 500, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# HTTP Status Codes

> HTTP status codes are 3-digit integers in 5 classes: 1xx informational, 2xx success, 3xx redirection, 4xx client error, 5xx server error — the most important are 200 OK, 201 Created, 204 No Content, 301/302 redirect, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 422 Unprocessable Entity, 500 Internal Server Error.

---

## Quick Reference

**Core idea:**
- `1xx` — informational (rare in APIs): `100 Continue`, `101 Switching Protocols` (WebSocket upgrade)
- `2xx` — success: `200 OK`, `201 Created` (POST success), `204 No Content` (DELETE success, no body)
- `3xx` — redirection: `301 Moved Permanently` (update bookmarks), `302 Found` (temporary), `304 Not Modified` (cache hit)
- `4xx` — client error: `400 Bad Request`, `401 Unauthorized` (not authenticated), `403 Forbidden` (authenticated but not allowed), `404 Not Found`, `409 Conflict`, `422 Unprocessable Entity`
- `5xx` — server error: `500 Internal Server Error`, `502 Bad Gateway`, `503 Service Unavailable`, `504 Gateway Timeout`

**Tricky points:**
- `401 Unauthorized` is a misnomer — it means "not authenticated" (no valid credentials); `403 Forbidden` means "authenticated but not authorized"
- `404 Not Found` vs `403 Forbidden`: returning 404 for resources the user isn't allowed to see hides the existence of the resource (intentional security pattern)
- `422 Unprocessable Entity` is used by FastAPI for validation errors — the request was syntactically valid but semantically wrong (e.g., a field value out of range)
- `204 No Content` must have no response body — sending a body with 204 is a protocol violation
- `503 Service Unavailable` should include a `Retry-After` header indicating when to retry

---

## What It Is

Status codes are the server's response to the question "how did it go?" They are a standardized 3-digit contract between server and client. The first digit encodes the class; the remaining two encode the specific condition. Clients, proxies, and caches use the class to make decisions without reading the body — a `3xx` is always a redirect; a `5xx` is always a server problem.

The class system allows generic handling: "retry on any 5xx" is a valid strategy regardless of the specific code. This is why following the standard matters — non-standard use (e.g., returning `200` for an error with an error object in the body) breaks this.

---

## How It Actually Works

FastAPI status code usage:
```python
from fastapi import FastAPI, HTTPException, status

app = FastAPI()

@app.get("/users/{id}", status_code=status.HTTP_200_OK)
async def get_user(id: int):
    user = db.get(id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@app.post("/users", status_code=status.HTTP_201_CREATED)
async def create_user(user: UserCreate):
    new_user = db.create(user)
    return new_user

@app.delete("/users/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(id: int):
    db.delete(id)
    # no return value — 204 No Content
```

Error response decision tree:
```
Did the client send bad data?        → 400 or 422
Does the client need to log in?      → 401
Is the client logged in but blocked? → 403
Does the resource not exist?         → 404
Does creating it conflict with existing data? → 409
Did the server crash?                → 500
Is a dependency down?                → 502 or 503
```

---

## How It Connects

HTTP status codes are returned as part of the HTTP response — understanding the full request-response cycle gives context for when and how status codes are set.
[[http-basics|HTTP Basics]]

FastAPI raises `HTTPException(status_code=..., detail=...)` to return specific status codes from route handlers.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Use 200 for everything and put the error in the body."
Reality: Many clients, middleware, and monitoring tools key off status codes to determine success/failure. Returning 200 for errors breaks retry logic, alerting, and log aggregation. Use the appropriate 4xx/5xx code.

Misconception 2: "401 means the user isn't allowed."
Reality: 401 means the user has not been authenticated (no token, expired token, wrong credentials). 403 means the user IS authenticated but lacks permission. The naming is historically confusing.

---

## Why It Matters in Practice

Proper status codes enable:
- **Retry logic**: clients retry on 503 with `Retry-After`, not on 400 (retrying a bad request is pointless).
- **Caching**: 304 signals "use your cached copy." 200 updates the cache.
- **Monitoring**: alerting on 5xx rate separate from 4xx rate.
- **Security**: returning 404 (instead of 403) for resources the requester can't see hides their existence.

---

## Interview Angle

Common question forms:
- "What is the difference between 401 and 403?"
- "What status code do you return for a POST that creates a resource?"

Answer frame: **401** = not authenticated (no valid credentials). **403** = authenticated but not authorized (no permission). POST creates return **201 Created**. DELETE with no body returns **204 No Content**. Validation errors return **422 Unprocessable Entity** (FastAPI default). Server errors are **5xx**. Use codes consistently — don't return 200 for errors.

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[http-methods|HTTP Methods]]
- [[fastapi|FastAPI]]
- [[rest|REST]]
