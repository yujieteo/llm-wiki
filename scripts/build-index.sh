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
from frontmatter import read_notes  # noqa: E402

REPO_ROOT = sys.argv[1]
WIKI_DIR = os.path.join(REPO_ROOT, "wiki")

rows = []
errors = []

for rel_path, topic, fm, _body, error in read_notes(WIKI_DIR):
    if error:
        errors.append(error)
        continue
    tags = fm["tags"]
    rows.append({
        "title": fm["title"],
        "summary": fm["summary"],
        "tags": ", ".join(str(t) for t in tags) if isinstance(tags, list) else str(tags),
        "updated": fm["updated"],
        "path": f"wiki/{rel_path}",
        "topic": topic,
    })

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

# Topic ascending, then updated descending within a topic. Both sorts are
# stable, so notes with the same topic and date keep their walk order.
rows.sort(key=lambda r: r["updated"], reverse=True)
rows.sort(key=lambda r: r["topic"])

lines = ["# Wiki Index", "", "| Title | Summary | Tags | Updated | Path |", "|---|---|---|---|---|"]
for r in rows:
    lines.append(f"| {r['title']} | {r['summary']} | {r['tags']} | {r['updated']} | {r['path']} |")
lines.append("")

with open(os.path.join(WIKI_DIR, "index.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"build-index.sh: wrote wiki/index.md ({len(rows)} notes)", file=sys.stderr)
PYEOF
