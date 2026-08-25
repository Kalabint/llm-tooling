#!/bin/bash
# SessionStart: bring the agent up current by injecting the handoff as additionalContext.
#   source=compact -> prefer this session's pre-compact safety net (firsthand recent state)
#   startup/resume  -> the curated *_session_handoff.md near cwd
# Always exits 0. Matcher is omitted in settings (fires on every SessionStart); the
# branching on .source lives here so we don't depend on matcher-regex semantics.
IN=$(cat)
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
SID=$(j '.session_id'); case "$SID" in ""|null) SID="unknown";; esac
# Only auto-load for sessions where the handoff skill was used at least once
# (else a fresh/unrelated session gets irrelevant details injected).
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0
SRC=$(j '.source')
CWD=$(j '.cwd'); case "$CWD" in ""|null) CWD="$(pwd)";; esac

CONTENT=""; HDR=""
if [ "$SRC" = "compact" ]; then
  NET="$HOME/.claude/handoff-safetynet/$SID.md"
  [ -f "$NET" ] && { CONTENT=$(cat "$NET"); HDR="pre-compact safety net (raw, re-verify)"; }
fi
if [ -z "$CONTENT" ]; then
  for f in "$CWD"/*_session_handoff.md "$CWD"/HANDOFF.md "$CWD"/docs/handoff*.md \
           "$(dirname "$CWD")"/*_session_handoff.md; do
    [ -f "$f" ] && { CONTENT=$(cat "$f"); HDR="curated handoff: $f"; break; }
  done
fi
[ -z "$CONTENT" ] && exit 0

PREFIX="SESSION HANDOFF loaded ($HDR). Read it. For any factual claim, prefer firsthand source (code/git) over this doc - it can be stale or a summary."
jq -nc --arg ctx "$PREFIX"$'\n\n'"$CONTENT" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
