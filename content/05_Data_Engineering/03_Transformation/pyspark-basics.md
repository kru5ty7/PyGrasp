---
title: 05 - PySpark Basics
description: "PySpark is the Python API for Apache Spark, enabling distributed data processing across clusters by expressing transformations as a lazy DAG of operations that Spark's optimizer compiles into efficient execution plans."
tags: [pyspark, spark, distributed, rdd, dataframe, spark-session, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# PySpark Basics

> PySpark brings distributed computing to Python  -  the same DataFrame transformations you write locally run across a cluster of hundreds of machines, processing terabytes without changing a line of code.

---

## Quick Reference

**Core idea:**
- `SparkSession` is the entry point  -  `spark = SparkSession.builder.appName("name").getOrCreate()`
- `DataFrame` (Spark SQL API) is the standard abstraction  -  schema-aware, lazy, distributed
- Transformations are lazy: `filter()`, `select()`, `groupBy()`, `join()` return new DataFrames without execution
- Actions trigger execution: `show()`, `collect()`, `count()`, `write.parquet()`
- Spark's Catalyst optimizer rewrites the logical plan before execution  -  predicate pushdown, projection pruning
- RDD (Resilient Distributed Dataset) is Spark's low-level API  -  prefer DataFrame API for all new code

**Tricky points:**
- `collect()` brings all data to the driver  -  never use it on large DataFrames; use `write` instead
- Python UDFs in PySpark serialize data to/from Python using pickling  -  extremely slow; prefer Spark SQL built-ins or pandas UDFs
- `SparkContext` and `SparkSession` are different objects  -  `SparkSession` wraps `SparkContext`; use `SparkSession` exclusively in PySpark 2+
- `explode()`, `pivot()`, and window functions are common but each has sharp edges  -  test on small data first
- The default number of shuffle partitions is 200  -  change with `spark.conf.set("spark.sql.shuffle.partitions", "50")` for small datasets

---

## What It Is

Think of a large mining operation where a mountain of ore needs to be processed. One person with one shovel cannot process the mountain in a reasonable time. But divide the mountain into hundreds of smaller piles, give one pile to each of hundreds of workers with their own shovels, and the entire mountain is processed in the same time it would take one worker to process one pile. Apache Spark is the coordination system for that operation: it divides your data into chunks (partitions), distributes those chunks across a cluster of machines, tells each machine what transformation to apply to its chunk, and assembles the results. PySpark is the Python API for giving Spark its instructions.

Spark was created at UC Berkeley's AMPLab in 2010 as a faster replacement for Hadoop MapReduce. The key insight was keeping intermediate data in memory across processing stages, rather than writing it to disk between every step the way MapReduce did. This made multi-stage transformations (filter, then join, then aggregate) 10-100 times faster than equivalent MapReduce jobs. The DataFrame API, introduced in Spark 1.3, added a schema-aware, SQL-like abstraction on top of Spark's low-level RDD API  -  making it familiar to pandas users and enabling the Catalyst query optimizer to rewrite queries for efficiency.

PySpark DataFrames look like pandas DataFrames on the surface but are fundamentally different underneath. A PySpark DataFrame is not a Python object holding data  -  it is a description of a distributed dataset stored across a cluster. Operations on it do not execute immediately. Instead, they add steps to a lazy evaluation plan. Only when you call an action  -  `show()`, `count()`, `collect()`, or `write`  -  does Spark submit the plan to the cluster, execute it across all nodes, and return results. This laziness allows the Catalyst optimizer to analyze the entire plan before executing it, potentially reordering operations, eliminating redundant steps, and pushing filters closer to data sources.

---

## How It Actually Works

A Spark application has a driver process (your PySpark script) and executor processes (JVM processes on worker nodes in the cluster). The driver runs the Python code, builds the logical plan, and coordinates. Executors run in JVM processes on worker machines and do the actual computation. When PySpark executes a DataFrame operation, it serializes the Python plan to the JVM through Py4J (a Python-to-JVM bridge library), and the JVM-based Spark engine runs the computation. This means that PySpark DataFrame operations run in JVM processes, not in the Python process  -  the Python script is a control plane, not the execution engine.

```python
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, DateType
from pyspark.sql.window import Window

spark = SparkSession.builder \
    .appName("SalesPipeline") \
    .config("spark.sql.shuffle.partitions", "50") \
    .getOrCreate()

# Schema definition (optional but recommended)
schema = StructType([
    StructField("order_id", StringType(), nullable=False),
    StructField("customer_id", StringType(), nullable=False),
    StructField("amount", DoubleType(), nullable=True),
    StructField("order_date", DateType(), nullable=False),
    StructField("region", StringType(), nullable=True),
])

# Read Parquet  -  lazy; no data loaded yet
df = spark.read.schema(schema).parquet("s3://my-bucket/orders/")

# Chain transformations  -  still lazy, building a plan
result = (
    df
    .filter(F.col("amount") > 0)                      # predicate
    .withColumn("year", F.year("order_date"))          # derived column
    .withColumn(                                        # window function
        "regional_rank",
        F.rank().over(
            Window.partitionBy("region").orderBy(F.desc("amount"))
        )
    )
    .filter(F.col("regional_rank") <= 10)             # top 10 per region
    .select("order_id", "customer_id", "region", "amount", "year")
)

# Action  -  triggers actual cluster execution
result.write.mode("overwrite").partitionBy("year").parquet("s3://my-bucket/output/")

# Only for small results  -  NEVER on large DataFrames
result.filter(F.col("region") == "North").show(20)   # ok for debugging
```

The shuffle is the most expensive operation in Spark. When an operation like `groupBy`, `join`, or `orderBy` requires grouping data that may be spread across different partitions on different machines, Spark must network-transfer data between nodes  -  the "shuffle." Every shuffle writes intermediate data to disk and transfers it over the network. Shuffle-heavy jobs are I/O bound and slow. Techniques to minimize shuffles: use `broadcast join` for joining a large DataFrame with a small one (the small DataFrame is sent to every node), use `repartition("key")` before a `groupBy("key")` to co-locate related rows, and use `coalesce()` instead of `repartition()` when reducing partition count (avoids a full shuffle).

Python UDFs are the most common source of PySpark performance problems. A Python UDF requires Spark to serialize each row from the JVM representation to Python (via Py4J + pickle), call the Python function, and serialize the result back  -  for each row. For a 1 billion row DataFrame, this means 1 billion serialize-deserialize cycles. Pandas UDFs (vectorized UDFs using pandas Series or DataFrames) reduce this cost: Spark passes an Arrow-serialized batch of rows to Python at once, the pandas function processes the entire batch, and the result is serialized back as a batch. Vectorized UDFs are 10-100x faster than row-at-a-time Python UDFs.

---

## How It Connects

PySpark DataFrames are built on Apache Arrow for pandas UDF communication  -  understanding Arrow's columnar format and batch-oriented data model explains why vectorized pandas UDFs are so much faster than row-level Python UDFs.

[[arrow|Apache Arrow]]

Parquet is the standard file format for reading and writing distributed data in PySpark  -  Spark's built-in Parquet reader uses predicate pushdown (reading only row groups that match filter conditions) and schema evolution natively.

[[parquet|Parquet Format]]

PySpark DataFrames in more detail  -  window functions, join strategies, and the Catalyst optimizer  -  build directly on the basics established here.

[[pyspark-dataframes|PySpark DataFrames]]

---

## Common Misconceptions

Misconception 1: "`collect()` is just a way to see data  -  it's fine for large DataFrames in a Jupyter notebook."
Reality: `collect()` transfers all data from the cluster to the driver (your local Python process or Jupyter kernel). For a 100 GB DataFrame, this means transferring 100 GB to your laptop's memory  -  likely causing an OOM crash. Use `show(n)` for sampling, `write` for output, and `toPandas()` only after reducing the DataFrame to a manageable size with `filter`/`limit`.

Misconception 2: "Adding more partitions always makes Spark faster."
Reality: Each partition has overhead: a task is created for it, and task scheduling has latency (~2ms per task). For small DataFrames, 200 partitions means 200 tasks each processing a few rows  -  the scheduling overhead dominates actual work. Set `spark.sql.shuffle.partitions` to match your data size: 10-50 for small DataFrames, 500-2000 for very large ones.

Misconception 3: "Python UDFs run as fast as Spark's built-in functions  -  they're all Python under the hood."
Reality: Spark's built-in functions (`F.col`, `F.sum`, `F.year`) run in the JVM Spark executor without touching Python. Python UDFs require serialization of each row between JVM and Python  -  typically 10-100x slower. Always use built-in Spark SQL functions when available; use pandas UDFs when custom logic is unavoidable.

---

## Why It Matters in Practice

Spark's scale makes it the standard for data engineering workloads at large companies. When a data pipeline needs to process 10 TB of daily logs, a single-machine pandas pipeline is not an option  -  Spark on a cluster of 20 machines processes that same data in minutes. PySpark is the entry point for Python engineers who need to write these pipelines without learning Scala.

The mental shift required is significant: thinking in distributed terms means reasoning about data locality (which data is on which node), shuffle cost (which operations require network transfer), and the driver/executor split (only driver-side Python is in your process; executor logic runs remotely in JVM). Engineers who treat PySpark like pandas  -  collecting large DataFrames, writing Python UDFs for everything, ignoring partition counts  -  write code that works on test data and fails in production.

---

## Interview Angle

Common question forms:
- "What is the difference between a transformation and an action in PySpark?"
- "Why are Python UDFs slow in PySpark?"
- "What is a shuffle in Spark and why should you minimize it?"

Answer frame:
Transformations vs actions: transformations (filter, select, join, groupBy) are lazy  -  they build a logical plan but do not execute. Actions (show, count, collect, write) trigger the actual cluster execution. Python UDF slowness: Spark's built-in functions run in JVM executors; Python UDFs require serializing each row from JVM to Python and back (via Py4J/pickle)  -  O(N) serialization operations. Use pandas UDFs for batch-level Arrow serialization (much faster). Shuffle: when operations require grouping data across partitions (join, groupBy, sort), Spark moves data between nodes over the network  -  expensive I/O. Minimize by using broadcast joins for small tables and co-partitioning data on join keys.

---

## Related Notes

- [[pyspark-dataframes|PySpark DataFrames]]
- [[parquet|Parquet Format]]
- [[arrow|Apache Arrow]]
- [[etl-patterns|ETL Patterns]]
