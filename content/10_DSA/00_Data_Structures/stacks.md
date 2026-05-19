---
title: 05 - Stacks
description: A stack is a LIFO (Last In, First Out) structure where all insertions and removals happen at one end, called the top.
tags: [dsa, layer-10, stack, lifo]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Stacks

> The stack is one of the most fundamental abstractions in computing - it is the structure that makes function calls, expression evaluation, and undo history all work.

---

## Quick Reference

**Core idea:**
- LIFO: the last item pushed onto the stack is the first item popped off
- Three core operations: push (add to top), pop (remove from top), peek (read top without removing)
- All three operations are O(1) - the top is always directly accessible
- Python implementation: use `list` with `append` for push and `pop()` for pop
- The call stack is a stack - each function call pushes a frame; return pops it

**Tricky points:**
- `pop()` on an empty stack raises `IndexError` - always check before popping or handle the exception
- Peek is `lst[-1]` in Python, not a dedicated method on lists
- A stack overflow occurs when the call stack grows too deep - Python's default recursion limit is 1000
- Do not use `list.pop(0)` for a stack - that is O(n) and pops the wrong end; use `list.pop()` (no argument)
- For thread-safe usage, `queue.LifoQueue` is the correct choice over a raw list

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Push | O(1) amortized | O(n) on resize |
| Pop | O(1) | O(1) |
| Peek | O(1) | O(1) |
| Search | O(n) | O(n) |
| Is Empty | O(1) | O(1) |

Space complexity: O(n)

---

## What It Is

Think of a stack of cafeteria trays. When clean trays are returned from the dishwasher, they are placed on top of the pile. When a student comes to collect a tray, they take from the top. The tray that was returned most recently is the first one taken. The tray at the very bottom of the stack - the one put there when the cafeteria opened - might sit undisturbed for the entire lunch service. There is only one access point: the top.

This single-access constraint might seem like a limitation, but it turns out to describe a pattern that appears everywhere in computing. When you call a function inside another function, the computer needs to remember where to return after the inner function finishes. It pushes the return address and local variables onto the call stack. When the inner function returns, those values are popped, and execution resumes exactly where it left off. If that inner function calls yet another function, another frame is pushed on top. The call stack is a real, physical stack in your computer's memory, and it is why deeply recursive programs can crash with a "stack overflow" error - the stack runs out of space because too many frames have been pushed without being popped.

The LIFO property is exactly what makes parenthesis matching work. When you scan `(({[()]})` and encounter an opening bracket, you push it. When you encounter a closing bracket, you pop the top and check whether it matches. The most recent unmatched opening bracket is always the one on top - LIFO ensures they are checked in the correct order. Any algorithm where you need to process things in reverse order of when you encountered them is a candidate for a stack.

---

## How It Actually Works

In Python, a stack is implemented directly on top of a `list`. Lists support O(1) amortized `append` (push) and O(1) `pop()` with no arguments (which removes and returns the last element). No additional wrapper class is necessary, though wrapping provides a cleaner interface and protects the bottom-of-stack from accidental access.

The internal mechanics are those of a dynamic array: elements are stored contiguously, and `pop()` decrements the length counter without moving any data. Push uses `append`, which places the new element at the end of the array and increments the length. The only non-constant case is when `append` triggers a resize, which is amortized over many operations.

