---
title: 10 - Descriptors
description: "A descriptor is any object that defines `__get__`, `__set__`, or `__delete__`  -  these methods intercept attribute access on a class, enabling properties, classmethods, staticmethods, and ORMs to implement controlled attribute access without modifying user code."
tags: [descriptors, __get__, __set__, __delete__, property, attribute-access, layer-1, core]
status: draft
difficulty: advanced
layer: 1
domain: core
created: 2026-05-17
---

# Descriptors

> A descriptor is any object that defines `__get__`, `__set__`, or `__delete__`  -  these methods intercept attribute access on a class, enabling properties, classmethods, staticmethods, and ORMs to implement controlled attribute access without modifying user code.

---

## Quick Reference

**Core idea:**
- A **descriptor** is an object stored as a class attribute that defines `__get__(self, obj, objtype)`, `__set__(self, obj, value)`, or `__delete__(self, obj)`
- **Data descriptor**: defines `__set__` (and/or `__delete__`)  -  takes priority over the instance's `__dict__`
- **Non-data descriptor**: defines only `__get__`  -  instance `__dict__` entries shadow it
- `property`, `classmethod`, `staticmethod`, `functools.cached_property` are all implemented as descriptors in CPython
- `obj.attr` triggers: look up `attr` in `type(obj).__mro__`, if found and it's a data descriptor call its `__get__`, else check `obj.__dict__`, else call non-data descriptor `__get__`

**Tricky points:**
- Descriptors only activate when stored as **class attributes**, not instance attributes  -  `self.x = SomeDescriptor()` inside `__init__` stores the descriptor as an instance attribute; it will not activate
- `__set_name__(self, owner, name)` is called when the descriptor is assigned in a class body  -  use it to store the attribute name without requiring it as a constructor argument
- Function objects are non-data descriptors  -  `function.__get__(instance, owner)` is what makes `obj.method(args)` work as `ClassName.method(obj, args)`
- The descriptor protocol is what allows `classmethod` and `staticmethod` to transform a function call  -  their `__get__` returns bound methods or plain functions respectively
- `__get__` receives `obj=None` when accessed on the class directly (e.g., `MyClass.attr`) rather than on an instance

---

## What It Is

