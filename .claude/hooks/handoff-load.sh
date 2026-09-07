#!/bin/bash
# SessionStart: inject this session's handoff doc as additionalContext.
# Resolution goes through handoff_doc(), because cwd-relative globs do not reach it:
# the doc for this session sits under ~/docker while cwd is ~/docs, and the old
# glob list returned nothing from there.
# Always exits 0.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
SID=$(j '.session_id'); case "$SID" in ""|null) exit 0;; esac
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0
CWD=$(j '.cwd'); case "$CWD" in ""|null) CWD="$(pwd)";; esac
SRC=$(j '.source'); case "$SRC" in ""|null) SRC="startup";; esac

. "$(dirname "${BASH_SOURCE[0]}")/handoff-doc.sh" 2>/dev/null || exit 0
DOC=$(handoff_doc "$SID" "$CWD") || exit 0
CONTENT=$(cat "$DOC" 2>/dev/null) || exit 0
[ -n "$CONTENT" ] || exit 0
printf '%s\n' "$DOC" > "$HOME/.claude/handoff-active/$SID" 2>/dev/null

AGE=$(( ( $(date +%s) - $(stat -c %Y "$DOC" 2>/dev/null || echo 0) ) / 60 ))
BYTES=$(stat -c %s "$DOC" 2>/dev/null || echo 0)

# Trim only when the doc and the compact summary were made from the SAME context —
# i.e. the doc was written minutes ago, which is what the PreCompact gate forces. Then
# its narrative sections restate what the summary already carries, while its pointer
# sections (62 file paths, the COMMITTED/UNCOMMITTED markers) do not: no compactor is
# trying to preserve those. A doc that predates this context is a different matter — it
# covers work the summary never saw, so it goes in whole. Same 30 min as the gate, so
# the gated path gets the cheap load and an ungated compaction gets the full one.
KEEP_RE='^## (Files to read|Open[ /]|Current live state|Durable gotchas)'
if [ "$SRC" = "compact" ] && [ "$AGE" -lt 30 ]; then
  BODY=$(awk -v keep="$KEEP_RE" '
    /^## / { on = ($0 ~ keep) }
    !seen && /^## / { seen = 1 }          # everything before the first ## is the header
    !seen || on { print }
  ' "$DOC" 2>/dev/null)
  DROPPED=$(awk -v keep="$KEEP_RE" '/^## / && $0 !~ keep { sub(/^## /,""); print "  - " $0 }' "$DOC" 2>/dev/null)
  [ -n "$BODY" ] || exit 0
  jq -nc --arg ctx "SESSION HANDOFF (partial) from $DOC — ${BYTES} B total, written ${AGE} min ago.
Post-compaction start: the narrative sections are omitted because the compact summary above
covers the same ground. What follows is the part a summary does not reliably carry — which
files to open, what is unfinished, and what is running. Omitted headings, in the file if needed:
${DROPPED}
For any factual claim, prefer firsthand source (code/git) over either — both can be stale.

$BODY" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
  exit 0
fi

PREFIX="SESSION HANDOFF loaded from $DOC (source=$SRC, written ${AGE} min ago). Read it.
For any factual claim, prefer firsthand source (code/git) over this doc — it can be stale."
jq -nc --arg ctx "$PREFIX"$'\n\n'"$CONTENT" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
