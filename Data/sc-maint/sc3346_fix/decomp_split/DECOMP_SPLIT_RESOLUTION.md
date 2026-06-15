# DECOMP-SPLIT — Resolution (false-premise partial → PASS)

**Status:** ✅ RESOLVED 2026-06-14 (FortraUAT). Verdict reclassified **partial → pass**. No code change, no SDD change, no deploy — the partial was a test-scenario premise error.
**Owner:** Liam Jeong.

## The scenario premise (what the test expected)
> Decomposition produces a derived maintenance **child OrderItem linked to the parent license via `Original_Order_Item__c`** (an FK-split), stamped `Base_Price__c = license source list × tier rate`.

## What's actually built (and it's correct)
The maintenance line is a **self-contained SKU** auto-added by the configurator alongside the license (its own QLI/OI). `MaintenanceOrderDecompositionService` (FORTRA-PRODUCT-018 Step 5) value-stamps the decomposition **directly onto that maintenance OrderItem** at quote-to-order conversion:
- `Base_Price__c = (sourceBase × tierRate)` (`compute`, L426) — e.g. 355 × 0.20 = **71**; plus `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` for renewal carry-forward.
- It selects maintenance lines via `loadDerivedPricebookEntryIds` (the line's PBE has a `PriceBookEntryDerivedPrice`) and reads the tier from the MTD attribute.
- It references **`Original_Order_Item__c` zero times** — there is no parent-license → child-maintenance FK.

## Why the premise is false (3 independent proofs)
1. **The SDD never calls for it.** `Fortra-Maintenance-Derived-Pricing-Solution-Design` has **0** `Original_Order_Item` / FK-split references. It specifies the as-built exactly: *"prices each maintenance line as source license list price × tier rate"* (§ lines 24/36/160), source list price *"captured as data on the maintenance line by a Flow"*, and *"the maintenance-to-source relationship is provided by the existing **`PriceBookEntryDerivedPrice.ContributingProductId`** mapping… **No new objects are introduced.**"* (line 162).
2. **The build never implements it.** `MaintenanceOrderDecompositionService` = 0 FK references; the decomposition is in-place value-stamping.
3. **`Original_Order_Item__c` belongs to a different feature.** It is populated by **`PowerOrderSplittingService`** (order **quantity-splits**, SC-3210 / SC-3368) — child OI = *same product* as parent, never license → maintenance. Live: of 40 OIs carrying the FK, **40/40 are same-product qty-splits, 0 license→maintenance**; of 19,844 maintenance OIs, **0 carry the FK**.

## Correctness (B-6 holds — unchanged)
The maintenance OrderItem carries the **maintenance base, never the license base**: 0 maintenance OIs with `Base=355 AND SLP=355`; all 16 positive-Base maintenance OIs have Base/SLP = 0.20; 0 license-base leaks. Chains proven end-to-end (PIAMBK 355→71; Automate Ultimate 275000→55000). The value the premise expected (`license list × tier`) is exactly what the build produces — only the *structure* (separate stamped line vs child FK) differed, and the separate-line structure is what the SDD specifies.

## Resolution
- **Reclassify DECOMP-SPLIT: partial/medium → PASS / none.** The decomposition feature works correctly and **conforms to the SDD**; the "FK-split not present" finding reflects an incorrect scenario premise, not a build gap.
- **No SDD edit needed** — the SDD already describes the as-built (separate maintenance line + `PBEDP.ContributingProductId` relationship + "no new objects").
- **No code change** — `MaintenanceOrderDecompositionService` is correct (B-6 + SOLO 40/40, 84%).
- **Test-suite note:** any DECOMP-SPLIT scenario asserting an `Original_Order_Item__c` license→maintenance FK should be **rewritten** to assert the as-built (maintenance OI `Base_Price__c = source list × tier`, source via `PBEDP.ContributingProductId`), so it stops reporting a false partial.

## JIRA comment (ready to paste)
> DECOMP-SPLIT resolved as a false-premise partial → PASS. The build does **not** use an `Original_Order_Item__c` license→maintenance FK-split, and neither the SDD nor the design ever called for one (SDD: "no new objects"; relationship via `PriceBookEntryDerivedPrice.ContributingProductId`). The maintenance line is a self-contained SKU whose OrderItem is value-stamped (`Base_Price__c = source list × tier`, e.g. 355×0.20=71) by `MaintenanceOrderDecompositionService` at Q2O. `Original_Order_Item__c` belongs to a different feature (`PowerOrderSplittingService` quantity-splits, SC-3210/3368). B-6 holds (0 license-base leaks). No code or SDD change; the test scenario should be rewritten to the as-built shape.
