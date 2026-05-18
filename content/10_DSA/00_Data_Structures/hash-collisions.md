---
title: 09 - Hash Collisions
description: A hash collision occurs when two different keys produce the same bucket index, requiring a resolution strategy to maintain correctness.
tags: [dsa, layer-10, hash-table, collisions]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Hash Collisions

> Collisions are not a failure of hash tables — they are mathematically inevitable, and the resolution strategy determines whether the hash table stays near O(1) or degrades toward O(n).

---

## Quick Reference

**Core idea:**
- A collision occurs when `hash(key_a) % table_size == hash(key_b) % table_size` for two different keys
- Two resolution strategies: chaining (each bucket holds a list of entries) and open addressing (probe for next free slot)
- CPython's `dict` uses open addressing with a pseudo-random probe sequence
- Worst case for any hash table is O(n) — when all n keys land in the same bucket
- Python uses hash randomisation (PYTHONHASHSEED) to prevent deliberate collision injection (Hash DoS)

**Tricky points:**
- The birthday paradox means collisions become likely far sooner than intuition suggests — with 23 people, there is a 50% chance two share a birthday; hash collision probability grows similarly
- Open addressing requires that lookups continue probing on collision — deleted slots need a "tombstone" marker, not a true empty marker
- Hash DoS attacks work by finding many strings with the same hash, causing all to collide in one bucket — this degrades service from O(1) to O(n)
- PYTHONHASHSEED randomises the hash seed per process, so `hash("abc")` returns a different value on each Python restart
- Load factor (entries / capacity) must be kept low — CPython resizes at ~2/3 load to maintain O(1) average

---

## Complexity

| Operation | Average | Worst (all keys collide) |
|---|---|---|
| Lookup | O(1) | O(n) |
| Insert | O(1) amortized | O(n) |
| Delete | O(1) average | O(n) |
| Resize | O(n) | O(n) |

Space complexity: O(n) for chaining (extra linked-list nodes); O(n) for open addressing (extra empty slots).

---

## What It Is

Consider assigning student IDs to lockers in a school. If you give each student a locker number based on the last two digits of their student ID, any two students whose IDs end in the same two digits compete for the same locker. You cannot avoid this — with 100 lockers and 200 students, at least half of the lockers must share occupants, by the pigeonhole principle. But even with 200 lockers and 200 students, two students are likely to clash far sooner than you expect.

This is the birthday paradox: the probability that at least two people in a group of 23 share a birthday is about 50%. Similarly, with a hash table of 365 buckets, you only need 23 entries before there is a roughly even chance that two entries share a bucket. This is not a flaw in the hash function — it is a consequence of probability. Collisions are statistically certain as the table fills, and the resolution strategy is what prevents them from corrupting the data or destroying performance.

Two strategies dominate. Chaining stores a linked list (or dynamic array) at each bucket. When two keys collide, both entries are appended to the list at that bucket. Lookup traverses the list until it finds the matching key. Open addressing does not use auxiliary lists — instead, when a collision occurs, it searches for the next available slot in the table itself, following a probing sequence. Both strategies have O(1) average behaviour when the table is not too full, and both degrade to O(n) in the worst case.

---

## How It Actually Works

CPython's `dict` uses open addressing with a pseudo-random probing sequence rather than simple linear probing. Linear probing (trying index+1, index+2, ...) causes "primary clustering" — collisions create long runs of occupied slots, which make future collisions more likely in the same region. CPython's probe sequence is `index = (5 * index + 1 + perturb) % size` where `perturb` is derived from the original hash value and is right-shifted on each iteration. This spreads probes across the table more evenly.

Open addressing requires careful handling of deletion. If a slot is deleted and left truly empty, a lookup for a key that previously probed past that slot will incorrectly terminate early (hitting the empty slot) and report the key as absent. CPython uses "tombstone" slots — deleted entries are marked specially so probing continues through them, but new entries can reuse them. This tombstone accumulation is one reason hash tables occasionally need full rehashing even when not growing.

