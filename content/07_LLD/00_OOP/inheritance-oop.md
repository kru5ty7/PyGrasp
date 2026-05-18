---
title: 04 - Inheritance
description: Inheritance lets a class reuse and extend another class's attributes and methods, forming an is-a relationship where the child class inherits the parent's interface and can override or extend its behavior.
tags: [oop, inheritance, mro, super, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# Inheritance

> Inheritance creates a parent-child relationship between classes where the child automatically receives the parent's attributes and methods, and can override or extend them.

---

## Quick Reference

**Core idea:**
- Inheritance establishes an **is-a** relationship: a `Dog` is an `Animal`, a `PostgresRepository` is a `Repository`
- The child class (subclass) inherits all attributes and methods from the parent class (superclass) and can override any of them
- Python supports **multiple inheritance** - a class can inherit from multiple parents simultaneously
- `super()` returns a proxy that delegates method calls to the next class in the Method Resolution Order (MRO), not necessarily the direct parent
- All Python classes implicitly inherit from `object`, which provides default implementations of `__repr__`, `__eq__`, `__hash__`, and other dunder methods

**Tricky points:**
- `super()` does not always call the parent class - in a diamond inheritance hierarchy, it calls the next class in the MRO, which might be a sibling
- Overriding `__init__` without calling `super().__init__()` silently skips parent initialization - the parent's attributes never get set
- isinstance checks walk the entire inheritance chain: `isinstance(dog, Animal)` returns `True` even though `dog` is a `Dog` instance
- Deep inheritance hierarchies (more than 2-3 levels) create fragile code where changing a parent class can break distant descendants in non-obvious ways

---

## What It Is

Think of a restaurant's recipe system. The head chef has a base recipe for "sauce" - a set of steps that every sauce follows: heat oil, add aromatics, add liquid, reduce. Each specific sauce - marinara, bechamel, curry - starts with those base steps and adds its own ingredients and techniques. The marinara adds tomatoes and basil. The bechamel adds butter, flour, and milk. Each specialized sauce inherits the base process and extends it with specifics. If the head chef improves the base "heat oil" step (use a wider pan for better evaporation), every sauce that inherits from it benefits automatically.

Inheritance in programming works the same way. You define a parent class with shared behavior, and child classes inherit that behavior while adding or modifying what is specific to them. A `Vehicle` class might define `start()`, `stop()`, and `fuel_level`. A `Car` class inherits all of that and adds `trunk_capacity`. A `Motorcycle` class inherits the same base but adds `lean_angle`. The shared logic lives in one place (the parent), reducing duplication and ensuring consistency.

Python's inheritance is more flexible than most languages because it supports multiple inheritance - a class can have more than one parent. A `FlyingCar` could inherit from both `Car` and `Aircraft`. This power comes with complexity: when two parents define a method with the same name, Python uses the C3 linearization algorithm to determine which one gets called. The resulting order is the Method Resolution Order (MRO), which you can inspect via `ClassName.__mro__` or `ClassName.mro()`.

The `super()` function is the correct way to call parent methods. In single inheritance, `super().__init__()` calls the parent's `__init__`. In multiple inheritance, `super()` follows the MRO chain, which means it might call a sibling class's method rather than a direct parent's. This cooperative behavior is what makes Python's multiple inheritance work correctly - each class in the chain calls `super()`, and the MRO ensures every class's method is called exactly once.

---

## How It Actually Works

When Python creates a class with inheritance, the metaclass (`type`) computes the MRO using C3 linearization. This algorithm produces a linear ordering of all ancestor classes that respects two constraints: children come before parents, and the order of base classes in the class definition is preserved. The MRO is stored as a tuple in the class's `__mro__` attribute and is used for all attribute lookups on instances of that class.

Method resolution follows the MRO from left to right. When you call `obj.method()`, Python starts at the instance's class, walks through each class in the MRO, and returns the first `method` it finds. When you override a method in a child class, the child's version appears first in the MRO and shadows the parent's version. When you call `super().method()` inside the child, Python skips the current class in the MRO and continues the search from the next class.

```python
class Animal:
    def __init__(self, name: str, species: str):
        self.name = name
        self.species = species

    def speak(self) -> str:
        return f"{self.name} makes a sound"

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(name={self.name!r})"


class Dog(Animal):
    def __init__(self, name: str, breed: str):
        super().__init__(name, species="Canis familiaris")  # call parent init
        self.breed = breed

    def speak(self) -> str:
        return f"{self.name} barks"

    def fetch(self, item: str) -> str:
        return f"{self.name} fetches the {item}"


class ServiceDog(Dog):
    def __init__(self, name: str, breed: str, task: str):
        super().__init__(name, breed)  # calls Dog.__init__
        self.task = task

    def speak(self) -> str:
        # Can extend parent behavior rather than fully replacing it
        base = super().speak()  # "Rex barks"
        return f"{base} (trained for {self.task})"


# Single inheritance chain
rex = ServiceDog("Rex", "German Shepherd", "guide")
print(rex.speak())       # "Rex barks (trained for guide)"
print(rex.species)       # "Canis familiaris" - inherited from Animal
print(rex.fetch("ball")) # "Rex fetches the ball" - inherited from Dog

# MRO inspection
print(ServiceDog.__mro__)
# (ServiceDog, Dog, Animal, object)

# isinstance walks the full chain
print(isinstance(rex, ServiceDog))  # True
print(isinstance(rex, Dog))         # True
print(isinstance(rex, Animal))      # True


# Multiple inheritance with cooperative super()
class Loggable:
    def __init__(self, **kwargs):
        print(f"Loggable.__init__ for {self.__class__.__name__}")
        super().__init__(**kwargs)

    def log(self, message: str) -> None:
        print(f"[{self.__class__.__name__}] {message}")


class Serializable:
    def __init__(self, **kwargs):
        print(f"Serializable.__init__ for {self.__class__.__name__}")
        super().__init__(**kwargs)

    def to_dict(self) -> dict:
        return {k: v for k, v in self.__dict__.items() if not k.startswith("_")}


class User(Loggable, Serializable):
    def __init__(self, name: str, email: str):
        super().__init__()  # follows MRO: Loggable -> Serializable -> object
        self.name = name
        self.email = email


u = User("Alice", "alice@example.com")
# Prints: Loggable.__init__ for User
# Prints: Serializable.__init__ for User
u.log("created")            # [User] created
print(u.to_dict())          # {'name': 'Alice', 'email': 'alice@example.com'}
print(User.__mro__)
# (User, Loggable, Serializable, object)
```

---

## How It Connects

Python resolves method calls in multiple inheritance using C3 linearization. Understanding the MRO is essential for predicting which method gets called when classes share method names.

[[mro|MRO]]

When multiple parents define the same method, the MRO determines which version wins. This is the core complexity of multiple inheritance and the reason Python uses C3 rather than simpler depth-first or breadth-first traversal.

[[multiple-inheritance|Multiple Inheritance]]

Composition is the alternative to inheritance - instead of "is-a", you use "has-a" relationships. Knowing when to inherit and when to compose is one of the most important design decisions in OOP.

[[composition-over-inheritance|Composition Over Inheritance]]

The Liskov Substitution Principle defines the contract that inheritance should follow: a subclass must be usable anywhere its parent is expected, without breaking the program.

[[lsp|Liskov Substitution Principle]]

---

## Common Misconceptions

Misconception 1: "`super()` always calls the direct parent class."
Reality: `super()` calls the next class in the MRO, which is not always the direct parent. In a diamond inheritance pattern (class D inherits from B and C, both of which inherit from A), calling `super()` in B might call C's method rather than A's. This cooperative behavior is by design and is what makes multiple inheritance work correctly in Python.

Misconception 2: "Inheritance is always better than duplicating code."
Reality: Inheritance creates a tight coupling between parent and child classes. If you change the parent's implementation, all children are affected. When the "shared code" is just a few lines and the classes do not have a true is-a relationship, extracting the shared logic into a utility function or using composition is often better. Inheritance for code reuse alone (without a genuine type relationship) leads to fragile hierarchies.

Misconception 3: "You should model real-world hierarchies directly in class hierarchies."
Reality: Real-world taxonomies do not map cleanly to inheritance. A `Penguin` is a `Bird`, but it cannot fly. A `Square` is a `Rectangle` mathematically, but making `Square` inherit from `Rectangle` violates the Liskov Substitution Principle because `set_width()` on a square must also change the height. Design class hierarchies based on behavioral compatibility, not on real-world categorization.

---

## Why It Matters in Practice

Inheritance is the primary mechanism for extending framework behavior. Django class-based views, FastAPI dependency injection, SQLAlchemy model definitions, and pytest fixtures all rely on inheritance. When you override a method in a Django view, you are using inheritance. When your SQLAlchemy model inherits from `Base`, you are using inheritance. Understanding the MRO and `super()` is not academic - it determines whether your framework customizations work correctly or silently break.

Misusing inheritance - creating deep hierarchies, using it purely for code reuse without an is-a relationship, or forgetting to call `super()` in `__init__` - causes bugs that are difficult to diagnose because the behavior emerges from the interaction of multiple classes across multiple files.

---

## Interview Angle

Common question forms:
- "What is inheritance and when would you use it?"
- "Explain the Method Resolution Order in Python."
- "What is the diamond problem and how does Python solve it?"
- "What is the difference between `super().__init__()` and `Parent.__init__(self)`?"

Answer frame:
Define inheritance as an is-a relationship for type reuse. Explain MRO and C3 linearization. Walk through the diamond problem with a concrete example. Show how `super()` follows MRO cooperatively vs `Parent.__init__(self)` hardcoding the parent. Discuss when composition is preferable (no true is-a relationship, code reuse only).

---

## Related Notes

- [[mro|MRO]]
- [[multiple-inheritance|Multiple Inheritance]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[lsp|Liskov Substitution Principle]]
- [[oop-basics|OOP Basics]]
- [[class-creation|Class Creation]]
