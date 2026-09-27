#!/usr/bin/env bash
# scripts/build-index.sh — regenerate wiki/index.md from note frontmatter.
# Deterministic. No LLM calls.
#
# Behavior (see spec §6.2):
#   1. Glob wiki/**/*.md, excluding wiki/index.md, wiki/.diffs/**, wiki/.queue/**.
#   2. For each, extract title, summary, tags, updated, and the relative path.
#   3. Sort by topic (directory name), then updated descending.
#   4. Write wiki/index.md as a markdown table.
#   5. Exit 0. If any note is missing a required field, print the offending
#      path to stderr, exit 1, and write no index (no partial output).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 - "$REPO_ROOT" <<'PYEOF'
import os
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "scripts", "lib"))
from frontmatter import split_frontmatter  # noqa: E402

REPO_ROOT = sys.argv[1]
WIKI_DIR = os.path.join(REPO_ROOT, "wiki")
REQUIRED = ["title", "tags", "source", "updated", "summary"]

rows = []
errors = []

for root, dirs, files in os.walk(WIKI_DIR):
    rel_root = os.path.relpath(root, WIKI_DIR)
    parts = [] if rel_root == "." else rel_root.split(os.sep)
    # Exclude wiki/.diffs/** and wiki/.queue/** entirely.
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
        fm, _body = split_frontmatter(text)
        if fm is None:
            errors.append(f"wiki/{rel_path}: missing frontmatter")
            continue
        missing = [k for k in REQUIRED if not fm.get(k)]
        if missing:
            errors.append(f"wiki/{rel_path}: missing required field(s): {', '.join(missing)}")
            continue
        topic = parts[0] if parts else "(root)"
        tags = fm.get("tags")
        if isinstance(tags, list):
            tags_str = ", ".join(str(t) for t in tags)
        else:
            tags_str = str(tags)
        rows.append({
            "title": fm["title"],
            "summary": fm["summary"],
            "tags": tags_str,
            "updated": fm["updated"],
            "path": f"wiki/{rel_path}",
            "topic": topic,
        })

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

rows.sort(key=lambda r: (r["topic"], r["updated"]), reverse=False)
# Sort by topic ascending, then updated descending within topic.
rows.sort(key=lambda r: r["topic"])
from itertools import groupby
grouped = []
for topic, group in groupby(rows, key=lambda r: r["topic"]):
    g = sorted(group, key=lambda r: r["updated"], reverse=True)
    grouped.extend(g)
rows = grouped

lines = ["# Wiki Index", "", "| Title | Summary | Tags | Updated | Path |", "|---|---|---|---|---|"]
for r in rows:
    lines.append(f"| {r['title']} | {r['summary']} | {r['tags']} | {r['updated']} | {r['path']} |")
lines.append("")

with open(os.path.join(WIKI_DIR, "index.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"build-index.sh: wrote wiki/index.md ({len(rows)} notes)", file=sys.stderr)
PYEOF
