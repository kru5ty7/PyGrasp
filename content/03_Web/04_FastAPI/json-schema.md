---
title: 04 - JSON Schema
description: "JSON Schema is a vocabulary for describing the structure and constraints of JSON data  -  Pydantic generates JSON Schema from models via `model.model_json_schema()`; FastAPI uses this to power OpenAPI documentation and request validation."
tags: [json-schema, schema, validation, OpenAPI, pydantic, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# JSON Schema

> JSON Schema is a vocabulary for describing the structure and constraints of JSON data  -  Pydantic generates JSON Schema from models via `model.model_json_schema()`; FastAPI uses this to power OpenAPI documentation and request validation.

---

## Quick Reference

**Core idea:**
- JSON Schema: a JSON document that describes the structure, types, and constraints of another JSON document
- Core keywords: `type`, `properties`, `required`, `additionalProperties`, `enum`, `minimum`, `maximum`, `minLength`, `maxLength`, `pattern`
- `$ref`  -  reference to a reusable schema definition (avoids repetition in complex schemas)
- Pydantic: `MyModel.model_json_schema()` -> generates the JSON Schema dict
- FastAPI: uses Pydantic JSON Schema to build OpenAPI spec -> Swagger UI shows field types and constraints

**Tricky points:**
- JSON Schema `type: "integer"` does not match `1.0` (float)  -  strict integer check; Pydantic's `int` type does coerce `1.0` -> `1` but the generated schema declares `integer`
- `additionalProperties: false`  -  rejects JSON objects with keys not in `properties`; Pydantic's `model_config = ConfigDict(extra="forbid")` generates this
- `$defs` / `$ref` in generated schemas  -  Pydantic uses these for nested models and avoids inlining the same schema twice
- `nullable` (OpenAPI 3.0) vs `type: ["string", "null"]` (JSON Schema)  -  FastAPI generates `anyOf: [{"type": "string"}, {"type": "null"}]` for `Optional[str]`
- JSON Schema draft versions (Draft 4, 7, 2019-09, 2020-12)  -  Pydantic v2 generates Draft 2020-12; OpenAPI 3.1 uses JSON Schema 2020-12; OpenAPI 3.0 uses a subset of Draft 4

---

## What It Is

JSON Schema solves the problem of describing JSON data: what fields are required, what types they have, what values are valid. It's the basis for automatic validation, documentation generation, and client SDK generation. When FastAPI shows a Swagger UI with typed fields and constraints, that UI is generated from the JSON Schema of Pydantic models.

Think of it as type annotations for JSON  -  just as Python type hints describe function signatures, JSON Schema describes the shape of data exchanged over HTTP. It's machine-readable, which enables tools (validators, generators) to work without custom code.

---

## How It Actually Works

A simple JSON Schema:
```json
{
  "type": "object",
  "properties": {
    "name": {"type": "string", "minLength": 1, "maxLength": 100},
    "age": {"type": "integer", "minimum": 0, "maximum": 150},
    "email": {"type": "string", "format": "email"}
  },
  "required": ["name", "email"],
  "additionalProperties": false
}
```

Pydantic generates this:
```python
from pydantic import BaseModel, Field

class User(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    age: int = Field(ge=0, le=150)
    email: str

print(User.model_json_schema())
# {'type': 'object', 'properties': {'name': {'type': 'string', 'minLength': 1, ...}, ...}}
```

Pydantic `Field()` -> JSON Schema constraints:
```python
Field(gt=0)        -> "exclusiveMinimum": 0
Field(ge=0)        -> "minimum": 0
Field(lt=100)      -> "exclusiveMaximum": 100
Field(le=100)      -> "maximum": 100
Field(min_length=1)-> "minLength": 1
Field(max_length=50)->"maxLength": 50
Field(pattern=r"^\w+$") -> "pattern": "^\\w+$"
```

Nested models use `$defs`:
```python
class Address(BaseModel):
    street: str
    city: str

class User(BaseModel):
    name: str
    address: Address

User.model_json_schema()
# {'$defs': {'Address': {'properties': {...}, 'type': 'object'}},
#  'properties': {'name': {...}, 'address': {'$ref': '#/$defs/Address'}}, ...}
```

---

## How It Connects

Pydantic generates JSON Schema from models  -  `model_json_schema()` is the bridge between Python type annotations and the JSON format.
[[pydantic|Pydantic]]

FastAPI uses JSON Schema (via Pydantic) to build OpenAPI docs  -  every endpoint's request and response schemas appear in Swagger UI automatically.
[[openapi|OpenAPI]]

---

## Common Misconceptions

Misconception 1: "JSON Schema validation and Pydantic validation are the same thing."
Reality: Pydantic validation runs in Python  -  it coerces types (string "42" -> int 42) and applies validators. JSON Schema validation runs against raw JSON data  -  it's used by external clients and documentation tools. They should describe the same constraints, but Pydantic's behavior (coercion) is more permissive than strict JSON Schema validation.

Misconception 2: "`additionalProperties: false` rejects extra fields by default."
Reality: JSON Schema allows additional properties unless `additionalProperties: false` is explicitly set. Pydantic's default is to ignore extra fields (`extra='ignore'`). Use `model_config = ConfigDict(extra='forbid')` to generate `additionalProperties: false` and reject unknown fields.

---

## Why It Matters in Practice

JSON Schema enables:
- **OpenAPI docs**: Swagger UI reads JSON Schema to render typed forms for testing endpoints
- **Client code generation**: tools like `openapi-generator` produce typed client SDKs from JSON Schema
- **Contract testing**: validate that a response matches the expected schema without parsing into a model
- **Frontend validation**: JavaScript validation libraries (Ajv) use the same JSON Schema as the server  -  single source of truth

---

## Interview Angle

Common question forms:
- "How does FastAPI generate its API documentation?"
- "What is JSON Schema?"

Answer frame: JSON Schema describes the structure and constraints of JSON data using a vocabulary (`type`, `properties`, `required`, `minimum`, etc.). Pydantic generates JSON Schema from models via `model_json_schema()`. FastAPI collects these schemas and builds an OpenAPI spec  -  Swagger UI renders the spec. `Field(ge=0, max_length=100)` in Pydantic -> `minimum: 0, maxLength: 100` in the generated schema.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[openapi|OpenAPI]]
- [[fastapi|FastAPI]]
- [[serialization|Serialization and Deserialization]]
