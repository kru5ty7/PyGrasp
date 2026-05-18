---
title: 04 - Black
description: "Black is an opinionated Python code formatter that enforces a single style with no meaningful configuration, eliminating formatting debates by applying deterministic transformations to Python's AST and re-serializing it."
tags: [black, formatter, code-style, ast, opinionated, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Black

> Black is "the uncompromising Python code formatter"  -  it takes your code, parses it to an AST, and re-serializes it into a single canonical form, removing all formatting decisions from the developer's hands and from code review discussions.

---

## Quick Reference

**Core idea:**
- `black .`  -  format all Python files in the current directory in place
- `black --check .`  -  check without modifying; exits non-zero if any file would change (for CI)
- `black --diff .`  -  show what would change without modifying files
- Default line length is 88 characters (the only intentionally chosen parameter)
- Configuration only in `pyproject.toml` under `[tool.black]`; Black intentionally has almost no options
- The "magic trailing comma"  -  a trailing comma in a collection forces Black to keep it expanded across multiple lines

**Tricky points:**
- Black does not enforce naming conventions, import order, or code logic  -  it only handles whitespace, quotes, and structural formatting
- Single-quoted strings are converted to double-quoted strings  -  this is not configurable and is a frequent initial surprise
- The `--skip-string-normalization` flag (`-S`) disables quote normalization if a project uses single quotes throughout
- Black is deterministic: formatting an already-formatted file produces identical output  -  `black black-formatted.py` is a no-op
- `# fmt: off` / `# fmt: on` markers disable Black for a code region  -  use sparingly

---

## What It Is

Black is best understood through its philosophical stance, not its technical behavior. Most formatters offer configuration: line length, quote style, whether to add trailing commas, how to handle blank lines. Black offers almost none of that. Its creators made this choice deliberately: the goal is not to enforce any particular style, but to eliminate the existence of style decisions entirely. When there is only one way the formatter will produce output, there is nothing to configure, and therefore nothing to debate in code review.

The analogy is a rigid mold. You pour code into Black and it comes out in a specific shape. Every developer on the team, every IDE, every CI run uses the same mold. The result is that all Python code formatted by Black looks the same, regardless of who wrote it. This has a profound effect on code review: formatting becomes a non-issue. Reviewers and authors stop commenting on whitespace, parenthesis placement, and quote style because the formatter decided all of that before the PR was even opened.

Black's approach differs from `autopep8`, which is a conservative formatter that makes the minimum changes necessary to comply with PEP 8. autopep8 will correct obvious violations but leave ambiguous style choices alone. Black, by contrast, reformats everything  -  it does not distinguish between "wrong" and "could be improved." Every file it touches is reformatted into Black's canonical form, even if it was already PEP 8 compliant.

---

## How It Actually Works

Black's pipeline is: parse the Python source file into a concrete syntax tree using Python's own `ast` module (or `lib2to3` in older versions), transform the CST into Black's internal IR, apply formatting rules, and serialize back to source text. Critically, Black does not do string manipulation  -  it never applies regex substitutions to source code. It works at the AST level, which means formatting changes cannot alter the semantics of the program. If Black would produce semantically different output, it raises an error rather than writing the file.

The 88-character line length was chosen because it is wider than PEP 8's recommended 79 but short enough to fit two files side by side on modern monitors at common font sizes. Black will try to fit expressions on one line, but will "explode" them to multiple lines if the result exceeds 88 characters:

```python
# Input (by a human)
result = some_function(argument_one, argument_two, argument_three, argument_four)

# Output if it fits on one line (under 88 chars)  -  stays on one line

# Output if it does not fit  -  Black explodes to one argument per line
result = some_function(
    argument_one,
    argument_two,
    argument_three,
    argument_four,
)
```

The "magic trailing comma" is the mechanism that lets developers communicate intent to Black. Adding a trailing comma to a collection tells Black: "I want this expanded, even if it would fit on one line."

```python
# No trailing comma: Black may collapse to one line
data = {"key": "value", "other": "thing"}

# With trailing comma: Black keeps it expanded
data = {
    "key": "value",
    "other": "thing",
}
```

In `pyproject.toml`:

```toml
[tool.black]
line-length = 88
target-version = ["py311"]
```

---

## How It Connects

Ruff's formatter is designed to be Black-compatible  -  on most codebases, switching from Black to `ruff format` produces identical output, and the two tools share the same philosophy of minimal configuration.

[[ruff|Ruff]]

Black and isort can conflict because Black may reformat import blocks in a way that isort then wants to change. The standard resolution is to use `isort` with `profile = "black"` or to replace both with Ruff's `I` rules.

[[isort|isort]]

Pre-commit hooks run Black automatically on staged files before each commit, enforcing formatting at the source rather than relying on developer memory.

[[pre-commit|Pre-commit Hooks]]

---

## Common Misconceptions

Misconception 1: "Black enforces PEP 8."
Reality: Black produces code that is PEP 8 compliant in most respects, but Black's choices sometimes diverge from PEP 8's recommendations. Black's goal is consistency and determinism, not PEP 8 compliance. For example, Black's 88-character line length exceeds PEP 8's recommended 79. Black does not check naming conventions, import ordering, or code logic  -  those are the domains of flake8 and isort.

Misconception 2: "Black changes the behavior of my code."
Reality: Black operates at the AST level and performs a semantic equivalence check after formatting. If Black cannot produce semantically equivalent output, it raises an error and leaves the file unchanged. Black changes whitespace and syntax structure, never program logic.

Misconception 3: "I can configure Black to match my team's existing style."
Reality: The deliberate design choice is that you cannot. Black has one style. The intended adoption path is: run `black .` on the entire codebase in a single commit, add a `black --check` CI step and a `black` pre-commit hook, and move on. The short-term pain of the initial bulk reformat is the trade-off for never discussing formatting again.

---

## Why It Matters in Practice

Black's impact is most visible in code review culture. Teams that adopt Black find that formatting comments in code review disappear entirely within a week. The author cannot argue that their style is fine  -  Black formatted it. The reviewer cannot request a different style  -  Black will reformat it back. The conversation moves to logic, correctness, and design.

For open source projects, Black as a contribution requirement dramatically lowers the friction for external contributors. A contributor does not need to read a style guide or match existing code patterns for formatting. They run `black .` before submitting a PR and the formatting is automatically correct.

---

## Interview Angle

Common question forms:
- "What formatters do you use in Python projects?"
- "How do you handle formatting disagreements in code review?"

Answer frame:
Describe Black's "uncompromising" philosophy  -  minimal configuration means no formatting debates. Explain the workflow: `black .` locally (or via pre-commit hook), `black --check .` in CI. Mention that `ruff format` is a Rust-based drop-in alternative. Note the difference between a formatter (Black  -  whitespace and structure) and a linter (Ruff/Flake8  -  code quality and correctness).

---

## Related Notes

- [[ruff|Ruff]]
- [[isort|isort]]
- [[pre-commit|Pre-commit Hooks]]
- [[pyproject-toml|pyproject.toml]]
