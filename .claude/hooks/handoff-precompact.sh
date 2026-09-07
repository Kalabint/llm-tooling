#!/bin/bash
# PreCompact. Compaction is the moment full context is about to be lost, so the
# job here is to steer what survives it, not to prevent it.
#
# THE CHANNEL. A PreCompact hook that exits 0 has its stdout returned as
# newCustomInstructions, and both call sites hand that to the summariser as its
# customInstructions. Verified by reading the 2.1.260 binary:
#
#   executePreCompactHooks -> { newCustomInstructions: <stdout of every hook that
#                               succeeded and did not block, joined>, ... }
#   auto:   FX(session,{trigger:"auto",...})  -> summarize({customInstructions: Oe.newCustomInstructions})
#   manual: FX(session,{trigger:"manual",...}) -> d2t(ve.newCustomInstructions, "User context: "+userArg)
#
# so hook text and any /compact argument merge rather than one dropping the other.
#
# WHY THIS FILE CHANGED. It used to block. That was reasoned from a real
# observation, that PreCompact has no hookSpecificOutput variant (the union in
# 2.1.260 covers 22 events and PreCompact is not one), and a wrong inference from
# it, that blocking was therefore the only lever. Stdout was always the lever.
# The cost of the mistake: a block is one-shot per session, so the held
# compaction just came back and went through with the doc still stale, and in
# between nothing drove the write except the human noticing a stderr line and
# relaying it. Held twice, wrote never.
#
# This file is now the third line of defence and the weakest, because by the time it
# runs the window is already full. handoff-context-gate.sh asks for the doc at a token
# threshold with room to spare, and handoff-expansion.sh converts a manual /compact
# into a handoff turn. Both of those can get a doc written. This one can only shape
# what the summariser keeps on the way past.
set -uo pipefail
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0
j() { printf '%s' "$IN" | jq -r "$1" 2>/dev/null; }
SID=$(j '.session_id'); case "$SID" in ""|null) exit 0;; esac
[ -f "$HOME/.claude/handoff-active/$SID" ] || exit 0

# Manual with a stash means handoff-expansion.sh already held this compaction and
# the doc was written in between. Adding instructions on top would be noise.
[ "$(j '.trigger')" = "manual" ] && [ -f "$HOME/.claude/handoff-pending/$SID" ] && exit 0

CWD=$(j '.cwd'); case "$CWD" in ""|null) CWD="$(pwd)";; esac
. "$HOME/.claude/hooks/handoff-doc.sh" 2>/dev/null || exit 0
DOC=$(handoff_doc "$SID" "$CWD") || exit 0

# Fresh enough = written within the last 30 minutes of wall clock. A fresh doc
# needs no steering, so say nothing and let the summariser use its own prompt.
AGE=$(( $(date +%s) - $(stat -c %Y "$DOC" 2>/dev/null || echo 0) ))
[ "$AGE" -lt 1800 ] && exit 0
MIN=$(( AGE / 60 ))

# Reaching here means the Stop gate (handoff-context-gate.sh) did not get the doc
# written before the window filled, so this is the last chance to shape what survives.
cat <<EOF
HANDOFF DOC IS ${MIN} MIN STALE: ${DOC}

This session maintains that handoff document, and the material it needs is in the
conversation being compacted right now. Two requirements on the summary:

1. Carry these forward at full fidelity, as values rather than as descriptions of
   values: file paths written or edited, commit hashes, every numeric measurement
   with what it measures and the command that produced it, every instruction,
   rule or correction the user issued in their own wording, and everything named
   as unfinished, deferred or blocked. The handoff gets written from this summary,
   so a figure dropped here is a figure that is gone.

2. Make this the first line of the continuing session's next steps, verbatim:
   FIRST ACTION: the handoff doc ${DOC} is ${MIN} min stale. Run the handoff
   skill's WRITE procedure and update it from this summary before other work.
EOF
exit 0
