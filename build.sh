#!/usr/bin/env bash
# build.sh — deterministically concatenate all wiki notes into dist/notes.md.
# No LLM runs in this path (invariant §2.4).
#
# Behavior (see spec §8):
#   1. Glob wiki/**/*.md, excluding wiki/index.md, wiki/.diffs/**, wiki/.queue/**.
#   2. Sort by topic (directory), then by updated descending.
#   3. For each note: emit "### <title>" then the note body (frontmatter
#      stripped). Precede each topic group with "## <topic>".
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
from itertools import groupby

sys.path.insert(0, os.path.join(sys.argv[1], "scripts", "lib"))
from frontmatter import split_frontmatter  # noqa: E402

REPO_ROOT = sys.argv[1]
WIKI_DIR = os.path.join(REPO_ROOT, "wiki")
REQUIRED = ["title", "tags", "source", "updated", "summary"]

notes = []
errors = []

for root, dirs, files in os.walk(WIKI_DIR):
    rel_root = os.path.relpath(root, WIKI_DIR)
    parts = [] if rel_root == "." else rel_root.split(os.sep)
    if parts and parts[0] in (".diffs", ".queue"):
        dirs[:] = []
        continue
    for fname in sorted(files):
        if not fname.endswith(".md"):
            continue
        rel_path = os.path.normpath(os.path.join(rel_root, fname)) if rel_root != "." else fname
        if rel_path == "index.md":
            continue
        full_path = os.path.join(root, fname)
        with open(full_path, "r", encoding="utf-8") as f:
            text = f.read()
        fm, body = split_frontmatter(text)
        if fm is None:
            errors.append(f"wiki/{rel_path}: missing frontmatter")
            continue
        missing = [k for k in REQUIRED if not fm.get(k)]
        if missing:
            errors.append(f"wiki/{rel_path}: missing required field(s): {', '.join(missing)}")
            continue
        topic = parts[0] if parts else "(root)"
        notes.append({
            "title": fm["title"],
            "updated": fm["updated"],
            "body": body.strip("\n"),
            "topic": topic,
        })

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

notes.sort(key=lambda n: n["topic"])
ordered = []
for topic, group in groupby(notes, key=lambda n: n["topic"]):
    g = sorted(group, key=lambda n: n["updated"], reverse=True)
    ordered.append((topic, g))

out_lines = []
for topic, group in ordered:
    out_lines.append(f"## {topic}")
    out_lines.append("")
    for note in group:
        out_lines.append(f"### {note['title']}")
        out_lines.append("")
        out_lines.append(note["body"])
        out_lines.append("")

dist_path = os.path.join(REPO_ROOT, "dist", "notes.md")
with open(dist_path, "w", encoding="utf-8") as f:
    f.write("\n".join(out_lines).rstrip("\n") + "\n")

print(f"build.sh: wrote dist/notes.md ({len(notes)} notes, {len(ordered)} topics)", file=sys.stderr)
PYEOF

# 5. Commit the build artifact if inside a git repo with changes to commit.
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git -C "$REPO_ROOT" diff --quiet -- dist/notes.md 2>/dev/null || \
     [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- dist/notes.md)" ]]; then
    git -C "$REPO_ROOT" add dist/notes.md
    git -C "$REPO_ROOT" commit -m "build: regenerate dist/notes.md" --quiet || true
  fi
fi
