# LLM Wiki

A general-purpose, git-versioned, LLM-maintained wiki. Raw sources are
immutable. Wiki notes are LLM-written. Build compiles them into `dist/notes.md`.
Publish imports that file into your website notes using the same
dated-paragraph format as `site/data/notes.md`.

This is not a wiki about LLMs; it is a wiki an LLM maintains. Clone it to keep
any topic you like, and let an agent ingest sources, write notes, and publish
them to your site.

## 5-minute start

1. Clone the repo and enter it:
   ```sh
   git clone git@github.com:yujieteo/llm-wiki.git && cd llm-wiki
   ```
2. Create a private repository for your wiki and point `origin` at it (or keep
   the clone and set your own remote).
3. Copy the environment template and add your `OPENROUTER_API_KEY`:
   ```sh
   cp .env.example .env
   ```
4. Set `wiki.name`, `openrouter.model`, and `website.repo` in `config.yaml`.
5. Point your agent at `SKILLS.md` and say `drop this link: <url>`.
6. Say `ingest <source>` to create a note under `wiki/<topic>/`.
7. Say `compile the wiki` to review source changes and rebuild `wiki/index.md`.
8. Run `./build.sh` to compile all wiki notes into `dist/notes.md`.
9. Say `publish` to merge the compiled dated notes into the website notes file.

To create another private wiki, clone this repository into a new directory, set a
new private `origin`, and update `config.yaml`. Each clone keeps its sources,
notes, history, and website section separate.

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

## Layout
- `raw/sources/` — human-only, immutable
- `raw/links/`   — LLM-writable URL manifests
- `wiki/`        — LLM-owned notes; `index.md` is generated
- `skills/`      — one SKILL.md per capability; routed by `SKILLS.md`
- `scripts/`     — deterministic mechanical work; no LLM inside
- `dist/`        — committed build artifact; the public interface
- `.github/`     — CI workflow for the self-test and structural checks

## Agent entry point

Point any agent (Codex, Claude Code, or a local dev loop) at **`SKILLS.md`**
first. It is a pure router: it lists the hard prohibitions that hold across
every skill, and maps a trigger phrase to exactly one `skills/*/SKILL.md`
file. Agents load one skill at a time and never chain skills within a single
invocation.

## Invariants

See `SKILLS.md` for the enforced prohibitions. The full list of non-negotiable
invariants (provenance, immutability of `raw/sources/`, no LLM in the build
path, script-mediated publishing, human confirmation for diffs and
cross-wiki merges, no forced pushes, no retried pushes, three-way publish
verification) is documented in the implementation spec this repo was built
from.

## Requirements

- Bash 3.2 or newer
- Git, curl, and Python 3
- One `OPENROUTER_API_KEY`. Set the model in `config.yaml` under
  `openrouter.model`.
