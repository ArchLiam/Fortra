# 03 — Prod deploy manifest + completion plan

## Production gap (live FortraProd, `liam.jeong.c@fortra.com`)
| Component | UAT | PROD |
|---|---|---|
| Rev_Mgmt_Default_Pricing_Procedure active version | **V13** | **V1** (12-version gap; one ExpressionSetVersion fuses this ticket + SC-3393/3372/3359/3384) |
| New Apex classes (Maintenance/Renewal/Partner/OrderReprice) | present | **0 of ~10** |
| QuoteTrigger / QuoteLineItemTrigger | Active | **absent** (no triggers dir in force-app) |
| QLI fields | all 6 | only `Base_Price__c`, `COLA_Uplift_Percent__c`, `COLA_Solution_Category__c` — **`Source_List_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c` missing** |
| OrderItem maintenance fields | 4 | **0** |
| `SalesTransactionContextExt_v2` context def | present | **absent** |
| ProductConfigurationRules | 302 | **0** |
| Selling-model / PBE backfill | loaded | **0** |
| `Maintenance_Rate__mdt` rows | present | **0** |
| MaintenanceType decision table | 1 | **0** |
| Stamp flows | v11 + v8 | **absent** |
| `COLAUpliftPrehook` | UAT 43,272 | prod 39,956 (**stale**) |

## Full ordered manifest

### A. Pipeline-deployable (metadata / CI-CD)
1. **QLI custom fields** missing in prod: `Source_List_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c`.
2. **OrderItem custom fields** (all 4): `Source_List_Price__c`, `Base_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c`.
3. **Reconcile `COLA_Source__c`** restricted picklist — add `MyCAP Default` (force-app copy is missing it → would fail validation / strip a live value). Audit all restricted picklists touched.
4. **Apex classes** (reconciled to latest UAT bodies, back-filled into force-app first): MaintenanceOrderDecompositionService, OrderRepriceInvocable, QuoteRenewalTypeHandler, RenewalQuoteLineHandler, RenewalQuoteHeaderHandler, RenewalAssetQuantityHandler, RenewalMaintenancePricingService, PartnerNetPricePosthook, COLAUpliftPrehook (updated), COLAUpliftHandler, PartnerPricingService, QuoteToOrderFieldMapper, QuoteLineItemTriggerHandler + all `*Test`.
5. **Triggers:** QuoteTrigger, QuoteLineItemTrigger (they call the renewal handlers unconditionally → handler graph must come too).
6. **Flows:** Stamp_Maintenance_Pricing_Inputs (resolve the dual-flow redundancy first), Fortra_Quote_to_Order_Conversion, Fortra_Quote_Reprice.

### B. Manual / non-CI-CD (flag each; assign an owner + runbook)
- **(A)** `SalesTransactionContextExt_v2` context definition + mappings — manual platform config; re-sync to the deployed procedure version.
- **(B)** Rev_Mgmt procedure **V1 → V13** rebuild + activation — platform-managed, version-delete-blocked; in-place edits caused the contextDefinitionName gack. **Author a carved V14** (new-business only, preserving the `QuoteTypeText__c` gate) OR consciously bundle-gate all of V13's tickets together.
- **(C)** MaintenanceType (and any Derived/Tiered) decision tables — build + **manual refresh**; **re-author `Asset_Action_Source_Entries_Decision_Table_V2`** so no hash group exceeds 200 rows (B-5), then sync to Completed.
- **(D)** `Maintenance_Rate__mdt` tier-rate records.
- **(E)** Year-2 `ProductConfigurationRule` 14OWC0000022Eyb2AE + dependent PCRs — **no migration tooling** (per `project_pcr_no_migration_path`); manual rebuild in prod or SF escalation. The single hardest non-deployable item.
- **(F)** ~85-row selling-model backfill (`ProductSellingModelOption` + `PricebookEntry`) — data load; **re-derive against prod at preflight** (per `feedback_stale_gap_inventory`).

## Completion plan (sequenced; new-business carve-out lens)
1. **Freeze the class set** — 5 classes were modified 2026-06-11; stop in-place V13 edits. *(owner: Nir)*
2. **Fix B-3** — PartnerPricingService bulk overload (cls:194) fall through to the Product2 lookup; partner-rate test → green. *(new-business; Nir)*
3. **Resolve M-2** — keep one new-business formula (`Source_List_Price×tier` vs `Base_Price×tier`), make its filter unconditional for new-business derived lines, retire the loser + its stamp flow, re-sync context, update SDD. *(Nir/Marc)*
4. **Test work** — new `RenewalMaintenancePricingServiceTest`; raise COLAUpliftPrehook, RenewalQuoteHeaderHandler, RenewalAssetQuantityHandler, PartnerNetPricePosthook, PartnerPricingService to ≥75%; fix the 2 env/data + the fake-Id failures; add ≥1 procedure-driven assertion; re-run to fully green ≥75% org-wide. *(Nir)*
5. **Fix B-5** — re-author `Asset_Action_Source_Entries_Decision_Table_V2` grouping (no group >200 rows), sync to Completed, re-test the two-asset renewal repro. *(Nir)*
6. **Fix B-4/B-6** — persist `Prior_Partner_Discount__c`/`Prior_Discretionary_Discount__c` + a committed unit net on renewal-maintenance OrderItems at conversion; make decomposition deterministic on every Q2O; add IsNull guards to the V13 renewal formula; validate Year-2→Year-3 carry-forward. *(Nir)*
7. **Back-fill source control** — all live classes + both triggers into force-app, reconciled to latest UAT; reconcile `COLA_Source__c` (`MyCAP Default`) and the prod-vs-UAT `COLAUpliftPrehook` divergence. *(Nir)*
8. **Prod prerequisites (manual)** — create/map `SalesTransactionContextExt_v2`; build/refresh decision tables; load `Maintenance_Rate__mdt` rows; rebuild Year-2 PCR (no tooling); load the selling-model/PBE backfill (re-derive vs prod). Each needs an owner + runbook. *(Marc/Nir)*
9. **Deploy bundle** — fields → picklist → context def → decision tables + CMDT rows → backfill data → classes+triggers (green, ≥75%) → flows → procedure version rebuild+activate (carved V14 or full V13 bundle-gated) → PCR rebuild → end-to-end prod reprice validation. **Do not promote until tests are green and the 4 manual items have owners.** *(Nir)*

## Decision required from Marc/German
- **Scope:** ship new-business-only (carved V14) now and split renewal (B-4/B-5/M-1, COLA, context-def reprice) into a separate ticket — vs hold the whole thing until renewal is solid. The new-business carve-out is defensible but is a multi-day hardening pass (steps 1-4, 7-9), not a same-day ship.
- **Architecture honesty:** accept the Apex prehook/posthook as supported architecture (reconcile the SDD) — the SC-3350 RCA proves a procedure-only net seed cannot work on non-derived renewal lines.
