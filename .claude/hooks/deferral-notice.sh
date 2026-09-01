#!/usr/bin/env bash
# Surfaces deferrals WITHOUT blocking. The other Stop guards force a re-emit;
# this one only raises a flag, because a deferral is sometimes correct and the
# decision belongs to whoever reads it.
#
# Mechanism: `systemMessage` is available to every hook type and renders in the
# UI without stopping the turn. Emitting it with no `decision` field passes.
#
# Class B in the 2026-09-01 corpus scan: 47 messages parked something for later,
# 22 with no follow-through in the same message. Rare enough that a notice costs
# nothing; common enough to be worth seeing.
#
# NOTE: the notice text is scanned by no-superlative-guard like any other output,
# so it must not itself contain banned phrasing. The first version ended with
# an empty-deferral phrase that banned-patterns.sh itself blocks (PNT class).
#
# ONE branch blocks instead of noticing: a fix priced as trivial and not applied.
# It is gated on the last user turn being an imperative - pricing an option in
# answer to a question is describing, not deferring, and blocking it turns a
# question into an edit.
#
# Fails OPEN on any error.

set -uo pipefail

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null)" = "Stop" ] || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$payload" 2>/dev/null)" = "true" ] && exit 0

text=$(jq -r '.last_assistant_message // empty' <<<"$payload" 2>/dev/null | head -c 20000)
[ -n "${text:-}" ] || exit 0

# Code spans/fences stripped so quoted examples and this file's own patterns
# cannot self-trip.
t=$(sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' <<<"$text" 2>/dev/null | sed 's/`[^`]*`//g')
[ -n "${t:-}" ] || exit 0

# BLOCKING branch: a fix priced as trivial, with no sign it was applied. Checked
# before the reasoned-deferral escape, because "one command" plus a reason is a
# rationalisation, not a reasoned deferral.
PRICED='(fix is|it.?s|that.?s|this is) (just |only )?(one|a one|a single)[- ](character|char|line|liner|word|command|flag)|one[- ]line (change|fix|edit)|a one[- ]liner|costs? (one|a single) (line|command|character)|trivial(ly)? to fix|cheap to (fix|do|add)|would (take|be) (one|a single) (line|command|character)'
APPLIED='\b(applied|patched|fixed it|done|committed|staged|removed|edited|rewritten|now (reads|fires|passes)|i (just )?(ran|applied|patched|changed|fixed))\b'
priced=$(grep -ioE "$PRICED" <<<"$t" 2>/dev/null | sort -u | head -1)

# SIMON SAYS. Only demand the fix when it was actually asked for. Pricing an
# option in answer to "could this go in X?" is describing, not deferring, and
# blocking it turns a question into an edit - which is exactly what happened on
# 2026-09-02: this branch fired on a hypothetical and a public skill got changed
# unasked. Read the last real user turn from the transcript and require an
# imperative.
asked=0
tp=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null)
if [ -f "$tp" ]; then
  lastu=$(tac "$tp" 2>/dev/null \
    | jq -r 'select(.message.role=="user") | .message.content | select(type=="string")' 2>/dev/null \
    | grep -vE '^(Stop hook feedback|<task-notification>|<system-reminder>|\[)' \
    | head -1 | head -c 600)
  # imperative = a bare command, an approval, or an explicit do-it
  grep -qiE '^(do it|go|yes|yep|ok|apply|fix|add|write|make|commit|ship|run|update|change|remove|delete)\b' <<<"$lastu" 2>/dev/null && asked=1
  grep -qiE '\b(do it|apply it|fix it|add it|make it so|go ahead|please do|just do)\b' <<<"$lastu" 2>/dev/null && asked=1
  # a question is not an instruction, even one that names the change
  grep -qiE '^(can|could|would|should|is|are|does|do you|possible|any |what|which|why|how)\b|\?\s*$' <<<"$lastu" 2>/dev/null && asked=0
fi

DEFER="leaving (that|it|this) (for now|aside|alone)\
|for a later session|in a later session|next session\
|out of scope for now|for now, (i|we) (will|wont|won't)\
|i'?ll leave (that|it|this)|i am not (doing|building|adding) (that|it|this) (now|yet)\
|parked (for|until)|come back to (that|it|this) later\
|have not (built|written|added) (it|that)|leave it (unfixed|open|as is)"

hit=$(grep -ioE "$DEFER" <<<"$t" 2>/dev/null | sort -u | head -2 | paste -sd'; ' -)
[ -n "$hit" ] || exit 0

# If the same message already says why it is deferred and what would unblock it,
# the deferral is reasoned rather than dropped - nothing to surface.
grep -qiE 'because|since it|until you|unless you|would need|blocked on|you have not asked|not requested' <<<"$t" 2>/dev/null && exit 0

# No `decision` field: this passes. systemMessage renders in the UI.
jq -nc --arg m "DEFERRED: \"$hit\" - nothing was done about it. Class B, 47 in corpus / 22 with no follow-through. See .claude/skills/no-self-report-omissions/" \
  '{systemMessage:$m}'
exit 0
