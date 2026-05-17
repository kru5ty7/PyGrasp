---
title: Response Models
description: "`response_model` in FastAPI declares the shape of the response — FastAPI serializes the return value to match the model, excluding fields not in the model; `response_model_exclude_unset=True` omits fields with default values that weren't set; use separate request and response models to control what is exposed."
tags: [fastapi, response_model, response-model, serialization, exclude, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Response Models

> `response_model` in FastAPI declares the shape of the response — FastAPI serializes the return value to match the model, excluding fields not in the model; `response_model_exclude_unset=True` omits fields with default values that weren't set; use separate request and response models to control what is exposed.

---

## Quick Reference

**Core idea:**
- `@app.get("/users/{id}", response_model=UserResponse)` — FastAPI serializes the return value using `UserResponse`
- Fields in the return value but NOT in `response_model` are excluded from the JSON output
- `response_model_exclude_unset=True` — omit fields that have defaults and weren't explicitly set on the returned model
- `response_model=list[UserResponse]` — works for lists
- `response_model=None` — disables response validation/serialization (return raw dict or `Response`)

**Tricky points:**
- `response_model` does NOT cause validation of the returned object's types — it only filters fields and handles serialization; the handler can return anything that Pydantic can coerce
- If the handler returns a Pydantic model of a different type than `response_model`, FastAPI calls `model_validate()` on the return value with the response model's class — this can fail if required fields are missing
- `response_model_include` / `response_model_exclude` — override which fields appear in the response (ad-hoc alternative to a separate model)
- Returning `None` for a `response_model=SomeModel` endpoint causes `ValidationError` — return `Response(status_code=204)` for no-content responses
- `JSONResponse(content=data)` bypasses response model validation — use when you need full control over the response

---

## What It Is

`response_model` separates input models from output models — a common need when the database model has fields (password hash, internal IDs, audit timestamps) that should never be sent to clients. By declaring a separate response model with only the public fields, FastAPI automatically strips the rest.

It also drives OpenAPI documentation — the response schema in Swagger UI comes from `response_model`.

---

## How It Actually Works

Input vs output models:
```python
class UserCreate(BaseModel):
    email: str
    password: str

class UserInDB(BaseModel):
    id: int
    email: str
    password_hash: str  # never expose this
    created_at: datetime

class UserResponse(BaseModel):
    id: int
    email: str
    created_at: datetime
    # no password_hash

@app.post("/users", status_code=201, response_model=UserResponse)
async def create_user(data: UserCreate):
    user = await db.create_user(data.email, hash(data.password))
    return user  # FastAPI converts UserInDB → UserResponse, dropping password_hash
```

`response_model_exclude_unset=True` for partial responses:
```python
class UserPartial(BaseModel):
    id: int
    email: str
    name: str = ""
    bio: str = ""

@app.get("/users/{id}", response_model=UserPartial, response_model_exclude_unset=True)
async def get_user_partial(id: int):
    # If the user has no bio, it won't appear in the response
    return UserPartial(id=id, email="alice@example.com")
# Response: {"id": 1, "email": "alice@example.com"}  (name and bio omitted)
```

Dynamic response models with `Union`:
```python
@app.get("/items/{id}", response_model=ItemFull | ItemSummary)
async def get_item(id: int, summary: bool = False):
    if summary:
        return ItemSummary(id=id, name="Widget")
    return ItemFull(id=id, name="Widget", description="...", price=9.99)
```

---

## How It Connects

Response models use Pydantic serialization — `model_dump()` is called on the return value with the response model's schema applied.
[[serialization|Serialization and Deserialization]]

Request bodies (input models) and response models are the two sides of a FastAPI endpoint's type contract — together they define the full API surface.
[[request-body|Request Body]]

---

## Common Misconceptions

Misconception 1: "`response_model` validates the handler's return value."
Reality: `response_model` serializes and filters the return value — it does not validate that the returned object satisfies all constraints. A handler returning `UserResponse(email="notanemail")` will not raise a validation error even if `email` has an email validator, because the returned object is already a Pydantic model instance.

Misconception 2: "Returning a dict that contains extra keys causes an error."
Reality: Extra keys in the returned dict are silently ignored by `response_model` — only the fields declared in the response model appear in the output. This is the feature: a database row with 20 columns can be returned, and `response_model` selects the 5 public ones.

---

## Why It Matters in Practice

Pattern: three model tiers per entity:
```python
class UserBase(BaseModel):
    email: str
    name: str

class UserCreate(UserBase):
    password: str          # write-only: received at creation

class UserUpdate(BaseModel):
    email: str | None = None
    name: str | None = None  # all optional for PATCH

class UserResponse(UserBase):
    id: int
    created_at: datetime   # read-only: set by server
    # no password
```

This is the standard FastAPI pattern: base model with shared fields, create model adds write-only fields, update model has all optional fields, response model has read-only fields.

---

## Interview Angle

Common question forms:
- "How do you prevent sensitive fields from appearing in API responses?"
- "What is `response_model` in FastAPI?"

Answer frame: Declare `response_model=UserResponse` on the route — FastAPI serializes the return value using `UserResponse`, omitting any fields not declared on it. Pattern: create a response model that excludes sensitive fields (`password_hash`); return the DB model; FastAPI does the field filtering. `response_model_exclude_unset=True` omits default-value fields that weren't explicitly set.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[serialization|Serialization and Deserialization]]
- [[request-body|Request Body]]
- [[pydantic|Pydantic]]
