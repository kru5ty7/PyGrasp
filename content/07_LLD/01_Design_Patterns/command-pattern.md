---
title: 12 - Command Pattern
description: The Command pattern encapsulates a request as an object, letting you parameterize methods with different requests, queue operations, log changes, and support undo/redo functionality.
tags: [design-patterns, command, behavioral, undo, queue, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Command Pattern

> The Command pattern turns a request into a standalone object containing all the information needed to perform the action, enabling queuing, logging, and undo.

---

## Quick Reference

**Core idea:**
- Encapsulate an action as an object with an `execute()` method (and optionally `undo()`)
- Decouples the **invoker** (what triggers the action) from the **receiver** (what performs the action)
- Enables: undo/redo, command queuing, macro recording, transaction logging
- In Python, callables (functions, lambdas, `functools.partial`) are lightweight commands
- Common in Python: task queues (Celery tasks are commands), CLI frameworks (Click), GUI undo systems

**Tricky points:**
- In Python, a simple callable often replaces a full Command class - use classes only when you need undo or state
- Commands should be self-contained: they carry all the data needed to execute
- Undo requires the command to store enough state to reverse its effect
- Command queues must handle failures: what happens when a command in the middle of a sequence fails?

---

## What It Is

Think of a restaurant's order ticket system. When a waiter takes your order, they write it on a ticket and clip it to the kitchen rail. The ticket is a command object. It contains everything the kitchen needs: what dish, which table, any modifications. The waiter (invoker) does not cook. The kitchen (receiver) does not interact with customers. The ticket (command) decouples them. Tickets can be queued (multiple orders on the rail), logged (duplicate copy for billing), undone (customer cancels before cooking), and replayed (re-fire a lost order).

The Command pattern encapsulates a request as an object. Instead of calling `editor.bold()` directly, you create a `BoldCommand` object that knows what text to bold and how to undo it. The editor stores commands in a history list. Undo pops the last command and calls its `undo()` method. Redo re-executes the command. The editor does not need to know what each command does - it just calls `execute()` and `undo()`.

In Python, first-class functions make simple commands trivial. Celery tasks, `concurrent.futures` callables, and Click CLI commands are all implementations of the Command pattern. Use a full command class when you need undo, when the command carries significant state, or when you need to serialize commands for logging or replay.

---

## How It Actually Works

A command object stores a reference to the receiver and the parameters for the action. The `execute()` method performs the action. The `undo()` method reverses it. The invoker stores commands and calls `execute()` without knowing the details.

```python
from abc import ABC, abstractmethod
from typing import Any
from dataclasses import dataclass, field


# Command interface
class Command(ABC):
    @abstractmethod
    def execute(self) -> None: ...

    @abstractmethod
    def undo(self) -> None: ...


# Receiver
class TextEditor:
    def __init__(self):
        self.content: str = ""
        self.clipboard: str = ""

    def insert(self, text: str, position: int) -> None:
        self.content = self.content[:position] + text + self.content[position:]

    def delete(self, start: int, end: int) -> str:
        deleted = self.content[start:end]
        self.content = self.content[:start] + self.content[end:]
        return deleted

    def __repr__(self) -> str:
        return f'Editor("{self.content}")'


# Concrete commands
class InsertCommand(Command):
    def __init__(self, editor: TextEditor, text: str, position: int):
        self._editor = editor
        self._text = text
        self._position = position

    def execute(self) -> None:
        self._editor.insert(self._text, self._position)

    def undo(self) -> None:
        self._editor.delete(self._position, self._position + len(self._text))


class DeleteCommand(Command):
    def __init__(self, editor: TextEditor, start: int, end: int):
        self._editor = editor
        self._start = start
        self._end = end
        self._deleted_text: str = ""

    def execute(self) -> None:
        self._deleted_text = self._editor.delete(self._start, self._end)

    def undo(self) -> None:
        self._editor.insert(self._deleted_text, self._start)


# Invoker with undo/redo support
class CommandHistory:
    def __init__(self):
        self._history: list[Command] = []
        self._redo_stack: list[Command] = []

    def execute(self, command: Command) -> None:
        command.execute()
        self._history.append(command)
        self._redo_stack.clear()  # new action invalidates redo history

    def undo(self) -> None:
        if not self._history:
            return
        command = self._history.pop()
        command.undo()
        self._redo_stack.append(command)

    def redo(self) -> None:
        if not self._redo_stack:
            return
        command = self._redo_stack.pop()
        command.execute()
        self._history.append(command)


# Usage
editor = TextEditor()
history = CommandHistory()

history.execute(InsertCommand(editor, "Hello", 0))
print(editor)  # Editor("Hello")

history.execute(InsertCommand(editor, " World", 5))
print(editor)  # Editor("Hello World")

history.execute(DeleteCommand(editor, 5, 11))
print(editor)  # Editor("Hello")

history.undo()
print(editor)  # Editor("Hello World") - undo delete

history.undo()
print(editor)  # Editor("Hello") - undo second insert

history.redo()
print(editor)  # Editor("Hello World") - redo second insert


# Pythonic: callable-based commands for simple cases
from functools import partial

class SimpleTaskQueue:
    def __init__(self):
        self._queue: list[tuple[str, Any]] = []

    def add(self, name: str, task: Any) -> None:
        self._queue.append((name, task))

    def run_all(self) -> list:
        results = []
        for name, task in self._queue:
            print(f"Running: {name}")
            results.append(task())
        self._queue.clear()
        return results

queue = SimpleTaskQueue()
queue.add("greet", lambda: "Hello!")
queue.add("compute", partial(pow, 2, 10))
results = queue.run_all()  # ["Hello!", 1024]
```

---

## How It Connects

Command encapsulates requests as objects, enabling undo/redo, queuing, and logging. It is a behavioral pattern that uses composition.

[[design-patterns-overview|Design Patterns Overview]]

Task queues like Celery serialize command objects (tasks) for asynchronous execution across processes and machines.

[[concurrent-futures|Concurrent Futures]]

Python's first-class functions and `functools.partial` provide lightweight command objects without class boilerplate.

[[first-class-functions|First Class Functions]]

[[partial-functions|Partial Functions]]

---

## Common Misconceptions

Misconception 1: "The Command pattern is just wrapping function calls in objects."
Reality: Simple commands are indeed wrapped function calls. The pattern's power emerges when you need undo (commands store state to reverse), queuing (commands are serializable objects), or macro recording (a sequence of commands stored for replay). Without these needs, a plain function is better.

Misconception 2: "Every action in my application should be a Command."
Reality: Command adds overhead (class definitions, history management). Use it for actions that need undo, queuing, or logging. Simple operations that will never be undone or replayed do not benefit from the pattern.

---

## Why It Matters in Practice

Undo/redo in text editors, graphic editors, and form builders all use the Command pattern. Task queues (Celery, RQ) serialize commands for distributed execution. CLI frameworks (Click) model subcommands as command objects. Understanding the pattern helps you design these systems and use these libraries effectively.

---

## Interview Angle

Common question forms:
- "What is the Command pattern?"
- "Implement undo/redo for a text editor."
- "How does the Command pattern relate to task queues?"

Answer frame:
Define Command as encapsulated request with `execute()` and `undo()`. Show the editor example with history. Explain how it enables undo, queuing, and logging. Mention Python's functional alternative for simple cases.

---

## Related Notes

- [[design-patterns-overview|Design Patterns Overview]]
- [[concurrent-futures|Concurrent Futures]]
- [[first-class-functions|First Class Functions]]
- [[partial-functions|Partial Functions]]
