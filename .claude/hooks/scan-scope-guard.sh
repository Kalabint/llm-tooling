#!/usr/bin/env bash
# PreToolUse(Bash): a recursive filesystem scan must be SCOPED, not bounded by a timeout.
#
# WHY. 2026-09-04: `grep -rIn PATTERN .` from a repository root blew the 120 s tool timeout.
# The retry added `timeout 90`, which was a number with no instrument behind it. The actual
# cause was scope: one gitignored child of that tree held 179 GB of regenerable data.
# Restricted to the source directories the same grep took 0.035 s. No timeout value would
# ever have fixed it -- a longer one just fails later.
#
# What it checks, computed rather than hardcoded: git already knows which children of the
# scan root are data. If an ignored directory sits under the root and the command does not
# exclude it, the scan is unscoped. Nothing here carries a site-specific path.
#
# Fail-open on anything unexpected: this must never block unrelated work.
set -u
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null) || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)
[ -d "${cwd:-}" ] || cwd=$PWD

# Recursive scanners only. `du`/`find` walk; `grep -r` and friends walk.
printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])(grep|egrep|fgrep|rg|ag|ack)([[:space:]]+-[^[:space:]]*)*[[:space:]]+-[a-zA-Z]*[rR]|(^|[|;&[:space:]])(find|du)[[:space:]]' || exit 0
# git grep already searches tracked files only -- that is the fix, not the problem.
printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])git[[:space:]]+grep' && exit 0

wrapped_in_timeout=0
printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]])timeout[[:space:]]+[0-9]' && wrapped_in_timeout=1

# Candidate scan roots: bare tokens that exist as directories. A `grep -r` with no path
# argument walks the working directory.
#
# `cd <dir> && grep -r ... src/` must not treat <dir> as a scan root -- it is the working
# directory the scan is scoped FROM, not a thing being scanned. Caught 2026-09-05 by this
# guard firing on its own author for exactly that shape, with the paths correctly named.
roots=""
prev=""
for tok in $cmd; do
  case "$tok" in
    -*|*'*'*|*'?'*) prev=$tok; continue ;;
  esac
  tok=${tok%\"}; tok=${tok#\"}; tok=${tok%\'}; tok=${tok#\'}
  [ -n "$tok" ] || { prev=$tok; continue; }
  case "$prev" in cd|pushd) prev=$tok; continue ;; esac
  prev=$tok
  if [ "$tok" = "." ]; then roots="$roots $cwd"; continue; fi
  case "$tok" in
    /*) [ -d "$tok" ] && roots="$roots $tok" ;;
     *) [ -d "$cwd/$tok" ] && roots="$roots $cwd/$tok" ;;
  esac
done
[ -n "${roots// /}" ] || roots="$cwd"

# Which children are data is git's answer, not this file's. check-ignore is one process
# over the immediate children -- no recursion, so it costs nothing on a 179 GB tree.
#
# Ignored is necessary but NOT sufficient: __pycache__ and .svelte-kit are ignored and
# cost nothing to walk. Probing this against the session's own commands denied two that
# were correct and fast, so each candidate is measured before it is named.
#
# The instrument is BYTES, not entries. An entry count was tried first and is wrong here:
# the 179 GB directory holds 341 entries within three levels and the 6.9 GB one holds 4.
# What a recursive grep pays for is bytes read. `du -sb` reads directory metadata only --
# measured at 1.57 s on the 179 GB tree, 2 ms on the rest -- and the timeout is itself a
# signal: a directory that cannot be sized in 3 s is not one to walk.
BIG_BYTES="${BIG_BYTES:-1073741824}"
unscoped=""
shown=""
for root in $roots; do
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  kids=$(find "$root" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | head -200)
  [ -n "$kids" ] || continue
  ignored=$(printf '%s\n' "$kids" | git -C "$root" check-ignore --stdin 2>/dev/null)
  for d in $ignored; do
    [ "$d" = ".git" ] && continue
    printf '%s' "$cmd" | grep -qE -- "--exclude-dir=[\"']?${d}[\"']?|(^|[[:space:]])${d}(/|[[:space:]]|$)" && continue
    n=$(timeout 3 du -sb "$root/$d" 2>/dev/null | cut -f1)
    if [ -z "$n" ]; then sz="unsizeable in 3s"          # same answer as "big"
    elif [ "$n" -ge "$BIG_BYTES" ] 2>/dev/null; then sz=$(numfmt --to=iec "$n" 2>/dev/null || echo "$n bytes")
    else continue
    fi
    case " $unscoped " in
      *" $d "*) ;;
      *) unscoped="$unscoped $d"; shown="$shown $d ($sz)" ;;
    esac
  done
done
[ -n "${unscoped// /}" ] || exit 0

list=${shown# }
excl=$(printf '%s' "${unscoped# }" | tr ' ' '\n' | sed 's/^/--exclude-dir=/' | paste -sd' ' -)

if [ "$wrapped_in_timeout" = "1" ]; then
  lead="A TIMEOUT IS NOT A SCOPE. This scan is bounded by a timeout value rather than restricted to the files that can contain the answer, and the timeout number has no instrument behind it."
else
  lead="UNSCOPED RECURSIVE SCAN. This walks directories git already classifies as data."
fi

r="$lead git ignores these children of the scan root and they were just measured: $list. On 2026-09-04 the same shape over a tree holding a 179 GB ignored directory blew the 120 s tool timeout; restricted to the source directories it returned in 0.035 s. Re-issue one of: (1) 'git grep -n PATTERN' -- tracked files only, and it is the whole fix; (2) the same command with $excl; (3) name the source directories explicitly as path arguments. If you deliberately need an ignored directory -- gitignored source such as a bench or scratch tree -- pass it as an explicit path argument and this check will pass. Raising the timeout is not one of the options: a longer bound on the wrong scope fails later, not less."
jq -nc --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
