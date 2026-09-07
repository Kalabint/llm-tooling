#!/bin/bash
# PostToolUse(Write|Edit): when a handoff doc is written, record its path against
# the session. That path is what handoff_doc() reads first, so resolution stops
# depending on cwd — which is what broke the old loader (doc under ~/docker,
# cwd ~/docs, no glob reached it). Writing a handoff doc also marks the session
# handoff-active, so the gate no longer depends on the Skill tool being used.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
SID=$(j '.session_id'); case "$SID" in ""|null) exit 0;; esac
P=$(j '.tool_input.file_path'); case "$P" in ""|null) exit 0;; esac
case "$(basename "$P")" in
  *session_handoff*.md|*_handoff*.md|HANDOFF.md|handoff*.md) ;;
  *) exit 0 ;;
esac
[ -f "$P" ] || exit 0
mkdir -p "$HOME/.claude/handoff-active" 2>/dev/null
printf '%s\n' "$P" > "$HOME/.claude/handoff-active/$SID" 2>/dev/null
# the doc is fresh again: release any held compaction
exit 0
