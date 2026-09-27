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
4. Read the source and produce one atomic note with this exact shape:
   ```md
   ---
   title: Short retrieval label
   tags: [canonical-tag, second-tag]
   source: raw/links/topic.md
   updated: YYYY-MM-DD
   summary: One-line retrieval summary
   ---
   One self-contained Markdown paragraph with source links and no heading, list, blank line, or trailing tags.
   ```
   Use `scripts/llm-call.sh` when configured. If the website has a tag registry,
   reuse its canonical tags. Keep tags in frontmatter because `build.sh` appends
   them in the website note format.
5. Write to `wiki/<topic>/<slug>.md`. Commit every `build.batch_size` notes.
6. Run `scripts/build-index.sh` as the final step. Commit the index.
7. Run `bash build.sh`. It must emit dated sections containing blank-line-
   delimited paragraphs with trailing tags, matching `site/data/notes.md`.
8. Report: notes written, index regenerated, compiled notes, remaining items.
