---
title: 11 - MongoDB with Python
description: "pymongo is the standard synchronous Python driver for MongoDB, while motor provides async support — both give access to MongoDB's document model through Python dicts and query operators."
tags: [mongodb, pymongo, motor, beanie, nosql, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# MongoDB with Python

> MongoDB stores documents as JSON-like objects rather than rows in tables — pymongo lets you query, filter, and modify those documents using Python dicts and MongoDB's operator-based query language.

---

## Quick Reference

**Core idea:**
- `MongoClient(host)` connects; `client['dbname']['collection']` navigates to a collection
- `insert_one(doc)` / `insert_many(docs)`, `find_one(filter)` / `find(filter)`, `update_one(filter, update)`, `delete_one(filter)`
- Query operators: `{'age': {'$gte': 18}}`, `{'$or': [{'x': 1}, {'y': 2}]}`, `{'status': {'$in': ['active', 'pending']}}`
- Indexes: `create_index([('email', ASCENDING)], unique=True)` — critical for performance; MongoDB scans all documents without an index
- `motor` for async operations; `beanie` for an ODM (Object Document Mapper) layer on top of motor

**Tricky points:**
- Every document gets a `_id` field automatically — it is a `bson.ObjectId`, not an integer; serialization requires `str(doc['_id'])` for JSON output
- `find()` returns a cursor, not a list — iterate it or call `list(collection.find(...))` to materialize results
- `update_one()` with a bare dict replaces the matched fields — use `{'$set': {'field': value}}` to update specific fields without replacing the whole document
- MongoDB has no foreign keys or joins — "joins" are either `$lookup` aggregation pipeline stages or application-side fetches
- Schema validation is optional — MongoDB will accept any document shape by default; enforce structure at the application layer via Pydantic or beanie models

---

## What It Is

Relational databases store data in a fixed schema — every row in a table has the same columns. MongoDB takes a different philosophy: every document in a collection can have a different shape. A user document might have five fields; another might have twenty. New fields can be added to some documents without migrating all existing ones. This flexibility trades the consistency guarantees of relational normalization for development speed and schema agility.

Documents in MongoDB are stored as BSON (Binary JSON), a binary-encoded superset of JSON that supports additional types like `ObjectId`, `Date`, and `Binary`. From Python's perspective, documents look and behave like dictionaries — you can nest dicts, include lists, and embed arbitrary structures. A user's address is not stored in a separate `addresses` table with a foreign key; it is embedded directly in the user document as a nested dict. This embedding model is efficient for reads — one document fetch retrieves the user and all their embedded data simultaneously.

pymongo, the official MongoDB Python driver, exposes this document model directly. Collections are analogous to tables; documents are dicts. Queries are also dicts using MongoDB's operator syntax. This consistency — everything is a dict — means that developers who understand Python dicts can be productive with pymongo very quickly. The library handles BSON encoding and decoding, connection pooling, replica set awareness, and cursor management transparently.

---

## How It Actually Works

The pymongo client connects lazily — the actual TCP connection is not opened until the first operation. For applications, create the client once at startup and reuse it across requests.

```python
from pymongo import MongoClient, ASCENDING

client = MongoClient("mongodb://localhost:27017")
db = client["myapp"]
users = db["users"]

# Insert
result = users.insert_one({"name": "Alice", "email": "alice@example.com", "age": 30})
print(result.inserted_id)  # bson.ObjectId

# Find one
user = users.find_one({"email": "alice@example.com"})
print(user["name"])  # "Alice"

# Find many with query operator
adult_users = list(users.find({"age": {"$gte": 18}}, {"name": 1, "email": 1, "_id": 0}))
# second dict is a projection: include name and email, exclude _id

# Update (must use $set to avoid replacing the whole document)
users.update_one({"email": "alice@example.com"}, {"$set": {"age": 31}})

# Delete
users.delete_one({"email": "alice@example.com"})

# Index for fast email lookups
users.create_index([("email", ASCENDING)], unique=True)
```

For async applications, `motor` provides a drop-in async wrapper with an identical API.

```python
import motor.motor_asyncio

client = motor.motor_asyncio.AsyncIOMotorClient("mongodb://localhost:27017")
db = client["myapp"]
users = db["users"]

user = await users.find_one({"email": "alice@example.com"})
await users.insert_one({"name": "Bob", "email": "bob@example.com"})
```

`beanie` is an ODM built on top of motor that provides Pydantic-based document models — similar to how SQLAlchemy ORM sits on top of SQLAlchemy Core.

```python
from beanie import Document, init_beanie
from pydantic import EmailStr

class User(Document):
    name: str
    email: EmailStr
    age: int

    class Settings:
        name = "users"  # MongoDB collection name

# Initialize at startup
await init_beanie(database=db, document_models=[User])

# Type-safe CRUD
user = await User(name="Alice", email="alice@example.com", age=30).insert()
found = await User.find_one(User.email == "alice@example.com")
```

---

## How It Connects

beanie uses Pydantic for document validation — the same Pydantic models used for FastAPI request/response schemas can serve as MongoDB document definitions.

[[pydantic|Pydantic]]

Motor's async interface follows the same asyncio patterns as other async Python database drivers — understanding the event loop context is essential for correct usage.

[[asyncio|asyncio]]

---

## Common Misconceptions

Misconception 1: "MongoDB is schema-less so I don't need to think about data structure."
Reality: MongoDB documents have no enforced schema by default, but the application still needs a consistent structure to query and display data correctly. An unexpected missing field causes `KeyError` or `None` results. Schema validation at the driver level (via beanie/Pydantic) catches these issues at write time rather than silently accepting malformed documents.

Misconception 2: "Updating a document with `update_one({'_id': id}, new_data)` merges the new data into the existing document."
Reality: Without an update operator like `$set`, MongoDB replaces the matched document entirely with `new_data` — the old fields are gone. Always use `{'$set': {'field': value}}` for partial updates.

---

## Why It Matters in Practice

MongoDB is a common choice for applications where document structure varies — content management, user profiles with heterogeneous attributes, or event logs. Knowing pymongo's query operator syntax, index creation, and the `$set` vs replace distinction prevents data loss bugs and query performance problems. motor and beanie are the standard async path, and knowing when beanie's ODM layer is worth the overhead (structured data with validation) versus motor's lower-level control (raw document manipulation) helps in architecture decisions.

---

## Interview Angle

Common question forms:
- "How do you query MongoDB in Python?"
- "What is the difference between pymongo and motor?"
- "How do you do an async MongoDB query in a FastAPI application?"

Answer frame:
pymongo is the standard sync driver — queries are Python dicts with MongoDB operators (`$gte`, `$in`, `$set`). motor is the async wrapper with an identical API. beanie adds a Pydantic ODM layer on motor for type-safe document models. Key gotcha: `update_one()` without `$set` replaces the document — always use `$set` for partial updates. Indexes are critical — without them MongoDB performs full collection scans.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[asyncio|asyncio]]
- [[async-await|Async/Await]]
- [[fastapi|FastAPI]]
