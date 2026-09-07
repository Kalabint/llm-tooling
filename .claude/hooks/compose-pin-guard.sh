#!/usr/bin/env bash
# PreToolUse guard for Bash: three recorded gotchas, enforced mechanically.
# 1. docker compose <project subcommand> without -f  -> wrong-project near-miss
#    (multiple compose projects on this box share service names, e.g.
#    the same service name in two projects -> writes land in the wrong DB).
# 2. Traccar /api/positions with a limit param -> kills the JVM (OOM). The
#    loader's reports/summary probe is the sanctioned earliest-history path.
# 3. pgrep/pkill -f -> matches the calling shell's own argv. Bit twice: once
#    loudly (pkill killed its own shell, exit 144) and once silently (a wait
#    loop never cleared, queued work never ran, and the bogus match was then
#    reported as a measurement). The quiet failure is the reason this is a
#    block and not a memory note: -f self-match returns exit 0 with a MATCH,
#    so there is no error to notice. Bracketing the pattern is not a fix here
#    -- this harness passes the whole command, heredoc bodies included, as one
#    argv string, so the wrapper matches any literal you search for.
# Exit 2 blocks the call and shows stderr to the model; exit 0 lets it pass.
#
# stdin is read by BASH first, then handed to python in the environment. It must
# not be read by python: `python3 - << 'PY'` makes the heredoc python's stdin, so
# json.load(sys.stdin) always hit EOF, always raised, and the fail-open except
# always exited 0. This guard was registered on 2026-07-10 and blocked nothing
# until 2026-08-13. Fail-open is right, but fail-open plus a structural bug is
# invisible -- hence the self-test at the bottom of this file.

# Self-test: `bash compose-pin-guard.sh --selftest`. Exists because this guard
# spent a month failing open and silent; a rule that cannot be observed firing
# is not a rule. Add a case whenever a rule is added above. Must sit ABOVE the
# stdin read -- with no stdin the empty-payload exit fires first and the branch
# is never reached. Fixtures are split so editing this file cannot trip the
# guard on its own test data.
if [ "${1:-}" = "--selftest" ]; then
  fail=0
  chk() {
    got=$(printf '%s' "$2" \
      | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
      | bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; [ $? -eq 2 ] && echo block || echo pass)
    [ "$got" = "$1" ] || { echo "FAIL want=$1 got=$got : $2"; fail=1; }
  }
  L='li''mit=100'; POS='api/pos''itions'
  chk block 'docker compose exec somedb psql -U someuser'
  chk block "curl 'http://trc/$POS?deviceId=1&$L'"
  chk block 'pkill -f tile_walk.py'
  chk block 'pgrep -f "tile_walk.py altona"'
  chk block 'pgrep -af tile_walk'
  chk block 'pkill -9 -f live_fill'
  chk block 'pgrep --full chain.sh'
  chk pass  'docker compose -f $HOME/docker/proj/docker-compose.yml ps'
  chk pass  'for p in $(pgrep -f tile_walk); do readlink -f /proc/$p/exe; done'
  chk pass  'kill $(cat $HOME/netmon/netmon.pid)'
  chk pass  'pgrep -x python3'
  chk pass  'ps aux | grep tile_walk'
  chk pass  'grep -f patterns.txt file.txt'
  [ $fail -eq 0 ] && echo "selftest OK (3 rules, 13 cases)"
  exit $fail
fi

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

# Site values live outside this file so the logic can be published.
LOCAL_ENV="$(dirname "${BASH_SOURCE[0]}")/local/env"
[ -r "$LOCAL_ENV" ] && . "$LOCAL_ENV" 2>/dev/null

HOOK_PAYLOAD="$payload" COMPOSE_PIN_FILE="${COMPOSE_PIN_FILE:-}" python3 - << 'PY'
import json, os, re, sys
try:
    data = json.loads(os.environ.get("HOOK_PAYLOAD", ""))
except Exception:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command", "")
if not cmd:
    sys.exit(0)

if re.search(r"\bdocker\s+compose\b", cmd) and " -f " not in cmd and re.search(
        r"\bdocker\s+compose\s+(exec|up|down|restart|stop|start|run|rm|build|logs|ps|pull)\b", cmd):
    print("BLOCKED: pin the compose project. Same-named services exist in multiple "
          "compose projects on this box (wrong-DB hazard). Use: docker compose "
          "-f " + (os.environ.get("COMPOSE_PIN_FILE") or "<your compose file>") + " ... "
          "(or the -f of the project you actually mean).", file=sys.stderr)
    sys.exit(2)

if re.search(r"api/positions[^ ]*[?&]limit=", cmd) or (
        "api/positions" in cmd and re.search(r"\blimit=\d", cmd)):
    print("BLOCKED: Traccar /api/positions with limit OOM-kills the JVM. Use the "
          "reports/summary probe (see loader.py probe_earliest) or bounded "
          "deviceId+from+to queries.", file=sys.stderr)
    sys.exit(2)

# pgrep/pkill with full-cmdline matching. Catches every flag spelling that
# turns it on: -f, -af, -fa, -9 -f, --full. Only the options belonging to that
# invocation are inspected, so a later unrelated -f in the line is not a match.
for opts in re.findall(r"\bp(?:grep|kill)\b((?:\s+-{1,2}[\w-]+)*)", cmd):
    if any(o == "--full" or (o.startswith("-") and not o.startswith("--") and "f" in o[1:])
           for o in opts.split()):
        # Escape hatches, both of which were the fixes that actually held:
        # resolve PIDs and confirm via /proc/<pid>/exe, or track a pidfile.
        if "/proc/" in cmd or re.search(r"\.pid\b", cmd):
            break
        print("BLOCKED: pgrep/pkill -f matches this shell's OWN argv here -- the "
              "harness passes the whole command (heredoc bodies included) as one "
              "argv string, so it finds any literal you search for. Bracketing the "
              "pattern does NOT fix it; that was already tried and it fired again. "
              "It fails silently: -f self-match exits 0 WITH a match, so there is no "
              "error to catch, and the bogus PIDs get reported as fact. Resolve PIDs "
              "then filter on `readlink -f /proc/$p/exe`, or use a pidfile.",
              file=sys.stderr)
        sys.exit(2)
sys.exit(0)
PY
