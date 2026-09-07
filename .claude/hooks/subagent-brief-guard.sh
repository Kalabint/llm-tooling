#!/usr/bin/env bash
# PreToolUse guard for Agent/Task: the dispatch rules bind at dispatch time.
#
# Why a hook and not a skill or a memory line. Both already existed and both
# failed, measurably: the rules live in feedback_subagent_dispatch.md AND in
# the /recon skill, yet a scan of all 153 Agent dispatches on this box found
# 82 carrying none of them, answerability in 9, single-input scope in 5, and
# 44 with no explicit model at all. /recon itself fired once in 154 dispatches
# because its description reads as a queue manager, so the copy inside it was
# unreachable. A rule that depends on remembering to load it is not a rule.
#
# Deliberately NOT a full checklist. Only the elements whose absence was both
# frequent and consequential are enforced; the rest stay advisory in the memory
# file. Over-gating a two-line "find where X is defined" dispatch would make
# this the brainstorming HARD-GATE, which is the failure mode being avoided.
#
# Exit 2 blocks and shows stderr to the model; exit 0 passes.

# Self-test: `bash subagent-brief-guard.sh --selftest`. compose-pin-guard spent
# a month failing open and silent; anything registered here gets a test.
# Must sit ABOVE the stdin read: with no stdin the empty-payload exit fires first.
if [ "${1:-}" = "--selftest" ]; then
  fail=0
  chk() { # chk <want> <model> <prompt>
    got=$(MODEL="$2" PROMPT="$3" python3 -c '
import json,os,sys
print(json.dumps({"tool_name":"Agent","tool_input":{
  "prompt":os.environ["PROMPT"],"model":os.environ["MODEL"]}}))' \
      | bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; [ $? -eq 2 ] && echo block || echo pass)
    [ "$got" = "$1" ] || { echo "FAIL want=$1 got=$got : ${3:0:60}"; fail=1; }
  }
  ANALYSIS="Analyze the conversation corpus and report findings on how the user works."
  FULL="$ANALYSIS Parse it yourself and return only distilled findings, never dump raw data.
Write one self-refutation of your conclusion and decide if it survives.
State what is NOT recoverable from this data rather than inventing it."
  chk block opus  "$ANALYSIS"
  chk block ''    "$FULL"
  chk block opus  "$ANALYSIS Return only distilled findings."
  chk pass  opus  "$FULL"
  chk pass  sonnet "$FULL"
  chk pass  opus  "Find the file where tierTolerance is defined and report the path."
  chk pass  sonnet "Read pruner.py and list the function names."
  # Rule 1 is universal: a mechanical dispatch still has to name its model.
  chk block ''    "Read pruner.py and list the function names."
  chk block ''    "Audit the loader service and report every defect you find."

  # Over-block boundary. Every case below was a real false BLOCK in the first
  # version (2026-09-03 audit); they are the reason MECHANICAL is unanchored and
  # the write/raw exemptions exist. The first version's selftest had no case in
  # this class at all, so it reported OK while blocking all of them.
  chk pass  opus  "In the webservice, find every call to analyze() and list the line numbers"
  chk pass  opus  "Add a row to the audit-log table when a share token is revoked"
  chk pass  opus  "After finding the config file, change the port to 27155 and rebuild"
  chk pass  opus  "Run npm audit in kalaMaps_webservice and paste the raw output verbatim"
  chk pass  opus  "Fix the map crash. The user wrote: the audit page freezes on load"

  # Under-block boundary. Inflected forms are genuine analysis and were all
  # passing ungated, because the stems sat inside \b...\b with no suffix.
  chk block opus  "Start analyzing the tile sizes and tell me which layer dominates"
  chk block opus  "Evaluate whether the pruner keeps the right rows and report back"
  chk block opus  "Reviewing the loader, tell me where the cursor logic is wrong"

  # Vacuous satisfier: "return only the file path" must not clear the
  # distilled-not-raw leg for a judgment brief.
  chk block opus  "Analyze the loader and report findings. Return only the file path."
  [ $fail -eq 0 ] && echo "selftest OK (2 rules, 18 cases)"
  exit $fail
fi

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

HOOK_PAYLOAD="$payload" python3 - << 'PY'
import json, os, re, sys
try:
    d = json.loads(os.environ.get("HOOK_PAYLOAD", ""))
except Exception:
    sys.exit(0)
if d.get("tool_name") not in ("Agent", "Task"):
    sys.exit(0)
ti = d.get("tool_input") or {}
prompt = ti.get("prompt") or ""
if not prompt:
    sys.exit(0)
low = prompt.lower()

missing = []

# Rule 1: explicit model. feedback-agents-on-opus - never inherit the session
# model. 44 of 153 dispatches left it unset.
if not (ti.get("model") or "").strip():
    missing.append("model: set it explicitly (opus for judgment/semantic, "
                   "sonnet or haiku only for mechanical counting) - never inherit")

# Rule 2: the analysis-brief triad. Only for dispatches that ask a worker to
# JUDGE something and hand back a conclusion.
#
# Every pattern here was rewritten after an audit of the first version
# (2026-09-03) proved it discriminated on GRAMMAR, not on task type:
#  - stems sat inside \b...\b with no suffix, so `analyze` fired but `analyzing`
#    did not, and `evaluat` could never match anything at all -- genuine analysis
#    briefs in continuous tense sailed through ungated. Hence \w* on every stem.
#  - MECHANICAL was anchored with re.match while ANALYSIS used re.search, so any
#    mechanical brief that opened with scope ("In the webservice, find ...") lost
#    its exemption. Hence unanchored.
#  - bare `findings?` matched the gerund "finding", blocking "After finding the
#    config file, change the port". Dropped: the judgment verbs already cover it.
#  - nothing exempted briefs that MODIFY code or that WANT raw output, so
#    "add a row to the audit-log table" and "paste the raw output verbatim" both
#    blocked, and the printed remedy ("return only distilled findings") directly
#    inverted the second one. That is the costly error: a false block here does
#    not just cost a retry, it corrupts the worker's task. Hence both exemptions,
#    and hence a deliberately narrow trigger -- under-firing is the cheap side.
JUDGE = re.compile(
    r"\b(analy[sz]\w*|audit\w*|review\w*|assess\w*|evaluat\w*|critique\w*|"
    r"red.?team\w*|synthesi[sz]\w*|characteri[sz]\w*|profil\w*|judg\w*|"
    r"critical\w* (?:read|look)|verdict\w*|draw conclusions)\b")
# A brief that tells the worker to CHANGE something is not a judgment brief.
WRITE = re.compile(
    r"\b(add|change|fix|implement|edit|rebuild|update|patch|refactor|create|"
    r"delete|remove|apply|migrate|install|rename|bump|wire|revert)\b")
# A brief that explicitly wants raw material back cannot also be told to distil.
RAW_WANTED = re.compile(r"\b(raw|verbatim|unmodified|full output|paste)\b")
MECHANICAL = re.compile(
    r"\b(find|locate|read|list|grep|search for|show me|print|count|fetch|open)\b")
judgy = JUDGE.search(low) and not (WRITE.search(low) or RAW_WANTED.search(low))
# A judgment verb plus a locate/list verb is ambiguous ("find every call to
# analyze()"): the judgy token is usually an identifier, so stay out.
if judgy and not MECHANICAL.search(low):
    if not re.search(r"distill|do not dump|don.t dump|no raw|"
                     r"return only (?:distilled|your |the )?(?:findings|conclusions)", low):
        missing.append("distilled-not-raw: tell it to parse heavy data itself and "
                       "return only distilled findings, never dump raw material back")
    if not re.search(r"self.refut|refute (your|the|its)|try to break (your|the)|"
                     r"disconfirm|argue against your", low):
        missing.append("self-refutation: make it write ONE refutation of its own "
                       "conclusion and decide whether the conclusion survives")
    if not re.search(r"not recoverable|answerab|cannot be (determined|recovered|"
                     r"answered)|state what.{0,40}(missing|unknown|absent)|"
                     r"rather than invent", low):
        missing.append("answerability: make it state what is NOT recoverable from "
                       "its input instead of inventing it")

if missing:
    print("SUBAGENT BRIEF INCOMPLETE. Missing:\n- " + "\n- ".join(missing)
          + "\nRe-issue the dispatch with these in the prompt. "
            "[rule: memory/feedback_subagent_dispatch.md]", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
