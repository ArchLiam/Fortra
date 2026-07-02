# SC-3211 — Validation Plan & Results

**Date:** 2026-05-29
**Status:** **DEFERRED — fix not deployed.** This file documents the pre-fix observed state and the validation plan to be executed once the v3 deploy is authorized.

---

## 1 · Why deferred

Per in-session user direction ("do not make change to the UAT yet nothing"), the edited Flow XML has not been deployed to FortraUAT. Live AC validation requires re-saving sample OrderItems against the new flow version; without a deploy that cannot happen. The plan below is structured so it can be run end-to-end by an operator (or by a follow-up Claude Code session) once deploy is authorized.

---

## 2 · Validation method (when authorized)

Touch-update existing OrderItems to force the Before-Save flow to re-fire, then re-query the four fields. Three categories of fixture per AC, plus one non-qualifying control.

Update vehicle: a no-op field touch via SOQL → DML. A safe choice is to set a benign updatable field to its current value (Salesforce treats this as a save event, firing Before-Save flows). Example with Description__c-equivalent field if present; otherwise re-set Quantity to its current value.

```bash
# template — DO NOT run until deploy is authorized
sf data update record \
    --target-org FortraUAT \
    --sobject OrderItem \
    --record-id <Id> \
    --values "Quantity=<currentValue>"
```

Then immediately re-query:

```bash
sf data query --target-org FortraUAT -q "
    SELECT Id, OrderItemNumber, ServiceDate, EndDate,
           Billing_Schedule_From_Date__c, Billing_Schedule_To_Date__c,
           Start_Date_Calculated__c, End_Date_Calculated__c,
           Order.EffectiveDate, Order.MyCap__c, MYCAP__c,
           Product2.Family, Product2.Rev_Category__c,
           Product2.Product_Selling_Model_Type__c
    FROM OrderItem WHERE Id='<Id>'"
```

---

## 3 · Per-AC fixtures, expected outcome, and pre-fix observed state

### AC #1 — Rev_Category in qualifying set

Sample fixtures with non-null `ServiceDate` (to make Defect B observable on data):

| OrderItem Id | OrderItemNumber | Rev_Category | ServiceDate | EndDate | Order.EffectiveDate |
|---|---|---|---|---|---|
| 802WC00000N0dioYAB | 0000370091 | RC_41000 | 2026-04-02 | null | 2024-02-02 |
| 802WC00000N0gIqYAJ | 0000372424 | RC_41000 | 2026-03-02 | null | 2025-09-02 |

**Expected after v3 fix + touch-save:**
- `Billing_Schedule_From_Date__c` = Order.EffectiveDate
- `Billing_Schedule_To_Date__c` = Order.EffectiveDate
- `Start_Date_Calculated__c` = null
- `End_Date_Calculated__c` = null

**Pre-fix observed (2026-05-29):** All four fields are null on both fixtures (records pre-date the v2 flow activation; they need a re-save to register either v2 or v3 behavior). Cannot draw an AC conclusion without a touch-update; planned.

### AC #2 — Order.MyCap__c = true

Sample fixtures:

| OrderItem Id | OrderItemNumber | Order.MyCap | OrderItem.MYCAP | Rev_Category | Family | PSM |
|---|---|---|---|---|---|---|
| 802WC00000NDKRwYAP | 0000563869 | true | false | RC_45000 | Services | One Time |
| 802WC00000NG3EcYAL | 0000563872 | true | false | RC_41204 | Subscription | Term Based - Annual |
| 802WC00000NG3EdYAL | 0000563873 | true | false | RC_41204 | Subscription | Term Based - Annual |

