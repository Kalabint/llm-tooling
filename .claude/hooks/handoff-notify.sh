#!/bin/bash
# UserPromptSubmit: PreCompact saw a stale handoff doc and steered the compaction
# summary at it. That reaches the agent through the summary; this is the second,
# independent path, so a summariser that ignored the instruction still gets caught.
# One-shot, and it fires whether or not the compaction has happened yet.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$IN" | jq -r '.session_id' 2>/dev/null); case "$SID" in ""|null) exit 0;; esac
N="$HOME/.claude/handoff-pending/${SID}.notify"
[ -f "$N" ] || exit 0
MIN=$(sed -n 1p "$N"); DOC=$(sed -n 2p "$N")
rm -f "$N" 2>/dev/null                       # one-shot: never nag twice
[ -n "${DOC:-}" ] || exit 0
jq -nc --arg c "HANDOFF DOC STALE AT COMPACTION: $DOC was ${MIN} min stale when a compaction ran. Update it via the handoff skill's WRITE mode before other work. Write it from whatever context you still hold; if that is a compaction summary, say so in the doc rather than presenting reconstructed detail as firsthand." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
exit 0
