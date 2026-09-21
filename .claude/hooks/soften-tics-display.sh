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
final=$(jq -r '.final // false' <<<"$payload" 2>/dev/null)
# An empty delta must NOT exit early when final is true: the carry still holds the
# tail of the message, and returning here drops it from the display entirely. The
# closing delta of a stream is routinely empty, so this lost the last sentence.
[ -n "$delta" ] || [ "$final" = "true" ] || exit 0
sid=$(jq -r '.session_id // "x"' <<<"$payload" 2>/dev/null)
mid=$(jq -r '.message_id // .messageId // .uuid // "m"' <<<"$payload" 2>/dev/null)

carry_dir="${TMPDIR:-/tmp}/claude-mdisp"
mkdir -p "$carry_dir" 2>/dev/null || exit 0
carry_f="$carry_dir/$(printf '%s-%s' "$sid" "$mid" | tr -c 'A-Za-z0-9._-' '_')"

# Cut only at a sentence end. Holding back a fixed N characters is not enough: the
# tail-carry keeps the last N, but a phrase that STARTS before that cut has already
# had its opening emitted, so "The honest reading" split as "The honest" + "reading"
# was passed through unchanged. No tic in the set below spans a sentence, so a
# terminator is a safe cut. FLUSH bounds the stall if a sentence never ends.
TERM='[.!?][])"'"'"']*[[:space:]]'
FLUSH=1200

carry=""
[ -f "$carry_f" ] && carry=$(cat "$carry_f" 2>/dev/null)
buf="$carry$delta"

