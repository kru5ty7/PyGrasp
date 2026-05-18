---
title: 08 - Single Responsibility Principle
description: A class should have only one reason to change - meaning it should encapsulate exactly one responsibility, so that changes to one concern do not force changes to unrelated code.
tags: [oop, solid, srp, cohesion, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Single Responsibility Principle

> A class should have only one reason to change - it should do one thing, own one responsibility, and encapsulate one axis of change.

---

## Quick Reference

**Core idea:**
- SRP says a class should have exactly one **reason to change** - one stakeholder or business concern that drives modifications
- "Responsibility" does not mean "one method" - it means one cohesive concern (e.g., user persistence, input validation, report formatting)
- A class that handles both database access and email sending has two reasons to change: database schema changes and email template changes
- SRP is about **cohesion** - methods in a class should be related to the same concern
- Splitting responsibilities produces smaller classes that are easier to test, name, and reason about

**Tricky points:**
- SRP does not mean one method per class - an `HTTPClient` with `get()`, `post()`, `put()`, `delete()` has one responsibility: HTTP communication
- The "reason to change" depends on context - in a small startup, one developer owns everything and SRP is less critical; in a large team with specialized roles, SRP prevents merge conflicts and cross-team dependencies
- Over-splitting creates class explosion - dozens of tiny classes with one method each, connected by excessive indirection
- SRP applies to modules and functions too, not just classes

---

## What It Is

Think of a restaurant kitchen. The head chef does not wash dishes, take orders from tables, manage the budget, and cook all the food. Each role has one responsibility: the dishwasher washes, the server takes orders, the accountant manages money, and the chef cooks. If the restaurant changes its menu, only the chef needs to adapt. If the restaurant changes its billing system, only the accountant needs to learn the new software. Each person changes for one reason, and changes in one area do not disrupt other areas.

When a class has multiple responsibilities, changing one of them risks breaking the others. Consider a `UserManager` class that validates user input, writes users to a database, sends welcome emails, and generates user reports. If the email provider changes from SendGrid to Mailgun, you open the `UserManager` class and modify it. But the class also contains database logic, and while editing the file you might accidentally break a query. Even without introducing bugs, the class is harder to test: to test the validation logic, you need to mock the database, the email sender, and the report generator.

SRP says to separate these responsibilities into focused classes. A `UserValidator` validates input. A `UserRepository` handles database operations. A `WelcomeEmailSender` sends emails. A `UserReportGenerator` builds reports. Each class is independently testable, independently deployable, and changes for exactly one reason. The `UserService` class then composes these components, coordinating the workflow without containing any of the implementation details.

The judgment call is where to draw the boundary. "One responsibility" is not a precise metric. A `FileWriter` that opens a file, writes content, and closes it has one responsibility (file I/O), even though it involves three operations. A `UserService` that validates, saves, and sends a notification might have one responsibility (user creation workflow) or three, depending on how independently these concerns evolve. The test is: when this code needs to change, what kind of change triggers it? If different kinds of changes (database schema changes vs email template changes) affect the same class, it has too many responsibilities.

---

## How It Actually Works

SRP violations are easy to detect by looking at a class's imports. If a class imports `sqlite3`, `smtplib`, `jinja2`, and `logging`, it is likely doing too many things. Each import represents a dependency on a different subsystem, and each subsystem is a potential source of change.

Another diagnostic is method grouping. If a class's methods naturally cluster into groups that do not call each other (validation methods never call email methods, database methods never call report methods), those groups are separate responsibilities sharing a class for convenience rather than cohesion.

```python
# BEFORE: SRP violation - Report class does formatting AND persistence AND delivery
class Report:
    def __init__(self, title: str, data: list[dict]):
        self.title = title
        self.data = data

    def generate_html(self) -> str:
        rows = "".join(
            f"<tr><td>{r['name']}</td><td>{r['value']}</td></tr>"
            for r in self.data
        )
        return f"<html><h1>{self.title}</h1><table>{rows}</table></html>"

    def generate_csv(self) -> str:
        lines = ["name,value"]
        lines.extend(f"{r['name']},{r['value']}" for r in self.data)
        return "\n".join(lines)

    def save_to_file(self, path: str, format: str = "html") -> None:
        content = self.generate_html() if format == "html" else self.generate_csv()
        with open(path, "w") as f:
            f.write(content)

    def email_report(self, to: str) -> None:
        import smtplib
        html = self.generate_html()
        # ... email sending logic ...


# AFTER: Each class has one responsibility

class ReportData:
    """Holds report data. Changes when data structure changes."""
    def __init__(self, title: str, data: list[dict]):
        self.title = title
        self.data = data


class HTMLFormatter:
    """Formats reports as HTML. Changes when HTML layout changes."""
    def format(self, report: ReportData) -> str:
        rows = "".join(
            f"<tr><td>{r['name']}</td><td>{r['value']}</td></tr>"
            for r in report.data
        )
        return f"<html><h1>{report.title}</h1><table>{rows}</table></html>"


class CSVFormatter:
    """Formats reports as CSV. Changes when CSV format changes."""
    def format(self, report: ReportData) -> str:
        lines = ["name,value"]
        lines.extend(f"{r['name']},{r['value']}" for r in report.data)
        return "\n".join(lines)


class FileExporter:
    """Saves content to files. Changes when storage mechanism changes."""
    def export(self, content: str, path: str) -> None:
        with open(path, "w") as f:
            f.write(content)


class EmailSender:
    """Sends emails. Changes when email provider changes."""
    def __init__(self, smtp_host: str):
        self._host = smtp_host

    def send(self, to: str, subject: str, body: str) -> None:
        print(f"Sending '{subject}' to {to} via {self._host}")


# Composition: the service coordinates but contains no implementation details
class ReportService:
    """Orchestrates report workflow. Changes when workflow steps change."""
    def __init__(
        self,
        formatter: HTMLFormatter | CSVFormatter,
        exporter: FileExporter,
        emailer: EmailSender,
    ):
        self._formatter = formatter
        self._exporter = exporter
        self._emailer = emailer

    def generate_and_send(self, report: ReportData, path: str, email_to: str) -> None:
        content = self._formatter.format(report)
        self._exporter.export(content, path)
        self._emailer.send(email_to, f"Report: {report.title}", content)
```

---

## How It Connects

SRP is the first SOLID principle and the foundation for the others. If a class has multiple responsibilities, it is harder to keep it open for extension (OCP), harder to ensure subclasses are substitutable (LSP), and harder to segregate interfaces (ISP).

[[solid-principles|SOLID Principles]]

SRP naturally leads to composition. When you split responsibilities into separate classes, the coordinating class composes them rather than inheriting from them.

[[composition-over-inheritance|Composition Over Inheritance]]

In Python, modules serve as a natural boundary for SRP. A module that contains related classes and functions for one concern (e.g., `repositories.py`, `validators.py`, `notifications.py`) follows SRP at the module level.

[[modules|Modules]]

---

## Common Misconceptions

Misconception 1: "SRP means a class should have only one method."
Reality: SRP means one **reason to change**, not one method. An `HTTPClient` with `get()`, `post()`, `put()`, `delete()`, and `head()` methods has one responsibility: HTTP communication. All methods change for the same reason (HTTP protocol changes, connection handling changes). Splitting each HTTP method into its own class would violate common sense without improving the design.

Misconception 2: "If I follow SRP, I will end up with hundreds of tiny classes."
Reality: Over-applying SRP does cause class explosion, and that is a real problem. The antidote is to define responsibilities at the right granularity. "User persistence" is a responsibility. "Writing the INSERT query" is too granular. Use the "reason to change" test: would a change to X require modifying this class even though it has nothing to do with X? If yes, split. If no, the class is cohesive enough.

---

## Why It Matters in Practice

SRP violations are the most common cause of merge conflicts in team environments. When two developers modify the same God class for unrelated reasons - one is fixing validation logic while another is updating the email template - they create a merge conflict in a file where neither change is related to the other. SRP eliminates this by ensuring each concern lives in its own file.

SRP also dramatically improves testability. Testing a `UserValidator` in isolation requires zero mocks - just pass in a string and check the result. Testing a `UserManager` that validates, persists, emails, and logs requires mocking four subsystems for every single test case.

---

## Interview Angle

Common question forms:
- "What is the Single Responsibility Principle?"
- "Look at this class - does it violate SRP? How would you refactor it?"
- "How do you decide where to draw the boundary for a responsibility?"

Answer frame:
Define SRP as one reason to change. Give the God class example (validates + persists + emails). Refactor by extracting each concern into its own class. Explain the benefits: independent testing, reduced merge conflicts, easier navigation. Mention the over-application risk and how to calibrate the right granularity.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[modules|Modules]]
- [[ocp|Open/Closed Principle]]
- [[oop-basics|OOP Basics]]
