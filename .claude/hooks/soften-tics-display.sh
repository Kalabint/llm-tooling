#!/usr/bin/env bash
# MessageDisplay: rewrite verbal tics on screen instead of blocking the turn.
#
# The Stop guard blocks and forces a full re-emit. That is the right price for an
# unverified claim (PAR, ADV, HAZ, CMP), where the content has to change. It is the
# wrong price for a pure tic, where the word IS the whole problem and a re-emit
# spends a turn deleting two words. Those classes are handled here instead.
#
# GOTCHA. The input field is `delta`, the streaming chunk, not the finished message.
# "worth noting" arrives as "worth" then " noting", so a per-delta regex never sees
# the phrase. This carries a tail across deltas so a match spanning a chunk boundary
# still fires. A MessageDisplay hook that matches per delta silently does nothing.
#
# LIMIT, STATED. Display-only: the transcript and what Claude re-reads keep the
# original. The tic is hidden from the reader, not removed from the writer — so a
# word softened here will keep being emitted. That is the trade: cheaper than a
# re-emit, and it teaches nothing. Keep epistemic classes in the Stop guard.
set -u
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
delta=$(jq -r '.delta // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$delta" ] || exit 0
final=$(jq -r '.final // false' <<<"$payload" 2>/dev/null)
sid=$(jq -r '.session_id // "x"' <<<"$payload" 2>/dev/null)
mid=$(jq -r '.message_id // .messageId // .uuid // "m"' <<<"$payload" 2>/dev/null)

carry_dir="${TMPDIR:-/tmp}/claude-mdisp"
mkdir -p "$carry_dir" 2>/dev/null || exit 0
carry_f="$carry_dir/$(printf '%s-%s' "$sid" "$mid" | tr -c 'A-Za-z0-9._-' '_')"

# Longest phrase below, plus margin. Held back so a boundary-split phrase matches.
HOLD=28

carry=""
[ -f "$carry_f" ] && carry=$(cat "$carry_f" 2>/dev/null)
buf="$carry$delta"

# Substitutions. Cosmetic only — anything that signals an unverified claim belongs
# in the Stop guard, not here. sed -E, case-insensitive, longest first.
soften() {
  sed -E \
    -e 's/\bgenuinely\b/really/gI' \
    -e 's/\b(it is|it.s) worth (noting|saying|flagging) that\b//gI' \
    -e 's/\bworth (noting|knowing|saying|flagging)\b//gI' \
    -e 's/\bcuts both ways\b/applies in both directions/gI' \
    -e 's/\bthe tell\b/the signal/gI' \
    -e 's/\bload.bearing\b/critical/gI' \
    -e 's/  +/ /g'
}

if [ "$final" = "true" ]; then
  out=$(printf '%s' "$buf" | soften)
  rm -f "$carry_f" 2>/dev/null
else
  len=${#buf}
  if [ "$len" -gt "$HOLD" ]; then
    keep=$((len - HOLD))
    head_part=${buf:0:$keep}
    printf '%s' "${buf:$keep}" > "$carry_f" 2>/dev/null
    out=$(printf '%s' "$head_part" | soften)
  else
    printf '%s' "$buf" > "$carry_f" 2>/dev/null
    out=""
  fi
fi

# Emitting an empty displayContent for a non-final delta is intentional: the text
# is not lost, it is held in the carry and emitted with the next chunk.
jq -nc --arg d "$out" \
  '{hookSpecificOutput:{hookEventName:"MessageDisplay", displayContent:$d}}' 2>/dev/null
exit 0
