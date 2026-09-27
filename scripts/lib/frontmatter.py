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
import re
import sys


def split_frontmatter(text):
    """Return (frontmatter_dict, body_str) or (None, text) if no frontmatter."""
    if not text.startswith("---"):
        return None, text
    parts = text.split("\n---", 1)
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


if __name__ == "__main__":
    # CLI helper: frontmatter.py <file> <field>
    # Prints the requested field's value (empty line if absent).
    path = sys.argv[1]
    field = sys.argv[2] if len(sys.argv) > 2 else None
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    fm, body = split_frontmatter(text)
    if fm is None:
        sys.exit(2)
    if field is None:
        for k, v in fm.items():
            print(f"{k}={v}")
    else:
        print(fm.get(field, ""))
