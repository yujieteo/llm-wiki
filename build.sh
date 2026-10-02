#!/usr/bin/env bash
# build.sh — deterministically concatenate all wiki notes into dist/notes.md.
# No LLM runs in this path (invariant §2.4).
#
# Behavior:
#   1. Glob wiki/**/*.md, excluding wiki/index.md, wiki/.diffs/**, wiki/.queue/**.
#   2. Validate that each body is one site-note paragraph.
#   3. Group by updated date and append frontmatter tags to each paragraph.
#   4. Write to dist/notes.md.
#   5. Commit dist/notes.md as a build artifact.
#
# Dedup: none. Cross-wiki dedup happens in the website repo's build, not here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

mkdir -p "$REPO_ROOT/dist"

python3 - "$REPO_ROOT" <<'PYEOF'
import os
import sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts", "lib"))
from frontmatter import read_notes  # noqa: E402

REPO_ROOT = sys.argv[1]
WIKI_DIR = os.path.join(REPO_ROOT, "wiki")

notes = []
errors = []

for rel_path, _topic, fm, body, error in read_notes(WIKI_DIR):
    if error:
        errors.append(error)
        continue
    body = body.strip()
    if not body or "\n\n" in body or body.startswith("#"):
        errors.append(f"wiki/{rel_path}: body must be one Markdown paragraph without a heading")
        continue
    tags = fm["tags"] if isinstance(fm["tags"], list) else [fm["tags"]]
    notes.append({
        "updated": fm["updated"],
        "body": body,
        "tags": tags,
        "path": rel_path,
    })

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

out_lines = []
dates = sorted({note["updated"] for note in notes}, reverse=True)
for updated in dates:
    out_lines.append(f"## {updated}")
    out_lines.append("")
    for note in sorted((n for n in notes if n["updated"] == updated), key=lambda n: n["path"]):
        tag_run = " ".join(f"#{tag}" for tag in note["tags"])
        out_lines.append(f"{note['body']} {tag_run}")
        out_lines.append("")

dist_path = os.path.join(REPO_ROOT, "dist", "notes.md")
with open(dist_path, "w", encoding="utf-8") as f:
    f.write("\n".join(out_lines).rstrip("\n") + "\n")

print(f"build.sh: wrote dist/notes.md ({len(notes)} notes, {len(dates)} dates)", file=sys.stderr)
PYEOF

# 5. Commit the build artifact if inside a git repo with changes to commit.
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git -C "$REPO_ROOT" diff --quiet -- dist/notes.md 2>/dev/null || \
     [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- dist/notes.md)" ]]; then
    git -C "$REPO_ROOT" add dist/notes.md
    git -C "$REPO_ROOT" commit -m "build: regenerate dist/notes.md" --quiet || true
  fi
fi
