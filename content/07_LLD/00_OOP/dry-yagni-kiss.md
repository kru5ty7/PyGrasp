---
title: 13 - DRY, YAGNI, KISS
description: Three complementary design heuristics - Don't Repeat Yourself eliminates duplication, You Aren't Gonna Need It prevents premature complexity, and Keep It Simple Stupid favors clarity over cleverness.
tags: [oop, design-principles, dry, yagni, kiss, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# DRY, YAGNI, KISS

> DRY eliminates knowledge duplication, YAGNI prevents building features you do not need yet, and KISS favors the simplest solution that works - together they keep code lean, clear, and maintainable.

---

## Quick Reference

**Core idea:**
- **DRY** (Don't Repeat Yourself): every piece of knowledge should have a single, authoritative representation in the system
- **YAGNI** (You Aren't Gonna Need It): do not build features, abstractions, or infrastructure until you actually need them
- **KISS** (Keep It Simple, Stupid): prefer the simplest solution that solves the problem - complexity should be justified by real requirements
- These three principles act as counterweights to over-engineering and under-engineering
- DRY prevents duplication, YAGNI prevents premature abstraction, KISS prevents unnecessary complexity

**Tricky points:**
- DRY is about **knowledge** duplication, not **code** duplication - two identical code blocks that change for different reasons should stay separate
- Over-applying DRY creates tight coupling: extracting shared code between unrelated features forces them to change together
- YAGNI does not mean "never plan ahead" - it means do not **implement** ahead; you can design for extensibility without building the extensions
- KISS is subjective - what is "simple" depends on the team's expertise and the problem domain
- These principles sometimes conflict: DRY might push you to create an abstraction, but YAGNI says you do not need it yet

---

## What It Is

Think of packing for a trip. KISS says bring only what you need and organize it simply - a carry-on bag with clear compartments. YAGNI says do not pack scuba gear "just in case" when you are going to a desert. DRY says bring one universal charger instead of three separate chargers that all do the same thing. Together: pack light, pack only what you need, and do not bring duplicates.

DRY was coined by Andy Hunt and Dave Thomas in "The Pragmatic Programmer." The full statement is: "Every piece of knowledge must have a single, unambiguous, authoritative representation within a system." Note that it says "knowledge," not "code." If two functions happen to have the same three lines but those lines represent different business rules that might change independently, they are not duplicates - they are coincidentally similar. Extracting them into a shared function would create accidental coupling. True DRY violations are when the same business rule, calculation, or configuration value is expressed in multiple places, so that changing the rule requires finding and updating every copy.

YAGNI comes from Extreme Programming and addresses the urge to build things "just in case." Developers frequently anticipate future requirements and build abstractions, plugin systems, configuration options, and extensibility hooks that are never used. Each unused abstraction adds code to maintain, tests to write, and complexity to navigate. YAGNI says: build what you need today. When the new requirement arrives, refactor. The cost of refactoring later is almost always lower than the cost of maintaining unused abstractions indefinitely.

KISS is the oldest of the three, attributed to the U.S. Navy in the 1960s. It says the best design is the simplest one that meets the requirements. A one-line list comprehension is simpler than a three-class strategy pattern when you have one case. A plain function is simpler than a class when you have no state. A dictionary is simpler than a custom object when you have no behavior. Complexity should be introduced only when simplicity genuinely fails to meet the need.

---

## How It Actually Works

DRY violations are detected by asking: "If this business rule changes, how many places do I need to update?" If the answer is more than one, you have a DRY violation. The fix is to extract the rule into a single source of truth - a constant, a function, a configuration file, a database column - and reference it from every place that needs it. Constants, utility functions, and configuration management are the primary tools for DRY in Python.

YAGNI violations are detected by asking: "Is there a current user story or requirement that demands this?" If the abstraction exists because "we might need it someday," that is YAGNI. The fix is to delete the abstraction and write the simplest code that serves the current need. If the future requirement materializes, you add the abstraction then, with the benefit of knowing the actual requirements rather than guessing.

KISS violations are detected by asking: "Could a junior developer understand this in under a minute?" If the code requires understanding three design patterns, two meta-programming techniques, and a custom DSL to perform what is essentially a data transformation, that is a KISS violation. The fix is to replace the clever code with straightforward code, even if it is a few lines longer.

```python
# DRY VIOLATION: same validation logic in two places
class UserAPI:
    def create_user(self, email: str):
        # Validation duplicated
        if "@" not in email or "." not in email.split("@")[1]:
            raise ValueError("Invalid email")
        # ... create user ...

    def update_email(self, user_id: str, email: str):
        # Same validation, different location
        if "@" not in email or "." not in email.split("@")[1]:
            raise ValueError("Invalid email")
        # ... update email ...


# DRY FIX: single source of truth for validation
def validate_email(email: str) -> None:
    """Single authoritative validation rule."""
    if "@" not in email or "." not in email.split("@")[1]:
        raise ValueError(f"Invalid email: {email}")


class UserAPIDry:
    def create_user(self, email: str):
        validate_email(email)  # single source
        # ... create user ...

    def update_email(self, user_id: str, email: str):
        validate_email(email)  # same source
        # ... update email ...


# YAGNI VIOLATION: building a plugin system for one notification type
class NotificationPlugin:  # premature abstraction
    def get_name(self) -> str: ...
    def validate_config(self, config: dict) -> bool: ...
    def send(self, to: str, message: str) -> None: ...

class NotificationRegistry:  # premature infrastructure
    _plugins: dict[str, NotificationPlugin] = {}

    @classmethod
    def register(cls, plugin: NotificationPlugin):
        cls._plugins[plugin.get_name()] = plugin

    @classmethod
    def get(cls, name: str) -> NotificationPlugin:
        return cls._plugins[name]

# All this for ONE notification type (email). YAGNI.


# YAGNI FIX: just send the email
def send_welcome_email(to: str, name: str) -> None:
    """When we need SMS or Slack, we refactor then."""
    print(f"Sending welcome email to {to}: Hello {name}!")


# KISS VIOLATION: over-engineered for a simple task
from functools import reduce
from operator import add

def calculate_total_clever(items: list[dict]) -> float:
    """Unnecessarily complex for summing prices."""
    return reduce(
        add,
        map(
            lambda item: item["price"] * item.get("quantity", 1),
            filter(lambda item: item.get("active", True), items)
        ),
        0.0
    )


# KISS FIX: straightforward loop
def calculate_total_simple(items: list[dict]) -> float:
    """Anyone can read this."""
    total = 0.0
    for item in items:
        if item.get("active", True):
            total += item["price"] * item.get("quantity", 1)
    return total


# WHEN DRY AND YAGNI CONFLICT:
# Two endpoints have similar but not identical response formatting.
# DRY says extract shared formatting. YAGNI says they might diverge.
# Resolution: wait until you have three cases, then extract.

# WHEN DRY AND KISS CONFLICT:
# Extracting a complex shared function makes each call site simpler
# but the shared function harder to understand.
# Resolution: favor KISS at the call site; the shared function
# is read less often.
```

---

## How It Connects

DRY, YAGNI, and KISS calibrate how you apply the SOLID principles. SOLID tells you to create abstractions, segregate interfaces, and invert dependencies. DRY/YAGNI/KISS tell you when those techniques are worth the complexity and when they are premature.

[[solid-principles|SOLID Principles]]

DRY drives code extraction into functions and modules. Understanding Python's module system helps you organize extracted code without creating circular dependencies.

[[modules|Modules]]

YAGNI is the counterweight to the Open/Closed Principle. OCP encourages designing for extension. YAGNI says do not build the extension points until you need them. The balance is to design code that is easy to refactor toward OCP when the need arises, without prematurely building the abstractions.

[[ocp|Open/Closed Principle]]

---

## Common Misconceptions

Misconception 1: "DRY means never have duplicate lines of code."
Reality: DRY is about knowledge duplication, not code duplication. Two identical loops that compute sales tax and shipping tax look the same but represent different business rules. If the tax authority changes sales tax rates, you do not want shipping tax to change too. Extracting them into a shared function creates coupling between unrelated concerns. Duplicated code is sometimes the correct design.

Misconception 2: "YAGNI means do not think about the future."
Reality: YAGNI means do not implement for the future. You should absolutely think about the future - design your code so it is easy to refactor when new requirements arrive. The distinction is between designing for extensibility (good: use clean interfaces, follow SRP) and implementing extensibility (bad: building a plugin system, a config-driven feature flag engine, and a migration framework before you have a second use case).

Misconception 3: "KISS means write the fewest lines of code."
Reality: KISS means write the clearest code. A one-line nested comprehension with three conditions is fewer lines but harder to understand than a five-line loop. KISS optimizes for readability and maintainability, not for line count. Code is read far more often than it is written.

---

## Why It Matters in Practice

These three principles are the most practical, day-to-day design heuristics a developer uses. Every code review involves judging: "Is this duplicated knowledge?" (DRY). "Do we need this right now?" (YAGNI). "Is there a simpler way?" (KISS). Getting these judgments right keeps codebases lean and navigable. Getting them wrong creates either spaghetti code (too little DRY) or astronaut architecture (too much premature abstraction).

The principles are especially important in fast-moving startups and agile environments where requirements change frequently. Over-built abstractions become technical debt when the feature they were built for is never shipped. Under-abstracted code becomes technical debt when business rules are scattered across twenty files. DRY, YAGNI, and KISS help you find the right balance for your specific context.

---

## Interview Angle

Common question forms:
- "What does DRY mean? Give an example of a DRY violation."
- "What is YAGNI and when would you apply it?"
- "How do you decide when code is too complex?"
- "These principles sometimes conflict - how do you resolve that?"

Answer frame:
Define all three with one-sentence explanations. Give a concrete DRY example (duplicated validation logic, fix with a shared function). Give a YAGNI example (building a plugin system for one implementation). Give a KISS example (nested comprehension vs simple loop). Address the tension: DRY says extract, YAGNI says wait. The heuristic is "rule of three" - extract when you see the same knowledge in three places, not two.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[modules|Modules]]
- [[ocp|Open/Closed Principle]]
- [[srp|Single Responsibility Principle]]
- [[oop-basics|OOP Basics]]
