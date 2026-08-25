#!/bin/bash
# SessionStart: surface a reminder when the memory audit is >=14 days overdue.
# Silent otherwise. Always exits 0. Scoped to projects that have a memory dir.
IN=$(cat)
CWD=$(printf '%s' "$IN" | jq -r '.cwd' 2>/dev/null); case "$CWD" in ""|null) CWD="$(pwd)";; esac
ENC=$(printf '%s' "$CWD" | sed 's#/#-#g')
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0   # only nag in projects with memories

STAMP="$HOME/.claude/skills/memory-audit/.last_audit"
INTERVAL=14
if [ -f "$STAMP" ]; then
  LAST=$(cat "$STAMP" 2>/dev/null)
  LAST_EPOCH=$(date -d "$LAST" +%s 2>/dev/null) || LAST_EPOCH=0
  AGE_DAYS=$(( ( $(date +%s) - LAST_EPOCH ) / 86400 ))
else
  LAST="never"; AGE_DAYS=999
fi
[ "$AGE_DAYS" -ge "$INTERVAL" ] || exit 0

MSG="Memory-audit due (last run: $LAST, ${AGE_DAYS}d ago; 14-day cadence). Offer to run the /memory-audit skill on this project's memories: flag backfire-risk / stale / contradictory / redundant / bloated entries and LIST them (do not auto-correct)."
jq -nc --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
