#!/usr/bin/env bash
# Blocks banned phrasing and forces a silent re-emit.
#   Stop        -> scans the assistant's last message, forces a correction turn.
#   PostToolUse -> scans Write/Edit content BEFORE the file is delivered/read.
#
# Patterns live in banned-patterns.sh; this is their only consumer.
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
h_eff=$(hit "$EFF"); h_pnt=$(hit "$PNT"); h_haz=$(hit "$HAZ")
# LED (framing preamble: "two things", "one consequence") retired 2026-09-01:
# purely stylistic, no correctness value, and it forced three re-emit turns in
# one session. The pattern is still defined in banned-patterns.sh but nothing
# reads it; re-point h_led at hit "$LED" to revive the class.
h_led=""
h_edi=$(hit "$EDI"); h_adv=$(hit "$ADV"); h_tim=$(hit "$TIM"); h_par=$(hit "$PAR"); h_fix=$(hit "$FIXP"); h_unrun=$(hit "$UNRUN"); h_abs=$(hit "$ABS"); h_brc=$(hit "$BRC")
[ -n "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_adv$h_tim$h_par$h_fix$h_unrun$h_abs$h_brc" ] || exit 0

# The words themselves, assembled here so the instruction can quote them verbatim
# and the next turn has nothing to decide. Backticked: code spans are stripped
# before matching, so the tag cannot re-trigger the guard on a later scan.
words=$(printf '%s\n' "$h_cmp" "$h_tic" "$h_syc" "$h_eff" "$h_pnt" "$h_haz" "$h_led" "$h_edi" "$h_tim" "$h_adv" "$h_par" \
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
[ -n "$h_adv" ] && r="$r Cross-source comparison: \"$h_adv\" — state what EACH source is and when it was populated [why: feedback_check_it_dont_assume]."
[ -n "$h_par" ] && r="$r Parameter semantics: \"$h_par\" — cite file:line where the setting is defined and what it multiplies or gates [why: feedback_check_it_dont_assume]."
[ -n "$h_edi" ] && r="$r Editorialising on a measurement: \"$h_edi\" — report the number, not what it proves [why: feedback-verify-what-the-number-counts]."
# PAR self-suppresses when the claim is already evidenced. A file:line citation,
# a fenced block (the definition pasted), or an explicit verification verb means
# the work the hook asks for was already done — firing then is pure noise.
# Class 5 exemption: the surface-assumptions template and enumerated option
# lists carry content. Checked against raw_text so a fenced list still counts.
pnt_exempt=$(printf '%s' "$raw_text" | grep -ciE "$PNT_EXEMPT" 2>/dev/null)
[ "${pnt_exempt:-0}" -gt 0 ] && h_pnt=""
# An absence claim is cleared only by evidence of the SEARCH ITSELF -- the
# command, or its empty result. A file:line citation does NOT clear it: on
# 2026-09-04 a size measurement was cited while no search had been run.
abs_searched=$(printf '%s' "$raw_text" | grep -ciE '\b(grep|rg|ripgrep|ag|find) -|--exclude-dir|\(empty|\(above is the complete set|\bsearched (the )?(whole|entire|full) (repo|tree|codebase)\b|\bUNVERIFIED\b')
[ "${abs_searched:-0}" -gt 0 ] && h_abs=""
par_cited=$(printf '%s' "$raw_text" | grep -ciE '[a-z_./-]+\.(ts|js|rb|py|sql|sh|yml|json):[0-9]+|```|\b(verified|i read|reading it|from the source|per the code)\b')
[ "${par_cited:-0}" -gt 0 ] && h_par=""
[ -n "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_adv$h_tim$h_par$h_fix$h_unrun$h_abs$h_brc" ] || exit 0
if [ -n "$h_brc" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim" ]; then
  r="FIX-HISTORY BREADCRUMB IN THE ARTEFACT: \"$h_brc\". You fixed something and are writing the story of the fix into the file. Cut it. Keep what the code DOES, a gotcha that bites at this line, a param's semantics. Delete what it used to do, why the earlier attempt failed, the numbered defect list, and the dated incident. On 2026-09-04 walk_osm.sql reached 48% comment and walk_osm_fn.sql 35%, carrying WHY-THE-FIRST-VERSION-LOST headers that nothing will read again. The fix history belongs in the reply and the commit, not the source."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
if [ -n "$h_abs" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim" ]; then
  r="ABSENCE CLAIMED WITHOUT A SEARCH: \"$h_abs\". Show the search and its SCOPE in this message -- the command, the directories it covered, and the empty result. On 2026-09-04 \"a_digest_state is read by nothing in the repo, 992 MB, drop it\" went into a memory recommending deletion of a live feature: it drives the /statistics/heatmap brake/accel slider via api/h3-cells/+server.ts:287,289. The earlier grep had covered future_position_stats/ only. A partial search cannot support an absence claim, and a size measurement is not a search. Run it across the whole tree, or say UNVERIFIED."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
if [ -n "$h_unrun" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim$h_fix" ]; then
  r="YOU NAMED A MEASUREMENT INSTEAD OF TAKING IT: \"$h_unrun\". If it is runnable now, RUN IT and report the number in this message. Listing it as open costs the reader a round trip for something that was one query away. Only leave it open if it needs access, tooling or data you do not have -- and then name the specific blocker, not the gap."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
if [ -n "$h_fix" ] && [ -z "$h_cmp$h_tic$h_syc$h_eff$h_pnt$h_haz$h_led$h_edi$h_tim" ]; then
  r="IS A STOP WARRANTED HERE? You declared a fix: \"$h_fix\". Before writing it, answer three things in the message: (1) has the CAUSE been reproduced, or only the symptom observed? (2) which earlier explanations for this same symptom were measured false — name them; (3) what would show this fix is wrong. On 2026-09-03 a gate change was proposed after two prior explanations for the same jump had already been refuted by measurement. A remedy on an unconfirmed cause ships. Answer those, or ask before implementing."
  jq -nc --arg r "$r" '{decision:"block", reason:$r}'; exit 0
fi
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
