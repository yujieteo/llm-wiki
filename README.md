# LLM Wiki

A general-purpose, git-versioned, LLM-maintained wiki. Raw sources are
immutable. Wiki notes are LLM-written. Build compiles them into `dist/notes.md`.
Publish imports that file into your website notes using the same
dated-paragraph format as `site/data/notes.md`.

This is not a wiki about LLMs; it is a wiki an LLM maintains. Clone it to keep
any topic you like, and let an agent ingest sources, write notes, and publish
them to your site.

## 5-minute start

Deploy a fresh, generic wiki from this template. The new wiki gets its own
single-commit history — none of this repo's git history or notes come along.

1. Get the template and deploy a new wiki next to it:
   ```sh
   git clone https://github.com/yujieteo/llm-wiki.git
   bash llm-wiki/scripts/new-wiki.sh my-wiki \
     --site-repo git@github.com:<user>/<site>.git \
     --remote git@github.com:<user>/my-wiki.git
   cd my-wiki
   ```
   The template clone is only a source; you can delete it afterwards.
2. Put your `OPENROUTER_API_KEY` in `.env` (already created from
   `.env.example`, and git-ignored).
3. Push once: `git push -u origin main`.
4. Point your agent at `SKILLS.md` and say `drop this link: <url>`.
5. Say `ingest <source>` to create a note under `wiki/<topic>/`.
6. Say `compile the wiki` to review source changes and rebuild `wiki/index.md`.
7. Run `./build.sh` to compile all wiki notes into `dist/notes.md`.
8. Say `publish` to merge the compiled dated notes into the website notes file.

`new-wiki.sh` options (all optional):

| Option | Sets |
|---|---|
| `--name NAME` | `wiki.name` (default: the target directory's name) |
| `--section HEADER` | `website.section_header` (default: `## NAME`) |
| `--site-repo URL` | `website.repo` |
| `--model MODEL` | `openrouter.model` |
| `--remote URL` | the new wiki's `origin` (never pushed for you) |
| `--no-commit` | stage files but skip the initial commit |

It copies the template's committed files, empties `raw/`, `wiki/` and
`dist/notes.md`, writes your settings into `config.yaml`, and runs
`git init -b main` with one fresh commit. Run it again with another directory
to create another private wiki; each keeps its sources, notes, history, and
website section separate. Any existing wiki can also serve as the template —
its notes and sources are never copied.

## Build and test

```sh
./build.sh && bash scripts/build-index.sh   # regenerate dist/notes.md and wiki/index.md
python3 scripts/check.py                    # offline self-test; no API key, no network
```

`dist/notes.md` and `wiki/index.md` are generated; do not edit them by hand.
CI runs the same self-test plus `bash -n` / `py_compile` checks on every push
to `main` and every pull request. Details: [docs/development.md](docs/development.md).

## Layout
- `raw/sources/` — human-only, immutable
- `raw/links/`   — LLM-writable URL manifests
- `wiki/`        — LLM-owned notes; `index.md` is generated
- `skills/`      — one SKILL.md per capability; routed by `SKILLS.md`
- `docs/`        — development and CI details
- `scripts/`     — deterministic mechanical work; no LLM inside
                   (`new-wiki.sh` deploys a fresh wiki from this template)
- `dist/`        — committed build artifact; the public interface
- `.github/`     — CI workflow for the self-test and structural checks
- `config.yaml`, `.env.example` — settings and the API-key template

Contributing: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Agent entry point

Point any agent (Codex, Claude Code, or a local dev loop) at **`SKILLS.md`**
first. It is a pure router: it lists the hard prohibitions that hold across
every skill, and maps a trigger phrase to exactly one `skills/*/SKILL.md`
file. Agents load one skill at a time and never chain skills within a single
invocation, except to read `skills/note-format/SKILL.md` as a reference.

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
