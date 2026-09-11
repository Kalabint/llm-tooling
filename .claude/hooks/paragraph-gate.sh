#!/usr/bin/env bash
# Paragraph-at-a-time answers. Stop -> block unless the message ends with the
# EndAnswer sentinel, so each numbered paragraph gets its own turn and every
# other Stop guard scans it in isolation before the next one is written.
#
# DEFAULT OFF. Enable per machine:
#   ~/.claude/hooks/paragraph-gate.sh on | off | status
# or per session by exporting PARAGRAPH_GATE=1.
#
# Runs LAST in the Stop chain on purpose: if a phrasing/cause/deferral guard has
# already blocked, that block is the one the user should see. This hook only
# decides whether an otherwise-clean message is allowed to END the turn.
#
# Sentinel: the last non-empty line must be exactly "EndAnswer". Anchored at the
# end of the message so that writing the word mid-sentence (as this comment does)
# cannot terminate a turn early.
#
# Budget: BUDGET consecutive gate-blocks per session, then the turn is released.
# A wiring mistake costs a handful of round trips, not a session.
#
# Fails OPEN on any error.

set -uo pipefail
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG="$HOOKS/.paragraph-gate-on"
BUDGET="${PARAGRAPH_GATE_BUDGET:-12}"

case "${1:-}" in
  on)     : > "$FLAG"; echo "paragraph gate: ON  (budget $BUDGET, sentinel 'EndAnswer')"; exit 0 ;;
  off)    rm -f "$FLAG" "$HOOKS"/.paragraph-gate.*; echo "paragraph gate: OFF"; exit 0 ;;
  status) [ -f "$FLAG" ] && echo "paragraph gate: ON (budget $BUDGET)" || echo "paragraph gate: OFF"; exit 0 ;;
esac

[ -f "$FLAG" ] || [ "${PARAGRAPH_GATE:-0}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
[ "$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null)" = "Stop" ] || exit 0

text=$(jq -r '.last_assistant_message // empty' <<<"$payload" 2>/dev/null | head -c 20000)
[ -n "$text" ] || exit 0

sid=$(jq -r '.session_id // "nosession"' <<<"$payload" 2>/dev/null)
STATE="$HOOKS/.paragraph-gate.$sid"

# Sentinel present -> the answer is finished. Reset and let the turn end.
last=$(printf '%s' "$text" | grep -vE '^[[:space:]]*$' | tail -1 | tr -d '[:space:]')
if [ "$last" = "EndAnswer" ]; then rm -f "$STATE"; exit 0; fi

# A turn that only ran tools has no prose to gate; releasing it keeps the loop
# from deadlocking against its own rule during the working phase.
words=$(printf '%s' "$text" | wc -w)
[ "$words" -lt 12 ] && exit 0

n=$(cat "$STATE" 2>/dev/null || echo 0)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$((n + 1))
if [ "$n" -gt "$BUDGET" ]; then rm -f "$STATE"; exit 0; fi
printf '%s' "$n" > "$STATE"

jq -nc --arg r "PARAGRAPH GATE ($n/$BUDGET): that paragraph is accepted and is already on the user's screen. Do NOT repeat it. Write ONLY the next numbered paragraph, then stop. When the answer is complete, put EndAnswer alone on the final line so this gate releases the turn." \
  '{decision:"block", reason:$r}'
