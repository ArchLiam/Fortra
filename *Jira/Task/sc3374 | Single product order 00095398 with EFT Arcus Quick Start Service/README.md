# SC-3374 — Single product order 00095398 (EFT Arcus Quick Start Service, "no discount") fails to generate Workday contract

> 🗺️ Part of the **[Pricing-V9 incident cluster](../_CLUSTER%20pricing-v9%20%28sc3371%20sc3372%20sc3374%29/ROADMAP.md)** (SC-3371 · SC-3372 · SC-3374) — see the shared ROADMAP for sequencing, ownership, and the open decisions (D4/D5) for this fix.

> Space: Salesforce-Coastal · Type: Task · Sprint: CRM Sprint 14 · Priority: 🔴 Critical
> Reporter: Joe Romo · Assignee: Liam Jeong · Labels: CRM-Revenue-Cloud, LOB-Salesforce-1-UAT
> Status: **RCA complete (FortraUAT, 2026-06-09).** Sync blocker is the **scXXXX / SC-3347 MuleSoft mapping defect** (one Mule change closes it). Upstream pricing is a **separate** RLM ticket.

## TL;DR

The Workday failure is the **same MuleSoft mapping defect already tracked in scXXXX / SC-3347**: the contract-line `extendedAmount` is sourced from `OrderItem.TotalLineAmount` (the **list** channel = 1540) while the header `currentContractAmount` and `unitCost` are **net** (`NetTotalPrice` = 2400). The two values differ by 860 → Workday rejects with *"Contract Amount and Contract Line Amount must be equal."*

It is **not** a discount. The 1540 is **Italy regional services pricing** (account PAGANI SPA, BillingCountry Italy): `CEILING(2400 × 0.64 / 5) × 5 = 1540`, which lands **only on the list channel**; the net channel stays at the catalog list 2400. So the order shows "no discount" in the UI (net == catalog list) while the underlying list/net split is what trips the Mule bug.

**One MuleSoft change (`extendedAmount ← OrderItem.NetTotalPrice`) unblocks the sync; the order is then cleanly resubmittable** (`Workday_ID__c` is null).

## Live evidence (FortraUAT, 2026-06-09)

**Order 00095398** = `801WC00000kQn0zYAC` — `TotalAmount` 2400, `Status` Order Complete, `Workday_Sync_Status__c` **Failure**, `Workday_ID__c` **null** (resubmittable), Pricebook `01sWC0000022GHFYA2` (Fortra Price Book).
Error: `The Contract Amount and the Contract Line Amount must be equal to Submit Contract.,Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.`

**One OrderItem** `802WC00000OZKPRYA5` — *EFT Arcus Quick Start Service* (`GS-GSE-NRST-EAQS`, One Time), `Original_Order_Item__c` null (**not** a SF subsplit):

| Channel | Field | Value |
|---|---|---|
| catalog | `ListPrice` | 2400 |
| **list/gross** | `UnitPrice` / `TotalLineAmount` | **1540** ← Mule puts this in `extendedAmount` |
| **net** | `NetUnitPrice` / `NetTotalPrice` | **2400** ← `unitCost` + header `currentContractAmount` |
| adj | `TotalAdjustmentAmount` | **+860** (positive; 1540 + 860 = 2400) |
| regional | `RegionalNetUnitPrice__c` / `AllowRegionalPricing__c` | **1540** / **true** |
| line type | `Workday_Contract_Line_Type__c` | PREPAID |

Source Quote `0Q0WC0000036wUD0AY` ("Q-Automation Test-2026-06-09", Joe Romo, Accepted). **QuoteLineItem `0QLWC000003c9294AA` already carries the identical split** (UnitPrice 1540 / NetUnitPrice 2400 / `TotalAdjustmentAmount` +860, **0** `QuoteLinePriceAdjustment` rows) — the anomaly originates at the **Quote**, before conversion; it is procedure-computed, not a manual override. **No PBE equals 1540** (SKU PBE set = {1896, 2208, 2400, 3240, 3648}).

Logged `Workday_Sync_Payload__c`: header `currentContractAmount` 2400; **two** contract lines built by Mule from the one OrderItem — L1 `PREPAID`/`Yearly_Billing_Template` billing line (blank `quantity`/`unitCost`), L2 `Usage Based`/`As Delivered` revenue line (`unitCost` 2400, **`extendedAmount` 1540**). The revenue line is the one that mismatches.

## Mechanism (two stages, both verified)

**Stage 1 — upstream pricing produces net ≠ list (Defect B, RLM).** PAGANI SPA is Italy. Live Apex prehook `RegionalServicesPricingPrehook` (v12.2) reads the Italy `0.64` multiplier from `Services_Regional_Pricing__mdt`, computes `CEILING(2400 × 0.64 / 5) × 5 = 1540`, and writes it **only** to `RegionalNetUnitPrice__c`. The Active V9 pricing-procedure step `RegionalServicesPrice27` (gated on `AllowRegionalPricing__c = true`) assigns `RegionalNetUnitPrice__c → InputUnitPrice`, so the **list** channel becomes 1540. The **net** channel is never regionalized → stays at catalog 2400. Result: `NetTotalPrice` 2400 > `TotalLineAmount` 1540, `TotalAdjustmentAmount` +860.

