---
title: 03 - Pandas Basics
description: "Pandas provides `Series` and `DataFrame`  -  labeled, indexed data structures built on NumPy that make tabular data manipulation expressive and fast."
tags: [pandas, dataframe, series, dtype, indexing, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Pandas Basics

> Pandas is the standard Python library for tabular data  -  its `Series` and `DataFrame` give you labeled, typed, indexed arrays that transform, filter, and summarize data with a readable syntax.

---

## Quick Reference

**Core idea:**
- `Series` = 1-D labeled array with an `Index`; `DataFrame` = 2-D table of `Series` sharing a common `Index`
- `dtypes` per column: `int64`, `float64`, `object` (for strings/mixed), `bool`, `datetime64[ns]`, `category`
- Key creation methods: `pd.DataFrame(dict)`, `pd.read_csv()`, `pd.read_parquet()`, `pd.read_sql()`
- Basic operations: `df.head()`, `df.info()`, `df.describe()`, `df.shape`, `df.dtypes`, `df.columns`
- Vectorized operations via `.str`, `.dt`, `.apply` accessor namespaces
- Missing values: `NaN` for floats, `pd.NA` for nullable integer/string types, `pd.NaT` for datetimes

**Tricky points:**
- `object` dtype means "arbitrary Python objects"  -  strings stored as `object` lose vectorization benefits
- Pandas `int64` column becomes `float64` if even one `NaN` is present (legacy behavior; use `Int64` nullable type to avoid)
- `df.apply(func)` is a Python loop internally  -  it is not vectorized; prefer built-in methods or `np.vectorize`
- The default `RangeIndex` is not stored in memory; a custom index is a real array that takes space
- Column assignment to a slice may trigger `SettingWithCopyWarning`  -  this is a sign of chained indexing

---

## What It Is

Imagine a spreadsheet program  -  something like Excel. You have rows of data, each row representing one observation: a customer order, a weather reading, a stock price. The columns each have a name and hold one type of data: dates in one column, prices in another, category names in a third. You can sort, filter, group, and summarize data by clicking through menus. Pandas is that spreadsheet, but programmable. Instead of clicking, you write code. Instead of being limited by what the menu offers, you can express any transformation as a function. And instead of slowing down at 100,000 rows, it processes millions of rows in seconds.

A `Series` is Pandas's one-dimensional labeled array. It has values (a NumPy array or extension array underneath) and an index (a label for each position). The index can be integers, strings, dates, or any hashable type. A `DataFrame` is a collection of `Series` that all share the same index  -  think of it as a dict of `Series`, where each key is a column name and each value is a `Series` of that column's data. The alignment by index is what makes Pandas powerful: when you add two DataFrames together, Pandas aligns them on their index, not their position. If one has a row labeled `"2023-01-01"` and the other has no such label, the result is `NaN` for that row, not silent misalignment.

Creating a DataFrame is straightforward: pass a dictionary of lists (`pd.DataFrame({"col": [1, 2, 3]})`), read from a CSV (`pd.read_csv("data.csv")`), or load from a Parquet file (`pd.read_parquet("data.parquet")`). Once loaded, `df.info()` gives you a summary of columns, non-null counts, and dtypes  -  the first thing to run on any new dataset. `df.describe()` gives statistical summaries for numeric columns. `df.head(n)` shows the first n rows. These three calls are the standard opening move when you encounter unfamiliar data.

---

## How It Actually Works

Internally, a `Series` is a thin Python object wrapping a one-dimensional array (typically a NumPy ndarray) and an `Index` object. The `Index` itself is an ndarray of labels with some additional structure for fast label lookup (a hash map in most cases). When you do `series["label"]`, Pandas consults this hash map to find the integer position, then uses that position to index the underlying array. For a `RangeIndex` (the default when you create a DataFrame without specifying an index), there is no actual array  -  labels are computed on demand from start, stop, and step parameters, so it uses essentially no memory.

```python
import pandas as pd
import numpy as np

df = pd.DataFrame({
    "name": ["Alice", "Bob", "Carol"],
    "score": [92.5, 88.0, 95.1],
    "passed": [True, True, True]
})

print(df.dtypes)
# name       object
# score     float64
# passed       bool

s = df["score"]
print(type(s.values))  # <class 'numpy.ndarray'>
print(s.values.dtype)  # float64

# String accessor: vectorized, no Python loop
df["name_upper"] = df["name"].str.upper()

# Datetime accessor
dates = pd.to_datetime(["2023-01-01", "2023-06-15"])
s_dates = pd.Series(dates)
print(s_dates.dt.month)  # [1, 6]
```

The `object` dtype deserves special attention. When Pandas stores strings or mixed-type data, it falls back to `object`, which means the underlying array holds Python object pointers rather than dense byte values. String operations on `object` columns iterate over Python string objects  -  they are not vectorized at the C level the way numeric operations are. Pandas 1.0 introduced `StringDtype` and Pandas 2.0 expanded nullable extension types (`Int8`, `Int16`, ..., `Int64`, `Float32`, `Float64`, `boolean`, `string`) to address this. Using `pd.StringDtype()` for string columns and `pd.Int64Dtype()` for nullable integers reduces memory and improves performance for large datasets.

---

## How It Connects

Pandas columns are backed by NumPy arrays; understanding ndarray dtype rules, vectorization, and memory layout is a prerequisite for understanding why Pandas behaves the way it does with numeric data  -  especially around dtype promotion when NaN appears.

[[numpy-basics|NumPy Basics]]

The internal structure of a DataFrame  -  how columns are stored together in blocks, how the block manager handles homogeneous vs heterogeneous dtypes  -  is the deeper story behind Pandas performance and memory behavior.

[[pandas-dataframe|Pandas DataFrame Internals]]

Selecting and modifying data in Pandas is surprisingly subtle; the distinction between `loc`, `iloc`, and `[]`  -  and the chained indexing trap  -  builds directly on the basics established here.

[[pandas-indexing|Pandas Indexing and Selection]]

Polars is a faster alternative to Pandas for large datasets; understanding Pandas basics provides the vocabulary needed to appreciate what Polars does differently with lazy evaluation and Arrow-native storage.

[[polars|Polars]]

---

## Common Misconceptions

Misconception 1: "Pandas automatically uses fast C code for everything, just like NumPy."
Reality: Pandas vectorizes numeric operations on numeric columns, but string operations on `object` dtype columns are Python loops over Python string objects. For string-heavy datasets at scale, use `StringDtype` or switch to Polars.

Misconception 2: "NaN and None are the same thing in Pandas."
Reality: `NaN` is a floating-point IEEE 754 value that only makes sense for `float64` columns. Inserting `None` into a numeric column triggers dtype promotion to `float64` and replaces `None` with `NaN`. In `object` columns, `None` stays as `None`. Pandas 1.0+ offers `pd.NA` as a unified missing-value sentinel that works across all nullable types.

Misconception 3: "`df.apply(my_function)` is fast because Pandas runs it in C."
Reality: `apply` iterates over rows or columns in Python, calling your function once per row/column. It is a Python loop with Pandas overhead. Use vectorized methods (`.str`, `.dt`, arithmetic operators, `np.where`, `pd.cut`) wherever possible.

---

## Why It Matters in Practice

Pandas is the de facto standard for tabular data manipulation in Python data engineering. Almost every pipeline that ingests CSV, Parquet, or SQL data will touch Pandas before sending data downstream to a model, a database, or a report. Knowing the semantics of dtypes, index alignment, and which operations are truly vectorized determines whether your pipeline processes 1 million rows in 2 seconds or 60 seconds.

The gotchas  -  `object` dtype strings, NaN promotion, `apply` performance  -  are the source of a large fraction of real-world Pandas performance bugs. Developers who understand what is happening under the surface choose the right dtype at read time, avoid `apply` for numeric operations, and write code that stays fast as data volumes grow.

---

## Interview Angle

Common question forms:
- "What is the difference between a Pandas Series and a DataFrame?"
- "Why is string processing in Pandas slow compared to numeric processing?"
- "What happens to a DataFrame's integer column when you insert a NaN?"

Answer frame:
For Series vs DataFrame: Series is a 1-D labeled array; DataFrame is a dict of Series sharing an index. Explain index alignment as the key differentiator from a plain dict. For string performance: `object` dtype stores Python object pointers, not dense bytes; operations iterate Python objects. Recommend `StringDtype` or Polars for scale. For NaN in an integer column: the column is promoted from `int64` to `float64` because NumPy's integer type has no NaN representation. Use `pd.Int64Dtype()` to preserve integers with nullable support.

---

## Related Notes

- [[numpy-basics|NumPy Basics]]
- [[pandas-dataframe|Pandas DataFrame Internals]]
- [[pandas-indexing|Pandas Indexing and Selection]]
- [[pandas-groupby|Pandas GroupBy]]
- [[pandas-merge-join|Pandas Merge and Join]]
- [[polars|Polars]]
