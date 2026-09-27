---
name: compile
description: Apply pending diffs and regenerate the index.
---

# Compile

## Never
- Never apply a diff without human confirmation.
- Never auto-merge cross-wiki notes.

## Steps
1. List pending diffs in `wiki/.diffs/*.md`.
2. For each diff: print Current / Proposed / Reason / Source, then ask
   the human: "Apply? (y/n)". Do not proceed without a `y`.
3. On `y`: apply the proposed change to the target wiki note, update the
   note's `updated` field, update the source link's `hash` in
   `raw/links/<topic>.md`, move the diff to `wiki/.diffs/applied/`.
4. On `n`: leave the diff in place.
5. Run `scripts/build-index.sh`.
6. Commit all changes with a message listing applied diffs.
