---
title: 01 - API Design Principles
description: "Resource naming, HTTP method semantics, error response formats, and the principles that make an API predictable and easy for consumers to use correctly."
tags: [api-design, rest, http, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# API Design Principles

> A well-designed API is self-documenting  -  every name, method, and status code tells the consumer what happened and what to do next without reading the docs.

---

## Quick Reference

**Core idea:**
- Resources are nouns, plural: `/users`, `/orders`, `/products/{id}`
- HTTP methods convey intent: GET (read), POST (create), PUT (full replace), PATCH (partial update), DELETE (remove)
- Status codes are semantically significant: 200 OK, 201 Created, 204 No Content, 400 Bad Request, 404 Not Found, 409 Conflict, 422 Unprocessable Entity, 500 Internal Server Error
- Error responses should be structured and machine-readable, not plain strings
- Consistency within an API is more important than any individual design choice

**Tricky points:**
- POST is not "do something"  -  it creates a resource or triggers a specific action
- 404 Not Found vs 403 Forbidden vs 401 Unauthorized are semantically different  -  use them correctly
- PUT replaces the entire resource; PATCH modifies specific fields  -  misusing them causes incorrect idempotency assumptions
- Do not leak internal implementation details (database IDs, internal service names) in API responses
- Avoid verbs in URLs: `/createUser` is wrong; `POST /users` is correct

---

## What It Is

Imagine you are using a hotel's concierge service over the phone. A well-designed concierge follows predictable patterns: "I'd like to make a reservation" creates something new. "Can you look up my reservation?" retrieves it. "Please cancel my reservation" removes it. You know what to expect: a reservation number, a confirmation, a cancellation notice. The language is consistent, the outcomes are predictable, and errors are explained clearly: "That reservation doesn't exist", "That date is fully booked."

A poorly designed concierge uses random verbs, gives you error codes with no explanation, and handles the same kind of request differently on Tuesday than on Friday. An API is a programmatic interface  -  and the same principles of consistency, predictability, and clarity apply.

REST (Representational State Transfer) is the architectural style that most web APIs follow today. It structures APIs around resources (things  -  nouns) accessed via URLs, using HTTP methods to express the type of action. A resource is anything you can name: a user, an order, a product, a session. The URL identifies which resource. The HTTP method identifies what you want to do with it.

Resource naming should use plural nouns: `/users` for the collection, `/users/{id}` for an individual user. Nested resources express relationships: `/users/{id}/orders` for a specific user's orders. The key principle is that the URL is a stable address for a resource  -  it does not encode the action (no `/createUser`, no `/getUserById`). The action is expressed by the HTTP method.

HTTP method semantics are a contract. GET is safe (no state change) and idempotent (same result every time). POST creates a resource or triggers an action  -  it is neither safe nor idempotent (two POSTs create two resources). PUT replaces a resource entirely  -  the client sends the full new state. PUT is idempotent (doing it twice results in the same state). PATCH modifies specific fields  -  it is not necessarily idempotent (a PATCH that increments a counter is not idempotent). DELETE removes a resource  -  it is idempotent (deleting twice has the same result as deleting once: the resource is gone).

---

## How It Actually Works

Status codes are the API's way of communicating the outcome of a request. Using them correctly means consumers can handle responses generically rather than parsing the body for clues about what happened.

The `2xx` range signals success. `200 OK` means the request succeeded and the response body contains the result. `201 Created` means a new resource was created and typically includes the resource's URL in the `Location` header. `204 No Content` means the request succeeded but there is nothing to return (common for DELETE and PUT responses). `202 Accepted` means the request was received and will be processed asynchronously  -  the actual work has not completed yet.

The `4xx` range signals client errors  -  something the client did wrong. `400 Bad Request` means the request was malformed. `401 Unauthorized` means the client is not authenticated  -  it should provide credentials. `403 Forbidden` means the client is authenticated but lacks permission. `404 Not Found` means the resource does not exist. `409 Conflict` means the request conflicts with existing state (e.g., creating a user with a duplicate email). `422 Unprocessable Entity` means the request was syntactically valid but semantically invalid (e.g., a well-formed request with an invalid business rule violation).

The `5xx` range signals server errors  -  problems the server is responsible for. `500 Internal Server Error` is a catch-all for unexpected server failures. `503 Service Unavailable` means the server is temporarily unable to handle requests (overloaded, in maintenance).

Error responses should be consistent and machine-readable. A standard error format includes: a stable error code (not an HTTP status code  -  a string like `"USER_NOT_FOUND"` or `"INVALID_PAYMENT_METHOD"`), a human-readable message, and optionally a details array with field-level validation errors.

```python
# FastAPI: well-structured API endpoint with proper status codes and error format
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, EmailStr
from typing import Optional

app = FastAPI()

class CreateUserRequest(BaseModel):
    email: EmailStr
    name: str
    role: str = "member"

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    role: str

class ErrorResponse(BaseModel):
    error_code: str
    message: str
    details: Optional[list] = None

@app.post(
    "/users",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,  # 201 Created, not 200 OK
    responses={
        409: {"model": ErrorResponse, "description": "Email already in use"},
        422: {"model": ErrorResponse, "description": "Validation error"},
    }
)
async def create_user(request: CreateUserRequest):
    existing = await db.get_user_by_email(request.email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error_code": "EMAIL_ALREADY_EXISTS",
                "message": f"A user with email {request.email} already exists.",
            }
        )

    user = await db.create_user(email=request.email, name=request.name, role=request.role)
    return UserResponse(**user)

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str):
    user = await db.get_user(user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "USER_NOT_FOUND", "message": f"User {user_id} not found."}
        )
    return UserResponse(**user)

@app.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(user_id: str):
    deleted = await db.delete_user(user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail={"error_code": "USER_NOT_FOUND"})
    # 204: no body returned
```

Request and response design should be deliberate about what is included. Never return more data than necessary  -  each additional field exposes more API surface area that becomes a compatibility commitment. Never return internal IDs or schema details that clients have no use for. Dates should be ISO 8601 format with timezone (`2026-05-18T10:30:00Z`). Amounts should be integers in the smallest unit (cents, not dollars) to avoid floating-point issues.

---

## How It Connects

API versioning is the mechanism for evolving an API without breaking existing consumers. The design principles established here are what you must maintain across versions.

[[api-versioning|API Versioning]]

Idempotency  -  the property that a request can be safely retried without causing duplicate effects  -  is a key consequence of correct HTTP method semantics. PUT and DELETE are idempotent; POST and PATCH may not be.

[[idempotency|Idempotency]]

In the Python ecosystem, FastAPI implements all of these design principles through Pydantic models, response models, and status code declarations.

[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "POST should be used for all operations that cause side effects."
Reality: POST is for creating resources or triggering actions with no natural idempotency. Operations that modify a resource (replace with PUT, partial update with PATCH) or delete it (DELETE) have their own HTTP methods with specific idempotency semantics. Using POST for everything loses these semantics and makes the API harder to reason about.

Misconception 2: "404 is fine to return when the user is not authorized to see a resource."
Reality: Returning 404 when the resource exists but the user lacks permission reveals the existence of the resource, which may be a security concern. The correct choice is 403 Forbidden (the resource exists, you lack access). However, in some security contexts (where revealing existence is itself sensitive), 404 is intentionally used to avoid leaking information about what exists. This is a deliberate security decision, not a default.

Misconception 3: "HTTP status codes in the 2xx range all mean success  -  I can use them interchangeably."
Reality: 200, 201, 202, and 204 have specific meanings. A client that creates a resource expects 201 Created with a Location header. A client that deletes a resource expects 204 No Content. Returning 200 for all success responses loses these signals and forces clients to parse the body to understand what happened.

---

## Why It Matters in Practice

A well-designed API is adopted quickly and used correctly. A poorly designed API causes support tickets, incorrect usage, security issues from improperly handled status codes, and costly breaking changes when the API needs to evolve. For Python developers building FastAPI or Django REST framework APIs, these principles are supported by the framework  -  FastAPI's `status_code`, `response_model`, and Pydantic validation enforce many of these decisions automatically.

The consistency principle deserves emphasis: within a single API, every endpoint should follow the same conventions for naming, error format, status codes, and field names. Inconsistency is the number one complaint developers have about APIs they use.

---

## Interview Angle

Common question forms:
- "What makes a good REST API design?"
- "What is the difference between PUT and PATCH?"
- "When would you return a 409 vs a 422 status code?"

Answer frame:
Start with resource naming (nouns, plural, nested relationships). Explain HTTP method semantics (GET/POST/PUT/PATCH/DELETE) with idempotency. Walk through status code groups and when to use specific codes (201 on create, 204 on delete, 409 on conflict, 422 on semantic validation failure). Describe a standard error format: error_code + message + optional details. Emphasize consistency as the top design principle.

---

## Related Notes

- [[api-versioning|API Versioning]]
- [[idempotency|Idempotency]]
- [[pagination|Pagination Patterns]]
- [[rest|REST]]
- [[fastapi|FastAPI]]
