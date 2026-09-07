#!/usr/bin/env bash
# Generate the plugin manifests from the tracked wiring, so a plugin install and a
# manual install can never disagree about which hooks run.
#
# LAYOUT, and why it is what it is. Two conventions differ:
#   hooks   named explicitly in hooks/hooks.json, so they may live anywhere. They
#           stay in .claude/hooks/ and the commands point at
#           ${CLAUDE_PLUGIN_ROOT}/.claude/hooks/.
#   skills  discovered POSITIONALLY at <plugin root>/skills. Listing them in
#           marketplace.json does not make them load: a plugin whose skills sat
#           only in .claude/skills reported "Skills (0)". So skills/ is the real
#           directory and .claude/skills is the symlink, not the other way round:
#           a session follows a symlink but `plugin validate` does not, and reads
#           nothing through it.
#
#   gen-plugin-manifest.sh           write the manifests and the symlink
#   gen-plugin-manifest.sh --check   exit 1 if anything would change
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
WIRING=".claude/settings.hooks.json"
[ -f "$WIRING" ] || { echo "$WIRING missing; run gen-hooks-readme.sh first" >&2; exit 2; }

gen_hooks() {
  python3 - "$WIRING" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
out = {"hooks": {}}
for ev, arr in sorted(src["hooks"].items()):
    out["hooks"][ev] = [
        {**({"matcher": m["matcher"]} if m.get("matcher") else {}),
         "hooks": [{"type": "command",
                    "command": h["command"].replace(
                        "bash ~/.claude/hooks/",
                        "bash ${CLAUDE_PLUGIN_ROOT}/.claude/hooks/")}
                   for h in m["hooks"]]}
        for m in arr]
print(json.dumps(out, indent=2))
PY
}

gen_plugin() {
  cat <<'JSON'
{
  "name": "llm-tooling",
  "description": "Hooks and skills that block common LLM failure modes at the turn boundary",
  "version": "0.1.0",
  "author": {
    "name": "Kalabint",
    "url": "https://github.com/Kalabint"
  }
}
JSON
}

gen_marketplace() {
  cat <<'JSON'
{
  "name": "llm-tooling",
  "owner": {
    "name": "Kalabint",
    "url": "https://github.com/Kalabint"
  },
  "metadata": {
    "description": "Hooks and skills that block common LLM failure modes at the turn boundary",
    "version": "0.1.0"
  },
  "plugins": [
    {
      "name": "llm-tooling",
      "description": "Stop and PreToolUse guards plus the rule skills",
      "source": "./",
      "strict": false
    }
  ]
}
JSON
}

if [ "${1:-}" = "--check" ]; then
  rc=0
  diff -q <(gen_hooks) hooks/hooks.json >/dev/null 2>&1 || { echo "hooks/hooks.json is stale" >&2; rc=1; }
  diff -q <(gen_plugin) .claude-plugin/plugin.json >/dev/null 2>&1 || { echo ".claude-plugin/plugin.json is stale" >&2; rc=1; }
  diff -q <(gen_marketplace) .claude-plugin/marketplace.json >/dev/null 2>&1 || { echo ".claude-plugin/marketplace.json is stale" >&2; rc=1; }
  [ -d skills ] && [ ! -L skills ] || { echo "skills/ must be a real directory; validate does not follow symlinks" >&2; rc=1; }
  [ "$rc" -eq 0 ] && echo "plugin manifests current"
  exit $rc
fi

mkdir -p hooks .claude-plugin
gen_hooks       > hooks/hooks.json
gen_plugin      > .claude-plugin/plugin.json
gen_marketplace > .claude-plugin/marketplace.json
[ -L .claude/skills ] || ln -s ../skills .claude/skills
echo "wrote hooks/hooks.json, .claude-plugin/{plugin,marketplace}.json, .claude/skills -> ../skills"
