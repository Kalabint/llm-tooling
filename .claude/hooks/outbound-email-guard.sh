#!/usr/bin/env bash
# PreToolUse guard for Bash: no email address on the protected domain may appear in
# a command. The login address on that domain is confidential and must never leave
# the box, and the rest of the domain is off-limits as a contact identity too, so
# nothing gets auto-pulled from session context into a header or contact field.
#
# It is the ADDRESS SHAPE that is denied, never the hostname: <local>@[sub.]domain
# is blocked while https://<host>/... URLs on the same domain pass. user@host forms
# such as ssh and scp targets are caught, which is intended.
#
# Everything identifying comes from local.env. With KC_MAIL_DOMAIN unset the guard
# passes everything, which is the right default for anyone who is not the owner:
# they have no such domain to protect, and a guard that blocked every address
# containing an @ would be unusable.
[ -f "$HOME/.claude/hooks/local.env" ] && . "$HOME/.claude/hooks/local.env" 2>/dev/null
DOMAIN="${KC_MAIL_DOMAIN:-}"
[ -n "$DOMAIN" ] || exit 0

payload=$(cat)
esc=$(printf '%s' "$DOMAIN" | sed 's/\./\\./g')
printf '%s' "$payload" | grep -qEi "[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)*${esc}" || exit 0

{
  printf 'BLOCKED: no %s email address may appear in a command. The domain is\n' "$DOMAIN"
  printf 'internal-only as a contact identity, and the session-context login address in\n'
  printf 'particular is confidential and must never leave the box.\n\n'
  printf 'For any outbound contact string (User-Agent, From:, API contact field, abuse\n'
  printf 'address) mint a disposable one instead'
  if [ -n "${KC_MINT_PATTERN:-}" ]; then
    printf ':\n  %s\n' "$KC_MINT_PATTERN"
    [ -n "${KC_MINT_EXAMPLE:-}" ] && printf '  e.g. %s\n' "$KC_MINT_EXAMPLE"
  else
    printf '.\n'
  fi
  printf '\nHostnames are fine'
  [ -n "${KC_ALLOWED_HOSTS:-}" ] && printf ' (%s)' "$KC_ALLOWED_HOSTS"
  printf '. It is the <something>@%s shape that is\n' "$DOMAIN"
  printf 'blocked, including user@host forms such as ssh and scp targets.\n\n'
  printf 'If you genuinely need such a literal locally (grep, git config, an ssh target),\n'
  printf 'ask the user to run that command themselves with a leading `!`.\n'
} >&2
exit 2
