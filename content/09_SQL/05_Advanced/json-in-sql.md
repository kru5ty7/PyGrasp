---
title: JSON in PostgreSQL
description: PostgreSQL's JSONB type stores semi-structured data in an indexed binary format, enabling flexible schemas and powerful JSON queries within a relational database.
tags: [sql, layer-9, json, jsonb, postgresql]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# JSON in PostgreSQL

> PostgreSQL's JSONB type turns the database into a document store without giving up relational joins, transactions, or SQL — but knowing when not to use it matters as much as knowing how.

---

## Quick Reference

**Core idea:**
- JSON stores data as text (validated but not indexed); JSONB stores as binary (indexed, faster queries) — prefer JSONB
- -> extracts a JSON field and returns JSON; ->> extracts and returns text
- #> and #>> navigate nested paths using array syntax
- @> is the containment operator: checks if the left JSONB contains the right JSONB as a subset
- GIN index on a JSONB column enables fast containment and key existence queries
- jsonb_set() performs partial updates to a JSONB value

**Tricky points:**
- JSONB does not preserve key order or duplicate keys; JSON does preserve order and allows duplicates
- Updating a single field in a large JSONB document requires rewriting the entire column value
- GIN indexes are large; creating one on a large JSONB column with many keys is storage-intensive
- Querying inside JSONB is less efficient than querying indexed relational columns for equality lookups
- The hybrid approach — structured columns for frequently queried fields, JSONB for everything else — is usually best

---

## What It Is

Think of a relational table as a spreadsheet where every cell in a column holds the same type of value, and every row has exactly the same columns. This is rigid but extremely efficient. Now think of a JSONB column as one column in that spreadsheet where any cell can hold a completely different JSON document — some cells have five keys, some have fifty, some have nested arrays of objects. The spreadsheet's other columns remain rigidly structured, queryable, and indexed. The JSONB column adds a flexible pocket for everything that does not fit the rigid schema. You get the best of both models in one row.

PostgreSQL introduced native JSON support with JSON (added in 9.2) and JSONB (added in 9.4). The difference is in how they store data. JSON validates the input and stores it verbatim as text — whitespace preserved, key order preserved, duplicate keys allowed. JSONB parses the JSON, stores it in a decomposed binary format, discards whitespace, deduplicates keys (last value wins), and does not preserve key order. The binary representation is what enables indexing. Almost every production use case should use JSONB.

The practical appeal of JSONB is handling varying schemas in a relational database. An e-commerce product catalog might have 10 attributes that all products share (name, price, category, SKU) and 50 attributes that vary by product type (electronics have wattage and voltage; clothing has size and material; food has ingredients and allergens). Normalizing all possible attributes into relational columns produces a table with hundreds of nullable columns, most empty for any given row. An EAV (Entity-Attribute-Value) table avoids nullable columns but makes queries extremely verbose. JSONB stores the varying attributes in a single column per row, queryable with JSON operators, and optionally indexed.

The cost of JSONB's flexibility is that querying inside a JSONB column is more expensive than querying a regular indexed column. An equality check on a JSONB field (WHERE attributes->>'color' = 'blue') without a GIN index requires scanning every row and extracting the field from each document. Even with a GIN index, JSONB containment queries do not use a B-tree lookup the way an indexed integer column does. The rule of thumb is: any field you query frequently and need to JOIN on should be a proper relational column. JSONB is for fields you query occasionally, store for completeness, or cannot predict in advance.

---

## How It Actually Works

The core operators for reading JSONB are the arrow operators. The -> operator returns a JSON value (preserving type). The ->> operator returns a text value (casts the JSON value to text). The #> operator navigates a path using an array of keys. The #>> operator does the same but returns text.

```sql
-- Sample table with JSONB metadata column
CREATE TABLE products (
    id         BIGSERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    price      NUMERIC(10,2) NOT NULL,
    attributes JSONB
);

INSERT INTO products (name, price, attributes) VALUES
    ('Laptop', 1299.99, '{"color": "silver", "weight_kg": 1.4, "specs": {"ram_gb": 16, "storage_gb": 512}}'),
    ('T-Shirt', 29.99,  '{"color": "blue", "sizes": ["S", "M", "L", "XL"], "material": "cotton"}');

-- -> returns JSONB (preserves type)
SELECT attributes -> 'color' FROM products;
-- "silver"
-- "blue"

-- ->> returns TEXT
SELECT attributes ->> 'color' FROM products;
-- silver
-- blue

-- Navigate nested paths
SELECT attributes #>> '{specs, ram_gb}' FROM products;
-- 16
-- (null for T-Shirt which has no specs.ram_gb)
```

The containment operator @> is the key operator for GIN-indexed searches. It checks whether the left JSONB value contains all the key-value pairs of the right JSONB value:

```sql
-- Find all products with color blue
SELECT name FROM products
WHERE attributes @> '{"color": "blue"}';

-- Find products with at least 16GB RAM (nested)
SELECT name FROM products
WHERE attributes @> '{"specs": {"ram_gb": 16}}';
```

Creating a GIN index to make these queries fast:

```sql
-- GIN index on the entire JSONB column (indexes all keys and values)
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);

-- Alternative: GIN index with jsonb_path_ops (smaller, faster for @> only)
CREATE INDEX idx_products_attributes_path ON products USING GIN (attributes jsonb_path_ops);
```

Partial updates with jsonb_set avoid rewriting the entire document:

```sql
-- Update a single nested field
UPDATE products
SET attributes = jsonb_set(attributes, '{specs, ram_gb}', '32')
WHERE id = 1;

-- Add a new key to the JSONB object
UPDATE products
SET attributes = attributes || '{"in_stock": true}'
WHERE id = 2;

-- Remove a key
UPDATE products
SET attributes = attributes - 'material'
WHERE id = 2;
```

