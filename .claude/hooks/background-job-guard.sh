#!/usr/bin/env bash
# PreToolUse(Bash): a foreground poll loop around a long job holds the turn open for the
# job's whole duration. The harness already has the mechanism -- run_in_background: true
# returns immediately and re-invokes on exit.
#
# WHY. 2026-09-05: a REINDEX sweep over ~9 GB of indexes was launched with `cmd &` followed
# by `for i in $(seq 1 300); do <check>; sleep 10; done`. The user watched an empty turn and
# asked "r u rly waiting 3000s for this to finish? cant u set a hook to wake u up when
# done??!". The same shape had been used a dozen times that session for 2-15 minute queries.
#
# Fires only on a sleep INSIDE a loop. A bare `sleep 2` between two commands is fine.
set -u
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null) || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Already backgrounded by the tool? The harness sets no flag we can read here, so the only
# signal is the command text. A loop is what we object to, not the job.
printf '%s' "$cmd" | grep -qE '\bsleep\b' || exit 0
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(for|while|until)\b' || exit 0

# The loop and the sleep must plausibly be the same construct: a `do ... sleep` between them.
printf '%s' "$cmd" | tr '\n' ' ' | grep -qE '\b(for|while|until)\b.{0,200}\bdo\b.{0,600}\bsleep\b' || exit 0

# A monitor-style wait on an EXTERNAL event that the harness cannot see is the legitimate
# case, and it is rare. Let it through when the loop is short and bounded small.
short=$(printf '%s' "$cmd" | grep -oE '\bseq 1 ([0-9]+)' | grep -oE '[0-9]+$' | head -1)
[ -n "$short" ] && [ "$short" -le 5 ] 2>/dev/null && exit 0

r="FOREGROUND POLL LOOP. This waits inside the turn for a job to finish: a \`sleep\` inside a \`for\`/\`while\`. Re-issue the job with run_in_background: true and end the turn -- the harness re-invokes you with a task notification when it exits, and you handle the result then. On 2026-09-05 a REINDEX sweep was launched as \`cmd &\` plus \`for i in \$(seq 1 300); do check; sleep 10; done\`, which held the turn open with nothing visible happening and added a docker exec per tick on top of the job. If several long jobs are independent, start them all in background in one message instead of serialising them behind poll loops. If you are genuinely waiting on an external event the harness cannot see (a file appearing, a log line), arm a Monitor instead of polling."
jq -nc --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
