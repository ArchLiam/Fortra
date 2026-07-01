# SC-3473 — Salesforce Platform Case (draft, ready to file)

**File against:** Revenue Lifecycle Management (Revenue Cloud) → Pricing / Place Sales Transaction
**Severity:** High — GoLive blocker (`LOB-Salesforce-2-GoLive`)
**Org:** `fortra--uat` (`00DWC000006eUFF2A2`) · RLM Dev Guide v67.0 (Summer '26) · API v67

---

## Subject
RLM Quote Line Editor **"Delete Group"** surfaces a raw JEP-358 `NullPointerException` (`Cannot invoke "Object.toString()" because the return value of "java.util.Map.get(Object)" is null`) instead of a guarded error message; the quote header commits but the group is not deleted.

## Description
In the Quote Line Editor, opening a group's action menu and clicking **Delete Group** fails with the red toast:

> Your quote was not updated. Cannot invoke "Object.toString()" because the return value of "java.util.Map.get(Object)" is null

The string is a JVM JEP-358 "helpful NullPointerException" emitted by the **native managed pricing/context engine** (it cannot originate in Apex — Apex null-derefs read "Attempt to de-reference a null object" and never name `java.util.Map`; the error is **not logged to Apex**). Per the Place Sales Transaction contract the engine **commits the quote header first and does not roll back a later-step failure**, so the group stays undeleted and the user sees "Your quote was not updated."

We confirmed the quote's **`CalculationStatus = SaveFailedOrIncomplete`** — i.e., the engine's *designed* status taxonomy fired, yet the raw JVM exception still leaked to the UI instead of an actionable `PlaceQuoteErrorResponse`. **That message leak is the platform defect we are reporting**, independent of the in-org data condition that triggers it.

## Reproduction (in our UAT)
- Quote `0Q0WC000002U2020AC` ("Test Wren - Order Processing", Accepted, USD, 4 lines).
- Group `1C9WC00000097of0AA` "Test HW1" (`Hardware_Group_Type__c=True`) containing 2 lines: **Advanced Job Scheduler** (PSM "One Time"/OneTime) and **Abstract** (PSM "Term Based - Annual"/TermDefined). 2 ungrouped **Suspicious Email Intelligence** (TermDefined) lines survive and are force-repriced.
- Action: Quote Line Editor → Test HW1 caret → **Delete Group** → the toast above.
- Active pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` **V16**; active context `SalesTransactionContextExt_v2` **V23** (bound to the procedure). Catalog is complete (each (Product2, PSM) pair has one active USD PricebookEntry + PSMO).

## Likely in-org trigger (for your trace to confirm)
The to-be-deleted **Abstract** line is **TermDefined/Annual with `EndDate = NULL` and `PricingTermCount = NULL`** (a malformed term state; the surviving lines are fully termed). We believe the forced reprice routes this null term/end-date into a term/proration or context-hydration map whose `Map.get(...)` returns null. We could not isolate the exact native frame read-only.

## Cross-reference
The only documented sibling of this exact NPE class is in the native Industries Context Service: `Cannot invoke industries.context.api.service.model.runtime.schema.impl.defaultimpl.DefaultContextRuntimeEntityAttribute.getTags() because the return value of java.util.Map.get(Object) is null` (a context-hydration failure remedied via Context Definition Mappings). Same `java.util.Map.get(Object)==null` JEP-358 pattern.

## What we are asking Salesforce to do
1. **Run a native pricing/context trace** on this transaction (we can reproduce on demand with debug logging on) to identify the exact native **frame** and the **null map key**.
2. **Null-guard** the unguarded `map.get(key).toString()` path so that a config/data prerequisite gap surfaces as an actionable `PlaceQuoteErrorResponse` / `CalculationStatus` message (e.g., "TermDefined line is missing its end date / term") **instead of a raw JVM NullPointerException**.
3. Confirm whether correcting the line's term fields and/or re-publishing the context definition is the supported remediation for the in-org trigger.

## Attachments to include
- Screenshot of the toast (Jira SC-3473 `image-202606...648.png`).
- The `CalculationStatus=SaveFailedOrIncomplete` query result.
- This RCA (`README.md` + `02_SOLUTION_ROADMAP.md`).
- A `referenceId` from a debug-logged repro **once captured** (see `REPRO_RUNBOOK.md`) — supplement the case with it to pinpoint the transaction.
