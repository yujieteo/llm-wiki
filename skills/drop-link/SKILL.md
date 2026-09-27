---
name: drop-link
description: Capture a web URL into raw/links/<topic>.md for later ingestion.
---

# Drop Link

## Never
- Never write to `raw/sources/`.
- Never commit secrets.

## Steps
1. Fetch the URL. Extract title.
2. Determine topic slug; default to `uncategorized`.
3. Append a YAML entry to `raw/links/<topic>.md` with:
   `url`, `title`, `dropped` (today), `last_crawled: null`,
   `status: pending`, `hash: null`.
4. Skip if `url` already present.
5. `git add raw/links/<topic>.md && git commit -m "drop-link: <title>"`.
6. Report: file, topic, total URL count in manifest.
