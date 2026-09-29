---
name: build
description: Regenerate dist/notes.md and wiki/index.md, or run the offline self-test.
---

# Build

## Never
- Never hand-edit `dist/notes.md` or `wiki/index.md`; they are generated.
- Never run the LLM in the build path.

## Steps
1. `./build.sh` — writes `dist/notes.md` and commits it when it changes.
   Non-zero exit means a note is malformed; the message names the file.
2. `bash scripts/build-index.sh` — rewrites `wiki/index.md`.
3. Changing scripts? Run `python3 scripts/check.py` (offline, no API key). It
   must print `check.py: all checks passed`.
4. Report: notes and dates built, check result.
