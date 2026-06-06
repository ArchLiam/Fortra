# SC-3297 — BUG: Specify a Billing From/To Date on the contract or contract line

## Details
- **Type:** Sub-task / Bug
- **Status:** Fix deployed to FortraUAT (Flow **v4**, 2026-06-05) — repro order **verified**; 4 other submission-surface lines pending recompute. See **§ Resolution log (2026-06-05)** below.
- **Assignee:** Liam Jeong
- **Reporter:** Andy Kumar
- **Parent:** [SC-3143](../README.md) — Integration E2E Testing Path to Complete
- **Sprint:** CRM Sprint 14 · **Components:** SF RCA · **Priority:** Undefined

## TL;DR
The ticket title says **Billing _From_ Date**, but that symptom is already fixed. On the live UAT
order the From Date is populated on both lines and the Workday rejection has **moved to the Billing
_To_ Date** on the "New Maintenance" line. Root cause: the date-setting flow copies a structurally
**null `OrderItem.EndDate`** into `Billing_Schedule_To_Date__c` for non-perpetual lines instead of
deriving the term end. Per Fortra's own SKU/Finance documentation, **New Maintenance (RC_42000) is a
Term Based – Renew, 12-month** line — so the correct To Date is **From + 12 months − 1 day**.

## Repro
- **Order:** [801WC00000jm40zYAA](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000jm40zYAA/view) (OrderNumber **00095276**, EffectiveDate 2026-05-29, Workday_Contract_Type = Master_Contract)
- **Current live Workday error** (`Order.Workday_Sync_Message__c`):
  ```json
  { "status": "Failure",
    "message": "Specify a Billing To Date on the contract or contract line. This field is required for all contract line types except Project Time and Expense and Usage when you use a billing template that generates installments with To Date." }
  ```
  > The original report quoted *"Billing **From** Date"*; the From Date has since been populated, so the live failure is now the **To** Date. Same mechanism, next field.

## Order line data (live FortraUAT)
| Line | OrderItem | Product | Rev Cat | Family | Branch | From Date | To Date | Result |
|---|---|---|---|---|---|---|---|---|
| 1 | 802WC00000O62FpYAJ | GS-GSE-NRPS-E8CP (EFT 8 Continuum) | RC_41000 | Perpetual | **Perpetual** | 2026-05-29 | 2026-05-29 | ✅ PASS |
| 2 | 802WC00000O62FqYAJ | GS-GSE-RNM-EFT8 (EFT 8 Continuum-NewMaintenance) | RC_42000 | New Maintenance | **Non-Perpetual** | 2026-05-29 | **NULL** | ❌ FAIL |

Both lines are `Workday_Contract_Line_Type__c = FIXED AMOUNT` (not exempt), so both require a To Date.
Line 2 also has `Product_Selling_Model_Type__c = "One Time"`, `ServiceDate = 2026-05-29`, `EndDate = NULL`.

## Root cause
1. The before-save flow **`Fortra_OrderItem_Set_Dates`** (Active **v2**, Flow Id `301WC00000jhe3XYAQ`,
   record-triggered on OrderItem) populates the billing-schedule dates. Its Decision **`Perpetual`**
   (`1 OR 2 OR 3 OR 4 OR 5 OR (6 AND 7)`) splits two branches:
   - **Perpetual** (Rev_Category ∈ {RC_41000, RC_45000, RC_45001, RC_45002}, or MyCap, or
     SellingModel="One Time" **AND** Family="Perpetual") → `From = To = Order.EffectiveDate`.
   - **Non-Perpetual** (everything else) → `From = ServiceDate`, **`To = OrderItem.EndDate`**.
2. **Line 1** matches condition 1 (RC_41000) → Perpetual branch → From=To=2026-05-29 → passes.
3. **Line 2** matches **none** of the conditions (RC_42000, MyCap=false, Family="New Maintenance"
   ≠ "Perpetual") → Non-Perpetual branch → `To = OrderItem.EndDate` = **NULL** → Workday rejects.
4. **Why `EndDate` is null:** the flow only *copies* an end date, it never *derives* one. The source
   Quote line (`0QLWC000003Xe9p4AC`, quote `0Q0WC0000032Ttp0AE`) has **no dates or term at all**
   (ServiceDate / StartDate / EndDate / SubscriptionTerm all null), and the maintenance product /
   selling model carries **no term**. So `EndDate` arrives null and the To Date is left blank.
5. **Systemic, not a one-off:** a live query found **0** RC_42000 New Maintenance OrderItems anywhere
   in the org with a populated `Billing_Schedule_To_Date__c` — every New Maintenance line is in this
   same broken state. The fix therefore belongs in the automation chokepoint (the flow), not in data.

