#!/usr/bin/env bash
# scripts/llm-call.sh — the single point of contact for all LLM calls.
# Model-agnostic. Enforces serialization, backoff, and key handling.
#
# Usage: llm-call.sh <prompt-file> <output-file>
#
# Behavior (see spec §6.1):
#   1. Load .env
#   2. Read openrouter.model / openrouter.base_url from config.yaml
#   3. POST to ${base_url}/chat/completions
#   4. On 429: backoff 2/4/8/16/32s up to build.backoff_attempts; on
#      exhaustion, write wiki/.queue/pending.json and exit non-zero.
#   5. On success: write the response body to <output-file>, exit 0.
#   6. Never run two invocations in parallel — callers must serialize
#      (a lock file is used here as a belt-and-braces guard).
#   7. Never echo the API key.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROMPT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$PROMPT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "Usage: llm-call.sh <prompt-file> <output-file>" >&2
  exit 1
fi
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "llm-call.sh: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

# 1. Load environment (secrets never printed).
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
  set +a
fi

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "llm-call.sh: OPENROUTER_API_KEY is not set (copy .env.example to .env)" >&2
  exit 1
fi

# 2. Read model / base_url from config.yaml. No model is ever hardcoded here.
read -r MODEL BASE_URL BACKOFF_ATTEMPTS <<EOF_PY
$(python3 - "$REPO_ROOT/config.yaml" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path, "r", encoding="utf-8").read()

def get(pattern, default=""):
    m = re.search(pattern, text, re.MULTILINE)
    return m.group(1).strip() if m else default

model = get(r"^\s*model:\s*(.+)$")
base_url = get(r"^\s*base_url:\s*(.+)$")
backoff = get(r"^\s*backoff_attempts:\s*(\d+)", "5")
print(model, base_url, backoff)
PYEOF
)
EOF_PY

if [[ -z "$MODEL" || -z "$BASE_URL" ]]; then
  echo "llm-call.sh: could not read openrouter.model / openrouter.base_url from config.yaml" >&2
  exit 1
fi

# 6. Serialize: a single global lock so two invocations never overlap.
LOCK_DIR="$REPO_ROOT/wiki/.queue"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/.llm-call.lock"
exec 200>"$LOCK_FILE"
flock -w 300 200 || { echo "llm-call.sh: could not acquire serialization lock" >&2; exit 1; }

# Build the JSON request body from the prompt file, without ever echoing
# the key. jq is preferred if present; otherwise fall back to python3.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

python3 - "$MODEL" "$PROMPT_FILE" "$BODY_FILE" <<'PYEOF'
import json, sys
model, prompt_file, body_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(prompt_file, "r", encoding="utf-8") as f:
    prompt = f.read()
payload = {
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
}
with open(body_file, "w", encoding="utf-8") as f:
    json.dump(payload, f)
PYEOF

# 3 & 4. POST with backoff on 429.
BACKOFFS=(2 4 8 16 32)
MAX_ATTEMPTS="${BACKOFF_ATTEMPTS:-5}"
ATTEMPT=0
HTTP_CODE=""
RESP_FILE="$(mktemp)"

while [[ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]]; do
  set +e
  HTTP_CODE="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' \
    -X POST "${BASE_URL%/}/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    --data @"$BODY_FILE")"
  CURL_EXIT=$?
  set -e

  if [[ "$CURL_EXIT" -ne 0 ]]; then
    echo "llm-call.sh: curl failed (exit $CURL_EXIT)" >&2
    rm -f "$RESP_FILE"
    exit 1
  fi

  if [[ "$HTTP_CODE" == "429" ]]; then
    WAIT="${BACKOFFS[$ATTEMPT]:-32}"
    ATTEMPT=$((ATTEMPT + 1))
    if [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
      break
    fi
    echo "llm-call.sh: 429 received, backing off ${WAIT}s (attempt ${ATTEMPT}/${MAX_ATTEMPTS})" >&2
    sleep "$WAIT"
    continue
  fi

  if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    cp "$RESP_FILE" "$OUTPUT_FILE"
    rm -f "$RESP_FILE"
    exit 0
  fi

  echo "llm-call.sh: request failed with HTTP $HTTP_CODE" >&2
  cat "$RESP_FILE" >&2
  rm -f "$RESP_FILE"
  exit 1
done

# 4. Backoff exhausted on repeated 429s — write resumable queue state.
mkdir -p "$REPO_ROOT/wiki/.queue"
python3 - "$REPO_ROOT/wiki/.queue/pending.json" "$PROMPT_FILE" <<'PYEOF'
import json, sys, datetime
out_path, prompt_file = sys.argv[1], sys.argv[2]
state = {
    "task": "ingest",
    "remaining": [prompt_file],
    "started": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
PYEOF

rm -f "$RESP_FILE"
echo "llm-call.sh: rate limit backoff exhausted; wrote wiki/.queue/pending.json" >&2
exit 1
