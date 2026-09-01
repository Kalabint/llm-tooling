#!/usr/bin/env bash
# Catches: "my earlier number was wrong / that makes the rest suspect" followed
# by nothing. Measured 2026-09-01 over the whole corpus: 91 such messages across
# 36 sessions, 84 of them (92%) with no re-run in the same message. An earlier
# count of 17/12 was itself an instance of the defect - the scan pre-filtered
# lines to five words before the regex ran, so the largest phrase group
# ("correction to what i", 21x) never reached the matcher.
# The admission is treated as the remedy. It is not - the stale number stays in
# the user's head and in whatever he built on it.
#
# The ONLY way past it is having actually re-run the thing. An earlier version
# also accepted "NOT REDONE: <reason>" - that was a loophole, since re-wording
# satisfies a Stop hook while the stale number stays published. Blocking Stop
# continues the turn, so tools are still available: the correct response is a
# tool call, not a re-draft. 91 hits in 16,237 assistant text messages, about
# 1 in 180.
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

# Code spans/fences stripped so this file's own examples cannot self-trip.
t=$(sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' <<<"$text" 2>/dev/null | sed 's/`[^`]*`//g')
[ -n "${t:-}" ] || exit 0

INVAL="my (earlier|previous|first|prior) (scan|count|number|measurement|reading|claim)s? (was|were|is|are) (wrong|off|incomplete|unreliable|suspect)\
|was a (scan |counting )?artefact|artifact of my\
|(that|which) means .{0,60}(are|is) also suspect\
|are (undercounts|unreliable|suspect)\
|i (had )?(undercounted|miscounted)\
|needs? re-?(measuring|running|checking)\
|(my|the) (scan|method|count|corpus) (had|has) (a |two |several )?(known )?(defect|flaw|bug|blind spot)\
|i was wrong (about|on)|correcting myself"

hit=$(grep -ioE "$INVAL" <<<"$t" 2>/dev/null | sort -u | head -2 | paste -sd'; ' -)
[ -n "$hit" ] || exit 0

# One way past: the re-run actually happened and its result is in this message.
grep -qiE '\b(re-?ran|re-?measured|re-?computed|recounted|re-?checked|corrected (count|number|table|figure)|here is the corrected|now measured|updated (count|table|number))\b' <<<"$t" 2>/dev/null && exit 0

r="SELF-INVALIDATION: \"$hit\". RE-RUN IT NOW - make the tool call, then give the corrected number. Measured 91 times over 36 sessions, 92% with no re-run: the admission gets treated as the fix, and the stale figure stays standing. Re-wording this message does not clear the hook; only the corrected measurement does. [feedback_no_self_report_omissions]"
jq -nc --arg r "$r" '{decision:"block", reason:$r}'
exit 0
