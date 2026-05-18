---
title: Hash Tables
description: A hash table maps keys to values via a hash function, enabling O(1) average lookup, insert, and delete.
tags: [dsa, layer-10, hash-table, hash-map]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Hash Tables

> Hash tables are the most practically useful data structure in everyday programming — they turn the O(n) cost of finding a value by its meaning into an O(1) cost by computing where it lives.

---

## Quick Reference

**Core idea:**
- A hash function maps each key to an integer, which is reduced modulo the table size to give a bucket index
- O(1) average lookup, insert, and delete — regardless of the number of stored entries
- Python's `dict` is a hash table; Python's `set` is a hash table without values
- Keys must be hashable — they must implement `__hash__` and `__eq__`; mutable objects like lists cannot be keys
- When two keys hash to the same bucket, a collision occurs — Python resolves this with open addressing

**Tricky points:**
- O(1) is the average case; worst case is O(n) when all keys collide into one bucket
- The `__hash__` and `__eq__` contract: if `a == b` then `hash(a) == hash(b)` must hold
- Objects that are equal must have equal hashes — violating this breaks dict and set
- Python's dict maintains insertion order since Python 3.7
- `hash()` returns different values across Python process restarts (hash randomisation) — do not persist hash values

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Lookup (get) | O(1) | O(n) |
| Insert (set) | O(1) amortized | O(n) |
| Delete | O(1) average | O(n) |
| Iteration | O(n) | O(n) |
| Membership test (in) | O(1) average | O(n) |

Space complexity: O(n)

---

## What It Is

Imagine a library with 10,000 books. If you want to find a book by author surname, you could scan every shelf — that is O(n). Or the library could assign each author to a shelf number based on a formula applied to their surname: take the sum of the character codes, divide by the number of shelves, use the remainder as the shelf number. Now finding a book requires computing one formula and going directly to one shelf. The formula is the hash function; the shelves are the buckets.

The magic is that this formula requires no knowledge of what other books exist. The shelf for "Tolkien" is computed independently of whether the library has ten books or ten million. The lookup time is therefore independent of the library's size — O(1). The cost you pay is that two authors might occasionally be assigned the same shelf (a collision), and the library must have a strategy for handling that. But as long as collisions are rare (a well-designed hash function and a table that is not too full), the average performance stays near O(1).

Hash tables are the structure behind Python's `dict`, `set`, and `frozenset`. They are what makes `"key" in my_dict` instantaneous regardless of whether the dictionary has 10 or 10 million entries. They underpin database index structures, caching systems, symbol tables in compilers, and deduplication logic. Any problem that involves counting, grouping, or looking up by a meaningful identifier is likely best solved with a hash table.

---

## How It Actually Works

The hash table internally maintains an array of buckets. When you insert a key-value pair, Python calls `hash(key)` to obtain an integer, then computes `bucket_index = hash(key) % table_size` to find the target bucket. The entry is stored there. On lookup, the same computation is performed: hash the key, compute the index, go directly to that bucket and check whether the key there matches.

When two keys map to the same bucket (a collision), Python uses open addressing: rather than storing multiple entries at the same slot, it probes for the next available slot using a pseudo-random probing sequence derived from the hash value. On lookup, if the first bucket does not match the key, Python follows the same probe sequence until it finds a matching key or an empty slot (indicating the key is absent).

The table resizes when its load factor (number of entries / table size) exceeds a threshold (roughly 2/3 in CPython). Resizing allocates a larger array and rehashes all existing entries into it. This is O(n) but happens infrequently enough that the amortized cost per insert remains O(1).

