---
title: Full Text Search
description: PostgreSQL's built-in full-text search uses tsvector and tsquery types with GIN indexes to provide efficient, linguistically-aware document search without an external search engine.
tags: [sql, layer-9, full-text-search, search, postgresql]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Full Text Search

> PostgreSQL's full-text search treats documents as bags of stems rather than raw strings — enabling natural language queries that match "running" to "run" and ranking results by relevance.

---

## Quick Reference

**Core idea:**
- tsvector is a pre-processed representation of a document: tokenized, lowercased, and stemmed
- tsquery is a processed search query, also stemmed and normalized
- The @@ operator tests whether a tsquery matches a tsvector
- to_tsvector('english', text) converts a string to a tsvector using English language rules
- to_tsquery('english', 'search & terms') builds a tsquery with AND/OR/NOT logic
- A GIN index on a tsvector column makes full-text search fast

**Tricky points:**
- Full-text search does not support fuzzy/typo-tolerant matching — use pg_trgm for that
- tsvector processing depends on the text search configuration (language) — mismatched configs produce wrong results
- Storing a pre-computed tsvector column and keeping it updated is important for performance
- ts_rank returns relevance scores but they are relative, not absolute
- plainto_tsquery is more forgiving than to_tsquery for user-entered text (no operators required)

---

## What It Is

Think of a library with a card catalog. The card catalog does not contain the books — it contains an index. Each card lists a keyword and the books where that word appears. But a good library catalog does more: it groups "running," "ran," and "runs" under the same card for "run." It ignores common words like "the" and "a" that appear everywhere. It lets you search for "cooking AND Italian NOT dessert." The card catalog is an index over the meaning of the text, not the text itself. PostgreSQL's full-text search works the same way: it converts text into an index representation (tsvector) that groups words by their stems and enables linguistic queries.

A tsvector is not the original text. It is a sorted list of lexemes — normalized word forms — along with positional information indicating where in the document each lexeme appeared. When PostgreSQL processes "The quick brown fox jumped over the lazy dog" into a tsvector, it discards "the" and "over" (stop words), lowercases everything, and stems the remaining words: "quick," "brown," "fox," "jump," "lazi," "dog." The resulting tsvector is compact and linguistically normalized. Two documents that use different forms of the same word (jumped, jumping, jumps) produce the same lexeme (jump) in their tsvectors, so a query for "jump" matches all of them.

A tsquery applies the same normalization to the search terms and adds Boolean logic. The query to_tsquery('english', 'jumping & fox') becomes the tsquery 'jump' & 'fox' after stemming. The @@ operator then checks whether the document's tsvector satisfies this query — does the tsvector contain both lexemes? If yes, the row is returned. This is a Boolean match: yes or no.

The limitation that follows from this design is that full-text search does not tolerate typos or spelling variations. A query for "recieve" (misspelled) does not match documents containing "receive" (correctly spelled), because they stem to different lexemes. For fuzzy matching, PostgreSQL provides pg_trgm (trigram similarity), which operates on character-level patterns rather than linguistic stems. A production search system sometimes combines both: full-text search for normal queries and trigram similarity for short strings or when the full-text match returns nothing.

---

## How It Actually Works

The basic workflow has three steps: convert documents to tsvector, build an index, and query with tsquery.

```sql
-- Convert text to tsvector (inspect what it looks like)
SELECT to_tsvector('english', 'The quick brown foxes jumped over the lazy dogs');
-- 'brown':3 'dog':9 'fox':4 'jump':5 'lazi':8 'quick':2

-- Build a tsquery
SELECT to_tsquery('english', 'jumping & fox');
-- 'jump' & 'fox'

-- Match using the @@ operator
SELECT to_tsvector('english', 'The quick brown foxes jumped')
    @@ to_tsquery('english', 'jump & fox');
-- true
```

For production use, pre-compute and store the tsvector in a column to avoid recomputing it on every query. Update it with a trigger or at write time.

```sql
-- Add a tsvector column to the articles table
ALTER TABLE articles ADD COLUMN search_vector tsvector;

-- Populate it
UPDATE articles
SET search_vector = to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''));

-- Create a GIN index on the tsvector column
CREATE INDEX idx_articles_fts ON articles USING GIN (search_vector);

-- Keep it updated with a trigger
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.search_vector = to_tsvector('english',
        coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, ''));
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_search_vector
BEFORE INSERT OR UPDATE ON articles
FOR EACH ROW EXECUTE FUNCTION update_search_vector();
```

Searching with ranking:

```sql
-- Search and rank results by relevance
SELECT
    id,
    title,
    ts_rank(search_vector, query) AS rank
FROM
    articles,
    to_tsquery('english', 'postgresql & performance') AS query
WHERE
    search_vector @@ query
ORDER BY
    rank DESC
LIMIT 10;
```

plainto_tsquery is more user-friendly for accepting free-form text input — it does not require the user to type & or | operators:

```sql
-- plainto_tsquery treats all words as AND
SELECT title FROM articles
WHERE search_vector @@ plainto_tsquery('english', 'postgresql performance');

-- phraseto_tsquery requires words to appear adjacent and in order
SELECT title FROM articles
WHERE search_vector @@ phraseto_tsquery('english', 'database performance');
```

Searching across multiple columns with different weights uses setweight to boost title matches over body matches:

