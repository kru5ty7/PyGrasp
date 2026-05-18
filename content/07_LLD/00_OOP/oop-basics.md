---
title: 01 - OOP Basics
description: Object-oriented programming organizes code around objects that bundle data and behavior together, letting you model real-world concepts as interacting entities rather than sequences of instructions.
tags: [oop, classes, objects, methods, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# OOP Basics

> Object-oriented programming structures code around objects - bundles of data and the functions that operate on that data - giving you a way to model, organize, and reason about complex systems.

---

## Quick Reference

**Core idea:**
- An **object** is a bundle of state (attributes) and behavior (methods) that represents a single entity
- A **class** is a blueprint that defines what attributes and methods its objects will have
- Python classes are themselves objects - instances of `type` - which means you can inspect, modify, and pass them around like any other value
- The `self` parameter is how a method accesses the specific instance it was called on - Python passes it automatically
- `__init__` is not a constructor - it is an initializer; `__new__` actually creates the object, then `__init__` sets up its state
- Everything in Python is an object: integers, strings, functions, modules, classes themselves

**Tricky points:**
- Class attributes are shared across all instances; instance attributes (set via `self.x`) belong to a single object - modifying a mutable class attribute from one instance affects all others
- `self` is a convention, not a keyword - you could call it anything, but breaking this convention confuses every reader of your code
- Methods are just functions stored as class attributes - calling `obj.method()` triggers the descriptor protocol to bind `self` automatically
- Defining `__init__` does not make your class a constructor - by the time `__init__` runs, the object already exists in memory

---

## What It Is

Think of a car factory. The factory has blueprints that describe what a car looks like: four wheels, an engine, a color, a VIN number. Every car that rolls off the assembly line follows the same blueprint, but each car is a distinct physical object with its own color, its own mileage, its own engine serial number. The blueprint is the class. Each individual car is an object (an instance of that class). The color and mileage are attributes. The actions the car can perform - start, accelerate, brake - are methods.

Object-oriented programming (OOP) is a way of organizing code around these blueprints and their instances. Instead of writing a program as a long sequence of instructions that operate on loose data, you group related data and the functions that manipulate it into a single unit. A `User` object knows its own name and email and knows how to validate its own password. A `ShoppingCart` object holds its own list of items and knows how to calculate its own total. Each object is responsible for its own data and its own behavior.

Python's OOP model is built on top of its object system. When you write `class Dog:`, Python creates a new object of type `type` whose name is `Dog`. When you call `Dog()`, Python first calls `Dog.__new__(Dog)` to allocate a new instance, then calls `Dog.__init__(instance)` to initialize its attributes. The result is a `Dog` instance - an object whose `__class__` attribute points back to the `Dog` class. This two-step creation process matters because `__new__` controls whether an object is actually created (useful for singletons, caching, or immutable types), while `__init__` only sets up state on an already-existing object.

The relationship between classes and instances is dynamic in Python. You can add attributes to an instance after creation. You can add methods to a class after it is defined. You can even change an object's class at runtime by reassigning its `__class__` attribute. This flexibility is powerful but demands discipline - OOP design principles exist precisely to help you use this flexibility without creating unmaintainable chaos.

---

## How It Actually Works

When CPython executes a class body, it creates a new namespace (a dictionary), runs the class body's bytecode in that namespace, and then calls the metaclass (usually `type`) with three arguments: the class name, the tuple of base classes, and the namespace dictionary. The result is a class object. The methods you defined in the class body are stored as regular function objects in the class's `__dict__`. Attributes set at class level (outside any method) become class attributes, also stored in `__dict__`.

When you access an attribute on an instance, Python follows a lookup chain. First it checks the instance's `__dict__`. If the attribute is not there, it walks the class's Method Resolution Order (MRO) - the class itself, then its parents in a specific order - checking each class's `__dict__`. If it finds a descriptor (an object with `__get__`, `__set__`, or `__delete__` methods), the descriptor protocol takes over. This is how methods work: a function stored in the class's `__dict__` is a descriptor. When accessed through an instance, its `__get__` method returns a bound method object that has `self` pre-filled with the instance.

Instance attributes are stored in the instance's `__dict__`, which is a regular Python dictionary allocated on the heap. This is why each instance can have different attributes - they each have their own dictionary. The `__slots__` mechanism replaces this dictionary with a fixed-size struct, saving memory when you have millions of instances, but at the cost of losing the ability to add arbitrary attributes.

```python
class Account:
    bank_name = "PyBank"  # class attribute - shared by all instances

    def __init__(self, owner: str, balance: float = 0.0):
        self.owner = owner        # instance attribute - unique per object
        self.balance = balance    # instance attribute

    def deposit(self, amount: float) -> None:
        if amount <= 0:
            raise ValueError("Deposit amount must be positive")
        self.balance += amount

    def withdraw(self, amount: float) -> None:
        if amount > self.balance:
            raise ValueError(f"Insufficient funds: {self.balance:.2f} available")
        self.balance -= amount

    def __repr__(self) -> str:
        return f"Account(owner={self.owner!r}, balance={self.balance:.2f})"


# Class vs instance attributes
a1 = Account("Alice", 100.0)
a2 = Account("Bob", 200.0)

print(a1.bank_name)       # "PyBank" - found in class __dict__
print(a1.owner)           # "Alice" - found in instance __dict__

Account.bank_name = "NewBank"
print(a2.bank_name)       # "NewBank" - class attribute changed for all

# Under the hood
print(type(Account))                    # <class 'type'>
print(Account.__dict__["deposit"])      # <function Account.deposit at 0x...>
print(type(a1.deposit))                 # <class 'method'> - bound method via descriptor
print(a1.deposit.__self__ is a1)        # True - self is bound to a1
```

---

## How It Connects

OOP in Python is not a separate system bolted on - it is built directly on top of the object model and class creation machinery that Python uses for everything. Understanding how classes are created gives you the foundation.

[[class-creation|Class Creation]]

Every attribute access on an object goes through the descriptor protocol. Methods, properties, classmethods, and staticmethods all work because of descriptors. Understanding descriptors means understanding why `self` gets passed automatically.

[[descriptors|Descriptors]]

When a class has multiple parent classes, Python uses the C3 linearization algorithm to determine the Method Resolution Order. This ordering affects which method gets called when multiple parents define the same method.

[[mro|MRO]]

The principles that guide how to organize classes - what responsibilities each class should have, how classes should relate to each other - are formalized in SOLID. These are not Python-specific but they shape how you design any object-oriented system.

[[solid-principles|SOLID Principles]]

---

## Common Misconceptions

Misconception 1: "`__init__` is Python's constructor - it creates the object."
Reality: `__init__` is the initializer. By the time `__init__` runs, the object already exists in memory - `__new__` created it. `__init__` receives the already-allocated object as `self` and sets up its attributes. This distinction matters when you need to control object creation itself (singletons, immutable types like subclasses of `str` or `tuple`).

Misconception 2: "Class attributes and instance attributes are the same thing."
Reality: Class attributes live in the class's `__dict__` and are shared by all instances. Instance attributes live in each instance's own `__dict__`. When you read `self.x`, Python checks the instance dict first, then the class dict. When you write `self.x = value`, it always writes to the instance dict - even if a class attribute with the same name exists. This means `self.x = value` can shadow a class attribute without modifying it.

Misconception 3: "Python OOP works like Java OOP - everything should be in a class."
Reality: Python is multi-paradigm. Functions, modules, and closures are first-class tools. Wrapping everything in a class (the Java `public static void main` style) is unidiomatic in Python. Use a class when you have state and behavior that belong together. Use a function when you have a stateless transformation. Use a module when you have related functions and constants.

---

## Why It Matters in Practice

Every Python framework you use is built on OOP. Django models are classes. FastAPI request handlers use class-based dependency injection. SQLAlchemy maps classes to database tables. Pydantic models are classes that validate data on construction. Without understanding how classes, instances, and attribute lookup work, you cannot debug framework behavior when it deviates from what you expect. You end up fighting the framework instead of using it.

Beyond frameworks, OOP is the primary organizational tool for codebases beyond a few hundred lines. When you need to model entities with state that changes over time - users, orders, connections, game objects - OOP gives you a natural structure. The discipline of grouping data with the functions that operate on it reduces the cognitive load of navigating a large codebase. The key is knowing when to use it and when a simpler function or module is enough.

---

## Interview Angle

Common question forms:
- "What are the four pillars of OOP?"
- "Explain the difference between a class and an object."
- "What is the difference between `__init__` and `__new__`?"
- "What happens when you access an attribute on a Python object?"

Answer frame:
Define classes as blueprints and objects as instances. Walk through attribute lookup (instance dict -> class MRO -> descriptors). Distinguish `__new__` (creation) from `__init__` (initialization). Explain class vs instance attributes with the shadowing behavior. Name the four pillars (encapsulation, abstraction, inheritance, polymorphism) but emphasize that Python also supports functional and procedural styles - OOP is a tool, not a mandate.

---

## Related Notes

- [[class-creation|Class Creation]]
- [[descriptors|Descriptors]]
- [[mro|MRO]]
- [[solid-principles|SOLID Principles]]
- [[encapsulation|Encapsulation]]
- [[abstraction|Abstraction]]
- [[inheritance-oop|Inheritance]]
- [[polymorphism|Polymorphism]]
