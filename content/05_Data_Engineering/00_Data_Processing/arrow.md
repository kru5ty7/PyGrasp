---
title: 09 - Apache Arrow
description: "Apache Arrow is a language-independent columnar in-memory format that enables zero-copy data sharing between processes and libraries, eliminating serialization overhead across the data engineering stack."
tags: [arrow, columnar, zero-copy, buffer-protocol, ipc, interoperability, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Apache Arrow

> Apache Arrow is the universal language that modern data tools use to share data without copying it — a columnar memory layout standard that lets Python, Rust, Java, and C++ all read the same bytes.

---

## Quick Reference

**Core idea:**
- Arrow defines a columnar, language-independent memory format — not a file format, but an in-memory layout standard
- Python library: `pyarrow`; key types: `pa.Array`, `pa.ChunkedArray`, `pa.RecordBatch`, `pa.Table`, `pa.Schema`
- Zero-copy sharing: two processes can map the same memory region without copying via `pa.ipc` or shared memory
- Validity bitmap: separate from data; all Arrow types support null natively (no NaN-as-null hack)
- `pyarrow` integrates with Pandas (`pa.Table.from_pandas()`, `arrow_table.to_pandas()`), NumPy, Polars, and DuckDB
- IPC (Inter-Process Communication) format: `RecordBatchStreamWriter`/`RecordBatchReader` for streaming; `RecordBatchFileWriter` for seekable files

**Tricky points:**
- Arrow arrays are immutable by design — there is no in-place mutation; transformations produce new arrays
- `ChunkedArray` is a list of same-schema `Array` chunks — allows incremental building without pre-knowing total size
- `pa.Table.from_pandas()` may copy data if Pandas dtypes are not Arrow-compatible; check `schema` to verify
- Arrow strings are encoded as UTF-8 byte sequences with a separate offsets array — not Python `str` objects
- Dictionary-encoded arrays (Arrow equivalent of Pandas `Categorical`) are stored as integer codes + dictionary

---

## What It Is

Picture a library with books in many different languages. If a Spanish speaker and a French speaker both want to read the same book, one approach is to translate the book separately for each reader — expensive, time-consuming, and you end up with multiple copies. A better approach is to keep one copy of the book and have each reader use their own language-specific "annotation key" that maps the shared pages to their reading system. Apache Arrow is that shared book. It is a precisely defined way of laying out data in memory so that any programming language with an Arrow implementation can read the data directly, without translation.

Arrow's format is columnar: instead of storing a table as a sequence of rows (record 1, then record 2, then record 3), it stores it as a sequence of columns (all values for column A, then all values for column B). For typical analytical queries — "what is the average of column A?" or "filter all rows where column B > 100" — columnar layout is dramatically more cache-friendly because a single query only reads the columns it needs, which are stored contiguously. Row-oriented storage reads entire rows even when only a few columns are needed, wasting memory bandwidth.

The most consequential feature of Arrow is zero-copy interoperability. When Pandas builds on top of Arrow (`ArrowDtype`), when Polars stores its columns in Arrow ChunkedArrays, and when DuckDB executes a query and returns results, all of these can reference the same physical memory. Transferring a billion-row dataset from DuckDB to a Polars DataFrame to a Pandas DataFrame does not require three copies of the data — it requires three array headers pointing to the same bytes. This is what "zero-copy" means: the data does not move; only the description of where it lives is passed between systems.

---

## How It Actually Works

An Arrow `Array` is defined by three memory buffers: a validity bitmap (one bit per element, indicating whether that element is null), a data buffer (the actual values in a type-specific layout), and for variable-length types like strings, an offsets buffer (recording where each string starts and ends in the data buffer). Fixed-width types like `int64` or `float32` have no offsets buffer — element i is always at byte `i * item_size` in the data buffer. This predictable layout is what makes Arrow arrays directly readable by any language that can do pointer arithmetic and interpret a dtype descriptor.

```python
import pyarrow as pa
import pandas as pd
import numpy as np

# Build an Arrow table
schema = pa.schema([
    ("name", pa.string()),
    ("score", pa.float64()),
    ("grade", pa.int32()),
])
table = pa.table({
    "name": ["Alice", "Bob", None],       # None → null in Arrow
    "score": [92.5, 88.0, 95.1],
    "grade": [1, 2, 1],
}, schema=schema)

print(table.schema)
print(table.num_rows)   # 3

# Zero-copy to Pandas (Arrow columns become Pandas ArrowDtype Series)
df = table.to_pandas(types_mapper=pd.ArrowDtype)
print(df.dtypes)        # name: string[pyarrow], score: double[pyarrow], ...

# From Pandas — may copy if dtypes don't map cleanly
table2 = pa.Table.from_pandas(df)

# IPC: write to bytes buffer, read back with zero copy
sink = pa.BufferOutputStream()
writer = pa.ipc.new_stream(sink, table.schema)
writer.write_table(table)
writer.close()

buf = sink.getvalue()
reader = pa.ipc.open_stream(buf)
table_back = reader.read_all()
```

The `ChunkedArray` is the practical unit for large datasets. A `pa.Array` must fit in a single contiguous buffer, which limits it to roughly 2 billion elements (due to 32-bit offset integers for variable-length types in Arrow 1.0; Arrow uses 64-bit offsets in newer specs for large lists). A `ChunkedArray` is a sequence of `Array` chunks that share the same schema but are stored in separate buffers — you append new chunks rather than reallocating one growing buffer. Polars columns and DuckDB results are typically `ChunkedArray` under the hood. When you call `.to_pandas()` on a large Arrow table, Pandas may need to concatenate chunks if the `ArrowDtype` wrapper is not used, which is why using `types_mapper=pd.ArrowDtype` is the memory-efficient path.

---

## How It Connects

NumPy's buffer protocol — the mechanism that lets C extensions share memory with NumPy arrays — is the conceptual predecessor of Arrow's zero-copy model. Arrow formalizes and extends this into a cross-language, cross-process standard, while NumPy's model is CPython-specific.

[[numpy-internals|NumPy Internals and Memory Layout]]

Polars stores all its columns as Arrow ChunkedArrays internally. Arrow is not an optional integration for Polars — it is the foundation of its memory model, null handling, and cross-library interoperability.

[[polars|Polars]]

Parquet is the most common file format used to persist Arrow data. Reading a Parquet file with `pyarrow.parquet.read_table()` produces an Arrow Table directly, and writing one preserves columnar layout on disk as it is in memory.

[[parquet|Parquet Format]]

---

## Common Misconceptions

Misconception 1: "Arrow is a file format like Parquet or CSV."
Reality: Arrow is an in-memory format specification — it defines how to lay out data in RAM for interoperability. Parquet is a disk-based file format with compression. Arrow has its own IPC file format (`.arrow` or `.feather`) for persisting to disk, but that is distinct from the in-memory layout standard.

Misconception 2: "Zero-copy means there is literally no CPU work when transferring data between libraries."
Reality: Zero-copy means the data buffer is not duplicated. But there is still CPU work: the receiving library must validate the Arrow schema, build its own array header structures, and potentially check the validity bitmap. The savings are in memory bandwidth (no copying gigabytes of data) and heap allocation, not in all CPU operations.

Misconception 3: "Arrow and Pandas work on the same memory model, so converting between them is always lossless and free."
Reality: Pandas natively uses NumPy arrays with NaN-as-null semantics for float columns. Arrow uses a separate validity bitmap for nulls. Converting a Pandas `float64` column with NaN values to an Arrow nullable float array involves reconstructing the validity bitmap — this is not lossless (NaN is distinct from null), and it may involve a copy to separate nulls from data values.

---

## Why It Matters in Practice

The data engineering ecosystem is converging on Arrow as the universal in-memory interchange format. DuckDB queries return Arrow. Polars stores Arrow. Pandas 2.0 supports Arrow-backed columns. Spark has an Arrow-based Python UDF execution path. This convergence means that pipelines built on Arrow interoperability today will have zero serialization cost as data moves between these tools — a fundamental performance advantage over pipelines that convert between NumPy, Python dicts, and JSON at each stage.

For Python developers writing data pipelines, the practical implication is: prefer `pa.Table` as your intermediate format when data crosses library boundaries. Reading from Parquet into Arrow and writing Arrow to Parquet is the zero-overhead path. Converting to Pandas only at the point where Pandas-specific operations are needed, and using `ArrowDtype` to preserve Arrow backing through those operations, maximizes both memory efficiency and cross-tool compatibility.

---

## Interview Angle

Common question forms:
- "What is Apache Arrow and what problem does it solve?"
- "What does 'zero-copy' mean in the context of Arrow?"
- "How does Arrow relate to Parquet?"

Answer frame:
Arrow is a language-agnostic columnar in-memory format specification. The problem it solves is serialization overhead: before Arrow, passing data between Python libraries (NumPy → Pandas → custom C extension) required converting through intermediate formats, copying data at each step. Arrow defines a universal layout so all libraries can read the same bytes. Zero-copy means the data buffer is shared, not duplicated — only the array header (schema, buffer pointers) is passed. Arrow vs Parquet: Arrow is in-memory; Parquet is a compressed on-disk format. Reading a Parquet file with pyarrow produces an Arrow table; writing an Arrow table to Parquet is the natural persistence path.

---

## Related Notes

- [[numpy-internals|NumPy Internals and Memory Layout]]
- [[polars|Polars]]
- [[parquet|Parquet Format]]
- [[pandas-dataframe|Pandas DataFrame Internals]]
