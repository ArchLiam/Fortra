# SC-3143 — Integration E2E Testing Path to Complete

**Source ticket:** [SC-3143](https://helpsystems.atlassian.net/browse/SC-3143) (parent: none — this is the E2E tracker)
**Component:** SF RCA
**Reporter:** Jomil Bell — **Assignee:** Andy Kumar
**Priority:** Critical — **Due:** 2026-05-27 — **Sprint:** CRM Sprint 14
**Status:** In Progress

## Ticket summary
End-to-end testing path for the Workday integration. Unit testing (Fortra Order Unit Testing)
is complete; E2E readiness requires examples A, B, C, D covering **Inquiry → Opportunity → Order**
mapping. Workday API references (Contract Data, Billing Schedule Data, Revenue Data) and the
*Fortra Integration Mapping Workbook (2026-05-04)* define the values expected to pass through
integration on trigger-activity creation.

E2E requirements:
1. Watch the demo.
2. Work the Integration List View of Master Test Cases — complete each MTC (sort by Sort Order,
   assign each test case to yourself).

## Subtickets
- [SC-3291](../sc3291/) — Account / Contact / Places validation errors on Order submission for Workday
- [SC-3292](../sc3292/) — Inquiry → Opportunity conversion: populate Territory

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This file — ticket scaffold and working notes |