**Stage 2 — MuleSoft mis-maps the contract line (Defect A, the blocker).** The platform event `Order_Completed_WD__e` carries only `Order_Id__c`; MuleSoft queries SF live and builds the `Submit_Customer_Contract` payload. On the revenue line `unitCost` = `NetTotalPrice` (2400, net) but `extendedAmount` = `TotalLineAmount` (1540, list). Both Workday equality checks fail by exactly 860: (1) Contract Line Amount: `unitCost × qty` (2400) ≠ `extendedAmount` (1540); (2) Contract Line Revenue Amount: header (2400) ≠ SUM(`extendedAmount`) (1540). Rejected; `Workday_ID__c` stays null.

## The two defects

**Defect A — Workday sync blocker (MuleSoft-owned).** `extendedAmount ← OrderItem.TotalLineAmount` should be `← OrderItem.NetTotalPrice`. Proven to the dollar from the stored payload (not inferred). **No Salesforce component assembles the payload** (org-wide sweep of all custom Apex/triggers/flows for `extendedAmount`/`contractLineData`/`currentContractAmount`/`Submit_Customer_Contract`/`Workday_Sync_Payload` = 0 hits), so it **cannot** be fixed in SF. Identical to scXXXX / SC-3347. **Fix:** `extendedAmount ← NetTotalPrice` (direction-agnostic; no-op where list already equals net). Post-fix everything reconciles to 2400.

**Defect B — upstream pricing (RLM, separate ticket, NOT the blocker).** Regional services pricing reduces the **list** channel but leaves **net** at catalog. The `RegionalNetUnitPrice__c` field is named "Net" yet wired to `InputUnitPrice` (list) via `RegionalServicesPrice27` — a naming/wiring mismatch. Business question for the RLM owner (Marc DeBrey, SC-3345/SC-3359 family): should Italy be billed **1540** (regional) or **2400** (catalog)? If net should be 1540, fixing the net channel also makes Workday pass natively. *Confidence: HIGH on the 1540 provenance; MEDIUM on the exact net-channel element — needs a live pricing-waterfall/RevSignaling trace of QLI `0QLWC000003c9294AA`.*

## Relationship to other tickets

- **Same root cause as scXXXX / SC-3347**, byte-identical Workday error — but a **distinct, new** instance (created 2026-06-09, not in scXXXX's 2026-06-08 20-order set) and the **sign-reversed** variant: scXXXX's failures were downward discounts (list > net); here list 1540 < net 2400. Also the **first** case with the two-line `PREPAID`/`Usage Based` payload shape (scXXXX's repro was a single `FIXED AMOUNT` line). The one Mule fix closes both. → **Track the sync fix under scXXXX/SC-3347; use 00095398 as the UP-direction / two-line acceptance case.**
- **"Caused by the RCA bug" (reporter):** half-right. The sync failure is purely the MuleSoft mapping (not RCA — nothing in SF/RCA builds the payload). The net≠list condition is real but comes from the **regional pricing path**, not the SC-3137 migration (UAT is the migration *source*, not target). And it is **not a discount** — it is a +860 upward adjustment on the list channel.

## The uncommitted Apex changes on this branch are unrelated

None of `QuoteToOrderFieldMapper` (SC-3339 Bill/Ship carryover), `PowerOrderSplittingService` (SC-3366 bulkification; skips this line — filter is `Solution_Group__c='Power' AND Quantity>1`, this is MFT/Qty 1), `FieldPopulatedCheck` (SC-3366 deprecation), or `OrderSubmissionValidator` (SC-3366 SOQL-governor fix) reads or writes any pricing amount or the Workday payload (grep = 0 matches each). The mapper was even last-modified *after* the order's failure timestamp. They neither cause nor fix SC-3374.

## Actions

1. **Integration team (MuleSoft, owner Anypoint):** in `Submit_Customer_Contract`, source revenue-line `extendedAmount` from `OrderItem.NetTotalPrice` (the scXXXX fix). Confirm against the DataWeave / an Anypoint log on resubmit (source not in repo).
2. **Resubmit (no data change):** republish `Order_Completed_WD__e` with `Order_Id__c = 801WC00000kQn0zYAC` after the Mule fix — `Workday_ID__c` null, idempotent upsert by Order Id.
3. **RLM owner (Marc DeBrey, separate ticket):** decide whether regional pricing should lower the **net** channel; flag `RegionalNetUnitPrice__c` (named "Net") wired to `InputUnitPrice` (list). Does not block the resubmit.

## Open items / confidence

- **HIGH:** the Workday error + mechanism (read directly from the stored payload), no-SF-payload-builder, the Mule fix reconciles both clauses, 1540 = Italy regional value and not any PBE, quote-sourced & procedure-computed, class changes irrelevant.
- **MEDIUM / open:** the exact V9 element seeding net to 2400 (inferred from data; needs a live reprice trace); whether 2400 or 1540 is the business-intended price; any additional Workday list-ceiling rule (low risk — post-fix all three = 2400); DataWeave source confirmation.

## References

- scXXXX — `*Jira/Task/scXXXX | Discounted orders fail Workday sync .../README.md` and SC-3347 `MIDDLEWARE_FIX_SPEC.md`
- Memory: `project_workday_extendedamount_mapping`, `project_sc3347_workday_sync_failure`, `project_workday_resubmit_mechanism`, `project_quote_pricing_rollups`
- RCA workflow: 9 agents, 4-investigator + adversarial-verify + synthesize, all cross-checked against live FortraUAT.
