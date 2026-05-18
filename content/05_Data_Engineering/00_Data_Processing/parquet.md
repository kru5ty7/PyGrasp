---
title: 10 - Parquet Format
description: "Parquet is a columnar storage format that uses row groups, column chunks, and metadata-driven predicate pushdown to store analytical data orders of magnitude more efficiently than CSV."
tags: [parquet, columnar-storage, row-groups, predicate-pushdown, compression, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Parquet Format

> Parquet encodes columnar data with statistics-driven file metadata so that query engines can skip reading entire sections of the file  -  turning file format design into a query performance optimization.

---

## Quick Reference

**Core idea:**
- Columnar on disk: all values for a column are stored together, not row by row
- File structure: file header -> row groups -> column chunks -> pages -> file footer (metadata)
- Row group = horizontal partition of rows; column chunk = one column's data within a row group
- Footer contains per-column-chunk statistics (min, max, null count)  -  enables predicate pushdown without reading data
- Compression per column chunk: `SNAPPY` (fast), `GZIP` (smaller), `ZSTD` (balance), `BROTLI`  -  choose per use case
- Python: `pyarrow.parquet`, `pandas.read_parquet()`, `polars.scan_parquet()` / `read_parquet()`

**Tricky points:**
- Parquet is not splittable at the row-group level by default  -  row groups must fit within one file to be parallel-readable
- Small row group sizes increase metadata overhead; large row groups reduce predicate pushdown granularity
- `pandas.read_parquet()` reads the whole file into memory  -  use `pyarrow.parquet.ParquetFile` or `polars.scan_parquet()` for streaming/lazy reads
- Nested types (structs, lists, maps) use Dremel encoding (definition/repetition levels)  -  pyarrow handles this automatically
- Schema evolution: adding columns is safe; renaming or reordering is not  -  always write an explicit schema

---

## What It Is

Imagine you manage a warehouse with a million items, each described by ten properties: item name, category, weight, price, country of origin, and so on. You could store each item as its own index card with all ten properties listed  -  that is row-oriented storage, like CSV. When someone asks "what is the average price of all items?", you pull out all million cards and read every field on every card, just to collect the prices. Alternatively, you could store all prices together in one drawer, all weights together in another drawer, and so on. When someone asks for average price, you open only the price drawer. That is columnar storage, and that is Parquet.

Parquet takes columnar storage further by dividing the file into row groups  -  horizontal slices of the data, each containing a few hundred thousand rows. Within each row group, each column is stored as a separate column chunk. The file ends with a footer that contains metadata about every column chunk: the minimum and maximum values stored, the count of null values, and the byte offset where each chunk starts. A query engine reading a Parquet file can inspect the footer first  -  at a cost of reading a few kilobytes  -  and then skip any row group where the column statistics prove no matching rows exist. If you are looking for orders where `amount > 1000` and a row group's metadata says the maximum `amount` in that group is 500, the entire row group can be skipped. This is predicate pushdown.

Parquet was designed at Twitter and Cloudera in 2013 specifically for Hadoop's distributed computing environment, where reading less data is more important than computing it efficiently. Today it is the standard format for analytical data lakes, used by Amazon S3, Google BigQuery, Apache Spark, Snowflake, DuckDB, Polars, and nearly every other analytical engine. Its combination of columnar layout (read only the columns you need), compression (columns of similar values compress extremely well), and statistics-driven skipping (skip row groups that cannot match) makes it consistently 5 to 50 times more efficient to read than equivalent CSV files for typical analytical queries.

---

## How It Actually Works

A Parquet file has a four-byte magic number (`PAR1`) at both the start and the end. The file footer, located at a fixed offset from the end, is a Thrift-encoded metadata structure containing the schema, the row group metadata, and pointers to every column chunk. A reader can seek to the end of the file, read the last eight bytes to find the footer length, then read the footer  -  all without scanning the data section. The footer is the index; data reading is guided entirely by the footer.

```python
import pyarrow as pa
import pyarrow.parquet as pq
import pandas as pd

# Write a Parquet file with specific options
table = pa.table({
    "user_id": pa.array([1, 2, 3, 4, 5], type=pa.int32()),
    "amount": pa.array([100.0, 50.0, 250.0, 80.0, 300.0], type=pa.float64()),
    "region": pa.array(["North", "South", "North", "East", "South"]),
})
pq.write_table(
    table,
    "sales.parquet",
    row_group_size=2,          # small for illustration; use 128k-1M in production
    compression="snappy",
    write_statistics=True,     # enables predicate pushdown
)

# Inspect metadata without reading data
meta = pq.read_metadata("sales.parquet")
print(meta.num_row_groups)     # 3 (ceil(5 / 2))
rg = meta.row_group(0)
col = rg.column(1)             # 'amount' column
print(col.statistics)          # min=50.0, max=100.0, null_count=0

# Predicate pushdown: read only row groups where amount > 200
filters = [("amount", ">", 200)]
result = pq.read_table("sales.parquet", filters=filters)
print(result.to_pandas())      # only rows with amount=250, 300

# Column projection: read only specific columns
result2 = pq.read_table("sales.parquet", columns=["user_id", "amount"])
```

Within each column chunk, data is further divided into pages (typically 8 KB or more) for dictionary encoding and data pages. Dictionary encoding is applied automatically when a column has low cardinality (few unique values): Parquet writes a dictionary of unique values once, then stores each data value as a small integer index into the dictionary. A column like `"region"` with values `"North"`, `"South"`, `"East"` would be stored as one dictionary page with three entries and data pages containing 0, 1, and 2 integers  -  far more compressible than the repeated strings. After dictionary encoding, additional compression (Snappy, Gzip, or Zstd) is applied at the column chunk level, with columnar data compressing far better than row data because adjacent values are highly correlated in typed columns.

---

## How It Connects

Apache Arrow and Parquet are designed as complementary layers: Arrow for in-memory columnar computation, Parquet for columnar storage on disk. The pyarrow library reads Parquet directly into Arrow Tables, and Polars's lazy scanner pushes Arrow-format predicates into the Parquet reader before any data is loaded into memory.

[[arrow|Apache Arrow]]

Polars's `scan_parquet()` is the highest-level interface for Parquet predicate pushdown in Python  -  it builds a lazy plan that the Polars optimizer can combine with filter expressions before executing, achieving file-level skipping plus in-memory query optimization.

[[polars|Polars]]

---

## Common Misconceptions

Misconception 1: "Parquet is row-oriented like CSV  -  it just has better compression."
Reality: Parquet is fundamentally columnar. All values for a column are stored together, compressed together, and read together. This makes column projection and predicate pushdown possible. CSV stores rows together and cannot skip rows or columns without reading past them.

Misconception 2: "I can always read a Parquet file efficiently with `pd.read_parquet()`."
Reality: `pd.read_parquet()` is a convenience wrapper that reads the entire file into memory. For files larger than available RAM, or for queries that only need a subset of rows and columns, use `pyarrow.parquet.read_table(filters=..., columns=...)` or Polars's `scan_parquet()` to leverage predicate pushdown before data enters memory.

Misconception 3: "The row group size doesn't matter much  -  Parquet handles it automatically."
Reality: Row group size is a critical tuning parameter. Too small (less than 50k rows): metadata overhead is large relative to data, and compression ratios suffer. Too large (more than a few million rows): predicate pushdown becomes coarse because you can only skip entire row groups, not sub-row-group ranges. For most analytical workloads, 128k to 512k rows per group is a good target.

---

## Why It Matters in Practice

Every major cloud data platform stores its data in Parquet (or a derivative like Delta Lake and Iceberg, which add transaction logs on top of Parquet). Engineers who understand Parquet's structure can make informed decisions about partitioning strategies, row group sizing, and compression choices that determine whether queries scan 10 GB or 100 GB for the same result. A well-organized Parquet dataset with appropriate statistics and partitioning is not just faster to query  -  it is substantially cheaper to operate in cloud billing environments where you pay per byte scanned.

Understanding predicate pushdown also changes how you write data transformation code. The difference between `scan_parquet` with a filter expression (which pushes the filter into the file reader) and `read_parquet` followed by a DataFrame filter (which reads everything then filters in memory) can be the difference between a job that runs in 10 seconds and one that takes 5 minutes and runs out of memory.

---

## Interview Angle

Common question forms:
- "What is Parquet and why is it preferred over CSV for data lakes?"
- "What is predicate pushdown and how does Parquet enable it?"
- "What is a row group and why does its size matter?"

Answer frame:
Parquet is a columnar disk format  -  columns stored together, not rows. Advantages over CSV: column projection reads only needed columns; predicate pushdown skips row groups based on metadata statistics; compression is 5-20x better because same-type adjacent values compress efficiently. Predicate pushdown: the file footer stores per-column-chunk min/max statistics; a query engine checks statistics before reading any data  -  if no row in a chunk can satisfy the filter, the entire chunk is skipped. Row group size: granularity of predicate pushdown and compression unit; too small wastes metadata overhead, too large reduces skipping effectiveness.

---

## Related Notes

- [[arrow|Apache Arrow]]
- [[polars|Polars]]
- [[pandas-basics|Pandas Basics]]
