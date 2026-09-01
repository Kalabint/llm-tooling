#!/usr/bin/env bash
# Blocks banned phrasing and forces a silent re-emit.
#   Stop        -> scans the assistant's last message, forces a correction turn.
#   PostToolUse -> scans Write/Edit content BEFORE the file is delivered/read.
#
# Patterns live in banned-patterns.sh, shared with redact-banned-display.sh.
# Reasons are TERSE ON PURPOSE: the block text is injected into context on every
# single hit (~147 tokens each before this was cut, ~885 over one session), and
# the rationale is already in the memory files loaded at session start.
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
raw_text="$text"
text=$(strip_code <<<"$text" 2>/dev/null)
[ -n "${text:-}" ] || exit 0

hit() { grep -ioE "$1" <<<"$text" 2>/dev/null | sort -u | head -4 | paste -sd'; ' -; }
h_cmp=$(hit "$CMP"); h_tic=$(hit "$TIC"); h_syc=$(hit "$SYC")
h_eff=$(hit "$EFF"); h_pnt=$(hit "$PNT"); h_haz=$(hit "$HAZ"); h_led=$(hit "$LED")
h_edi=$(hit "$EDI"); h_adv=$(hit "$ADV"); h_tim=$(hit "$TIM"); h_par=$(hit "$PAR")
[ -n "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_adv$h_tim$h_par" ] || exit 0

# The words themselves, assembled here so the instruction can quote them verbatim
# and the next turn has nothing to decide. Backticked: code spans are stripped
# before matching, so the tag cannot re-trigger the guard on a later scan.
words=$(printf '%s\n' "$h_cmp" "$h_tic" "$h_syc" "$h_eff" "$h_pnt" "$h_haz" "$h_led" "$h_edi" "$h_tim" \
        | tr ';' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u \
        | sed 's/^/`/; s/$/`/' | paste -sd',' - | sed 's/,/, /g')

r="BANNED PHRASING."
[ -n "$h_cmp" ] && r="$r Unbaselined comparison: \"$h_cmp\" [why: feedback-no-time-estimates]."
[ -n "$h_tic" ] && r="$r Stock phrase: \"$h_tic\" [why: feedback_no_sycophancy]."
[ -n "$h_syc" ] && r="$r Sycophancy: \"$h_syc\" [why: feedback_no_sycophancy]."
[ -n "$h_eff" ] && r="$r Effort/duration estimate: \"$h_eff\" — measured elapsed fine, projected never [why: feedback-no-time-estimates]."
[ -n "$h_pnt" ] && r="$r Empty deferral: \"$h_pnt\" — options + marked recommendation are wanted [why: feedback_no_redundant_confirmation]."
[ -n "$h_haz" ] && r="$r Invented hazard: \"$h_haz\" — cite file:line where it is TRUE now, else cut it [why: feedback_no_safety_theater]."
[ -n "$h_tim" ] && r="$r Temporal self-framing: \"$h_tim\" — you have turns, not days; say \"earlier\", \"in this conversation\", or the measured delta [why: feedback-turns-not-days]."
[ -n "$h_edi" ] && r="$r Editorialising on a measurement: \"$h_edi\" — report the number, not what it proves [why: feedback-verify-what-the-number-counts]."
[ -n "$h_led" ] && r="$r Framing preamble: \"$h_led\" — lead with the fact, not with what kind of statement follows [why: feedback_no_sycophancy]."
# PAR self-suppresses when the claim is already evidenced. A file:line citation,
# a fenced block (the definition pasted), or an explicit verification verb means
# the work the hook asks for was already done — firing then is pure noise.
par_cited=$(printf '%s' "$raw_text" | grep -ciE '[a-z_./-]+\.(ts|js|rb|py|sql|sh|yml|json):[0-9]+|```|\b(verified|i read|reading it|from the source|per the code)\b')
[ "${par_cited:-0}" -gt 0 ] && h_par=""
[ -n "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_adv$h_tim$h_par" ] || exit 0
if [ -n "$h_par" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim" ]; then
  r="PARAMETER SEMANTICS UNVERIFIED. You asserted what a named setting does: \"$h_par\". Open where it is defined and state what it multiplies, gates or defaults to, with file:line. On 2026-09-01 \"density_factor=0.1 already applied\" was read as a reduction; tierTolerance() multiplies the snap grid by the factor, so it was a 10x FINER render — backwards, and it inverted the comparison built on it. Re-emit with the citation, or drop the claim."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
if [ -n "$h_adv" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim" ]; then
  r="CONTEXT PROBABLY MISSING. Cross-source comparison: \"$h_adv\". Before asserting it, state in one sentence what EACH source is and when it was populated — a dev restore, a live feed, a different clock, a filtered subset. Two such claims were false on 2026-08-31. Re-emit with that sentence, or drop the claim."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
r="$r Re-emit without it, silently. Open with a --- divider, then a code box containing: banned: $words\n\n"


jq -nc --arg r "$r" '{decision:"block", reason:$r}'
exit 0
