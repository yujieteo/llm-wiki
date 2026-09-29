#!/usr/bin/env bash
# scripts/new-wiki.sh — deploy a fresh, generic wiki from this template.
# Deterministic. No LLM calls. No network. Never pushes.
#
# Usage:
#   bash scripts/new-wiki.sh <target-dir> [options]
#
# Options:
#   --name NAME        wiki.name in config.yaml (default: basename of target-dir)
#   --section HEADER   website.section_header (default: "## NAME")
#   --site-repo URL    website.repo, the site repo that publish writes to
#   --model MODEL      openrouter.model
#   --remote URL       set `origin` for the new wiki (it is not pushed)
#   --no-commit        stage the files but skip the initial commit
#
# Behavior:
#   1. Copy the tracked template files (from HEAD when run from a git clone,
#      otherwise from the working tree) into <target-dir>, which must be new
#      or empty. No .git, .env, or local caches come along.
#   2. Reset content: empty raw/sources/, raw/links/ and wiki/, and write an
#      empty wiki/index.md and dist/notes.md.
#   3. Write the given settings into config.yaml and create .env from
#      .env.example.
#   4. `git init -b main` with a single fresh commit — no template history.

set -euo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '4,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

TARGET=""
NAME=""
SECTION=""
SITE_REPO=""
MODEL=""
REMOTE=""
COMMIT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)      [[ $# -ge 2 ]] || usage; NAME="$2"; shift 2 ;;
    --section)   [[ $# -ge 2 ]] || usage; SECTION="$2"; shift 2 ;;
    --site-repo) [[ $# -ge 2 ]] || usage; SITE_REPO="$2"; shift 2 ;;
    --model)     [[ $# -ge 2 ]] || usage; MODEL="$2"; shift 2 ;;
    --remote)    [[ $# -ge 2 ]] || usage; REMOTE="$2"; shift 2 ;;
    --no-commit) COMMIT=0; shift ;;
    -h|--help)   usage ;;
    -*)          echo "new-wiki.sh: unknown option: $1" >&2; usage ;;
    *)
      [[ -z "$TARGET" ]] || usage
      TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || usage

if [[ -e "$TARGET" ]]; then
  if [[ ! -d "$TARGET" ]] || [[ -n "$(ls -A "$TARGET")" ]]; then
    echo "new-wiki.sh: $TARGET exists and is not an empty directory" >&2
    exit 1
  fi
fi
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

if [[ "$TARGET" == "$SRC_ROOT" ]]; then
  echo "new-wiki.sh: target must differ from the template repo" >&2
  exit 1
fi

[[ -n "$NAME" ]] || NAME="$(basename "$TARGET")"
[[ -n "$SECTION" ]] || SECTION="## $NAME"

# 1. Copy the template files.
if git -C "$SRC_ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  git -C "$SRC_ROOT" archive --format=tar HEAD | tar -x -C "$TARGET"
else
  (cd "$SRC_ROOT" && tar -cf - \
    --exclude=./.git --exclude=./.env --exclude=./.cache \
    --exclude=__pycache__ --exclude=./wiki/.queue --exclude=./wiki/.diffs \
    --exclude=./.claude/settings.local.json .) | tar -x -C "$TARGET"
  for f in "$TARGET"/.env.*; do
    [[ "$f" == "$TARGET/.env.example" ]] || rm -f "$f"
  done
fi

# 2. Reset content to an empty wiki.
rm -rf "$TARGET/raw/sources" "$TARGET/raw/links" "$TARGET/wiki"
mkdir -p "$TARGET/raw/sources" "$TARGET/raw/links" "$TARGET/wiki" "$TARGET/dist"
: > "$TARGET/raw/sources/.gitkeep"
: > "$TARGET/raw/links/.gitkeep"
printf '# Wiki Index\n\n| Title | Summary | Tags | Updated | Path |\n|---|---|---|---|---|\n' \
  > "$TARGET/wiki/index.md"
printf '\n' > "$TARGET/dist/notes.md"

# 3. Settings.
python3 - "$TARGET/config.yaml" "$NAME" "$SECTION" "$SITE_REPO" "$MODEL" <<'PYEOF'
import json
import re
import sys

path, name, section, site_repo, model = sys.argv[1:6]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()


def put(text, parent, key, value, quote=False):
    """Replace `key:` inside the top-level `parent:` block."""
    rendered = json.dumps(value) if quote else value
    pattern = r"(?m)(^%s:\n(?:[ \t]+.*\n)*?[ \t]+%s:)[ \t]*.*$" % (
        re.escape(parent), re.escape(key))
    new, count = re.subn(pattern, lambda m: m.group(1) + " " + rendered, text, count=1)
    if count != 1:
        sys.exit("new-wiki.sh: config.yaml has no %s.%s" % (parent, key))
    return new


text = put(text, "wiki", "name", name, quote=not re.match(r"^[A-Za-z0-9._-]+$", name))
text = put(text, "website", "section_header", section, quote=True)
if site_repo:
    text = put(text, "website", "repo", site_repo)
if model:
    text = put(text, "openrouter", "model", model)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF

if [[ ! -e "$TARGET/.env" ]]; then
  cp "$TARGET/.env.example" "$TARGET/.env"
fi

# 4. Fresh git history.
git -C "$TARGET" init -q
git -C "$TARGET" symbolic-ref HEAD refs/heads/main
git -C "$TARGET" add -A
if [[ -n "$REMOTE" ]]; then
  git -C "$TARGET" remote add origin "$REMOTE"
fi
if [[ "$COMMIT" -eq 1 ]]; then
  if ! git -C "$TARGET" commit -q -m "init: $NAME from llm-wiki template"; then
    echo "new-wiki.sh: initial commit failed (set git user.name/user.email)." >&2
    echo "new-wiki.sh: files are staged in $TARGET; commit them yourself." >&2
    exit 1
  fi
fi

echo "new-wiki.sh: created $NAME in $TARGET" >&2
echo "Next steps:" >&2
echo "  cd \"$TARGET\"" >&2
echo "  edit .env                          # set OPENROUTER_API_KEY" >&2
if [[ -z "$SITE_REPO" ]]; then
  echo "  edit config.yaml                   # set website.repo" >&2
fi
if [[ -n "$REMOTE" ]]; then
  echo "  git push -u origin main            # first push" >&2
else
  echo "  git remote add origin <url> && git push -u origin main" >&2
fi
