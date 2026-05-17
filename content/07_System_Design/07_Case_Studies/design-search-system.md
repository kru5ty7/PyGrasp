---
title: 05 - Design a Search System
description: "A walkthrough of designing a full-text search system — inverted index construction, query processing, ranking, and the indexing pipeline."
tags: [system-design, case-study, search, inverted-index, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design a Search System

> A search system is an exercise in data transformation: raw content becomes an inverted index; a user's text query becomes a structured retrieval operation against that index. Understanding how this transformation works explains why search systems behave the way they do — why some queries are fast, why some results are ranked higher, and why indexing new content is not instant.

---

## Quick Reference

**Core idea:**
- Inverted index: maps each term to the list of documents containing it (and their positions/frequencies)
- Query processing: tokenize the query → look up each term in the index → intersect/union document lists → rank by relevance
- Indexing pipeline: ingest documents → extract text → tokenize/normalize → update inverted index
- Ranking: TF-IDF (term frequency × inverse document frequency) or BM25 is the standard relevance scoring formula
- Elasticsearch/OpenSearch wraps all of this: sharded Lucene indexes, REST API, JSON queries

**Key design decisions:**
- Near real-time vs batch indexing: Elasticsearch commits new documents to segments within ~1 second (near real-time); batch pipelines periodically rebuild the full index from source data
- Search index is a derived artifact: the source of truth is the operational database; the search index is kept in sync via CDC or the outbox pattern
- Sharding the search index: shard by document ID (Elasticsearch default); number of shards is fixed at index creation — plan capacity upfront
- Caching common queries: most searches are for the same popular terms; a Redis cache keyed by the query string + page reduces Elasticsearch load by 90%+
- Fuzzy matching and typo tolerance: edit distance (Levenshtein) allows matching "Pythn" to "Python"; controlled by `fuzziness` parameter in Elasticsearch

---

## What It Is

A library catalog is the original search system. Each book has a card in the catalog. The catalog is arranged so you can find all books by a given author, all books on a given subject, or all books with a given word in the title — without opening any books. The catalog is the index. Every entry in the card catalog points back to the actual books, which are the documents. When you look up "distributed systems" in the subject catalog, you find twenty card entries, each pointing to a book on a shelf. You did not read the books — you searched the index.

A computer search system works identically, except the index is an inverted index rather than a card catalog, and "looking up" is a hash table or B-tree lookup rather than alphabetical scanning. The inverted index maps each term to the list of documents that contain it. The term "Python" maps to document IDs 45, 132, 890, 1204 — every document mentioning Python. A query for "Python concurrency" looks up both terms, intersects the two lists (documents containing both terms), and ranks the results by relevance.

The design challenge is at scale. A system with a billion documents has an inverted index containing billions of entries. Building it, storing it, keeping it current as documents change, and querying it with sub-100ms latency requires a specialized architecture. Elasticsearch (built on Apache Lucene) is the standard solution for production full-text search, but understanding what it does internally is what the system design question is actually testing.

---

## How It Actually Works

**The indexing pipeline** transforms raw documents into index entries. A document arrives (either from an API call, a CDC stream from the operational database, or a batch import). The indexing pipeline applies a text analysis chain: character filtering (strip HTML tags), tokenization (split on whitespace and punctuation), token filtering (lowercasing, stop word removal, stemming — "running" → "run"). The result is a list of normalized tokens. Each token is added to the inverted index: the posting list for that token gains a new entry with the document ID, term frequency, and term positions.

**Query processing** applies the same analysis chain to the query string, then executes a retrieval and ranking operation against the inverted index. A phrase query ("machine learning") intersects the posting lists for "machine" and "learning" and then filters for documents where the terms appear adjacent. A multi-field query (search across title and body, with title boosted) is a weighted union of scores across fields. BM25 — the current standard ranking function — scores documents by how often the query terms appear (term frequency), penalized by document length (to prevent long documents from scoring highly just by containing more words), and weighted by how rare each term is across the entire corpus (inverse document frequency — "the" scores near zero because it appears everywhere; "Luenberger" scores high because it is rare).

```python
from elasticsearch import Elasticsearch
from typing import Optional
import redis
import json
import hashlib

es = Elasticsearch(["http://elasticsearch:9200"])
r = redis.Redis(decode_responses=True)

INDEX_NAME = "articles"

def create_index():
    """Create Elasticsearch index with field mappings and analysis configuration."""
    es.indices.create(
        index=INDEX_NAME,
        body={
            "settings": {
                "number_of_shards": 5,     # fixed at creation — choose carefully
                "number_of_replicas": 1,
                "analysis": {
                    "analyzer": {
                        "english_analyzer": {
                            "type": "custom",
                            "tokenizer": "standard",
                            "filter": ["lowercase", "stop", "english_stemmer"]
                        }
                    },
                    "filter": {
                        "english_stemmer": {
                            "type": "stemmer",
                            "language": "english"
                        }
                    }
                }
            },
            "mappings": {
                "properties": {
                    "title": {
                        "type": "text",
                        "analyzer": "english_analyzer",
                        "boost": 2.0  # title matches score higher than body matches
                    },
                    "body": {"type": "text", "analyzer": "english_analyzer"},
                    "author": {"type": "keyword"},   # exact match, not analyzed
                    "created_at": {"type": "date"},
                    "tags": {"type": "keyword"}
                }
            }
        },
        ignore=400  # ignore if already exists
    )

def index_document(doc_id: str, title: str, body: str, author: str, tags: list[str]):
    """Index a single document. Elasticsearch adds it to the next commit segment."""
    es.index(
        index=INDEX_NAME,
        id=doc_id,
        document={
            "title": title,
            "body": body,
            "author": author,
            "created_at": "now",
            "tags": tags
        }
    )

def search(
    query: str,
    author_filter: Optional[str] = None,
    tags_filter: Optional[list[str]] = None,
    page: int = 1,
    page_size: int = 10
) -> dict:
    """
    Full-text search with optional filters, BM25 ranking, and Redis caching.
    Cache key includes all query parameters to avoid stale results.
    """
    # Cache key: hash of all query parameters
    cache_key = "search:" + hashlib.md5(
        json.dumps({
            "q": query, "author": author_filter,
            "tags": tags_filter, "page": page
        }, sort_keys=True).encode()
    ).hexdigest()

    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)

    # Build Elasticsearch query
    must_clauses = [
        {
            "multi_match": {
                "query": query,
                "fields": ["title^2", "body"],  # title gets 2x boost
                "type": "best_fields",
                "fuzziness": "AUTO"  # tolerate typos (1-2 edits for longer terms)
            }
        }
    ]

    filter_clauses = []
    if author_filter:
        filter_clauses.append({"term": {"author": author_filter}})
    if tags_filter:
        filter_clauses.append({"terms": {"tags": tags_filter}})

    es_query = {
        "query": {
            "bool": {
                "must": must_clauses,
                "filter": filter_clauses  # filters do not affect score, are cached
            }
        },
        "from": (page - 1) * page_size,
        "size": page_size,
        "highlight": {
            "fields": {
                "title": {},
                "body": {"fragment_size": 150, "number_of_fragments": 1}
            }
        }
    }

    response = es.search(index=INDEX_NAME, body=es_query)

    result = {
        "total": response["hits"]["total"]["value"],
        "page": page,
        "results": [
            {
                "id": hit["_id"],
                "score": hit["_score"],
                "title": hit["_source"]["title"],
                "highlight": hit.get("highlight", {}),
                "author": hit["_source"]["author"]
            }
            for hit in response["hits"]["hits"]
        ]
    }

    # Cache for 5 minutes — search results change slowly relative to query rate
    r.setex(cache_key, 300, json.dumps(result))
    return result

# Indexing pipeline: keep search index in sync with operational database
# Pattern: database outbox → CDC → Elasticsearch index update
async def handle_document_change_event(event: dict):
    """
    CDC event from the articles table in the operational database.
    Keeps the search index in sync without dual-write in application code.
    """
    if event["operation"] in ("INSERT", "UPDATE"):
        index_document(
            doc_id=str(event["row"]["id"]),
            title=event["row"]["title"],
            body=event["row"]["body"],
            author=event["row"]["author"],
            tags=event["row"]["tags"] or []
        )
    elif event["operation"] == "DELETE":
        es.delete(index=INDEX_NAME, id=str(event["row"]["id"]), ignore=404)
```

**Keeping the search index in sync** with the operational database is the integration challenge. The source of truth is the relational database (or document store). The search index is a derived projection. Two approaches: application-level dual-write (the application writes to both the database and Elasticsearch on each change — this is fragile: a crash between the two writes leaves them inconsistent) and CDC-based sync (Debezium or similar tools stream change events from the database's WAL directly to an indexing consumer — the search index eventually catches up, with no application code changes required). The CDC approach is more robust for production.

**The three most important design decisions:** (1) The search index is not the source of truth — never use Elasticsearch as the primary data store; keep the relational database as the source of truth and treat the search index as a read replica. (2) Shard count is fixed — choose the number of shards at index creation based on expected data volume; resharding requires creating a new index and re-indexing all documents. (3) Query caching for popular terms — most search traffic is concentrated on a small number of popular queries; caching with a 5-minute TTL dramatically reduces Elasticsearch load.

---

## Why It Matters in Practice

Search is everywhere: product search in e-commerce, document search in productivity tools, code search in developer platforms, log search in observability tools. The inverted index and BM25 ranking model used in Elasticsearch are the foundation of all of them. Understanding the indexing pipeline (why search is near-real-time, not instant), the source of truth vs. derived index distinction, and query caching provides the framework for designing any search feature.

---

## Interview Angle

Common question forms:
- "Design a full-text search feature for an e-commerce product catalog."
- "How does an inverted index work?"
- "How do you keep a search index in sync with your database?"

Answer frame:
Requirements: full-text search with ranking, filter by facets, pagination. Core data structure: inverted index (term → document list). Analysis pipeline: tokenize, normalize, stem. Ranking: BM25 (TF-IDF variant). Implementation: Elasticsearch as the search backend. Integration: CDC/Debezium from operational DB to ES — search index is a derived projection, never the source of truth. Shard count: fixed at creation, size based on data volume. Query cache: Redis for popular queries, 5-minute TTL. Typo tolerance: fuzziness parameter. Faceted filtering: keyword fields with filter clauses.

---

## Related Notes

- [[data-warehousing|Data Warehousing]]
- [[caching-basics|Caching Basics]]
- [[cache-invalidation|Cache Invalidation]]
- [[database-indexes|Database Indexes]]
- [[outbox-pattern|Outbox Pattern]]
