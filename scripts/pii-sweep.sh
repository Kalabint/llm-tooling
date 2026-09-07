#!/usr/bin/env bash
# Refuse to publish identifying data. Run before every push; the pre-push hook does.
#
# WHAT COUNTS. The owner's standard, in their words: "no home dir, no mail, domains,
# etc." Project and product names are explicitly NOT in scope ("if kalamaps leaks,
# whatever"), which is why kalamaps, traccar and h3 appear nowhere below. Scoping to
# what is actually secret is what keeps the output worth reading.
#
# ALLOWLIST. Applied by DELETING the allowed substring and re-testing what is left,
# never by clearing the whole line. Clearing lines hid two real leaks on the first
# run: the LAN IP sat on a line that also said 127.0.0.1, and a domain hit sat on a
# line that also had sk=. A line can carry both an innocent match and a real one.
#
# MODES
#   --staged        what is about to be committed
#   --range A..B    added lines in a commit range, for pre-push
#   --tree          every tracked file, the full audit
#
# Exit 0 clean, 1 on a hit, 2 on misuse.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }

# The values are themselves identifying, so they live in local.env with the rest and
# this file names only the variables. Unset means that class is skipped, which is
# right for a stranger's clone: they have a different name and a different domain.
[ -f "$HOME/.claude/hooks/local.env" ] && . "$HOME/.claude/hooks/local.env"
USER_NAME="${KC_USER_NAME:-}"
MAIL_DOMAIN="${KC_MAIL_DOMAIN:-}"
CLASSES=(
  ${USER_NAME:+"username|\\b${USER_NAME}\\b"}
  ${MAIL_DOMAIN:+"private domain|\\b$(printf '%s' "$MAIL_DOMAIN" | sed 's/\./\\./g')\\b"}
  "home path|/home/[a-z][a-z0-9_-]*"
  "email|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
  "private IP|\\b(10|192\\.168)\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\b"
  "GPS coordinate|\\b4[5-7]\\.[0-9]{5,}\\b"
  "credential|(\\bsk-[A-Za-z0-9]{16}|\\bghp_[A-Za-z0-9]{16}|\\bAKIA[0-9A-Z]{8}|BEGIN [A-Z ]*PRIVATE KEY)"
)
# 127.0.0.1 needs no entry: the IP class only matches 10.x and 192.168.x.
#
# The account handle is deleted where it is INHERENT to publishing: a github.com
# URL and the copyright line. The repo lives at github.com/<handle>/<repo>, so the
# handle cannot be secret while the repo is public, and a licence needs a named
# holder. What the username class is actually for is the unix name in a path, and
# /home/<name> and -home-<name>-<project> still match after this deletion.
scrub() { printf '%s' "$1" | sed -E '
  s/traccar\.example//g
  s/\|[[:space:]:|-]*-{3,}[[:space:]:|-]*//g
  s#(https?://)?(www\.)?github\.com/[A-Za-z0-9_-]+#gh#g
  s/[Cc]opyright \([Cc]\) [0-9]{4} .*$/Copyright/
'; }

mode="${1:-"--tree"}"; range="${2:-}"
case "$mode" in
  --staged) src(){ git diff --cached --unified=0 | grep '^+' | grep -v '^+++'; } ;;
  --range)  [ -n "$range" ] || { echo "usage: $0 --range A..B" >&2; exit 2; }
            src(){ git diff "$range" --unified=0 | grep '^+' | grep -v '^+++'; } ;;
  --tree)   src(){ git ls-files -z | xargs -0 grep -nH '' 2>/dev/null; } ;;
  *) echo "usage: $0 [--staged|--range A..B|--tree]" >&2; exit 2 ;;
esac

payload=$(src)
[ -n "$payload" ] || { echo "pii-sweep: nothing to check"; exit 0; }
hits=0
for c in "${CLASSES[@]}"; do
  name="${c%%|*}"; pat="${c#*|}"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$(scrub "$line")" | grep -qiE "$pat" || continue
    hits=$((hits+1))
    printf '  %-16s %s\n' "$name" "$(printf '%s' "$line" | cut -c1-120)"
  done < <(printf '%s\n' "$payload" | grep -iE "$pat" || true)
done

if [ "$hits" -gt 0 ]; then
  echo
  echo "pii-sweep: $hits line(s) carry identifying data. Fix them, or move the file to"
  echo "a private name (*.private.sh / *.private.md), which is gitignored."
  exit 1
fi
echo "pii-sweep: clean ($mode${range:+ $range})"
exit 0
