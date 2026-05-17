---
title: Mutability vs Immutability
description: Mutability describes whether an object's value can be changed after it is created — a distinction that is not enforced by Python's type system but is built into the internal C structure of each object type, with real consequences for correctness, performance, and safety.
tags: [mutability, immutability, objects, memory, cpython, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Mutability vs Immutability

> Mutability describes whether an object's value can be changed after it is created — a distinction that is not enforced by Python's type system but is built into the internal C structure of each object type, with real consequences for correctness, performance, and safety.

---

## Quick Reference

**Core idea:**
- **Immutable** — internal state cannot change after creation: `int`, `float`, `str`, `bytes`, `bool`, `tuple`
- **Mutable** — internal state can change in place: `list`, `dict`, `set`, most class instances
- Immutability is not enforced by a flag — it is the absence of any C-level mutation functions in that type
- Immutable objects can be hashed and used as `dict` keys; mutable objects cannot
- Interned strings and small integers (-5 to 256) are cached singletons — `"x" is "x"` and `1 is 1` are `True` in CPython

**Tricky points:**
- `x = x + 1` creates a **new** integer object and rebinds `x` — `id(x)` changes; the original object is untouched
- A tuple is only hashable if **all its elements** are hashable — `(1, [2, 3])` raises `TypeError`
- Mutable default arguments (`def f(x=[])`) are created **once at definition time** — every call shares the same object
- `is` checks identity (same object in memory); `==` checks value — they can agree for small integers purely due to CPython's cache, not semantics
- `list.copy()` is a **shallow** copy — the new list is independent, but its elements still point to the same objects as the original

---

## What It Is

Think about two kinds of delivery boxes. The first kind is sealed when it leaves the warehouse: whatever is inside stays inside, and the outside label is permanent. You can read the label, copy the contents to a new box, but you cannot open it and change what is inside. The second kind is an open crate: you can add items, remove items, or replace items at any time. The sealed box is immutable; the open crate is mutable. Python objects work the same way — some are sealed after creation, others are open crates you can modify freely.

In Python, immutable objects are those whose internal state cannot change after they are created. The most common immutable types are integers, floats, strings, bytes, booleans, and tuples. You cannot change the character at position 2 in a string without creating a new string. You cannot change the value of an integer object in place. When you write `x = x + 1`, you are not modifying the integer object `x` pointed to — you are creating a new integer object with the new value and rebinding the name `x` to point to it. The original integer object is unchanged; its reference count just dropped by one.

Mutable objects are those whose internal state can be changed in place. The most common mutable types are lists, dictionaries, sets, and instances of most user-defined classes. When you append an item to a list, the list object itself is modified — its internal array of pointers grows to accommodate the new item. The list object at the same memory address, with the same identity (`id()`), still exists, but it now contains more items. Any other name or container that holds a reference to that list will see the change, because they all point to the same object.

---

## How It Actually Works

Immutability in CPython is not enforced by a flag or a lock. It is a consequence of a type not providing any C-level operations that modify its internal data. The `PyObject` struct for an integer (`PyLongObject`) stores its value in an array of "digits" that is set once at allocation and never written to again. There are no C functions in CPython that modify an existing `PyLongObject`'s digits in place. The type's slot table simply does not register any in-place modification methods. The object is immutable because no code exists to mutate it, not because CPython actively prevents mutation.

For strings, CPython goes further: because strings are immutable and hashable, they can be interned — a process where CPython stores a single canonical copy of a string and reuses it across all identical string literals in the program. Short strings that look like valid Python identifiers are automatically interned at compile time. This means that `"hello" is "hello"` is reliably `True` in CPython — both literals resolve to the same interned object. This optimization is only safe because strings are immutable: if two names point to the same string, neither can change it in a way the other would observe.

For tuples, immutability has a performance consequence: because a tuple's contents cannot change, CPython can hash a tuple if all its elements are hashable. This makes tuples usable as dictionary keys and set members, while lists are not. The hashability of a type is directly tied to its immutability — CPython's design guarantees that if an object is hashable, its hash value must not change over its lifetime. Mutable objects like lists cannot be hashed because their contents (and therefore their logical equality) can change, which would invalidate any hash-based lookup they had been stored under.

Mutability also interacts with the `==` operator and the `is` operator in a way that trips up many developers. `is` compares identity — are these the same object in memory? `==` compares value — are these equal? For mutable objects, two objects can be `==` without being `is`. For small immutable objects like integers and interned strings, CPython's caching means `is` and `==` may both return `True` not because of the semantics, but because CPython happens to reuse the same object.

---

## How It Connects

Mutability and memory are inseparable. Immutable objects can be safely shared — multiple references to the same immutable object can never conflict. Mutable objects must be handled carefully when shared, because one reference changing the object changes what every other reference sees. How CPython allocates and manages these objects in memory is the structural foundation beneath this distinction.
[[python-memory-model|Python's Memory Model]]

The fact that every Python value is a heap-allocated object with an identity is what makes the mutability distinction visible and meaningful. If Python stored integers as raw values (as C does), the question of mutability would not arise in the same way. Because integers are objects with an identity, you can ask whether two names point to the same integer object or to different ones with equal values.
[[everything-is-an-object|Everything is an Object]]

---

## Common Misconceptions

Misconception 1: "Tuples are immutable, so they're always safe to use as dictionary keys."
Reality: A tuple is only hashable if all of its elements are hashable. A tuple containing a list is not hashable and cannot be used as a dictionary key, because the list inside could change — and a hash value that changes after storage would corrupt any hash-based data structure. `(1, 2, 3)` is a valid dict key; `(1, [2, 3])` is not. Immutability of the container does not guarantee hashability if the contents are mutable.

Misconception 2: "Assigning a new value to a variable changes the object in place."
Reality: In Python, assignment rebinds a name to a different object. `x = x + 1` does not modify the integer object `x` was pointing to. It creates a new integer object and binds the name `x` to it. The original object still exists (until its reference count drops to zero). This is visible with `id()`: `id(x)` before and after `x = x + 1` will show different values. For truly in-place modification, you need a mutable object and an in-place operation like `x.append(1)` or `x += [1]` on a list.

---

## Why It Matters in Practice

Mutability is the source of a large category of Python bugs. The most common is the mutable default argument: defining `def f(x=[]):` means all calls to `f` that do not pass an argument share the same list object. The first call that appends to `x` permanently changes the default for all future calls. This surprises almost every Python developer the first time they encounter it, and it is a direct consequence of the fact that the default value is a mutable object that persists between calls.

Mutability also determines where your code can run into aliasing problems. Passing a list to a function and having the function modify it affects the caller's list — there is only one list object, and both the caller and the function hold a reference to it. This is not a flaw; it is the designed behavior. But it means you need to think about whether you want to share state or copy it. `list.copy()` or `list[:]` gives you a shallow copy — a new list object whose elements are still the same objects. `copy.deepcopy()` gives you a completely independent copy. Which one you need depends entirely on whether the elements themselves are mutable.

---

## Interview Angle

Common question forms:
- "What is the difference between mutable and immutable objects in Python?"
- "Why can't you use a list as a dictionary key?"
- "What is the mutable default argument gotcha?"

Answer frame: Define mutability as whether the object's internal state can change in place. Give mutable examples (list, dict, set) and immutable examples (int, str, tuple). Explain that immutable objects are safe to hash (and therefore usable as dict keys) because their value never changes. Walk through the mutable default argument: the default object is created once at function definition time and shared across all calls. Connect to the identity model — assignment rebinds names, it does not copy objects.

---

## Related Notes

- [[python-memory-model|Python's Memory Model]]
- [[everything-is-an-object|Everything is an Object]]
