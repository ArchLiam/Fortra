# SC-3447 P1 — STAMP FIELDS + COPY-vs-DERIVE Decision (live, read-only)

Date: 2026-06-27 · Org: FortraUAT (00DWC000006eUFF2A2) · user liam.jeong.c@fortra.com.uat · API v67
Method: fresh `sf project retrieve start` of both live OrderItem flows + `sf sobject describe OrderItem` + Tooling FieldDefinition + read-only SOQL on live OrderItem data. No mutations.
Fresh retrieve artifact: `Data/sc3447/investigation_2026-06-27/P1_retrieve/flows/`

---

## TL;DR / VERDICT

**The flow-suppression is SAFE if the split Apex stamps the right things. The minimal-safe stamp is a HYBRID:**

- The **6 date/term fields** (Set_Dates output) — **COPY from parent is sufficient (no-regression).** Each is a pure function of the clone's own inputs (Order.EffectiveDate, ServiceDate, EndDate, SellingModelType), which are identical to the parent, so copy == re-derive. `createFullClone` already copies them. Current data: the 4 date-calc + 2 billing-schedule fields are **100% populated** on recent non-split Power lines; EndDate/PTC/ServiceDate are null only on **OneTime** lines, which is **correct** (no term), not a defect.
- **`Workday_Contract_Line_Type__c` — RE-DERIVE, do NOT blindly copy the parent.** Live data has **1 parent line carrying a STALE value** (stamped by an older flow version) that disagrees with its own product boolean; pure copy-from-parent would propagate that stale value to all its clones. Re-deriving from the product boolean (the V11 logic: `Is_Subsplit_Product__c` ? `FIXED AMOUNT BILLING ONLY` : `FIXED AMOUNT`) is what live V11 does and matches **34/34** recent non-split lines. Cheap: requires adding `Product2.Is_Subsplit_Product__c` (and `Product2.pse__IsServicesProduct__c` for the services guard) to the existing split query — **no extra SOQL**.

The "~36% null EndDate/PTC" prior figure is **confirmed as pre-existing and EXPECTED (OneTime product mix), not a SC-3447 regression** — do NOT block P1 on it. Closing it (if desired) is SC-3411/3420 scope.

**SC-3368 reverse-lookup risk: CONFIRMED ABSENT in live V11.** Subsplit is determined purely from the product boolean `$Record.Product2.Is_Subsplit_Product__c`. Zero references to `Original_Order_Item__c` / `Is_Split_Line__c` in either flow XML.

---

## 1. Complete set of fields each flow WRITES to $Record (the derived fields a suppressed clone would miss)

Re-verified active versions (FlowDefinitionView, `TriggerObjectOrEventLabel='Order Product'`): **Set_Dates V6 (`301WC00000knsJNYAY`)** and **Set_Workday V11 (`301WC00000kUYVFYA4`)** — both Active, both `CreateAndUpdate`. **No drift** vs known state. **Neither flow has a `<start>` entry filter** (the two `<filters>` blocks in V11 are inside `recordLookups`, not `<start>`).

### Fortra_OrderItem_Set_Dates (V6, RecordBeforeSave, 0 SOQL / 0 DML — in-memory $Record writes)

| # | Field written | When (path) | Source / formula |
|---|---|---|---|
| 1 | `Billing_Schedule_From_Date__c` | Non-perpetual: `Calculated_From_Date` (ServiceDate else Order.EffectiveDate). Perpetual (Rev_Category__c=RC_41000): Order.EffectiveDate | line-own inputs |
| 2 | `Billing_Schedule_To_Date__c` | Non-perpetual: `Calculated_To_Date` (EndDate else ServiceDate/EffectiveDate +12mo −1). Perpetual: Order.EffectiveDate | line-own inputs |
| 3 | `End_Date_Calculated__c` | = Calculated_To_Date (non-perp) / Order.EffectiveDate (perp) | line-own inputs |
| 4 | `Start_Date_Calculated__c` | = Calculated_From_Date (non-perp) / Order.EffectiveDate (perp) | line-own inputs |
| 5 | `EndDate` | **Backstop only** (`Termed_Needs_Dates`: SellingModelType=TermDefined AND (EndDate null OR PricingTermCount null)) → Calculated_To_Date | line-own inputs |
| 6 | `PricingTermCount` | **Backstop only**, same gate → `Std_PricingTermCount` = IF(blank,1,current)=1 (the SC-3411 backstop) | constant 1 |

**`ServiceDate` is READ (formula input) but NEVER WRITTEN by Set_Dates.** The prompt listed ServiceDate as an expected stamp; live V6 does not stamp it. (ServiceDate is populated upstream — see §3.)

### Fortra_OrderItem_Set_Workday_Contract_Line_Type (V11, RecordAfterSave, 1 SOQL Get_Product + 1 recordUpdate $Record → re-entrant re-fire of Set_Dates)

