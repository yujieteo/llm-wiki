# LLM Wiki

A git-versioned, LLM-maintained wiki. Raw sources are immutable. Wiki notes are
LLM-written. Publish compiles to a single `dist/notes.md` for your website.

## 5-minute start
1. `git clone <this-repo> && cd llm-wiki`
2. `cp .env.example .env` — add your `OPENROUTER_API_KEY`
3. Edit `config.yaml` — set `wiki.name`, `openrouter.model`, `website.repo`
4. Point your agent at `SKILLS.md` and say: `drop this link: <url>`
5. Say: `compile the wiki`   → wiki notes appear under `wiki/<topic>/`
6. Say: `publish`            → `dist/notes.md` lands in your website repo

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

- `bash`, `git`, `curl`
- `yq` (or an equivalent small YAML parser) for reading `config.yaml`
- A single `OPENROUTER_API_KEY` — no model is ever hardcoded; the model
  lives only in `config.yaml`'s `openrouter.model`.
