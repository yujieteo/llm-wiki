# LLM Wiki

A git-versioned, LLM-maintained wiki. Raw sources are immutable. Wiki notes are
LLM-written. Build compiles them into `dist/notes.md`. Publish imports that file
into your website notes.

## 5-minute start

1. `git clone <this-repo> && cd llm-wiki`
2. Create a private GitHub repository for this wiki and set it as `origin`.
3. `cp .env.example .env` and add your `OPENROUTER_API_KEY`.
4. Set `wiki.name`, `openrouter.model`, and `website.repo` in `config.yaml`.
5. Point your agent at `SKILLS.md` and say `drop this link: <url>`.
6. Say `ingest <source>` to create a note under `wiki/<topic>/`.
7. Say `compile the wiki` to review source changes and rebuild `wiki/index.md`.
8. Run `./build.sh` to compile all wiki notes into `dist/notes.md`.
9. Say `publish` to replace this wiki's imported section in the website notes file.

To create another private wiki, clone this repository into a new directory, set a
new private `origin`, and update `config.yaml`. Each clone keeps its sources,
notes, history, and website section separate.

## Layout
- `raw/sources/` — human-only, immutable
- `raw/links/`   — LLM-writable URL manifests
- `wiki/`        — LLM-owned notes; `index.md` is generated
- `skills/`      — one SKILL.md per capability; routed by `SKILLS.md`
- `scripts/`     — deterministic mechanical work; no LLM inside
- `dist/`        — committed build artifact; the public interface

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
