# SC-3338 — Phase 2 Build Log: Flow guidance modal (AC3)

**Status:** ✅ Built + deployed to FortraUAT 2026-06-12 · data-layer validated on real Quotes. Prod-safe (no dependency on UAT-only Order machinery) — prod deferred to Phase 5.

## Artifacts (all live in UAT)
| Component | API name | State | Notes |
|---|---|---|---|
| Screen flow | `Fortra_Quote_Required_Fields_Check` | v1 **Active** | Read-only "Order Readiness" checklist; `runInMode=SystemModeWithSharing` (avoids FLS false-negatives); no DML |
| Quick action | `Quote.Review_Required_Fields` (Type=Flow, label "Required Fields Check") | Created | Launches the flow with `recordId` |
| Page layout | `Quote-Quote Layout` | Changed | Action added to `platformActionList` at sortOrder 6 (right after Convert Quote to Order; within the 7 visible actions) |
| Page layout | `Quote-Amendment Quote Layout` | Changed | Action added after CreateOrder |

Source: `force-app/main/default/flows/Fortra_Quote_Required_Fields_Check.flow-meta.xml`, `force-app/main/default/quickActions/Quote.Review_Required_Fields.quickAction-meta.xml`. Layout edits deployed from `Data/sc3338/phase2/layout/unpackaged` (layouts are not tracked in force-app).

## Design (per 14_SOLUTION_DESIGN.md §2)
- **Quote-side analog, NOT the Order validator.** `OrderSubmissionValidator` is Order-Id-keyed and there's no Order pre-conversion. This flow reads the live Quote + Account + both Contacts + Ship-To Place directly.
- **5 Get Records** (Quote → Account → BillToContact → ShipToContact[=Quote Contact] → ShipToPlace), each a simple `Id =` filter — robust, no relationship-name guessing. The conversion mapping authority is `QuoteToOrderFieldMapper.cls:13-31` (Order.ShipToContactId ← Quote.ContactId; Order.Ship_To_Account__c ← Quote.Ship_To_Place__r.Account__c).
- **20 line formulas** render `✅ Field` / `❌ Field — how to fix`; semantics mirror `OrderSubmissionValidator.isValuePopulated` (text non-blank; reference non-null; checkbox always-populated → the Workday Mobile Primary lines show ✅ once the contact exists). Picklist refs (`Account.Type`, Workday device/usage types) wrapped in `TEXT()` per Flow formula rules.
- **`fReady`** = AND of all presence checks → drives a green "Ready to convert" vs amber "Action needed" header.
- **4 grouped sections:** On this Quote / On the Customer Account / On the Bill To Contact / On the Ship To Contact, + footer noting auto-populated fields (Tax, Line Numbers, Billing Frequency, Workday IDs).

## Validation (data-layer simulation on live Quotes)
Ran the exact cross-object reads + presence logic against real Quotes — all field refs resolve and output is correct & useful:
- `0Q0WC0000038PHF0A2` (complete): all "On this Quote" ✅, but **Account Phone ❌ + D&B DUNS ❌** — exactly the rep-guidance surface the research predicted.
- `0Q0WC0000038ORd0AM` (incomplete): **Bill To Contact ❌ + Start Date ❌** correctly flagged.

## Deploy gotchas (resolved)
1. Picklist fields in `ISBLANK()` → must wrap in `TEXT()` ("Picklist fields are only supported in certain functions"). Fixed.
2. Flow QuickAction requires `optionsCreateFeedItem` and rejects `height` ("Field cannot be set for type Flow"). Final QA has `optionsCreateFeedItem=false`, no `height`.
3. A combined flow+QA deploy rolls back the flow if the QA fails, and a Flow-QA can't validate against a not-yet-existing flow → deploy **flow first**, then QA.
4. Pre-existing stray `classes/rca_diagnostic.cls-meta.xml` breaks full-project `--metadata` deploys → deploy by `--source-dir`/`--metadata-dir`.

## Correction — surfacing lever was the FlexiPage, not the layout (2026-06-12)
The Quote Lightning page (`Quote_Record_Page`) Highlights Panel has **dynamic actions enabled** (`force:highlightsPanel` with `enableActionsConfiguration=true` + an `actionNames` valueList). With dynamic actions on, the **page-layout `platformActionList` is ignored** for this page. The action was therefore added to the **FlexiPage** Highlights Panel `actionNames` list, right after `Quote.Convert_Quote_to_Order` (position 5; `numVisibleActions=7` so it's visible). Deployed + live-verified.
- Side effect: this pushes `SyncQuote` (Start Sync) from the 7th visible slot into the overflow "more" menu. If Start Sync should stay visible, bump `numVisibleActions` to 8. (Awaiting preference.)
- The earlier **page-layout** action additions (both Quote layouts) are now **inert/redundant** for this page but harmless — they remain as a fallback if dynamic actions are ever disabled, and cover mobile/other contexts. Can be reverted for a minimal change set if desired.
- FlexiPage is **not tracked in force-app** (like layouts); deployable copy saved at `Data/sc3338/phase2/flexi/unpackaged/` for the Phase 5 prod deploy.

## Remaining for sign-off
- **Manual click-test in UAT** (human): open a Quote → "Required Fields Check" action → confirm the modal renders the grouped ✅/❌ list and the header. Data layer is validated; this just confirms the screen render.
- Wren UX review of grouping/wording (Phase 0).
- Prod deploy (Phase 5): flow + quick action + the two layout action additions are all prod-safe.
