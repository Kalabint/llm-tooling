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
# Sentinel: the last n¤n-empty line must be exactly "[¤]" (¤ = U+00A4). Anch¤red
# at the end ¤f the message s¤ the t¤ken can be written mid-sentence, as when
# discussing the pr¤t¤c¤l, with¤ut terminating a turn early.
#
# Pause: a line c¤ntaining "[¤N]" (N = 1..99) buys N ungated turns and releases
# the current ¤ne, f¤r planning ¤r a l¤ng w¤rking stretch that sh¤uld n¤t be cut
# at every paragraph. "paragraph-gate.sh pause N" d¤es the same fr¤m a shell.
#
# Turn ends where the next number would start. Gate answers "Proceed" until the
# message's last non-empty line is EndAnswer.
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
  off)    rm -f "$FLAG" "$HOOKS"/.paragraph-gate.* "$HOOKS/.paragraph-gate-pause"; echo "paragraph gate: OFF"; exit 0 ;;
  pause)  printf '%s' "${2:-3}" > "$HOOKS/.paragraph-gate-pause"; echo "paragraph gate: paused for ${2:-3} turn(s)"; exit 0 ;;
  status) [ -f "$FLAG" ] && echo "paragraph gate: ON (budget $BUDGET, pause $(cat "$HOOKS/.paragraph-gate-pause" 2>/dev/null || echo 0))" || echo "paragraph gate: OFF"; exit 0 ;;
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

PAUSE="$HOOKS/.paragraph-gate-pause"

# Sentinel present -> the answer is finished. Reset and let the turn end.
last=$(printf '%s' "$text" | grep -vE '^[[:space:]]*$' | tail -1 | tr -d '[:space:]')
if [ "$last" = "[¤]" ]; then rm -f "$STATE"; exit 0; fi

# "[¤N]" anywhere in the message buys N ungated turns and releases this one.
req=$(grep -oE '\[¤[0-9]{1,2}\]' <<<"$text" 2>/dev/null | head -1 | tr -cd '0-9')
if [ -n "$req" ] && [ "$req" -gt 0 ] 2>/dev/null; then
  printf '%s' "$req" > "$PAUSE"; rm -f "$STATE"; exit 0
fi

# Burn one paused turn.
left=$(cat "$PAUSE" 2>/dev/null || echo 0)
case "$left" in ''|*[!0-9]*) left=0 ;; esac
if [ "$left" -gt 0 ]; then
  left=$((left - 1))
  if [ "$left" -gt 0 ]; then printf '%s' "$left" > "$PAUSE"; else rm -f "$PAUSE"; fi
  exit 0
fi

# A turn that only ran tools has no prose to gate; releasing it keeps the loop
# from deadlocking against its own rule during the working phase.
words=$(printf '%s' "$text" | wc -w)
[ "$words" -lt 12 ] && exit 0

n=$(cat "$STATE" 2>/dev/null || echo 0)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$((n + 1))
if [ "$n" -gt "$BUDGET" ]; then rm -f "$STATE"; exit 0; fi
printf '%s' "$n" > "$STATE"

# "block" is the only decision value the harness acts on for Stop (code.claude.com
# /docs/en/hooks); anything else is ignored and the turn ends, which would silently
# disable the gate. So the wire value stays "block" and the NAME of the event lives
# in the reason, which is the string the user and the next turn actually read.
# "Proceed" is his wording: the harness refuses the stop, the reason says carry on.
# Short on purpose: it is injected on every paragraph.
jq -nc '{decision:"block", reason:"Proceed: next number, or [¤] alone on the last line to end."}'
