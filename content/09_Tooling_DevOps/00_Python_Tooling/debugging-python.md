---
title: 09 - Debugging Python
description: "Python debugging spans the built-in pdb module for interactive stepping through code, the breakpoint() built-in for dropping into a debugger, post-mortem analysis of crashed processes, and VS Code's debugger which integrates with Python's debug adapter protocol."
tags: [debugging, pdb, ipdb, breakpoint, debugger, post-mortem, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Debugging Python

> Python debugging is the practice of pausing execution at arbitrary points to inspect state and step through code  -  from the built-in `pdb` interactive debugger to production post-mortem analysis of crashed processes.

---

## Quick Reference

**Core idea:**
- `breakpoint()`  -  drops into pdb (Python 3.7+); replaces the older `import pdb; pdb.set_trace()`
- `n` (next)  -  execute the current line and stop at the next line in the same frame
- `s` (step)  -  execute the current line, stepping into function calls
- `c` (continue)  -  resume execution until the next breakpoint or end of program
- `l` (list)  -  show surrounding source code
- `p expr` / `pp expr`  -  print / pretty-print an expression
- `bt` (backtrace)  -  print the full call stack from the current frame

**Tricky points:**
- `n` and `s` differ at function calls: `n` steps over (executes the called function as a unit), `s` steps into (enters the called function)
- `q` (quit) raises `BdbQuit` and exits  -  it does not cleanly resume; use `c` to continue past the last breakpoint
- `PYTHONBREAKPOINT=0` disables all `breakpoint()` calls without changing code  -  useful to run without debugger stopping in test suites
- `PYTHONBREAKPOINT=ipdb.set_trace` redirects `breakpoint()` to ipdb  -  works without changing any code
- `pdb.pm()` (post-mortem) debugs the most recent uncaught exception's traceback  -  extremely useful for analyzing crashes

---

## What It Is

Debugging is the process of systematically understanding why a program does not behave as expected. The most primitive debugging tool is `print()`  -  insert a print statement, run the program, observe the output, remove the print statement. This works, but it is slow, clutters the code, and gives no interactivity. A debugger is a more powerful alternative: it pauses program execution at specified points and opens a REPL-like interface where the developer can inspect variables, evaluate expressions, and step through code one line at a time.

Python's built-in debugger is `pdb` (Python Debugger). It is implemented entirely in Python, ships with the standard library, and works everywhere CPython runs  -  no installation required, no editor integration required, just an interpreter and a terminal. The `breakpoint()` built-in (added in Python 3.7) provides a clean, configurable way to drop into the debugger: it calls `sys.breakpointhook()`, which by default calls `pdb.set_trace()`, but can be redirected to any debugger by setting the `PYTHONBREAKPOINT` environment variable.

The mental model for pdb is that the debugger is a second interpreter running alongside your program. When execution reaches a breakpoint, control transfers to the debugger's prompt. The developer is now operating on the live program state  -  all variables in scope are accessible, expressions can be evaluated, and the developer can move through the call stack to inspect frames from different function invocations.

---

## How It Actually Works

The key pdb commands form a short vocabulary that covers most debugging needs:

```
(Pdb) n       # next line (step over function calls)
(Pdb) s       # step into the next function call
(Pdb) c       # continue until next breakpoint
(Pdb) l       # list source code around current line
(Pdb) l 1,20  # list lines 1 to 20
(Pdb) p x     # print the value of variable x
(Pdb) pp data # pretty-print data (useful for dicts/lists)
(Pdb) bt      # backtrace  -  print the full call stack
(Pdb) u       # move up one frame in the call stack
(Pdb) d       # move down one frame in the call stack
(Pdb) b 42    # set a breakpoint at line 42
(Pdb) b mymodule.py:42  # breakpoint in a specific file
(Pdb) b func_name  # breakpoint at the start of a function
(Pdb) cl      # clear all breakpoints
(Pdb) q       # quit the debugger
```

Dropping into pdb at a specific point in code:

```python
def process_order(order):
    items = validate_items(order.items)
    breakpoint()  # execution pauses here
    total = calculate_total(items)
    return total
```

**Post-mortem debugging** is valuable when a program crashes and you want to inspect the state at the point of the exception. `pdb.pm()` (post-mortem) enters the debugger at the frame where the most recent uncaught exception was raised:

```python
import pdb

def main():
    data = load_data("file.json")  # raises FileNotFoundError
    process(data)

try:
    main()
except Exception:
    pdb.pm()  # drops into pdb at the point of the exception
```

This is also achievable from the command line for entire scripts:

```bash
python -m pdb script.py  # runs script under pdb control
# On unhandled exception, pdb enters post-mortem mode
```

**ipdb** is a drop-in pdb replacement that adds syntax highlighting, tab completion, and the IPython REPL experience:

```bash
pip install ipdb
PYTHONBREAKPOINT=ipdb.set_trace python script.py
```

**VS Code debugger** integrates with Python's Debug Adapter Protocol (DAP). The debugger server runs inside the Python process (via `debugpy`), and VS Code connects to it over a socket. This provides GUI breakpoints, variable inspection panels, and call stack navigation without using the terminal pdb interface. The underlying mechanism is the same  -  `sys.settrace` callbacks  -  but with a richer UI.

A `launch.json` for VS Code:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python: Current File",
            "type": "python",
            "request": "launch",
            "program": "${file}",
            "console": "integratedTerminal"
        },
        {
            "name": "Python: Remote Attach",
            "type": "python",
            "request": "attach",
            "connect": {"host": "localhost", "port": 5678}
        }
    ]
}
```

---

## How It Connects

The Python interpreter loop is what pdb pauses  -  understanding how CPython executes bytecode explains why the debugger can stop at specific lines (bytecode instructions have line number metadata).

[[interpreter-loop|The Interpreter Loop]]

Profiling and debugging are complementary: debugging finds incorrect behavior, profiling finds slow-but-correct behavior.

[[profiling-python|Profiling Python Code]]

In pytest, `--pdb` flag drops into pdb on test failure: `pytest --pdb tests/`  -  the debugger opens at the point of failure in the failing test.

[[pytest|Pytest]]

---

## Common Misconceptions

Misconception 1: "I should just add `print()` statements because pdb is complicated."
Reality: pdb's command vocabulary is ten commands: n, s, c, l, p, pp, bt, u, d, q. These take 5 minutes to learn. pdb provides access to the live program state  -  arbitrary expressions, the full call stack, the ability to change variables mid-execution. print-based debugging requires re-running the program for each observation, cannot navigate the call stack, and clutters the code with statements to later remove.

Misconception 2: "The VS Code debugger is fundamentally different from pdb."
Reality: The VS Code debugger uses `debugpy`, which implements the Debug Adapter Protocol on top of Python's `sys.settrace`  -  the same mechanism pdb uses. When you set a breakpoint in VS Code and hit it, the underlying mechanism is identical to `breakpoint()` dropping into pdb. The UI is different; the mechanism is the same.

Misconception 3: "Post-mortem debugging is only useful after a crash  -  I can only use it when something went wrong."
Reality: Post-mortem debugging is also a workflow for analyzing the state at any point. Raising an exception intentionally (e.g., `raise Exception("inspect here")`) and catching it to call `pdb.pm()` is a valid debugging strategy for inspecting complex state that is hard to pause interactively.

---

## Why It Matters in Practice

Learning pdb commands pays dividends in every context where a GUI debugger is unavailable: SSH sessions on remote servers, debugging inside Docker containers, post-mortem analysis of production crashes from saved tracebacks. A developer who relies exclusively on IDE-integrated debuggers finds debugging in those environments awkward. A developer who knows pdb is equally productive in a terminal as in a GUI.

The `pytest --pdb` integration is particularly valuable: a failing test drops directly into the debugger at the assertion failure, with all test fixtures in scope. Instead of adding print statements, re-running tests, and repeating, the developer interactively inspects what `expected` and `actual` actually contain and why they differ.

---

## Interview Angle

Common question forms:
- "How do you debug a Python application?"
- "What is the difference between stepping over and stepping into in a debugger?"

Answer frame:
A strong answer covers the full spectrum: `breakpoint()` for interactive development, `n`/`s` distinction (step over vs step into), `bt` for call stack inspection, and `pdb.pm()` for post-mortem analysis. Mentioning `pytest --pdb` and `PYTHONBREAKPOINT=ipdb.set_trace` demonstrates practical depth beyond basic knowledge. Noting that VS Code's debugger uses the same underlying `sys.settrace` mechanism shows understanding of how the tool works, not just how to use it.

---

## Related Notes

- [[profiling-python|Profiling Python Code]]
- [[interpreter-loop|The Interpreter Loop]]
- [[pytest|Pytest]]