## Resolution (documentation-backed)
Fortra's **New Sku Database Requirements** doc (Confluence; distilled in
[`FORTRA_KNOWLEDGE_BASE.md`](../../../FORTRA_KNOWLEDGE_BASE.md) §4.2) authoritatively defines the
Revenue Category:

> **RC_42000 · NEW MAINT · Recurring New Maintenance · Spread_Even · Deferred · Term Based – Renew · 12 Months**

and defines **Term Length** as a per-SKU field defaulting to **12 Months**. The "One Time" label on the
New Maintenance companion SKU (§4.3) refers to the **billing cadence** (one yearly invoice, matching
Line 2's `Billing_Frequency__c = Yearly_Billing_Template`), **not** a single-day service period — the
revenue is recognized Spread_Even over **12 months**, so the billing schedule must span the year.

**→ Correct To Date = Billing From Date + 12 months − 1 day.** For this order: **2026-05-29 → 2027-05-28**.
(Day-convention confirmed by the only working 12-month line in the org: ServiceDate 2025-06-01 → EndDate 2026-05-31.)

### Fix
Edit `Fortra_OrderItem_Set_Dates`, **Non-Perpetual branch** (`Non_Perpetual_Set_Dates` record-update),
so `Billing_Schedule_To_Date__c` (and `End_Date_Calculated__c`) are never null:
```
To Date = EndDate (if set)
        else Order.EndDate (if set)
        else ADDMONTHS(ServiceDate, 12) - 1     // documented 12-month maintenance/subscription term
```
> Retrieve the **live** flow first — it is not in `force-app`, and the archived copy at
> `*Jira/sc3211/retrieve/flows/Fortra_OrderItem_Set_Dates.flow-meta.xml` diverges from live v2.
> Do **not** mass-edit product/selling-model data (per scope: fix the root cause, not all the data).

### Adjacent items (bundled with this ticket)
- **Pre-submission validation:** add an `Order_Submit_Validation__mdt` row for
  `OrderItem.Billing_Schedule_To_Date__c` so SF blocks with a friendly error before the Workday round-trip.
- **MyCap discrepancy:** live flow Decision cond 5 reads `$Record.MYCAP__c` (OrderItem) while the
  SC-3211 intended fix used `$Record.Order.MyCap__c` (Order) — reconcile to the field-of-record.
- **Refresh `force-app`:** retrieve the live Active flow + `OrderItem` object into source control
  (repo currently lacks them).

## Verification
1. Deploy the flow change (v3) to FortraUAT.
2. Force Line 2 to recompute (touch the OrderItem so the before-save flow re-fires), then:
   `sf data query -o FortraUAT -q "SELECT Id, Billing_Schedule_From_Date__c, Billing_Schedule_To_Date__c, EndDate FROM OrderItem WHERE Id='802WC00000O62FqYAJ'"`
   → expect `Billing_Schedule_To_Date__c = 2027-05-28`.
3. Re-submit Order 801WC00000jm40zYAA; expect `Workday_Sync_Message__c` → Success and
   `Workday_Sync_Status__c` off Pending; both contract lines carry From + To.
4. Regression: submit one Perpetual-only and one Term-Based subscription order — confirm no branch regressed.

## Open / confirm before close
- **Confirm with Andy/business:** docs say New Maintenance = 12-month term — agree the Workday billing
  schedule should span the full year (2026-05-29 → 2027-05-28) rather than a single day. *(This is now a
  confirmation, not an open design decision.)*
- **Known data-quality flag** (Confluence *Sku Changes Needed*): some Term-Based SKUs carry a stray
  **1-month** term — reason to apply the documented **12-month default** in the flow rather than trust a
  product-level term field.
- **Authorization:** any UAT deploy (flow v3, CMDT) or data recompute needs a fresh explicit go-ahead.

## Andy (tester) conversation
_(Still to be pasted. The term-length question it was expected to answer has since been resolved by the
Confluence SKU documentation — see Resolution above.)_

## Resolution log (2026-06-05)
Deep data investigation against live FortraUAT **revised the fix** from the original design above.

**What the data changed.** The original design assumed RC_42000 was the only category on the
Non-Perpetual + EndDate-null "derived path" and that 12 months was uniformly correct. Live data
disproved both, but also showed the **Workday submission surface is tiny and 12-month-dominant**:
- Of **9,654** derived-path lines org-wide, only **5** sit on actually-submittable orders (the other
  ~9,602 are a bulk-migration backlog stuck "Activated/Pending" that has never transmitted to Workday).
- Those 5 span RC_42000 (2), RC_45005 Subscription (1), and **null-Rev** (2 — genuine Data Protection
  *Term-Based-Annual* products). 12 months is the modal term for **every** submitted category
  (RC_42000 73%, RC_45005 89%, null-Rev TBA 92%). The 24/36-mo tails live only on EndDate-**bearing**
  lines the fix never touches (derived-path lines are ~100% term-less "One Time" SKUs).
- → **Do not gate to RC_42000** (would leave 3 of the 5 real lines failing for no gain). Apply the
  12-month default flat to all non-perpetual lines.

**Two corrections vs the original formula:**
1. **Null `ServiceDate` defect.** 4 of the 5 submittable lines have **null ServiceDate**, so the original
   `ADDMONTHS(ServiceDate,12)-1` returned null and they'd *still* fail. Anchored on `Order.EffectiveDate`
   (100% populated on all derived lines) when ServiceDate is blank. Dropped the near-dead
   `Order.EndDate` middle layer (fired ~0.04%, semantically an order-header date at line level).
2. **From Date too.** Those same null-ServiceDate lines also have a null `Billing_Schedule_From_Date__c`
   (the branch set `From = ServiceDate` raw) — so they'd fail on "Billing **From** Date" (this ticket's
   other half). Anchored From on the same `Calculated_From_Date`.

