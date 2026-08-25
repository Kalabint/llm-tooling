#!/bin/bash
# PreToolUse(Skill): when the handoff skill is invoked, mark this session
# "handoff-active" so the PreCompact / SessionStart hooks only engage for sessions
# where handoff is actually in use (otherwise they'd inject irrelevant details).
# Grep on the raw tool input is robust to the exact field name of the skill arg.
IN=$(cat)
SID=$(printf '%s' "$IN" | jq -r '.session_id // "unknown"' 2>/dev/null)
if printf '%s' "$IN" | grep -qi '"handoff"'; then
  mkdir -p "$HOME/.claude/handoff-active" 2>/dev/null
  touch "$HOME/.claude/handoff-active/$SID" 2>/dev/null
fi
exit 0
