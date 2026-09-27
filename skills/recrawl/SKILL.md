---
name: recrawl
description: Refresh all raw/links/ URLs and flag changed or dead links.
---

# Recrawl

## Steps
1. Run `scripts/recrawl.sh`.
2. Report: links crawled, links changed (diffs produced), links dead.
3. Do not commit. Diffs are consumed by `compile`.
