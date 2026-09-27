---
name: publish
description: Merge site-shaped dist/notes.md into the website notes source, push, verify.
---

# Publish

## Never
- Never write to the website repo directly — only via `scripts/append-notes.sh`.
- Never `git push --force`.
- Never retry a failed push.
- Never skip verification.

## Steps
1. `bash build.sh` → regenerate `dist/notes.md`. Abort if exit ≠ 0. Confirm its
   shape is `## YYYY-MM-DD`, then blank-line-delimited paragraphs ending in
   tags. Topic and title headings are invalid.
2. `NEW_SHA=$(bash scripts/append-notes.sh)` — abort if exit ≠ 0.
3. `REMOTE=$(git ls-remote <website.repo> <website.branch> | cut -f1)`.
   Compare `$NEW_SHA` to `$REMOTE`.
   - Mismatch → report last 5 lines of push stderr, stop. No retry.
4. Fetch the published `<notes_path>` and check for the newest compiled note.
   - Miss → wait 60s, retry once.
   - Still miss → report "push landed, CDN stale", exit 0.
5. Report: local SHA, remote SHA, content-check result.
