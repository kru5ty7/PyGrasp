# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

PyGrasp is a "Python Knowledge Vault" — an Obsidian vault of ~630 markdown notes published as a website with [Quartz 4](https://quartz.jzhao.xyz) (v4.5.2). The content covers Python from CPython internals through web frameworks, data/AI engineering, system design, SQL, DSA, AWS, security, and DevOps. Deployed to GitHub Pages at `kru5ty7.github.io/PyGrasp` automatically on push to `main` (`.github/workflows/deploy.yml` runs `npm ci && npx quartz build` and publishes `public/`).

## Commands

Requires Node ≥ 22, npm ≥ 10.9.2.

```bash
npm i                          # install dependencies
npx quartz build --serve       # dev server with live reload (localhost:8080)
npx quartz build               # production build into public/
npm run check                  # tsc --noEmit + prettier --check
npm run format                 # prettier --write
```

There is no test suite for the vault content. `npm run check` only validates the TypeScript framework code, not markdown.

Build speed tip: the `CustomOgImages` emitter in `quartz.config.ts` is enabled and slows builds considerably — comment it out temporarily for faster local iteration, but don't commit that change.

## Repository Layout — Two Distinct Halves

**`content/` is the deliverable.** Everything else is publishing machinery.

- `content/` — the vault. 13 numbered "layer" folders (`01_Core` → `13_Tooling_DevOps`) plus `00_MOC`, which holds the `lp-*` learning-path pages linked from `content/index.md`. Layers form a dependency order (Core → Concurrency → Web → …); learning paths sequence notes so each concept builds on prior ones.
- `quartz/` — the upstream Quartz framework, vendored per Quartz convention. **It contains local customizations** (see below), so don't treat it as untouchable vendor code, but don't casually rewrite framework internals either.
- `quartz.config.ts` / `quartz.layout.ts` — site config and page layout. `quartz.layout.ts` has a custom `explorerSort` that sorts the sidebar numerically by slug so the `NN_` folder prefixes drive ordering.
- `*.ps1` scripts at repo root — one-off vault-maintenance scripts (frontmatter fixes, alias additions, renames) with hardcoded `f:\workspace\PyGrasp` paths from the author's Windows machine. Historical reference only; not part of the build. `content-map.md` is a planning doc for filename sequencing that was **not** applied (sequence numbers went into titles instead — see below).

## Note Conventions (follow these when adding/editing notes)

Every note has YAML frontmatter:

```yaml
---
title: 07 - *args and **kwargs
description: "one-paragraph summary…"
tags: [args, kwargs, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---
```

- **Sequence numbers live in `title:`** (`NN - Name`), not in filenames. Filenames are plain slugs (`args-and-kwargs.md`). Folders carry `NN_` prefixes for sidebar ordering.
- **Slugs must be globally unique** across the vault: `CrawlLinks` uses `markdownLinkResolution: "shortest"`, so wikilinks like `[[decorators]]` resolve by bare slug regardless of folder.
- **Quote `description:` values** containing backticks or `: ` — unquoted ones break YAML parsing (this is exactly what `fix_frontmatter.ps1` was written to repair).
- Tags include a `layer-N` tag and a domain tag matching the frontmatter fields.
- Note files start with a UTF-8 BOM; preserve it when editing with raw byte-level tools.
- Wikilink syntax is Obsidian-flavored: `[[slug]]` or `[[slug|Display Text]]`.
- `private/`, `templates/`, and `.obsidian/` are excluded from the build (`ignorePatterns` in `quartz.config.ts`).

## Interactive Visualizers

145 standalone, self-contained HTML visualizers live in `quartz/static/visualizers/` and are embedded into notes via:

```html
<iframe src="/static/visualizers/<slug>.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="… Visualizer"></iframe>
```

They were built in 5 phases (DSA/DP, LLD, HLD, Cloud, AI) and are named after the note slug they accompany. When adding a visualizer: put the HTML file in `quartz/static/visualizers/`, embed it in the matching note with the iframe pattern above, and keep it dependency-free (everything inline in one file).
