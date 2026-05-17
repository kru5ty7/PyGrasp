---
title: Pydantic Validators
description: "Pydantic validators customize field validation with `@field_validator` (per-field) and `@model_validator` (whole model) — they run during model instantiation and raise `ValidationError` on failure; `mode='before'` runs before type coercion, `mode='after'` runs after."
tags: [pydantic, field_validator, model_validator, ValidationError, before, after, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Pydantic Validators

> Pydantic validators customize field validation with `@field_validator` (per-field) and `@model_validator` (whole model) — they run during model instantiation and raise `ValidationError` on failure; `mode='before'` runs before type coercion, `mode='after'` runs after.

---

## Quick Reference

**Core idea:**
- `@field_validator("field_name")` — class method; validates a single field; return the (possibly transformed) value
- `@model_validator(mode="after")` — validates the whole model after all fields are set; use for cross-field validation
- `@model_validator(mode="before")` — receives raw input dict before any field processing
- Raise `ValueError` or `AssertionError` inside a validator — Pydantic converts these to `ValidationError`
- `@field_validator("*")` — applies to all fields (Pydantic v2)

**Tricky points:**
- `@field_validator` is a classmethod — `@classmethod` decorator is implied in Pydantic v2; adding it explicitly causes issues in some versions
- `mode='before'` receives the raw value (could be any type); `mode='after'` receives the value after type coercion (correct type guaranteed)
- Validators run in field declaration order — if field B depends on field A's validated value, declare A before B
- `@model_validator(mode='after')` receives a model instance (access fields via `self.field`); mutations to `self` are allowed
- Validators do NOT run on default values by default — use `validate_default=True` on the field to opt in

---

## What It Is

Pydantic's built-in type coercion handles the common cases (string → int, str → datetime). Validators handle the domain-specific rules: "the price must be positive," "end_date must be after start_date," "username can only contain alphanumeric characters." They are hooks into the validation pipeline that run automatically during model instantiation.

`@field_validator` is surgical — it operates on one field in isolation. `@model_validator` has context — it sees all fields and can enforce cross-field invariants. Together they express the full validation logic for a data model.

---

## How It Actually Works

`@field_validator` (per-field):
```python
from pydantic import BaseModel, field_validator

class User(BaseModel):
    username: str
    age: int
    email: str
    
    @field_validator("username")
    @classmethod
    def username_alphanumeric(cls, v: str) -> str:
        if not v.isalnum():
            raise ValueError("username must be alphanumeric")
        return v.lower()  # transform: normalize to lowercase
    
    @field_validator("age")
    @classmethod
    def age_positive(cls, v: int) -> int:
        if v < 0:
            raise ValueError("age must be non-negative")
        return v
```

`@model_validator` (cross-field):
```python
from pydantic import BaseModel, model_validator
from datetime import date

class DateRange(BaseModel):
    start: date
    end: date
    
    @model_validator(mode="after")
    def end_after_start(self) -> "DateRange":
        if self.end <= self.start:
            raise ValueError("end must be after start")
        return self
```

`mode='before'` — normalize input before type coercion:
```python
class Tag(BaseModel):
    name: str
    
    @field_validator("name", mode="before")
    @classmethod
    def strip_name(cls, v) -> str:
        if isinstance(v, str):
            return v.strip().lower()
        return v
```

Validation error output:
```python
try:
    User(username="alice!", age=-1, email="x")
except ValidationError as e:
    print(e.errors())
# [{'type': 'value_error', 'loc': ('username',), 'msg': 'Value error, username must be alphanumeric', ...},
#  {'type': 'value_error', 'loc': ('age',), 'msg': 'Value error, age must be non-negative', ...}]
```

---

## How It Connects

Validators run during Pydantic model instantiation — understanding the Pydantic model basics is required before adding validators.
[[pydantic|Pydantic]]

FastAPI uses Pydantic models for request body validation — validators are part of the automatic request validation pipeline.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Validators only raise errors, they can't transform values."
Reality: Validators can return a transformed value — `return v.lower()` normalizes the input. Both validation (raise on bad input) and coercion (transform and return) are valid uses. The returned value replaces the original value in the model.

Misconception 2: "`@model_validator(mode='after')` receives the raw input."
Reality: `mode='after'` receives a fully-constructed model instance with all fields already validated and type-coerced. For raw dict access, use `mode='before'` which receives the unprocessed input.

---

## Why It Matters in Practice

```python
class CreateOrderRequest(BaseModel):
    items: list[OrderItem]
    discount_code: str | None = None
    shipping_address: Address
    
    @field_validator("items")
    @classmethod
    def items_not_empty(cls, v: list) -> list:
        if not v:
            raise ValueError("order must have at least one item")
        return v
    
    @model_validator(mode="after")
    def validate_discount_eligibility(self) -> "CreateOrderRequest":
        if self.discount_code and len(self.items) < 2:
            raise ValueError("discount codes require at least 2 items")
        return self
```

This single model validates structure (Pydantic), per-field rules (`@field_validator`), and cross-field business rules (`@model_validator`) — all in one place, automatically triggered by FastAPI on every request.

---

## Interview Angle

Common question forms:
- "How do you add custom validation to a Pydantic model?"
- "How do you validate that one field depends on another?"

Answer frame: `@field_validator("field_name")` for single-field validation — raise `ValueError` or return transformed value. `@model_validator(mode="after")` for cross-field validation — receives a model instance after all fields are set. `mode="before"` for raw input preprocessing. All raise `ValueError`; Pydantic collects them into `ValidationError` with per-field locations.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[pydantic-settings|Pydantic Settings]]
- [[fastapi|FastAPI]]
- [[request-body|Request Body]]