```sql
-- Weight A (highest) for title, Weight B for body
UPDATE articles SET search_vector =
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(body, '')),  'B');
```

---

## How It Connects

GIN (Generalized Inverted iNdex) is the index type used for tsvector columns. Understanding why GIN is the right index type here (rather than B-tree) requires understanding that a GIN index is designed for columns that contain multiple values — a tsvector is a list of lexemes, and GIN indexes each lexeme so the search engine can quickly find documents containing a given term. This is conceptually the same index structure used for JSONB.

Full-text search in PostgreSQL is suitable for moderate search volumes on structured data. When search becomes the core product — autocomplete, typo correction, faceted filtering, billions of documents — a dedicated search service like Elasticsearch or Typesense provides capabilities that PostgreSQL cannot match. Knowing when the simpler tool is sufficient and when to reach for the specialized one is a key engineering judgment.

[[sql-indexes|SQL Indexes]]
[[json-in-sql|JSON in PostgreSQL]]
[[triggers|Triggers]]
[[composite-indexes|Composite Indexes]]

---

## Common Misconceptions

Misconception 1: "Full-text search works like ILIKE '%search%' but faster."
Reality: They are fundamentally different tools. ILIKE performs substring matching on the raw text and cannot use standard indexes. Full-text search uses linguistic processing (stemming, stop words) and a GIN index, which makes it both faster and linguistically smarter — but it matches whole words and their stems, not arbitrary substrings. 'fox' @@ tsvector matches "foxes" but not "foxhole" in the same way ILIKE '%fox%' would.

Misconception 2: "You can use to_tsvector inline in a WHERE clause and the GIN index will be used."
Reality: The GIN index is built on a column, not on a function call. If you write WHERE to_tsvector('english', body) @@ query in a WHERE clause without a stored tsvector column, PostgreSQL must call to_tsvector on every row at query time — the GIN index is not used. The index is only used when the WHERE clause references the indexed column directly: WHERE search_vector @@ query.

Misconception 3: "Full-text search handles all search use cases."
Reality: PostgreSQL full-text search does not support fuzzy matching, phonetic matching, autocomplete with partial words (unless combined with pg_trgm), result highlighting beyond ts_headline, or distributed search across sharded data. For a search feature that users expect to work like Google or a modern application search bar, a dedicated service is usually the right tool.

---

## Why It Matters in Practice

PostgreSQL full-text search is the right choice when search is a secondary feature of an application that already uses PostgreSQL. A blog platform, a documentation site, a support ticket system, or an internal knowledge base can deliver competent search without adding an external service to the infrastructure. A single GIN index and a stored tsvector column provide sub-millisecond query times on millions of documents. The operational simplicity — no Elasticsearch cluster to manage, no index synchronization job to maintain — is a significant practical advantage.

The decision point is usually when search quality requirements outgrow what PostgreSQL can provide. Fuzzy matching, synonym expansion, autocomplete suggestions, typo correction, and personalized ranking all require capabilities that PostgreSQL does not natively offer. At that point, the investment in running a dedicated search service becomes justified. Until then, built-in full-text search is the pragmatic choice.

---

## What Breaks

**Language configuration mismatch.** A tsvector column is populated with to_tsvector('english', ...) at insert time. A query uses to_tsquery('french', ...) for searching. The stemming rules are different — "walk" stems to "walk" in English but "marche" in French. The query terms produce lexemes that never match the stored lexemes. Zero results are returned for queries that should have results. Text search configuration must be consistent between indexing and querying.

**Missing GIN index causing full table scan.** A developer adds a search feature using the @@ operator but forgets to create the GIN index. On small datasets, queries are fast. After a few months of growth, the same queries take seconds — each one is performing a full table scan and calling to_tsvector on every row. EXPLAIN ANALYZE reveals a Seq Scan with high cost.

```sql
-- Check that the GIN index is being used
EXPLAIN ANALYZE
SELECT id, title FROM articles
WHERE search_vector @@ to_tsquery('english', 'postgresql');
-- Look for: Bitmap Index Scan on idx_articles_fts
-- Not: Seq Scan on articles
```

**tsvector column out of sync.** The trigger that updates search_vector is dropped during a schema migration by a developer who did not realize it existed. New and updated rows are inserted with stale tsvector values. Search results become increasingly incomplete as new content is not indexed. The problem is not immediately obvious because existing indexed content still returns correctly.

---

## Interview Angle

Common question forms:
- "How does PostgreSQL full-text search work?"
- "What is the difference between tsvector and tsquery?"
- "How would you implement a search feature in a PostgreSQL-backed application?"
- "When would you use PostgreSQL FTS versus Elasticsearch?"

Answer frame:
Explain the two core types: tsvector (processed document) and tsquery (processed query), both normalized with stemming and stop word removal. Describe the @@ match operator. Explain that a GIN index on a stored tsvector column is required for performance. Address the use-case boundary: PostgreSQL FTS is excellent for simple search on small-to-medium datasets within an existing PostgreSQL application; Elasticsearch is needed for fuzzy search, autocomplete, billions of documents, or search as a primary product feature.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[json-in-sql|JSON in PostgreSQL]]
- [[triggers|Triggers]]
- [[composite-indexes|Composite Indexes]]
- [[query-optimization|Query Optimization]]
