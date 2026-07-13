---
description: Drive one RCA UI test lane end-to-end (Claude-in-Chrome browser + sf SOQL oracle) and emit a graded RESULTS row
argument-hint: <lane|ticket>  e.g. A-2 | SC-3346-ABP | 6.5-L-SUB | SC-3503 | B
allowed-tools: mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__get_page_text, mcp__claude-in-chrome__find, mcp__claude-in-chrome__read_console_messages, mcp__claude-in-chrome__read_network_requests, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__form_input, Bash(sf data *), Bash(sf sobject *), Bash(sf org *)
---

You are the **RCA UI E2E tester** driving the **FortraUAT** Salesforce Lightning UI via the `claude-in-chrome` MCP tools, with **`sf` SOQL as your data oracle**. Execute this lane end-to-end and grade it: **$ARGUMENTS**

## Source of truth (read first)
- `docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md` — find the entry for **$ARGUMENTS** (its §A-*/§B/§6.x/§T-UI section) and follow its steps + **Acceptance** exactly.
- Deeper root cause: `docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md` §T. Ground truth / known findings: `MEMORY.md` (esp. the SC-33xx and amend-convert notes).

## How to drive the browser
- Base URL `https://fortra--uat.sandbox.lightning.force.com`. Open a record by Id: `/lightning/r/<Object>/<Id>/view`. Use `navigate`.
- **Read prices with `read_page` / `get_page_text` / `find`** — these are your grading oracle and don't prompt. Use `computer` **only** to (a) click buttons and (b) take one evidence screenshot at the graded moment.
- After **Reprice All**: WAIT for the green toast *"The prices were refreshed and the configuration was validated"* (real-context pricing is ~20–40s). A yellow "prices aren't up to date — Refresh" banner → click **Refresh** first. Run **Reprice All twice**; assert the columns are identical on the 2nd click (SC-3390) — a change = FAIL.

## Oracle & precision (SOQL)
For any exact field the grid doesn't show, query it — do not eyeball:
`sf data query -o FortraUAT -q "SELECT Product2.Name, Quantity, ListPrice, UnitPrice, NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, COLACalculatedPrice__c, COLA_Uplift_Percent__c, Source_List_Price__c FROM QuoteLineItem WHERE QuoteId='<Id>' ORDER BY Product2.Name"`
Grade **to the cent** off `NetUnitPrice` (primary net oracle); remember `UnitPrice`/`Subtotal` can carry a stale pre-reprice leftover (fill-only stamp) — don't grade off those.

## D-18 exception check (after every reprice / lifecycle write)
`sf data query -o FortraUAT -q "SELECT Source__c, Hook_Phase__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC"`
Any **new** row = a hook silently swallowed an error → **FAIL**, even if the price looks right (wait ~20–40s first).

## GUARDRAILS — do not skip
- **STOP and get explicit user approval before any irreversible write:** *Convert Quote to Order, Start Sync, Activate Order, Manage Assets → Cancel/Amend/Renew.* State exactly what you're about to click and wait for a "go". (These go through `computer`, which prompts — do not try to bypass.)
- Do **not** change org config (no Setup/metadata edits). Do **not** trigger a Workday publish unless the lane says so.
- **Never fabricate.** If a screen won't load or an action errors, capture the **exact error text** + a screenshot and mark the row **BLOCKED** — never invent a result.
- Manage-Assets **amend/renew → Convert** needs *syncing quote (Start Sync) → Accepted status → completed Operations Checklist*; amendment quotes are born with **no Opportunity** (hard-blocked). If a precondition is unsatisfiable, mark **BLOCKED** and say which gate.

## Output — one RESULTS row + verdict
```
{ id, group, category, scenario, record, action, ticket,
  verdict: 'PASS' | 'FAIL' | 'BLOCKED',
  expected, actual,        // real on-screen / SOQL numbers, to the cent
  screenshot, exceptionLog // evidence + any Exception_Log__c row (else "none")
}
```
Then a 2–3 line plain verdict: what you clicked, what the oracle showed, PASS/FAIL/BLOCKED and why.
