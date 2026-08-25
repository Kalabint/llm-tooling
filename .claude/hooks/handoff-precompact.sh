#!/bin/bash
# PreCompact safety net. Captures FIRSTHAND recent state (the user's actual recent
# messages verbatim + git state) before compaction eats the conversation.
# Deliberately NOT a `claude -p` model summary - a summary institutionalizes a lossy,
# low-trust artifact (the firsthand-vs-summary failure mode). Stamped for re-verify.
# Always exits 0 so it can never block compaction.
IN=$(cat)
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
SID=$(j '.session_id'); case "$SID" in ""|null) SID="unknown";; esac
# Only engage for sessions where the handoff skill was used at least once.
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0
CWD=$(j '.cwd'); case "$CWD" in ""|null) CWD="$(pwd)";; esac
TR=$(j '.transcript_path')
DIR="$HOME/.claude/handoff-safetynet"; mkdir -p "$DIR" 2>/dev/null
OUT="$DIR/$SID.md"
{
  echo "# AUTO-CAPTURED pre-compact safety net"
  echo "> RAW state, not a curated handoff. RE-VERIFY every claim against source (code/git)."
  echo
  echo "- captured: $(date -Iseconds 2>/dev/null || date)"
  echo "- session: $SID"
  echo "- cwd: $CWD"
  if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    echo "- branch: $(git -C "$CWD" branch --show-current 2>/dev/null)"
    echo
    echo "## git status (firsthand)"; echo '```'
    git -C "$CWD" status --short 2>/dev/null | head -50; echo '```'
    echo "## last 8 commits"; echo '```'
    git -C "$CWD" log -8 --format='%h %s' 2>/dev/null; echo '```'
  fi
  if [ -n "$TR" ] && [ "$TR" != "null" ] && [ -f "$TR" ]; then
    echo
    echo "## last user messages (verbatim, firsthand)"
    jq -rs '[ .[] | select(.type=="user") | .message.content
              | if type=="string" then . else ([.[]?|select(.type=="text")|.text]|join(" ")) end ]
            | map(select(. != null and (startswith("[Request")|not) and (. != "")))
            | .[-15:][] | "- " + (gsub("\n";" ")|.[0:300])' < "$TR" 2>/dev/null
  fi
} > "$OUT" 2>/dev/null
exit 0
