#!/bin/bash
# UserPromptExpansion: catch `/compact` BEFORE it runs and convert it into a
# handoff turn, holding the user's compact instructions for the retry.
#
# The point is ordering. Compaction is the lossy step; a handoff written after it
# is written from the damage. This fires while the full conversation is still in
# context, so the doc is written from complete detail and compaction happens second.
#
# Logs every expansion payload (until settled) so the open question — do BUILT-IN
# commands reach this event, or only skills? — is answered by evidence.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
[ "$(j '.hook_event_name')" = "UserPromptExpansion" ] || exit 0

LOG="$HOME/.claude/hooks/expansion-events.jsonl"
printf '%s\n' "$IN" >> "$LOG" 2>/dev/null
tail -n 200 "$LOG" > "$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG" 2>/dev/null

CMD=$(j '.command_name'); CMD="${CMD#/}"
[ "$CMD" = "compact" ] || exit 0
SID=$(j '.session_id'); case "$SID" in ""|null) exit 0;; esac
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0   # only sessions using handoff

PEND="$HOME/.claude/handoff-pending/$SID"
mkdir -p "$HOME/.claude/handoff-pending" 2>/dev/null

# Second /compact after the handoff ran: let it through and clear the hold.
if [ -f "$PEND" ]; then rm -f "$PEND" 2>/dev/null; exit 0; fi

ARGS=$(j '.command_args'); case "$ARGS" in null) ARGS="";; esac
printf '%s\n' "$ARGS" > "$PEND" 2>/dev/null

CTX="COMPACTION HELD. You ran /compact, which was intercepted before it executed:
the full conversation is still in context right now, and it will not be after.

Do this now, in order:
1. Run the handoff WRITE procedure and update this session's handoff doc from the
   FULL context you still have — not from a summary.$( [ -n "$ARGS" ] && printf '\n2. Bias the doc toward what the user asked to keep: %s' "$ARGS" )
$( [ -n "$ARGS" ] && echo '3.' || echo '2.' ) Then tell the user the doc is written and to re-run /compact; the next one
   passes straight through.

Do not summarize into chat instead. The doc is the artifact that survives."

jq -nc --arg c "$CTX" \
  '{decision:"block", reason:"compaction held until the handoff doc is written",
    hookSpecificOutput:{hookEventName:"UserPromptExpansion",
                        additionalContext:$c, suppressOriginalPrompt:true}}'
exit 0
