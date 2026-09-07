#!/bin/bash
# Shared resolver, sourced by the handoff hooks. Answers one question: which file
# is THIS session's handoff doc? Resolution must not depend on cwd — the doc for
# session ae298404 lives at $HOME/docker/kalamaps_live_session_handoff_ae298404.md
# while cwd is $HOME/docs, which no cwd-relative glob reaches.
# Order: recorded path (authoritative) > filename carrying the short session id > cwd globs.
handoff_doc() {   # $1 = session id, $2 = cwd. Echoes a path, or returns 1.
  local sid="$1" cwd="$2" gate="$HOME/.claude/handoff-active/$1" p short root
  if [ -s "$gate" ]; then
    p=$(head -1 "$gate")
    [ -n "$p" ] && [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  fi
  short="${sid%%-*}"
  if [ -n "$short" ]; then
    for root in "$cwd" "$(dirname "$cwd")" "$HOME/docker" "$HOME"; do
      [ -d "$root" ] || continue
      p=$(find "$root" -maxdepth 2 -type f -name "*handoff*${short}*.md" 2>/dev/null | head -1)
      [ -n "$p" ] && { printf '%s' "$p"; return 0; }
    done
  fi
  for p in "$cwd"/*_session_handoff*.md "$cwd"/HANDOFF.md "$cwd"/docs/handoff*.md \
           "$(dirname "$cwd")"/*_session_handoff*.md; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}
