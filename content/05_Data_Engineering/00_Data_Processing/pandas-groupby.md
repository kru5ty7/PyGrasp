---
title: 06 - Pandas GroupBy
description: "Pandas GroupBy implements the split-apply-combine pattern, and the choice between `agg`, `transform`, and `apply` determines whether you get a reduced result, a same-shape result, or an arbitrary Python result."
tags: [pandas, groupby, split-apply-combine, agg, transform, apply, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Pandas GroupBy

> GroupBy is the engine behind aggregations, feature engineering, and group-level transformations — but the choice between `agg`, `transform`, and `apply` is not interchangeable and each has a distinct performance profile.

---

## Quick Reference

**Core idea:**
- `df.groupby("col")` splits the DataFrame into groups without copying data (lazy)
- `agg(func)` — reduces each group to a scalar: returns a smaller DataFrame (one row per group)
- `transform(func)` — applies a function to each group but returns a same-shape result aligned to original index
- `apply(func)` — passes each group as a DataFrame to an arbitrary Python function; most flexible, least optimized
- Named aggregations: `df.groupby("g").agg(mean_x=("x", "mean"), max_y=("y", "max"))`
- `groupby(["a", "b"])` produces a `MultiIndex` result; `as_index=False` returns a flat column layout

**Tricky points:**
- `groupby` is lazy — no computation happens until you call `agg`, `transform`, `apply`, or another method
- `transform` must return a result with the same number of rows (or a scalar) — it raises if the shape doesn't match
- `apply` is a Python loop over groups; avoid it for anything achievable with `agg` or `transform`
- `groupby` with `sort=False` is faster for large DataFrames where group order doesn't matter
- String `nunique` in agg is slow on `object` dtype — cast to `category` first for repeated string data

---

## What It Is

Think of a post office sorting room. Hundreds of letters arrive in a big unsorted pile. Workers first sort the letters by destination city — that is the "split" step. Then each group of letters goes to a specific clerk who counts them, bundles them, or stamps them — that is the "apply" step. Finally, the results from all clerks are gathered back into a single report — the "combine" step. GroupBy in Pandas is that sorting room. The "destination city" is the column (or columns) you group by. The sorting, processing, and reassembly all happen automatically.

Pandas's split-apply-combine pattern was formalized by Hadley Wickham (for R's `plyr` package) and implemented in Pandas from its earliest versions. You call `df.groupby("region")`, which logically divides the DataFrame into one group per unique value in the `"region"` column. You then chain one of three action methods: `agg` to reduce each group to summary statistics, `transform` to compute group-level values that stay aligned with the original rows, or `apply` to pass each group as a full DataFrame to any Python function you write. The choice between these three is not stylistic — each produces a differently shaped result and has dramatically different performance characteristics.

The most important practical distinction is between `agg` and `transform`. Both can compute, say, the mean of a group. But `agg` returns a result with one row per group — the "summary table" case. `transform` returns a result with the same number of rows as the original DataFrame — the "annotate each row with its group's mean" case. If you want to create a new column where each row contains the average sales for its region (for computing deviation from regional mean, for example), `transform` is correct. Using `agg` for this and then merging back is the common workaround when people do not know `transform` exists.

---

## How It Actually Works

When you call `df.groupby("col")`, Pandas builds a `DataFrameGroupBy` object. Internally, this object computes a "grouper" — an array mapping each row index to a group label — but does not yet split or copy the data. The actual data remains in the original DataFrame's memory. When you subsequently call `.agg("mean")`, Pandas iterates over the groups using the grouper array, takes a view of each group's rows, applies the aggregation using a Cython-compiled path (for built-in functions like `"mean"`, `"sum"`, `"min"`, `"max"`, `"std"`), and assembles the result.

```python
import pandas as pd
import numpy as np

df = pd.DataFrame({
    "region": ["North", "South", "North", "South", "North"],
    "sales":  [100, 200, 150, 80, 120],
    "cost":   [60,  120, 90,  40, 70],
})

# agg: one row per group
summary = df.groupby("region").agg(
    total_sales=("sales", "sum"),
    avg_cost=("cost", "mean"),
    n=("sales", "count")
)
print(summary)
#        total_sales   avg_cost  n
# North          370  73.333333  3
# South          280  80.000000  2

# transform: same-shape result, each row gets its group's total
df["region_total"] = df.groupby("region")["sales"].transform("sum")
print(df[["region", "sales", "region_total"]])
# North  100  370,  South  200  280,  ...

# apply: arbitrary function, least optimized
def top_row(grp):
    return grp.nlargest(1, "sales")

top = df.groupby("region").apply(top_row)
print(top)
```

