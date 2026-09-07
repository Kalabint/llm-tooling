#!/usr/bin/env bash
# PreToolUse guard for Bash: service lifecycle changes must be asked for.
#
# Recorded 2026-09-04. Told "docker down kalamaps live and try to build", the
# model brought live down (asked), built (asked), then ALSO tore the test stack
# down and brought live back up (neither asked) -- destroying the artefact the
# user wanted to look at. Corrected once, it did the same thing again one turn
# later, trying to "restore" live unprompted. Verbatim: "didnt tell you to bring
# it down", then "didnt tell you to restore anything!!".
#
# The failure is tidying: treating "put the environment back" as neutral. It is
# not. Starting and stopping services is externally visible state, and the user
# is the only one who knows which state he wants to be looking at.
#
# Mechanism: lifecycle verbs are blocked unless the command carries a marker
# quoting the instruction, e.g.  # asked: "docker down kalamaps live"
# The marker cannot be produced reflexively -- it forces the model to point at
# the words that authorised the change, which is exactly the check that was
# missing. Read-only docker (ps/logs/inspect/images) and `build` are untouched.
#
# Exit 2 blocks and shows stderr to the model; exit 0 passes.

if [ "${1:-}" = "--selftest" ]; then
  fail=0
  chk() {
    got=$(printf '%s' "$2" \
      | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
      | bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; [ $? -eq 2 ] && echo block || echo pass)
    [ "$got" = "$1" ] || { echo "FAIL want=$1 got=$got : $2"; fail=1; }
  }
  chk block 'docker compose -f /x/docker-compose.yml up -d'
  chk block 'docker compose -f /x/docker-compose.yml down'
  chk block 'docker compose -f /x/docker-compose.yml down -v'
  chk block 'docker compose -f /x/docker-compose.yml restart web'
  chk block 'docker stop somecontainer'
  chk block 'docker rm -f somecontainer'
  chk block 'systemctl restart nginx'
  chk pass  'docker compose -f /x/docker-compose.yml up -d   # asked: "bring it up"'
  chk pass  'docker compose -f /x/docker-compose.yml build'
  chk pass  'docker compose -f /x/docker-compose.yml ps'
  chk pass  'docker ps -a'
  chk pass  'docker compose -f /x/docker-compose.yml logs --tail=20 web'
  chk pass  'docker run --rm -v /a:/w alpine sh -c "rm -rf /w/tmp"'
  [ $fail -eq 0 ] && echo "service-state-guard: all cases pass"
  exit $fail
fi

payload=$(cat)
[ -z "$payload" ] && exit 0

CMD="$payload" python3 <<'PY'
import json, os, re, sys
try:
    cmd = json.loads(os.environ["CMD"]).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)
if not cmd:
    sys.exit(0)

# An explicit citation of the instruction releases the block.
if re.search(r'#\s*asked:', cmd):
    sys.exit(0)

LIFECYCLE = [
    (r'\bdocker\s+compose\b[^\n]*?\b(up|down|start|stop|restart|kill)\b', 'docker compose lifecycle'),
    (r'\bdocker\s+(start|stop|restart|kill|rm)\b',                        'docker container lifecycle'),
    (r'\bsystemctl\s+(start|stop|restart|reload)\b',                      'systemctl lifecycle'),
]
for pat, label in LIFECYCLE:
    m = re.search(pat, cmd)
    if not m:
        continue
    # `docker rm` on a throwaway --rm run is not lifecycle management
    if label == 'docker container lifecycle' and re.search(r'docker\s+run\b', cmd):
        continue
    sys.stderr.write(
        "SERVICE STATE CHANGE NOT AUTHORISED: %s (%r).\n\n"
        "Starting, stopping or restarting services is externally visible state, and\n"
        "only the user knows which state he wants to be looking at. Do NOT do this to\n"
        "tidy up, to restore what you changed earlier, or to free a port you decided\n"
        "you needed.\n\n"
        "If he asked, cite it inline and re-run:\n"
        "    <command>   # asked: \"<his words>\"\n\n"
        "If he did not ask, do not run it. Report the current state and let him choose.\n"
        % (label, m.group(0))
    )
    sys.exit(2)
sys.exit(0)
PY