```python
# Python dict IS a hash table
d = {}
d["name"] = "Alice"      # O(1) insert
d["age"] = 30
print(d["name"])          # O(1) lookup
print("age" in d)         # O(1) membership
del d["age"]              # O(1) delete

# Keys must be hashable
try:
    d[[1, 2]] = "list key"    # TypeError: unhashable type: 'list'
except TypeError as e:
    print(e)

# Tuples are hashable (immutable)
d[(1, 2)] = "tuple key"    # fine

# Custom hashable class — must implement __hash__ and __eq__
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def __eq__(self, other):
        return isinstance(other, Point) and self.x == other.x and self.y == other.y

    def __hash__(self):
        return hash((self.x, self.y))   # delegate to tuple hash

p1 = Point(1, 2)
p2 = Point(1, 2)
mapping = {p1: "origin-ish"}
print(mapping[p2])    # "origin-ish" — equal keys, equal hashes

# Simplified hash table implementation
class SimpleHashTable:
    def __init__(self, capacity=16):
        self._capacity = capacity
        self._buckets = [None] * self._capacity
        self._size = 0

    def _hash(self, key):
        return hash(key) % self._capacity

    def _probe(self, key):
        """Linear probing for demonstration; CPython uses pseudo-random probing."""
        index = self._hash(key)
        while self._buckets[index] is not None:
            stored_key, _ = self._buckets[index]
            if stored_key == key:
                return index    # found existing key
            index = (index + 1) % self._capacity
        return index            # found empty slot

    def put(self, key, value):
        if self._size / self._capacity >= 0.67:
            self._resize()
        index = self._probe(key)
        if self._buckets[index] is None:
            self._size += 1
        self._buckets[index] = (key, value)

    def get(self, key):
        index = self._hash(key)
        while self._buckets[index] is not None:
            stored_key, stored_value = self._buckets[index]
            if stored_key == key:
                return stored_value
            index = (index + 1) % self._capacity
        raise KeyError(key)

    def _resize(self):
        old_buckets = self._buckets
        self._capacity *= 2
        self._buckets = [None] * self._capacity
        self._size = 0
        for entry in old_buckets:
            if entry is not None:
                self.put(entry[0], entry[1])

    def __contains__(self, key):
        try:
            self.get(key)
            return True
        except KeyError:
            return False


ht = SimpleHashTable()
ht.put("a", 1)
ht.put("b", 2)
ht.put("a", 99)  # update
print(ht.get("a"))     # 99
print("b" in ht)       # True
print("c" in ht)       # False

# Common patterns with Python dict
words = ["apple", "banana", "apple", "cherry", "banana", "apple"]
frequency = {}
for word in words:
    frequency[word] = frequency.get(word, 0) + 1
print(frequency)  # {'apple': 3, 'banana': 2, 'cherry': 1}

# groupby pattern
from collections import defaultdict
groups = defaultdict(list)
for word in words:
    groups[word[0]].append(word)
print(dict(groups))  # {'a': ['apple', 'apple', 'apple'], 'b': [...], 'c': [...]}
```

---

## How It Connects

Hash collisions are the failure mode of hash tables. Understanding what causes them, how Python resolves them with open addressing, and what the worst-case implications are is the essential second chapter after learning what a hash table is.

[[hash-collisions|Hash Collisions]]

Python's `dict` is the most-used hash table in the language. Its internal layout — compact array with a separate indices table — is an optimisation over the basic design described here, and understanding the internals helps reason about memory and performance at scale.

[[dict-internals|Dict Internals]]

---

## Common Misconceptions

Misconception 1: "dict lookup is always O(1)."
Reality: Dict lookup is O(1) on average, assuming a good hash function and a low load factor. In the worst case — when many keys hash to the same bucket — lookup degrades to O(n). Python's hash randomisation makes it difficult for an attacker to engineer this situation deliberately, but degenerate hash functions on custom classes can cause it accidentally.

Misconception 2: "Any Python object can be a dict key."
Reality: Only hashable objects can be dict keys. An object is hashable if it has a `__hash__` method that returns an integer and an `__eq__` method that is consistent with it. Mutable built-in containers (`list`, `dict`, `set`) are not hashable. Immutable containers (`tuple`, `frozenset`) are hashable if their contents are.

Misconception 3: "The `__hash__` contract only matters if I use the object as a dict key."
Reality: The `__hash__` and `__eq__` contract also matters for sets and for any framework that internally uses hashing for deduplication or grouping. Breaking the contract — defining `__eq__` without `__hash__`, or making `__hash__` return a different value for equal objects — causes silent, hard-to-debug errors.

---

## Why It Matters in Practice

Hash tables are the answer to almost every "check if we've seen this before" or "count how many times each item appears" problem. They turn O(n²) duplicate-detection loops into O(n) single-pass solutions. In database query optimisers, hash joins use a hash table to match rows from two tables without sorting. In web servers, session stores and route dispatchers are hash tables. In compilers, symbol tables — which map variable names to their types and memory locations — are hash tables.

The performance cliff is equally important to understand. A hash table with a poor hash function, a very high load factor, or a maliciously crafted input set can degrade to O(n) per operation. For public-facing services that accept arbitrary user input as keys (URL parameters, JSON keys), Python's PYTHONHASHSEED randomisation is the mitigation. For internal code, ensuring custom `__hash__` implementations distribute keys well is the developer's responsibility.

---

## Interview Angle

Common question forms:
- "Two Sum — find two numbers in an array that add to a target."
- "Group anagrams — group strings that are anagrams of each other."
- "Implement a hash table from scratch."
- "What happens when you use a mutable object as a dict key?"
- "Why is dict lookup O(1)?"

Answer frame:
For Two Sum, describe the single-pass hash table approach: as you iterate, check if `target - current_value` is in the table, and if not, insert `current_value`. For "explain O(1) lookup," describe the hash function, the modulo to get the bucket index, and the direct array access — no comparison with other keys required. For custom hash table implementation, describe open addressing and the resize-at-2/3-load-factor strategy.

---

## Related Notes

- [[hash-collisions|Hash Collisions]]
- [[sets|Python Sets]]
- [[dicts|Python Dicts]]
