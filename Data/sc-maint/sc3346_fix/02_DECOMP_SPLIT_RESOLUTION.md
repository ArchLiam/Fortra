# SC-3346 DECOMP-SPLIT — Resolution (2026-06-14, FortraUAT)

## Verdict: NOT a build defect — works-as-designed. Reclassify PARTIAL → PASS.

The scenario's premise was **wrong**, not the build. The build's maintenance-decomposition model is the
intended FORTRA-PRODUCT-018 Step 5 design, the value math is correct (B-6), and the design's stated purpose
(carry maintenance dollars forward to renewal) is verified end-to-end. **No code change required.**

## What the scenario assumed vs what the build does
- **Scenario premise (wrong):** maintenance decomposition produces a *derived maintenance child OrderItem
  linked to its parent license OrderItem via `Original_Order_Item__c`* (an FK-split / parent-child model).
- **Actual build (correct by design):** the maintenance line is a **separate Product2 SKU** (e.g.
  `…(BoKS)-NewMaintenance`) auto-added by a config rule, carrying the license list price in its **own**
  `Source_List_Price__c`. At quote→order conversion, `MaintenanceOrderDecompositionService` stamps the
  maintenance **dollars** onto that line. There is **no parent-child FK by design** — not on the Order
  (`Original_Order_Item__c`/`RelatedOrderItemId` both null) and not on the Quote
  (`ParentQuoteLineItemId`/`RelatedQuoteLineItemId` both null).

## Evidence
1. **Service intent (authoritative):** `MaintenanceOrderDecompositionService.cls` header — *"FORTRA-PRODUCT-018
   Step 5: persists maintenance dollar decomposition (Base, Partner$, Discretionary$) onto OrderItem at
   quote-to-order conversion **so renewal pricing can carry real dollars forward**."* It is value-stamping,
   not FK-splitting. The class references **no** link field (0 hits for Original_Order_Item__c / RelatedOrderItemId
   / ParentQuoteLineItemId across all build classes).
2. **Stamping is complete** (cls L147-149): `Base_Price__c = maintenanceBase`,
   `Prior_Partner_Discount__c = partnerDiscount`, `Prior_Discretionary_Discount__c = discretionaryDiscount`.
   Live OIs confirm all three: e.g. 00095472 New-Maint → Base 71, PriorPartner 8.52, PriorDisc 0; 00095475
   Renewal-Maint → Base 71, PriorPartner 8.52. `Original_Order_Item__c`/`RelatedOrderItemId` = null on all.
3. **Value math correct (B-6, already PASS):** maintenanceBase = sourceBase × tierRate (Standard/Professional
   0.20, Premier 0.30); 71 = 355 × 0.20; 55000 = 275000 × 0.20; zero license-base (355) leaks.
4. **Stated purpose verified end-to-end:** the renewal-maintenance QLI `cy334` (00781053) reads exactly the
   decomposed dollars — Base 71, Prior_Partner 8.52 — i.e. the carry-forward works.
5. **`Original_Order_Item__c` belongs to quantity-splits, not maintenance:** all 40 OIs that have it populated
   are same-Product2 quantity splits from `PowerOrderSplittingService`; ZERO of 19,844 maintenance OIs have it
   (discovery KB 14 L327 + memory `project_sc3210_workday_linetype`).
6. **Unit tests:** `MaintenanceOrderDecompositionServiceTest` SOLO re-run this session — **all Pass, 0 Fail**
   (closes the original verdict's "could not self-run / org-locked" gap), incl. `compute_matchesWorkedExample`,
   `compute_premierTierRate`, `buildPatches_persistsDecompositionForDerivedLine`,
   `buildRenewalCarryForwardPatches_persistsQliInputsOnOrderItem`.

## FINALIZED 2026-06-14 — re-confirmed live + the doc reconciliation (the only open item) executed
Re-verified against the org (retest agrees: "doc/SDD reconciliation only; math is correct, FK-absence is by design"):
- Recent maintenance OIs (00095470/72/75) still value-stamped (Base 71, SLP 355, PriorPartner 8.52) with
  `Original_Order_Item__c` = null and `RelatedOrderItemId` = null.
- Live `MaintenanceOrderDecompositionService` references **0** link fields (Original_Order_Item / RelatedOrderItem /
  ParentQuoteLineItem); SOLO test 40/40 pass.
- **Asset-level association confirmed:** BoKS assets are flat (ParentId null, RootAssetId = self) and link to Contracts
  via `AssetContractRelationship`; the maintenance↔license association is therefore **Contract-level**, which is exactly
  why renewal quote 00781053 renewed BOTH the license and the maintenance legs with no order-line FK.

### Owner decision: value-stamping (no FK) is the intended design → reclassify DECOMP-SPLIT **PARTIAL → PASS** (works-as-designed).

### SDD / design-doc correction text (hand to the SDD owner — replaces the FK-split premise)
> **Maintenance Decomposition (FORTRA-PRODUCT-018 Step 5).** First-year (New) and renewal maintenance are represented as
> **separate Product2 SKUs** (the product's `-NewMaintenance` / `-RenewalMaintenance` variant), auto-added by a
> ProductConfigurationRule when the corresponding license is added; the maintenance line carries the license's list price
> in its own `Source_List_Price__c`. At Quote→Order conversion, `MaintenanceOrderDecompositionService` stamps the
> maintenance **dollars** onto the maintenance OrderItem — `Base_Price__c = Source_List_Price__c × tier rate`
> (`Maintenance_Rate__mdt`), plus `Prior_Partner_Discount__c` and `Prior_Discretionary_Discount__c` — so renewal pricing
> carries real dollars forward. **There is no parent-child foreign key** between the maintenance and license OrderItems;
> `Original_Order_Item__c` is reserved for quantity-splits (`PowerOrderSplittingService`) and must **not** be used for
> maintenance (it would mis-classify the line in the Workday contract-line-type flow, SC-3210/SC-3368). The
> maintenance↔license association for renewal is maintained at the **Contract/Asset** level (`AssetContractRelationship`).

### Optional (not required): if the business later wants explicit reporting/audit traceability of maintenance→license,
add a **new dedicated lookup field** (never `Original_Order_Item__c`). Not needed for pricing or renewal.

## Recommendation — do NOT add a maintenance↔license link via `Original_Order_Item__c`
Populating `Original_Order_Item__c` on maintenance lines would **break** the Workday contract-line-type flow
(`Fortra_OrderItem_Set_Workday_Contract_Line_Type`, SC-3210/SC-3347/SC-3368), which uses that FK to detect
subsplit parents. The value model is self-contained and renewal works via the asset/contract association
(00781053 renewed both license + maintenance assets without any order-line FK), so no link is needed.

## Cross-ticket observation (for SC-3210/3368, not DECOMP-SPLIT)
This investigation confirms *why* the Workday line-type flow mis-stamps: it expects a "LIC/MAINT subsplit via
`Original_Order_Item__c`" model, but SC-3346 creates maintenance as **separate SKUs with no FK**. The two models
are on different tracks; the Workday flow's `Original_Order_Item__c`-based subsplit detection is the wrong
discriminator (it catches quantity-splits and misses SC-3346 maintenance lines entirely).

## Minor note (not a defect)
There is no persistent traceability FK from a maintenance line back to its specific license line at any level.
Harmless for pricing/renewal (value is self-contained; renewal associates at asset/contract level), but if
audit traceability is ever required it should use a **new dedicated field**, never `Original_Order_Item__c`.
