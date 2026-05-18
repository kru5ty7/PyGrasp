---
title: 05 - Serialization and Deserialization
description: "Serialization converts Python objects to a transmissible format (JSON, bytes); deserialization converts back  -  Pydantic's `model_dump()` serializes to dict and `model_dump_json()` to JSON string; `model.model_validate(data)` deserializes; custom serializers with `@field_serializer` control field output."
tags: [serialization, deserialization, pydantic, model_dump, model_validate, json, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Serialization and Deserialization

> Serialization converts Python objects to a transmissible format (JSON, bytes); deserialization converts back  -  Pydantic's `model_dump()` serializes to dict and `model_dump_json()` to JSON string; `model.model_validate(data)` deserializes; custom serializers with `@field_serializer` control field output.

---

## Quick Reference

**Core idea:**
- `model.model_dump()`  -  serialize to Python dict
- `model.model_dump_json()`  -  serialize to JSON string (bytes)
- `Model.model_validate(data)`  -  deserialize from dict (with validation)
- `Model.model_validate_json(json_str)`  -  deserialize from JSON string
- `@field_serializer("field_name")`  -  custom serialization for a specific field

**Tricky points:**
- `model_dump(exclude_none=True)`  -  omit fields with `None` values; useful for PATCH requests where you don't want to send unchanged fields
- `model_dump(mode="json")`  -  applies JSON-compatible serialization (e.g., `datetime` -> ISO 8601 string) even in the dict output
- `by_alias=True`  -  use field aliases in the output (needed when a model has `alias=` set on fields)
- Python `datetime` objects are not JSON-serializable by default  -  Pydantic converts them to ISO 8601 strings in `model_dump_json()`; raw `json.dumps()` on a `datetime` raises `TypeError`
- `model_dump(include={"field1", "field2"})` / `exclude={"password"}`  -  whitelist/blacklist fields in output

---

## What It Is

Serialization and deserialization are the conversions between in-memory Python objects and a wire format (JSON, bytes). Every time a FastAPI handler returns a Pydantic model, the model is serialized to JSON. Every time a request body arrives, the JSON bytes are deserialized into a Pydantic model.

Understanding this process matters when: you need to exclude sensitive fields from output, handle types that aren't JSON-native (datetime, UUID, Decimal), or produce different output shapes for different clients.

---

## How It Actually Works

Basic serialization:
```python
from pydantic import BaseModel
from datetime import datetime
from uuid import UUID

class User(BaseModel):
    id: UUID
    name: str
    created_at: datetime
    password_hash: str

user = User(id=UUID("..."), name="Alice", created_at=datetime.now(), password_hash="$2b$...")

# To dict:
user.model_dump()
# {'id': UUID('...'), 'name': 'Alice', 'created_at': datetime(...), 'password_hash': '...'}

# To JSON (datetime -> ISO string, UUID -> string):
user.model_dump_json()
# '{"id":"...","name":"Alice","created_at":"2026-01-01T12:00:00","password_hash":"..."}'

# Exclude sensitive fields:
user.model_dump(exclude={"password_hash"})
# {'id': UUID('...'), 'name': 'Alice', 'created_at': datetime(...)}
```

Custom serialization with `@field_serializer`:
```python
from pydantic import field_serializer
from decimal import Decimal

class Price(BaseModel):
    amount: Decimal
    currency: str
    
    @field_serializer("amount")
    def serialize_amount(self, v: Decimal) -> str:
        return f"{v:.2f}"  # Decimal -> "19.99" instead of Decimal('19.99')

Price(amount=Decimal("19.99"), currency="USD").model_dump_json()
# '{"amount":"19.99","currency":"USD"}'
```

Deserialization:
```python
data = {"id": "a1b2c3d4-...", "name": "Alice", "created_at": "2026-01-01T12:00:00", "password_hash": "..."}
user = User.model_validate(data)  # string ID -> UUID, string datetime -> datetime

json_str = '{"id": "a1b2c3d4-...", "name": "Alice", ...}'
user = User.model_validate_json(json_str)
```

Response model in FastAPI  -  serialize and filter:
```python
class UserResponse(BaseModel):
    id: UUID
    name: str
    created_at: datetime
    # no password_hash  -  excluded by using a separate response model

@app.get("/users/{id}", response_model=UserResponse)
async def get_user(id: int):
    user = await db.get_user(id)
    return user  # FastAPI calls model_dump() then serializes to JSON
```

---

## How It Connects

Pydantic models drive serialization  -  `model_dump()` and `model_dump_json()` are core Pydantic methods.
[[pydantic|Pydantic]]

In FastAPI, `response_model` triggers serialization of the handler's return value  -  only the fields on the response model are included in the output.
[[response-model|Response Models]]

---

## Common Misconceptions

Misconception 1: "Pydantic's `model_dump()` produces JSON-safe output."
Reality: `model_dump()` produces a Python dict which may contain non-JSON-serializable types (`UUID`, `datetime`, `Decimal`). To get JSON-safe values, use `model_dump(mode="json")` or `model_dump_json()`.

Misconception 2: "Using `response_model` in FastAPI automatically excludes sensitive fields."
Reality: `response_model` only includes fields that are on the response model class  -  it is your responsibility to define a response model that excludes sensitive fields. If you return the full database model and set `response_model=UserResponse`, only the fields declared on `UserResponse` appear in the output.

---

## Why It Matters in Practice

PATCH endpoint with `exclude_unset`:
```python
class UserUpdate(BaseModel):
    name: str | None = None
    email: str | None = None

@app.patch("/users/{id}")
async def update_user(id: int, update: UserUpdate):
    # exclude_unset: only includes fields the client actually sent
    # avoids overwriting fields the client didn't mention with None
    changes = update.model_dump(exclude_unset=True)
    await db.update_user(id, changes)
```

`exclude_unset=True` is the standard pattern for PATCH endpoints  -  it distinguishes "client sent null" from "client didn't mention this field."

---

## Interview Angle

Common question forms:
- "How do you convert a Pydantic model to JSON?"
- "How do you exclude sensitive fields from API responses?"

Answer frame: `model_dump()` -> dict; `model_dump_json()` -> JSON string. `model_dump(mode="json")` ensures dict contains JSON-safe types. `exclude={"password_hash"}` or use a separate response model class. `exclude_unset=True` for PATCH endpoints  -  only includes fields the client sent. `model_validate(data)` for deserialization with type coercion.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[pydantic-validators|Pydantic Validators]]
- [[response-model|Response Models]]
- [[fastapi|FastAPI]]
