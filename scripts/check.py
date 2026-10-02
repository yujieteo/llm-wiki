#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GIT_ENV = {
    **os.environ,
    "GIT_AUTHOR_NAME": "llm-wiki check",
    "GIT_AUTHOR_EMAIL": "check@example.invalid",
    "GIT_COMMITTER_NAME": "llm-wiki check",
    "GIT_COMMITTER_EMAIL": "check@example.invalid",
}


def run(args, cwd, env=None, ok=True):
    result = subprocess.run(
        args,
        cwd=str(cwd),
        env=env or GIT_ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if ok and result.returncode:
        raise AssertionError(
            "{} failed\nstdout:\n{}\nstderr:\n{}".format(
                " ".join(args), result.stdout, result.stderr
            )
        )
    return result


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def git(args, cwd):
    return run(["git"] + args, cwd)


def set_config(repo, website_repo=None, attempts=None):
    path = repo / "config.yaml"
    text = path.read_text(encoding="utf-8")
    if website_repo is not None:
        text = re.sub(r"(?m)^  repo: .*$", "  repo: " + str(website_repo), text)
        text = re.sub(r"(?m)^  notes_path: .*$", "  notes_path: notes.md", text)
    if attempts is not None:
        text = re.sub(
            r"(?m)^  backoff_attempts: \d+$",
            "  backoff_attempts: " + str(attempts),
            text,
        )
    path.write_text(text, encoding="utf-8")


def clone_source(destination):
    shutil.copytree(
        ROOT,
        destination,
        ignore=shutil.ignore_patterns(".git", ".cache", "__pycache__"),
    )
    git(["init", "-q", "-b", "main"], destination)
    git(["add", "."], destination)
    git(["commit", "-qm", "fixture"], destination)


def check_build(repo):
    note = """---
title: Deterministic note
tags: [test, stable]
source: raw/sources/test.md
updated: 2026-09-27
summary: A fixed note
---
Body text.
"""
    write(repo / "wiki/topic/note.md", note)
    run(["bash", "build.sh"], repo)
    first_dist = (repo / "dist/notes.md").read_bytes()
    run(["bash", "scripts/build-index.sh"], repo)
    first_index = (repo / "wiki/index.md").read_bytes()
    run(["bash", "build.sh"], repo)
    run(["bash", "scripts/build-index.sh"], repo)
    assert (repo / "dist/notes.md").read_bytes() == first_dist
    assert (repo / "wiki/index.md").read_bytes() == first_index
    assert "## 2026-09-27" in first_dist.decode()
    assert "Body text. #test #stable" in first_dist.decode()
    assert "| Deterministic note | A fixed note | test, stable | 2026-09-27 | wiki/topic/note.md |" in first_index.decode()


def check_invalid_notes(base):
    """build.sh and build-index.sh refuse unusable notes, name each one, and write nothing."""
    repo = base / "invalid"
    clone_source(repo)
    good = "---\ntitle: Good\ntags: [a]\nsource: s\nupdated: 2026-09-27\nsummary: s\n---\nFine.\n"
    write(repo / "wiki/a/good.md", good)
    write(repo / "wiki/a/bare.md", "No frontmatter.\n")
    write(repo / "wiki/b/empty.md", good.replace("summary: s", "summary: "))
    write(repo / "wiki/b/two.md", good.replace("Fine.", "One.\n\nTwo."))
    write(repo / "wiki/.queue/skipped.md", "Queued, never read.\n")
    before = [(repo / p).read_bytes() for p in ("dist/notes.md", "wiki/index.md")]
    build = run(["bash", "build.sh"], repo, ok=False)
    assert build.returncode == 1
    frontmatter_errors = [
        "wiki/a/bare.md: missing frontmatter",
        "wiki/b/empty.md: missing required field(s): summary",
    ]
    body_error = "wiki/b/two.md: body must be one Markdown paragraph without a heading"
    assert sorted(build.stderr.splitlines()) == sorted(frontmatter_errors + [body_error]), build.stderr
    index = run(["bash", "scripts/build-index.sh"], repo, ok=False)
    assert index.returncode == 1
    assert sorted(index.stderr.splitlines()) == sorted(frontmatter_errors), index.stderr
    assert [(repo / p).read_bytes() for p in ("dist/notes.md", "wiki/index.md")] == before


def seed_site(base):
    bare = base / "site.git"
    site = base / "site"
    bare.mkdir()
    site.mkdir()
    git(["init", "-q", "--bare"], bare)
    git(["init", "-q", "-b", "main"], site)
    write(site / "notes.md", "---\ntitle: Notes\n---\n\n## 2026-09-26\n\nOld note. #old\n")
    git(["add", "notes.md"], site)
    git(["commit", "-qm", "seed"], site)
    git(["remote", "add", "origin", str(bare)], site)
    git(["push", "-q", "-u", "origin", "main"], site)
    git(["symbolic-ref", "HEAD", "refs/heads/main"], bare)
    return bare


def remote_notes(bare, checkout):
    if checkout.exists():
        shutil.rmtree(checkout)
    git(["clone", "-q", str(bare), str(checkout)], bare.parent)
    return (checkout / "notes.md").read_text(encoding="utf-8")


def check_publish(repo, base):
    bare = seed_site(base)
    set_config(repo, website_repo=bare)
    write(repo / "dist/notes.md", "## 2026-09-27\n\nFirst note. #test\n")
    run(["bash", "scripts/append-notes.sh"], repo)
    published = remote_notes(bare, base / "readback")
    assert published == "---\ntitle: Notes\n---\n\n## 2026-09-27\n\nFirst note. #test\n\n## 2026-09-26\n\nOld note. #old\n"

    run(["bash", "scripts/append-notes.sh"], repo)
    assert remote_notes(bare, base / "readback") == published

    write(repo / "dist/notes.md", "## 2026-09-27\n\nSecond note. #test\n")
    run(["bash", "scripts/append-notes.sh"], repo)
    published = remote_notes(bare, base / "readback")
    assert "Second note. #test\n\nFirst note. #test" in published
    assert published.count("## 2026-09-27") == 1

    write(repo / "dist/notes.md", "## 2026-09-28\n\n" + "\n\n".join("Note {}. #test".format(i) for i in range(501)) + "\n")
    result = run(["bash", "scripts/append-notes.sh"], repo, ok=False)
    assert result.returncode != 0
    assert "> 500" in result.stderr
    assert remote_notes(bare, base / "readback") == published


def fake_curl(path, body, delay=False):
    sleep = (
        'if ! mkdir "$FAKE_STATE/active" 2>/dev/null; then touch "$FAKE_STATE/overlap"; fi\n'
        '/bin/sleep 0.2\nrmdir "$FAKE_STATE/active"'
        if delay
        else ":"
    )
    write(
        path,
        """#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then out="$2"; shift 2; else shift; fi
done
{sleep}
printf '%s' '{body}' > "$out"
printf '%s' '{code}'
""".format(
            sleep=sleep,
            body=body,
            code="200" if delay else "429",
        ),
    )
    path.chmod(0o755)


def check_llm(repo, base):
    set_config(repo, attempts=1)
    prompt = repo / "prompt.txt"
    write(prompt, "prompt")
    fake_bin = base / "fake-bin"
    fake_bin.mkdir()
    fake_curl(fake_bin / "curl", '{"error":"rate limited"}')
    env = {
        **GIT_ENV,
        "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
        "OPENROUTER_API_KEY": "secret",
    }
    lock = repo / "wiki/.queue/.llm-call.lock"
    lock.mkdir(parents=True)
    write(lock / "pid", "99999999\n")
    result = run(
        ["bash", "scripts/llm-call.sh", str(prompt), str(repo / "response.json")],
        repo,
        env=env,
        ok=False,
    )
    assert result.returncode != 0
    pending = json.loads((repo / "wiki/.queue/pending.json").read_text(encoding="utf-8"))
    assert pending["task"] == "ingest"
    assert pending["remaining"] == [str(prompt)]
    assert not lock.exists()

    fake_curl(fake_bin / "curl", '{"ok":true}', delay=True)
    state = base / "curl-state"
    state.mkdir()
    env["FAKE_STATE"] = str(state)
    (repo / "wiki/.queue/pending.json").unlink()
    first = subprocess.Popen(
        ["bash", "scripts/llm-call.sh", str(prompt), str(repo / "one.json")],
        cwd=str(repo),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    second = subprocess.Popen(
        ["bash", "scripts/llm-call.sh", str(prompt), str(repo / "two.json")],
        cwd=str(repo),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert first.communicate(timeout=10)[0] == ""
    assert second.communicate(timeout=10)[0] == ""
    assert first.returncode == second.returncode == 0
    assert (repo / "one.json").read_text() == '{"ok":true}'
    assert (repo / "two.json").read_text() == '{"ok":true}'
    assert not (state / "overlap").exists()


def check_new_wiki(repo, base):
    target = base / "fresh-wiki"
    write(repo / "raw/sources/old.md", "template content\n")
    git(["add", "raw/sources/old.md"], repo)
    git(["commit", "-qm", "template source"], repo)
    run(
        [
            "bash", "scripts/new-wiki.sh", str(target),
            "--name", "fresh-wiki",
            "--site-repo", "git@example.invalid:me/site.git",
            "--model", "test/model",
            "--remote", "git@example.invalid:me/fresh-wiki.git",
        ],
        repo,
    )
    log = git(["log", "--format=%s"], target).stdout.splitlines()
    assert log == ["init: fresh-wiki from llm-wiki template"], log
    assert git(["rev-parse", "--abbrev-ref", "HEAD"], target).stdout.strip() == "main"
    assert git(["status", "--porcelain"], target).stdout == ""
    assert git(["config", "remote.origin.url"], target).stdout.strip()
    config = (target / "config.yaml").read_text(encoding="utf-8")
    assert "  name: fresh-wiki\n" in config
    assert "  model: test/model\n" in config
    assert "  repo: git@example.invalid:me/site.git\n" in config
    assert '  section_header: "## fresh-wiki"\n' in config
    assert (target / ".env").is_file()
    assert git(["ls-files", ".env"], target).stdout == ""
    assert sorted(p.name for p in (target / "raw/sources").iterdir()) == [".gitkeep"]
    assert [p.name for p in (target / "wiki").iterdir()] == ["index.md"]
    assert (target / "dist/notes.md").read_text(encoding="utf-8") == "\n"
    run(["bash", "build.sh"], target)
    run(["bash", "scripts/build-index.sh"], target)
    assert git(["status", "--porcelain"], target).stdout == ""
    assert run(["bash", "scripts/new-wiki.sh", str(target)], repo, ok=False).returncode


def check_static():
    llm = (ROOT / "scripts/llm-call.sh").read_text(encoding="utf-8")
    publish = (ROOT / "scripts/append-notes.sh").read_text(encoding="utf-8")
    assert "flock" not in llm
    assert "mapfile" not in llm + publish
    assert "mkdir \"$LOCK_DIR\"" in llm
    assert publish.count('git push origin "$WEBSITE_BRANCH"') == 1
    assert '[[ "$ADDED_LINES" -gt 500 ]]' in publish
    assert "## (\\d{4}-\\d{2}-\\d{2})" in publish


def main():
    check_static()
    with tempfile.TemporaryDirectory(prefix="llm-wiki-check-") as tmp:
        base = Path(tmp)
        repo = base / "wiki"
        clone_source(repo)
        check_build(repo)
        check_invalid_notes(base)
        check_publish(repo, base)
        check_llm(repo, base)
        check_new_wiki(repo, base)
    print("check.py: all checks passed")


if __name__ == "__main__":
    main()
