---
title: 02 - API Versioning
description: "URL vs header vs query parameter versioning, backward compatibility strategies, and how to deprecate old API versions without breaking existing clients."
tags: [api-versioning, api-design, backward-compatibility, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# API Versioning

> Every API will need to change, and every API has consumers who depend on it not changing — versioning is the design discipline that lets both be true simultaneously.

---

## Quick Reference

**Core idea:**
- URL versioning: `/v1/users` — explicit, visible, easily cached; most common approach
- Header versioning: `Accept: application/vnd.example.v2+json` — clean URLs, harder to test and share
- Query parameter: `/users?version=2` — flexible but mixing routing concerns with query parameters
- Backward compatibility: additive changes (new fields, new endpoints) are safe; removing or changing fields is breaking
- Sunset headers: `Sunset: Sat, 01 Jan 2027 00:00:00 GMT` signals when a version will be removed

**Tricky points:**
- "Versioning everything upfront" is over-engineering — start without versions, add when breaking changes are necessary
- Adding an optional field to a response is backward compatible; removing a field is always breaking
- Client parsing of unknown fields (lenient parsers) vs strict parsers determines what "breaking" means for a change
- A major version bump (v1 → v2) should be reserved for fundamental redesigns, not incremental changes
- Never silently change behavior in the same version — this breaks the version contract

---

## What It Is

Think of software documentation as a promise to users. When you publish an API, you are making a promise: send this request, receive this response. If you change the API — rename a field, change a field's type, remove a feature — you break that promise. Users who built their code against the old API suddenly find it is broken. API versioning is how you maintain the old promise while also making a new, different promise.

The core problem is that APIs evolve. Business requirements change. Mistakes need correction. New features require changes to the data model. But once an API is in production with real consumers, you cannot simply change it — you need a strategy for evolving the API while honoring existing integrations.

URL versioning is the most common approach: the version is embedded in the URL path. `/v1/users` points to version 1; `/v2/users` points to version 2. This is explicit, highly visible, easily cacheable, and simple to route at the infrastructure level. Load balancers and proxies can route `/v1/*` and `/v2/*` to different backend services, enabling different teams to own different versions simultaneously. The downside is that it makes URLs less "clean" from a REST purist's perspective (the URL should identify a resource, not a version of the API), and it multiplies the number of URLs a client must know.

Header versioning passes the version in an HTTP header, usually via a custom `Accept` header using content negotiation: `Accept: application/vnd.myapi.v2+json`. This keeps URLs clean — `/users` remains `/users` for all versions. Versioning is a concern of the content type, not the resource address. The downside is practical: you cannot paste a URL into a browser and specify a custom header. API testing and sharing are harder. Most CDNs and proxies route on URL, not headers.

Query parameter versioning appends the version to the URL: `/users?api_version=2`. This is easy to use and does not require headers, but it mixes version information with query parameters, which are semantically for filtering and searching, not routing.

---

## How It Actually Works

Backward compatibility is the discipline of making changes that do not break existing consumers. Changes are additive (adding new fields to responses, adding new optional request parameters, adding new endpoints) or breaking (removing fields, changing field types, changing behavior). Additive changes are safe in minor versions. Breaking changes require a new major version.

A practical rule: assume clients ignore unknown fields (lenient parsing). Most modern JSON clients skip fields they do not recognize. Adding a new field to a response is therefore safe — old clients ignore it. Removing a field is always breaking — old clients that read that field will fail. Changing a field's type (string to integer) is breaking. Renaming a field is breaking. Changing the semantics of a field (it used to mean "total in dollars" and now means "total in cents") is breaking even if the type is the same.

The Sunset header (`Sunset: RFC-date`) is the standard mechanism for announcing API deprecation. Adding it to responses from an old version tells clients and intermediate systems (monitoring tools, API gateways) when this version will be removed. Combined with a `Deprecation` header and a `Link` header pointing to documentation for the new version, this forms a complete deprecation signal. Responsible API consumers read these headers and proactively upgrade.

```python
from fastapi import FastAPI, APIRouter, Request, Response
from datetime import datetime

# Version 1 router — maintained for backward compatibility
v1_router = APIRouter(prefix="/v1")

@v1_router.get("/users/{user_id}")
async def get_user_v1(user_id: str, response: Response):
    # Add deprecation headers to v1 responses
    response.headers["Sunset"] = "Sat, 01 Jan 2027 00:00:00 GMT"
    response.headers["Deprecation"] = "true"
    response.headers["Link"] = '</v2/users/{user_id}>; rel="successor-version"'

    user = await db.get_user(user_id)
    # V1 response format: old field names, old structure
    return {
        "user_id": user["id"],       # old field name
        "user_name": user["name"],   # old field name (v2 uses "name")
        "email_address": user["email"]  # old field name (v2 uses "email")
    }

# Version 2 router — current version
v2_router = APIRouter(prefix="/v2")

@v2_router.get("/users/{user_id}")
async def get_user_v2(user_id: str):
    user = await db.get_user(user_id)
    # V2 response format: cleaner, consistent names
    return {
        "id": user["id"],
        "name": user["name"],
        "email": user["email"],
        "created_at": user["created_at"],  # new field not in v1
    }

app = FastAPI()
app.include_router(v1_router)
app.include_router(v2_router)

# Routing can also be done at Nginx level:
# location /v1/ { proxy_pass http://api-v1-service; }
# location /v2/ { proxy_pass http://api-v2-service; }
```

API versioning strategy should also address when to create a new version. A common heuristic: a new major version is needed when the change is breaking for most existing consumers. A non-breaking additive change (new optional field, new endpoint) does not need a version bump. Incremental deprecation — marking specific endpoints as deprecated within the same version using headers — handles evolutionary changes without a full version bump.

The decision of how many versions to maintain simultaneously is a support burden question. Each live version requires testing, maintenance, and operational support. Most organizations maintain at most two versions simultaneously (current and the previous one), with a clear deprecation timeline for the older version.

---

## How It Connects

API versioning is the mechanism for safely evolving the API design principles described in the companion note. Breaking changes require version bumps; non-breaking changes do not.

[[api-design-principles|API Design Principles]]

API gateways can enforce version routing: `/v1/*` goes to one backend service, `/v2/*` to another. This infrastructure-level separation enables different teams to independently develop and deploy different API versions.

[[api-gateway|API Gateway]]

In GraphQL, the versioning problem is handled differently: the schema evolves with backward-compatible additions, and deprecated fields are marked with `@deprecated` directives. Understanding how REST versioning compares to GraphQL's approach helps in choosing between them.

[[graphql-design|GraphQL Design]]

---

## Common Misconceptions

Misconception 1: "I should version my API from day one, even before it has any consumers."
Reality: Premature versioning adds complexity without benefit. Version when you need to make breaking changes with existing consumers. Many internal APIs never need versioning. Start clean, add versioning when the first breaking change is required. The cost of adding versioning later (a one-time refactor) is much lower than the cost of maintaining multiple versions indefinitely.

Misconception 2: "Adding a new field to a response is always a breaking change."
Reality: Adding new fields to a JSON response is backward compatible because well-written clients use lenient parsing and ignore fields they do not know about. The breaking changes are: removing existing fields, renaming existing fields, changing field types, changing semantics, and changing HTTP status codes for existing endpoints.

Misconception 3: "URL versioning is not RESTful."
Reality: Strict REST purists argue that the resource identifier (URL) should not encode a version of the representation. In practice, URL versioning is the most widely adopted approach because of its simplicity, cacheability, and routability. The theoretical purity of the alternative approaches (header versioning) does not justify their practical costs for most systems.

---

## Why It Matters in Practice

API consumers — mobile apps, third-party integrations, partner systems — cannot upgrade immediately when you release a new version. Mobile apps go through app store review. Enterprise partners have quarterly release cycles. Internal services have their own deployment schedules. An API that changes without versioning breaks all of these consumers simultaneously. Versioning gives consumers a migration window.

For Python API developers, the practical discipline is: before changing an existing API endpoint, ask whether the change is backward compatible. If yes, make the change. If no, create a new version. Document the change in the changelog. Add deprecation headers to the old version. Set a sunset date. Follow through on the deprecation.

---

## Interview Angle

Common question forms:
- "How would you version a REST API? What are the options?"
- "What is the difference between a breaking and a non-breaking API change?"
- "How do you communicate API deprecation to consumers?"

Answer frame:
Describe three versioning approaches: URL (most common), header, query parameter. Explain backward compatibility: additive changes are safe, changes to existing fields/behavior are breaking. Explain when to bump the major version: breaking changes with existing consumers. Describe sunset/deprecation headers. Discuss the practical support burden of maintaining multiple versions and the need for clear deprecation timelines.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[api-gateway|API Gateway]]
- [[rest|REST]]
- [[graphql-design|GraphQL Design]]
