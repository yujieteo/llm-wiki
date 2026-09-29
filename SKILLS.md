---
name: llm-wiki
description: Router for the llm-wiki repo. Use when dropping links, ingesting sources, compiling, recrawling, linting, building or publishing wiki notes; loads one focused sub-skill.
---

# SKILLS.md — Router

## Never (hard prohibitions)
- Never write to `raw/sources/` — human-only.
- Never write to the website repo directly — only via `scripts/append-notes.sh`.
- Never commit secrets — no `.env`, no API keys in any committed file.
- Never `git push --force` on any repo.
- Never auto-merge cross-wiki notes — require human confirmation.
- Never apply a diff to a wiki note without human confirmation.
- Never retry a failed `git push` — auth failures need human intervention.
- Never skip publish verification (checks 1–3).

## Routing table
| Trigger                                   | Skill                          |
|-------------------------------------------|--------------------------------|
| Drop a web link                           | `skills/drop-link/SKILL.md`    |
| Ingest raw source                         | `skills/ingest/SKILL.md`       |
| Compile wiki notes                        | `skills/compile/SKILL.md`      |
| Recrawl links                             | `skills/recrawl/SKILL.md`      |
| Publish to website                        | `skills/publish/SKILL.md`      |
| Lint stale notes                          | `skills/lint/SKILL.md`         |
| Rebuild `dist/notes.md` / index, run checks | `skills/build/SKILL.md`      |
| Exact note shape (frontmatter, body)      | `skills/note-format/SKILL.md`  |

## How routing works
Read the trigger. Load exactly one skill. Fire its steps. Do not chain skills.
The one exception: a skill may name `skills/note-format/SKILL.md` as a
reference; read it only when writing or validating a note.
Do not read `README.md` or `docs/` to do routine work; the skills are enough.
