---
title: 05 - Semantic Versioning
description: "Semantic Versioning defines version numbers as MAJOR.MINOR.PATCH where MAJOR breaks compatibility, MINOR adds features backward-compatibly, and PATCH fixes bugs — providing a contract that pip version specifiers use to select compatible releases."
tags: [semantic-versioning, semver, versioning, pip, packaging, releases, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Semantic Versioning

> Semantic Versioning (SemVer) is a version numbering convention where the three numbers MAJOR.MINOR.PATCH each carry a specific promise about compatibility — a convention that makes automated dependency management possible by allowing tools to reason about which version upgrades are safe.

---

## Quick Reference

**Core idea:**
- **MAJOR**: breaking change — existing code that uses this package may break
- **MINOR**: new feature, backward compatible — existing code still works
- **PATCH**: bug fix, backward compatible — behavior only corrected, not extended
- `1.0.0` → `2.0.0`: breaking change (remove API, change behavior)
- `1.0.0` → `1.1.0`: new feature added (existing code unaffected)
- `1.0.0` → `1.0.1`: bug fixed (no API change)
- Pre-release: `1.0.0-alpha.1`, `1.0.0.beta2` — lower precedence than the release

**Tricky points:**
- Major version 0 (`0.x.y`) is special — the API is considered unstable; MINOR may include breaking changes; `0.x.y` is not a stability promise
- pip's `^` operator does not exist natively — Poetry uses it; pip uses `>=1.0,<2.0` or `~=1.0` (compatible release)
- `~=1.4.2` (compatible release in pip) means `>=1.4.2,<1.5` — only patch updates allowed
- `~=1.4` (one component) means `>=1.4,<2` — minor and patch updates allowed
- Version specifiers in `pyproject.toml` as a library author should be loose (`>=2.0`); as an application owner they should be tight (lockfile or `==2.31.0`)

---

## What It Is

Version numbers are a communication protocol between software authors and software users. Before SemVer, version numbers were arbitrary — `2.0` might mean "we rewrote the internals" or "we added a new feature" or "we fixed a typo in the README." Users had no reliable way to determine whether upgrading from `1.4` to `1.5` was safe to do automatically, or whether it might break their code. They had to read changelogs and test manually for every upgrade.

SemVer formalizes the version number into a contract. The author commits: a PATCH bump means nothing changed that you can observe from outside the package — a bug was fixed, but the API and behavior are otherwise identical. A MINOR bump means new functionality was added, but existing functionality was not removed or changed — your code that worked before will work after. A MAJOR bump means the author made a choice that may break your code — a function was removed, a parameter was renamed, a return type was changed.

This contract makes automated dependency management possible. When pip or Poetry resolves dependencies, they use version specifiers to select versions that are expected to be compatible. The specifier `requests>=2.28,<3.0` says: "I know this works with requests 2.28, and I trust that any 2.x version after that has not removed or changed the API I use." This trust is grounded in SemVer's promise. Without SemVer, the specifier `requests>=2.28` would be reckless — any version might be compatible or not.

---

## How It Actually Works

SemVer version identifiers have the format `MAJOR.MINOR.PATCH` with optional pre-release and build metadata:

```
1.4.2           # Release
1.4.2-alpha.1   # Pre-release (lower precedence than 1.4.2)
1.4.2+build.42  # Build metadata (ignored in precedence comparison)
2.0.0-rc.1      # Release candidate
```

Version precedence: `1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0-rc.1 < 1.0.0 < 1.1.0 < 2.0.0`

**pip version specifiers** in `requirements.txt` or `pyproject.toml`:

```
requests==2.31.0           # Exact version (lockfile-style; for applications)
requests>=2.28,<3.0        # Range (for libraries; accepts any 2.x >= 2.28)
requests~=2.28             # Compatible release: >=2.28, <3.0
requests~=2.28.0           # Compatible release: >=2.28.0, <2.29
requests>=2.0              # Lower bound only (loose; not recommended for libraries)
requests!=2.29.0           # Exclude a specific broken version
```

The `~=` operator (compatible release) is read as "compatible with". `~=2.28` is compatible with any 2.x.y where 2.x >= 2.28. `~=2.28.0` is compatible with any 2.28.y where y >= 0. The general rule: the last component is free to change, all earlier components are pinned.

**Poetry's version specifiers** add the caret operator:

```toml
requests = "^2.28"    # >=2.28.0, <3.0.0 (minor and patch free)
requests = "~2.28.0"  # >=2.28.0, <2.29.0 (patch only free)
requests = ">=2.28"   # Lower bound only
requests = "2.31.0"   # Exact version
```

The caret (`^`) is Poetry's most common choice. `^2.28` trusts that any 2.x release is safe — which is what SemVer promises for MINOR and PATCH changes.

**Practical versioning decisions:**

For a library author, specifying dependencies too tightly (`requests==2.31.0`) will conflict with other packages in users' environments that require different versions. Specify the minimum version you know works and the major version ceiling: `requests>=2.28,<3.0`.

For an application owner, pin exactly in the lockfile (`poetry.lock` or `requirements.txt` from `pip freeze`). The lockfile records exact versions for reproducibility — the constraint in `pyproject.toml` is the policy, the lockfile is the implementation.

**GitHub releases and tags** should follow SemVer. A `git tag v1.4.2` triggering a CI release workflow that builds and publishes the package to PyPI is the standard pattern. The tag name becomes the version. Tooling like `python-semantic-release` can automate this by parsing conventional commit messages to determine the version bump.

---

## How It Connects

Poetry uses SemVer-compatible specifiers (`^`, `~`) in `pyproject.toml` — understanding SemVer is prerequisite to understanding what Poetry's version constraints mean.

[[poetry|Poetry]]

pip's version specifiers (used in `requirements.txt` and `install_requires`) implement the SemVer ranges that libraries specify in their package metadata.

[[pip-and-packaging|pip and Packaging]]

CD pipelines typically tag releases with SemVer version numbers, triggering the release to PyPI or a package registry.

[[cd-docker|CD with Docker]]

---

## Common Misconceptions

Misconception 1: "Version 0.x is stable enough to use SemVer compatibility rules."
Reality: SemVer explicitly states that MAJOR version 0 (`0.x.y`) is for initial development. The public API should not be considered stable. MINOR version bumps may include breaking changes during the 0.x phase. This is why many popular libraries stay on `0.x` for years (attrs, httpx in early versions) — they want freedom to break the API while iterating. Only at `1.0.0` does the SemVer compatibility contract formally apply.

Misconception 2: "Adding a new optional parameter to a function is a breaking change requiring a MAJOR bump."
Reality: Adding a new optional parameter with a default value is backward compatible — existing callers continue to work without modification. This is a MINOR change. A MAJOR change would be removing a parameter, making an optional parameter required, or changing the behavior of existing parameters. The test: will existing code break? Optional additions never break existing code.

Misconception 3: "The version in `pyproject.toml` dependencies and the version in `poetry.lock` serve the same purpose."
Reality: The `pyproject.toml` version specifier is a constraint (a policy): "I require requests 2.x". The `poetry.lock` entry is a solution (the implementation): "requests 2.31.0 was the specific version that satisfied all constraints". The constraint allows a range; the lock pins one specific version. Changing the constraint requires re-running resolution; changing the lockfile directly is fragile and not recommended.

---

## Why It Matters in Practice

SemVer discipline is what allows the Python ecosystem's automatic dependency updates to work reliably. Tools like Dependabot or Renovate can automatically open PRs that bump a `requests` dependency from `2.28.0` to `2.31.0` with confidence that the update is safe because the MINOR and PATCH bumps carry the SemVer promise. Without this convention, every version bump would require manual review.

When a team is building a library for internal use or PyPI, SemVer forces them to think carefully about API stability. Committing to SemVer means taking seriously which changes are breaking — deprecating a parameter before removing it, providing migration paths, maintaining changelogs. This discipline produces better APIs because it requires thinking about backward compatibility at the time the change is made, not after users have broken.

---

## Interview Angle

Common question forms:
- "What is semantic versioning and how does it relate to pip?"
- "When should you bump the major version of a package?"

Answer frame:
Define MAJOR.MINOR.PATCH with the breaking/feature/fix semantics. Explain how pip version specifiers (`>=`, `~=`, `!=`) rely on the SemVer contract to select safe versions. Describe the library vs application distinction: libraries use range specifiers, applications pin with a lockfile. Note the 0.x caveat. A strong answer connects this to automated dependency updates (Dependabot) — they work because of SemVer.

---

## Related Notes

- [[poetry|Poetry]]
- [[pip-and-packaging|pip and Packaging]]
- [[pyproject-toml|pyproject.toml]]
- [[cd-docker|CD with Docker]]
