#!/usr/bin/env python3
"""Mechanical pre-pass for the memory-audit skill.

Lists the project's persistent memory files with age/size and shortlists
stale-marker / bloat / oldest candidates, so the audit starts from a focused
list instead of re-reading everything. Stamps .last_audit (resets the 14-day
surfacing timer) unless --no-stamp.

Usage: python3 scan.py [--dir <memory_dir>] [--no-stamp]
Default memory dir is derived from cwd: ~/.claude/projects/<cwd-with-slashes-as-dashes>/memory
"""
import argparse
import glob
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--dir", help="memory dir (default: derive from cwd)")
ap.add_argument("--no-stamp", action="store_true")
args = ap.parse_args()


def project_memdir():
    enc = os.getcwd().replace("/", "-")
    return os.path.expanduser(f"~/.claude/projects/{enc}/memory")


memdir = args.dir or project_memdir()
if not os.path.isdir(memdir):
    print(f"no memory dir at {memdir}", file=sys.stderr)
    sys.exit(1)

# markers that often signal a stale point-in-time status claim
STALE = re.compile(
    r"\b(UNCOMMITTED|unpushed|not yet (?:done|built|pushed|merged)|NOT yet|PLANNED\b|"
    r"not built|unbuilt|TODO|NEXT STEP|in progress|will build|to build|doesn't exist|"
    r"neither page exists|not (?:fixed|merged|pushed))\b",
    re.I,
)

now = time.time()
files = sorted(
    f for f in glob.glob(os.path.join(memdir, "*.md"))
    if os.path.basename(f) != "MEMORY.md"
)
rows = []
for f in files:
    st = os.stat(f)
    age = int((now - st.st_mtime) / 86400)
    txt = open(f, errors="ignore").read()
    markers = sorted({m.group(0).lower() for m in STALE.finditer(txt)})
    rows.append((os.path.basename(f), age, st.st_size, markers))

idx = os.path.join(memdir, "MEMORY.md")
idx_kb = os.path.getsize(idx) // 1024 if os.path.exists(idx) else 0
print(f"# memory-audit pre-pass - {memdir}")
print(f"{len(rows)} memories | MEMORY.md index = {idx_kb} KB (budget ~24)")

print("\n## stale-marker candidates (point-in-time status; verify vs repo before trusting):")
hits = [r for r in rows if r[3]]
for name, age, size, mk in sorted(hits, key=lambda r: -r[1]):
    print(f"  {name}  ({age}d, {size}b)  -> {', '.join(mk)}")
if not hits:
    print("  (none)")

print("\n## bloat candidates (>4500 b - one memory should be one fact):")
big = [r for r in rows if r[2] > 4500]
for name, age, size, mk in sorted(big, key=lambda r: -r[2]):
    print(f"  {name}  {size}b")
if not big:
    print("  (none)")

print("\n## oldest (fact-rot risk):")
for name, age, size, mk in sorted(rows, key=lambda r: -r[1])[:8]:
    print(f"  {name}  {age}d")

if not args.no_stamp:
    stamp = time.strftime("%Y-%m-%d")
    open(os.path.join(HERE, ".last_audit"), "w").write(stamp)
    print(f"\nstamped .last_audit = {stamp} (next surfacing in 14 days)")