The Cython-compiled aggregation path is critically important for performance. Functions named as strings (`"mean"`, `"sum"`, `"count"`, `"min"`, `"max"`, `"first"`, `"last"`, `"std"`, `"var"`, `"nunique"`) invoke internal Cython routines that work directly on NumPy arrays without Python overhead per group. Passing a Python lambda or custom function forces Pandas to use a Python loop over groups, which is 10 to 100 times slower on large DataFrames. The rule: if you can express what you need as one of the named aggregations, always do so. If you need custom logic, see whether you can vectorize it with NumPy or `np.where` before falling back to `apply`.

`transform` works by calling the function (or built-in aggregation) on each group's data, then broadcasting the result back to all rows that belong to that group. The result has the same length as the original DataFrame and the same index, so it can be assigned directly as a new column. For window operations like "subtract each row from its group's mean," the pattern is `df["col"] - df.groupby("grp")["col"].transform("mean")` — no merge required.

---

## How It Connects

GroupBy results are DataFrames (for `agg`) or Series (for many `transform` calls), and the resulting index — whether a flat index or a MultiIndex — connects directly to Pandas indexing methods for subsequent selection and filtering.

[[pandas-indexing|Pandas Indexing and Selection]]

Merge and join operations often complement GroupBy: you GroupBy to produce a summary, then join it back to the original data. Understanding both operations — and when to use `transform` instead of GroupBy-then-merge — makes your code cleaner and faster.

[[pandas-merge-join|Pandas Merge and Join]]

---

## Common Misconceptions

Misconception 1: "I can use `apply` for any group operation and it will just be slower — but it will work correctly."
Reality: `apply` can produce surprising results when the function returns a scalar, a Series, or a DataFrame — Pandas infers the shape from the first group's return value and may raise or produce a wrongly shaped result for groups where the function returns a different type. `agg` and `transform` have strict contracts about their output shapes; `apply` does not.

Misconception 2: "`groupby` immediately copies data into separate group DataFrames."
Reality: `groupby` is lazy. It computes an index mapping (the grouper) but does not copy or split data. Data is processed group by group only when you call `agg`, `transform`, `apply`, or iterate the `GroupBy` object. Constructing a `GroupBy` object on a large DataFrame is cheap.

Misconception 3: "I need to `sort_values` before `groupby` to make groups work correctly."
Reality: Pandas `groupby` handles unsorted data correctly. Sorting beforehand is unnecessary and adds O(N log N) work. If you use `groupby(sort=False)`, Pandas skips the additional sort of group keys in the output — this is faster when you do not need the result in sorted group order.

---

## Why It Matters in Practice

GroupBy is the workhorse of feature engineering in data science pipelines. Computing group statistics — average sales per region, number of events per user per day, maximum value in a rolling segment — is required in almost every real-world dataset. Knowing when to use `agg` versus `transform` versus `apply` is the difference between code that is clear and fast versus code that is a nested loop over groups disguised as Pandas.

The `transform` pattern in particular is underused. Without it, the standard approach is `agg` to produce a summary, then `merge` back to the original on the group key. This works but creates intermediate DataFrames and requires careful handling of column name collisions. `transform` does the same thing in one line with better readability and typically better performance.

---

## Interview Angle

Common question forms:
- "Explain the split-apply-combine pattern in Pandas."
- "What is the difference between `agg`, `transform`, and `apply` in GroupBy?"
- "How would you add a column to a DataFrame that shows each row's value as a percentage of its group's total?"

Answer frame:
For split-apply-combine: groupby splits by unique values, apply processes each group, combine reassembles. For the three methods: `agg` reduces each group to scalars (fewer rows); `transform` returns same-shape output aligned to original index; `apply` calls arbitrary Python on each group and is slowest. For the percentage-of-group question: `df["pct"] = df["val"] / df.groupby("grp")["val"].transform("sum") * 100` — demonstrates `transform` for a same-shape division operation.

---

## Related Notes

- [[pandas-basics|Pandas Basics]]
- [[pandas-indexing|Pandas Indexing and Selection]]
- [[pandas-merge-join|Pandas Merge and Join]]