# Substitutions. Cosmetic only — anything that signals an unverified claim belongs
# in the Stop guard, not here. sed -E, case-insensitive, longest first.
# This set mirrored the TIC class removed from banned-patterns.sh line 114 exactly
# until 2026-09-21, when the announce-preamble rules below were added on request.
# The INVARIANT is what must not drift, not the size of the set: nothing rewritten
# here may also be blocked by the Stop guard, or the reader sees softened text and
# then the turn blocks over words they never saw. Anything added here has to be run
# past no-superlative-guard.sh first and come back clean.
# `genuinely` deliberately stays out — banned-patterns VIRT still catches it in the
# "genuinely X rather than Y" construction, which is a claim shape, not a tic.
soften() {
  # Paired rules, case-SENSITIVE: a capitalised match gets a capitalised replacement.
  # The /I flag alone lowercased sentence starts ("Nobody wins." -> "the result is
  # debatable."). A generic capitalise-after-terminator pass was rejected because it
  # also hits "e.g. foo" and "i.e. foo".
  #
  # Announce preamble (user, 2026-09-21: "The limitation worth stating > banned.
  # preamble. this is a heading within a numbered list, so makes no sense
  # whatsoever" / "what is allowed is a Limits: XXX" / "simple filter / replace,
  # without reprompt"). A noun phrase that announces a point instead of making it.
  # Filter, not ban: no row in userban.tsv, so no block and no re-emit.
  #   limitation family -> the bare label the user asked for, "Limits: "
  #   every other announce noun -> preamble deleted, payload kept. Nothing is
  #   relabelled, because "the thing worth noting" is not a limitation.
  # _ptl requires a copula or a separator after the gerund, so the rule only fires
  # where the preamble is structurally a heading with its payload behind it;
  # "Two decisions worth flagging before we move on" is left alone rather than
  # butchered into "before we move on". _pad excludes the adjectives MSG blocks
  # (real|actual|true|genuine|big|hard|crux|central|important|interesting|tricky)
  # and the noun lists exclude MSG's gap|catch|one|part|bit, so "the part worth
  # noting" stays a block and never reaches a rewrite.
  local _pg='(stating|noting|mentioning|flagging|saying|highlighting|repeating|restating|emphasi[sz]ing|stressing|underlining|underscoring|spelling out|calling out|pointing out|knowing|remembering|bearing in mind|adding|recording|reporting|naming|surfacing)'
  local _pad='((only|main|first|second|third|final|last|remaining|other|obvious|practical|single|primary|chief|lone)[[:space:]]+)?'
  local _plim='(limitation|limit|caveat|constraint|exception|qualification|qualifier)s?'
  # Rule 3 sees the noun at the head of a list item, so it needs the capitalised
  # form too: sed is case-sensitive and "- Caveat worth mentioning" is the shape
  # the ban was issued for.
  local _plimc='([Ll]imitation|[Ll]imit|[Cc]aveat|[Cc]onstraint|[Ee]xception|[Qq]ualification|[Qq]ualifier)s?'
  local _pnoun='(thing|point|detail|nuance|subtlety|wrinkle|fact|finding|note|remark|observation|difference|distinction|item|aspect|consequence|implication|number|figure|result|issue|risk|decision|reason|lesson|takeaway|assumption|gotcha|warning|concern|problem|change)s?'
  local _ptl='([[:space:]]+(is|are)([[:space:]]+that)?[[:space:]]*[,:]?|[[:space:]]*([,:]|-{1,2}>|→))[[:space:]]+'
  sed -E \
    -e "s/\b(The|A|An|One|Another|Two|Three|Four|Five|Six|Several|Some|Both)[[:space:]]+${_pad}${_plim}[[:space:]]+worth[[:space:]]+${_pg}${_ptl}/Limits: /g" \
    -e "s/\b(the|a|an|one|another|two|three|four|five|six|several|some|both)[[:space:]]+${_pad}${_plim}[[:space:]]+worth[[:space:]]+${_pg}${_ptl}/limits: /g" \
    -e "s/^([[:space:]]*([0-9]+[.)]|[-*+>#])?[[:space:]]*)((The|A|An|One|Another|the|a|an|one|another)[[:space:]]+)?${_pad}${_plimc}[[:space:]]+worth[[:space:]]+${_pg}[[:space:]]*[,:]?[[:space:]]*$/\1Limits:/" \
    -e "s/\b(The|A|An|One|Another|Two|Three|Four|Five|Six|Several|Some|Both|the|a|an|one|another|two|three|four|five|six|several|some|both)[[:space:]]+${_pad}${_pnoun}[[:space:]]+worth[[:space:]]+${_pg}${_ptl}//g" \
    -e 's/\b(It|This|That) (is|.s) worth (noting|knowing|saying|having|flagging) that[,:]?[[:space:]]+//g' \
    -e 's/\b(it|this|that) (is|.s) worth (noting|knowing|saying|having|flagging) that[,:]?[[:space:]]+//g' \
    -e 's/\bWorth (noting|knowing|saying|having|flagging)\b/Notable/g' \
    -e 's/\bworth (Noting|Knowing|Saying|Having|Flagging|noting|knowing|saying|having|flagging)\b/notable/g' \
    -e 's/\b(The|the) (honest|real|actual|true) (answer|version|truth|reading|framing|one)\b/\1 \3/g' \
    -e 's/\bHow it lands\b/Its effect/g'   -e 's/\bhow it lands\b/its effect/g' \
    -e 's/\b(That|This|It|Which) lands\b/\1 reads/g' \
    -e 's/\b(that|this|it|which) lands\b/\1 reads/g' \
    -e 's/\bThe tell\b/The signal/g'       -e 's/\bthe tell\b/the signal/g' \
    -e 's/\bLoad.bearing\b/Critical/g'     -e 's/\bload.bearing\b/critical/g' \
    -e 's/\bcuts both ways\b/is bidirectional/g' \
    -e 's/\bCuts both ways\b/Is bidirectional/g' \
    -e 's/\b(Both sides|Everyone|Everybody) [Ll]os(e|es)\b/The result is debatable/g' \
    -e 's/\b(both sides|everyone|everybody) los(e|es)\b/the result is debatable/g' \
    -e 's/\bNobody wins\b/The result is debatable/g' \
    -e 's/\bnobody wins\b/the result is debatable/g' \
    -e 's/  +/ /g'
}

if [ "$final" = "true" ]; then
  out=$(printf '%s' "$buf" | soften)
  rm -f "$carry_f" 2>/dev/null
else
  # byte offset just past the last sentence terminator in the buffer
  cut=$(printf '%s' "$buf" | grep -boE "$TERM" 2>/dev/null | tail -1 | cut -d: -f1)
  if [ -n "$cut" ]; then
    cut=$((cut + 1))
  elif [ ${#buf} -gt "$FLUSH" ]; then
    cut=${#buf}                       # no terminator in sight: do not stall forever
  else
    cut=0
  fi
  if [ "$cut" -gt 0 ]; then
    printf '%s' "${buf:$cut}" > "$carry_f" 2>/dev/null
    out=$(printf '%s' "${buf:0:$cut}" | soften)
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
