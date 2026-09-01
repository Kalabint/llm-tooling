# llm-tooling

This repo contains claude code tooling and my old ChatGPT Primer.

## How it Works

The claude code harness tries to give claude hints and rules to avoid the most common
llm failure modes. It works by adding pre and after hooks to the answers, where scripts
react to the in and outputs of human and machine, kindly reminding claude to BE AN ADULT.

## Hints

  If you spot an error: **give additional context which avoids the error and re-prompt again.**  
  **DO NOT attempt to "fix" the error within the same thread!**
  This will only lead to context poisoning.

## Guiding principles

The Machine will try to keep to the facts and generally be as grounded as possible.
If the Machine steers off, it will get reprimanded.
If the *user* types stuff which leads to known llm failure modes, the harness injects
preemptive reminders.
The Machine will forget. It's on the harness to work around this.

## Background

Rules collected over my work with cc and constantly getting reminded that llms like to
acknowledge things while changing absolutely nothing.

Things that are broken and not fixed yet:

- Two rules fall out of the report when they fire alongside anything else: the one about
  comparing two sources, and the one about asserting what a setting does.
- The `memory-audit` timer reads one path and writes another, so it never stops nagging.
- Only the first draft gets scanned. The rewrite is not checked.
- Quoting someone who used a banned word trips the guard.
- Code fences give up at a fence inside a fence, so code examples can trip it too.

No test corpus. No `plugin.json` — install is manual, into two different places.

## Example

    User:  did the loop approach work better?
    Hook:  VERDICT ASKED -> name the quantity asked about vs the proxy you can
           measure, and try to refute your own strongest number first.
           [skill: .claude/skills/discriminator/]

    Model: "my earlier count was wrong" with no re-run
    Hook:  BLOCK -> re-run it now and give the corrected number. Re-wording does
           not clear this.

## Repository Contents

- [`.claude/skills/`](.claude/skills/): 19 skills. Start with `discriminator`,
  `no-invented-hazards`, `check-dont-assume`.
- [`.claude/hooks/`](.claude/hooks/): 9 hooks and the shared pattern file, with install
  JSON in [its README](.claude/hooks/README.md). Needs `bash` and `jq`.
- [`universal_task_system_instructions.txt`](universal_task_system_instructions.txt): the
  ChatGPT primer — give it a query, it lists topics, selects an overqualified role, and
  answers from that perspective.
- [`chatgpt_custom_instructions.md`](chatgpt_custom_instructions.md): custom-instructions
  form, both fields.
