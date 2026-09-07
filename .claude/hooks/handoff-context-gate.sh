#!/bin/bash
# Stop. Ask for the handoff at a fraction of the context window, while there is still
# room to write one, instead of at the compaction cliff where the material is going.
#
# Two numbers, both read from the transcript, neither hardcoded:
#
#   context now   the last assistant message's usage.{input_tokens,
#                 cache_read_input_tokens, cache_creation_input_tokens}, summed. That
#                 sum is what the next request carries.
#   the window    every compaction boundary records preTokens, the context size at the
#                 moment it fired. The largest one this session has seen IS the
#                 auto-compact point, measured rather than assumed. Manual compactions
#                 land lower and max() ignores them.
#
# Learning it beats configuring it: the window moved from 200k to 1M without anything
# on disk changing, and a hardcoded threshold would have gone from sensible to firing
# at 15% of the window, which is the failure mode where a guard becomes noise and gets
# ignored. The learned value is cached so a fresh session starts calibrated.
#
# Self-clearing, no marker files: writing the doc updates its mtime, which silences it.
# stop_hook_active guards the re-entry loop. Every error path exits 0.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }

[ "$(j '.stop_hook_active')" = "true" ] && exit 0
SID=$(j '.session_id'); case "$SID" in ""|null) exit 0;; esac
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0
TR=$(j '.transcript_path'); [ -f "${TR:-}" ] || exit 0

CWD=$(j '.cwd'); case "$CWD" in ""|null) CWD="$(pwd)";; esac
. "$HOME/.claude/hooks/handoff-doc.sh" 2>/dev/null || exit 0
DOC=$(handoff_doc "$SID" "$CWD") || exit 0

CACHE="$HOME/.claude/handoff-window"
READ=$(python3 - "$TR" "$CACHE" <<'PY' 2>/dev/null
import json, os, re, sys
tr, cache = sys.argv[1], sys.argv[2]
ctx = None; window = 0
# Backwards in 1 MiB chunks for the current context: transcripts reach tens of MB.
with open(tr, "rb") as f:
    f.seek(0, 2); pos = f.tell(); buf = b""
    while pos > 0 and ctx is None:
        step = min(1 << 20, pos); pos -= step
        f.seek(pos); buf = f.read(step) + buf
        lines = buf.split(b"\n"); buf = lines[0] if pos > 0 else b""
        for ln in reversed(lines[1:] if pos > 0 else lines):
            if b'"usage"' not in ln: continue
            try: u = (json.loads(ln).get("message") or {}).get("usage") or {}
            except Exception: continue
            if u:
                ctx = sum(u.get(k, 0) for k in ("input_tokens",
                          "cache_read_input_tokens", "cache_creation_input_tokens"))
                break
if ctx is None: raise SystemExit
# Forward, cheaply, for boundaries. Regex over bytes beats parsing every line.
with open(tr, "rb") as f:
    for ln in f:
        if b'preTokens' not in ln: continue
        m = re.search(rb'"preTokens"\s*:\s*(\d+)', ln)
        if m: window = max(window, int(m.group(1)))
if window:
    try: open(cache, "w").write(str(window))
    except Exception: pass
elif os.path.exists(cache):
    try: window = int(open(cache).read().strip())
    except Exception: window = 0
print(ctx, window or 1000000)
PY
)
set -- ${READ:-}
CTX="${1:-}"; WIN="${2:-}"
case "${CTX}${WIN}" in ''|*[!0-9]*) exit 0;; esac
[ "$WIN" -gt 0 ] || exit 0

PCT="${HANDOFF_CTX_PCT:-70}"
LIMIT=$(( WIN * PCT / 100 ))
[ "$CTX" -lt "$LIMIT" ] && exit 0

AGE=$(( $(date +%s) - $(stat -c %Y "$DOC" 2>/dev/null || echo 0) ))
[ "$AGE" -lt 1800 ] && exit 0
USED=$(( CTX * 100 / WIN ))
MIN=$(( AGE / 60 ))

jq -nc --arg r "CONTEXT AT ${CTX} OF ${WIN} TOKENS (${USED}%, gate at ${PCT}%) and ${DOC} is ${MIN} min stale.

Write it now, from the full context you still hold, using the handoff skill's WRITE
procedure. At the compaction boundary it gets written from a summary instead, which is
how this document went stale in the first place.

The window figure is measured from this session's own compaction boundaries, not
assumed. This fires once per turn and stops as soon as the doc's mtime is current, so
writing it is what clears it." '{decision:"block", reason:$r}'
exit 0
