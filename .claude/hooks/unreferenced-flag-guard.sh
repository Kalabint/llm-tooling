#!/usr/bin/env bash
# Blocks "there is something you should look at" clauses that name nothing.
#
# feedback_no_invented_hazards already states the rule - cite where it is true
# NOW or cut it. Writing the rule down is not the mechanism: measured
# 2026-09-01, 220 such clauses exist and 144 (65%) cite no referent at all,
# with 46% sitting in the last quarter of the message where padding lives. The
# rule was in force the whole time. This enforces it instead.
#
# Deliberately NOT a follow-through prompt: for an invented item the fix is to
# delete the sentence, not to go investigate it. A "close your open items" hook
# would have sent me chasing my own padding.
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

# Fences stripped, but NOT inline code spans: a backticked identifier is exactly
# the referent this hook is checking for, so removing them would delete the
# evidence before the test runs.
t=$(sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' <<<"$text" 2>/dev/null)
[ -n "${t:-}" ] || exit 0

FLAG="worth (checking|verifying|a check|doing|a look)\
|should (also )?(check|verify|confirm|test)\
|one thing to (check|watch|flag)\
|may be worth|might be worth\
|keep an eye on|bears watching"

# A referent = the same bar the hazard rule sets: a file:line, a backticked
# identifier, a measured quantity, a path, or a known table name.
REF='[A-Za-z0-9_./-]+\.(ts|js|py|sh|sql|svelte|md|json|yml|jsonl|svelte):[0-9]+|`[^`]{3,}`|[0-9][0-9,.]*[[:space:]]*(%|[a-z]{3,})|/home/|km_[a-z_]+|tc_[a-z_]+'

bad=""
while IFS= read -r line; do
  grep -qiE "$FLAG" <<<"$line" 2>/dev/null || continue
  grep -qE "$REF" <<<"$line" 2>/dev/null && continue
  frag=$(grep -ioE ".{0,30}($FLAG).{0,30}" <<<"$line" 2>/dev/null | head -1)
  [ -n "$frag" ] && { bad="$frag"; break; }
done < <(printf '%s\n' "$t" | sed 's/\([.!?]\)[[:space:]]\+/\1\n/g')

[ -n "$bad" ] || exit 0

r="UNREFERENCED FLAG: \"$bad\". You raised something to look at and named nothing to look at. Measured 2026-09-01: 144 of 220 such clauses cite no referent, 46% of them trailing at the end of a message. Either name the file:line, identifier or number where it is true NOW, or DELETE the sentence - do not go investigate it, an invented item does not become real by being chased. [feedback_no_invented_hazards]"
jq -nc --arg r "$r" '{decision:"block", reason:$r}'
exit 0
