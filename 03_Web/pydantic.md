---
title: Pydantic
description: Pydantic is a data validation library that uses Python type hints to define data schemas — it validates, coerces, and serializes data at runtime, and it is the validation engine underneath FastAPI's request and response handling.
tags: [pydantic, validation, type-hints, serialization, FastAPI, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Pydantic

> Pydantic is a data validation library that uses Python type hints to define data schemas — it validates, coerces, and serializes data at runtime, and it is the validation engine underneath FastAPI's request and response handling.

---

## Quick Reference

**Core idea:**
- Define a `BaseModel` subclass with annotated fields — Pydantic validates and coerces data on instantiation
- Validation happens at **runtime** (unlike mypy/pyright which are static) — invalid data raises `ValidationError`
- Pydantic **coerces** by default: `"42"` → `int` field becomes `42`; use `model_config = ConfigDict(strict=True)` to disable
- `model.model_dump()` → dict; `model.model_dump_json()` → JSON string; `Model.model_validate(dict)` → model instance
- Field customization: `Field(default=..., alias=..., gt=0, max_length=100, description=...)`

**Tricky points:**
- Pydantic v2 (current) is a near-complete rewrite from v1 — method names changed: `dict()` → `model_dump()`, `parse_obj()` → `model_validate()`, `schema()` → `model_json_schema()`
- **Validators run on assignment** by default in v2 — mutating a field after creation still triggers validation if `model_config = ConfigDict(validate_assignment=True)` is set
- `Optional[str]` in a Pydantic model means the field accepts `None` — it does **not** mean the field has a default; you still must pass it or set `default=None`
- Nested models are validated recursively — a dict passed for a nested model field is automatically coerced into the nested model type
- `model_dump(exclude_unset=True)` returns only fields that were explicitly set — critical for PATCH endpoints that should not overwrite unset fields

---

## What It Is

Think of a customs officer at an airport. Every traveller (piece of data) must pass through customs. The officer checks that the passport (the required fields) is present, that the declared items (the field values) match what is allowed, and that everything is in the right format. If something is wrong, the traveller is turned away with a clear explanation of what failed. If something is close but needs a minor conversion — a weight declared in pounds that needs to be in kilograms — the officer handles that too. Pydantic is that customs officer for your Python data.

Pydantic lets you define data schemas as Python classes. You subclass `BaseModel` and add class attributes with type annotations. When you instantiate the model with data, Pydantic validates every field: it checks that required fields are present, that each value is the right type (or can be coerced to it), and that any constraints (minimum value, maximum length, regex pattern) are satisfied. If anything is wrong, it raises a `ValidationError` with a precise description of every field that failed and why.

The key design choice that makes Pydantic powerful is that it uses Python type hints as the schema definition. You write `name: str`, `age: int`, `email: EmailStr`, `tags: list[str]` — the same syntax you would use for type checking — and Pydantic turns those annotations into a runtime validation system. This means your schema and your type annotations are the same thing. There is no separate schema file, no XML, no JSON schema to maintain alongside your code. The class definition is both documentation and enforcement.

---

## How It Actually Works

Pydantic v2 is implemented in Rust (via the `pydantic-core` package) for performance. When a `BaseModel` subclass is created, Pydantic's metaclass (`ModelMetaclass`) inspects the class body, reads the type annotations and any `Field()` descriptors, and builds a validator function in Rust. This validator is called every time an instance is created. For a model with ten fields, Pydantic builds a single optimized validator that checks and coerces all ten fields in one pass.

Coercion is one of Pydantic's most-used features and most debated behaviors. In the default "lax" mode, Pydantic accepts values that can be sensibly converted: a string `"42"` is accepted for an `int` field and converted to the integer `42`; a string `"true"` is accepted for a `bool` field and converted to `True`. In strict mode (`ConfigDict(strict=True)` or `Field(strict=True)`), Pydantic rejects any value that is not already the exact expected type. Strict mode is appropriate for API responses where you control the data; lax mode is appropriate for user input that may arrive as strings from form data or URL parameters.

`ValidationError` raised by Pydantic contains a list of errors, each with the field path, the error type, and a human-readable message. `err.errors()` returns a list of dicts; each dict has `loc` (field location as a tuple), `type` (error type string), `msg` (human message), and `input` (the value that failed). FastAPI catches `ValidationError` from request parsing and automatically converts it to a `422 Unprocessable Entity` response with the error details as JSON.

Custom validators are defined with the `@field_validator` decorator (v2) or `@validator` (v1). A field validator receives the field's value after basic type coercion and can apply additional logic, raise `ValueError` to signal failure, or return a modified value. `@model_validator` runs after all field validators and receives the fully populated model, allowing cross-field validation.

---

## How It Connects

Pydantic reads type annotations from the class body to build its validation schema. The `__annotations__` dict on the model class is the raw material. Understanding what type hints are, how they are stored, and how tools can read them at runtime is the foundation of understanding how Pydantic converts annotations into validators.
[[type-hints|Type Hints]]

Pydantic models behave like Python objects with a rich data model: they support `__init__`, `__repr__`, `__eq__`, and custom serialization via dunder methods. The Python data model protocol is what allows Pydantic to define clean, natural-feeling Python classes that still have validation behavior.
[[python-data-model|The Python Data Model]]

FastAPI uses Pydantic as its validation engine. Every request body type, every response model, every query parameter with a complex type in FastAPI is defined as a Pydantic model. FastAPI reads the annotations on route handlers, uses Pydantic to validate incoming data, and uses Pydantic again to serialize outgoing data. You cannot use FastAPI effectively without understanding Pydantic.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Pydantic validates types the same way mypy does."
Reality: Pydantic validates at runtime when data is instantiated. Mypy validates statically before the program runs. They are complementary, not duplicates. Mypy catches type errors in your code — where you use the model. Pydantic catches data errors at the boundary — when untrusted external data (user input, API responses, database rows) enters your system. You need both.

Misconception 2: "Pydantic v2 and v1 are compatible — I can upgrade without changes."
Reality: Pydantic v2 was a near-complete rewrite. Method names changed significantly: `dict()` is now `model_dump()`, `parse_obj()` is now `model_validate()`, `schema()` is now `model_json_schema()`. Configuration moved from a nested `Config` class to `model_config = ConfigDict(...)`. Validators use `@field_validator` instead of `@validator`. Pydantic v2 provides a compatibility layer (`from pydantic.v1 import BaseModel`) but relying on it is a migration step, not a final state. New projects should use v2 APIs from the start.

---

## Why It Matters in Practice

Pydantic is the boundary guard between the untrustworthy outside world and your application's internal logic. HTTP requests arrive as raw bytes; JSON is parsed into Python dicts with unvalidated values. Without Pydantic, every route handler must manually validate inputs, check for missing keys, coerce types, and return appropriate errors. With Pydantic, this entire layer is declarative: define a model, annotate the handler, and all validation is handled automatically. Invalid data never reaches your business logic.

The `model_dump(exclude_unset=True)` pattern is particularly important for REST API design. In a PATCH endpoint, you only want to update the fields the client explicitly sent — not overwrite all fields with defaults for the ones they did not send. `exclude_unset=True` returns only the fields that were present in the incoming data, regardless of whether those fields have defaults. This makes building partial-update endpoints clean and correct without custom parsing logic.

---

## Interview Angle

Common question forms:
- "What is Pydantic and how does it relate to type hints?"
- "How does Pydantic handle invalid data?"
- "What is the difference between Pydantic and mypy?"

Answer frame: Define Pydantic as a runtime validation library that uses type annotations as schema definitions. Explain the `BaseModel` pattern: annotate fields, instantiate with data, receive a validated object or a `ValidationError`. Distinguish from mypy: Pydantic is runtime (catches bad data), mypy is static (catches bad code). Mention coercion (lax mode converts compatible types) and strict mode. Connect to FastAPI: Pydantic is FastAPI's validation and serialization engine.

---

## Related Notes

- [[type-hints|Type Hints]]
- [[python-data-model|The Python Data Model]]
- [[fastapi|FastAPI]]
