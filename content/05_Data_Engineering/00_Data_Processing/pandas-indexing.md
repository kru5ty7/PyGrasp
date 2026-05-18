---
title: 05 - Pandas Indexing and Selection
description: "Pandas offers three indexing systems  -  `loc`, `iloc`, and `[]`  -  that differ in whether they use labels, positions, or a mixed shorthand, and chaining them is a reliable path to silent bugs."
tags: [pandas, indexing, loc, iloc, chained-indexing, SettingWithCopyWarning, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Pandas Indexing and Selection

> `loc`, `iloc`, and `[]` look similar but operate on fundamentally different concepts  -  mixing them or chaining them is the single most common source of silent data corruption in Pandas code.

---

## Quick Reference

**Core idea:**
- `df.loc[row_label, col_label]`  -  label-based; both endpoints of a slice are **inclusive**
- `df.iloc[row_int, col_int]`  -  position-based; slice endpoint is **exclusive** (Python convention)
- `df[col_name]`  -  column selection by label (returns a `Series`); `df[[col1, col2]]` returns a DataFrame
- Boolean indexing: `df.loc[boolean_series, :]`  -  always use `loc` with boolean masks for clarity
- Chained indexing (`df["col"][mask] = val`) is ambiguous and unreliable  -  always use a single `loc` expression
- `SettingWithCopyWarning` (Pandas <2.0) means your assignment may have gone to a temporary copy; CoW (2.0+) changes but does not eliminate the concern

**Tricky points:**
- `df.loc["a":"c"]` includes row `"c"`; `df.iloc[0:3]` excludes row at position 3  -  the slice semantics differ
- Boolean masks passed to `[]` select rows; string keys passed to `[]` select columns  -  same syntax, different behavior
- `df.at[label, col]` and `df.iat[pos, col]` are scalar-optimized versions of `loc`/`iloc`  -  much faster in tight loops
- Selecting a single column with `df[col]` can return a view or copy depending on dtype  -  never rely on mutation through it
- `df.query("col > 5")` is a string-based alternative that avoids chaining and is often faster for simple filters

---

## What It Is

Think about how a librarian finds a book. One approach: use the catalog system  -  look up the book by its title or call number, which gives you a precise location. Another approach: walk to the third shelf, count fifteen books from the left, and take that one. Both approaches get you a book, but they are completely different instructions. The first approach works even if the library reorganizes its shelves (as long as the catalog is updated). The second approach breaks immediately if someone inserts a new book anywhere before position fifteen. Pandas has both approaches  -  and a third, more casual one that the librarian uses when she already knows exactly which room she is heading to.

`loc` is the catalog approach: you ask for rows and columns by their labels. If your DataFrame's index contains dates and your columns are named `"sales"` and `"cost"`, you write `df.loc["2023-01-01":"2023-03-31", "sales"]` and get exactly those rows and that column, regardless of where they physically sit in the underlying array. `iloc` is the position approach: `df.iloc[0:90, 0]` means "the first 90 rows, the first column"  -  no knowledge of labels required, but the result changes if rows are added, removed, or reordered. `df["column"]` is the casual shorthand for column selection, fine for quick exploration but limited in power.

The chained indexing trap emerges when you combine these accessors in a sequence. Writing `df["sales"][df["sales"] > 100] = 0` looks natural but is actually two separate indexing operations. The first, `df["sales"]`, might return a view or a copy depending on internal dtype layout  -  Pandas does not guarantee which. The second, `[df["sales"] > 100] = 0`, applies to whatever the first operation returned. If it returned a copy, your assignment changes nothing in `df`. If it returned a view, it modifies `df`. Pandas cannot know which case applies at write time, which is why it raises `SettingWithCopyWarning`. The correct form is a single operation: `df.loc[df["sales"] > 100, "sales"] = 0`.

---

## How It Actually Works

Internally, `loc` dispatches through `_LocIndexer`, which accepts labels (scalars, lists, slices, or boolean arrays) and translates them to integer positions using the Index's `get_loc` or `get_indexer` method. For a `RangeIndex`, label and position are the same integer, so `loc` and `iloc` appear identical. For a string or datetime index, `get_loc` performs a hash lookup, which is O(1) for unique labels. For duplicate labels, `get_loc` may return a slice or array, which is why DataFrames with duplicate index values can return unexpected shapes from `loc`.

```python
import pandas as pd

df = pd.DataFrame({
    "a": [10, 20, 30, 40, 50],
    "b": [1.1, 2.2, 3.3, 4.4, 5.5]
}, index=["x", "y", "z", "w", "v"])

# loc: label-based, inclusive slice
print(df.loc["y":"w", "a"])       # y=20, z=30, w=40

# iloc: position-based, exclusive slice
print(df.iloc[1:4, 0])            # y=20, z=30, w=40  (same result here)
print(df.iloc[1:3, 0])            # y=20, z=30  (stops before position 3)

# Boolean indexing through loc
mask = df["a"] > 25
df.loc[mask, "b"] = 0.0            # correct: single operation

# Chained  -  DO NOT DO THIS
# df["b"][mask] = 0.0              # ambiguous: may silently do nothing

# Scalar access: at/iat are faster than loc/iloc for single values
print(df.at["z", "a"])            # 30
print(df.iat[2, 0])               # 30
```

`SettingWithCopyWarning` is generated by Pandas when it detects that you have chained two indexing operations together and are trying to assign through them. Internally, this check happens in `NDFrame.__setitem__` after the indexer chain is resolved. Pandas checks `_is_copy`  -  a weak reference to the potential parent DataFrame  -  and emits the warning if it suspects the target is a copy. This detection is heuristic, not certain, which is why "warning" is accurate  -  the warning means "I am not sure whether this worked."

Pandas 2.0 Copy-on-Write eliminates the ambiguity by making all indexing return lazy copies  -  the data is shared until a write happens, at which point only the written column is copied. The warning is suppressed (it was confusing), but the correct pattern remains the same: always write through a single `loc` expression.

---

## How It Connects

DataFrame internals  -  specifically Copy-on-Write semantics and how Pandas 2.0 handles column ownership  -  directly explain why the chained indexing trap exists and why it was fixed in a particular way.

[[pandas-dataframe|Pandas DataFrame Internals]]

GroupBy and merge operations return new DataFrames with potentially restructured indexes; understanding label-based indexing via `loc` is essential for working with these results correctly, especially when the index is a MultiIndex or a non-default RangeIndex.

[[pandas-groupby|Pandas GroupBy]]

---

## Common Misconceptions

Misconception 1: "`df['col']` and `df.loc[:, 'col']` are always equivalent and return the same thing."
Reality: For column selection they return the same `Series`, but `df['col']` may return a view or copy depending on dtype (pre-2.0) while `df.loc[:, 'col']` is a more explicit label-based accessor. For row selection, `df['col']` does not work at all  -  it selects columns, not rows.

Misconception 2: "`df.loc['a':'c']` follows Python's normal slice convention where the end is excluded."
Reality: `loc` slices are **inclusive** on both ends because they are label-based. If your index contains `'a', 'b', 'c', 'd'`, then `df.loc['a':'c']` returns rows `a`, `b`, and `c`  -  all three. `iloc` follows Python's exclusive-end convention.

Misconception 3: "The `SettingWithCopyWarning` is just noisy output I can silence with `pd.options.mode.chained_assignment = None`."
Reality: Silencing the warning does not fix the underlying issue. If the chain was modifying a copy, your assignment silently does nothing and your data remains unchanged. Fix the root cause by using `df.loc[condition, col] = value` in a single operation.

---

## Why It Matters in Practice

Chained indexing bugs are among the most common silent correctness issues in Pandas code. They appear most often in data cleaning pipelines where someone writes `df[df["col"].notna()]["other_col"] = fixed_value`  -  the assignment appears to work (no error is raised), but the DataFrame is unchanged. Hours later, a downstream check finds dirty data with no obvious cause. The fix is always the same: restructure as a single `loc` operation.

Understanding the difference between `loc` and `iloc` also matters when working with data that has been sorted, filtered, or reset-indexed. After a `df.sort_values()`, the integer positions and the index labels no longer align  -  `iloc[0]` and `df.loc[df.index[0]]` might give the same row, but only by coincidence. Using the wrong accessor on re-indexed data produces results that are subtly wrong and hard to debug.

---

## Interview Angle

Common question forms:
- "What is `SettingWithCopyWarning` and what causes it?"
- "What is the difference between `loc` and `iloc`?"
- "How would you safely update a subset of rows in a DataFrame?"

Answer frame:
For `SettingWithCopyWarning`: it occurs when two indexing operations are chained  -  Pandas cannot guarantee whether the intermediate result is a view or a copy, so an assignment to it may silently fail. For `loc` vs `iloc`: `loc` is label-based and inclusive on both ends; `iloc` is position-based and exclusive at the end. For safe row updates: `df.loc[boolean_mask, "column"] = value`  -  a single `loc` call that targets both the rows and the column in one operation, which always works regardless of view/copy semantics.

---

## Related Notes

- [[pandas-basics|Pandas Basics]]
- [[pandas-dataframe|Pandas DataFrame Internals]]
- [[pandas-groupby|Pandas GroupBy]]
- [[pandas-merge-join|Pandas Merge and Join]]
