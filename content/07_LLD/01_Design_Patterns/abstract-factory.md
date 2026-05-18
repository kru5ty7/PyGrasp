---
title: 04 - Abstract Factory Pattern
description: The Abstract Factory pattern provides an interface for creating families of related objects without specifying their concrete classes, ensuring that products from the same family are used together.
tags: [design-patterns, abstract-factory, creational, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Abstract Factory Pattern

> The Abstract Factory creates families of related objects through a single interface, ensuring that products designed to work together are always used together.

---

## Quick Reference

**Core idea:**
- Abstract Factory creates **families** of related objects, not just individual objects (that is Factory Method)
- Ensures consistency: a "dark theme" factory creates dark buttons, dark text fields, and dark menus that all match
- The client depends on the factory interface, not on concrete product classes
- In Python, a factory function returning a bundle of related objects or a dataclass of factories often replaces the full GoF class hierarchy
- Used when a system must work with one of several families of products (UI themes, database dialects, OS-specific components)

**Tricky points:**
- Adding a new product type to the family requires changing the abstract factory interface - this is the pattern's main rigidity
- In Python, passing a module or a dictionary of factory functions is often simpler than creating abstract factory classes
- Abstract Factory is rarely needed in Python due to duck typing and dynamic dispatch - most cases are better served by simple factory functions
- The pattern adds significant indirection and is justified only when product families must be consistent

---

## What It Is

Think of a furniture store that sells matching sets. When you order a "modern" living room set, you get a modern sofa, a modern coffee table, and a modern lamp - all designed to match. When you order a "vintage" set, you get vintage versions of each piece. The store does not let you mix a modern sofa with a vintage lamp because they would look wrong together. The "modern set" catalog is an abstract factory that produces a consistent family of products.

Abstract Factory extends the Factory Method concept from single objects to families. A Factory Method creates one product (a button). An Abstract Factory creates a coordinated set of products (a button, a text field, a checkbox) that are designed to work together. The classic example is a GUI toolkit that supports multiple look-and-feel themes: each theme factory creates themed versions of every widget, ensuring visual consistency.

In Python, the full GoF Abstract Factory (with abstract factory classes, concrete factories, abstract product classes, and concrete products) is rare because the language offers simpler alternatives. A module can serve as a factory (import `postgres_module` or `mysql_module` and each provides `create_connection()`, `create_cursor()`, `create_pool()`). A dictionary mapping theme names to widget constructors achieves the same decoupling with less ceremony.

---

## How It Actually Works

The abstract factory defines methods for creating each product in the family. Concrete factories implement these methods to create specific product variants. The client code receives a factory object and calls its creation methods, never knowing which concrete products it gets.

In Python, you can implement this with Protocols defining the factory interface, concrete classes implementing it, and dependency injection to select the factory at runtime.

```python
from typing import Protocol
from dataclasses import dataclass


# Product protocols - what the products must support
class Button(Protocol):
    def render(self) -> str: ...
    def click(self) -> str: ...

class TextField(Protocol):
    def render(self) -> str: ...
    def get_value(self) -> str: ...

class Checkbox(Protocol):
    def render(self) -> str: ...


# Concrete products - Dark theme
class DarkButton:
    def render(self) -> str:
        return "[Dark Button]"
    def click(self) -> str:
        return "Dark button clicked"

class DarkTextField:
    def render(self) -> str:
        return "[Dark Input ____]"
    def get_value(self) -> str:
        return "dark_value"

class DarkCheckbox:
    def render(self) -> str:
        return "[x] Dark checkbox"


# Concrete products - Light theme
class LightButton:
    def render(self) -> str:
        return "(Light Button)"
    def click(self) -> str:
        return "Light button clicked"

class LightTextField:
    def render(self) -> str:
        return "(Light Input ____)"
    def get_value(self) -> str:
        return "light_value"

class LightCheckbox:
    def render(self) -> str:
        return "[ ] Light checkbox"


# Abstract Factory protocol
class UIFactory(Protocol):
    def create_button(self) -> Button: ...
    def create_text_field(self) -> TextField: ...
    def create_checkbox(self) -> Checkbox: ...


# Concrete factories
class DarkThemeFactory:
    def create_button(self) -> Button:
        return DarkButton()
    def create_text_field(self) -> TextField:
        return DarkTextField()
    def create_checkbox(self) -> Checkbox:
        return DarkCheckbox()

class LightThemeFactory:
    def create_button(self) -> Button:
        return LightButton()
    def create_text_field(self) -> TextField:
        return LightTextField()
    def create_checkbox(self) -> Checkbox:
        return LightCheckbox()


# Client code depends on factory interface, not concrete products
class LoginForm:
    def __init__(self, factory: UIFactory):
        self.username = factory.create_text_field()
        self.password = factory.create_text_field()
        self.remember = factory.create_checkbox()
        self.submit = factory.create_button()

    def render(self) -> str:
        return "\n".join([
            "Username: " + self.username.render(),
            "Password: " + self.password.render(),
            self.remember.render(),
            self.submit.render(),
        ])


# Switch themes by swapping the factory
dark_form = LoginForm(DarkThemeFactory())
print(dark_form.render())
print("---")
light_form = LoginForm(LightThemeFactory())
print(light_form.render())


# Pythonic alternative: dictionary of factories
themes = {
    "dark": {"button": DarkButton, "text": DarkTextField, "check": DarkCheckbox},
    "light": {"button": LightButton, "text": LightTextField, "check": LightCheckbox},
}

def create_form(theme_name: str) -> dict:
    theme = themes[theme_name]
    return {
        "username": theme["text"](),
        "password": theme["text"](),
        "remember": theme["check"](),
        "submit": theme["button"](),
    }
```

---

## How It Connects

Abstract Factory extends Factory Method from single products to product families. Understanding Factory Method is prerequisite.

[[factory-method|Factory Method Pattern]]

[[design-patterns-overview|Design Patterns Overview]]

Abstract Factory implements DIP at the product creation level: the client depends on the factory and product abstractions, not on concrete classes.

[[dip|Dependency Inversion Principle]]

---

## Common Misconceptions

Misconception 1: "Abstract Factory and Factory Method are the same thing."
Reality: Factory Method creates one product. Abstract Factory creates a family of related products. Factory Method uses inheritance (subclass overrides the creation method). Abstract Factory uses composition (the client holds a factory object and calls its creation methods).

Misconception 2: "Abstract Factory is needed whenever you have multiple implementations."
Reality: If your products do not need to be consistent as a family, use individual Factory Methods. Abstract Factory is justified only when mixing products from different families would cause problems (a dark button with a light theme text field).

---

## Why It Matters in Practice

Abstract Factory appears in database abstraction layers (a Postgres factory creates Postgres connections, cursors, and type adapters that work together), cross-platform libraries (a Windows factory creates Windows-specific file handlers, path objects, and system calls), and testing (a mock factory creates test doubles for an entire subsystem).

In Python applications, the full pattern is uncommon. More often, you see a configuration-driven approach: load a module based on a config value, and the module provides all the related components. SQLAlchemy's dialect system is a real-world abstract factory: each dialect (PostgreSQL, MySQL, SQLite) provides a consistent set of compiler, type system, and connection components.

---

## Interview Angle

Common question forms:
- "What is the difference between Factory Method and Abstract Factory?"
- "When would you use Abstract Factory?"
- "Design a system that supports multiple database backends."

Answer frame:
Distinguish from Factory Method (single product vs family). Explain the consistency guarantee. Give the UI theme or database dialect example. Show the Pythonic alternative (module-level factories, dictionary dispatch). Acknowledge that the full pattern is rare in Python.

---

## Related Notes

- [[factory-method|Factory Method Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[dip|Dependency Inversion Principle]]
- [[composition-over-inheritance|Composition Over Inheritance]]
