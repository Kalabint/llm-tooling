# Hooks

Claude Code hooks that make some of the skills in this repo enforce or fire
automatically instead of relying on the model to remember them. All hooks fail
open (any error exits 0) and require `jq` and `bash`.

Copy the scripts to `~/.claude/hooks/` and merge the JSON blocks below into
`~/.claude/settings.json`.

## 1. no-superlative-guard

Enforces `no-sycophancy`, `no-invented-hazards`, `no-unmeasured-numbers`, and the
empty-deferral rule.

- **Stop**: scans the finished message; on a banned phrase it blocks the turn and
  forces a silent re-emit without it.
- **PostToolUse (Write|Edit)**: scans file content before it is written; exempts
  `~/.claude/**` since the pattern files quote the banned phrases by design.

Patterns live in `banned-patterns.sh` (six classes, documented inline) - tune the
regexes to your own habits.

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/no-superlative-guard.sh" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/no-superlative-guard.sh" } ] }
    ]
  }
}
```

## 2. handoff

Pairs with the `handoff` skill (`.claude/skills/handoff/`), which reads or writes
a session-handoff doc so a fresh session can continue the work. The three hooks
make it automatic, and only engage for sessions where the skill was actually used
(a per-session marker under `~/.claude/handoff-active/`):

- **handoff-mark.sh** - PreToolUse(Skill): when the handoff skill is invoked, marks
  the session active, so the other two hooks stay quiet in unrelated sessions.
- **handoff-load.sh** - SessionStart: injects the curated handoff doc (or the
  pre-compact safety net) as context so a resumed session starts current.
- **handoff-precompact.sh** - PreCompact: before compaction, captures firsthand
  recent state (git status, last commits, last user messages verbatim) as a
  safety net. Deliberately not a model summary, so nothing lossy is institutionalized.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/handoff-load.sh" } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/handoff-precompact.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Skill", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/handoff-mark.sh" } ] }
    ]
  }
}
```

If you already have entries for these events, merge the arrays rather than
replacing them.

## 3. memory-audit-due

Pairs with the `memory-audit` skill (`.claude/skills/memory-audit/`), which
periodically reviews the harness's persistent memories and lists the ones that
have gone stale, contradictory, redundant, bloated, or actively harmful
(backfiring), for you to disposition. It does not auto-correct.

**Requires the harness's file-based memory** (memories under
`~/.claude/projects/<cwd>/memory/`). The hook stays silent in any project
without a memory dir, so it is inert on setups that do not use it.

- **memory-audit-due.sh** - SessionStart: when the last audit is 14+ days old
  (tracked by `~/.claude/skills/memory-audit/.last_audit`), injects a reminder to
  run the skill. Silent otherwise.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/memory-audit-due.sh" } ] }
    ]
  }
}
```

`handoff-load.sh` is also a SessionStart hook - if you use both, put them in the
same `SessionStart` array.

## 4. prompt-shape-guard

The hooks above police the model's output. This one reads **your prompt** and, when
its shape reliably precedes a known failure, injects one line of context. It never
blocks, and caps at two lines per prompt.

- **UserPromptSubmit**: emits `hookSpecificOutput.additionalContext`, which arrives
  as a record typed `hook_additional_context` with the hook named - so it is not
  mistakable for something you wrote.

Eight triggers, each pointing at the skill that states the rule:

| trigger | fires on | skill |
|---|---|---|
| COMPLETENESS ASKED | "find all", "everything", "exhaustive" | `no-self-report-omissions` |
| EXTERNAL SOURCE NAMED | a URL, "the docs", "upstream", "<name> folder" | `code-is-authority` |
| MEASURE, DO NOT RECALL | "how many", "is X still", "what's the status" | `check-dont-assume` |
| PASTED BLOCK | >900 chars over >=6 lines | `untrusted-content-isolation` |
| CORRECTION | "no", "not what I said", "again" | `no-sycophancy` |
| VERDICT ASKED | "did X work", "which is better", "worth it" | `discriminator` |
| PROHIBITION GIVEN | "don't touch", "never commit" | `own-guardrails-bind-me` |
| MULTI-PART ASK | three or more imperatives in one prompt | `no-self-report-omissions` |

Measured on one 5,692-prompt corpus it fired on 18% of prompts, no single trigger
above 6.3%. **Re-measure on your own corpus before trusting those numbers** - the
patterns are tuned to one person's phrasing, and a trigger that fires on one prompt
in ten crowds out the others under the two-line cap.

Two tuning lessons that cost real false positives:

- Match on word *sense*, not the word. `lags` was autocorrelation and `frozen` was an
  immutable extract, both in ordinary use. Ambiguous terms now need a domain noun
  alongside them.
- Watch for substrings inside your own escape hatches. An escape list containing
  `redone` matched inside `NOT REDONE` and silently reopened the hole it closed.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/prompt-shape-guard.sh" } ] }
    ]
  }
}
```

## 5. self-invalidation-guard

Catches "my earlier number was wrong" / "that makes the rest suspect" followed by
nothing. Measured over one corpus: 91 such messages across 36 sessions, 84 of them
with no re-run in the same message. The admission gets treated as the remedy; the
stale figure stays published.

- **Stop**: blocks unless the same message shows the re-run. Blocking a Stop
  continues the turn, so tools are still available - the correct response is a tool
  call, not a re-draft.

An earlier version also accepted `NOT REDONE: <reason>`. That was a loophole:
re-wording satisfies a Stop hook while the number stays wrong. Removed.

## 6. unreferenced-flag-guard

Enforces `no-invented-hazards` on the softer phrasings that slip past it - "worth
checking", "one thing to watch", "may be worth". Measured: of 220 such clauses, 144
(65%) cite no referent at all and 46% sit in the last quarter of the message.

- **Stop**: blocks a flag clause with no `file:line`, backticked identifier,
  measured quantity or path. The block text says **delete the sentence**, not
  investigate it - an invented item does not become real by being chased.

Unlike the other guards it does **not** strip inline code spans, because a
backticked identifier is the referent being tested.

## 7. deferral-notice

The only non-blocking hook here. Surfaces a parked item rather than forcing action,
since deferring is sometimes correct.

- **Stop**: emits `systemMessage` (available to every hook type, renders in the UI
  without stopping the turn) when a message parks something. Stays silent when the
  deferral is reasoned - "because", "blocked on", "you have not asked".

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/self-invalidation-guard.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/unreferenced-flag-guard.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/deferral-notice.sh" } ] }
    ]
  }
}
```

## A caveat that applies to all of them

Every hook here scans text without knowing who wrote it. Quoting the user back can
trip the prose guard; a hook's own test fixtures can trip itself. Fenced blocks are
stripped for that reason, but the hole is structural, not fixable by tuning.
