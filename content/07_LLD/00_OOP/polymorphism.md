---
title: 05 - Polymorphism
description: Polymorphism lets different objects respond to the same method call in their own way, so code that calls the method works correctly regardless of the specific type it receives.
tags: [oop, polymorphism, duck-typing, method-overriding, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# Polymorphism

> Polymorphism means different types respond to the same operation in their own way, letting you write code that works with any type that supports the expected interface.

---

## Quick Reference

**Core idea:**
- Polymorphism means "many forms" - the same method name produces different behavior depending on the object that receives the call
- **Duck typing** is Python's primary polymorphism mechanism: if an object has the method you call, it works - no inheritance or interface declaration required
- **Method overriding** is inheritance-based polymorphism: a subclass provides its own version of a method defined in the parent
- **Operator overloading** is polymorphism through dunder methods: `+` calls `__add__`, `len()` calls `__len__`, `str()` calls `__str__`
- Python does **not** support method overloading (multiple methods with the same name but different parameter types) the way Java or C++ do - use default arguments, `*args`, or `@singledispatch` instead

**Tricky points:**
- Duck typing means type errors surface at runtime, not at compile time - you only discover a missing method when the code path is actually executed
- Method overriding without calling `super()` silently replaces the parent's behavior entirely - the parent's logic is never executed
- `@functools.singledispatch` provides function-level dispatch based on the first argument's type, which is the closest Python gets to method overloading
- Operator overloading can make code elegant (`vector_a + vector_b`) or confusing (`config + "key"`) - use it only when the operator's meaning is intuitive for the type

---

## What It Is

Think of a universal TV remote control. The remote has a "power" button. When you point it at a Samsung TV, the power button sends a Samsung-specific infrared signal. When you point it at an LG TV, the same button sends an LG-specific signal. The person pressing the button does not care which TV is receiving the signal - they press "power" and the TV turns on. The remote interacts with a uniform interface ("power"), and each TV implements that interface in its own way. This is polymorphism: one interface, multiple implementations.

In programming, polymorphism means you write code that calls a method, and the actual behavior depends on the object receiving the call. A function that calls `shape.area()` works with circles, rectangles, and triangles without knowing which one it has. Each shape class defines its own `area()` method with the correct formula. The calling code does not contain any `if isinstance(shape, Circle)` checks - it trusts that whatever object it received knows how to calculate its own area.

Python achieves polymorphism primarily through duck typing. The language does not require objects to declare which interfaces they implement. If your function calls `obj.read()`, any object with a `read()` method works - files, network sockets, `io.StringIO` buffers, custom classes. There is no `Readable` interface that these classes must explicitly inherit from. The name comes from the saying: "If it walks like a duck and quacks like a duck, then it is a duck." Python checks capabilities, not pedigree.

Inheritance-based polymorphism is the second mechanism. When a parent class defines a method and multiple child classes override it, calling the method on a parent-typed variable dispatches to the correct child implementation. This is what happens when you define a `Serializer` base class and have `JSONSerializer`, `XMLSerializer`, and `CSVSerializer` subclasses - each overrides the `serialize()` method, and the calling code works with any of them interchangeably.

---

## How It Actually Works

Python's polymorphism is powered by dynamic dispatch. When you call `obj.method()`, CPython does not look up the method at compile time - it looks it up at runtime using the instance's type and the MRO. The bytecode instruction `LOAD_ATTR` finds the method, and `CALL_FUNCTION` invokes it. Because the lookup happens at runtime, the same variable can hold different types at different times, and the correct method is always called based on the actual type of the object at that moment.

Operator overloading works through dunder methods that CPython's eval loop calls when it encounters specific operations. When the bytecode for `a + b` executes, CPython calls `a.__add__(b)`. If that returns `NotImplemented`, Python tries `b.__radd__(a)` as a fallback. This two-step protocol lets custom types interoperate with built-in types: your `Vector.__radd__` can handle `5 + Vector(1, 2)` even though `int.__add__` does not know about vectors.

```python
from abc import ABC, abstractmethod
from functools import singledispatch
import math


# 1. Inheritance-based polymorphism (method overriding)
class Shape(ABC):
    @abstractmethod
    def area(self) -> float: ...

    @abstractmethod
    def perimeter(self) -> float: ...


class Circle(Shape):
    def __init__(self, radius: float):
        self.radius = radius

    def area(self) -> float:
        return math.pi * self.radius ** 2

    def perimeter(self) -> float:
        return 2 * math.pi * self.radius


class Rectangle(Shape):
    def __init__(self, width: float, height: float):
        self.width = width
        self.height = height

    def area(self) -> float:
        return self.width * self.height

    def perimeter(self) -> float:
        return 2 * (self.width + self.height)


# Polymorphic function - works with any Shape
def print_shape_info(shape: Shape) -> None:
    # No isinstance checks - relies on polymorphism
    print(f"{shape.__class__.__name__}: area={shape.area():.2f}, "
          f"perimeter={shape.perimeter():.2f}")

print_shape_info(Circle(5))        # Circle: area=78.54, perimeter=31.42
print_shape_info(Rectangle(4, 6))  # Rectangle: area=24.00, perimeter=20.00


# 2. Duck typing polymorphism (no inheritance needed)
class DatabaseLogger:
    def write(self, message: str) -> None:
        print(f"[DB] {message}")

    def flush(self) -> None:
        pass  # no-op for database

class FileLogger:
    def __init__(self, path: str):
        self._file = open(path, "a")

    def write(self, message: str) -> None:
        self._file.write(message + "\n")

    def flush(self) -> None:
        self._file.flush()

def log_event(logger, event: str) -> None:
    """Works with ANY object that has write() and flush().
    No common base class required."""
    logger.write(f"EVENT: {event}")
    logger.flush()

log_event(DatabaseLogger(), "user_login")  # works
# log_event(sys.stdout, "user_login")      # also works - stdout has write/flush


# 3. Operator overloading
class Vector:
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

    def __add__(self, other: "Vector") -> "Vector":
        if not isinstance(other, Vector):
            return NotImplemented
        return Vector(self.x + other.x, self.y + other.y)

    def __mul__(self, scalar: float) -> "Vector":
        return Vector(self.x * scalar, self.y * scalar)

    def __rmul__(self, scalar: float) -> "Vector":
        return self.__mul__(scalar)  # 3 * vec works

    def __abs__(self) -> float:
        return math.sqrt(self.x ** 2 + self.y ** 2)

    def __repr__(self) -> str:
        return f"Vector({self.x}, {self.y})"

v1 = Vector(1, 2)
v2 = Vector(3, 4)
print(v1 + v2)       # Vector(4, 6)
print(3 * v1)         # Vector(3, 6) - uses __rmul__
print(abs(v2))        # 5.0


# 4. singledispatch - type-based dispatch (Python's answer to overloading)
@singledispatch
def serialize(value) -> str:
    raise TypeError(f"Cannot serialize {type(value)}")

@serialize.register(str)
def _(value: str) -> str:
    return f'"{value}"'

@serialize.register(int)
@serialize.register(float)
def _(value) -> str:
    return str(value)

@serialize.register(list)
def _(value: list) -> str:
    items = ", ".join(serialize(item) for item in value)
    return f"[{items}]"

print(serialize("hello"))      # "hello"
print(serialize(42))           # 42
print(serialize([1, "two"]))   # [1, "two"]
```

---

## Visualizer

<iframe src="/static/visualizers/polymorphism.html" style="width:100%;height:440px;border:none;border-radius:8px;" title="Polymorphism Visualizer"></iframe>

---

## How It Connects

Duck typing is the most Pythonic form of polymorphism. It requires no class hierarchy and no explicit interface - just compatible method signatures. Protocols formalize duck typing for static type checkers.

[[protocols|Protocols]]

Method overriding relies on inheritance and the MRO to determine which implementation gets called. Understanding the MRO is essential for predicting polymorphic behavior in multi-level hierarchies.

[[inheritance-oop|Inheritance]]

[[mro|MRO]]

Operator overloading is achieved through dunder methods. The Python data model defines which dunder methods correspond to which operators, and CPython's eval loop calls them automatically.

[[dunder-methods|Dunder Methods]]

[[python-data-model|Python Data Model]]

---

## Common Misconceptions

Misconception 1: "Python supports method overloading - you can define multiple methods with the same name but different parameter types."
Reality: Python does not support traditional method overloading. If you define two methods with the same name in a class, the second one silently replaces the first. For type-based dispatch, use `@functools.singledispatch` (for functions) or `@functools.singledispatchmethod` (for methods). For optional parameters, use default values and `*args`/`**kwargs`.

Misconception 2: "You need isinstance checks to handle different types in a function."
Reality: isinstance checks are the opposite of polymorphism. If your function has `if isinstance(x, Circle): ... elif isinstance(x, Rectangle): ...`, you have written a type switch, not polymorphic code. Each type should know how to perform its own operation. The calling code should call the method and let the object handle the rest.

Misconception 3: "Operator overloading makes code more readable by default."
Reality: Operator overloading makes code readable only when the operator's meaning is intuitive for the domain. `Vector(1,2) + Vector(3,4)` is clear. `User("alice") + User("bob")` is confusing - what does adding users mean? Use operator overloading for mathematical types, collections, and other domains where operators have well-established semantics.

---

## Why It Matters in Practice

Polymorphism is what makes plugin architectures, strategy patterns, and extensible systems work. A web framework that accepts any callable as a request handler is using duck typing polymorphism. A serialization library that converts different types to JSON by calling `to_dict()` on each one is using polymorphism. Without it, every new type requires modifying existing code to add another isinstance branch, violating the Open/Closed Principle.

In testing, polymorphism enables mocks and stubs. Your production code uses a `DatabaseRepository`. Your tests pass in a `FakeRepository`. Both implement the same interface. This only works because the calling code is polymorphic - it does not care which specific type it receives, only that the type supports the expected methods.

---

## Interview Angle

Common question forms:
- "What is polymorphism? Give an example in Python."
- "What is the difference between method overloading and method overriding?"
- "How does Python achieve polymorphism without explicit interfaces?"
- "Implement a polymorphic `area()` method for different shapes."

Answer frame:
Define polymorphism as same interface, different behavior. Distinguish compile-time (overloading, not in Python) from runtime (overriding, duck typing). Give a concrete shape example with method overriding. Explain duck typing as Python's primary mechanism. Mention operator overloading via dunder methods. Note `singledispatch` as Python's closest equivalent to overloading.

---

## Related Notes

- [[protocols|Protocols]]
- [[inheritance-oop|Inheritance]]
- [[mro|MRO]]
- [[dunder-methods|Dunder Methods]]
- [[python-data-model|Python Data Model]]
- [[oop-basics|OOP Basics]]
- [[strategy-pattern|Strategy Pattern]]