```python
# Demonstrating collision mechanics

# Same hash modulo small table size — artificial collision
table_size = 8
keys = ["a", "i", "q"]  # With PYTHONHASHSEED=0 these may collide

# Show hash values (PYTHONHASHSEED randomises these per process)
import os
print("Note: hash values change per process due to PYTHONHASHSEED")
for k in keys:
    print(f"  hash({k!r}) % {table_size} = {hash(k) % table_size}")

# Demonstrate hash randomisation
import subprocess
results = []
for _ in range(3):
    out = subprocess.run(
        ["python", "-c", "print(hash('hello'))"],
        capture_output=True, text=True
    )
    results.append(out.stdout.strip())
print("hash('hello') across 3 processes:", results)
# Will be different each time unless PYTHONHASHSEED=0 is set


# Chaining implementation
class ChainingHashTable:
    def __init__(self, capacity=8):
        self._capacity = capacity
        self._buckets = [[] for _ in range(capacity)]  # list of (key, value) pairs
        self._size = 0

    def _bucket_index(self, key):
        return hash(key) % self._capacity

    def put(self, key, value):
        idx = self._bucket_index(key)
        chain = self._buckets[idx]
        for i, (k, v) in enumerate(chain):
            if k == key:
                chain[i] = (key, value)    # update existing
                return
        chain.append((key, value))         # new entry
        self._size += 1
        if self._size / self._capacity > 0.75:
            self._resize()

    def get(self, key):
        idx = self._bucket_index(key)
        for k, v in self._buckets[idx]:
            if k == key:
                return v
        raise KeyError(key)

    def delete(self, key):
        idx = self._bucket_index(key)
        chain = self._buckets[idx]
        for i, (k, v) in enumerate(chain):
            if k == key:
                chain.pop(i)
                self._size -= 1
                return
        raise KeyError(key)

    def _resize(self):
        old_buckets = self._buckets
        self._capacity *= 2
        self._buckets = [[] for _ in range(self._capacity)]
        self._size = 0
        for chain in old_buckets:
            for key, value in chain:
                self.put(key, value)

    def chain_lengths(self):
        return [len(b) for b in self._buckets]


ht = ChainingHashTable(capacity=4)  # small capacity to force collisions
for i in range(12):
    ht.put(f"key{i}", i)
print("Chain lengths:", ht.chain_lengths())


# Open addressing with linear probing and tombstones
_EMPTY = object()
_DELETED = object()   # tombstone

class OpenAddressHashTable:
    def __init__(self, capacity=8):
        self._capacity = capacity
        self._slots = [_EMPTY] * capacity
        self._size = 0

    def _probe(self, key):
        """Yield slot indices in probe order."""
        index = hash(key) % self._capacity
        for _ in range(self._capacity):
            yield index
            index = (index + 1) % self._capacity   # linear probing for clarity

    def put(self, key, value):
        first_deleted = None
        for index in self._probe(key):
            slot = self._slots[index]
            if slot is _EMPTY:
                target = first_deleted if first_deleted is not None else index
                self._slots[target] = (key, value)
                self._size += 1
                return
            elif slot is _DELETED:
                if first_deleted is None:
                    first_deleted = index
            elif slot[0] == key:
                self._slots[index] = (key, value)  # update
                return
        raise RuntimeError("Hash table full")

    def get(self, key):
        for index in self._probe(key):
            slot = self._slots[index]
            if slot is _EMPTY:
                raise KeyError(key)
            elif slot is not _DELETED and slot[0] == key:
                return slot[1]
        raise KeyError(key)

    def delete(self, key):
        for index in self._probe(key):
            slot = self._slots[index]
            if slot is _EMPTY:
                raise KeyError(key)
            elif slot is not _DELETED and slot[0] == key:
                self._slots[index] = _DELETED   # tombstone, not truly empty
                self._size -= 1
                return
        raise KeyError(key)


oht = OpenAddressHashTable(capacity=8)
oht.put("x", 10)
oht.put("y", 20)
oht.delete("x")
oht.put("z", 30)
print(oht.get("y"))   # 20
print(oht.get("z"))   # 30
```

