# SC-3211 — Diagnosis

**Date:** 2026-05-29
**Org inspected:** `FortraUAT` (liam.jeong.c@fortra.com.uat). `fortradp2` was excluded per user direction in-session.
**Source of truth for current state:** Flow XML retrieved from FortraUAT (`force-app/.../Fortra_OrderItem_Set_Dates.flow-meta.xml`, v66, retrieved 2026-05-29).

---

## 1 · Flow version state

| Version | Status   | Process Type     |
|---------|----------|------------------|
| 2       | Active   | AutoLaunchedFlow |
| 1       | Obsolete | AutoLaunchedFlow |

Exactly one Active version — §7.5 does not fire. Trigger: `RecordBeforeSave` on `OrderItem` (CreateAndUpdate). Active before any change is v2.

---

## 2 · Other automation on the four target fields (§7.3 check)

Active record-triggered flows on OrderItem in UAT:

| API name | Trigger | Writes any of the 4 target fields? |
|---|---|---|
| `Fortra_OrderItem_Set_Dates` | BeforeSave | yes — the flow under fix |
| `Fortra_OrderItem_Set_Workday_Contract_Line_Type` | AfterSave | **no** (XML grep on the 4 field names returns zero hits) |
| `Order_Product_Disallow_delete_for_Globalscape_Integration_User` | BeforeDelete | **no** (delete-only) |

Active OrderItem Apex triggers in UAT: **none** (queried `ApexTrigger WHERE TableEnumOrId='OrderItem' AND Status='Active'`).

Conclusion: §7.3 does not fire. `Fortra_OrderItem_Set_Dates` is the sole writer of the four fields.

---

## 3 · Field existence (§7.4 check)

| Object     | Field           | Type     |
|------------|-----------------|----------|
| OrderItem  | `MYCAP__c`      | Checkbox |
| Order      | `MyCap__c`      | Checkbox |
| Quote      | `Mycap__c`      | Checkbox |
| Quote      | `MYCAP_Approval__c` | Checkbox |

`Order.MyCap__c` exists — §7.4 does not fire. Note the three-way casing variance (`MYCAP__c` / `MyCap__c` / `Mycap__c`) is itself a latent footgun for any future SOQL or formula author; flagged for the ticket follow-up list but not in this fix's scope.

---

## 4 · Pre-fix state of `Fortra_OrderItem_Set_Dates` (v2)

### 4.1 Decision element `Perpetual` (condition logic `1 OR 2 OR 3 OR 4 OR 5 OR (6 AND 7)`)

| # | Condition (as deployed) | Spec (§1.1) | Status |
|---|---|---|---|
| 1 | `$Record.Product2.Rev_Category__c = "RC_41000"` | same | OK |
| 2 | `$Record.Product2.Rev_Category__c = "RC_45000"` | same | OK |
| 3 | `$Record.Product2.Rev_Category__c = "RC_45001"` | same | OK |
| 4 | `$Record.Product2.Rev_Category__c = "RC_45002"` | same | OK |
| 5 | **`$Record.MYCAP__c = true`** (OrderItem field) | `$Record.Order.MyCap__c = true` (Order field) | **DEFECT** |
| 6 | `$Record.Product2.Product_Selling_Model_Type__c = "One Time"` | same | OK |
| 7 | `$Record.Product2.Family = "Perpetual"` | same | OK |

Defect: condition #5 evaluates `OrderItem.MYCAP__c`, but the field that is actually populated by the Quote → Order propagation is `Order.MyCap__c`. Open Question #1 in the ticket resolves explicitly to use `Order.MyCap__c`.

### 4.2 `recordUpdates` node `Perpetual_Set_Dates`

| Field | Value as deployed | Spec (§1.2) | Status |
|---|---|---|---|
| `Billing_Schedule_From_Date__c` | `$Record.Order.EffectiveDate` | `$Record.Order.EffectiveDate` | OK |
| `Billing_Schedule_To_Date__c` | `$Record.Order.EffectiveDate` | `$Record.Order.EffectiveDate` | OK |
| `Start_Date_Calculated__c` | **`$Record.ServiceDate`** | **`null`** | **DEFECT** |
| `End_Date_Calculated__c` | **`$Record.EndDate`** | **`null`** | **DEFECT** |

The deployed Perpetual branch matches the ticket's defective Build Instructions verbatim — exactly the spec-vs-Build-Instructions divergence flagged in handoff §3. Spec wins (Requirements + AC + HLD + Notes all agree on `null`).

### 4.3 `recordUpdates` node `Non_Perpetual_Set_Dates`

| Field | Value as deployed | Spec (§1.2) | Status |
|---|---|---|---|
| `Billing_Schedule_From_Date__c` | `$Record.ServiceDate` | `$Record.ServiceDate` | OK |
| `Billing_Schedule_To_Date__c` | `$Record.EndDate` | `$Record.EndDate` | OK |
| `Start_Date_Calculated__c` | `$Record.ServiceDate` | `$Record.ServiceDate` | OK |
| `End_Date_Calculated__c` | `$Record.EndDate` | `$Record.EndDate` | OK |

Matches spec exactly. §7.2 does not fire — non-qualifying branch is correct, will not be touched.

### 4.4 Inactive / dead artifacts

A `<formulas>` element named `Tk` (Date) exists in the XML but is not referenced by any element. It uses `$Record.Order.MyCap__c` — i.e. the *correct* MyCap path — suggesting the decision element was written with the wrong reference even though a co-author knew the right one. Not removing it (out of scope), but flagging for future cleanup.

---

## 5 · Net summary of pre-fix defects in scope

