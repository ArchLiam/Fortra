# SC-3447 — The Decisive Workday Quantity Question (Completeness Critic C)

**Date:** 2026-06-27 · **Mode:** STRICTLY READ-ONLY · **Org:** FortraUAT (00DWC000006eUFF2A2)

## THE QUESTION

Does the Workday contract integration require **ONE CONTRACT LINE PER SEAT/UNIT**, or **ONE CONTRACT LINE WITH QUANTITY=N**?
This decides whether per-unit `OrderItem` splitting (`PowerOrderSplittingService`, qty-N → N qty-1 clones) is needed AT ALL. If Workday takes `quantity=N`, the heavy P2 async build collapses and **P3 ("don't explode seat lines") is the correct resolution**.

## VERDICT (HIGH CONFIDENCE)

**Workday takes ONE CONTRACT LINE WITH QUANTITY=N. Per-unit seat splitting is NOT required by Workday.**

A single `OrderItem` with `Quantity=7500` (unsplit) maps to **one** `contractLineData` entry carrying `"quantity": 7500`, `"unitCost": NetUnitPrice`, `"extendedAmount": NetUnitPrice × 7500`. Workday's API explicitly supports this, and the live Mule mapping already does `line.quantity = OrderItem.Quantity`. The seat-explosion split is therefore **not a Workday requirement** — in fact it actively *harms* the Workday integration (see SC-3210 below).

Confidence is HIGH on three independent legs (API spec + live captured payload + inferred Mule mapping). The **one residual unknown** (a captured payload with `quantity>1` proving the value flows through verbatim, vs. always-1) is addressable only by the Mule/Workday owners — framed below as the #1 confirmation item, but it does NOT change the verdict given the convergent evidence.

---

## EVIDENCE LEG 1 — Workday API spec: the contract line HAS a Quantity field

Source: `*Jira/sc3143(epic | integration)/workday-api-reference/Submit_Customer_Contract.md`
(Workday Revenue Management **v46.1**, deterministic HTML parse of community.workday.com, extracted 2026-06-01.)

`Customer_Contract_Line_Data` type (line 800+) carries genuine quantity/unit-price fields:

| Field (md line) | Type | Card. | Description |
|---|---|---|---|
| `Quantity` (833) | decimal (22,2) | [0..1] | **"Quantity for Contract Line"** |
| `Unit_Cost` (837) | decimal (26,6) | [0..1] | "Unit Cost for Contract Line" |
| `Extended_Amount` (838) | decimal (18,3) | [0..1] | "Extended Amount for Contract Line" |
| `Unit_of_Measure_Reference` (834) | UoM Object | [0..1] | Line Unit of Measure |
| `List_Unit_Price` (844) | decimal (21,6) | [0..1] | List Unit Price |
| `List_Extended_Amount` (845) | decimal (18,3) | [0..1] | List Extended Amount |
| `Fair_Value_Extended_Amount` (843) | decimal (18,3) | [0..1] | **"FV Extended Amount is FV Unit Price multiplied by the Quantity"** |

Workday's OWN model is `Extended = Unit Price × Quantity` (explicit in the FV field description, line 843). The line is a **quantity-bearing line**, not a per-unit atom.

**No per-unit / per-seat / serial-per-line constraint exists** anywhere in the 1,693-line spec. A `grep` for `per unit|per seat|one line per|each unit|serial|quantity must be 1` returned only address-descriptor false positives ("serialized attribute" = address override labels). A `Customer_Contract` "may have multiple lines and must have at least 1 line" (line 802) — multiplicity is by line *type/product*, never by unit count.

**The only contract-level invariant** (md line 180, header validation): *"The Contract Amount and the Contract Line Amount must be equal to Submit Contract."* This is `currentContractAmount == SUM(line extendedAmount)` — a header-vs-sum-of-lines reconciliation. One line with `extendedAmount = unitCost × N` satisfies it identically to N lines of `extendedAmount = unitCost × 1`. Splitting buys **nothing** here.

## EVIDENCE LEG 2 — A real captured payload: quantity field is populated, 1 line per OrderItem

Source: `*Jira/Task/sc3347 .../evidence/payloads.md` — Order **00095355** `Workday_Sync_Payload__c` (logged by Mule, full JSON):

```json
"contractLineData": [
  { "lineNumber": 1, "contractLineTypeID": "FIXED AMOUNT BILLING ONLY",
    "salesItemID": "GS-GSE-NRPS-AAMP", "quantity": 1, "unitCost": 3150, "extendedAmount": 3150, ... },
  { "lineNumber": 2, "contractLineTypeID": "FIXED AMOUNT BILLING ONLY",
    "salesItemID": "GS-GSE-NRPS-AAMP", "quantity": 1, "unitCost": 0,    "extendedAmount": 3150, ... }
]
```

