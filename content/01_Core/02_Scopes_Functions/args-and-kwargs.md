---
title: 07 - *args and **kwargs
description: "`*args` collects extra positional arguments into a tuple and `**kwargs` collects extra keyword arguments into a dict  -  together they make functions that accept variable numbers of arguments; the `*` and `**` unpacking operators are the complement, spreading iterables and mappings into function calls."
tags: [args, kwargs, variadic-functions, unpacking, positional-only, keyword-only, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# *args and **kwargs

> `*args` collects extra positional arguments into a tuple and `**kwargs` collects extra keyword arguments into a dict  -  together they make functions that accept variable numbers of arguments; the `*` and `**` unpacking operators are the complement, spreading iterables and mappings into function calls.

---

## Quick Reference

**Core idea:**
- `def f(*args)`  -  `args` is a tuple of all extra positional arguments beyond the named parameters
- `def f(**kwargs)`  -  `kwargs` is a dict of all extra keyword arguments beyond the named parameters
- `f(*iterable)`  -  unpacks the iterable into positional arguments at the call site
- `f(**mapping)`  -  unpacks the mapping into keyword arguments at the call site
- `def f(a, b, /, c, *, d)`  -  `/` marks positional-only parameters; `*` marks keyword-only parameters (Python 3.8+)

**Tricky points:**
- `*args` is a tuple, not a list  -  it is immutable; reassigning `args = (1, 2)` inside the function creates a new local, it does not change the caller's values
- Named parameters before `*args` are positional-or-keyword; all parameters after `*args` are **keyword-only**  -  they must be passed by name
- `def f(*, name)` uses a bare `*` (no variable name) to force all following parameters to be keyword-only without collecting extra positionals
- Multiple `**dict` unpacking in a single call is allowed: `f(**d1, **d2)`  -  keys must not overlap
- `*args` and `**kwargs` can be forwarded: `wrapper(*args, **kwargs)` passes all arguments unchanged to another function

---

## What It Is

Think of a hotel check-in form with named fields (name, check-in date, room preference) and then an "other requests" text box at the bottom. The named fields handle the expected inputs. The "other requests" box captures anything extra the guest wants to say  -  the hotel doesn't know in advance what will be in it. `*args` is that "extra requests" box for positional arguments, and `**kwargs` is the version for named requests.

The `*` and `**` operators work in both directions: **collecting** (in function definitions) and **spreading** (in function calls). In a definition, `*args` collects extra positionals into a tuple. In a call, `*my_list` spreads a list into positional arguments. The same symbol does the reverse operation depending on context.

This symmetry is what makes argument forwarding so clean: a wrapper function can accept `(*args, **kwargs)` and pass `*args, **kwargs` to the inner function  -  all arguments are forwarded without the wrapper needing to know what they are.

---

## How It Actually Works

In CPython's calling convention, positional arguments are passed as a C array and keyword arguments as a dict (or a series of name-value pairs in newer CPython). The `*args` parameter is filled by taking the positionals that don't match named parameters and packing them into a tuple. The `**kwargs` parameter is filled by taking keyword arguments that don't match named parameters and packing them into a new dict.

The parameter ordering rule is enforced by the compiler: `(normal_params, *args, keyword_only_params, **kwargs)`. Violating this order is a `SyntaxError`.

For `*` unpacking at a call site, `f(*[1, 2, 3])` is compiled to bytecode that iterates the list and pushes each element as a positional argument. Multiple `*` unpackings (`f(*a, *b)`) are supported  -  CPython iterates each separately and concatenates.

Positional-only parameters (left of `/`) can only be passed by position. This means callers cannot use the parameter name to pass them, and the function can freely rename those parameters without breaking callers. Keyword-only parameters (right of `*` or `*args`) must be passed by name  -  they cannot be positional.

```python
def f(pos_only, /, normal, *, kw_only):
    ...

f(1, 2, kw_only=3)   # ok
f(pos_only=1, ...)   # TypeError: pos_only is positional-only
f(1, 2, 3)           # TypeError: kw_only must be keyword
```

---

## How It Connects

`functools.partial` fixes some arguments of a function, producing a new callable. It uses `*args` and `**kwargs` internally  -  `partial(f, 1)` stores `args=(1,)` and calls `f(1, *more_args, **kwargs)` when invoked.
[[partial-functions|Partial Functions]]

Decorator wrappers always use `(*args, **kwargs)` to forward arguments to the wrapped function unchanged. This is the standard pattern for transparent wrappers that should not affect the call signature.
[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "`*args` is a list."
Reality: `*args` is a `tuple`  -  immutable. You can iterate it, index it, and pass it onward with `*args`, but you cannot append to it. If you need to modify the arguments, convert with `list(args)` first.

Misconception 2: "`**kwargs` captures all keyword arguments."
Reality: `**kwargs` captures only keyword arguments that do **not** match any explicitly named parameter. If the function declares `def f(name, **kwargs)` and you call `f(name="Alice", age=30)`, then `kwargs` is `{"age": 30}`  -  `name` is matched to the `name` parameter, not included in `kwargs`.

---

## Why It Matters in Practice

Argument forwarding is the primary use case. Decorators universally use `def wrapper(*args, **kwargs): return func(*args, **kwargs)` to pass all arguments to the wrapped function without knowing the wrapped function's signature.

`print(*items)` is the canonical example of spreading: `print(*[1, 2, 3])` is equivalent to `print(1, 2, 3)`. `dict(**d1, **d2)` merges two dicts (Python 3.5+).

Keyword-only arguments are a design tool. `def connect(host, port, *, timeout)` forces callers to write `connect("localhost", 5432, timeout=5)`  -  the `timeout` cannot be passed positionally and is always explicit in call sites, making code more readable.

---

## Interview Angle

Common question forms:
- "What is the difference between `*args` and `**kwargs`?"
- "What are keyword-only arguments?"
- "How do you forward all arguments to another function?"

Answer frame: `*args` collects extra positional arguments into a tuple; `**kwargs` collects extra keyword arguments into a dict. The `*` and `**` operators are bidirectional  -  in definitions they collect; in calls they spread. A bare `*` in a definition forces all following parameters to be keyword-only. Argument forwarding: `def wrapper(*args, **kwargs): return fn(*args, **kwargs)` passes everything through unchanged. `*args` is a tuple (immutable); `**kwargs` only captures kwargs that don't match named parameters.

---

## Related Notes

- [[partial-functions|Partial Functions]]
- [[decorators|Decorators]]
- [[first-class-functions|First-Class Functions]]
- [[functools|functools]]
