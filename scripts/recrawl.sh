#!/usr/bin/env bash
# scripts/recrawl.sh — fetch every URL in raw/links/, update last_crawled and
# hash, and flag changed/dead links.
#
# Behavior (see spec §6.4):
#   1. For each raw/links/*.md, parse the YAML.
#   2. For each link with status live or pending:
#      - Fetch the URL with a readability extractor (strip nav/footer/boilerplate).
#      - Compute sha256(normalized_body).
#      - Update last_crawled to today.
#      - hash null -> set it, set status: live. Done.
#      - hash matches -> no change.
#      - hash differs -> write a structured diff to wiki/.diffs/, do NOT
#        update the stored hash yet (it updates when the diff is applied).
#   3. On 404: set status: dead, do not diff. (Wayback fallback is a no-op
#      stub here unless WAYBACK_FALLBACK=1 is set in the environment.)
#   4. Serialize fetches with a 1-second delay between requests.
#   5. Exit 0.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p "$REPO_ROOT/raw/links" "$REPO_ROOT/wiki/.diffs"

shopt -s nullglob
LINK_FILES=("$REPO_ROOT"/raw/links/*.md)
shopt -u nullglob

if [[ ${#LINK_FILES[@]} -eq 0 ]]; then
  echo "recrawl.sh: no link manifests found under raw/links/" >&2
  exit 0
fi

for LINK_FILE in "${LINK_FILES[@]}"; do
  python3 - "$REPO_ROOT" "$LINK_FILE" <<'PYEOF'
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import urllib.error
import datetime

REPO_ROOT, LINK_FILE = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(REPO_ROOT, "scripts", "lib"))
from frontmatter import parse_flat_yaml  # noqa: E402

TOPIC = os.path.splitext(os.path.basename(LINK_FILE))[0]
TODAY = datetime.date.today().isoformat()

with open(LINK_FILE, "r", encoding="utf-8") as f:
    raw_text = f.read()

# --- Minimal manifest parser for the §5.2 shape (topic + links: list of
# flat dicts). Deliberately hand-rolled to avoid a PyYAML dependency.
lines = raw_text.split("\n")
topic_line = TOPIC
links = []
current = None
in_links = False
for line in lines:
    if line.startswith("topic:"):
        topic_line = line.split(":", 1)[1].strip()
        continue
    if line.strip() == "links:" and not line.startswith(" "):
        in_links = True
        continue
    if not in_links:
        continue
    m_item = re.match(r"^\s*-\s*url:\s*(.+)$", line)
    if m_item:
        if current is not None:
            links.append(current)
        current = {"url": m_item.group(1).strip()}
        continue
    m_field = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*)$", line)
    if m_field and current is not None:
        key, val = m_field.group(1), m_field.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        if val == "null" or val == "":
            val = None
        current[key] = val
if current is not None:
    links.append(current)

if not links:
    sys.exit(0)

crawled = 0
changed = 0
dead = 0

for link in links:
    status = link.get("status")
    if status not in ("live", "pending"):
        continue

    url = link["url"]
    req = urllib.request.Request(url, headers={"User-Agent": "llm-wiki-recrawl/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw_html = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            link["status"] = "dead"
            link["last_crawled"] = TODAY
            dead += 1
            if os.environ.get("WAYBACK_FALLBACK") == "1":
                # Stub: recording intent only; a full Wayback client is out
                # of scope for this build.
                link["sourceOrigin"] = "archive"
            time.sleep(1)
            continue
        else:
            link["last_crawled"] = TODAY
            time.sleep(1)
            continue
    except Exception:
        link["last_crawled"] = TODAY
        time.sleep(1)
        continue

    # Readability extraction: strip script/style/nav/footer/header, then tags.
    body = raw_html
    for tag in ("script", "style", "nav", "footer", "header", "aside"):
        body = re.sub(rf"<{tag}[^>]*>.*?</{tag}>", " ", body, flags=re.DOTALL | re.IGNORECASE)
    body = re.sub(r"<[^>]+>", " ", body)
    normalized = re.sub(r"\s+", " ", body).strip()
    new_hash = "sha256:" + hashlib.sha256(normalized.encode("utf-8")).hexdigest()

    old_hash = link.get("hash")
    link["last_crawled"] = TODAY
    crawled += 1

    if not old_hash:
        link["hash"] = new_hash
        link["status"] = "live"
    elif old_hash == new_hash:
        pass  # no change
    else:
        changed += 1
        diffs_dir = os.path.join(REPO_ROOT, "wiki", ".diffs")
        os.makedirs(diffs_dir, exist_ok=True)
        url_hash_short = new_hash.split(":", 1)[1][:12]
        diff_path = os.path.join(diffs_dir, f"{topic_line}-{url_hash_short}-{TODAY}.md")
        title = link.get("title", url)
        diff_text = f"""# Diff: {title}

**URL:** {url}
**Old hash:** {old_hash}
**New hash:** {new_hash}
**Detected:** {TODAY}

## Current
(see wiki note sourced from this link — regenerate by inspecting wiki/{topic_line}/)

## Proposed
Content at {url} has changed since the last crawl. Re-ingest to review the
updated body and decide what the wiki note should say.

## Reason
sha256(normalized_body) changed from {old_hash} to {new_hash}.

## Source
{url} (crawled {TODAY})
"""
        with open(diff_path, "w", encoding="utf-8") as df:
            df.write(diff_text)
        # Per spec: do not update the stored hash yet; it updates on apply.

    time.sleep(1)

# Rewrite the manifest, preserving field order per link as best-effort.
FIELD_ORDER = ["url", "title", "dropped", "last_crawled", "status", "hash"]
out_lines = [f"# raw/links/{TOPIC}.md", f"topic: {topic_line}", "links:"]
for link in links:
    out_lines.append(f"  - url: {link.get('url', '')}")
    for key in FIELD_ORDER[1:]:
        val = link.get(key)
        if key == "title" and val is not None:
            out_lines.append(f'    title: "{val}"')
        elif val is None:
            out_lines.append(f"    {key}: null")
        else:
            out_lines.append(f"    {key}: {val}")
    for key, val in link.items():
        if key in FIELD_ORDER:
            continue
        out_lines.append(f"    {key}: {val}")

with open(LINK_FILE, "w", encoding="utf-8") as f:
    f.write("\n".join(out_lines) + "\n")

print(f"recrawl.sh: {TOPIC}: crawled={crawled} changed={changed} dead={dead}", file=sys.stderr)
PYEOF
done

exit 0
