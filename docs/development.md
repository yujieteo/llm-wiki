# Development

Build, test and CI details for llm-wiki. Moved out of the README; content unchanged.

## Checks

Run the offline self-test with:

```sh
python3 scripts/check.py
```

It needs no LLM API key and makes no network calls: it copies the repo into a
temporary directory and exercises the deterministic paths end to end —
`build.sh` and `scripts/build-index.sh` idempotency and output shape, the
`scripts/append-notes.sh` publish flow against a local bare repo (including the
500-added-line guardrail), and `scripts/llm-call.sh` locking and 429 backoff
against a fake `curl`. It also asserts the static portability invariants (no
`flock`, no `mapfile`, a single push site). On success it prints
`check.py: all checks passed`.

CI (`.github/workflows/ci.yml`) runs the same self-test plus structural checks
(`bash -n` on every shell script and `python3 -m py_compile` on the Python
sources) on every push to `main` and every pull request. No secrets are
required.

## Generated outputs

Two committed files are generated and must not be edited by hand:

- `dist/notes.md` — the public interface. `./build.sh` globs `wiki/**/*.md`
  (excluding `wiki/index.md`, `wiki/.diffs/**`, and `wiki/.queue/**`), validates
  each note's frontmatter and single-paragraph body, groups the paragraphs by
  `updated` date, appends each note's tags, and writes the result. The script
  commits the artifact when it changes.
- `wiki/index.md` — the note index. `bash scripts/build-index.sh` rebuilds the
  markdown table from note frontmatter (`title`, `summary`, `tags`, `updated`,
  `path`), sorted by topic then update date.

Regenerate both with `./build.sh && bash scripts/build-index.sh` after changing
notes. The check suite asserts both are idempotent, so hand edits will be
overwritten on the next build.
