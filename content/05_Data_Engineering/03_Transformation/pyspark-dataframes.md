---
title: 06 - PySpark DataFrames
description: "PySpark DataFrames are distributed, schema-aware, lazy datasets with a Catalyst optimizer that rewrites logical plans  -  window functions, join strategies, and partitioning are the main levers for performance."
tags: [pyspark, dataframe, catalyst, window-functions, join-strategies, partitioning, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# PySpark DataFrames

> PySpark's DataFrame API is a declarative, distributed query language  -  the Catalyst optimizer decides how to execute it, and understanding the optimizer's capabilities is what separates fast Spark jobs from slow ones.

---

## Quick Reference

**Core idea:**
- `DataFrame` = distributed, lazy, schema-aware dataset partitioned across the cluster
- Catalyst optimizer stages: Analysis -> Logical Optimization -> Physical Planning -> Code Generation
- `explain()` / `explain(extended=True)` shows the execution plan  -  essential for debugging performance
- Window functions: `F.row_number()`, `F.rank()`, `F.lag()`, `F.lead()`, `F.sum()` over a `Window.partitionBy().orderBy()`
- Join strategies: broadcast, sort-merge, shuffle-hash  -  controlled via `broadcast()` hint or `spark.sql.autoBroadcastJoinThreshold`
- `cache()` / `persist()` materializes a DataFrame in memory to avoid re-computing it in multiple actions

**Tricky points:**
- `cache()` is lazy  -  the DataFrame is not actually cached until the first action; use `cache().count()` to force immediate materialization
- `repartition(n)` always does a full shuffle; `coalesce(n)` (reducing only) avoids a shuffle
- `join` without a column type check can produce a cross join on null keys  -  always filter nulls from join keys
- `withColumn` in a loop (adding 50 columns one at a time) creates deeply nested plans that Catalyst struggles to optimize  -  use `select([...])` with a list comprehension instead
- `show()` triggers a full execution but only returns 20 rows  -  Spark still computes the full plan; it does not stop early

---

## What It Is

Think of a large logistics company with warehouses in dozens of cities. When an order comes in to ship 10,000 items nationwide, the central planning office does not call each warehouse individually. Instead, it creates a shipping plan: "Route all West Coast orders to LA, Midwest orders to Chicago, East Coast orders to New York." The plan is designed before any trucks move. When the order is finalized, the trucks execute the plan simultaneously. If the plan says "sort all East Coast orders by ZIP code before loading," the planning office decides whether that sort should happen at each warehouse (partition level) or at a central sorting facility (requiring trucks to bring items to one place first). Spark's Catalyst optimizer is that planning office, and the truck movements are the shuffle operations it tries to minimize.

PySpark's DataFrame API is designed to let you express what you want  -  not how to get it. You write `df.filter(...).groupBy(...).agg(...)`, and the Catalyst optimizer figures out the most efficient physical execution plan. This separation of "what" from "how" is the same principle as SQL: you write a SELECT statement and the database engine decides whether to use an index, which join algorithm to use, and which predicates to apply first. Understanding the Catalyst optimizer  -  what it can and cannot optimize  -  is what distinguishes PySpark code that is fast from code that looks correct but executes inefficiently.

Window functions are where PySpark pulls dramatically ahead of pandas for large-scale computations. Operations like "rank each order within its region by amount," "compute the 7-day rolling average of sales," or "find the previous event for each user" require window semantics: apply a function across a group of rows without collapsing them into one row. In pandas, these are straightforward with `.groupby().transform()`. In PySpark on a cluster, window functions require Spark to partition the data by the window's partition key (a shuffle) and then sort within each partition (another pass). Understanding this cost  -  and when to accept it versus restructure the computation  -  is practical PySpark knowledge.

---

## How It Actually Works

Spark's execution pipeline for a DataFrame action has four stages. First, the Analyzer resolves column names against the schema and checks for ambiguities. Second, the Logical Optimizer applies rule-based rewrites: pushes predicates closer to data sources (predicate pushdown), prunes unused columns (projection pruning), collapses adjacent filters, and eliminates redundant sorts. Third, the Physical Planner converts the logical plan into physical plans  -  choosing join algorithms (broadcast vs sort-merge vs shuffle-hash) and exchange (shuffle) strategies. Finally, Tungsten's code generator produces JVM bytecode for the physical plan that bypasses Java's object overhead and operates on binary data directly.

```python
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.functions import broadcast

spark = SparkSession.builder.appName("demo").getOrCreate()

df = spark.read.parquet("s3://bucket/orders/")

# Inspect the query plan
df.filter(F.col("amount") > 100).groupBy("region").agg(F.sum("amount")).explain(True)
# Shows: Parsed -> Analyzed -> Optimized -> Physical plans

# Window functions  -  each requires a partition + optional sort
window_by_region = Window.partitionBy("region").orderBy(F.desc("amount"))
window_rolling = Window.partitionBy("user_id").orderBy("order_date") \
                       .rowsBetween(-6, 0)   # 7-day rolling window

df_with_rank = df.withColumn("rank_in_region", F.rank().over(window_by_region))
df_rolling = df.withColumn("rolling_7d_sum", F.sum("amount").over(window_rolling))

# Join strategies
small_customers = spark.read.parquet("s3://bucket/customers/")  # small table

# Force broadcast join  -  small table sent to every executor
df_enriched = df.join(broadcast(small_customers), on="customer_id", how="left")

# Sort-merge join (default for large tables)
df_large = df.join(another_large_df, on="region", how="inner")

# Check join strategy in explain output
df_enriched.explain()   # look for BroadcastHashJoin vs SortMergeJoin

# Caching  -  force materialization immediately
df_cached = df.filter(F.col("status") == "completed").cache()
df_cached.count()     # triggers actual caching
print(f"Cached: {df_cached.count()}")    # reads from cache

# Efficient multi-column addition  -  avoid withColumn loop
new_columns = [
    F.col("amount") * 1.1,
    F.year("order_date").alias("year"),
    F.month("order_date").alias("month"),
]
df_new = df.select("*", *new_columns)

# Repartitioning for downstream join efficiency
df_repartitioned = df.repartition(200, "customer_id")
# Now a join on customer_id will not need to shuffle this DataFrame
```

Broadcast join is the highest-impact optimization available in PySpark. In a sort-merge join between two large DataFrames, Spark must shuffle both DataFrames to co-locate rows with the same join key  -  two full shuffles. In a broadcast join, Spark sends the smaller DataFrame to every executor (one network broadcast, not a shuffle), and each executor performs a hash join locally. The automatic threshold (`spark.sql.autoBroadcastJoinThreshold`, default 10 MB) is often too conservative  -  a 500 MB dimension table that fits in executor memory is a good broadcast candidate even though it exceeds the default threshold. Use `broadcast(small_df)` explicitly to force it.

`cache()` versus `persist()` is a nuanced choice. `cache()` is equivalent to `persist(StorageLevel.MEMORY_AND_DISK)`  -  data is stored in memory if possible, spills to disk if needed. For DataFrames that are much larger than available executor memory, `persist(StorageLevel.DISK_ONLY)` avoids the overhead of attempting memory caching. For DataFrames that are used many times in a complex pipeline, caching eliminates re-computation of all upstream steps on each use  -  the most impactful optimization for iterative algorithms or multi-branch pipelines.

---

## How It Connects

PySpark basics establishes the core concepts  -  SparkSession, transformations vs actions, lazy evaluation. This note builds on those to cover the optimizer, window functions, and join strategies that determine real-world performance.

[[pyspark-basics|PySpark Basics]]

Arrow is used for Spark's pandas UDF communication  -  when you write a `pandas_udf`, Spark serializes batches as Arrow RecordBatches, processes them in Python, and sends Arrow RecordBatches back.

[[arrow|Apache Arrow]]

---

## Common Misconceptions

Misconception 1: "The Catalyst optimizer will fix any inefficient code I write  -  I don't need to think about execution."
Reality: Catalyst applies deterministic rule-based and cost-based optimizations, but it cannot overcome fundamental algorithmic choices. Calling `df.filter()` after a `join` instead of before is a cartesian-join-then-filter that Catalyst may or may not push down; writing the filter before the join is explicit and guaranteed to be correct. Catalyst is a multiplier on good code, not a substitute for it.

Misconception 2: "`cache()` always improves performance  -  I should cache all intermediate DataFrames."
Reality: Caching has cost: first, the DataFrame must be computed and stored (memory or disk); second, cached DataFrames consume memory that might be needed for other computations. Cache only DataFrames that are used more than once in the same action scope, are expensive to compute, and fit in available executor memory.

Misconception 3: "Window functions in PySpark work just like pandas `.groupby().transform()`  -  same cost."
Reality: PySpark window functions require a shuffle (to co-locate rows with the same partition key) plus a sort within each partition. For a 10 TB DataFrame with a window partitioned by `user_id`, this means shuffling 10 TB across the cluster. The equivalent pandas operation on a single machine does not involve network I/O. The result is the same; the cost is orders of magnitude different.

---

## Why It Matters in Practice

The difference between a PySpark job that runs in 10 minutes and one that runs in 10 hours is almost always in how it handles shuffles, joins, and caching. Engineers who understand that `groupBy` and `join` are shuffle operations, that window functions have a partition-then-sort cost, and that `collect()` is dangerous learn to write jobs that scale. Engineers who treat PySpark like a remote pandas end up with jobs that work on test data and time out in production.

Reading `explain()` output is the most important diagnostic skill in PySpark. A plan showing `SortMergeJoin` on two large DataFrames that could use `BroadcastHashJoin` is a clear optimization target. A plan showing `Filter` applied after `Join` when it could be applied before is predicate pushdown failure. The plan output is a direct window into what Spark will do with your code.

---

## Interview Angle

Common question forms:
- "What is the Catalyst optimizer and what does it do?"
- "When would you use a broadcast join versus a sort-merge join?"
- "What is the cost of window functions in Spark?"

Answer frame:
Catalyst: takes the logical plan (from DataFrame API or SQL), applies rule-based and cost-based rewrites (predicate pushdown, projection pruning, join reordering), generates physical plans, selects the best, and compiles to JVM bytecode. Broadcast join: use when one side is small enough to fit in executor memory  -  avoids the full shuffle of sort-merge join; explicitly `broadcast(small_df)` or set threshold. Sort-merge join: both sides shuffled on the join key, sorted, then merged  -  correct for any size but requires two shuffles. Window function cost: shuffle to co-locate rows with same partition key, sort within partition  -  significant for large DataFrames; minimize by choosing high-cardinality partition keys and reducing the window frame size.

---

## Related Notes

- [[pyspark-basics|PySpark Basics]]
- [[arrow|Apache Arrow]]
- [[parquet|Parquet Format]]
- [[etl-patterns|ETL Patterns]]