```python
# Minimal stack using a Python list
stack = []
stack.append(10)   # push
stack.append(20)
stack.append(30)

top = stack[-1]    # peek - O(1), no removal
print(top)         # 30

value = stack.pop()  # pop - O(1), removes and returns 30
print(value)         # 30
print(stack)         # [10, 20]


# Wrapped stack class for safer interface
class Stack:
    def __init__(self):
        self._data = []

    def push(self, item):
        self._data.append(item)

    def pop(self):
        if self.is_empty():
            raise IndexError("pop from empty stack")
        return self._data.pop()

    def peek(self):
        if self.is_empty():
            raise IndexError("peek at empty stack")
        return self._data[-1]

    def is_empty(self):
        return len(self._data) == 0

    def __len__(self):
        return len(self._data)


# Application 1: balanced parentheses checker
def is_balanced(s):
    stack = Stack()
    matching = {')': '(', '}': '{', ']': '['}
    for char in s:
        if char in '({[':
            stack.push(char)
        elif char in ')}]':
            if stack.is_empty() or stack.pop() != matching[char]:
                return False
    return stack.is_empty()

print(is_balanced("({[]})"))   # True
print(is_balanced("({[})"))    # False


# Application 2: evaluate postfix expression
def eval_postfix(tokens):
    stack = Stack()
    ops = {'+': lambda a, b: a + b,
           '-': lambda a, b: a - b,
           '*': lambda a, b: a * b,
           '/': lambda a, b: a / b}
    for token in tokens:
        if token in ops:
            b, a = stack.pop(), stack.pop()
            stack.push(ops[token](a, b))
        else:
            stack.push(float(token))
    return stack.pop()

# "3 4 + 2 *" = (3+4)*2 = 14
print(eval_postfix(["3", "4", "+", "2", "*"]))  # 14.0


# Application 3: iterative DFS using explicit stack
def dfs_iterative(graph, start):
    visited = set()
    stack = [start]
    order = []
    while stack:
        node = stack.pop()
        if node not in visited:
            visited.add(node)
            order.append(node)
            for neighbour in graph.get(node, []):
                if neighbour not in visited:
                    stack.append(neighbour)
    return order

graph = {0: [1, 2], 1: [3], 2: [3], 3: []}
print(dfs_iterative(graph, 0))  # [0, 2, 3, 1] (order depends on neighbour order)
```

---

## Visualizer

<iframe src="/static/visualizers/stack.html" style="width:100%;height:380px;border:none;border-radius:8px;" title="Stack Visualizer"></iframe>

---

## How It Connects

The call stack is the most pervasive stack in computing, and it is precisely what makes recursion possible. Every recursive function call pushes a new frame; every return pops one. Understanding the call stack explains both how recursion works and why stack overflow errors occur at deep recursion depths.

[[call-stack|Call Stack]]

DFS (depth-first search) on a graph is naturally implemented with a stack - either explicitly (as shown above) or implicitly through recursive calls. Understanding the stack as the mechanism behind DFS makes it easier to convert recursive DFS to iterative when recursion depth is a concern.

[[dfs|Depth-First Search]]

---

## Common Misconceptions

Misconception 1: "A stack is a restricted list - it is less useful because you can only access one end."
Reality: The restriction is the point. Forcing all access through one end is what gives the LIFO property, which is precisely what balanced-parentheses checking, function call management, undo history, and DFS require. A structure with unrestricted access does not have that property.

Misconception 2: "Python's `list` is not a stack - I should use a dedicated stack class."
Reality: Python's `list` with `append` and `pop()` (no argument) is a perfectly efficient stack. `append` is O(1) amortized, `pop()` is O(1) exactly. The only reason to wrap it in a class is for interface clarity or to prevent accidental access to elements other than the top.

Misconception 3: "Stack overflow only happens in recursive programs."
Reality: Any deep call chain - recursive or not - can exhaust the call stack. A long chain of mutually calling functions, event callbacks, or deeply nested framework calls can also overflow the stack. Python's limit of 1000 frames (by default, adjustable with `sys.setrecursionlimit`) applies to all call depth, not only explicit recursion.

---

## Why It Matters in Practice

Stacks are directly used in parsers, compilers, and interpreters. When a Python program is compiled, the bytecode interpreter uses a value stack to evaluate expressions. Undo/redo functionality in any application is a pair of stacks - the undo stack holds operations to be reversed, and the redo stack holds operations that were undone. Browser navigation history is also a stack (the back button pops the current page; visiting a new page pushes it).

The ability to convert recursive algorithms to iterative ones using an explicit stack is a practical skill. Recursive algorithms can hit Python's recursion limit on deep inputs; rewriting them iteratively with an explicit stack eliminates that constraint. This is a direct requirement in production code that processes trees, parses structured data, or traverses graphs.

---

## Interview Angle

Common question forms:
- "Implement a stack using a queue."
- "Design a stack that supports O(1) min() in addition to push and pop."
- "Evaluate a postfix expression."
- "Check if a string of brackets is balanced."
- "Implement iterative inorder traversal of a binary tree."

Answer frame:
For balanced brackets, describe the push-on-open, pop-and-match-on-close pattern, then handle the edge cases: empty stack on closing bracket, and non-empty stack at end. For the min-stack problem, describe maintaining a parallel stack of minimums - push the current min alongside each element, pop in sync. For iterative tree traversal, sketch the stack state after one or two pushes to demonstrate you understand the order.

---

## Related Notes

- [[queues|Queues]]
- [[call-stack|Call Stack]]
- [[dfs|Depth-First Search]]
