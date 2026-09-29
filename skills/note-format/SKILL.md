---
name: note-format
description: Reference for the exact shape of a wiki note. Read only when writing or validating a note.
---

# Note format

Path: `wiki/<topic>/<slug>.md`.

```md
---
title: Short retrieval label
tags: [canonical-tag, second-tag]
source: raw/links/topic.md
updated: YYYY-MM-DD
summary: One-line retrieval summary
---
One self-contained Markdown paragraph with source links and no heading, list, blank line, or trailing tags.
```

- Required frontmatter: `title`, `tags`, `source`, `updated`, `summary`.
- `source` must point to an existing `raw/` entry.
- Body is exactly one paragraph: no heading, list, or blank line, and no
  trailing tags. `build.sh` appends `#tag` for each frontmatter tag.
- If the website has a tag registry, reuse its canonical tags.
- `build.sh` rejects notes with missing required fields or a body that is not
  one paragraph without a heading or blank line. `source` existence, no-list,
  and no-trailing-tags are checked only by lint/manual review.
