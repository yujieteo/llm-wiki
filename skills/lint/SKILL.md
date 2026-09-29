---
name: lint
description: Find stale, orphaned, or malformed wiki notes.
---

# Lint

## Steps
1. Glob `wiki/**/*.md`. For each note, check:
   - Required frontmatter fields present (see `skills/note-format/SKILL.md`).
   - `source` points to an existing `raw/` entry.
   - `updated` is within 365 days (or flag as stale).
2. Cross-check every `raw/links/*` entry: is it cited by at least one wiki note?
   Flag uncited links.
3. Output a report to stdout. Do not modify files.
