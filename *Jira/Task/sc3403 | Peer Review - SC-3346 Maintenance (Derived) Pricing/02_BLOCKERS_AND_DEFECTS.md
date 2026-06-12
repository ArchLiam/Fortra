# 02 — Blockers & defects (mechanism + code citations)

Each item lists the owner/design claim it tests, the mechanism, the live evidence, and the fix. Severity: 🔴 blocker (prevents deploy) · 🟠 major.

---

## 🔴 B-3 · Partner rate picks Software 15% instead of New/Renewal Maintenance 12%
**Claim tested:** "apply 15% software / 12% maintenance partner rates" (owner) + Step 4 "maintenance line's own partner/discretionary discounts apply — DONE."
**Mechanism:** On a derived maintenance line the line-level `Fortra_Product_Type__c` is blank when the posthook reads it (it's stamped by a separate before-save flow → ordering race). `PartnerNetPricePosthook.calculateDeferredPartnerPrice` (cls:379) calls `PartnerPricingService.resolveProductType(blank, qliId, bulkMap)`. The **bulk overload** (`PartnerPricingService.cls:181-198`) returns the map value if the key is present, **else hard-returns `'Software'` (line 194)** — it does NOT fall through to the `Product2.Fortra_Product_Type__c` lookup that the **single overload** performs (lines 79-92). `getMarginForProductType` then maps `'Software'`→`Software_Percent__c`=15.
**Evidence:** testrun.txt:68 ("Expected 12, Actual 15.00"); PartnerPricingService.cls:194 vs :79-92; PartnerNetPricePosthook.cls:379-383. `PartnerNetPricePosthook` implements `RevSignaling.SignalingApexProcessor` and fires after every procedure execution, so this hits **new business too**.
**Fix:** in the bulk overload, on a map-miss call `resolveProductType(contextType, qliId)` (the single overload's Product2 lookup) instead of returning `'Software'`; and ensure `loadProductTypesForLines` reliably populates the derived-line type. Re-run the test to green. Cross-ref **SC-3359** (partner net not applied).

## 🔴 B-4 · Renewal carry-forward broken — priced E2E once, decomposition not persisted
**Claim tested:** "convert to order with renewal carry-forward fields (base, prior partner $, prior discretionary $) persisting … Quote-to-order end-to-end validated" + Step 7 "Renewal formula — DONE."
**Mechanism:** Exactly one renewal quote→order completed: **order 00095475** (801WC00000kaGBpYAM, Activated, TotalAmount 60.64). Its Renewal-Maintenance OrderItem (PIA-PIA-RRM-PIAM) has `Base_Price__c=71` but `Prior_Partner_Discount__c=null`, `Prior_Discretionary_Discount__c=null`, `UnitPrice=0`, `TotalPrice=60.64`. Decode: `60.64=(71−8.52−6.25)×1.0785` — the discount components were computed transiently but **not persisted**. A Year-3 renewal reads null priors → `(71−0−0)×1.0785=76.57` (wrong). 13/15 most-recent build-renewal quotes have GrandTotal 0.
The in-procedure `DerivedPricingRenewals` (V130:1971) `IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (Base_Price__c−Prior_Partner_Discount__c−Prior_Discretionary_Discount__c)×(1+COLA_Uplift_Percent__c/100))` has **no IsNull guard** on its operands, and per SC-3350's RCA a FormulaBasedPricing NetUnitPrice write from a ListGroup does not commit for non-derived `LastTransaction` renewal lines (the `UnitPrice=0` on 00095475 confirms net never committed at unit level — it only depends on the prehook seed). See **M-1**.
**Evidence:** live OrderItem query on 801WC00000kaGBpYAM; V130:1971; SC-3350 09_NETPRICE_SEED_INERT_RCA.md §5b-5c.
**Fix:** persist `Prior_Partner_Discount__c`/`Prior_Discretionary_Discount__c` and a committed unit net on renewal-maintenance OrderItems at conversion (the `MaintenanceOrderDecompositionService` path); fix `UnitPrice=0`; add IsNull guards to the V13 formula; validate a Year-2→Year-3 carry-forward; reconcile the net-commit lever with SC-3350.

## 🔴 B-5 · Renewal source decision table refresh is FAILED (this is "renewing both assets fails before a quote")
**Claim tested:** owner blocker B1 "renewing both assets at once fails in the pricing procedure before a quote is created."
**Mechanism:** `Asset_Action_Source_Entries_Decision_Table_V2` (0lDa50000007BJhEAM, SourceObject=`AssetActionSource`) is Status=Active but **RefreshStatus=Failed**, `LastSyncDate=null`, reason **"common.exception.ApiException: Hash Key Group contains more than 200 rows"**. Source has **430,329** `AssetActionSource` rows. This is the lookup that maps a renewing asset to its source/renewal entries; with a never-completed sync it returns no usable data. The companion `Derived Pricing Entries` table IS Completed (synced 2026-06-11 20:36) — which is why **new business works and renewal fails**.
**Evidence:** live DecisionTable query (RefreshStatus/RefreshFailureReason); `SELECT count() FROM AssetActionSource`=430329.
**Fix:** re-author the table's grouping/hash key so no group exceeds 200 rows (finer GroupKey or a source-row filter), re-sync to Completed, re-test the both-assets renewal repro. Step 10 "decision-table refresh as needed" is a **hard blocker**, not optional.

## 🔴 B-6 · Step-5 decomposition persisted inconsistently
**Claim tested:** "carry-forward fields persisting … E2E validated."
**Evidence:** OrderItem `WHERE Base_Price__c>0 AND Fortra_Product_Type__c='New Maintenance'`: line 802WC00000OgTnmYAF on order 801WC00000kZELqYAO = Base 71 / Partner 8.52 / Unit 62.48 (correct). Lines on order 801WC00000kYmw8YAC = **Base 355** (license base) / Partner null / Disc null. `MaintenanceOrderDecompositionService.cls:145-154` sets `Base_Price__c=decomp.maintenanceBase`, but it did not run/overwrite on the 13:26 order. Renewal reads `OrderItem.Base_Price__c` (Stamp flow Get_Prior_OrderItem.Base_Price__c), so carrying 355 forward ~5×'s the renewal price.
**Fix:** make decomposition deterministic on every Q2O (invoke `persistPatches`/`buildPatches` unconditionally; verify it overwrites `Base_Price__c`). Backfill/block renewal of orders still carrying the license base. Add an E2E Q2O test asserting Base/Partner$/Discretionary$ on the OrderItem.

---

## 🟠 M-1 · "No Apex pricing prehook" principle is false as built
SDD lines 22/26/160 assert config + one flow, no Apex prehook. Live: `COLAUpliftPrehook.cls:21` and `PartnerNetPricePosthook.cls:22` both `implements RevSignaling.SignalingApexProcessor` and write net (PartnerNetPricePosthook.cls:264-271, 842-849); `Stamp_Maintenance_Pricing_Inputs.flow:162` writes `COLACalculatedPrice__c`. `DerivedPricingRenewals` reads `COLACalculatedPrice__c` first. Per SC-3350 the prehook seed is the **only** lever that commits net on non-derived renewal lines — so the prehook is *necessary*, and the principle is unattainable as stated. **Reconcile the SDD; build the manifest from the live org, not the SDD component list.**

## 🟠 M-2 · Two competing new-business formulas in V13
`ListContainer9` seq6 = `IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,0)))×Source_List_Price__c→NetUnitPrice` (V130:1776). `ListContainer` seq7 `DerivedPricingNewBusiness` = `IF(Renewal,NetUnitPrice,Base_Price__c×tier)→NetUnitPrice` (V130:1906). Seq7 overwrites seq6 — *only* when its DerivedPricing filter `(MDT present) OR (Renewal AND derived)` passes (V130:1700); if the MDT attribute is absent the line keeps Container9's `Source_List_Price` value. Different inputs (catalog PBE UnitPrice vs source-line Pre_Partner_Price/ListPrice/UnitPrice) → divergent prices. SDD documents only the Container-9 formula.
**Fix:** keep one formula, make its filter unconditional for new-business derived lines, retire the loser + its stamp flow, re-sync context, update the SDD to the field actually used (`Base_Price__c`).

## 🟠 M-3 · Reprice contextDefinitionName error is a guaranteed prod failure
Prod lacks `SalesTransactionContextExt_v2` entirely (UAT has base + _v2). `PartnerNetPricePosthook.cls:28,98` hard-codes `CONTEXT_DEFINITION_NAME='SalesTransactionContextExt_v2'`. UAT also has 2 active context defs + 4 active discovery procedures (Marc's "two discovery procedures/corruption" instinct — a real anomaly; prior RCA blames the unsynced context after in-place V-edits). `OrderRepriceInvocable` (PlaceOrderExecutor Force, cls:57-61) is the affected path; its success test fails (testrun.txt:78).
**Fix:** create+map `SalesTransactionContextExt_v2` in prod, re-sync to the deployed procedure version, ensure exactly one intended active context + discovery procedure for the reprice path; reproduce a real reprice with FINEST logging to confirm the error is gone; add a passing reprice test or a UAT runbook.

## 🟠 M-4 · Source_List_Price__c Q2O mapping disabled
`QuoteToOrderFieldMapper` (the one class in force-app) has the `Source_List_Price__c` QLI→OrderItem propagation commented out (cls:11 note + 115-121); the other carry-forward fields ARE mapped (246-253). Tied to the "Unable to fetch tags: [Source_List_Price__c]" reprice error. Decide flow-vs-mapper source of truth and enable exactly one.

## 🟠 M-5 · 2 of 4 derived RRM/RNM PBEs lack PriceBookEntryDerivedPrice (SC-3372 risk)
Only 01uWC000005wsbUYAQ (RNM-Fortra) and 01uWC000005wsbVYAQ (RRM-Fortra/TermDefined) have derived-price config; 01uWC000006XPNZYA4 (RRM Standard) and 01uWC000006XPPBYA4 (RRM Fortra/OneTime) have none → native `DerivedPricingDataRetrieval` hard-errors "contributing products are missing" if reachable. Add config or deactivate; confirm reachability via the design's removal of the native element; re-test OneTime RRM renewal add-to-cart.

## 🟠 M-6 · COLAUpliftPrehook prod copy stale vs UAT
Prod `LengthWithoutComments`=39,956 vs UAT 43,272 (~3,316 delta); prod runs an older prehook lacking the UAT renewal-maintenance COLA logic. Neither in force-app. Co-deploy the COLA/partner stack reconciled.

## 🟠 M-7 · Renewal classes largely untested
`RenewalMaintenancePricingService` 2% (no test class), `RenewalQuoteHeaderHandler` 15%, `RenewalAssetQuantityHandler` 36% — the exact classes behind the owner's open items. See [01_PROD_READINESS_GATES.md](01_PROD_READINESS_GATES.md).
