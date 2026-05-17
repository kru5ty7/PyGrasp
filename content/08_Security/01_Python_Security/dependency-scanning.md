---
title: 01 - Dependency Vulnerability Scanning
description: "Dependency scanning identifies known security vulnerabilities in the third-party packages a Python project uses, mapping installed package versions against public CVE databases to surface exploitable weaknesses in the supply chain."
tags: [dependency-scanning, pip-audit, supply-chain, cve, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Dependency Vulnerability Scanning

> Your application's attack surface includes every package in your `requirements.txt` — most Python projects have at least one known vulnerability waiting in their dependency tree.

---

## Quick Reference

**Core idea:**
- `pip-audit` queries the PyPA Advisory Database and OSV (Open Source Vulnerabilities) for CVEs in installed packages
- `safety check` (Safety CLI) checks against the Safety DB maintained by PyUp.io
- GitHub Dependabot automatically opens pull requests to update vulnerable dependencies in repositories it monitors
- CVEs (Common Vulnerabilities and Exposures) are standardized identifiers for publicly disclosed vulnerabilities — each has a severity score (CVSS)
- Supply chain attacks inject malicious code at the package level — dependency scanning catches known issues but not novel attacks

**Tricky points:**
- Transitive dependencies (packages your packages depend on) carry the same risk as direct dependencies but are less visible in your requirements file
- `pip-audit` defaults to checking the current environment; in CI/CD, run it against a frozen `requirements.txt` or in an isolated virtual environment
- A CVE with a high CVSS score is not necessarily exploitable in your specific usage of the package — triage matters
- Pinning exact versions (`package==1.2.3`) ensures reproducible builds but means vulnerability fixes require explicit updates
- `pip-audit --fix` can automatically upgrade vulnerable packages, but this should be tested — it may introduce breaking changes

---

## What It Is

Imagine buying wood for a building project from a lumber yard where some batches have been recalled for being structurally unsound. If you know the specific batch numbers to avoid, you can check whether your order includes them. If you do not check, you might build with compromised material without knowing it. Python dependencies are that lumber: most of the time they are exactly what they say they are, but known vulnerabilities — publicly documented weaknesses with published CVE identifiers — can be present in any version of any package you install.

Dependency vulnerability scanning is the systematic check against the recall list. Tools like `pip-audit` and Safety examine every package installed in your environment, compare each package's name and version against databases of known vulnerabilities, and report which packages have CVEs associated with them. The databases are built from security researchers, vendors, and automated discovery — when a vulnerability in a Python package is found and reported, it is assigned a CVE, scored for severity, and added to the databases that scanning tools query.

The supply chain risk runs deeper than your direct dependencies. When your application installs `requests`, it also installs `certifi`, `charset-normalizer`, `idna`, and `urllib3`. Each of those packages has its own version and its own history of CVEs. A vulnerability in `urllib3` affects every application that uses `requests`, regardless of whether the developer knew `urllib3` was in the dependency tree. The attack surface of a modern Python application is the full transitive closure of its dependency graph — sometimes hundreds of packages — and most developers are not aware of what that includes.

---

## How It Actually Works

Running `pip-audit` in a Python environment produces output like:

```
$ pip-audit
Found 2 known vulnerabilities in 2 packages
Name       Version  ID                  Fix Versions
---------- -------- ------------------- ------------
Pillow     9.0.0    GHSA-8vj2-vxx3-667w  9.0.1
cryptography 38.0.0 CVE-2023-0286        39.0.1
```

Each row reports the package, the installed version, the CVE or GitHub Security Advisory identifier, and the version that fixes the issue. The typical CI/CD integration runs `pip-audit` as a build step and fails the pipeline if any vulnerabilities are found above a severity threshold:

```yaml
# .github/workflows/security.yml
- name: Audit dependencies
  run: |
    pip install pip-audit
    pip-audit --severity high --error-on-unaudited-package
```

The `--severity high` flag fails only on high and critical CVEs, allowing low-severity issues to be tracked without blocking deployments. The `--error-on-unaudited-package` flag fails if any package cannot be checked — this catches packages not in the vulnerability databases (which could indicate a private or malicious package).

GitHub Dependabot operates differently — it monitors the repository's dependency files (`requirements.txt`, `pyproject.toml`, `Pipfile`) and automatically opens pull requests when a newer version of a dependency is available or when a CVE is published for a currently pinned version. The pull request includes the changelog and vulnerability details. Teams that merge Dependabot PRs promptly maintain a continuously low vulnerability exposure without a manual audit process.

Supply chain attacks are distinct from CVEs. In a supply chain attack, the malicious code is injected into the package itself — either by compromising the package maintainer's PyPI account (as in the 2022 PyTorch supply chain attack that injected a data-exfiltrating version of `torchtriton`) or by publishing a typosquat package with a name similar to a popular package (`requets` instead of `requests`). These attacks are not caught by CVE scanning because no CVE exists yet. Defenses include: pinning exact package versions and hashes in `requirements.txt` (so pip verifies the downloaded package matches), using `pip install --require-hashes`, and using private package mirrors for production dependencies.

---

## How It Connects

Managing Python packages and understanding the full dependency graph are prerequisite knowledge for understanding what dependency scanning is auditing.

[[pip-and-packaging|pip and Packaging]]

Bandit performs static analysis of your own code; dependency scanning checks your third-party code. Both are part of a complete security pipeline.

[[bandit|Bandit (Python Security Linter)]]

---

## Common Misconceptions

Misconception 1: "I pin all my dependencies to exact versions, so nothing changes unexpectedly and I'm safe."
Reality: Pinning versions means you get reproducible builds, which is valuable. But pinning a vulnerable version means you are consistently deploying the same vulnerability. Pinning and scanning complement each other: pin versions for reproducibility, scan regularly for CVEs against those pinned versions, and update when vulnerabilities are found.

Misconception 2: "We reviewed our direct dependencies and they're fine."
Reality: Direct dependencies are typically a small fraction of what actually gets installed. A project with 10 direct dependencies can have 80+ transitive dependencies. The 2021 `ua-parser-js` attack (npm, but the pattern is identical in Python) exploited a transitive dependency that almost no developer knew was in their project. `pip-audit` checks the full installed environment, not just the packages explicitly listed in requirements.

Misconception 3: "A CVE in a package we use is only a problem if we call the vulnerable function."
Reality: This is sometimes true — a CVE in a file-parsing function you never call may genuinely not affect your application. But triage requires understanding the attack vector (network reachable? requires user input?), whether your application exposes that code path, and whether there are indirect paths through the package that could be reached. The operational default should be to update unless there is a specific, documented reason the CVE is not exploitable in your usage.

---

## Why It Matters in Practice

The Log4Shell vulnerability (CVE-2021-44228) illustrated the consequences of unscanned transitive dependencies at catastrophic scale. Log4j was a transitive dependency in thousands of Java applications — most teams did not know they were using it until the vulnerability was publicized. Python's ecosystem is not immune to the same pattern: a vulnerability in a widely used package like `requests`, `cryptography`, or `Pillow` affects every application that depends on it, directly or transitively.

In regulated industries (healthcare, finance, government), dependency scanning is not optional — it is a compliance requirement under frameworks like PCI DSS, SOC 2, and FedRAMP. Even outside regulated contexts, CVEs in dependencies are the most common source of security vulnerabilities in production Python applications because they require no developer error — the vulnerability is inherited from a dependency without the developer doing anything wrong.

---

## Interview Angle

Common question forms:
- "How do you manage security vulnerabilities in Python dependencies?"
- "What is the difference between pip-audit and Dependabot?"
- "What is a supply chain attack? How would you defend against it?"

Answer frame:
A strong answer explains CVEs and the databases that tools query, then distinguishes the scanning tools: `pip-audit` is for local/CI audits, Dependabot is for automated PR-based updates in GitHub-hosted repos. On supply chain attacks, it distinguishes CVEs (known vulnerabilities) from novel supply chain injections (malicious packages), and mentions hash-pinning with `--require-hashes` as the defense against package substitution.

---

## Related Notes

- [[pip-and-packaging|pip and Packaging]]
- [[bandit|Bandit (Python Security Linter)]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[owasp-top-10|OWASP Top 10]]
