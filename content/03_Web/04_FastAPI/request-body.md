---
title: 09 - Request Body
description: "FastAPI reads request bodies as Pydantic models — declare a parameter with a Pydantic model type and FastAPI automatically parses the JSON body, validates it, and passes a typed model instance to the handler; `Body()` provides additional control for metadata and multiple body parameters."
tags: [fastapi, request-body, pydantic, Body, JSON, form-data, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Request Body

> FastAPI reads request bodies as Pydantic models — declare a parameter with a Pydantic model type and FastAPI automatically parses the JSON body, validates it, and passes a typed model instance to the handler; `Body()` provides additional control for metadata and multiple body parameters.

---

## Quick Reference

**Core idea:**
- Declare a Pydantic model parameter → FastAPI reads JSON body, validates, and injects the model instance
- `Body(embed=True)` — wraps the parameter in a key (`{"item": {...}}` instead of `{...}`)
- `Body(...)` — marks a body field as required; can add `description`, `examples`
- `Form(...)` — reads from form data (`Content-Type: application/x-www-form-urlencoded`)
- `File(...)` / `UploadFile` — reads uploaded files

**Tricky points:**
- FastAPI distinguishes body from query/path by type: Pydantic model → body; scalar (`int`, `str`) → path/query; `Body()` explicitly forces a scalar to be read from the body
- Multiple body parameters: FastAPI wraps each in a dict key automatically: `{"item": {...}, "user": {...}}`
- `UploadFile` gives async streaming access — `await file.read()` reads the whole file; for large files, read in chunks with `file.read(chunk_size)`
- Form data and JSON body cannot coexist in the same endpoint — you can't have both `Form()` and a Pydantic body parameter in the same handler
- `Content-Type` must be `application/json` for Pydantic body parsing — sending `text/plain` with a JSON string fails with 422

---

## What It Is

The request body carries structured data from client to server — the payload of POST/PUT/PATCH requests. In FastAPI, you declare the expected shape as a Pydantic model, and the framework handles parsing, validation, and error responses automatically.

This is distinct from path and query parameters (which are scalars in the URL) — the body can be an arbitrarily complex nested structure, and Pydantic validates the entire tree before the handler sees it.

---

## How It Actually Works

Basic body:
```python
from pydantic import BaseModel

class CreateItem(BaseModel):
    name: str
    price: float
    quantity: int = 1

@app.post("/items", status_code=201)
async def create_item(item: CreateItem):
    # item is fully validated; item.name, item.price, item.quantity are correct types
    return item

# POST /items
# {"name": "Widget", "price": 9.99}
# → CreateItem(name="Widget", price=9.99, quantity=1)
```

Multiple body parameters:
```python
class Item(BaseModel):
    name: str

class Metadata(BaseModel):
    source: str

@app.post("/items")
async def create_item(item: Item, meta: Metadata):
    ...
# Expects: {"item": {"name": "Widget"}, "meta": {"source": "api"}}
```

Mixed path + body:
```python
@app.put("/items/{item_id}")
async def update_item(item_id: int, item: UpdateItem):
    # item_id from path; item from body
    ...
```

File upload:
```python
from fastapi import UploadFile, File

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    content = await file.read()
    return {"filename": file.filename, "size": len(content)}
```

Form data:
```python
from fastapi import Form

@app.post("/login")
async def login(username: str = Form(...), password: str = Form(...)):
    ...
```

---

## How It Connects

FastAPI infers body parameters from Pydantic model type annotations — Pydantic does the actual parsing and validation.
[[pydantic|Pydantic]]

Path and query parameters are inferred from scalar types (non-Pydantic); understanding the distinction prevents confusion about which source FastAPI reads from.
[[path-and-query-params|Path and Query Parameters]]

---

## Common Misconceptions

Misconception 1: "A single Pydantic model in the handler automatically wraps in a key."
Reality: A single Pydantic model parameter (`item: Item`) expects a flat JSON object: `{"name": "Widget"}`. Only multiple Pydantic parameters trigger wrapping: `item: Item, user: User` expects `{"item": {...}, "user": {...}}`.

Misconception 2: "You can send both form data and JSON in the same request."
Reality: A request has one `Content-Type` — it's either `application/json` OR `application/x-www-form-urlencoded` (form) OR `multipart/form-data` (file upload). FastAPI route parameters must match the content type.

---

## Why It Matters in Practice

```python
class CreateUserRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    role: Literal["admin", "user", "viewer"] = "user"

@app.post("/users", status_code=201, response_model=UserResponse)
async def create_user(
    request: CreateUserRequest,
    current_user: User = Depends(require_admin),
):
    # request is validated: email is a real email, password >= 8 chars
    user = await create_user_in_db(request)
    return user
```

FastAPI rejects invalid bodies with a detailed 422 error before the handler runs — no manual validation code needed.

---

## Interview Angle

Common question forms:
- "How do you read a JSON request body in FastAPI?"
- "How do you handle file uploads in FastAPI?"

Answer frame: Declare a Pydantic model parameter — FastAPI reads and validates the JSON body automatically. For files: `UploadFile = File(...)`. For form data: `str = Form(...)`. Path params (scalars in path template) + query params (scalars not in template) + body (Pydantic model) can coexist in one handler. Invalid body → automatic 422 with field-level error details.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[pydantic|Pydantic]]
- [[path-and-query-params|Path and Query Parameters]]
- [[response-model|Response Models]]
