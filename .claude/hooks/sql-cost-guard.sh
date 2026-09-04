#!/usr/bin/env bash
# PreToolUse(Bash): a psql query that spatially correlates two large tables must be
# EXPLAINed before it is run.
#
# WHY. 2026-09-03: a correlated `EXISTS (SELECT 1 FROM pts WHERE ST_DWithin(n.geom, ...))`
# over 5,142,177 H3 cells x 1,297,878 OSM ways was launched blind, ran past the 600 s
# tool timeout, and had to be pg_terminate_backend'd. Rewritten as a materialised
# point table with a GiST index plus a plain spatial join, the same answer took under
# a minute: 380,201 ways. The cost was visible in EXPLAIN before a row was read.
#
# Fail-open on anything unexpected: this must never block unrelated work.
set -u
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null) || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Only psql invocations.
printf '%s' "$cmd" | grep -qiE '\bpsql\b' || exit 0
# Already explaining, or a bounded probe: let it through.
printf '%s' "$cmd" | grep -qiE 'EXPLAIN' && exit 0
printf '%s' "$cmd" | grep -qiE '\bLIMIT[[:space:]]+[0-9]{1,4}\b' && exit 0

# Which tables are big is a property of the database, not of this file. Pull the
# candidate names out of the statement, then ask the catalogue. reltuples is a
# planner estimate held in pg_class -- no scan, and the connection details are
# reused from the very command being checked, so there is nothing to configure.
BIG_ROWS="${BIG_ROWS:-1000000}"

cand=$(printf '%s' "$cmd" | grep -oiE '\b(from|join)[[:space:]]+"?[a-z_][a-z0-9_]*"?' \
       | sed -E 's/^[a-zA-Z]+[[:space:]]+//; s/"//g' | sort -u | head -20)
[ -n "$cand" ] || exit 0

ctr=$(printf '%s' "$cmd" | grep -oE 'docker exec [^ ]*(-i )?[a-zA-Z0-9_.-]+' | awk '{print $NF}' | head -1)
usr=$(printf '%s' "$cmd" | grep -oE '\-U[[:space:]]*[a-zA-Z0-9_]+' | sed -E 's/-U[[:space:]]*//' | head -1)
dbn=$(printf '%s' "$cmd" | grep -oE '\-d[[:space:]]*[a-zA-Z0-9_]+' | sed -E 's/-d[[:space:]]*//' | head -1)
[ -n "$ctr" ] && [ -n "$usr" ] && [ -n "$dbn" ] || exit 0

list=$(printf "%s\n" $cand | sed "s/^/'/; s/$/'/" | paste -sd',' -)
big=$(timeout 10 docker exec "$ctr" psql -U "$usr" -d "$dbn" -t -A -c \
      "SELECT relname FROM pg_class WHERE relkind='r' AND relname IN ($list) AND reltuples > $BIG_ROWS;" 2>/dev/null)
n_big=$(printf '%s' "$big" | grep -c . )
[ "${n_big:-0}" -ge 2 ] || exit 0

# The shape that goes quadratic: a spatial predicate evaluated per outer row.
printf '%s' "$cmd" | grep -qiE 'ST_DWithin|ST_Intersects|ST_Contains|ST_Distance|<->' || exit 0
printf '%s' "$cmd" | grep -qiE 'EXISTS[[:space:]]*\(|IN[[:space:]]*\([[:space:]]*SELECT|CROSS[[:space:]]+JOIN|,[[:space:]]*LATERAL' || exit 0

tbls=$(printf '%s' "$big" | paste -sd', ' -)
r="EXPLAIN THIS FIRST. The query spatially correlates two large tables ($tbls) with a per-row predicate (EXISTS / IN (SELECT) / CROSS JOIN / LATERAL) and no LIMIT. On 2026-09-03 that exact shape over 5.1M cells x 1.3M ways ran past the 600 s timeout and needed pg_terminate_backend; materialising one side into an indexed table and using a plain spatial join returned the same answer in under a minute. Run EXPLAIN (no ANALYZE) and read the estimated rows, or restructure first -- then re-issue. If the plan is genuinely fine, add EXPLAIN to this command once to clear the check."
jq -nc --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
