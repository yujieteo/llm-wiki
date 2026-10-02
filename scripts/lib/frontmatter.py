#!/usr/bin/env python3
"""
Minimal YAML-frontmatter parser for wiki notes.

Deliberately small and dependency-free (no PyYAML) so the build path has
zero external Python dependencies. Handles exactly the shapes used by
this repo's schemas (§5.1 / §5.2 in the spec):

    ---
    title: Some Title
    tags: [tag1, tag2]
    source: raw/sources/topic/file.md
    updated: 2026-09-27
    summary: One-line description
    ---
    body...

Also supports block-list style values:

    tags:
      - tag1
      - tag2

This is intentionally not a general YAML parser. It only needs to round-trip
the flat, single-document frontmatter this repo writes.
"""
import os
import re


def split_frontmatter(text):
    """Return (frontmatter_dict, body_str) or (None, text) if no frontmatter."""
    if not text.startswith("---"):
        return None, text
    # text starts with '---\n...\n---\nbody'
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, re.DOTALL)
    if not m:
        return None, text
    fm_raw, body = m.group(1), m.group(2)
    return parse_flat_yaml(fm_raw), body


def parse_flat_yaml(raw):
    """Parse a flat key: value block, with optional inline or block lists."""
    data = {}
    lines = raw.split("\n")
    i = 0
    key = None
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        block_item = re.match(r"^-\s*(.*)$", stripped)
        if block_item and key is not None and isinstance(data.get(key), list):
            data[key].append(_scalar(block_item.group(1)))
            i += 1
            continue
        kv = re.match(r"^([A-Za-z0-9_\-]+):\s*(.*)$", stripped)
        if kv:
            key = kv.group(1)
            val = kv.group(2).strip()
            if val == "":
                # Could be start of a block list on following lines.
                data[key] = []
            elif val.startswith("[") and val.endswith("]"):
                inner = val[1:-1].strip()
                data[key] = [
                    _scalar(x.strip()) for x in inner.split(",") if x.strip()
                ] if inner else []
            else:
                data[key] = _scalar(val)
        i += 1
    return data


def _scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1]
    if v == "null" or v == "~":
        return None
    return v



REQUIRED = ["title", "tags", "source", "updated", "summary"]


def read_notes(wiki_dir):
    """Yield (rel_path, topic, frontmatter, body, error) for every wiki note.

    Skips wiki/index.md and wiki/.diffs/, wiki/.queue/. Notes come in a stable
    walk order. error is None, or why the note's frontmatter is unusable
    (missing, or a required field empty); the build and the index both refuse
    such a note, so they share this one reading of the wiki.
    """
    for root, dirs, files in os.walk(wiki_dir):
        rel_root = os.path.relpath(root, wiki_dir)
        parts = [] if rel_root == "." else rel_root.split(os.sep)
        if parts and parts[0] in (".diffs", ".queue"):
            dirs[:] = []
            continue
        for fname in sorted(files):
            if not fname.endswith(".md"):
                continue
            rel_path = os.path.normpath(os.path.join(rel_root, fname)) if rel_root != "." else fname
            if rel_path == "index.md":
                continue
            with open(os.path.join(root, fname), "r", encoding="utf-8") as f:
                fm, body = split_frontmatter(f.read())
            topic = parts[0] if parts else "(root)"
            if fm is None:
                yield rel_path, topic, None, body, f"wiki/{rel_path}: missing frontmatter"
                continue
            missing = [k for k in REQUIRED if not fm.get(k)]
            error = f"wiki/{rel_path}: missing required field(s): {', '.join(missing)}" if missing else None
            yield rel_path, topic, fm, body, error
