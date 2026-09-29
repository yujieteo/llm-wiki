---
name: ingest
description: Turn a raw source or a link into a wiki note.
---

# Ingest

## Never
- Never write to `raw/sources/`.
- Never apply a diff without human confirmation.
- Never retry a failed push.

## Steps
1. If `wiki/.queue/pending.json` exists, resume from `remaining`.
2. Determine target: a `raw/sources/<file>` or a `raw/links/<topic>.md#<url-hash>`.
3. For links: recrawl via `scripts/recrawl.sh` first. If a diff was produced,
   queue it for `compile` (do not write the wiki note from a changed source
   until the diff is confirmed).
4. Read the source and produce one atomic note in the shape given by
   `skills/note-format/SKILL.md`. Use `scripts/llm-call.sh` when configured.
5. Write to `wiki/<topic>/<slug>.md`. Commit every `build.batch_size` notes.
6. Run `scripts/build-index.sh` as the final step. Commit the index.
7. Run `bash build.sh`. It must emit dated sections containing blank-line-
   delimited paragraphs with trailing tags, matching `site/data/notes.md`.
8. Report: notes written, index regenerated, compiled notes, remaining items.
