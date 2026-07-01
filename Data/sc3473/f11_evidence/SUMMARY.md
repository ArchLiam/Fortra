F-11 — Amend / co-term line with correct partner band (P1, defect_provenance SC-3346)
Active proc: Rev_Mgmt_Default_Pricing_Procedure V21 (status=Active, versionNumber=21; retrieve d01_v21_fresh.json)

PROC TRACE (from fresh V21 metadata, 123 steps):
 - AmendNetCarry (ListGroup seq39) > AmendFilter: ItemPricingSource='LastTransaction' AND ItemSalesTransactionAction='Amend' AND DerivedPricingAttribute=false
     -> AmendSeedNetUnit: NetUnitPrice = IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice)  [co-term net carryover]
     -> AmendSeedNetTotal: ItemNetTotalPrice = IF(ItemNetTotalPrice>0, ItemNetTotalPrice, TotalLineAmount)
 - ManualQuoteLevelDiscount (AdvancedListFilter, parent ListContainer56): logic "1 AND (2 OR 3 OR 4) AND (5 OR 6)"
     [1] ItemPricingSource NotEquals 'LastTransaction'  [2] ItemSalesTransactionAction='Amend'  [3]='Add'  [4] IsNull
     [5] ItemIsDerived__std IsNull  [6] ItemIsDerived__std=false
     => AMEND IS EXPLICITLY ELIGIBLE for manual quote-level discount (criterion 2).
 - PartnerDiscount (AdvancedListFilter, parent ListContainer3): Deal_Type__c NotEquals 'Fortra Originated' AND non-derived.
 - Partner band resolved by PartnerPricingService.getMarginForProductType(model, productType): keys PURELY on Fortra_Product_Type__c:
     'New Maintenance' -> New_Maintenance_Percent__c ; 'Renewal Maintenance' -> Renewal_Maintenance_Percent__c.
 - PartnerNetPricePosthook.isNewBusinessDerivedMaintenance: returns true ONLY when productType='New Maintenance' AND NOT renewal quote.
     => the renewal-COLA / Renewal-Maintenance-band path is GATED OUT for a New-Maintenance line on a non-renewal quote.

REAL DATA SMOKE-TEST (UI-priced control, NOT a hand-built headless line):
 Quote 0Q0WC0000039Vm10AE (Q-Wren - Test Pricebook 2), Deal_Type='Channel Originated', Partner 001WC00000ZtazZYAR, USD, active Fortra Price Book.
 Partner model (aGlWC00000024vZ0AQ/Aa3p): New_Maintenance_Percent=12, Renewal_Maintenance_Percent=10, Software=15, Subscription=18.
 New-Maint AMEND line 0QLWC000003ehR8: Product PIA-PIA-RNM-PIAMBK, Fortra_Product_Type='New Maintenance' (QLI+Product2), QuoteAction.Type='Amend',
   Maintenance Type Defn=Standard (rate 0.20), Source_List_Price=355, Base_Price=355, derived base = 355x0.20 = 71.
 3 Force-reprices (/connect/rev/sales-transaction/actions/place, pricingPref=Force; all isSuccess=true, errorResponse=[]):
   pre (UI): Net=62.48 = 71x(1-0.12) New-Maint band 12%
   pass1:    Net=62.48 (held)
   pass2:    Net=60.35 = 71x(1-0.15) contributor (license)-carried Software band 15%
   pass3:    Net=60.35 (STABLE fixed point)
 Sibling lines stable + each on its OWN band: Subscription ES-CEP-RSL-ACTIDB Net=77080 (18%); Perpetual PIA-PIA-NRPS-PIAP Net=301.75 (Software 15%).

VERDICT BASIS:
 - F-11 claim "Amend eligible for manual quote-level discount" = PASS (proc filter ManualQuoteLevelDiscount includes ItemSalesTransactionAction='Amend').
 - F-11 claim "new-maint band applied NOT renewal band" = PASS: line routes through new-business derived-maint path (isNewBusinessDerivedMaintenance=true);
     renewal band (10% -> would be 63.90) is NEVER applied at any pass. Both 62.48 (12%) and 60.35 (15%) are NEW-BUSINESS derivations.
 - Co-term carryover step (AmendNetCarry) is present + structurally correct (carries prior net); not fully exercised on this perpetual-maint control (no subscription term/EndDate) — same limit noted in A-02 (BLOCKED on building a hydrated native LastTransaction line headlessly).

DOCUMENTED NUANCE (NOT an F-11 defect, NOT the renewal band): on reprice the committed net converges from the UI prehook's own New-Maint band (12%->62.48)
 to the SC-3412 posthook's contributor-carry band (15%->60.35). buildDerivedMaintenanceSequentialDiscountUpdate carries the contributor (license)
 partner percent forward because the maint net is DERIVED from the license net. This is the deployed carry-forward design (project_newmaint_derivation_inconsistency,
 SC-3410/SC-3412), same partner-posthook non-idempotency family as F-07/SC-3359 — a separate, pre-existing observation, not a renewal-band misapplication.
