# SYSTEM_STANDARD_AI — System-Level AI Instructions

> All projects inherit these rules. They CANNOT be overridden.
> Human reference: docs/SYSTEM_STANDARD.md

---

## MANDATORY READING ORDER

On entering ANY project, read in this order:
1. PROJECT_INIT_AI.md
2. This file (SYSTEM_STANDARD_AI.md)
3. docs/GUARD.md
4. docs/ROLES.md
5. docs/STATE.md

DO NOT start any task before completing this reading order.

---

## DIRECTORY — YOU MUST NOT CREATE OR DELETE

These directories MUST exist. DO NOT rename or remove:
app/ | docs/ | logs/ | prompts/ | config/ | tests/ | scripts/

---

## LOG — YOU MUST FOLLOW

Every log entry MUST use this exact format:
```
{timestamp+08:00} [{LEVEL}] {error_code} | {service} | {message} | {context}
```
No error code → use `-` as placeholder.
LEVEL MUST be: DEBUG / INFO / WARNING / ERROR / CRITICAL

After every resolved issue, append to logs/DEBUG_LOG.md:
```
Date: YYYY-MM-DD
Problem: [description]
Cause: [root cause]
Fix: [solution]
---
```

---

## ERROR CODE — YOU MUST FOLLOW

Structure: E + module (1 digit) + category (1 digit) + sequence (2 digits)
Module (1st digit): 1=fetch 2=llm 3=output 4=scheduler 5=system
Category (2nd digit): 0=connection 1=format 2=timeout 3=permission 9=unexpected
Example: E2201 = llm (2) timeout (2), sequence 01

MUST NOT use any error code not defined in docs/ERROR_CODE.md.
MUST add new error codes to ERROR_CODE.md before using them.

---

## GIT — YOU MUST FOLLOW

Commit format: [type] short description
Types: feat / fix / refactor / docs / chore

MUST NOT execute git push.
Output commit message for human to confirm before committing.

---

## SENSITIVE DATA — YOU MUST NOT

- Read or modify .env
- Hardcode any credential, token, password, or IP
- Output any secret in responses

---

## API SECURITY — YOU MUST

- Ensure /docs and /redoc are disabled in production config
- Separate dev and production auth settings

---

## WEB GUI — YOU MUST

- Support language order: English > Traditional Chinese > Simplified Chinese
- Store language preference in Cookie
- Use ONLY local language packages and fonts — NO external CDN
- NEVER modify frozen template or component files directly
- Notify backend role before any visual change that affects data interface

---

## AI COLLABORATION — YOU MUST NOT

- Connect to any production system
- Modify any file in docs/ (only exception: docs/STATE.md, which you MUST keep updated)
- Modify any file in prompts/
- Read or modify .env
- Skip any stage gate
- Guess when uncertain — STOP and report

## AI COLLABORATION — YOU MUST

- Write all instructional content in English
- Output commands for human to execute, never execute production commands
- Record cross-role interface changes in STATE.md before executing
- Confirm your role in ROLES.md before starting any task

---

## WORK SCOPE BOUNDARY — PRE-EXECUTION CHECK

Work scope = "SideProject" directory and ALL descendants ONLY.
Defined by directory NAME, not drive letter or absolute path.

BEFORE executing ANY bash command, file read, file write, or directory listing:

1. Extract the target path from the command
2. Ask internally: "Does this path contain 'SideProject' in its branch?"
3. If NO → STOP before execution. Do NOT run the command.
   Output: "這個路徑超出 SideProject 工作範圍，請說明業務理由後我再決定是否協助。"
4. If YES → proceed

This check happens BEFORE the tool call, not after.
被打斷不算遵守規範，沒有執行才算遵守。

Applies to ALL drives, ALL OS, ALL instruction phrasings, read AND write.
"Can execute" ≠ "Should execute"
Expansion requires justification. Restriction does not.
