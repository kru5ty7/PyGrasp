---
title: 16 - OpenAPI
description: OpenAPI is a language-agnostic specification for describing HTTP APIs  -  FastAPI generates a complete OpenAPI schema automatically from your route type annotations, serving interactive documentation at /docs and /redoc without any manual schema authoring.
tags: [openapi, swagger, api-schema, fastapi, documentation, json-schema, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# OpenAPI

> OpenAPI is a language-agnostic specification for describing HTTP APIs  -  FastAPI generates a complete OpenAPI schema automatically from your route type annotations, serving interactive documentation at /docs and /redoc without any manual schema authoring.

---

## Quick Reference

**Core idea:**
- OpenAPI (formerly Swagger) is a **JSON/YAML schema** that describes an HTTP API: its endpoints, HTTP methods, parameters, request bodies, and response shapes
- FastAPI generates an OpenAPI schema **automatically** from route type annotations  -  the same annotations used for validation double as schema definitions
- The schema is served at `/openapi.json`; Swagger UI at `/docs` renders it interactively; ReDoc at `/redoc` renders a reference view
- Pydantic models in route annotations become **JSON Schema** objects in the OpenAPI spec  -  their field types, validators, and descriptions map directly
- `tags`, `summary`, `description`, `response_description`, and `deprecated` parameters on route decorators customize the generated schema

**Tricky points:**
- FastAPI uses **JSON Schema draft 2020-12** (via Pydantic v2) for model schemas; older clients expecting draft 4/7 may have compatibility issues
- The `response_model` on a route decorator determines the schema for **successful** responses  -  if omitted, the schema infers from the return annotation
- `status_code` on the route decorator sets the primary response code in the schema  -  the default is `200` for `GET` and `201` for `POST` if not specified
- `responses` parameter on decorators allows documenting **additional** status codes (e.g., `404`, `422`) beyond the default success response
- `include_in_schema=False` on a route hides it from the OpenAPI schema entirely  -  useful for internal or health-check endpoints

---

## What It Is

Think of OpenAPI as a blueprint for a building. The blueprint does not build the building  -  it is a precise technical document that describes every room, every door, every window, and the exact dimensions of each. Anyone who reads the blueprint knows exactly what the building contains and how to move through it. OpenAPI is that blueprint for an HTTP API. It is a formal document, written in JSON or YAML, that describes every endpoint, what parameters it accepts, what request body shape it expects, what response codes it can return, and what each response body looks like. Any tool that understands OpenAPI can read this document and know exactly how to interact with the API.

The OpenAPI specification emerged from the Swagger project, which was donated to the OpenAPI Initiative in 2016. Swagger became OpenAPI 2.0, and the current version is OpenAPI 3.1. The specification defines a structured format: a top-level `info` section with API metadata, a `paths` object mapping URL paths to their operations (GET, POST, etc.), a `components` section holding reusable schemas, parameters, and response definitions, and a `servers` section listing base URLs. Within each operation, `parameters` describe path and query parameters, `requestBody` describes the expected body, and `responses` maps status codes to their response schemas.

What makes FastAPI's OpenAPI integration exceptional is that the schema is not separately authored  -  it is derived from the same source of truth as the validation rules. A Pydantic model with field validators, field descriptions, and type constraints generates both the runtime validation logic and the JSON Schema object that appears in the OpenAPI spec. If you add a new field to a Pydantic model, that field appears in the documentation automatically on the next server start. If you change a field from `str` to `int`, the schema and the validation both change simultaneously. There is no separate documentation layer that can fall out of sync with the actual API behavior.

---

## How It Actually Works

FastAPI builds its OpenAPI schema by iterating over all registered routes at application startup. For each route, it calls `get_openapi_operation_metadata()` to extract tags, summary, description, and operation IDs from the route decorator arguments. It then calls `get_flat_params()` to inspect the route's parameter map (built at registration from `inspect.signature()`) and classifies each parameter as a path parameter, query parameter, header, or cookie. For body parameters, it calls Pydantic's `model_json_schema()` to get the JSON Schema representation of the model.

Pydantic v2's `model_json_schema()` returns a JSON Schema dict that represents the model's structure. Field types map to JSON Schema types: `str` -> `{"type": "string"}`, `int` -> `{"type": "integer"}`, `Optional[str]` -> `{"anyOf": [{"type": "string"}, {"type": "null"}]}`. Field validators using `Field(gt=0, le=100)` map to `{"minimum": 0, "maximum": 100}`. Nested Pydantic models become `$ref` references to component schemas, which FastAPI collects into the top-level `components.schemas` section. This generates a flat, self-contained schema where complex types are defined once and referenced by name.

The schema is assembled into a Python dict matching the OpenAPI 3.1 structure and cached on the application instance. The `/openapi.json` endpoint serializes this dict to JSON and returns it. The `/docs` endpoint serves the Swagger UI static HTML, configured to point at `/openapi.json` for its data. The `/redoc` endpoint similarly serves the ReDoc HTML. Both UIs load the schema at page load and render their respective interfaces from it  -  they are not generated by FastAPI, they are static JavaScript applications that consume the OpenAPI JSON.

Customizing the generated schema beyond what decorator parameters offer is done by accessing the schema programmatically. `app.openapi()` returns the generated schema dict. You can override this method by assigning `app.openapi = custom_openapi_function`, where your function calls `get_openapi()` with the base routes and then modifies the resulting dict before caching and returning it. This is the pattern for adding security scheme definitions, global headers, custom `info` fields, or schema modifications that are not directly expressible through route decorator parameters.

---

## How It Connects

FastAPI is the framework that generates the OpenAPI schema automatically. Every route decorator, every type annotation, every Pydantic model used in a handler contributes to the schema FastAPI builds at startup. Understanding FastAPI's route registration and type inspection explains exactly what information feeds the OpenAPI generation.
[[fastapi|FastAPI]]

Pydantic models are the primary source of schema information for request and response bodies. Pydantic's `model_json_schema()` is the mechanism that converts Python type definitions into JSON Schema objects. The richness of the OpenAPI schema  -  field descriptions, validation constraints, examples  -  depends directly on how thoroughly Pydantic models are annotated with `Field()` metadata.
[[pydantic|Pydantic]]

---

## Common Misconceptions

Misconception 1: "The `/docs` page is generated by FastAPI and shows real-time behavior."
Reality: `/docs` serves a static Swagger UI JavaScript application that fetches the OpenAPI JSON from `/openapi.json`. The schema is generated once at application startup and cached. The documentation reflects the state of the routes at startup time  -  adding routes dynamically after startup will not appear in the docs unless the schema cache is invalidated. The interactive "Try it out" feature in Swagger UI sends real HTTP requests to your API endpoints  -  it is a live client, not a simulation.

Misconception 2: "OpenAPI documentation is only useful for human readers."
Reality: OpenAPI schemas are machine-readable specifications. SDK generators (like `openapi-generator`) read the schema and produce client libraries in multiple languages automatically. API testing tools like Postman import OpenAPI specs to pre-configure request shapes. Contract testing tools use the schema to verify that both client and server agree on the API's shape. Type-safe API clients for TypeScript frontends can be generated from the FastAPI OpenAPI schema. The documentation at `/docs` is the human-readable surface; the JSON at `/openapi.json` is the machine-readable contract.

---

## Why It Matters in Practice

The `Field()` function from Pydantic is the primary tool for enriching the OpenAPI schema. `Field(description="The user's email address", example="user@example.com")` adds a description and example to the field in the schema, which Swagger UI displays. `Field(title="Email", min_length=5, max_length=255)` adds a title and length constraints that appear in the schema and are enforced at validation time. Investing in `Field()` annotations makes the auto-generated documentation actually useful rather than just structurally correct.

Hiding endpoints from the schema with `include_in_schema=False` is important for health-check endpoints, internal admin routes, and debug endpoints that should not be part of the public API contract. These endpoints still function normally  -  they are just excluded from the OpenAPI JSON and therefore from Swagger UI and ReDoc. For endpoints that should exist in the schema but should not be callable without authentication, use security scheme definitions in the schema rather than hiding them.

---

## Interview Angle

Common question forms:
- "How does FastAPI generate its documentation?"
- "What is OpenAPI and how does it relate to Swagger?"
- "How do you customize the FastAPI-generated OpenAPI schema?"

Answer frame: OpenAPI is a JSON/YAML specification for HTTP API contracts  -  endpoints, parameters, request bodies, and responses. Swagger was the original tool; OpenAPI is the standardized specification derived from it. FastAPI generates an OpenAPI schema automatically from route type annotations and Pydantic models at startup, caches it, and serves it at `/openapi.json`. Swagger UI at `/docs` and ReDoc at `/redoc` are static JavaScript clients that consume this schema. Customization: `Field()` for per-field metadata, `tags`/`summary`/`description` on route decorators, `responses` for additional status codes, and overriding `app.openapi()` for structural changes.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[pydantic|Pydantic]]
- [[http-basics|HTTP Basics]]