| # | Field written | Value | Branch condition |
|---|---|---|---|
| 7 | `Workday_Contract_Line_Type__c` | `PREPAID` | services (`Get_Product.pse__IsServicesProduct__c=true`) AND prepaid OrderItemAttribute |
| 7 | `Workday_Contract_Line_Type__c` | `USAGE BASED` | services AND not-prepaid |
| 7 | `Workday_Contract_Line_Type__c` | `FIXED AMOUNT BILLING ONLY` | non-services AND `$Record.Product2.Is_Subsplit_Product__c=true` |
| 7 | `Workday_Contract_Line_Type__c` | `FIXED AMOUNT` | non-services AND not-subsplit (the default for Power split children) |

**Total distinct fields the flows write = 7:** `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `End_Date_Calculated__c`, `Start_Date_Calculated__c`, `EndDate`, `PricingTermCount`, `Workday_Contract_Line_Type__c`.

---

## 2. Describe: existence, type, createable/updateable, read-only flags (OrderItem)

All 7 written fields + ServiceDate exist, are **non-formula / non-calculated / non-compound**, and are **BOTH createable AND updateable** → all are settable in Apex on a new clone via `put()`. **No read-only / formula / roll-up field among them → no special-handling field; nothing blocks Apex-stamping.**

| API Name | dataType | createable | updateable | calculated/formula | settable on clone |
|---|---|---|---|---|---|
| Billing_Schedule_From_Date__c | date | true | true | false | YES |
| Billing_Schedule_To_Date__c | date | true | true | false | YES |
| End_Date_Calculated__c | date | true | true | false | YES |
| Start_Date_Calculated__c | date | true | true | false | YES |
| EndDate | date (std) | true | true | false | YES |
| PricingTermCount | double Number(16,2) (std) | true | true | false | YES |
| Workday_Contract_Line_Type__c | picklist | true | true | false | YES |
| ServiceDate (input only) | date (std) | true | true | false | YES |

`Workday_Contract_Line_Type__c` active picklist values = exactly the 4 the flow stamps: `USAGE BASED`, `PREPAID`, `FIXED AMOUNT BILLING ONLY`, `FIXED AMOUNT`. Clone-customize fields also all createable/updateable: `Is_Split_Line__c` (boolean), `Original_Order_Item__c` (reference), `Quantity`, `Manual_Discount__c`, `Displaced_ARR__c`.

---

## 3. COPY-vs-DERIVE on CURRENT data

### 3a. Recent (last 14d) NON-split Power OrderItems — the would-be split originals (N=34)

| Field | NULL/0 | %null | Populated |
|---|---|---|---|
| Workday_Contract_Line_Type__c | 0 | **0.0%** | 34 |
| Billing_Schedule_From_Date__c | 0 | **0.0%** | 34 |
| Billing_Schedule_To_Date__c | 0 | **0.0%** | 34 |
| End_Date_Calculated__c | 0 | **0.0%** | 34 |
| Start_Date_Calculated__c | 0 | **0.0%** | 34 |
| EndDate | 16 | 47.1% | 18 |
| PricingTermCount | 16 | 47.1% | 18 |
| ServiceDate | 16 | 47.1% | 18 |

**The 16 EndDate/PTC/ServiceDate nulls are EXACTLY the 16 `OneTime` (FIXED AMOUNT) lines.** All 18 `TermDefined` lines have EndDate + PTC **100% populated** (backstop fires). OneTime lines legitimately have no term → null EndDate/PTC/ServiceDate is **correct, not a defect**.

### 3b. All-time split-line OrderItems (Is_Split_Line=true, N=66) — refreshed

| Field | NULL/0 | %null |
|---|---|---|
| Workday_Contract_Line_Type__c | 3 | 4.5% |
| Billing_Schedule_From_Date__c | 25 | 37.9% |
| Billing_Schedule_To_Date__c | 25 | 37.9% |
| End_Date_Calculated__c | 32 | 48.5% |
| Start_Date_Calculated__c | 32 | 48.5% |
| EndDate | 24 | 36.4% |
| PricingTermCount | 24 | 36.4% |
| ServiceDate | 24 | 36.4% |

Decomposition: **OneTime 22/22 (100%) null EndDate/PTC; TermDefined 0/42 (0%) null; +2 records with no SellingModel.** → the headline "~36% null EndDate/PTC" is **entirely the OneTime product mix**, identical in nature to non-split lines. CONFIRMED pre-existing & expected; not SC-3447's to fix.

### 3c. Date/term fields → COPY is sufficient (no-regression)

Each Set_Dates field is a deterministic function of the line's OWN inputs (`Order.EffectiveDate`, `ServiceDate`, `EndDate`, `ProductSellingModel.SellingModelType`, `Product2.Rev_Category__c`). A clone shares the parent's Order, Product2, SellingModel, and ServiceDate, so **copy(parent) == re-derive** for all 6. `createFullClone` already copies all createable fields from the flow-stamped parent. **Recommendation: trust the copy for the 6 date/term fields.** (Optional hardening: if the team wants to close the OneTime/null gap, that is SC-3411/3420 re-derive scope, NOT P1.)

### 3d. Workday_Contract_Line_Type__c → RE-DERIVE (copy is NOT always safe)

Child-vs-parent comparison across all 63 split children with a parent FK:
- child.Product2Id == parent.Product2Id: **63/63 (100%)**
- child.Is_Subsplit_Product__c == parent.Is_Subsplit_Product__c: **63/63 (100%)**
- child.WCLT == parent.WCLT: **52/63** — **11 mismatches.**

The 11 mismatches resolve into two patterns, both OLD data:
1. (9× 2026-05-05, 2× type-A) child stored `FIXED AMOUNT` but child Is_Subsplit=**true** → live V11 would derive `FIXED AMOUNT BILLING ONLY` = parent's value. Here copy-parent is actually MORE correct than the stale child.
2. (2× 2026-06-05, OQLFx/OQLFy) child stored `FIXED AMOUNT` (correct: Is_Subsplit=false), but **PARENT** stored `FIXED AMOUNT BILLING ONLY` while the parent's own `Is_Subsplit_Product__c=false`. The parent (OQLFw, 2026-06-05) is **STALE** — stamped by an older flow version that disagreed with the current product boolean. **Copying this parent verbatim would give the clone the WRONG `BILLING ONLY`.**

Decisive check: on the **34 recent non-split Power lines, stored WCLT == product-boolean-derive (V11 logic) for 34/34 (0 mismatch).** So re-derive is reliable on current data; copy-from-parent carries a (small but real) stale-parent risk.

→ **Recommendation: re-derive WCLT in the clone stamp using the V11 rule** (services→PREPAID/USAGE; else `Is_Subsplit_Product__c` ? BILLING ONLY : FIXED AMOUNT). Cost = add `Product2.Is_Subsplit_Product__c` + `Product2.pse__IsServicesProduct__c` to `queryOrderItemsToSplit` (relationship columns, **no extra SOQL**). For the services branch (PREPAID vs USAGE needs an OrderItemAttribute lookup), copy-from-parent is the safe fallback — but **all P3-eligible Power lines are non-services (svc=false), so the services branch is never hit on genuine per-machine splits** (45 services Power qty>1 lines exist org-wide, but NONE have a Partition/Hardware, so none are P3-eligible).

---

## 4. Line-type safety (SC-3368) — RE-CONFIRMED on live V11

- Live V11 derives `Workday_Contract_Line_Type__c` from **`$Record.Product2.Is_Subsplit_Product__c`** (product-level boolean; cross-object on $Record, NO SOQL) for the non-services path, and `Get_Product.pse__IsServicesProduct__c` for the services gate.
- **NO `Original_Order_Item__c` reverse-lookup anywhere in V11** (grep of fresh XML = 0 hits for `Original_Order_Item` and `Is_Split_Line`). The SC-3368 "reverse-lookup mis-stamps qty-split parents" risk described in older docs is **NOT present in live V11** (that was a V10-era version). Down-ranked to "re-verify V11 is still product-boolean at build" (daily churn).
- Because a clone has the SAME Product2 as its parent, the clone's `Is_Subsplit_Product__c` and `pse__IsServicesProduct__c` are identical → the V11 result on a clone == the V11 result on the parent. **So re-derive-on-clone == what the flow would stamp**, and the ONLY way copy-from-parent diverges is when the PARENT itself holds a stale pre-V11 value (the OQLFw case). Re-derive eliminates even that edge.

---

## 5. Where to stamp (implementation pointer, for the build task — NOT done here)

`PowerOrderSplittingService.cls` clone-customize block (L188-201) already sets `Quantity=1`, `Manual_Discount__c`, `Displaced_ARR__c`, `Is_Split_Line__c=true`, `Original_Order_Item__c`. P1 (if flows suppressed) adds here:
- (date/term ×6) — already present via `createFullClone` copy; no new code needed (copy=no-regression).
- `splitItem.Workday_Contract_Line_Type__c = deriveLineType(original.Product2)` — re-derive from product booleans (requires the 2 added query columns in §3d).

P1#1 describe-hoist targets (separate from stamping): `createFullClone` L407-409 calls `getDescribe()/isCreateable()` **per field per clone** (the real ×N amplifier → hoist to a static createable-field-name list); `queryOrderItemsToSplit` L368-373 does `getDescribe()/isAccessible()` per field but only **once per invocation** (smaller win, still cacheable).

---

## Queries / artifacts (all read-only)
- FlowDefinitionView active-version re-verify (Set_Dates V6 / Set_Workday V11, no drift).
- Fresh retrieve of both flow XMLs → `P1_retrieve/flows/`.
- `sf sobject describe OrderItem` + Tooling FieldDefinition for the 7+ServiceDate.
- OrderItem WHERE Solution_Group='Power' non-split CreatedDate=LAST_N_DAYS:14 (N=34) — null/selling-model analysis.
- OrderItem WHERE Is_Split_Line=true (N=66) — refreshed null fractions + selling-model decomposition.
- Child-vs-parent WCLT/Product2/Is_Subsplit comparison (N=63) — 11 WCLT mismatches diagnosed.
- Recent non-split WCLT vs product-boolean-derive (34/34 match).
- P3-eligible Power lines services-product check (all svc=false).
