---
title: 05 - First-Class Functions
description: In Python, functions are objects  -  they can be assigned to variables, passed as arguments, returned from other functions, and stored in data structures; this is what "first-class" means and it is the foundation for decorators, callbacks, and higher-order functions.
tags: [first-class-functions, functions-as-objects, callable, higher-order, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# First-Class Functions

> In Python, functions are objects  -  they can be assigned to variables, passed as arguments, returned from other functions, and stored in data structures; this is what "first-class" means and it is the foundation for decorators, callbacks, and higher-order functions.

---

## Quick Reference

**Core idea:**
- A **first-class value** is one that can be: assigned to a variable, passed as an argument, returned from a function, stored in a data structure
- Python functions satisfy all four criteria  -  they are full objects, instances of the `function` type
- `def f(): ...` creates a function object and binds the name `f` to it  -  the name and the object are separate; `g = f` makes two names point to one function object
- Functions have attributes: `f.__name__`, `f.__doc__`, `f.__annotations__`, `f.__code__`, `f.__globals__`, `f.__defaults__`
- `callable(obj)` returns `True` if `obj` has a `__call__` method  -  functions, methods, classes, and any object with `__call__` are callable

**Tricky points:**
- `lambda x: x + 1` creates an anonymous function object  -  it is identical to `def f(x): return x + 1` except it has no name and is limited to a single expression
- Assigning `f = None` does not destroy the function object if other names still reference it  -  Python's reference counting keeps the object alive
- Functions defined inside other functions are objects too  -  they can be returned and outlive their enclosing scope (forming closures)
- Methods are also function objects  -  `obj.method` is a bound method wrapping the underlying function; `type(obj).method` gives the raw function

---

## What It Is

Think of the difference between a citizen in a society with full rights versus a second-class member with limited rights. A first-class citizen can own property, enter contracts, and participate fully in civic life. A second-class member may exist in the society but cannot do all the same things. In programming, "first-class" means a value has the same rights as any other value  -  it can be stored, passed around, and returned, just like integers and strings. In many older languages, functions were second-class: you could call them, but you could not pass them as arguments or return them. Python gives functions full citizenship.

The practical consequence is that any place you can use an integer or string, you can use a function. A dictionary can map strings to functions: `{"add": operator.add, "sub": operator.sub}`. A list can hold functions: `[str.upper, str.lower, str.strip]`. A function can receive another function as an argument and call it  -  this is the entire foundation of the callback pattern, event handlers, and decorators.

---

## How It Actually Works

`def f(x): return x + 1` compiles to bytecode that, when executed, creates a `function` object and stores it in the local namespace under the name `f`. The function object holds a reference to the code object (`f.__code__`), the global namespace the function was defined in (`f.__globals__`), and any default argument values (`f.__defaults__`).

The `function` type is defined in CPython as `PyFunctionObject`. It is a regular heap object with a refcount, like any other Python object. `id(f)` gives its memory address. `type(f)` is `<class 'function'>`. `isinstance(f, object)` is `True`.

Calling `f(arg)` triggers `f.__call__(arg)`. Functions have a `__call__` method, which is why `callable(f)` returns `True`. Any object with `__call__` can be used where a function is expected.

The `def` statement is syntactic sugar for creating a function object and binding a name. These are equivalent:

```python
def add(x, y):
    return x + y

add = (lambda x, y: x + y)  # same behavior, different name/repr
```

---

## How It Connects

First-class functions enable decorators  -  a decorator is a function that receives a function, wraps it, and returns the wrapper. The wrapper is a function too, so it can be stored and called like the original. The entire decorator pattern is an application of functions being first-class values.
[[decorators|Decorators]]

Closures are functions that capture variables from their enclosing scope. A closure is only possible because functions are objects that can outlive the scope in which they were created  -  they hold a reference to the enclosing scope's variables via the `__closure__` attribute.
[[closures|Closures]]

---

## Common Misconceptions

Misconception 1: "A function and its name are the same thing."
Reality: `def f(): ...` creates a function object and binds the name `f` to it. `g = f` creates a second name for the same object. `del f` removes the name `f` but does not destroy the function  -  `g` still references it. The object and its bindings are independent.

Misconception 2: "`lambda` creates a different kind of object than `def`."
Reality: Both `def` and `lambda` create the same `function` type object. The differences are purely syntactic: `lambda` is an expression (can appear inline), is limited to a single expression body, and produces a function with `__name__ = '<lambda>'`. The underlying object type, calling convention, and capabilities are identical.

---

## Why It Matters in Practice

Sorting with a key function is the most immediate example: `sorted(people, key=lambda p: p.age)` passes a function as the `key` argument. The `sorted` built-in calls `key(item)` for each item  -  it does not care that `key` is a lambda or a named function. Any callable works.

Event-driven frameworks (GUI toolkits, web frameworks) are built entirely on first-class functions. `button.on_click(my_handler)` stores the `my_handler` function and calls it later when the button is clicked. The handler is just an object that happens to be callable.

`functools.lru_cache(fn)` receives a function and returns a new function with caching. This pattern  -  receive a function, return a function  -  is only possible because functions are first-class objects.

---

## Interview Angle

Common question forms:
- "What does 'first-class functions' mean in Python?"
- "How are functions objects in Python?"

Answer frame: "First-class" means a function can be assigned to a variable, passed as an argument, returned from a function, and stored in data structures  -  the same operations available to integers and strings. In CPython, a function is a `PyFunctionObject` heap object with a `__call__` method. `def` creates the object and binds a name to it; the name and object are independent. This is the foundation for decorators (functions that receive and return functions) and callbacks.

---

## Related Notes

- [[decorators|Decorators]]
- [[closures|Closures]]
- [[higher-order-functions|Higher-Order Functions]]
- [[lambda|Lambda Functions]]
