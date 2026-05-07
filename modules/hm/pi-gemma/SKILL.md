---
name: gemma-coding
description: >
  Structured agentic coding protocol for Gemma4 A4B. Load this skill at the
  start of any coding task. Provides: working document initialisation, surgical
  codebase exploration, file editing protocol, sub-agent delegation, and
  context-budget discipline. Use when fixing bugs, adding features, refactoring,
  or analysing unfamiliar codebases.
---

# Gemma Coding Protocol

## Start here — call this tool right now

```
bash: git ls-files | head -60
```

Do not narrate. Do not plan. Call the bash tool with that command and wait for output.

---

## After you have the file list

**Fill in WORKDOC.md** (it already exists — use `edit` to populate it):

```
## Project
<repo name, language, what it does — one sentence>

## Task
<ask the user if not stated>

## Scope
<which files/modules are in scope>

## Findings
(fill as you explore)

## Plan
(fill after enough findings)

## Decisions
(fill as constraints emerge)

## Open Questions
(fill before asking the user for help)
```

Then tell the user: "Ready. What are we working on?" — unless they already told you.

---

## Exploration — always in this exact order, no exceptions

**1. Find with git grep — never skip this step**
```
bash: git grep -n 'SymbolOrPattern'
bash: git ls-files | grep -i 'pattern'
```

**2. Locate the line number**
```
bash: grep -n 'def target_function' path/to/file.py
```

**3. Read only that range — 80 lines max per call**
```
bash: sed -n '45,90p' path/to/file.py
```

Never read a file before step 1. Never use `cat`. Never use `ls` or `find`.
If a file is >300 lines, steps 1+2 are mandatory — no exceptions.

After each discovery → update **Findings** in WORKDOC.md immediately.

---

## Planning

Once you have enough findings, write a checklist in WORKDOC.md:

```
## Plan
[ ] patch `_poll_loop` (module.py:47) — change single-startup query to loop
[ ] add asyncio.sleep(interval) inside loop
[ ] verify: hypothesis "tasks added at runtime are picked up within interval"
[ ] commit if tests pass
```

Save WORKDOC.md before touching any source files.

---

## Applying changes

**Editing existing files** — use `edit`:
- Before calling `edit`: one sentence stating what you are changing and why
- After `edit`: verify with `sed -n` on the changed lines → mark step [done] in Plan
- If `edit` fails: refine the instruction — do NOT fall back to `write`

**New files only** — use `write`:
- Confirm the file does not exist: `bash: git ls-files | grep filename`
- `write` silently overwrites — never use it on an existing file

**Tests:**
```
bash: python -m pytest tests/relevant_test.py -x -q 2>&1 | tail -20
```
State your hypothesis before running. Update **Findings** with the result.

---

## Verifying edits

After the user confirms an edit applied:
- Do NOT re-issue it
- Read the changed section with `sed -n` to confirm
- Mark the step [done] in Plan

---

## Sub-agent delegation — `spawn_subagent` tool

Use for focused analysis of complex logic without loading whole files into context.

Good: interface assessment, cross-file compatibility, understanding a complex class.
Bad: finding symbols (→ git grep), reading a function (→ grep + sed), listing files (→ git ls-files).

Always include `context`. Keep prompt to one question. End with "Be as brief as possible, no preamble."

---

## Context discipline

WORKDOC.md is your memory. When Pi compacts old turns, anything not in WORKDOC.md is gone.

Before each WORKDOC update: mark completed steps [done], capture findings, log decisions.
After compaction: read WORKDOC.md first, resume from Plan, do not re-explore Findings.

---

## Commit (only when user asks)

```
bash: git add -u
bash: git commit -m "fix: short lowercase description"
```
