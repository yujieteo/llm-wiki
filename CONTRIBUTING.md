# Contributing

- Run `python3 scripts/check.py` before opening a PR; CI runs it too.
- Do not hand-edit `dist/notes.md` or `wiki/index.md`; regenerate them with
  `./build.sh && bash scripts/build-index.sh`.
- Never edit `raw/sources/` (human-only) or commit `.env` or API keys.
- Keep scripts portable to Bash 3.2 (no `flock`, no `mapfile`); `check.py`
  enforces this.
- Agent guidance lives in `SKILLS.md` and `skills/`. Keep each skill small and
  put situational detail in its own sub-skill.

See [docs/development.md](docs/development.md) for how the checks work.
