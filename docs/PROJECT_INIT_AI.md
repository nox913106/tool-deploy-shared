# PROJECT_INIT_AI — AI Operational Instructions

> This file is for AI tools only.
> Human reference: docs/PROJECT_INIT.md

---

## BEFORE ANY TASK — MANDATORY

Execute these steps in order before doing anything else:

1. Read `docs/SYSTEM_STANDARD_AI.md` — confirm system-level rules
2. Read `docs/GUARD.md` — confirm what you MUST NOT do
3. Read `docs/ROLES.md` — confirm your role and boundaries
4. Read `docs/STATE.md` — confirm current stage and known issues
5. Ask the human: "Which stage are we on? Is the previous stage complete?"
6. Wait for human confirmation before proceeding

---

## STAGE GATE RULES

MUST NOT proceed to any stage if the previous stage is incomplete.

| Stage | Gate Condition |
|-------|---------------|
| Stage 2 | Feature list frozen and human-signed |
| Stage 3 | SPEC / GUARD / ROLES / STATE all exist |
| Stage 4 | git initialized, ERROR_CODE.md exists |
| Stage 5 | .env.example exists, GUARD.md lists protected files |
| Stage 6 | DB selection documented in SPEC.md |
| Stage 7 | Auth mechanism defined, /docs protection confirmed |
| Dev Start | All 7 stages complete, human signed off |

IF any gate condition is not met:
STOP. Report which stage is blocked. DO NOT attempt to complete it yourself.

---

## YOU MUST NOT

- Write any code before all 7 stages are complete
- Modify any file in `docs/` (only exception: `docs/STATE.md`, which you MUST keep updated)
- Modify any `*_system_prompt.md` in `prompts/`
- Read or modify `.env`
- Connect to any production system
- Skip any stage gate
- Make assumptions about incomplete stages

---

## YOU MUST

- Output commands for human to execute, never execute production commands
- Record cross-role interface changes in `docs/STATE.md` before executing
- Stop and report when uncertain — never guess
- After completing any task, output a 3-line debug card and append to `logs/DEBUG_LOG.md`

---

## LOG FORMAT — MANDATORY

```
{timestamp+08:00} [{LEVEL}] {error_code} | {service} | {message} | {context}
```

LEVEL: DEBUG / INFO / WARNING / ERROR / CRITICAL
No error code: use `-` as placeholder

---

## ERROR CODE FORMAT

Structure: E + module (1 digit) + category (1 digit) + sequence (2 digits)
Module (1st digit): 1=fetch 2=llm 3=output 4=scheduler 5=system
Category (2nd digit): 0=connection 1=format 2=timeout 3=permission 9=unexpected
Example: E2201 = llm (2) timeout (2), sequence 01

All error codes MUST be defined in `docs/ERROR_CODE.md` before use.

---

## UNCERTAINTY PROTOCOL

IF uncertain about anything:
1. STOP current task
2. Output debug commands for human to execute and return results
   OR request code review agent verification
3. DO NOT continue until resolved

---

## ROLE ASSIGNMENT

Confirm your assigned role from `docs/ROLES.md` before starting any task.
MUST NOT perform actions outside your assigned role boundary.
Cross-role actions require AI Leader coordination and human approval.

---

## WORK SCOPE BOUNDARY — CHECK BEFORE EVERY FILE OPERATION

Work scope = "SideProject" directory and ALL descendants ONLY.
Defined by directory NAME, not drive letter or absolute path.

BEFORE every file operation, verify internally:
"Is this path within SideProject or a descendant of SideProject?"

If NO → STOP. Report to human. DO NOT execute.
"能執行" ≠ "應該執行"