Two facts proven directly:
1. **The payload carries a real `"quantity"` field on every contract line** — not an implicit/absent attribute.
2. **One `contractLineData` entry per OrderItem.** Verified live: `SELECT COUNT(Id) FROM OrderItem WHERE Order.OrderNumber='00095355'` = **2**, and the payload has exactly 2 lines (lineNumber 1, 2). The mapping is **1 OrderItem → 1 contract line**, NOT 1 unit → 1 line.

These OrderItems were `Quantity=1`, so the payload shows `quantity:1` — which is why this single sample can't by itself distinguish "maps `Quantity` verbatim" from "hardcodes 1." Leg 3 closes that.

## EVIDENCE LEG 3 — The Mule mapping: line.quantity = OrderItem.Quantity (inferred, strongly)

Source: `*Jira/Task/scXXXX | Discounted orders fail Workday sync .../README.md` (lines 84-93), the SC-3347/extendedAmount fix spec, corroborated by `project_workday_extendedamount_mapping` memory.

The reverse-engineered Mule contract-line builder:
```
line.unitCost       = OrderItem.NetUnitPrice
line.quantity       = OrderItem.Quantity          # ← quantity sourced from the OrderItem's Quantity
line.extendedAmount = OrderItem.NetTotalPrice     # == NetUnitPrice × Quantity (the SC-3347 fix target)
```
Per-line invariant Workday enforces: `extendedAmount == round(unitCost × quantity, 2)`; header: `SUM(extendedAmount) == currentContractAmount`.

If `quantity` were hardcoded to 1, the spec would not write `line.quantity = OrderItem.Quantity`, and `extendedAmount = NetTotalPrice` (= NetUnitPrice × Quantity) would be wrong for any qty>1 line. The whole extendedAmount-reconciliation model the integration team is debugging **presumes quantity is a live multiplier from `OrderItem.Quantity`.** A qty=7500 OrderItem → `quantity:7500, unitCost:NetUnitPrice, extendedAmount:NetUnitPrice×7500` → reconciles cleanly.

Architecture (memory `project_workday_resubmit_mechanism` + `project_workday_extendedamount_mapping`): `Order_Completed_WD__e` carries **only** `Order_Id__c`; **Mule reads live Order/OrderItem and builds the entire payload** (Order LastModifiedBy = `svc.mulesoft@fortra.com.uat`). Org-wide body search of ApexClass/Trigger/Flow/DataRaptor for `extendedAmount|contractLineData|Submit_Customer_Contract|Workday_Sync_Payload` = **0 hits** — no Salesforce component assembles the payload (re-confirmed this wave: only the per-line *classifier* flow exists locally, see below). So the split happening in Salesforce is **invisible to and unneeded by** the payload builder except that it changes the *count of OrderItems Mule iterates*.

## CROSS-REFERENCE — "per-line contract amount" = per-OrderItem, NOT per-unit

The three Workday-failure memories all describe **per-line** amounts:
- `project_sc3347_workday_sync_failure` / `project_workday_extendedamount_mapping` — "Contract Amount and Contract Line Revenue Amount must be equal." This is the header==SUM(lines) rule (Leg 1, md:180). Per-line = **per-`contractLineData` = per-OrderItem** (proven 1:1 in Leg 2). It is satisfied by a single quantity=N line. **Implies split NOT needed.**
- `project_sc3210_workday_linetype` — **the decisive corroboration.** The `Fortra_OrderItem_Set_Workday_Contract_Line_Type` flow (V10/V11) stamps `Workday_Contract_Line_Type__c` per OrderItem. For a **pure quantity split** (PowerOrderSplittingService sets `Original_Order_Item__c = original.Id` on every qty-1 clone, same Product2), V10's reverse-lookup mis-classifies the parent as a "subsplit parent" → stamps it `FIXED AMOUNT BILLING ONLY` (zero revenue) → `SUM(extendedAmount) ≠ currentContractAmount` → **Workday REJECTS**. Live repro: order **00095351** (3× perpetual, parent BILLING ONLY + 2 children FIXED AMOUNT, Failure, $11,025 billed ≠ $7,350 recognized).

  → The seat/qty explosion does **not enable** the Workday integration; it **breaks** it. Today, splitting qty into N OrderItems creates N contract lines that the line-type automation then mis-stamps, causing the exact "Contract Amount ≠ Contract Line Amount" failures SC-3210/SC-3368 exist to fix. **Not splitting** (one qty=N line) sidesteps the entire subsplit-conflation defect class.

## THE LIVE SALESFORCE LINE-TYPE FLOW (re-verified this wave)