**Deployed flow (v4, Active, apiVersion 67.0).** Non_Perpetual branch only; Perpetual branch byte-unchanged;
strictly additive (every line with a date today keeps its exact value):
```
Calculated_From_Date = IF(NOT(ISBLANK(ServiceDate)), ServiceDate, Order.EffectiveDate)
Calculated_To_Date   = IF(NOT(ISBLANK(EndDate)),     EndDate,
                          ADDMONTHS(IF(NOT(ISBLANK(ServiceDate)), ServiceDate, Order.EffectiveDate), 12) - 1)
Non_Perpetual_Set_Dates: From & Start_Date_Calculated__c -> Calculated_From_Date;
                         To   & End_Date_Calculated__c   -> Calculated_To_Date
```
Deploy IDs: v3 (To-only) `0AfWC00000GCZC50AP`; v4 (From+To) re-deploy. Source: `Data/sc3297/build/`.

**Verified on repro order 00095276 (801WC00000jm40zYAA):** after re-save, Line 2 (RC_42000)
`From = 2026-05-29 → To = 2027-05-28`, `End_Date_Calculated__c = 2027-05-28`; Line 1 (Perpetual)
unchanged (`From = To = 2026-05-29`). No regression.

**All 5 submission-surface lines verified** (re-saved to re-fire the flow):
- 00095276 L2 (RC_42000, ServiceDate set) → From 2026-05-29 / To 2027-05-28
- 00095272 (RC_42000, null ServiceDate) → From 2026-05-28 / To 2027-05-27
- 00095266 (RC_45005, null ServiceDate) → From 2026-05-26 / To 2027-05-25
- 00000100 ×2 (null-Rev DP Term-Based-Annual, null ServiceDate) → From 2025-10-16 / To 2026-10-15

**Workday round-trip CONFIRMED for repro 00095276.** Re-submitted via the supported path — publish the
`Order_Completed_WD__e` platform event with `Order_Id__c` = the order (this is exactly what the
`Fortra_Screen_Send_Order_to_Workday` button → `Fortra_Subflow_Order_Completed_Platform_Event` does;
neither rebuilds the stored payload, so the **middleware reads live order/line data** and upserts by
`contractReferenceId`/`fortraSfdcExternalId` = Order Id → idempotent). Result:
`Workday_Sync_Status__c = Success`, message *"Contract saved successfully"* (`id dea02b7aec441002168e611bb6670000`),
`Workday_Contract_ID__c` populated; the freshly-built payload now carries Line 2 `billingScheduleToDate = 2027-05-28`.
> Note: the stored `Workday_Sync_Payload__c` is a *log* and does **not** rebuild on a plain Order re-save
> (`Fortra_Order_Set_Workday_and_PO_Fields` only blanks/re-queues it); the live read on send is what matters.

**Open for business (non-blocking):** (a) the 4,287 "Legacy SKU - Other" null-Rev lines have *no real term*
anywhere — 12 mo is a defensible placeholder matching their Yearly cadence, but it's an assumption (none
are on the submission surface today); (b) whether genuinely "One Time" charges should bill across a
12-month window vs a single point (pre-existing ambiguity in the blessed RC_42000 case).

**Adjacent items — confirmed out of scope:** MyCap discrepancy (latent — `OrderItem.MYCAP__c` false on all
229k rows; `Order.MyCap__c` read only by the dead `Tk` formula), validation CMDT (redundant + UAT-only-no-prod),
force-app refresh (separate housekeeping retrieve of the flow + OrderItem fields).

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This file — root cause + resolution + working notes |

---
_Investigation 2026-06-01/02 against live FortraUAT + the `*Jira` docs + `FORTRA_KNOWLEDGE_BASE.md`. Treat
field/flow names as point-in-time; the live org is the source of truth._
