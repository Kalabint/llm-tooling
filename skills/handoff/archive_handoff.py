#!/usr/bin/env python3
"""Snapshot a handoff into a numbered sibling version, then get out of the way.

Run this BEFORE rewriting a handoff. The live doc is copied to
  <repo-parent>/.handoff-history/<doc-name>/vNN_<UTC>.md
and left untouched, so the caller edits it normally. Nothing is ever destroyed
and the live doc stays small: history is separate files, read only on demand,
never loaded at session start.

Version files are named vNN so the resolver's `*handoff*<sid>*.md` glob cannot
match them and mistake a snapshot for the live doc.
"""
import sys, os, re, shutil
from datetime import datetime, timezone

def history_dir(path):
    base = os.path.basename(path)
    base = base[:-3] if base.endswith(".md") else base
    return os.path.join(os.path.dirname(os.path.abspath(path)), ".handoff-history", base)

def next_index(d):
    if not os.path.isdir(d):
        return 1
    ns = [int(m.group(1)) for f in os.listdir(d)
          if (m := re.match(r"v(\d+)_", f))]
    return max(ns, default=0) + 1

def main(path):
    if not os.path.isfile(path):
        sys.exit(f"no such handoff: {path}")
    if os.path.getsize(path) == 0:
        sys.exit("handoff is empty; nothing to archive")
    d = history_dir(path)
    os.makedirs(d, exist_ok=True)
    n = next_index(d)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%MZ")
    dest = os.path.join(d, f"v{n:02d}_{ts}.md")
    shutil.copyfile(path, dest)
    print(f"archived v{n:02d} -> {dest}\n{n} version(s) held; live doc untouched, edit it now")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: archive_handoff.py <handoff.md>")
    main(sys.argv[1])
