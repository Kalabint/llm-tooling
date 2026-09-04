# Hook archive

Superseded versions of the Stop/PreToolUse guards that live in `~/.claude/hooks`.
Each was taken immediately before the edit named in its suffix, so the pair
`X` and `X.pre-<change>` is a before/after of one behavioural class being added.

The live counterparts enforce at runtime what `.claude/skills/` in this repo
states as instructions — `check-dont-assume`, `no-invented-hazards`,
`no-self-report-omissions`, `no-unmeasured-numbers`, `own-guardrails-bind-me`.
Kept because the diffs record *why* each class exists: every one carries a dated
incident in its comment, and the comment is what does the work, not the regex.

## Ordering

`banned-patterns.sh` holds the patterns; `no-superlative-guard.sh` dispatches
them. Oldest first:

| file | the change it precedes |
|---|---|
| `banned-patterns.sh.bak` | earliest snapshot |
| `banned-patterns.sh.pre712` | — |
| `banned-patterns.sh.pre-disclose` | disclosure-narration block added to TIC |
| `banned-patterns.sh.pre-fix` / `no-superlative-guard.sh.pre-fix` | class 12 FIXP, declaring a fix before the cause is reproduced |
| `banned-patterns.sh.pre-unrun` / `no-superlative-guard.sh.pre-unrun` | class 13 UNRUN, naming a measurement instead of taking it |
| `banned-patterns.sh.pre-unban` | `genuinely` un-banned |
| `banned-patterns.sh.pre-abs` / `no-superlative-guard.sh.pre-abs` | class 14 ABS, claiming absence without a search |
| `no-superlative-guard.sh.bak`, `.pre72` | earlier dispatch snapshots |
| `announce-then-stop-guard.sh.pre-selfdep` | self-dependency check |
| `announce-then-stop-guard.sh.pre-rawescape` | raw-escape handling |
| `announce-then-stop-guard.sh.pre-boxrule` | code-box rule for attention text |

Hostnames in comments are placeholders (`traccar.example`).
