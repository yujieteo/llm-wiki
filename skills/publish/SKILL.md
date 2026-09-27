---
name: publish
description: Compile dist/notes.md into the website repo's notes.md, push, verify.
---

# Publish

## Never
- Never write to the website repo directly — only via `scripts/append-notes.sh`.
- Never `git push --force`.
- Never retry a failed push.
- Never skip verification.

## Steps
1. `bash build.sh` → regenerate `dist/notes.md`. Abort if exit ≠ 0.
2. `NEW_SHA=$(bash scripts/append-notes.sh)` — abort if exit ≠ 0.
3. `REMOTE=$(git ls-remote <website.repo> <website.branch> | cut -f1)`.
   Compare `$NEW_SHA` to `$REMOTE`.
   - Mismatch → report last 5 lines of push stderr, stop. No retry.
4. `curl -s https://raw.githubusercontent.com/<user>/<site>/<branch>/<notes_path> \
     | grep -q "<section_header>"`.
   - Miss → wait 60s, retry once.
   - Still miss → report "push landed, CDN stale", exit 0.
5. Report: local SHA, remote SHA, content-check result.
