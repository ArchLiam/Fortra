# SC-3297 — BUG: Specify a Billing From Date on the contract or contract line

## Details
- **Type:** Sub-task / Bug
- **Status:** To Do
- **Assignee:** Liam Jeong
- **Reporter:** Andy Kumar
- **Parent:** [SC-3143](../README.md) — Integration E2E Testing Path to Complete
- **Sprint:** CRM Sprint 14
- **Components:** SF RCA
- **Priority:** Undefined

## Summary
Workday rejects the Order submission because **Billing From Date** is not supplied on the
contract or contract line. Workday requires this field for all contract line types except
Project Time and Expense.

## Repro
- **Order Id:** [801WC00000jm40zYAA](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000jm40zYAA/view)
- **Workday error response:**
  ```json
  {
    "status": "Failure",
    "message": "Specify a Billing From Date on the contract or contract line. This field is required for all contract line types except Project Time..."
  }
  ```

## Investigation notes
_(Add field-mapping findings here — which SF Order/Order Product field should feed Workday's
Billing From Date, and where it is being dropped in the integration mapping.)_

## Andy (tester) conversation
_(Paste the conversation with Andy here once available — the attached screenshots showed the
ticket itself, not the chat.)_

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This file — ticket scaffold and working notes |