Think of a hotel concierge desk. Rather than placing all items directly in guest rooms, the hotel routes certain requests through the concierge. When a guest asks for "room service" (accesses an attribute), the concierge (the descriptor's `__get__`) intercepts the request and provides the service  -  possibly after verification, logging, or transformation. The guest's room (the instance) doesn't need to store "room service" as a physical item; the concierge handles the request dynamically each time. When the guest tries to leave a note (assigns to the attribute), the concierge intercepts that too (`__set__`) and may store it elsewhere, validate it, or transform it.

Descriptors are the mechanism beneath several of Python's most fundamental features. Every Python method call uses the descriptor protocol: functions are non-data descriptors. When you access `obj.method`, Python finds `method` in the class, sees it is a function (which is a descriptor), and calls `function.__get__(obj, type(obj))`, which returns a bound method object that wraps both the function and `obj`. Calling that bound method calls `function(obj, ...)`. This is how `self` is provided without the caller explicitly passing it.

`property` is a data descriptor that provides the getter/setter pattern. `@property` on a method creates a `property` object stored as a class attribute. When you read `obj.name`, Python finds the `property` descriptor in the class, calls `property.__get__(obj, type(obj))`, which calls the getter function. When you write `obj.name = value`, Python finds the `property` descriptor, calls `property.__set__(obj, value)`, which calls the setter. The instance's `__dict__` is never consulted for data descriptor attributes  -  the descriptor always wins.

---

## How It Actually Works

The attribute lookup protocol in `object.__getattribute__` follows these steps for `obj.attr`:

1. Look up `attr` in `type(obj).__mro__` (search each class in the MRO). Call the found object `meta_attr`.
2. If `meta_attr` is a **data descriptor** (has `__set__` or `__delete__`), call `meta_attr.__get__(obj, type(obj))` and return.
3. Look in `obj.__dict__` for `attr`. If found, return it.
4. If `meta_attr` is a **non-data descriptor** (has `__get__` but no `__set__`), call `meta_attr.__get__(obj, type(obj))` and return.
5. Return `meta_attr` directly (plain class attribute, no descriptor protocol).
6. If not found anywhere, `AttributeError`.

This priority order explains why data descriptors shadow instance attributes (step 2 before step 3) but non-data descriptors do not (step 3 before step 4). A `property` with a setter is a data descriptor  -  setting `obj.name = val` calls the setter even if `obj.__dict__` has `name`. A function is a non-data descriptor  -  if you do `obj.method = lambda: 42`, the instance attribute shadows the class's function.

A minimal descriptor:

```python
class Validator:
    def __set_name__(self, owner, name):
        self.name = name

    def __get__(self, obj, objtype=None):
        if obj is None:
            return self
        return obj.__dict__.get(self.name)

    def __set__(self, obj, value):
        if not isinstance(value, int):
            raise TypeError(f"{self.name} must be int")
        obj.__dict__[self.name] = value

class MyClass:
    count = Validator()  # __set_name__ called here with name="count"
```

`MyClass().count = "hello"` raises `TypeError`. `MyClass().count = 5` stores 5 in the instance dict.

---

## How It Connects

`property`, `classmethod`, and `staticmethod` are all built-in descriptors. Understanding the descriptor protocol explains exactly what these built-ins do  -  they are not special syntax but regular Python objects that implement `__get__`, `__set__`, and `__delete__`.
[[properties|Properties]]

`__set_name__` is called during class creation when a descriptor is assigned in the class body. This is how descriptors can know their own attribute name without requiring it as a constructor argument  -  it connects descriptors to the class creation sequence.
[[class-creation|How Classes Are Created]]

---

## Common Misconceptions

Misconception 1: "Descriptors are a niche feature for framework developers."
Reality: Every Python method call uses the descriptor protocol  -  functions are non-data descriptors. Every `@property` use is a descriptor. `classmethod` and `staticmethod` are descriptors. SQLAlchemy's column definitions are descriptors. Descriptors are not niche; they are the foundation of Python's attribute access system. Understanding them explains behaviors that otherwise appear magical.

Misconception 2: "Instance attributes always shadow class attributes."
Reality: This is only true for non-data descriptors and plain class attributes. Data descriptors (those with `__set__`) take priority over instance attributes. Setting `obj.attr = val` when `attr` is a data descriptor on the class calls `descriptor.__set__(obj, val)`  -  it does not store `val` in `obj.__dict__`. This is why `@property` setters intercept assignment even when the instance has no prior value for that attribute.

---

## Why It Matters in Practice

SQLAlchemy column definitions are the most widely encountered real-world descriptors. `name = Column(String(100))` creates a `Column` descriptor stored as a class attribute on the model. Accessing `instance.name` calls `Column.__get__`, which returns the column's value from the unit of work session. Assigning `instance.name = "Alice"` calls `Column.__set__`, which marks the change as pending in the session. This entire ORM tracking mechanism is built on the descriptor protocol.

`functools.cached_property` is a non-data descriptor that computes a value once and stores it in the instance `__dict__`. On first access, `__get__` computes the value, stores it in `obj.__dict__[name]`, and returns it. On subsequent accesses, the instance `__dict__` entry shadows the `cached_property` descriptor (because it is a non-data descriptor  -  step 3 before step 4 in the lookup protocol), so the stored value is returned directly without calling `__get__` again.

---

## Common Pitfalls

- Forgetting `__set_name__`: without it, a descriptor needs the attribute name passed manually (`x = Validator(name="x")`), which is easy to get wrong on rename since the string and the attribute name can silently drift apart.
- Storing descriptor state on `self` (the descriptor instance) instead of `obj.__dict__` - since one descriptor instance is shared by the class, every instance of the owning class ends up sharing the same value.
- Assigning a descriptor as an instance attribute (`self.x = Validator()` inside `__init__`) instead of a class attribute - descriptors only activate when looked up via the class's MRO, so this silently does nothing.
- Omitting the `obj is None` check in `__get__` - accessing the descriptor via the class itself (`MyClass.attr`) then misbehaves instead of returning the descriptor object.
- Assuming `__get__` always runs: a non-data descriptor is shadowed by an instance `__dict__` entry of the same name, so `__get__` can be silently skipped after a direct assignment.

---

## Interview Angle

Common question forms:
- "What is a descriptor in Python?"
- "How does `@property` work internally?"
- "Why does `obj.method(args)` automatically provide `self`?"

Answer frame: A descriptor is a class attribute that implements `__get__`, `__set__`, or `__delete__`. Data descriptors (with `__set__`) take priority over instance `__dict__`; non-data descriptors (only `__get__`) are shadowed by instance attributes. Functions are non-data descriptors  -  `function.__get__(obj, type)` returns a bound method, which is how `self` is automatically provided. `property` is a data descriptor  -  its `__get__`/`__set__` intercept reads and writes. `__set_name__` allows descriptors to know their own attribute name from the class they are assigned to.

**Sample Q&A:**

Q: "Why does `obj.method(args)` not need to pass `self` explicitly?"
A: Methods are plain functions stored as class attributes, and function objects are non-data descriptors via `__get__`. When you access `obj.method`, attribute lookup finds `method` on the class and calls `function.__get__(obj, type(obj))`, which returns a *bound method* that has already captured `obj`. Calling that bound method with `(args)` is equivalent to `ClassName.method(obj, args)` - that's where `self` comes from. `staticmethod` and `classmethod` wrap the same mechanism: `staticmethod.__get__` returns the plain function unbound, and `classmethod.__get__` binds to the class instead of the instance.

Q: "What's the difference between writing a custom `__get__`/`__set__` descriptor and just using `@property`?"
A: `@property` *is* a data descriptor - it's the standard library's ready-made implementation of the protocol for a single attribute on a single class. A custom descriptor class earns its keep when the same validation or transformation logic needs to apply to many attributes or many classes (e.g. a `PositiveInt` descriptor reused for `age`, `price`, and `quantity`): write `__get__`/`__set__` once, instantiate the descriptor per attribute, and let `__set_name__` tell each instance which attribute it owns. `@property` would require duplicating the getter/setter for every attribute.

Q: "Given `class A: x = SomeNonDataDescriptor()`, then `a = A(); a.x = 5; print(a.x)` - what prints, and why?"
A: `5` - not whatever the descriptor's `__get__` would normally compute. `SomeNonDataDescriptor` only implements `__get__`, so it's a non-data descriptor with no `__set__`. The assignment `a.x = 5` simply stores `5` in `a.__dict__['x']`. On the next lookup, step 3 of `object.__getattribute__` (check `obj.__dict__`) finds `'x': 5` *before* step 4 would call the descriptor's `__get__`, so the instance dict wins.

---

## Practice Prompts

- Implement a `TypedAttribute(type_)` descriptor that enforces a type on assignment, using `__set_name__` so the attribute name never has to be passed manually. Reuse it for two different attributes on the same class.
- Predict the output of assigning `obj.method = lambda: 42` on an instance whose class defines `method`, then verify it - explain which descriptor priority rule from "How It Actually Works" applies.
- Write a `LazyProperty` non-data descriptor that computes a value once and caches it in `obj.__dict__`. Explain why the second access never calls `__get__` again, then compare your implementation to `functools.cached_property`.

---

## Related Notes

- [[properties|Properties]]
- [[class-creation|How Classes Are Created]]
- [[python-data-model|The Python Data Model]]
- [[dunder-methods|Dunder Methods]]
