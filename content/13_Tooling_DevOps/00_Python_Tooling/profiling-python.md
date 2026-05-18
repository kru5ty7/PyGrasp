---
title: 08 - Profiling Python Code
description: "Profiling is the measurement of where a Python program spends its time and memory, using tools like cProfile for deterministic call-count profiling, line_profiler for line-level timing, and py-spy for low-overhead sampling on running processes."
tags: [profiling, cprofile, performance, optimization, line-profiler, py-spy, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Profiling Python Code

> Profiling is measuring where your program's time and memory actually go  -  because developer intuition about performance bottlenecks is reliably wrong, and optimizing without measurement is the definition of premature optimization.

---

## Quick Reference

**Core idea:**
- `python -m cProfile -o output.prof script.py`  -  runs the deterministic profiler, saves results
- `python -m pstats output.prof`  -  interactive stats viewer for cProfile output
- `@profile` decorator from `line_profiler`  -  profiles a specific function line by line
- `py-spy top --pid PID`  -  attaches to a running Python process, sampling profiler, no code changes
- `memory_profiler` `@profile` decorator  -  measures per-line memory usage
- **Profile before optimizing**  -  guess wrong 90% of the time; measure to know where to spend effort

**Tricky points:**
- cProfile uses deterministic profiling  -  it intercepts every function call, which adds overhead and can change timing ratios
- `pstats` sort options: `cumulative` (total time including callees, identifies entry points), `tottime` (time in function only, identifies hot functions)
- py-spy is a sampling profiler  -  it samples the call stack at intervals without modifying the Python process; minimal overhead, safe for production
- Amdahl's Law: if a function takes 10% of total runtime, optimizing it to zero saves at most 10%  -  profile to find functions that dominate total time
- CPython's GIL means profiling multithreaded Python shows only one thread's perspective in most profilers; py-spy handles this better

---

## What It Is

Optimization without profiling is guessing. Human intuition about where programs spend their time is systematically wrong  -  we suspect the complex algorithm, but the hot path is almost always something simpler: a database query called in a loop, a string serialization happening on every request, a library function with unexpected overhead. Profiling is the discipline of measuring before acting, replacing speculation with data.

There are two categories of Python profilers: deterministic profilers and sampling profilers. A deterministic profiler, like cProfile, instruments the program by intercepting every function call and return using Python's tracing API (`sys.settrace`). It records exact call counts and precise time measurements for every function. The cost is overhead  -  the measurement itself slows the program down, sometimes significantly, because the tracing hook is called on every function call. Deterministic profiling is best used in development, not production.

A sampling profiler, like py-spy, works differently. It runs as an external process and periodically reads the call stack of the target Python process from outside  -  by inspecting the process's memory directly. It does not modify the Python program, inject any instrumentation, or use `sys.settrace`. The overhead is essentially zero, and it can be attached to a running production process without restarting it. The trade-off is resolution  -  sampling only approximates where time is spent; very short functions that run infrequently may not appear in the profile. For identifying the dominant bottlenecks in real production traffic, sampling profilers are the right tool.

---

## How It Actually Works

**cProfile** is the standard library deterministic profiler. It produces a report of every function called during the profiled execution, with call counts and cumulative/self timing:

```bash
# Profile a script
python -m cProfile -s cumulative script.py

# Profile and save to file for later inspection
python -m cProfile -o profile.prof script.py

# Inspect saved profile
python -m pstats profile.prof
# (pstats) sort cumulative
# (pstats) stats 20
```

To profile a specific section of code programmatically:

```python
import cProfile
import pstats

profiler = cProfile.Profile()
profiler.enable()

# ... code to profile ...

profiler.disable()
stats = pstats.Stats(profiler)
stats.sort_stats("cumulative")
stats.print_stats(20)
```

**line_profiler** adds line-level granularity for a specific function:

```python
# Install: pip install line_profiler
# Decorate the function to profile
@profile  # injected by the line_profiler runner
def process_records(records):
    result = []
    for record in records:           # line 4
        parsed = parse(record)       # line 5
        validated = validate(parsed) # line 6
        result.append(validated)     # line 7
    return result

# Run with: kernprof -l -v script.py
```

The output shows each line's hit count, total time, and percentage of the function's time  -  making it immediately clear which line is the bottleneck.

**py-spy** requires no code changes and attaches to any running Python process:

```bash
# Install: pip install py-spy
# Live top-like view of a running process
py-spy top --pid 12345

# Record a flamegraph for offline analysis
py-spy record -o profile.svg --pid 12345

# Profile a script from start (no pid needed)
py-spy record -o profile.svg -- python script.py
```

**memory_profiler** tracks memory usage line by line, useful for finding memory leaks:

```python
# Install: pip install memory_profiler
@profile
def load_data(path):
    with open(path) as f:
        data = f.read()        # line 3
    records = parse(data)      # line 4
    return records             # line 5

# Run with: python -m memory_profiler script.py
```

---

## How It Connects

Understanding the interpreter loop clarifies why Python profiling shows what it does  -  function calls are expensive in CPython because they create frame objects, which is why cProfile's call-count data is meaningful.

[[interpreter-loop|The Interpreter Loop]]

Profiling async code requires async-aware profilers  -  standard cProfile misses time spent in the event loop, making it look like async functions are fast when they are actually waiting.

[[asyncio|Asyncio]]

Debugging and profiling are complementary: debugging finds where the code is wrong, profiling finds where correct code is slow.

[[debugging-python|Debugging Python]]

---

## Common Misconceptions

Misconception 1: "I can guess where the bottleneck is by reading the code."
Reality: Experienced developers consistently misjudge where programs spend their time. The bottleneck is usually in a different function than expected, or in a library call that appears trivial. Profile first, then optimize the function that cProfile or py-spy identifies as the dominant contributor to runtime.

Misconception 2: "cProfile overhead is negligible and safe for production."
Reality: cProfile uses Python's `sys.settrace` hook, which is called on every function call and return. For a program with many function calls, this overhead can slow execution by 10 - 100x. It is a development tool, not a production tool. For production profiling, use py-spy (sampling, zero-instrumentation) or a purpose-built APM tool.

Misconception 3: "Optimizing the slowest function always makes the program significantly faster."
Reality: Amdahl's Law governs this. If function X takes 5% of total runtime, optimizing it to run 10x faster saves only 4.5% of total runtime. The largest gains come from optimizing functions that dominate total runtime  -  typically 60 - 90% of time in 1 - 3 functions. Sorting cProfile output by `cumulative` time reveals these dominators.

---

## Why It Matters in Practice

The professional practice of performance work is: measure, identify the dominant contributor, optimize it, measure again. Each iteration is driven by data. A developer who profiles before optimizing will spend 2 hours making a program 40% faster. A developer who optimizes by intuition will spend 2 hours making it 2% faster, having worked on the wrong function.

In web services, profiling typically reveals that database query time dominates response time. The Python code path itself is fast; the bottleneck is N+1 query patterns, missing indexes, or unoptimized SQL. A cProfile run on a slow request will show most time in database driver calls, directing effort to query optimization rather than Python-level micro-optimization.

---

## Interview Angle

Common question forms:
- "How would you diagnose a slow Python service?"
- "What profiling tools do you use and when?"

Answer frame:
A strong answer distinguishes deterministic (cProfile, line_profiler) from sampling profilers (py-spy), explains when to use each (development vs production), and mentions Amdahl's Law as the framework for deciding what to optimize. Describing a real workflow  -  profile, find dominant function, optimize, re-profile  -  demonstrates practical experience.

---

## Related Notes

- [[debugging-python|Debugging Python]]
- [[interpreter-loop|The Interpreter Loop]]
- [[asyncio|Asyncio]]
