# SC-3441 — Cancellation line mis-pricing: comparator analysis (FortraUAT)

Generated 2026-06-24. Org: FortraUAT (00DWC000006eUFF2A2). Subject defect line: OrderItem `802WC00000OugI7YAJ` (Arcus Hosting, Order 00095539 / 801WC00000ktJPMYA2), UnitPrice=NULL → TotalPrice=0 (expected -3000).

## 1. Population scope (how rare is cancellation in this org)

| Probe | Count | Notes |
|---|---|---|
| OrderAction Type='Cancel' | **2** | 8OAWC000002SxiL4AS (our order), 8OAWC000002Qws14AC |
| Order OriginalActionType='Cancel' | **2** | 801WC00000ktJPMYA2 (ours), 801WC00000kZUARYA4 |
| OrderItem Quantity < 0 | **2** | both cancellation lines below |
| QuoteLineItem Quantity < 0 | **42** | the rich comparator set (see §3) |

## 2. The two ORDER-side cancellation lines (both broken, identical pattern)

| OrderItem | Product | Family | StQ | EnQ | Qty | ListPrice | UnitPrice | NetUnitPrice | TotalPrice | PricingTermCount | Created |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 802WC00000OugI7YAJ | Arcus Hosting | Subscription | 1 | 0 | -1 | 3000 | **NULL** | **NULL** | **0** | 1 | 2026-06-16 |
| 802WC00000OgXD4YAN | beSECURE - Cloud-Based | Subscription | 1 | 0 | -1 | 0 | **NULL** | **NULL** | **0** | null | 2026-06-11 |

Both broke identically. Identical on: ProductSellingModelId 0jPWC000000060b2AA, Asset__c null, OriginalOrderItemId null, PriceRevisionPolicyId null, AllowRegionalPricing__c false, RegionalNetUnitPrice__c null. Differ only on ListPrice (3000 vs 0) and PricingTermCount (1 vs null) — and BOTH still broke → those fields are NOT the discriminator.

## 3. The QUOTE-side comparator: 42 negative-qty QLIs — PROVENANCE is the boundary

Base rate:
- **36 / 42 priced CORRECTLY** (UnitPrice populated, TotalPrice negative). **ALL 36 created by `Service Data Migration`** (bulk data load — UnitPrice was stamped directly, never ran the live pricing procedure).
- **6 / 42 BROKEN** (UnitPrice NULL → TotalPrice 0). **ALL 6 created by REAL USERS via the UI cancellation flow.** This is the genuine cancellation population, and it is **6/6 = 100% broken.**

### All 6 BROKEN (procedure-priced) cancellation lines

| QLI | Product | Family | Qty | ListPrice | TotalPrice | Created By | Date |
|---|---|---|---|---|---|---|---|
| 0QLWC000003fKAj4AM | Arcus Hosting | Subscription | -1 | 3000 | 0 | Joe Romo | 2026-06-16 |
| 0QLWC000003dCu14AE | Automate Enterprise | Subscription | -1 | 0 | 0 | Sachin Gupta | 2026-06-11 |
| 0QLWC000003d7uL4AQ | beSECURE - Cloud-Based | Subscription | -1 | 0 | 0 | German Wren | 2026-06-11 |
| 0QLWC000003YOW14AO | Cybersecurity Services | Services | -1 | 350 | 0 | Marc DeBrey | 2026-05-31 |
| 0QLWC0000034tk94AA | 24 X 7 X 365 Monitoring | Services | -1 | 15000 | 0 | Aaron Broom | 2026-04-17 |
| 0QLWC000002q2Sn4AI | 24 X 7 X 365 Monitoring | Services | -1 | 15000 | 0 | Aaron Broom | 2026-03-20 |

Spans **4 months** (2026-03-20 → 2026-06-16), **5 users**, **2 families** (Subscription, Services), ListPrice 0→15000. No date/product/sellingmodel boundary — uniformly broken.

### Sample WORKING comparators (migrated — NOT a counter-example of procedure logic)

| QLI | Product | Qty | ListPrice | UnitPrice | TotalPrice | Created By |
|---|---|---|---|---|---|---|
| 0QLWC000003EwbN4AS | EFT Enterprise-RenewalMaintenance | -1 | 0 | 5014 | -5014 | Service Data Migration |
| 0QLWC000003K76d4AC | Globalscape Legacy SKU - Other | -2 | 0 | 49.8 | -99.6 | Service Data Migration |

Key contrast: migrated lines carry a non-null **UnitPrice that was loaded directly** (ListPrice is 0 on them — they were never expected to derive price from ListPrice). The user/UI cancellation lines have **null UnitPrice and rely on the procedure to derive it from ListPrice** — which is exactly what fails.

## 4. Conclusion

**SYSTEMIC.** Every cancellation/negative-qty line that actually executed the live pricing procedure ended with NULL UnitPrice/NetUnitPrice → TotalPrice 0 (6/6 = 100%). The only "working" negative lines are bulk-migrated records with a pre-stamped UnitPrice that bypassed the procedure entirely. The discriminator is **provenance (procedure-run vs migrated)**, NOT product, selling model, region flag, Asset, PriceRevisionPolicy, ListPrice value, or date.

## 5. Procedure corroboration

`Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` (retrieved, ~92.6k lines, ~10 variant blocks): `StartQuantity`, `EndQuantity`, `Cancel` each appear **0 times** → the procedure has NO cancellation/reduction-aware branch. It seeds InputUnitPrice from ListPrice via an AssignmentElement (line ~346–396, ListPrice→InputUnitPrice) and computes line total as InputUnitPrice * LineItemQuantity with ItemNetTotalPrice→ItemTotalPrice. For the cancellation lines UnitPrice/NetUnitPrice arrive at the procedure already NULL and are never (re)seeded from ListPrice on the negative-qty path → NULL propagates to TotalPrice 0. The null originates UPSTREAM of the procedure (in how RLM creates the cancellation OrderItem/QLI), then the procedure faithfully multiplies NULL × -1 = 0.