`force-app/main/default/flows/Fortra_Autolaunched_Set_Workday_Contract_Line_Type.flow-meta.xml`: loops OrderItems and sets `Workday_Contract_Line_Type__c` to one of {FIXED AMOUNT, PREPAID (usage-based), …} based on product attributes. It does **NOT** read or write `Quantity` and does **NOT** split lines. Purely a per-OrderItem classifier. So nothing in the Salesforce automation requires per-unit lines.

Live OrderItem Workday fields (FortraUAT FieldDefinition): `Workday_Contract_Line_Reference_ID__c` (External ID — the **1:1** OrderItem↔contract-line write-back key), `Workday_Contract_Line_Type__c`, `Workday_Sync_Payload__c`, `Workday_Sync_Status__c`. The External ID being on OrderItem (one per OrderItem) re-confirms the **1 OrderItem ⇒ 1 contract line** design. (All currently null in UAT — Mule populates on real sync runs; UAT sync-status counts: ~28,804 Pending / 66 Success / 71 Failure per SC-3347.)

## DECISIVE ANSWER — would unsplit Quantity=7500 work?

**Yes — Workday would accept ONE contract line with `quantity:7500`.** Evidence chain:
1. API: `Customer_Contract_Line_Data.Quantity` decimal(22,2) [0..1] exists; `Extended = UnitPrice × Quantity`; no per-unit constraint (Leg 1).
2. Payload: every line already carries `"quantity"`; 1 OrderItem ⇒ 1 line (Leg 2, verified 2 OI → 2 lines on 00095355).
3. Mapping: `line.quantity = OrderItem.Quantity`, `line.extendedAmount = NetUnitPrice × Quantity` (Leg 3).
4. The contract-level rule `SUM(extendedAmount) == currentContractAmount` is satisfied identically by 1 line of N×unit or N lines of 1×unit (Leg 1, md:180).
5. Splitting *creates* Workday failures (SC-3210 subsplit conflation), it doesn't prevent them.

There is **no read-only evidence that Workday requires 7500 separate lines, and strong convergent evidence it does not.**

## RESIDUAL UNKNOWN → #1 question for Joe Romo + Workday/Mule owners

The Mule DataWeave is **not in this repo**; `line.quantity = OrderItem.Quantity` is *inferred* (from spec semantics + the qty=1 payloads + the extendedAmount=NetTotalPrice=NetUnitPrice×Qty fit). To make it 100% airtight:

> **For the Mule/Workday integration owners (Keith Irwin / Andy Kumar / Joe Romo):** Confirm against the `Submit_Customer_Contract` DataWeave (or an Anypoint log of a fresh resubmit on a qty>1 order) that the contract-line builder maps `line.quantity ← OrderItem.Quantity` verbatim (not hardcoded 1), and that Workday accepts a single contract line with a large quantity (e.g. 7500) with `extendedAmount = unitCost × quantity`. Are there ANY downstream Workday processes (billing schedule, MEA revenue allocation, fulfillment/provisioning, entitlement/asset-per-seat) that require one contract line **per seat**? If not, the Power seat-line explosion has no Workday justification and should be removed (SC-3447 resolution P3).

This is the single gating confirmation. Given Legs 1-3 converge, the working verdict is **quantity=N (no split needed)** and the P2 heavy async build should be treated as unnecessary pending that confirmation.

## IMPACT ON SC-3447 RESOLUTION CHOICE

- **If quantity=N (this verdict):** P3 ("don't explode seat lines; keep one qty-N OrderItem") is viable and Workday-correct. The convert-time CPU blowup (208 un-hoisted getDescribe()/clone × N clones + 2 record-triggered OI flows/clone) **disappears at the source** — O(line-count) instead of O(qty). The heavy P2 async-split build collapses. Bonus: it eliminates the SC-3210/SC-3368 subsplit-conflation Workday failures that the split itself causes.
- **If per-seat lines were truly required (NOT supported by evidence):** P2 async split would be needed, but the 10k-DML-rows-per-transaction hard ceiling (identical sync & async) would still block any order with a 100k–1M "unlimited" sentinel Power line (402 such QLIs exist) — so even then per-unit splitting is architecturally unviable for the sentinel population. Either way, per-unit explosion is the wrong design.

## CPU/limit framing for SC-3447

Per-convert cost of the split path is **O(qty/clone-count)**: each clone adds ~208 un-hoisted `Schema.getDescribe()` calls + 2 record-triggered OrderItem flows. CPU (not SOQL/DML) is the thrown limit. Removing the split makes it **O(line-count)** — independent of seat quantity. The P1 `Is_Split_Line__c=false` guard (if added to the OI flows) suppresses the per-clone flow re-fire but does NOT remove the per-clone getDescribe storm or the clone DML rows; only *not splitting* (P3) removes the quantity-proportional cost entirely. Since Workday accepts quantity=N, P3 is both the cheapest and the most Workday-correct fix.
