---
title: 02 - Litestar
description: "Litestar is a strict, performance-focused ASGI framework with built-in dependency injection, DTOs, caching, and rate limiting."
tags: [litestar, asgi, web-framework, performance, typing, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Litestar

> Litestar is an opinionated ASGI framework that enforces strict typing, introduces Data Transfer Objects as first-class citizens, and ships batteries like caching and rate limiting that FastAPI delegates to third-party libraries.

---

## Quick Reference

**Core idea:**
- ASGI framework (formerly Starlite, renamed Litestar in 2023) built on Starlette internals with a distinct higher-level API
- DTOs (Data Transfer Objects) separate input/output schemas from domain models, enforced at the framework level
- Dependency injection is built-in and does not require decorator syntax  -  uses type annotations exclusively
- Supports both Pydantic v2 and `attrs` for data validation
- Built-in caching (`@get("/", cache=True)`), rate limiting, and OpenAPI documentation generation
- Strict type enforcement at route definition time catches configuration errors before the server starts

**Tricky points:**
- DTOs are mandatory for routes that accept or return data  -  unlike FastAPI where you annotate directly with Pydantic models
- The dependency injection API differs from FastAPI: no `Depends()` function; dependencies are declared as parameters with type annotations on handler functions
- `Controller` classes group related handlers, similar to class-based views in Django  -  a pattern FastAPI does not have natively
- Pydantic v1 is not supported; the framework targets Pydantic v2 exclusively
- Plugin architecture is central to Litestar  -  SQLAlchemy, Redis, and other integrations are installed as plugins, not ad-hoc middleware

---

## What It Is

A software framework can be thought of on a spectrum from "library with suggestions" to "structured environment with rules". Flask sits toward the first end: it provides routing and request/response primitives, but you decide how to structure models, validation, and data flow. Django sits toward the other end: it mandates a project layout, provides ORM, admin, and forms, and expects you to follow its conventions. Litestar occupies a middle position that leans toward the opinionated side for the concerns it covers  -  particularly around type safety and data shapes  -  while remaining a general-purpose ASGI framework.

Litestar began as Starlite in late 2021, created as a response to perceived complexity and inconsistency in FastAPI's dependency injection model. The project was renamed Litestar in 2023 following a governance restructuring and community vote. The core philosophy is that a framework should catch as many errors as possible at application startup rather than at runtime. Litestar validates route handlers, their parameter types, return type annotations, and dependency graphs when the application is first built. If a handler's return annotation does not match the registered response model, the application raises a configuration error before the first request arrives.

DTOs (Data Transfer Objects) are Litestar's most distinctive concept. In FastAPI, you typically use the same Pydantic model for both API input/output and internal domain logic, or you define separate models manually and convert between them. Litestar formalizes this separation: a DTO is an explicit layer between the HTTP boundary and your domain model. The framework generates a DTO from a dataclass or SQLAlchemy model automatically, controlling which fields are exposed, which are read-only, and which are excluded. This prevents accidentally exposing internal fields (like password hashes or audit columns) through API responses without writing explicit exclusion logic.

---

## How It Actually Works

A basic Litestar application uses `@get`, `@post`, and other decorators on handler functions, but handler configuration is richer than FastAPI's:

```python
from litestar import Litestar, get, post
from litestar.dto import DTOConfig
from litestar.contrib.pydantic import PydanticDTO
from pydantic import BaseModel

class UserModel(BaseModel):
    id: int
    email: str
    password_hash: str  # should never be in API response

class UserReadDTO(PydanticDTO[UserModel]):
    config = DTOConfig(exclude={"password_hash"})

@get("/users/{user_id:int}", return_dto=UserReadDTO)
async def get_user(user_id: int) -> UserModel:
    return UserModel(id=user_id, email="user@example.com", password_hash="hashed!")

app = Litestar(route_handlers=[get_user])
```

The `return_dto=UserReadDTO` parameter tells Litestar to pass the return value through the DTO before serialization. The `password_hash` field is excluded automatically, regardless of what the handler returns. This is an opt-out-of-exposure model rather than FastAPI's opt-in-to-exclusion model with `response_model_exclude`.

Dependency injection in Litestar uses `Provide` and type-based resolution. Dependencies are provided at the application, router, or handler level:

```python
from litestar import Litestar, get
from litestar.di import Provide

async def get_db_session() -> AsyncSession:
    async with async_session_factory() as session:
        yield session

@get("/items", dependencies={"db": Provide(get_db_session)})
async def list_items(db: AsyncSession) -> list[dict]:
    ...

app = Litestar(
    route_handlers=[list_items],
    dependencies={"db": Provide(get_db_session)}  # or app-level
)
```

The built-in caching and rate limiting are configured directly on route decorators. `@get("/summary", cache=60)` caches the response for 60 seconds using the configured cache backend (in-memory by default, Redis via plugin). Rate limiting is applied via `@get("/api", guards=[RateLimitGuard(...)])`. These capabilities reduce the middleware boilerplate required in FastAPI applications that reach for `slowapi` or `fastapi-cache` as third-party dependencies.

---

## How It Connects

Litestar is built on top of Starlette's foundational ASGI primitives  -  understanding Starlette's request/response cycle and middleware model explains what Litestar provides on top.

[[starlette|Starlette]]

The direct comparison between Litestar and FastAPI is the most practically useful framing for a Python developer evaluating ASGI frameworks; both target the same async-first, type-driven audience but make different trade-offs.

[[fastapi|FastAPI]]

Litestar's DTO system integrates tightly with Pydantic v2, and understanding Pydantic's model system is necessary for working effectively with Litestar's type validation layer.

[[pydantic|Pydantic]]

---

## Common Misconceptions

Misconception 1: "Litestar is just FastAPI with different syntax."
Reality: Litestar and FastAPI share the ASGI foundation and type-annotation-driven design, but differ in core concepts. Litestar's DTO system, Controller class-based views, startup-time validation, and built-in caching/rate-limiting represent architectural differences, not syntax variations. Code does not port between the two without rethinking the data layer.

Misconception 2: "Starlite and Litestar are different projects."
Reality: Litestar is a direct continuation of Starlite. The project was renamed in 2023; the GitHub history, contributors, and codebase are the same. Documentation for Starlite is outdated but largely conceptually applicable to Litestar.

Misconception 3: "I must use DTOs for all routes in Litestar."
Reality: DTOs are optional but encouraged. Routes that return primitive types (strings, integers, dicts) or that do not need field-level control can omit DTOs. The DTO system is most valuable when you have rich domain models with fields that should not cross the API boundary.

---

## Why It Matters in Practice

Litestar is gaining adoption in teams that find FastAPI's loose conventions lead to inconsistency at scale. In a large FastAPI codebase, it is easy to accidentally return internal model fields, skip dependency injection for some routes, or accumulate ad-hoc validation logic. Litestar's startup-time validation and mandatory DTO layer push these issues to the surface earlier. For smaller teams or exploratory projects, that strictness can feel like friction  -  FastAPI's flexibility is genuinely useful when requirements are in flux.

The framework comparison note covers the decision matrix in full, but the practical trigger for choosing Litestar over FastAPI is usually a team that has hit the "inconsistency at scale" problem and wants a framework that enforces the patterns they want to follow anyway. The built-in caching and rate limiting also reduce dependency count for services that need those features, which simplifies maintenance and security auditing.

---

## Interview Angle

Common question forms:
- "What is a DTO in Litestar and why does it exist?"
- "How does Litestar differ from FastAPI?"
- "When would you choose Litestar for a new project?"

Answer frame:
A strong answer to the DTO question explains the separation of concerns: DTOs are the layer that controls which fields of a domain model cross the API boundary, enforced by the framework rather than by developer discipline. For the FastAPI comparison, key differentiators are startup-time validation, Controller-based routing, and built-in caching/rate-limiting. The "when to choose" question should be answered with a team-size and consistency argument: Litestar's opinionation reduces long-term decision fatigue in larger codebases at the cost of a steeper initial learning curve.

---

## Related Notes

- [[starlette|Starlette]]
- [[fastapi|FastAPI]]
- [[pydantic|Pydantic]]
- [[asgi|ASGI]]
- [[framework-comparison|Python Web Framework Comparison]]
