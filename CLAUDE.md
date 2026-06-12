# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PyGrasp is a Python knowledge vault (~700 notes) published as a static site via **Quartz 4** (a Markdown -> static site generator built on Preact/esbuild). The `quartz/` directory is the site generator itself (config, plugins, components, build pipeline); `content/` is the actual knowledge base of Markdown notes. Most day-to-day work in this repo is editing/organizing Markdown notes in `content/`, occasionally touching Quartz config/components/visualizers in `quartz/`.

## Commands

- `npm run check` - type-check (`tsc --noEmit`) + Prettier check. Run this after editing any `.ts`/`.tsx` file under `quartz/`.
- `npm run format` - apply Prettier formatting.
- `npm test` - run the test suite (`tsx --test`), which picks up `*.test.ts` files (e.g. `quartz/util/path.test.ts`, `quartz/util/fileTrie.test.ts`).
  - Run a single test file: `npx tsx --test quartz/util/path.test.ts`
- `npx quartz build --serve` - build the site and serve it locally with live reload (use this to preview content/layout changes).
- `npx quartz build` - production build, outputs to `public/` (this is what CI runs).

There is no Python code/tooling in this repo despite the subject matter being Python - it's a notes vault, not a Python project.

## Content architecture (`content/`)

Notes are organized into 13 numbered top-level domains, each with numbered subfolders, e.g.:

- `01_Core`, `02_Concurrency`, `03_Web`, `04_Web_Ecosystem`, `05_Data_Engineering`, `06_AI_Engineering`, `07_HLD`, `08_LLD`, `09_SQL`, `10_DSA`, `11_Cloud`, `12_Security`, `13_Tooling_DevOps`

The `NN_` numeric prefixes on both folders and (historically) files exist purely to control sidebar/explorer ordering - see the custom `explorerSort` in `quartz.layout.ts`, which sorts folders before files and sorts by `slugSegment` with numeric-aware locale comparison. Don't remove numeric prefixes from folder names without considering ordering impact.

### `content/00_MOC/`

"Map of Content" files (`lp-*.md`, e.g. `lp-core.md`, `lp-concurrency.md`) are curated **learning paths** - ordered reading lists of `[[wikilink]]`-style links through a domain's notes, grouped by "Layer" (e.g. Layer 0, Layer 1). `content/index.md` is the site homepage and links out to every learning path with a note count.

### Note frontmatter convention

Notes use YAML frontmatter with these fields (see any file under `content/01_Core/00_How_Python_Runs/` for a template):

```yaml
title: <NN - Title>
description: <1-2 sentence summary>
tags: [topic, tags, here, domain-tag]
status: draft
difficulty: beginner | intermediate | advanced
layer: <integer>
domain: <domain slug, e.g. core>
created: YYYY-MM-DD
```

Notes generally follow a structure of: `# Title` -> blockquote summary -> `## Quick Reference` (core ideas + "tricky points") -> deeper explanatory sections.

### Interactive visualizers

`quartz/static/visualizers/*.html` are standalone interactive HTML/JS visualizations (sorting, data structures, system design diagrams, etc.). They're embedded in notes via:

```html
<iframe src="/static/visualizers/<name>.html" width="100%" height="440px" style="border:none;border-radius:6px;" title="..."></iframe>
```

If instead a visualizer is inlined directly as a `<script>` in a note's Markdown (rather than via iframe), it relies on `quartz/components/scripts/visualizer.inline.ts` to execute on SPA navigation - inline `<script>` tags in Markdown content are normally inert under Quartz's SPA router (micromorph), so that script patches and re-evaluates wrapper-scoped `<script>` blocks on every `nav` event. New inline visualizers must follow the existing `*-wrap` wrapper-element + `DOMContentLoaded`/`nav` listener pattern used by other visualizers for this patching to work.

## Quartz site config (`quartz/`)

- `quartz.config.ts` - site-wide config: title ("Python Knowledge Vault"), theme/colors/fonts, and the **plugin pipeline** (`transformers`, `filters`, `emitters`). Transformers run in order over each Markdown file (frontmatter parsing, Obsidian-flavored Markdown, GFM, TOC, link crawling, LaTeX, etc.); emitters generate output pages/assets.
- `quartz.layout.ts` - page layout: which components render on content pages vs. list pages, sidebar (Explorer with custom sort), graph view, etc.
- `quartz/components/` - Preact components used in layouts (Explorer, Graph, Search, TableOfContents, etc.) and their client-side scripts in `components/scripts/`.
- `quartz/plugins/` - transformer/filter/emitter plugins (this is vendored/forked Quartz source, not vault-specific most of the time).
- `ignorePatterns: ["private", "templates", ".obsidian"]` in `quartz.config.ts` - content under these paths is excluded from the build.

## Deployment

`.github/workflows/deploy.yml` builds with `npx quartz build` and deploys `public/` to GitHub Pages on every push to `main`. `baseUrl` in `quartz.config.ts` is `kru5ty7.github.io/PyGrasp`.

## Root-level PowerShell scripts

`*.ps1` files at the repo root (`restructure_vault.ps1`, `fix_frontmatter.ps1`, `prefix_titles.ps1`, `add_aliases.ps1`, `scan_frontmatter.ps1`, `revert_filenames.ps1`, `restructure.ps1`) are one-off, Windows-only migration scripts used during past vault reorganizations (hardcoded `f:\workspace\PyGrasp` paths). They are not part of the build and generally shouldn't need to be run again, but are kept for reference on how the vault's file/frontmatter conventions evolved.
