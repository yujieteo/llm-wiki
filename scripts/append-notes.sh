#!/usr/bin/env bash
# scripts/append-notes.sh — the ONLY path by which this repo ever touches
# the website repo (invariant §2.6).
#
# Behavior (see spec §6.3):
#   1. Read website.repo/branch/notes_path/section_header from config.yaml.
#   2. Clone to a temp dir (or pull a cached clone at .cache/website).
#   3. git checkout <branch> && git pull.
#   5. Append "\n\n<section_header>\n\n" + contents of dist/notes.md.
#   6. Guardrail: abort before committing if the diff exceeds 500 added lines.
#   7. git add / commit.
#   8. git push origin <branch>. Never --force. Never retried on failure.
#   9. Print the new commit SHA to stdout.
#  10. Exit 0 on success, non-zero on failure. Print last 5 stderr lines on failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "$1" >&2
  exit 1
}

# 1. Read config (one value per line, in a fixed order).
CFG_VALUES=()
while IFS= read -r value; do
  CFG_VALUES+=("$value")
done < <(python3 - "$REPO_ROOT/config.yaml" <<'PYEOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()

def get(pattern, default=""):
    m = re.search(pattern, text, re.MULTILINE)
    return m.group(1).strip() if m else default

repo = get(r"^\s*repo:\s*(.+)$")
branch = get(r"^\s*branch:\s*(.+)$", "main")
notes_path = get(r"^\s*notes_path:\s*(.+)$", "notes.md")
header = get(r'^\s*section_header:\s*(.+)$', "## LLM Wiki").strip('"').strip("'")
print(repo)
print(branch)
print(notes_path)
print(header)
PYEOF
)

WEBSITE_REPO="${CFG_VALUES[0]:-}"
WEBSITE_BRANCH="${CFG_VALUES[1]:-main}"
NOTES_PATH="${CFG_VALUES[2]:-notes.md}"
SECTION_HEADER="${CFG_VALUES[3]:-## LLM Wiki}"

if [[ -z "$WEBSITE_REPO" || "$WEBSITE_REPO" == *"<user>"* ]]; then
  fail "append-notes.sh: website.repo is not configured in config.yaml"
fi

if [[ ! -f "$REPO_ROOT/dist/notes.md" ]]; then
  fail "append-notes.sh: dist/notes.md not found — run build.sh first"
fi

# 2. Clone (or reuse a cached clone) of the website repo.
CACHE_DIR="$REPO_ROOT/.cache/website"
mkdir -p "$REPO_ROOT/.cache"

if [[ -d "$CACHE_DIR/.git" ]]; then
  GIT_STDERR="$(git -C "$CACHE_DIR" fetch origin 2>&1)"
  if [[ $? -ne 0 ]]; then
    echo "$GIT_STDERR" | tail -5 >&2
    fail "append-notes.sh: failed to fetch cached website clone"
  fi
else
  rm -rf "$CACHE_DIR"
  GIT_STDERR="$(git clone "$WEBSITE_REPO" "$CACHE_DIR" 2>&1)"
  if [[ $? -ne 0 ]]; then
    echo "$GIT_STDERR" | tail -5 >&2
    fail "append-notes.sh: failed to clone website repo"
  fi
fi

# 3. checkout & pull.
GIT_STDERR="$( { git -C "$CACHE_DIR" checkout "$WEBSITE_BRANCH" && git -C "$CACHE_DIR" pull origin "$WEBSITE_BRANCH"; } 2>&1)"
if [[ $? -ne 0 ]]; then
  echo "$GIT_STDERR" | tail -5 >&2
  fail "append-notes.sh: failed to checkout/pull website branch"
fi

TARGET_FILE="$CACHE_DIR/$NOTES_PATH"
mkdir -p "$(dirname "$TARGET_FILE")"
touch "$TARGET_FILE"

# 4 & 5. Replace the previous section (if present) and append the new one.
python3 - "$TARGET_FILE" "$SECTION_HEADER" "$REPO_ROOT/dist/notes.md" <<'PYEOF'
import re, sys

target_path, header, notes_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(target_path, "r", encoding="utf-8") as f:
    content = f.read()

with open(notes_path, "r", encoding="utf-8") as f:
    new_notes = f.read().rstrip("\n")

match = re.search(rf"(?m)^{re.escape(header)}\s*$", content)
content = content[:match.start()].rstrip("\n") if match else content.rstrip("\n")

if content:
    content = content + "\n\n" + header + "\n\n" + new_notes + "\n"
else:
    content = header + "\n\n" + new_notes + "\n"

with open(target_path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

# 6. Guardrail: abort if the diff is too large.
cd "$CACHE_DIR"
DIFF_STAT="$(git diff --stat -- "$NOTES_PATH")"
ADDED_LINES="$(git diff --numstat -- "$NOTES_PATH" | awk '{sum += $1} END {print sum+0}')"

if [[ "$ADDED_LINES" -gt 500 ]]; then
  fail "append-notes.sh: diff for $NOTES_PATH adds $ADDED_LINES lines (> 500), aborting before commit"
fi

if git diff --quiet -- "$NOTES_PATH" && [[ -z "$(git status --porcelain -- "$NOTES_PATH")" ]]; then
  # Nothing changed — still report the current HEAD SHA as "the" published SHA.
  CURRENT_SHA="$(git rev-parse HEAD)"
  echo "$CURRENT_SHA"
  exit 0
fi

# 7. Commit.
GIT_STDERR="$(git add "$NOTES_PATH" 2>&1 && git commit -m "wiki: import dist/notes.md" 2>&1)"
if [[ $? -ne 0 ]]; then
  echo "$GIT_STDERR" | tail -5 >&2
  fail "append-notes.sh: commit failed"
fi

# 8. Push. Never --force. Never retried here — a failure is surfaced as-is.
GIT_STDERR="$(git push origin "$WEBSITE_BRANCH" 2>&1)"
PUSH_EXIT=$?
if [[ "$PUSH_EXIT" -ne 0 ]]; then
  echo "$GIT_STDERR" | tail -5 >&2
  fail "append-notes.sh: git push failed (no retry)"
fi

# 9. Print new commit SHA to stdout.
git rev-parse HEAD
exit 0
