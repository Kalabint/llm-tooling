#!/usr/bin/env bash
# Two failures in the /insights handoff, both fixed by forcing one re-emit:
#
#   1. It hands over a file:/// path. The user is NOT on this box, so a local
#      path is unreadable ("Couldn't load this preview"). Same class of miss as
#      leaving deliverables in /tmp. Anything meant to be READ must go to the
#      LAN filehost first.
#   1b. A loopback URL - localhost, 127.0.0.1, 0.0.0.0 - handed over in prose. Same
#      failure as a local path: the user is on another machine and cannot open it.
#      Measured 2026-09-01: 6 occurrences over 16,344 assistant messages, 5 sessions.
#      Code fences and spans are exempt, since a curl against 127.0.0.1 from this box
#      is how the service actually gets tested.
#   2. The built-in report pads itself with "Features to Try" / "On the Horizon"
#      pitches for Skills, Hooks and MCP servers. The user asked for insights
#      into their own usage, not an ad read for other Anthropic products.
#
# /insights is compiled into the claude binary, so neither is fixable at source.
#
# Fails OPEN on any error: a guard that blocks the session is worse than a miss.

set -uo pipefail
[ -f "$HOME/.claude/hooks/local.env" ] && . "$HOME/.claude/hooks/local.env"

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

[ "$(jq -r '.hook_event_name // empty' <<<"$payload" 2>/dev/null)" = "Stop" ] || exit 0
# Never re-block a turn we already forced: avoids a loop.
[ "$(jq -r '.stop_hook_active // false' <<<"$payload" 2>/dev/null)" = "true" ] && exit 0

tp=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null)
text=$(jq -r '.last_assistant_message // empty' <<<"$payload" 2>/dev/null | head -c 20000)
if [ -z "$text" ]; then
  [ -f "$tp" ] || exit 0
  text=$(tac "$tp" 2>/dev/null \
    | jq -r 'select(.type=="assistant" and (.isSidechain|not))
             | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
             | select(length>0) | @base64' 2>/dev/null \
    | head -1 | base64 -d 2>/dev/null | head -c 20000)
fi
[ -n "${text:-}" ] || exit 0

# Code spans and fences are stripped: a path inside a runnable command is an
# instruction, not a handover, and this file's own comments must not self-trip.
stripped=$(sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' <<<"$text" 2>/dev/null | sed 's/`[^`]*`//g')
[ -n "${stripped:-}" ] || exit 0

# Already delivered somewhere the user can actually open? Then nothing to fix.
# Only a DELIVERY link disarms this. Matching any https?:// meant an unrelated
# github or docs link in the same message silenced it - verified 2026-09-01.
grep -qiE 'file\.kala\.li|10\.1\.0\.216|10\.1\.1\.[0-9]+' <<<"$stripped" 2>/dev/null && exit 0

# Loopback handed over as something to open.
loopback=$(grep -ioE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]+)?[^ )"'"'"']*' \
  <<<"$stripped" 2>/dev/null | sort -u | head -2 | paste -sd'; ' -)

is_insights=0
grep -qiE 'usage-data/report-[0-9]|insights report is ready' <<<"$stripped" 2>/dev/null && is_insights=1

# Any local path to something meant to be READ, not just referenced.
unreachable=$(grep -ioE '(file://)?(/home/[a-z0-9_-]+|/tmp|/var/tmp)/[^ )"'"'"']*\.(html|md|pdf|png|jpe?g|svg|csv|xlsx|docx|json)' \
  <<<"$stripped" 2>/dev/null | sort -u | head -3 | paste -sd'; ' -)

# A file DELIVERED inline (SendUserFile) is already in the user's hands -- naming its
# local path beside it is a reference, not a handover, and does not need an upload.
# 2026-09-06: the guard fired on a path mentioned in the same turn the PDF was sent
# inline; the operator's ruling was "inline is fine". Only an UNDELIVERED path is
# unreachable.
if [ -n "$unreachable" ] && [ -n "${tp:-}" ] && [ -f "$tp" ]; then
  delivered=$(tail -n 60 "$tp" 2>/dev/null \
    | grep -o '"name":"SendUserFile"' | head -1)
  if [ -n "$delivered" ]; then
    still=""
    for f in $(printf '%s' "$unreachable" | tr ';' '\n' | sed 's/^ *//'); do
      base=$(basename "$f")
      tail -n 60 "$tp" 2>/dev/null | grep -qF "$base" || still="$still; $f"
    done
    unreachable="${still#; }"
  fi
fi

[ "$is_insights" = "1" ] || [ -n "$unreachable" ] || [ -n "$loopback" ] || exit 0

r="UNREACHABLE DELIVERABLE."
[ -n "$loopback" ] && r="$r Loopback URL handed over: \"$loopback\" - the user is NOT on this box, so localhost/127.0.0.1 resolves to THEIR machine, not the service. Give the LAN address of the host it runs on${KC_LAN_IP:+ (this box is $KC_LAN_IP)} [why: feedback_user_is_remote]."
[ -n "$unreachable" ] && r="$r Local path handed over: \"$unreachable\" — the user is not on this box, file:// and /tmp render as \"Couldn't load this preview\" [why: feedback_user_is_remote]."
if [ "$is_insights" = "1" ]; then
  r="$r Upload the report HTML to the LAN filehost and give that link instead:"
  r="$r Upload the report HTML with the upload skill and give that link instead."
  r="$r ALSO STRIP THE PRODUCT PITCH: drop \"Features to Try\" and the aspirational \"On the Horizon\" copy wholesale — no selling Skills, Hooks, MCP servers or any other Anthropic product back to the user."
  r="$r Keep only findings about THEIR OWN measured usage: session/tool counts, friction categories with counts, concrete quoted examples, and what they actually did."
  r="$r [why: feedback_strip_vendor_framing]"
else
  r="$r Upload it with the upload skill and hand over that URL [why: feedback_prefer_fkalali_over_artifact]."
fi
r="$r Re-emit silently. Open with a --- divider, then a code box containing: unreachable: local path\\n\\n"

jq -nc --arg r "$r" '{decision:"block", reason:$r}'
exit 0
