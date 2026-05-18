---
title: 08 - Polars
description: "Polars is a Rust-based DataFrame library that uses lazy evaluation, a query optimizer, and Arrow-native columnar storage to outperform Pandas on large datasets with a consistent, explicit API."
tags: [polars, lazy-evaluation, query-optimizer, arrow, dataframe, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Polars

> Polars brings the query optimizer that database engines use to DataFrames  -  expressing intent lazily, letting the engine decide how to execute it, and running on Arrow-native memory for maximum speed.

---

## Quick Reference

**Core idea:**
- Two execution modes: `Eager` (returns result immediately) and `Lazy` (builds a query plan, executes on `.collect()`)
- Arrow-native: every column is an Arrow `ChunkedArray`  -  no NumPy dependency
- Lazy API: `pl.scan_csv()`, `pl.scan_parquet()` build logical plans; `lf.collect()` executes them
- Key methods: `.filter()`, `.select()`, `.with_columns()`, `.group_by()`, `.join()`, `.sort()`
- Expressions: `pl.col("x")`, `pl.col("x").alias("y")`, `pl.col("*")`, `pl.lit(5)`  -  composable column descriptors
- `collect()` triggers predicate pushdown, projection pushdown, and query fusion  -  work is minimized before execution

**Tricky points:**
- Polars has no index  -  row order is positional; no label-based selection like `loc`
- Column names are always strings; unlike Pandas, there is no concept of an integer column position via label
- `.groupby()` is non-deterministic in row order within groups (Polars uses parallel hash grouping); use `.sort()` if order matters
- `LazyFrame` operations are not executed until `.collect()`  -  errors may surface at collection time, not at the method call
- Polars uses Rust threads internally  -  Python's GIL is released during most operations; true multi-core parallelism

---

## What It Is

Think of ordering at a restaurant. One approach is to walk into the kitchen yourself after every course and demand each ingredient be prepared immediately, one at a time. That is eager evaluation  -  each operation runs the moment you call it. The other approach is to describe your entire meal to a waiter, who brings your order to the chef. The chef reads the whole order at once, figures out the most efficient way to prepare everything (what can go in the oven together, what takes longest), and delivers the optimal meal. That is lazy evaluation  -  describing what you want, and letting a smart executor figure out how to produce it.

Polars is built around this second philosophy. Most of its operations do not execute immediately. Instead, they construct a logical plan  -  a description of what you want to compute, represented as a tree of operations. When you call `.collect()`, Polars's query optimizer reads the entire plan, rewrites it for efficiency (pushing filters down to happen before expensive joins, eliminating columns that are computed but never used, combining operations that can share a single pass over the data), and then executes the optimized plan using compiled Rust code across all available CPU cores.

Polars also differs from Pandas in its memory model. Every column in a Polars DataFrame is stored as an Apache Arrow `ChunkedArray`  -  the same format used by Arrow Flight, DuckDB, and modern data lake tooling. This means Polars DataFrames can be shared with other Arrow-aware libraries without copying data, and it means null values are represented as a separate validity bitmap rather than as special float values like `NaN`. Every column type supports nulls natively, which eliminates the integer-to-float promotion problem that Pandas has when NaN appears.

---

## How It Actually Works

When you write a Polars lazy expression like `lf.filter(pl.col("age") > 18).select(["name", "age"])`, Polars builds an Abstract Syntax Tree (AST) of logical operations. Each method call adds a node to this tree  -  no data is touched. When you call `.collect()`, the optimizer applies a series of rewrite rules. Predicate pushdown moves filter conditions as close to the data source as possible  -  if reading from a Parquet file, the predicate may be pushed all the way into the file reader, skipping entire row groups that cannot match. Projection pushdown ensures only the columns you actually use are read and kept in memory. These are the same techniques that SQL databases have used for decades; Polars brings them to the DataFrame API.

```python
import polars as pl

# Lazy scan  -  nothing read from disk yet
lf = pl.scan_parquet("sales.parquet")

# Build a query plan
result = (
    lf
    .filter(pl.col("amount") > 100)
    .with_columns([
        (pl.col("amount") * pl.col("qty")).alias("total"),
        pl.col("date").dt.year().alias("year"),
    ])
    .group_by(["year", "region"])
    .agg([
        pl.col("total").sum().alias("revenue"),
        pl.col("order_id").n_unique().alias("orders"),
    ])
    .sort("revenue", descending=True)
)

# Inspect the optimized plan before running
print(result.explain(optimized=True))

# Execute  -  optimizer runs here
df = result.collect()

# Eager mode for quick exploration
df_eager = pl.read_csv("data.csv")
print(df_eager.filter(pl.col("score") > 90).select(["name", "score"]))
```

Polars's expression system is the key to both composability and optimization. An expression like `pl.col("x").cast(pl.Float64).pow(2).alias("x_sq")` is a composable descriptor that the optimizer can analyze statically  -  it knows what type the result will be, what columns are needed as inputs, and whether the expression is elementwise (parallelizable per chunk) or requires group context. This static analysis is what allows Polars to reject invalid expressions at plan time (before `.collect()` even runs) and to parallelize independent column expressions automatically. In Pandas, `df["x_sq"] = df["x"].astype(float) ** 2` is a sequence of imperative mutations; in Polars, the equivalent is a declarative expression that the engine schedules.

---

## How It Connects

Polars stores data in Apache Arrow's columnar format natively, which means understanding Arrow's memory model  -  ChunkedArrays, validity bitmaps, zero-copy sharing  -  is essential for understanding why Polars can interoperate with DuckDB, Spark, and other Arrow-native tools without data conversion overhead.

[[arrow|Apache Arrow]]

Pandas is the library Polars is most often compared to and most commonly adopted alongside. Understanding Pandas first makes Polars's design choices more legible  -  no index, explicit lazy vs eager modes, and expression-based rather than imperative mutation.

[[pandas-basics|Pandas Basics]]

Parquet is the file format Polars is most optimized to read, largely because Polars can push predicates and projections into the Parquet reader itself, reading only the row groups and columns that the query needs.

[[parquet|Parquet Format]]

---

## Common Misconceptions

Misconception 1: "Polars is just a faster Pandas with the same API."
Reality: Polars has a fundamentally different API. There is no index. Selection uses expressions (`pl.col("x")`) rather than `loc`/`iloc`. Mutation is replaced by `with_columns()`. Code written for Pandas cannot be used in Polars without rewriting.

Misconception 2: "I should always use lazy mode  -  eager mode is just for beginners."
Reality: Lazy mode is best when reading from files (where predicate pushdown has real impact) and for multi-step transformations where the optimizer can eliminate work. Eager mode is appropriate for quick, interactive exploration on in-memory DataFrames where the overhead of building and analyzing a plan is unnecessary.

Misconception 3: "Polars is multi-threaded so it always uses all my CPU cores."
Reality: Polars uses Rust's Rayon library for parallelism within operations that support it (many do). But single-pass operations on small DataFrames may not parallelize because the overhead of partitioning and merging work exceeds the benefit. Performance gains are most pronounced on large DataFrames with multiple independent operations.

---

## Why It Matters in Practice

For data engineering pipelines processing hundreds of millions of rows on a single machine, Polars can complete in minutes what would take Pandas tens of minutes or more  -  without requiring a distributed compute cluster. The combination of Arrow-native memory (eliminating dtype promotion bugs), lazy evaluation (reducing intermediate allocations), and multi-core execution (using the whole machine) represents a fundamentally more scalable approach to Python data processing than Pandas provides.

The lack of an index is a deliberate API simplification that also eliminates an entire class of alignment bugs. In Pandas, index alignment causes NaN fills whenever two DataFrames have incompatible indexes. In Polars, joins and concatenations are explicit operations with explicit key columns  -  there is no silent alignment on a hidden label.

---

## Interview Angle

Common question forms:
- "What is lazy evaluation in Polars and why does it matter?"
- "How does Polars differ from Pandas at a conceptual level?"
- "When would you choose Polars over Pandas in a data engineering pipeline?"

Answer frame:
For lazy evaluation: operations build a logical query plan; `.collect()` triggers the optimizer (predicate pushdown, projection pushdown, query fusion) before executing compiled Rust code in parallel. For conceptual differences: Arrow-native storage (no NaN dtype promotion), no index (explicit join keys), expression system (composable descriptors vs imperative mutation), true multi-core parallelism via Rust. For when to choose: large in-memory workloads (millions+ rows), pipelines reading from Parquet (predicate pushdown pays off), or any situation where Pandas dtype/NaN behavior causes correctness issues.

---

## Related Notes

- [[pandas-basics|Pandas Basics]]
- [[arrow|Apache Arrow]]
- [[parquet|Parquet Format]]
- [[numpy-basics|NumPy Basics]]