---

## Visualizer

<iframe src="/visualizers/hash-collisions.html" style="width:100%;height:400px;border:none;border-radius:8px;" title="Hash Collisions Visualizer"></iframe>

---

## How It Connects

Hash collisions are the internal complication that the hash table note abstracts away. Understanding the O(n) worst case, the tombstone deletion requirement, and the role of load factor requires understanding how collisions are resolved — this note is the detailed internals behind the O(1) averages claimed in the hash tables overview.

[[hash-tables|Hash Tables]]

CPython's dict uses a specific compact open-addressing design with a separate indices array. The collision resolution mechanism described here is the foundation for understanding how the CPython dict actually stores and retrieves keys at the memory level.

[[dict-internals|Dict Internals]]

---

## Common Misconceptions

Misconception 1: "A good hash function eliminates collisions."
Reality: No hash function eliminates collisions when the number of possible keys exceeds the number of buckets. With a 1000-bucket table and a billion possible string keys, collisions are guaranteed by the pigeonhole principle. A good hash function distributes entries uniformly — so no bucket has dramatically more entries than others — but it cannot prevent all collisions.

Misconception 2: "Hash DoS attacks are not a real concern for Python applications."
Reality: Before Python 3.3, an attacker who could send arbitrary strings to a server (as form field names, JSON keys, or HTTP headers) could craft strings with identical hashes, causing all of them to land in the same bucket and making every dict operation O(n). This brought servers to a halt in practice. Python 3.3 introduced PYTHONHASHSEED randomisation to counter this. The attack is real and was exploited.

Misconception 3: "Deleting an entry from an open-addressing table is O(1) and leaves the slot truly empty."
Reality: Deletion in an open-addressing table must leave a tombstone, not a true empty marker. If a true empty marker is placed, future lookups for keys that probed past the deleted slot will incorrectly terminate, reporting those keys as absent. The tombstone tells the probing sequence to continue. This is a correctness requirement, not an optimisation.

---

## Why It Matters in Practice

A hash table with all keys in one bucket is functionally a linked list — every operation requires scanning the full list. Any production system that allows external input to become hash table keys must either use hash randomisation (which Python does by default for strings) or validate that inputs cannot be crafted to collide. Custom `__hash__` implementations are a common source of accidentally poor hash functions that cause unexpected O(n) performance.

Understanding load factor management helps when sizing pre-allocated dictionaries. Python's `dict` starts small and resizes automatically, but in memory-constrained environments or when inserting large volumes of known-size data, pre-sizing with `dict.fromkeys(iterable)` or managing load factor deliberately can prevent costly resize operations.

---

## Interview Angle

Common question forms:
- "What is a hash collision and how does Python handle it?"
- "What is the worst-case complexity of a hash table lookup and when does it occur?"
- "What is a Hash DoS attack and how does Python mitigate it?"
- "Why can't you use a regular empty-slot marker for deletion in open addressing?"

Answer frame:
Define collision as two keys mapping to the same bucket index. Describe both chaining and open addressing, then specify that CPython uses open addressing with pseudo-random probing. For the worst case, say O(n) when all keys collide and describe the deliberate adversarial version (Hash DoS). For PYTHONHASHSEED, explain that it randomises the per-process hash seed for strings, making it computationally infeasible to craft colliding inputs without knowing the seed. For deletion, describe the tombstone requirement and why a true empty marker would break lookup correctness.

---

## Related Notes

- [[hash-tables|Hash Tables]]
- [[dict-internals|Dict Internals]]
- [[big-o-notation|Big O Notation]]
