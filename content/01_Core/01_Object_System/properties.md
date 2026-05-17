---
title: 06 - Properties
description: "The `property` built-in is a descriptor that wraps getter, setter, and deleter functions behind a clean attribute interface — it enables computed and validated attributes without changing the calling syntax from simple attribute access."
tags: [property, getter, setter, descriptor, attribute-access, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Properties

> The `property` built-in is a descriptor that wraps getter, setter, and deleter functions behind a clean attribute interface — it enables computed and validated attributes without changing the calling syntax from simple attribute access.

---

## Quick Reference

**Core idea:**
- `@property` turns a method into a read-only attribute — `obj.method` (no parentheses) calls the getter function
- `@name.setter` defines the setter — `obj.name = value` calls the setter function
- `@name.deleter` defines the deleter — `del obj.name` calls the deleter function
- `property(fget, fset, fdel, doc)` is the constructor form — equivalent to the decorator syntax
- `property` is a **data descriptor** — it takes priority over instance `__dict__`, so the getter/setter always intercept access even if an instance attribute with the same name exists

**Tricky points:**
- `@property` methods should use `self._name` (with underscore) to store the backing value — using `self.name` inside the setter causes infinite recursion (`self.name = value` calls the setter again)
- Without a setter, assigning to the property raises `AttributeError: can't set attribute` — a common mistake is forgetting `@name.setter`
- The property docstring comes from the getter function's docstring — set it explicitly in `property(fget, fset, fdel, doc=...)` if needed
- **Properties are not inherited lazily** — if a subclass overrides only the setter using `@parent_class.attr.setter`, it must also inherit the parent's getter via the exact same property object
- `property` in `__slots__` classes works normally — slots provide storage; properties provide access control

---

## What It Is

Think of a smart thermostat display. The temperature shown is not a raw sensor reading — it is a computed, formatted value: the sensor data is converted from Celsius to Fahrenheit, rounded, and formatted as a string. When you set the target temperature on the display, the thermostat validates the input (rejecting values outside safe range) and stores the underlying value. From the user's perspective, they are just reading and writing a temperature display — they do not need to know about the sensor, conversion, or validation happening behind it. Python's `property` provides exactly this abstraction: a clean attribute interface that hides computation and validation behind simple read/write syntax.

Without properties, Python code would face a choice: expose attributes directly (simple, but validation requires callers to use a method), or require callers to use `obj.get_name()` and `obj.set_name(value)` (verbose, different from attribute access, not Pythonic). Properties bridge this gap. You start with a simple attribute (`self.name = value`). When you later need to add validation, you convert it to a property — the caller's code does not change. `obj.name = value` still works; the setter function now validates the value before storing it.

This design aligns with the Uniform Access Principle: from the caller's perspective, there should be no syntactic difference between accessing a stored value and accessing a computed value. Properties ensure that an attribute access (`obj.temperature`) can be transparently changed from a direct dict lookup to a computed function call without modifying any caller.

---

## How It Actually Works

`property` is a built-in type, implemented as a C descriptor in CPython. It stores four attributes: `fget` (the getter function), `fset` (the setter function), `fdel` (the deleter function), and `__doc__` (the docstring, taken from `fget.__doc__` if not explicitly provided).

`property.__get__(self, obj, objtype)`: if `obj` is `None` (class-level access), returns the `property` object itself. Otherwise, calls `self.fget(obj)` and returns the result.

`property.__set__(self, obj, value)`: if `self.fset` is `None`, raises `AttributeError("can't set attribute")`. Otherwise, calls `self.fset(obj, value)`.

`property.__delete__(self, obj)`: similarly calls `self.fdel(obj)` or raises `AttributeError`.

The decorator syntax desugars as follows:

```python
class MyClass:
    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._name = value.strip()
```

Is equivalent to:

```python
class MyClass:
    def _get_name(self):
        return self._name

    def _set_name(self, value):
        self._name = value.strip()

    name = property(_get_name, _set_name)
```

`@name.setter` calls `property.setter(func)`, which returns a new `property` object with the same `fget` and `fdel` but the new `fset`. This new property replaces the old `name` attribute in the class namespace.

---

## How It Connects

`property` is implemented as a descriptor. The descriptor protocol — `__get__`, `__set__`, `__delete__` — is what makes `property` intercept attribute access transparently. Understanding descriptors explains why `property` works and why data descriptors take priority over instance `__dict__`.
[[descriptors|Descriptors]]

The typical `@property` implementation stores the backing value in a private instance attribute (`self._name`). This interacts with `__slots__` — if `__slots__` is defined, the private attribute must be included in the slots or a `__dict__` slot must be present.
[[slots|__slots__]]

---

## Common Misconceptions

Misconception 1: "Using `@property` makes attribute access slower."
Reality: Property access does add one function call compared to direct `__dict__` lookup. For hot inner loops, this can be measurable. But in the vast majority of Python code, attribute access is not the bottleneck, and the clarity benefit of a clean attribute interface outweighs the marginal overhead. Profile before optimizing.

Misconception 2: "Subclasses can add a setter to a parent's `@property` by just defining `@Parent.attr.setter`."
Reality: `@Parent.attr.setter` creates a new `property` object in the subclass's namespace. The subclass has both its own `attr` property (with getter from parent and new setter) and the parent's `attr` property (getter only). The subclass's `attr` property shadows the parent's. But if a class has only `@parent.attr.setter` in its body and no explicit getter, it may have an incomplete property. The correct pattern: `@property` for the getter in the parent, `@ParentClass.attr.setter` in the subclass creates a new complete property that the subclass owns.

---

## Why It Matters in Practice

Validation in properties is one of the most common real-world uses. A `User` class with a `password` property can hash the password in the setter and return a redacted value in the getter — the caller uses `user.password = "secret"` and `print(user.password)` with no awareness of the hashing:

```python
@password.setter
def password(self, value):
    self._hashed_password = bcrypt.hash(value)
```

Computed properties are equally common: `@property def full_name(self): return f"{self.first_name} {self.last_name}"`. The caller accesses `user.full_name` as if it were a stored attribute; the computation is transparent.

The "start as attribute, convert to property later" workflow is the practical reason `property` exists. An initial implementation stores `self.price = value` directly. When business logic requires that price be non-negative, you convert to a property with a validating setter — zero caller changes required.

---

## Interview Angle

Common question forms:
- "What is `@property` and when would you use it?"
- "How do you add validation to a Python attribute?"
- "What is the difference between `@property` and a regular method?"

Answer frame: `property` is a descriptor that makes a method callable as an attribute. The getter runs on read access; the setter runs on assignment; the deleter runs on `del`. Use it for: computed attributes, validation on assignment, and backward-compatible API evolution (start with a plain attribute, convert to property without changing callers). Common mistake: storing the backing value as `self.name` (same name as the property) causes infinite recursion — use `self._name`.

---

## Related Notes

- [[descriptors|Descriptors]]
- [[slots|__slots__]]
- [[dunder-methods|Dunder Methods]]
- [[python-data-model|The Python Data Model]]
