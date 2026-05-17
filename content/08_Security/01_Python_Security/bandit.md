---
title: 02 - Bandit (Python Security Linter)
description: "Bandit is a static analysis tool that scans Python source code for common security issues, assigning each finding a severity and confidence level, and is designed to be run in CI/CD pipelines as a first-pass security gate."
tags: [bandit, static-analysis, linting, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Bandit (Python Security Linter)

> Bandit is automated code review for security — it catches the class of mistakes that are easy to make under time pressure and hard to see in code review.

---

## Quick Reference

**Core idea:**
- Bandit uses AST (Abstract Syntax Tree) analysis to find patterns associated with security vulnerabilities in Python code
- Each finding has a severity (LOW, MEDIUM, HIGH) and a confidence (LOW, MEDIUM, HIGH) — both matter for triage
- Common findings: `subprocess` with `shell=True`, hardcoded passwords, use of `MD5`/`SHA1` for security purposes, SQL string concatenation, `assert` in non-test code
- Run with `bandit -r src/` to scan a directory recursively; `-l` for verbose; `--skip B101` to suppress specific tests
- Designed for CI/CD integration — exit code is non-zero when issues are found, enabling pipeline failure on high-severity findings

**Tricky points:**
- Bandit has false positives — not every `subprocess` call or MD5 use is a vulnerability in context; triage is required
- `# nosec` comment on a line suppresses Bandit warnings for that line — this is legitimate for acknowledged false positives but should require a comment explaining why
- Bandit does not understand data flow — it cannot determine whether a value passed to a dangerous function originated from user input or is hardcoded; it flags the pattern regardless
- `assert` statements in application code (not tests) are flagged because Python can be run with `-O` (optimize) flag which strips all assertions — security checks using `assert` disappear in optimized mode
- Bandit is a first-pass tool, not a comprehensive security audit — it finds known-bad patterns but cannot find business logic flaws or authorization issues

---

## What It Is

A spell checker does not understand the meaning of what you write — it finds words that match patterns of known misspellings. Bandit is a spell checker for security anti-patterns in Python code. It parses your Python source into an Abstract Syntax Tree, walks through every node of that tree, and checks each node against a library of tests — each test looks for a specific pattern that commonly indicates a security problem.

Bandit was originally developed at OpenStack for auditing large Python codebases and is now maintained by PyCQA (Python Code Quality Authority). It is not a complete security audit tool. It cannot find authorization flaws, business logic vulnerabilities, or application-specific misconfigurations. What it reliably finds are the category of mistakes that appear repeatedly across Python codebases: calling functions that are documented to be insecure, using cryptographic primitives in ways known to be weak, and writing patterns that invite injection vulnerabilities.

The two-dimensional rating system — severity and confidence — is important for practical use. A HIGH severity finding means the issue, if genuinely present, is serious. HIGH confidence means Bandit is quite sure the pattern it found is actually a problem (not a false positive). A MEDIUM severity, LOW confidence finding is a suggestion to investigate rather than a confirmed vulnerability. In CI/CD pipelines, failing on HIGH/HIGH findings and reviewing MEDIUM/HIGH findings in pull requests is a workable policy for most teams.

---

## How It Actually Works

Running Bandit on a simple Python file demonstrates its output format:

```
$ bandit -r myapp/

>> Issue: [B602:subprocess_popen_with_shell_equals_true] subprocess call with shell=True
   Severity: High   Confidence: High
   Location: myapp/utils.py:47
   More Info: https://bandit.readthedocs.io/en/latest/plugins/b602_subprocess_popen.html
47  result = subprocess.run(f"ls {user_path}", shell=True, capture_output=True)

>> Issue: [B105:hardcoded_password_string] Possible hardcoded password: 'admin123'
   Severity: Low   Confidence: Medium
   Location: myapp/config.py:12
12  DEFAULT_ADMIN_PASSWORD = "admin123"

>> Issue: [B324:hashlib_new_insecure_functions] Use of weak MD5 hash
   Severity: Medium   Confidence: High
   Location: myapp/auth.py:89
89  token = hashlib.md5(user_id.encode()).hexdigest()
```

The `subprocess.run` with `shell=True` is a genuinely dangerous pattern: when `shell=True`, the entire command string is passed to the system shell for parsing, which means shell metacharacters in `user_path` (backticks, semicolons, pipe characters, `$(...)`) execute as shell commands. The safe replacement constructs the argument list explicitly:

```python
# Dangerous
result = subprocess.run(f"ls {user_path}", shell=True, capture_output=True)

# Safe — user_path is passed as data, not parsed by the shell
result = subprocess.run(["ls", user_path], shell=False, capture_output=True)
```

The `assert` test (B101) is one that surprises developers:

```python
# Bandit flags this
def require_admin(user):
    assert user.is_admin, "Not authorized"
    # ... admin-only code ...
```

Running Python with `python -O myapp.py` compiles the bytecode with assertions removed. The `require_admin` function now has no authorization check — all code after the assert executes unconditionally. While most production deployments do not use `-O`, relying on `assert` for security-critical checks is a fragile pattern. The correct replacement is an explicit `if` statement with a proper exception.

Bandit configuration lives in a `.bandit` file or `pyproject.toml`. To acknowledge a false positive in a specific line while keeping the check active globally:

```python
result = subprocess.run(["sh", "-c", hardcoded_safe_command], shell=False)  # nosec B602
```

The `# nosec B602` comment tells Bandit to skip the B602 check on that line. The test ID makes the suppression precise — it is clear what was reviewed and why it was excluded, making code review of `nosec` comments meaningful.

---

## How It Connects

Bandit scans your own code; dependency scanning checks your third-party packages. Both are needed for a complete security pipeline.

[[dependency-scanning|Dependency Vulnerability Scanning]]

Bandit's B324 test flags weak cryptographic hash functions — understanding which hash functions are appropriate for security use versus general hashing is context that makes the findings actionable.

[[cryptography-python|Cryptography with Python]]

---

## Common Misconceptions

Misconception 1: "Bandit gives me too many false positives, so it's not worth running."
Reality: False positives are a real friction point, but the solution is tuning, not abandonment. Set an appropriate severity threshold for pipeline failures (HIGH severity only, for example), acknowledge known false positives with `# nosec` comments that document the reasoning, and configure Bandit to skip test files (where B101 assert-checks and B311 random-use findings are expected and safe). A well-configured Bandit run has a manageable false positive rate and catches real issues automatically.

Misconception 2: "My code passed Bandit, so it's secure."
Reality: Bandit checks for specific, well-known anti-patterns — it is a necessary but not sufficient security control. It cannot find authorization logic bugs, IDOR vulnerabilities, business logic flaws, SSRF via application-specific URL construction, or any vulnerability that requires understanding what the code is supposed to do. Passing Bandit means you have not committed obvious security mistakes; it does not mean your application has no vulnerabilities.

Misconception 3: "I should always fix every Bandit finding immediately."
Reality: The severity and confidence scores exist precisely because not every finding is equally urgent or even real. A LOW severity, LOW confidence finding in a non-critical internal utility is different from a HIGH severity, HIGH confidence finding in an authentication endpoint. The correct workflow is: fail CI on HIGH/HIGH findings, review MEDIUM findings in pull requests, and track LOW findings in a backlog. Treating all findings as equal leads to alert fatigue and `nosec` suppression without thought.

---

## Why It Matters in Practice

The patterns Bandit catches are exactly the patterns that appear in post-breach code review. `subprocess` with `shell=True` is how command injection vulnerabilities get introduced — a developer writes it for convenience, reviews pass because the code looks reasonable at a glance, and it stays in production until someone discovers that the user-controlled path contains a semicolon. Hardcoded credentials have caused more significant breaches than almost any other single category of developer mistake, and they are trivially detectable by static analysis.

In teams without a dedicated security engineer, Bandit running in CI/CD provides a baseline of automated security review that would otherwise not exist. It catches the issue at the point it is introduced — in the pull request — rather than after deployment. This is the correct point to catch security issues: when the fix is a code change rather than an incident response.

---

## Interview Angle

Common question forms:
- "What tools do you use for Python security analysis?"
- "What does Bandit check for? Give some examples of findings."
- "How would you integrate security scanning into a CI/CD pipeline?"

Answer frame:
A strong answer explains Bandit as AST-based static analysis that catches known-bad patterns, with concrete examples (subprocess shell=True, hardcoded passwords, MD5 for security). It explains the severity/confidence matrix and the practical policy of failing CI on HIGH/HIGH. It mentions the CI integration pattern and `# nosec` for false positives. Distinguishing Bandit (your code) from `pip-audit` (dependencies) as complementary tools demonstrates system-level thinking.

---

## Related Notes

- [[dependency-scanning|Dependency Vulnerability Scanning]]
- [[cryptography-python|Cryptography with Python]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[sql-injection|SQL Injection]]
