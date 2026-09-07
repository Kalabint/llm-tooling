#!/usr/bin/env bash
# Adds a user-requested ban. Driven by the "<phrase> > banned. <reason>" form.
#
#   ban-add.sh "<phrase>"  "<reason>"          literal shape, escaped
#   ban-add.sh -p '<regex>' "<phrase>" "<reason>"   generalised shape
#
# Writes a row to userban.tsv, which no-superlative-guard.sh reads at Stop. The
# curated classes in banned-patterns.sh stay hand-written: this file is the
# append-only log of bans issued in conversation, so adding one needs no edit to
# a shared regex and cannot break an existing class.
#
# -p is the difference between banning a phrase and banning a shape. Without it
# the exact sentence never recurs and a paraphrase does; the two bans that
# prompted this script both needed the generalised form, and deriving it is a
# judgement the script does not make. It says so at the end rather than pretending.
#
# Refuses to write if the new pattern hits anything in ban-corpus-negatives.txt.

set -uo pipefail
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSV="$HOOKS/userban.tsv"
NEG="$HOOKS/ban-corpus-negatives.txt"
# Repo to mirror bans into. Tries the current tree first so a rename does not
# silently stop the mirroring, then the known checkout names.
REPO="${BAN_REPO:-}"
if [ -z "$REPO" ]; then
  for d in "$HOME/LLM-Tooling" "$HOME/ChatGPT-Primer"; do
    [ -d "$d/.git" ] && { REPO="$d"; break; }
  done
fi

pat=""; generalised=0
if [ "${1:-}" = "-p" ]; then pat="$2"; generalised=1; shift 2; fi
phrase="${1:-}"; reason="${2:-}"
if [ -z "$phrase" ] || [ -z "$reason" ]; then
  echo "usage: ban-add.sh [-p '<regex>'] \"<phrase>\" \"<reason>\"" >&2; exit 2
fi

# Literal fallback: escape ERE metacharacters, let any run of whitespace match
# any other, and anchor on word boundaries so it cannot fire mid-word.
if [ -z "$pat" ]; then
  pat=$(printf '%s' "$phrase" \
        | sed -e 's/[][(){}.*+?^$|\\]/\\&/g' -e 's/[[:space:]][[:space:]]*/\\s+/g')
  pat="\\b${pat}\\b"
fi

# 1. the pattern must actually match the phrase it was issued for
if ! grep -qiE "$pat" <<<"$phrase" 2>/dev/null; then
  echo "REJECTED: pattern does not match its own phrase" >&2
  echo "  pattern: $pat" >&2; echo "  phrase : $phrase" >&2; exit 1
fi

# 2. it must not match anything the corpus says is legitimate
if [ -f "$NEG" ]; then
  hits=$(grep -inE "$pat" "$NEG" 2>/dev/null | grep -v '^[0-9]*:#' | head -5)
  if [ -n "$hits" ]; then
    echo "REJECTED: pattern fires on known-good sentences in $(basename "$NEG"):" >&2
    printf '  %s\n' "$hits" >&2
    echo "Narrow it with -p, or add the sentence to the negatives if it is not good after all." >&2
    exit 1
  fi
fi

# 3. commit to the store
[ -f "$TSV" ] || printf 'date\tpattern\tphrase\treason\n' > "$TSV"
if cut -f2 "$TSV" | grep -qxF "$pat" 2>/dev/null; then
  echo "already banned, nothing written: $pat"; exit 0
fi
today=$(date +%F)
printf '%s\t%s\t%s\t%s\n' "$today" "$pat" "$phrase" "$reason" >> "$TSV"
echo "banned  $pat"
echo "  phrase: $phrase"
echo "  reason: $reason"

# 4. end-to-end: the guard must now block a message containing the phrase
blocked=$(jq -nc --arg m "$phrase" \
  '{hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:$m}' \
  | bash "$HOOKS/no-superlative-guard.sh" 2>/dev/null | jq -r '.decision // empty')
if [ "$blocked" = "block" ]; then echo "  guard: blocks"; else echo "  guard: DID NOT BLOCK -- check the wiring" >&2; fi

# 5. the repo is the backup
if [ -d "$REPO/.git" ]; then
  cp "$TSV" "$REPO/.claude/hooks/userban.tsv" 2>/dev/null
  cp "$HOOKS/ban-add.sh" "$HOOKS/ban-corpus-negatives.txt" "$HOOKS/no-superlative-guard.sh" \
     "$REPO/.claude/hooks/" 2>/dev/null
  git -C "$REPO" add .claude/hooks/ >/dev/null 2>&1
  git -C "$REPO" commit -q -m "Ban: $phrase" -m "$reason" 2>/dev/null \
    && echo "  committed: $(git -C "$REPO" log --oneline -1)"
fi

# Only the literal path gets the warning. Testing the pattern's shape cannot tell
# the two apart: the literal branch wraps its output in \b too, so both look alike.
if [ "$generalised" -eq 0 ]; then
  echo
  echo "This is the literal phrase. A paraphrase still passes."
  echo "If the shape generalises, re-run with -p '<regex>' and the literal row"
  echo "can be dropped from $(basename "$TSV")."
fi
