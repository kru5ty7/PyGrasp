---
title: 01 - NumPy Basics
description: "NumPy provides the `ndarray`, a fixed-type, contiguous-memory array that makes numerical computation in Python orders of magnitude faster than native Python lists."
tags: [numpy, ndarray, vectorization, broadcasting, dtype, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# NumPy Basics

> NumPy's `ndarray` is the foundation of numerical Python  -  a typed, fixed-shape array stored in contiguous memory that enables C-speed arithmetic on entire datasets without writing a single loop.

---

## Quick Reference

**Core idea:**
- `ndarray` stores elements of a single `dtype` in a contiguous block of memory
- Shape is a tuple of ints; `ndim`, `shape`, `dtype`, `itemsize`, `nbytes` are the primary introspection attributes
- Vectorized operations (e.g. `arr * 2`) apply element-wise at C speed  -  no Python loop needed
- Broadcasting allows arithmetic between arrays of different but compatible shapes
- `np.zeros`, `np.ones`, `np.arange`, `np.linspace`, `np.random.default_rng()` are the standard constructors
- Universal functions (`ufuncs`) like `np.sqrt`, `np.exp`, `np.sum` operate element-wise and support `axis` parameter

**Tricky points:**
- Default integer dtype on Windows is `int32`; on Linux/macOS it is `int64`  -  never assume
- Slicing an ndarray returns a **view**, not a copy; mutating the slice mutates the original
- `arr.shape` is a tuple  -  `arr.shape[0]` is the row count, not `len(arr)` (though `len` also works for 1-D)
- `np.array([1, 2, 3.0])` upcasts to `float64`  -  dtype is inferred from the most general element
- Boolean indexing always returns a **copy**, not a view

---

## What It Is

Think of a spreadsheet column full of numbers. Each cell holds a number, the cells are in a fixed order, and every cell is the same type  -  all integers, or all decimals. Because the cells are all the same size and arranged one after another, the computer can jump directly to any cell by simple arithmetic: start address plus (cell number times cell size). There is no searching, no following pointers, no checking what type each cell is. Python's built-in lists are not like this  -  each element is a separate Python object floating somewhere in memory, connected by a pointer. Lists are flexible but slow when you need to do math on millions of numbers.

NumPy's `ndarray` is the spreadsheet column taken to multiple dimensions. A one-dimensional ndarray is like that column: every element is the same numeric type, stored back to back in memory, addressable in constant time. A two-dimensional ndarray is like a spreadsheet grid  -  rows and columns, all same type, all contiguous. Three dimensions and beyond follow the same pattern. Because NumPy knows at creation time exactly how many bytes each element occupies and what arithmetic rules apply to that type, it can hand a large computation off to compiled C or Fortran code and let that code run without ever coming back to the Python interpreter for each element.

Vectorized operations are the practical consequence of this design. When you write `arr * 2` in NumPy, you are not asking Python to loop over each element. Instead, NumPy calls a compiled C function that walks through memory multiplying each element by 2 at hardware speed. For an array of one million floats, this is roughly 100 times faster than a Python `for` loop doing the same work. Broadcasting extends this further: when two arrays have compatible but different shapes  -  say, a (3, 4) matrix and a (4,) vector  -  NumPy figures out how to align them logically without actually duplicating data, then applies the operation across both. This lets you write `matrix + row_vector` and get exactly what you expect without manually reshaping anything.

---

## How It Actually Works

An `ndarray` is a Python object that wraps a raw data buffer, a `dtype` descriptor, a shape tuple, and a strides tuple. The data buffer is a flat block of bytes  -  there is nothing two-dimensional about it in memory. The strides tuple is what makes multi-dimensional indexing work: each entry says how many bytes to advance in the buffer to move one step along that axis. A C-contiguous (row-major) 2-D array of shape (3, 4) with `float64` elements has strides `(32, 8)`  -  moving to the next row requires skipping 4 elements × 8 bytes, moving to the next column requires skipping 1 element × 8 bytes. Slicing works by returning a new array header pointing into the same buffer with adjusted strides and offsets  -  no data is copied.

```python
import numpy as np

a = np.arange(12, dtype=np.float64).reshape(3, 4)
print(a.strides)   # (32, 8)
b = a[1:, ::2]     # view: rows 1-2, every other column
print(b.strides)   # (32, 16)  -  same buffer, different strides
b[0, 0] = 999      # mutates a as well
```

Universal functions (ufuncs) are compiled C functions that implement element-wise operations. They receive arrays, walk through the data buffer respecting strides, and write results to an output buffer. Most ufuncs accept an `out` parameter to write in place and an `axis` parameter for reduction operations. The `axis` parameter is zero-indexed and refers to which dimension to collapse: `arr.sum(axis=0)` collapses rows (producing one value per column), `arr.sum(axis=1)` collapses columns (producing one value per row). Getting `axis` wrong is one of the most common NumPy mistakes, and the fix is always to reason about which dimension you want to disappear.

---

## How It Connects

NumPy arrays are stored in contiguous memory and use a fixed dtype  -  both properties tie directly to how CPython allocates and manages raw memory objects. Understanding Python's memory model explains why slices return views (the buffer is shared) and why `copy()` is sometimes necessary. The buffer protocol that makes NumPy interoperable with other libraries is also part of CPython's object system.

[[python-memory-model|Python's Memory Model]]

The ndarray's design  -  typed, contiguous, strided  -  directly informs NumPy's more advanced memory layout behavior, including the distinction between C-contiguous and Fortran-contiguous arrays, views versus copies, and the buffer protocol used by libraries like Pillow and PyTorch.

[[numpy-internals|NumPy Internals and Memory Layout]]

Pandas is built on top of NumPy: every column in a DataFrame is backed by a NumPy array (or an Arrow-backed extension array in newer versions). Understanding ndarray dtype rules and vectorized operations is a prerequisite for understanding why certain Pandas operations are fast and others are not.

[[pandas-basics|Pandas Basics]]

Apache Arrow provides an alternative columnar memory format that is increasingly replacing raw NumPy buffers in high-performance libraries. NumPy and Arrow can share memory via the buffer protocol in many cases, making an understanding of ndarray layout essential for working with Arrow-native tools.

[[arrow|Apache Arrow]]

---

## Common Misconceptions

Misconception 1: "NumPy arrays work like Python lists  -  slicing gives me a copy I can safely mutate."
Reality: Slicing an ndarray returns a view into the original buffer. Mutating `b = a[1:3]` will also change `a`. Use `a[1:3].copy()` explicitly when you need independence.

Misconception 2: "I can mix types in an ndarray like I can in a list."
Reality: An ndarray has a single `dtype`. When you create one from a mixed list, NumPy silently upcasts everything to the most general type  -  integers become floats if any float is present. You lose type precision without any warning.

Misconception 3: "A bigger shape means more dimensions means more computation. Reshaping is slow."
Reality: `reshape` does not copy data as long as the total number of elements is unchanged. It returns a view with new shape and strides. The operation is O(1).

---

## Why It Matters in Practice

If you write Python loops over large numerical datasets  -  even short ones that "seem fast enough"  -  you are leaving enormous performance on the table. The difference between a vectorized NumPy operation and an equivalent Python loop is not a constant factor; it scales with array size and compounds when operations are chained. Data pipelines that process millions of rows, machine learning preprocessing steps, and scientific simulations all depend on NumPy to be feasible.

Once you understand that an ndarray is a typed buffer with a shape and strides, a whole class of confusing behaviors becomes obvious: why slices are views, why dtype upcasting happens silently, why operations across incompatible shapes raise errors, and why certain reshaping tricks are free. This mental model also carries over directly to PyTorch tensors, TensorFlow tensors, and Arrow arrays, which are all conceptually the same structure with variations in memory ownership and device placement.

---

## Interview Angle

Common question forms:
- "Why is NumPy so much faster than a Python list for numerical operations?"
- "What is broadcasting in NumPy? Give an example where it matters."
- "When does a NumPy slice return a view versus a copy?"

Answer frame:
Start with the memory layout difference: Python list elements are Python objects (heap-allocated, pointer-chased); NumPy elements are raw bytes in a contiguous typed buffer. Vectorized operations hand the entire buffer to compiled C code that never re-enters the Python interpreter per element. For broadcasting, explain that NumPy expands shapes logically  -  it prepends 1s to the shorter shape, then repeats along size-1 dimensions  -  and that no data is physically duplicated. For views vs copies: basic slicing always returns a view; fancy indexing (integer arrays, boolean masks) always returns a copy. Strides are the mechanism that makes views work.

---

## Related Notes

- [[numpy-internals|NumPy Internals and Memory Layout]]
- [[pandas-basics|Pandas Basics]]
- [[arrow|Apache Arrow]]
- [[python-memory-model|Python's Memory Model]]
