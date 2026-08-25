#!/usr/bin/env bash
# Blocks banned phrasing and forces a silent re-emit.
#   Stop        -> scans the assistant's last message, forces a correction turn.
#   PostToolUse -> scans Write/Edit content BEFORE the file is delivered/read.
#
# Patterns live in banned-patterns.sh.
# Reasons are TERSE ON PURPOSE: the block text is injected into context on every
# single hit (~147 tokens each before this was cut, ~885 over one session), and
# the rationale lives in the matching skill (.claude/skills).
#
# Fails OPEN on any error: a guard that blocks the session is worse than a miss.

set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/banned-patterns.sh" 2>/dev/null || exit 0

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null) || exit 0

case "$event" in
  Stop)
    # Never re-block a turn we already forced: avoids a loop.
    [ "$(jq -r '.stop_hook_active // false' <<<"$payload" 2>/dev/null)" = "true" ] && exit 0
    # last_assistant_message is the documented field for the CURRENT turn's text;
    # transcript_path is written asynchronously and can lag it. Fall back only if absent.
    text=$(jq -r '.last_assistant_message // empty' <<<"$payload" 2>/dev/null | head -c 20000)
    if [ -z "$text" ]; then
      tp=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null)
      [ -f "$tp" ] || exit 0
      # base64 per record so a message's own blank lines can't truncate it
      text=$(tac "$tp" 2>/dev/null \
        | jq -r 'select(.type=="assistant" and (.isSidechain|not))
                 | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
                 | select(length>0) | @base64' 2>/dev/null \
        | head -1 | base64 -d 2>/dev/null | head -c 20000)
    fi
    ;;
  PostToolUse)
    # Exempt ~/.claude/** : hooks and memory files quote the banned phrases
    # verbatim by design, so scanning them is a guaranteed self-trip.
    fp=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)
    case "$fp" in
      "$HOME"/.claude/*|~/.claude/*) exit 0 ;;
    esac
    text=$(jq -r '[.tool_input.content?, .tool_input.new_string?] | map(select(.!=null)) | join("\n")' \
      <<<"$payload" 2>/dev/null | head -c 20000)
    ;;
  *) exit 0 ;;
esac

[ -n "${text:-}" ] || exit 0
text=$(strip_code <<<"$text" 2>/dev/null)
[ -n "${text:-}" ] || exit 0

hit() { grep -ioE "$1" <<<"$text" 2>/dev/null | sort -u | head -4 | paste -sd'; ' -; }
h_cmp=$(hit "$CMP"); h_tic=$(hit "$TIC"); h_syc=$(hit "$SYC")
h_eff=$(hit "$EFF"); h_pnt=$(hit "$PNT"); h_haz=$(hit "$HAZ")
[ -n "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz" ] || exit 0

# The words themselves, assembled here so the instruction can quote them verbatim
# and the next turn has nothing to decide. Backticked: code spans are stripped
# before matching, so the tag cannot re-trigger the guard on a later scan.
words=$(printf '%s\n' "$h_cmp" "$h_tic" "$h_syc" "$h_eff" "$h_pnt" "$h_haz" \
        | tr ';' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u \
        | sed 's/^/`/; s/$/`/' | paste -sd',' - | sed 's/,/, /g')

r="BANNED PHRASING."
[ -n "$h_cmp" ] && r="$r Unbaselined comparison: \"$h_cmp\" [why: no-unmeasured-numbers]."
[ -n "$h_tic" ] && r="$r Stock phrase: \"$h_tic\" [why: no-sycophancy]."
[ -n "$h_syc" ] && r="$r Sycophancy: \"$h_syc\" [why: no-sycophancy]."
[ -n "$h_eff" ] && r="$r Effort/duration estimate: \"$h_eff\" - measured elapsed fine, projected never [why: no-unmeasured-numbers]."
[ -n "$h_pnt" ] && r="$r Empty deferral: \"$h_pnt\" - options + marked recommendation are wanted [why: empty-deferral]."
[ -n "$h_haz" ] && r="$r Invented hazard: \"$h_haz\" - cite file:line where it is TRUE now, else cut it [why: no-invented-hazards]."
r="$r Re-emit without it, silently. Open with a --- divider, then a code box containing: banned: $words\n\n"


jq -nc --arg r "$r" '{decision:"block", reason:$r}'
exit 0
