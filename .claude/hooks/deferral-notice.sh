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
