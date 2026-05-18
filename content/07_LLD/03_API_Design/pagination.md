---
title: 07 - Pagination Patterns
description: "Offset pagination vs cursor-based pagination  -  why offset breaks on large datasets and why cursors provide stable, efficient pagination at scale."
tags: [pagination, api-design, performance, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Pagination Patterns

> Offset pagination is intuitive and breaks at scale; cursor pagination is less intuitive and works at scale  -  knowing when each applies is an API design decision with real performance consequences.

---

## Quick Reference

**Core idea:**
- Offset pagination: `SELECT ... LIMIT 20 OFFSET 100`  -  skip 100 rows, return next 20
- Cursor pagination: encode the last item's position as an opaque token; next page starts after that position
- Offset breaks at large offsets: `OFFSET 10000` requires the database to scan and discard 10,000 rows
- Cursor handles concurrent data changes gracefully  -  inserted or deleted items do not shift page contents
- Page-number UI (1, 2, 3...) requires offset; infinite scroll and API pagination prefer cursor

**Tricky points:**
- Cursors must encode enough information to uniquely identify a position  -  not just an ID if records share timestamps
- Offset pagination returns incorrect results when items are inserted or deleted between page requests
- A cursor is opaque to clients  -  never let clients parse or construct cursors themselves
- Cursor-based pagination cannot jump to arbitrary pages ("go to page 50")  -  only next/previous
- Keyset pagination is the database-level technique behind cursor pagination

---

## What It Is

Think of reading a novel. Offset pagination is like saying "skip to page 200 and read from there." You open the book to page 200 by counting pages. If someone tears out pages 150 - 180 while you are reading, your bookmark on page 200 now points to the wrong content. Cursor pagination is like using an actual bookmark: a slip of paper between two specific pages. When you return to the book, you open it at the bookmark regardless of what happened to other pages. Your position is defined by the content, not the number.

Offset pagination is the oldest and most common approach. A client requests page N with size P by specifying `LIMIT P OFFSET N*P`. The database returns rows starting at position N*P. This is simple, supports jumping to any page number, and maps intuitively to UI elements like page number links. The SQL is straightforward.

Cursor-based pagination encodes the position in the result set as an opaque cursor token. The first request returns a page of results plus a cursor representing the last item returned. The next request sends that cursor, and the server returns the next page starting after the cursor's position. The cursor might encode the last item's ID and timestamp in a base64-encoded JSON string.

The problem with offset pagination at scale is the database's behavior. `OFFSET 10000` does not skip 10,000 rows cheaply  -  it reads 10,000 rows and discards them, returning the next page. For tables with millions of rows, a request for the 500th page of 20 items (`OFFSET 10000`) scans and discards 10,000 rows before returning 20. This adds up to significant database load for deep pagination requests, and the performance degrades linearly with the offset value.

The second problem with offset pagination is consistency under concurrent modification. When users browse pages of a product catalog and another user adds 3 new products between two page requests, every subsequent page shifts by 3 items. Items that were on page 3 appear on page 4. The user browsing sequentially skips 3 items, never seeing them. Cursor pagination prevents this: the cursor points to a specific item, so new items added before or after it do not affect the cursor's reference point.

---

## How It Actually Works

Keyset pagination is the database technique behind cursor pagination. Instead of `LIMIT N OFFSET M`, it uses `WHERE (created_at, id) > (cursor_created_at, cursor_id) LIMIT N`. This requires an index on the columns used in the WHERE clause and ORDER BY, but uses the index efficiently  -  no rows are discarded, the query starts at the indexed cursor position and reads N rows forward. Performance is constant regardless of how deep in the result set the cursor is.

The cursor itself is an encoded representation of the last item returned. Common implementations encode the item's sortable fields into a base64 or JSON string that the client treats as opaque. The server decodes it on the next request to reconstruct the WHERE clause. Cursors should be signed or encrypted to prevent clients from constructing arbitrary positions that the server would trust, which could allow accessing data out of order or bypassing access controls.

```python
from fastapi import FastAPI, Query
from pydantic import BaseModel
import base64
import json
from typing import Optional

app = FastAPI()

class User(BaseModel):
    id: str
    name: str
    created_at: str

class PaginatedResponse(BaseModel):
    items: list[User]
    next_cursor: Optional[str] = None
    has_next_page: bool

def encode_cursor(created_at: str, id: str) -> str:
    """Encode the cursor position as an opaque token."""
    data = json.dumps({"created_at": created_at, "id": id})
    return base64.b64encode(data.encode()).decode()

def decode_cursor(cursor: str) -> dict:
    """Decode the cursor  -  validate that it is well-formed."""
    try:
        data = base64.b64decode(cursor.encode()).decode()
        return json.loads(data)
    except (ValueError, json.JSONDecodeError):
        raise ValueError("Invalid cursor")

@app.get("/users", response_model=PaginatedResponse)
async def list_users(
    limit: int = Query(default=20, le=100, ge=1),
    cursor: Optional[str] = Query(default=None)
):
    if cursor:
        pos = decode_cursor(cursor)
        # Keyset pagination: WHERE (created_at, id) > (last_created_at, last_id)
        users = await db.fetch_all(
            """
            SELECT id, name, created_at FROM users
            WHERE (created_at, id) > (:cursor_ts, :cursor_id)
            ORDER BY created_at ASC, id ASC
            LIMIT :limit
            """,
            {"cursor_ts": pos["created_at"], "cursor_id": pos["id"], "limit": limit + 1}
        )
    else:
        users = await db.fetch_all(
            "SELECT id, name, created_at FROM users ORDER BY created_at ASC, id ASC LIMIT :limit",
            {"limit": limit + 1}
        )

    has_next = len(users) > limit
    page_items = users[:limit]

    next_cursor = None
    if has_next and page_items:
        last = page_items[-1]
        next_cursor = encode_cursor(last["created_at"], last["id"])

    return PaginatedResponse(
        items=[User(**u) for u in page_items],
        next_cursor=next_cursor,
        has_next_page=has_next
    )

# Offset pagination (for comparison  -  fine for small datasets)
@app.get("/users/offset", response_model=dict)
async def list_users_offset(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=20, le=100)
):
    offset = (page - 1) * size
    total = await db.fetch_val("SELECT COUNT(*) FROM users")
    users = await db.fetch_all(
        "SELECT id, name, created_at FROM users ORDER BY created_at LIMIT :size OFFSET :offset",
        {"size": size, "offset": offset}
    )
    return {
        "items": users,
        "total": total,
        "page": page,
        "total_pages": (total + size - 1) // size
    }
```

The `limit + 1` trick is a standard way to detect whether there is a next page without a separate COUNT query. You request one more item than the page size. If you get `limit + 1` results back, there is a next page  -  you return only `limit` items to the client. If you get `limit` or fewer, you are on the last page. This avoids the expensive `COUNT(*)` query on large tables.

Total count is a challenge for cursor pagination. Offset pagination naturally provides total count (and therefore total pages) from a `COUNT(*)` query. Cursor pagination does not need total count for the pagination mechanism itself, but UIs often want to show "showing items 1-20 of 12,345". For large tables, `COUNT(*)` is expensive. Alternatives: approximate counts using table statistics, cached counts updated by a background job, or progressive disclosure ("there are more results").

---

## How It Connects

Pagination is closely related to database index design. Cursor pagination's keyset approach requires an index on the ORDER BY columns for efficient execution.

[[database-indexes|Database Indexes]]

API design principles govern how pagination parameters are named and how the response is structured. The standard for GraphQL cursor pagination is the Relay specification.

[[api-design-principles|API Design Principles]]

GraphQL's Relay-compatible pagination (Connection type with edges, node, pageInfo) is the standardized form of cursor pagination in the GraphQL ecosystem.

[[graphql-design|GraphQL Design]]

---

## Common Misconceptions

Misconception 1: "Offset pagination is fine for my dataset."
Reality: Offset pagination is fine for small datasets (under ~50,000 rows). For larger datasets, `OFFSET 100000` scans and discards 100,000 rows before returning 20. Response time grows linearly with offset. This becomes noticeable for users who scroll to the end of a long list or for automated processes iterating through large datasets.

Misconception 2: "Cursor pagination always returns consistent results."
Reality: Cursor pagination is consistent for items added after the cursor position  -  they appear on later pages. Items deleted after the cursor is issued may create "missing" entries (the cursor points to a deleted item). A robust cursor implementation detects this (item at cursor position no longer exists) and adjusts the query accordingly.

Misconception 3: "I can use a cursor based on just the primary key."
Reality: A cursor based only on an auto-increment integer ID works if results are ordered by ID. If results are ordered by `created_at` (which is not unique  -  multiple items can share the same timestamp), a cursor based only on `created_at` is ambiguous. The cursor must include all ORDER BY columns plus enough columns to uniquely identify a row. Using `(created_at, id)` as a compound cursor handles ties in `created_at`.

---

## Why It Matters in Practice

Most application APIs that expose lists of data need pagination. For small datasets, the choice rarely matters. As datasets grow  -  thousands of records, then millions  -  the choice between offset and cursor becomes a performance question. A product catalog with 500,000 items paginated with offset pagination will have noticeably slow response times for later pages. The same catalog with cursor pagination performs identically on page 1 and page 10,000.

For Python API development, implementing cursor pagination correctly requires attention to the compound cursor (multiple sort columns), the limit+1 trick for detecting next pages, and the index on the ORDER BY columns. The code is slightly more complex than offset pagination, but the performance profile is predictable and scales.

---

## Interview Angle

Common question forms:
- "What are the trade-offs between offset and cursor pagination?"
- "Why does offset pagination break on large datasets?"
- "How would you implement cursor-based pagination?"

Answer frame:
Define offset pagination: LIMIT/OFFSET, supports page numbers, degrades at large offsets (full scan to discard). Define cursor pagination: keyset WHERE clause, O(1) regardless of depth, no page jumping. Explain why offset breaks at large offsets: the database scans and discards N rows. Explain the consistency advantage of cursor: new items don't shift pages. Describe cursor implementation: encode (created_at, id) in an opaque token, decode for the WHERE clause, use limit+1 to detect next page.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[database-indexes|Database Indexes]]
- [[graphql-design|GraphQL Design]]
- [[rest|REST]]