1. **Defect A — decision condition #5 MyCap reference.** Currently `$Record.MYCAP__c`; must be `$Record.Order.MyCap__c`.
2. **Defect B — Perpetual_Set_Dates `Start_Date_Calculated__c`.** Currently `$Record.ServiceDate`; must be `null`.
3. **Defect C — Perpetual_Set_Dates `End_Date_Calculated__c`.** Currently `$Record.EndDate`; must be `null`.

All three are corrected in one new Flow version. No other automation is added.

---

## 6 · Order 95272 (handoff symptom reproduction)

| OrderItemNumber | Family | RC | PSM | Order.MyCap | OrderItem.MYCAP | ServiceDate | EndDate | Bill From | Bill To | Start Calc | End Calc |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0000563953 | New Maintenance | RC_42000 | One Time | false | false | null | null | null | null | null | null |
| 0000563954 | Perpetual | RC_41000 | One Time | false | false | null | null | 2026-05-28 | 2026-05-28 | null | null |

Order.EffectiveDate = 2026-05-28.

- Item 563954 qualifies via condition #1 (RC_41000). Perpetual branch fires → From/To = `Order.EffectiveDate`. Start/End Calc happen to land at `null` only because `ServiceDate`/`EndDate` themselves are null on this record — not because the flow writes `null` intentionally. Under the spec, Start/End Calc must be `null` regardless of `ServiceDate`/`EndDate`; on this single record the bug is masked.
- Item 563953 does not qualify (RC_42000 not in qualifying set; Family=New Maintenance). Non-Perpetual branch fires → From=ServiceDate=null, To=EndDate=null. Workday would reject this one too, but for a different reason (missing source data on the OrderItem itself, not a flow-write bug). Out of scope.

Note: the handoff describes the failing item as "EFT8 suffix, Family=Perpetual, From/To empty." On the current snapshot of 95272, the Perpetual item's From/To are populated (2026-05-28). Either the data was repaired after the handoff was authored or the suffix mapping in the handoff was approximate. Recording for transparency; the spec defects remain valid and load-bearing.

---

## 7 · Wider-data evidence of the live defect

Sample qualifying OrderItems with non-null `ServiceDate` (where Defect B would visibly surface as `Start_Date_Calculated__c = ServiceDate` instead of `null`):

| OrderItemNumber | RC | ServiceDate | EndDate | Bill From | Start Calc | End Calc |
|---|---|---|---|---|---|---|
| 0000370091 | RC_41000 | 2026-04-02 | null | null | null | null |
| 0000372424 | RC_41000 | 2026-03-02 | null | null | null | null |

Bill-from is null on these older records, which indicates they predate the v2 flow's activation (the flow only runs on save). They are not useful as pre-fix evidence by inspection alone — re-save under v2 would be required to observe the deployed write behavior, and re-saving qualifying records before deploying the fix would be wasted work (we would just have to re-touch them post-deploy anyway). Post-deploy validation uses a deliberate save-touch on hand-picked records — see `validation_results.md`.

The spec defects are confirmed by the XML itself (§4.2 above); the data-driven confirmation is being deferred to the post-fix validation step where it makes a useful before/after delta.

---

## 8 · Quote → Order MyCap propagation spot-check (§7.8)

| Order# | Order.MyCap | Quote.Mycap |
|---|---|---|
| 00014757 | true  | true  |
| 00095212 | true  | true  |
| 00095215 | true  | true  |
| 00095270 | true  | true  |
| 00095271 | false | false |
| 00095272 | false | false |
| 00095274 | false | false |
| 00095275 | false | false |
| 00095276 | false | false |

All 4 MyCap=true orders match their source Quote; all 5 MyCap=false orders match. No mismatches in the sampled set. Propagation Quote → Order appears to be wired and functional. Not authoring or modifying the propagation logic per §9.1.

Note: Quote field is `Mycap__c` (only the leading M capitalised) — a third casing on top of `OrderItem.MYCAP__c` and `Order.MyCap__c`. Working as a latent gotcha but not in scope here.

---

## 9 · One-Time product classification mismatch (§9.5 spot-check)

OrderItem 0000563953 (`Family = "New Maintenance"`, `PSM Type = "One Time"`, `Rev_Category = "RC_42000"`) is functionally a one-time line per the PSM tag but does not qualify for the Perpetual branch because:
- `RC_42000` is not in the qualifying Rev_Category set
- `Family = "New Maintenance"` ≠ `"Perpetual"`, so condition 6+7 misses.

So a product that is "one-time" by PSM type can still fall through to the Non-Perpetual branch. If Workday's contract requires perpetual-branch dates for *all* one-time billing semantics, this is a real gap — but the gap lives in the Product2 tagging / qualifying-conditions design, not in the recordUpdates wiring. Flagged here and in the ticket comment as a separate defect; not fixed in this ticket.

---

## 10 · §7 stop-condition summary

| §7.x | Condition | Fires? | Why not |
|---|---|---|---|
| 7.1 | Flow already spec-correct AND MyCap on OrderItem | **No** | Flow is NOT spec-correct (Defects B and C); proceed with fix including MyCap reference change |
| 7.2 | Non-qualifying branch deviates from §1.2 | **No** | Matches spec exactly |
| 7.3 | >1 active flow writes the 4 fields | **No** | Only this flow writes them |
| 7.4 | `Order.MyCap__c` missing | **No** | Exists |
| 7.5 | >1 active version | **No** | One Active (v2), one Obsolete (v1) |
| 7.6 | AC#5 Billing Schedule pathway unclear | partially | RCA managed `BillingSchedule` — see `validation_results.md` |
| 7.7 | Deploy to UAT | **Overridden** | User explicitly directed UAT-only this session ("forget about dp2 focus on uat") |
| 7.8 | MyCap propagation unclear | **No** | Spot-checked — propagating correctly in sampled records |

Proceeding to fix.
