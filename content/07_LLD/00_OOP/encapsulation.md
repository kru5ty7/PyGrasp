---
title: 02 - Encapsulation
description: Encapsulation bundles data and the methods that operate on it into a single unit, controlling access to internal state so that objects manage their own invariants and external code interacts only through a defined interface.
tags: [oop, encapsulation, private, protected, properties, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# Encapsulation

> Encapsulation bundles data with the methods that operate on it and restricts direct access to internal state, forcing external code to interact through a controlled interface.

---

## Quick Reference

**Core idea:**
- Encapsulation means an object's internal state is not directly accessible from outside - callers use methods to read or modify it
- Python uses **naming conventions** rather than access modifiers: `_private` signals "internal, do not touch"; `__mangled` triggers name mangling to make accidental access harder
- Python has no `private` keyword - the convention is enforced by culture and tooling, not by the runtime
- Properties (`@property`) let you expose computed or validated attributes that look like simple attribute access but execute code behind the scenes
- The goal is not secrecy but **protection of invariants** - ensuring that an object's state is always valid

**Tricky points:**
- `_single_underscore` is a convention only - Python does not prevent access; linters and IDEs flag it
- `__double_underscore` triggers name mangling: `__attr` in class `Foo` becomes `_Foo__attr` - it is not truly private, just harder to accidentally override in subclasses
- Name mangling exists to prevent **name collisions in inheritance**, not to enforce privacy
- Properties can have side effects - a `@property` getter that mutates state or triggers I/O is a design smell because callers expect attribute access to be cheap and side-effect-free
- Overusing getters and setters for every attribute (Java-style) is unidiomatic in Python - start with plain attributes and add properties only when you need validation or computation

---

## What It Is

Think of a thermostat on your wall. You interact with it through a simple interface: set the target temperature, read the current temperature. You never reach inside the thermostat to manually twist the relay switch or adjust the temperature sensor's calibration. The thermostat manages its own internal wiring and logic. If you could reach in and twist any wire, you might set the heater to run while the air conditioner is also running - an invalid state that the thermostat's internal logic prevents. The limited interface protects the system's invariants.

Encapsulation applies the same principle to code. An object bundles its data (attributes) and the methods that are allowed to modify that data into a single unit. External code does not reach directly into the object's internals. Instead, it calls methods that validate inputs, enforce business rules, and ensure the object's state remains consistent. A `BankAccount` object does not let you set `self.balance = -1000` directly. It exposes a `withdraw()` method that checks whether you have sufficient funds before modifying the balance.

Python takes a pragmatic approach to encapsulation. There are no access modifiers like `private`, `protected`, or `public`. Instead, Python relies on naming conventions: a single leading underscore (`_balance`) signals that an attribute is internal and should not be accessed by external code. A double leading underscore (`__balance`) triggers name mangling, where CPython renames the attribute to `_ClassName__balance` to prevent accidental collisions in subclass hierarchies. Neither mechanism prevents determined access - Python trusts developers to respect conventions. The philosophy is "we are all consenting adults here."

The `@property` decorator bridges the gap between raw attribute access and encapsulation. It lets you define a method that is accessed like an attribute: `account.balance` looks like reading a simple field, but behind the scenes it calls a method that can compute, validate, or log the access. This means you can start with plain attributes in your initial design and add encapsulation later without changing the interface that callers use.

---

## How It Actually Works

When you prefix an attribute with double underscores, CPython's compiler performs name mangling during the class body compilation phase - before the class object is even created. The bytecode compiler rewrites any reference to `__attr` inside the class body into `_ClassName__attr`. This happens at compile time, not at runtime, and it applies to any name with two or more leading underscores and at most one trailing underscore. The purpose is not privacy - it is preventing a subclass from accidentally overriding a parent class's internal attribute with the same name.

Properties are implemented using the descriptor protocol. When you apply `@property` to a method, it creates a `property` descriptor object and stores it in the class's `__dict__`. When you access `obj.attr` and Python finds a data descriptor (an object with both `__get__` and `__set__`) in the class hierarchy, the descriptor takes priority over the instance's `__dict__`. This means a property defined on the class intercepts all reads and writes to that attribute name on any instance, even if the instance has a key with the same name in its own `__dict__`.

```python
class Temperature:
    """Encapsulates a temperature value with Celsius/Fahrenheit conversion.
    
    Internal state is stored in Celsius. Fahrenheit is a computed view.
    Direct modification of the internal value is prevented by convention
    and by the property interface.
    """

    def __init__(self, celsius: float):
        self.celsius = celsius  # goes through the setter

    @property
    def celsius(self) -> float:
        return self._celsius

    @celsius.setter
    def celsius(self, value: float) -> None:
        if value < -273.15:
            raise ValueError(
                f"Temperature {value}C is below absolute zero (-273.15C)"
            )
        self._celsius = value  # actual storage uses _celsius

    @property
    def fahrenheit(self) -> float:
        return self._celsius * 9 / 5 + 32

    @fahrenheit.setter
    def fahrenheit(self, value: float) -> None:
        self.celsius = (value - 32) * 5 / 9  # delegates to celsius setter for validation

    def __repr__(self) -> str:
        return f"Temperature({self._celsius:.1f}C / {self.fahrenheit:.1f}F)"


t = Temperature(100)
print(t)                # Temperature(100.0C / 212.0F)
t.fahrenheit = 32
print(t.celsius)        # 0.0

try:
    t.celsius = -300    # ValueError: below absolute zero
except ValueError as e:
    print(e)

# Name mangling example
class Connection:
    def __init__(self, host: str, port: int):
        self.__socket = None    # mangled to _Connection__socket
        self.host = host
        self.port = port

    def connect(self):
        import socket
        self.__socket = socket.create_connection((self.host, self.port))

    def close(self):
        if self.__socket:
            self.__socket.close()
            self.__socket = None

conn = Connection("localhost", 8080)
# conn.__socket                # AttributeError
# conn._Connection__socket     # works - mangling is not security
```

---

## How It Connects

Encapsulation relies on properties, which are built on Python's descriptor protocol. Understanding descriptors explains why properties can intercept attribute access and how the lookup chain determines whether a descriptor or an instance attribute wins.

[[descriptors|Descriptors]]

[[properties|Properties]]

The `@property` decorator is syntactic sugar for creating descriptor objects. Decorators in general are functions that wrap other functions, and properties are the most common example of decorators used for encapsulation rather than cross-cutting concerns.

[[decorators|Decorators]]

Encapsulation is one of the four pillars of OOP. It works hand-in-hand with abstraction: encapsulation hides the implementation, abstraction defines the interface. Together they let you change internals without breaking callers.

[[abstraction|Abstraction]]

The `__slots__` mechanism is an alternative to `__dict__` that restricts which attributes an instance can have. This is a stronger form of encapsulation at the structural level - you physically prevent arbitrary attribute assignment.

[[slots|Slots]]

---

## Common Misconceptions

Misconception 1: "Python's single underscore `_attr` makes an attribute private."
Reality: The single underscore is purely a naming convention. Python does not enforce it in any way. Any code can read or write `obj._attr` without restriction. The convention tells other developers "this is internal - if you use it, you are on your own when it changes." Linters and IDE autocompletion respect this convention, but the language does not.

Misconception 2: "Double underscore `__attr` makes an attribute truly private and inaccessible."
Reality: Name mangling renames `__attr` to `_ClassName__attr`, which is fully accessible if you know the mangled name. The purpose of mangling is to prevent accidental name collisions when a subclass defines an attribute with the same name as a parent class's internal attribute. It is a namespace collision avoidance mechanism, not an access control mechanism.

Misconception 3: "Every attribute should have a getter and setter method like in Java."
Reality: In Python, start with plain public attributes. If you later need to add validation, computation, or side effects when an attribute is accessed, convert it to a `@property`. The calling code does not change because `obj.attr` works the same whether `attr` is a plain attribute or a property. This is the Uniform Access Principle - and it makes preemptive getters and setters unnecessary.

---

## Why It Matters in Practice

Without encapsulation, any part of a codebase can modify any object's internal state directly. A balance goes negative because some module set `account.balance` without checking the withdrawal limit. A connection pool's internal counter gets out of sync because external code decremented it directly instead of calling `release()`. These bugs are hard to find because the modification happens far from the object's definition.

Encapsulation concentrates all state-modifying logic inside the object itself. When something goes wrong, you know the bug is in the object's methods - not scattered across the entire codebase. This is especially critical in larger teams and longer-lived codebases where the person modifying code is not the person who wrote the class.

---

## Interview Angle

Common question forms:
- "What is encapsulation and why is it important?"
- "How does Python handle private attributes?"
- "What is name mangling in Python?"
- "When would you use `@property` vs a plain attribute?"

Answer frame:
Define encapsulation as bundling state with controlled access. Explain Python's convention-based approach (single underscore, double underscore mangling). Clarify that mangling prevents name collisions in inheritance, not access. Describe `@property` as the Pythonic way to add validation without changing the caller's interface. Contrast with Java's mandatory getter/setter pattern and explain why Python's approach is more pragmatic.

---

## Related Notes

- [[descriptors|Descriptors]]
- [[properties|Properties]]
- [[decorators|Decorators]]
- [[abstraction|Abstraction]]
- [[slots|Slots]]
- [[oop-basics|OOP Basics]]