The jsonb_each() and jsonb_array_elements() functions expand JSONB objects and arrays into rows, enabling joins and aggregations:

```sql
-- Expand JSONB object keys into rows
SELECT id, key, value
FROM products, jsonb_each(attributes)
WHERE id = 1;

-- Expand a JSONB array into rows
SELECT id, size
FROM products, jsonb_array_elements_text(attributes -> 'sizes') AS size
WHERE id = 2;
```

---

## How It Connects

JSONB and PostgreSQL full-text search share the GIN index type. Both index data that does not fit the B-tree model — full-text search indexes word stems across a document, JSONB indexes keys and values across a document. Understanding why GIN exists and what it is optimized for applies to both use cases.

The hybrid approach to JSONB — structured columns for relational data, JSONB for semi-structured metadata — is a standard pattern in Python web applications using ORMs like SQLAlchemy. The JSONB column is often mapped to a dict in the Python model, with read/write handled transparently by the ORM. Understanding the SQL semantics underneath helps when debugging queries generated by the ORM.

[[sql-indexes|SQL Indexes]]
[[full-text-search|Full Text Search]]
[[data-types|Data Types]]
[[composite-indexes|Composite Indexes]]

---

## Common Misconceptions

Misconception 1: "JSON and JSONB are interchangeable — choose either."
Reality: JSON and JSONB have different storage characteristics, different capabilities, and different use cases. JSON preserves whitespace, key order, and duplicate keys, but cannot be indexed (no GIN support) and queries are slower. JSONB is binary, deduplicated, indexed, and faster to query. In almost every production application, JSONB is the correct choice. JSON is useful only when key order or duplicate keys are semantically significant, which is rare.

Misconception 2: "JSONB is always better than normalized tables for flexible data."
Reality: JSONB trades query flexibility for query efficiency. A WHERE clause on an indexed integer column is faster than the equivalent JSONB containment query. JOIN operations on foreign keys are faster than JOINs that extract values from JSONB. If a field is queried in every WHERE clause or used as a JOIN key, it belongs in a proper relational column with a B-tree index. JSONB shines for data that is stored for completeness, queried occasionally, or highly variable in structure.

Misconception 3: "You can update a single key inside a JSONB column efficiently."
Reality: Every UPDATE to a JSONB column rewrites the entire column value for that row, even if only one key changed. Unlike a dedicated column where only that column is rewritten, a JSONB update is always a full-document rewrite internally. For JSONB documents that are very large (hundreds of keys) and frequently partially updated, this can generate significant write amplification and dead tuples requiring autovacuum.

---

## Why It Matters in Practice

JSONB in PostgreSQL fills the gap that previously required either a separate document database (MongoDB) or a rigid EAV schema. For applications that are primarily relational but have one or two entities with truly variable attributes — user preferences, product metadata, audit event payloads, webhook request/response bodies — JSONB allows the flexible storage without adding a second database system to the infrastructure.

The practical pattern most commonly seen in Python applications is storing event or audit data as JSONB. An events table has structured columns for the event type, user ID, timestamp, and a JSONB column for the event payload. Different event types have completely different payload schemas. Querying by event type uses the indexed column; querying by payload contents uses the GIN index when needed. The application code receives the payload as a Python dict via the ORM, with no schema migration required when a new payload field is added.

---

## What Breaks

**Unindexed JSONB query causing full table scan.** A developer adds a WHERE clause filtering on a JSONB key — WHERE metadata->>'tenant_id' = '42' — without creating a GIN index. On a small table this is imperceptible. After the table grows to 10 million rows, this query takes 30 seconds. EXPLAIN ANALYZE shows a Seq Scan with Filter. A GIN index or, better, promoting tenant_id to a proper indexed column fixes the issue.

```sql
-- Better: extract frequently-queried JSONB values into indexed generated columns
ALTER TABLE events
ADD COLUMN tenant_id TEXT GENERATED ALWAYS AS (metadata->>'tenant_id') STORED;

CREATE INDEX ON events (tenant_id);
```

**JSONB column storing data that should be normalized.** A team uses JSONB to store order line items as an array of objects inside the order row. Later, they need to query all orders containing a specific product. The query requires @> containment search and cannot efficiently use a JOIN or FK index. Aggregating revenue per product requires JSON expansion. What started as flexibility has become a query anti-pattern. Data that needs to be joined or aggregated belongs in its own table.

**Key name typos causing silent nulls.** A query selects attributes->>'colur' (typo) instead of attributes->>'color'. The ->> operator returns NULL when the key does not exist, not an error. Every row in the result has NULL for that column. The developer does not notice because the query succeeds silently. JSONB provides no schema enforcement — typos in key names are invisible at the SQL level.

---

## Interview Angle

Common question forms:
- "What is the difference between JSON and JSONB in PostgreSQL?"
- "When would you use JSONB instead of normalizing into separate columns?"
- "How do you index JSONB data for fast queries?"
- "What are the downsides of storing data as JSONB?"

Answer frame:
Lead with the JSON vs JSONB distinction — binary storage, indexing capability, prefer JSONB. Explain the use case: semi-structured data with varying keys, metadata columns, event payloads. Describe the GIN index for the @> containment operator. Then pivot to when NOT to use JSONB: data you JOIN on, data you filter on in every query, data with a stable known schema — all of these belong in proper relational columns. The hybrid approach (structured + JSONB metadata) is the pattern that shows maturity.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[full-text-search|Full Text Search]]
- [[data-types|Data Types]]
- [[composite-indexes|Composite Indexes]]
- [[partitioning|Table Partitioning]]
