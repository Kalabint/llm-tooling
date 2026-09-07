#!/usr/bin/env bash
# Stop + PostToolUse(Write|Edit). Blocks an INVENTORY of what the sensitive data is.
#
# Writing "the transcripts carry file contents, database rows, GPS including a home
# address and medical text" into a privacy document is itself a disclosure. It tells
# a reader what to look for and confirms it exists, in the one artefact that is
# published precisely because the data is not. The rule predates this guard
# (feedback_sanitation_no_breadcrumbs) and had nothing enforcing it.
#
# WHAT SEPARATES A HIT FROM A DEFINITION. A tool naming what it searches for is
# necessary and generic: "classes: home path, email, private IP, GPS coordinate".
# A claim that those things are PRESENT in a specific corpus is the disclosure. So a
# containment verb is required, and it must reach two or more categories. One
# category with a verb is usually a legitimate single statement of fact.
#
#   hit:  "the transcripts contain GPS coordinates, medical text and credentials"
#   pass: "classes: home path, email, private IP, GPS coordinate, credential"
#   pass: "the file contains an API key"        one category, not an inventory
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
EV=$(printf '%s' "$IN" | jq -r '.hook_event_name // empty' 2>/dev/null)

case "$EV" in
  Stop) TEXT=$(printf '%s' "$IN" | jq -r '.last_assistant_message // empty' 2>/dev/null) ;;
  PostToolUse)
    F=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    case "$F" in *.md|*.txt|*.sh|*.yml|*.yaml) ;; *) exit 0 ;; esac
    TEXT=$(printf '%s' "$IN" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null) ;;
  *) exit 0 ;;
esac
[ -n "${TEXT:-}" ] || exit 0

# Code spans and fences are stripped so a quoted example cannot trip this, matching
# how the other guards behave.
TEXT=$(printf '%s' "$TEXT" | sed -E 's/`[^`]*`//g; /^```/,/^```/d')

VERB='(contain|contains|containing|carry|carries|carrying|hold|holds|holding|include|includes|including|full of|riddled with)'
CAT='(home address|street address|GPS coordinate|GPS includ|coordinates includ|medical|health record|patient|diagnos|password|credential|api[ -]?key|secret key|access token|bank|IBAN|social security|passport|phone number|date of birth|personal data|database row|file content|private key)'

# A category followed by ZERO is proof of absence: a verification table reading
# "home address 0, medical 0" is the opposite of an inventory. Only zero counts are
# stripped. A nonzero count is still a claim of presence and must still fire, which
# is why this does not simply drop every counted category.
hit=$(printf '%s' "$TEXT" | grep -ioE "${VERB}[^.]{0,200}" 2>/dev/null | while IFS= read -r span; do
        span=$(printf '%s' "$span" | sed -E "s/${CAT}s?[[:space:]:=·|-]*0([^0-9]|$)/ /gI")
        n=$(printf '%s' "$span" | grep -ioE "$CAT" | sort -u | wc -l)
        [ "$n" -ge 2 ] && { printf '%s' "$span" | cut -c1-110; break; }
      done)
[ -n "$hit" ] || exit 0

R="SENSITIVE-DATA INVENTORY: \"$hit\". You are listing what the private data IS, inside an artefact that exists because it is private. That listing is the disclosure: it tells a reader what to look for and confirms it is there. State the size and the scope, then stop. \"The corpus is private and is not published\" is the whole statement. [why: feedback_sanitation_no_breadcrumbs]"

if [ "$EV" = "Stop" ]; then
  jq -nc --arg r "$R" '{decision:"block", reason:$r}'
else
  jq -nc --arg r "$R" '{decision:"block", reason:$r,
    hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$r}}'
fi
exit 0
