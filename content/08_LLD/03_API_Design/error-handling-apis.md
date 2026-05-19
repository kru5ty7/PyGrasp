---
title: 07 - API Error Handling
description: API error handling defines how services communicate failures to clients through structured error responses, appropriate HTTP status codes, and consistent error formats that enable debugging without leaking internals.
tags: [api, error-handling, http, rest, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# API Error Handling

> API error handling communicates failures to clients through consistent, structured responses that identify the error type, provide actionable detail, and use appropriate HTTP status codes.

---

## Quick Reference

**Core idea:**
- Use **HTTP status codes** correctly: 4xx for client errors (fixable by the caller), 5xx for server errors (not the caller's fault)
- Return a **consistent error response format** across all endpoints - same structure for validation errors, auth failures, and server errors
- Include enough detail for debugging but never expose internal implementation (stack traces, SQL queries, file paths)
- Use **error codes** (machine-readable) alongside messages (human-readable) so that clients can handle errors programmatically
- Distinguish between **retryable** errors (503, 429, 502) and **non-retryable** errors (400, 404, 403)

**Tricky points:**
- `400 Bad Request` is overused - distinguish validation errors (422) from malformed requests (400)
- `500 Internal Server Error` should trigger alerts - if it happens regularly, it is a bug
- Rate limiting should return `429 Too Many Requests` with a `Retry-After` header
- Do not return `200 OK` with an error body - this breaks HTTP semantics and confuses clients, caches, and monitoring tools

---

## What It Is

Think of a bank teller. When you ask to withdraw more money than you have, the teller does not crash or give you a cryptic error code. They tell you exactly what went wrong ("insufficient funds"), how much you have ("balance: $50"), and what you can do about it ("try a smaller amount"). A good API error response works the same way: it tells the client what category of error occurred, provides specific details, and suggests corrective action.

API error handling is the contract between a service and its clients for how failures are communicated. Without a standard, one endpoint returns `{"error": "bad request"}`, another returns `{"message": "Validation failed", "errors": [...]}`, and a third returns a raw string. Clients cannot write generic error handling code because every endpoint behaves differently.

A well-designed error handling system uses HTTP status codes as the primary error category (the client's first indication of what went wrong), a consistent response body format with machine-readable error codes and human-readable messages, and optional metadata like field-level validation errors, request IDs for tracing, and retry guidance.

---

## How It Actually Works

The error response format should be consistent across all endpoints. A common structure includes: an error code (string, machine-readable), a message (human-readable), optional details (field errors, validation messages), and a request ID for server-side log correlation.

FastAPI provides built-in exception handlers that return structured JSON errors. You define custom exception classes for your domain errors and register handlers that convert them into the standard response format.

```python
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, field_validator
from typing import Any
from datetime import datetime
import uuid


# Standard error response model
class ErrorResponse(BaseModel):
    error_code: str
    message: str
    details: list[dict[str, Any]] | None = None
    request_id: str
    timestamp: str
    path: str


# Domain-specific exceptions
class AppError(Exception):
    def __init__(self, error_code: str, message: str, status_code: int = 400,
                 details: list[dict] | None = None):
        self.error_code = error_code
        self.message = message
        self.status_code = status_code
        self.details = details


class NotFoundError(AppError):
    def __init__(self, resource: str, resource_id: str):
        super().__init__(
            error_code="RESOURCE_NOT_FOUND",
            message=f"{resource} with id '{resource_id}' not found",
            status_code=404,
        )


class ConflictError(AppError):
    def __init__(self, message: str):
        super().__init__(
            error_code="CONFLICT",
            message=message,
            status_code=409,
        )


class RateLimitError(AppError):
    def __init__(self, retry_after: int = 60):
        super().__init__(
            error_code="RATE_LIMITED",
            message=f"Too many requests. Retry after {retry_after} seconds.",
            status_code=429,
        )
        self.retry_after = retry_after


# FastAPI app with custom error handlers
app = FastAPI()


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            error_code=exc.error_code,
            message=exc.message,
            details=exc.details,
            request_id=str(uuid.uuid4()),
            timestamp=datetime.now().isoformat(),
            path=str(request.url),
        ).model_dump(),
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Convert Pydantic validation errors to standard format."""
    details = [
        {
            "field": " -> ".join(str(loc) for loc in err["loc"]),
            "message": err["msg"],
            "type": err["type"],
        }
        for err in exc.errors()
    ]
    return JSONResponse(
        status_code=422,
        content=ErrorResponse(
            error_code="VALIDATION_ERROR",
            message="Request validation failed",
            details=details,
            request_id=str(uuid.uuid4()),
            timestamp=datetime.now().isoformat(),
            path=str(request.url),
        ).model_dump(),
    )


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all: never expose internal details to the client."""
    # Log the real error internally
    print(f"UNHANDLED ERROR: {exc}")
    return JSONResponse(
        status_code=500,
        content=ErrorResponse(
            error_code="INTERNAL_ERROR",
            message="An unexpected error occurred",
            details=None,  # never expose internals
            request_id=str(uuid.uuid4()),
            timestamp=datetime.now().isoformat(),
            path=str(request.url),
        ).model_dump(),
    )


# Usage in endpoints
class CreateUserRequest(BaseModel):
    name: str
    email: str

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("must contain @")
        return v


@app.post("/users")
async def create_user(body: CreateUserRequest):
    # Domain errors use custom exceptions
    existing = None  # simulate lookup
    if existing:
        raise ConflictError(f"User with email '{body.email}' already exists")

    return {"id": "new-user-id", "name": body.name, "email": body.email}


@app.get("/users/{user_id}")
async def get_user(user_id: str):
    # 404 with structured response
    raise NotFoundError("User", user_id)
```

---

## How It Connects

Error handling builds on HTTP status codes and REST principles. Understanding the semantics of each status code range is prerequisite.

[[api-design-principles|API Design Principles]]

[[http-status-codes|HTTP Status Codes]]

Pydantic validation errors are a common source of API errors. FastAPI converts Pydantic's `ValidationError` into HTTP 422 responses.

[[pydantic-validation|Pydantic Validation]]

Error responses should include request IDs that correlate with server-side logs for debugging distributed systems.

[[idempotency|Idempotency]]

---

## Common Misconceptions

Misconception 1: "Return 200 OK with an error message in the body."
Reality: HTTP status codes exist to communicate the outcome category. Returning 200 for errors breaks HTTP caches (they cache the "successful" error response), breaks monitoring (error rates show zero errors), and forces clients to parse the body to determine success vs failure.

Misconception 2: "Return detailed stack traces in error responses for debugging."
Reality: Stack traces expose internal file paths, library versions, database table names, and other information that helps attackers. Log detailed errors server-side with a request ID. Return only the request ID to the client so they can reference it when contacting support.

---

## Why It Matters in Practice

Consistent error handling reduces support tickets and integration time. When every endpoint returns errors in the same format with machine-readable error codes, clients can write generic error handling middleware once. When errors include request IDs, debugging becomes correlating the client's report with server logs instead of guessing.

---

## Interview Angle

Common question forms:
- "How do you design error responses for a REST API?"
- "What HTTP status codes do you use for different error types?"
- "How do you handle validation errors in an API?"

Answer frame:
Define a consistent error response format (code, message, details, request ID). Map error types to status codes (400 malformed, 404 not found, 409 conflict, 422 validation, 429 rate limit, 500 server). Show custom exception classes and FastAPI exception handlers. Emphasize never leaking internals and always including request IDs.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[http-status-codes|HTTP Status Codes]]
- [[pydantic-validation|Pydantic Validation]]
- [[idempotency|Idempotency]]