**Expected after v3 fix + touch-save:** All three should qualify (condition #5 now reads `Order.MyCap__c = true`), so:
- `Billing_Schedule_From_Date__c` = Order.EffectiveDate
- `Billing_Schedule_To_Date__c` = Order.EffectiveDate
- `Start_Date_Calculated__c` = null
- `End_Date_Calculated__c` = null

**Pre-fix observed (2026-05-29):**
| OrderItemNumber | Bill From | Bill To | Start Calc | End Calc | Inferred branch at last save |
|---|---|---|---|---|---|
| 0000563869 | 2026-05-29 (=ServiceDate, NOT Order.Effective=2026-05-11) | 2026-05-29 | null | null | Inconclusive — From matches ServiceDate which would mean Non-Perpetual, but To = From here, not EndDate(null) — possibly v1 era |
| 0000563872 | 2026-04-16 | 2026-04-16 | null | null | Looks like Perpetual fired (To = From = Order.EffectiveDate=2026-04-16); but condition #5 reads OrderItem.MYCAP__c (false on this record) and conditions 1–4, 6, 7 don't match RC_41204+Subscription+Term-Annual — so this must reflect either v1 logic or an unrelated write |
| 0000563873 | 2026-04-16 | 2026-04-16 | null | null | Same as 563872 |

The pre-fix state on AC #2 fixtures is contaminated by history — these records were saved under v1 (Obsolete) or in a sequence we can't reconstruct. This is *expected* for record-triggered flows: the "current" field values reflect whatever logic ran at last save, not the current flow code. A post-fix touch-update will produce a definitive AC #2 result.

### AC #3 — Family=Perpetual AND PSM=One Time (and *not* RC_4100x)

Query attempted: `Product2.Family='Perpetual' AND Product2.Product_Selling_Model_Type__c='One Time' AND ServiceDate!=null AND Product2.Rev_Category__c NOT IN ('RC_41000','RC_45000','RC_45001','RC_45002')`

**Result:** 0 records. In FortraUAT the Family=Perpetual + PSM=One Time set overlaps entirely with Rev_Category in the qualifying RC list. Pragmatically AC #3 is exercised by the same records as AC #1 — the (6 AND 7) compound rule is redundant relative to rule #1 for the current product catalogue. This is not a defect; just a data-shape observation. AC #3 is logically equivalent to AC #1 on the current catalogue.

If isolated AC #3 evidence is required, the only path is creating a synthetic Product2 with Family=Perpetual + PSM=One Time + Rev_Category outside the qualifying set, attaching it to a fresh OrderItem, and observing the four fields. That is catalog mutation — explicitly forbidden by handoff §11 ("Do not modify Product2, PricebookEntry, or any catalog data while staging validation fixtures"). Therefore AC #3 is validated *by inference* through AC #1, not by an independent fixture.

### AC #4 — None of the qualifying conditions

Candidate fixture (needs to be re-checked at validation time):

| OrderItem Id | OrderItemNumber | Order.MyCap | Rev_Category | Family | PSM | ServiceDate | EndDate |
|---|---|---|---|---|---|---|---|
| 802WC00000O3bLNYAZ | 0000563953 | false | RC_42000 | New Maintenance | One Time | null | null |

This record is non-qualifying on every condition, but it has null ServiceDate/EndDate — so Non-Perpetual would write four nulls and that doesn't prove Non-Perpetual fired (it just proves nothing visibly broke). A better AC #4 fixture is one with non-null ServiceDate AND non-null EndDate AND non-qualifying Family/RC/MyCap/PSM. The query to find one:

```sql
SELECT Id, OrderItemNumber, ServiceDate, EndDate,
       Billing_Schedule_From_Date__c, Billing_Schedule_To_Date__c,
       Start_Date_Calculated__c, End_Date_Calculated__c,
       Order.EffectiveDate, Order.MyCap__c, Product2.Family,
       Product2.Rev_Category__c, Product2.Product_Selling_Model_Type__c
FROM OrderItem
WHERE Order.MyCap__c=false
  AND (Product2.Rev_Category__c=null OR Product2.Rev_Category__c NOT IN ('RC_41000','RC_45000','RC_45001','RC_45002'))
  AND NOT (Product2.Family='Perpetual' AND Product2.Product_Selling_Model_Type__c='One Time')
  AND ServiceDate != null AND EndDate != null
LIMIT 3
```

(Not executed pre-fix — the goal is to use this exact query at validation time, then touch-update the result rows.)

**Expected after v3 fix + touch-save:**
- `Billing_Schedule_From_Date__c` = ServiceDate
- `Billing_Schedule_To_Date__c` = EndDate
- `Start_Date_Calculated__c` = ServiceDate
- `End_Date_Calculated__c` = EndDate

### AC #5 — Billing Schedule can be created without missing-date errors

Per §6 in the handoff: "If the pathway is non-obvious from inspection, do not fabricate one — record the gap in validation_results.md and proceed."

**Gap recorded.** `BillingSchedule` is a standard RCA-managed SObject (confirmed by EntityDefinition lookup). RCA's billing engine creates BillingSchedule records as part of the Order activation / billing-cycle generation pipeline — that pipeline is not a custom flow on OrderItem we can directly trace from the metadata in scope. In FortraUAT no obvious `Trigger / Flow / OmniScript` artifact named for Billing Schedule creation surfaces under a generic name search.

**Recommended AC #5 validation path (deferred to deploy operator or to a follow-up session):**

1. Pick a fully-formed qualifying OrderItem after the v3 fix is applied (i.e., one where all four target fields are populated per §1.2).
2. Use Setup → Subscription Management → Billing Schedule Generation (or whatever the UAT-specific operator runs to invoke the RCA billing engine on the OrderItem's parent Order).
3. Confirm `BillingSchedule` records appear under that Order with no "missing date" error.

If the in-house RCA setup wraps billing-schedule creation behind a specific button / Lightning action / scheduled job, the team who owns that path should run the test. Claude Code lacks reliable visibility into which path is "the" path here.

### AC #6 — No regression on non-qualifying branch

Validation: re-run the AC #4 query above on the *exact same fixtures* used pre-fix (capture IDs and pre-fix field values into a control set before deploy), touch-update after deploy, compare. Expectation: zero deltas in the four target fields between pre-fix and post-fix on the non-qualifying records.

### AC #7 — Single-flow delivery

Verified by static inspection — no new flow / trigger / process was authored. The only file in the deploy is `Fortra_OrderItem_Set_Dates.flow-meta.xml`. No new automation. See `change_summary.md §1, §4`.

---

## 4 · Anomalies / data issues surfaced during diagnosis

1. **Three-way casing of MyCap field across objects** — `OrderItem.MYCAP__c`, `Order.MyCap__c`, `Quote.Mycap__c`. Real footgun for SOQL writers and formula authors. Not in scope to fix here, but recommended for follow-up cleanup ticket.
2. **`Tk` formula is dead code** — declared but never referenced. Uses the *correct* `$Record.Order.MyCap__c` path, which is evidence the original author intended the corrected reference. Out-of-scope cleanup candidate.
3. **OrderItem MYCAP__c field exists at all** — given the spec puts MyCap at Order level, the OrderItem checkbox is potentially confusing/redundant. Worth a separate look (is it propagated somewhere? Is anything writing to it?). Out of scope.
4. **One-time PSM products with non-Perpetual Family** — OrderItem 0000563953 (`RC_42000`, `Family = New Maintenance`, `PSM = One Time`) is functionally a one-time line but skips the Perpetual branch. If Workday treats *all* one-time lines as needing perpetual-branch dates, this is a separate defect in the product-tagging or condition-set design (handoff §9.5). Recorded as a follow-up; out of scope for SC-3211.
5. **Catalog-shape redundancy** — Family=Perpetual + PSM=One Time always co-occurs with `Rev_Category` in the qualifying RC list in current data. The (6 AND 7) compound rule has no records it uniquely qualifies. Not a bug, but worth a product-team conversation about whether the compound rule is still load-bearing.

---

## 5 · Per-AC pre-deploy status table

| AC | Status pre-deploy | Plan to verify post-deploy |
|---|---|---|
| #1 | Cannot conclude — pre-fix records have null From/To showing they predate v2; need touch-save | Touch-save 2 fixtures listed under §3 AC #1, expect From=To=Order.EffectiveDate, Start/End Calc = null |
| #2 | Pre-fix records contaminated by history; bug present in deployed XML for sure | Touch-save 3 fixtures listed under §3 AC #2 |
| #3 | No isolated fixture available (catalog overlap with AC #1) | Inferred from AC #1 result; do not create synthetic catalog data |
| #4 | Need a clean fixture (see §3 AC #4 SOQL) | Run query, touch-save 3 fixtures, expect Non-Perpetual mapping |
| #5 | Gap — RCA pathway not directly traceable from this Flow | Defer to RCA-aware operator; recommended path documented |
| #6 | Same fixtures as AC #4; capture pre/post deltas | Compare pre-fix and post-fix snapshots |
| #7 | **Pass** by static inspection — only one Flow XML edited; no new automation | n/a |
