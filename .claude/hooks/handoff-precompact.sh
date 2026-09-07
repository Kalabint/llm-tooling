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
# GOTCHA. PreCompact has no hookSpecificOutput variant, so it looks write-only. It is
# not: stdout is the channel, and exiting 0 is what sends it. Blocking here (exit 2)
# reaches the human's stderr and never the model, and the block is one-shot per
# session, so a held compaction returns and passes anyway.
#
# This file is the third line of defence and the weakest, because by the time it
# runs the window is already full. handoff-context-gate.sh asks for the doc at a token
# threshold with room to spare, and handoff-expansion.sh converts a manual /compact
# into a handoff turn. Both of those can get a doc written. This one can only shape
# what the summariser keeps on the way past.
#
# Which is why it ships the handoff skill's own "What to write" section rather than a
# paraphrase of it. The audience is the summariser, and a summariser cannot invoke a
# skill to go and read the rules; the Stop gate can leave that to the agent, this
# cannot. Reading the section out of SKILL.md keeps one source of truth, so editing the
# skill changes what compaction preserves.
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
# Assemble the optional block BEFORE the heredoc: a ${VAR:+...} that spans newlines
# is a parse error inside one, and the failure mode is the whole instruction emitting
# raw, unexpanded, which is worse than emitting nothing.
SKILL="$HOME/.claude/skills/handoff/SKILL.md"
RULES=""
if [ -f "$SKILL" ]; then
  R=$(sed -n '/^## What to write/,/^## Style/p' "$SKILL" | sed '$d')
  [ -n "$R" ] && RULES="
--- the document's own spec, from $SKILL. Preserve what it calls for ---

$R"
fi

cat <<EOF
HANDOFF DOC IS ${MIN} MIN STALE: ${DOC}

This session maintains that handoff document. It is written from your summary, so
whatever you drop cannot be recovered for it. Two requirements:

1. Carry these forward as values rather than as descriptions of values: file paths
   written or edited, commit hashes, every numeric measurement with what it measures
   and the command that produced it, every instruction, rule or correction the user
   issued in their own wording, and everything named as unfinished, deferred or
   blocked.

2. Make this the first line of the continuing session's next steps, verbatim:
   FIRST ACTION: the handoff doc ${DOC} is ${MIN} min stale. Run the handoff
   skill's WRITE procedure and update it from this summary before other work.
${RULES}
EOF
exit 0
