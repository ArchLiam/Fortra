import React, { useState, useMemo } from "react";

/**
 * V21 Pricing-Procedure Validation — Results (FortraUAT, active V21).
 * Self-contained, dependency-free (inline styles). Drop into any React app:
 *   import V21Results from "./V21_VALIDATION_RESULTS.jsx";  ->  <V21Results />
 * Source of truth: Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md + rows_run3/*.json.
 * 69 PASS / 13 FAIL / 22 BLOCKED. Validation only — fixes are PROPOSED, not applied.
 */

const DATA = {
 "meta": {
  "title": "V21 Pricing-Procedure Validation",
  "subtitle": "Rev_Mgmt_Default_Pricing_Procedure \u2014 Active Version 21",
  "org": "FortraUAT",
  "procVersion": "ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (Active; LastModified 2026-06-30 05:56Z)",
  "context": "SalesTransactionContextExt_v2 (v23) / OrderEntitiesMapping",
  "date": "2026-06-30",
  "verdictLine": "V21 prices the large majority of catalog scenarios correctly. 13 defects remain \u2014 a tight cluster of multi-currency / configured-pricing faults, a null-unsafe filter that hard-crashes cancellation & amend-remove reprices, a discount that compounds across reprices, and several derived/maintenance config gaps. One defect (F-09) is a fresh regression introduced by today's in-place V21 edit.",
  "method": "Every scenario was smoke-tested on real FortraUAT data (find/reuse a real record \u2192 mandatory preflight gate \u2192 headless Force-reprice through live V21 \u2192 re-measure actual field values), not statically reasoned. Findings ran a 4-stage adversarial pipeline: (1) 104 executor agents, (2) an independent verifier on every FAIL, (3) a skeptical data-artifact audit that defaulted each FAIL to \u201cbad seed data\u201d until disproven, and (4) an Opus tie-breaker on every verifier-vs-audit conflict, each resolved against a decisive live fact. 154 agents, ~8.9M tokens.",
  "dataDiscipline": "No FAIL was allowed to stand as a defect until its seed passed preflight and the explainability trace confirmed the intended V21 branch ran on valid inputs. The audit + tie-breaker caught 3 false-positive defects (stale data, malformed EndDate, wrong QuoteAction binding), corrected 2 catalog expectation-errors, and rescued 1 real defect a verifier had wrongly dismissed. Validation only \u2014 fixes are PROPOSED, not applied."
 },
 "legend": {
  "verdicts": [
   {
    "key": "PASS",
    "color": "#16794d",
    "meaning": "V21 priced the scenario correctly AND it was proven.",
    "why": "The seed passed preflight, the intended branch fired on valid inputs, and the measured numbers matched the expected behavior on real data. A PASS is confirmed-correct behavior, never static reasoning."
   },
   {
    "key": "FAIL",
    "color": "#b3261e",
    "meaning": "V21 produced the wrong number on valid, preflighted input with the intended branch confirmed to have run.",
    "why": "The fault is in the procedure or in org config a real user would also hit \u2014 not in the test data. Every FAIL survived an adversarial \u2018prove it isn\u2019t a data issue\u2019 challenge. Sub-classed PROCEDURE-DEFECT vs ORG-CONFIG-DEFECT."
   },
   {
    "key": "BLOCKED",
    "color": "#8a6d00",
    "meaning": "Could not be smoke-tested to a trustworthy verdict \u2014 deliberately NOT scored as FAIL.",
    "why": "Caused by an environment gap (no Evergreen catalog, no contracted lines in UAT), a headless-insert $0 fixture artifact, stale/malformed seed data, or another unprovable input. An unproven input must never be reported as a procedure defect; when in doubt we suspect the fixture, not V21."
   }
  ],
  "rootCauses": [
   {
    "key": "PROCEDURE-DEFECT",
    "desc": "Inputs valid, intended branch ran, V21 produced the wrong number \u2014 a procedure/engine fault."
   },
   {
    "key": "ORG-CONFIG-DEFECT",
    "desc": "Wrong number traces to missing/incorrect config a real UI user would also hit (e.g. a product genuinely lacking a required pricing attribute, or a currency-incomplete decision table)."
   },
   {
    "key": "TEST-DATA-ARTIFACT",
    "desc": "The fixture was malformed / the branch never ran / a stale field \u2014 not a V21 fault. Reclassified to BLOCKED, not a reportable defect."
   },
   {
    "key": "EXPECTATION-ERROR",
    "desc": "The catalog\u2019s expected value was itself wrong. Corrected and re-graded to PASS."
   }
  ]
 },
 "headlines": [
  {
   "tag": "Currency cluster (3 defects, P0)",
   "text": "G-01 / G-02 / J-10 \u2014 configured & derived pricing is currency-blind: an EUR line picks up the USD ABA override (G-02), the Unit-Price-Display step double-applies FX (G-01), and EUR derived-maintenance prices $0 because the IsDerived flag exists only on the USD PBE (J-10). All trace to SC-3384."
  },
  {
   "tag": "Null-unsafe filter hard-crash (2 defects, P0/P1)",
   "text": "K-01 (cancellation) and F-12 (mid-term amend-remove) both abort the ENTIRE reprice at StampBaseFilter (SF-BRE-00004) because criterion \u2018NetUnitPrice > 0\u2019 has no IsNull guard \u2014 3 of 6 instances remain unpatched. No credit is produced. SC-3441."
  },
  {
   "tag": "New regression from today\u2019s in-place edit (P1)",
   "text": "F-09 \u2014 non-USD partner lines are now double-FX-converted (corporate rate \u00d7 hardcoded rate), understating net ~8%. This same quote PASSed in run-1 at 01:47Z and FAILs after the 05:56Z in-place V21 edit \u2014 a confirmed regression."
  },
  {
   "tag": "Discount compounds across reprices (P0)",
   "text": "H-01 \u2014 the manual line-level amount discount seeds its base from NetUnitPrice instead of ListPrice, so the discount re-applies on every reprice and net erodes (45000 \u2192 40500 \u2192 \u2026). Same family as the F-07/E-03 idempotency fixes, which didn\u2019t cover the manual-amount path."
  },
  {
   "tag": "Derived / maintenance config gaps (P0\u2013P2)",
   "text": "J-06 partner band uses license 15% not New-Maint 12%; J-09 derived lines with no PBEDP row price silently null (only 199/1889 IsDerived PBEs covered); A-07 ~1497 maintenance products lack the Maintenance-Type attribute \u2192 $0/100%-copy. SC-3346/3359/3372."
  },
  {
   "tag": "What got better since the last run",
   "text": "5 prior FAILs are fixed (F-03, G-04, I-01, K-09 + K-02 expectation); 9 more prior FAILs were correctly downgraded to BLOCKED \u2014 they had been logged on headless-insert $0 artifacts or env gaps, not real V21 faults."
  }
 ],
 "defects": [
  {
   "id": "G-01",
   "pri": "P0",
   "type": "PROCEDURE",
   "cat": "Multi-Currency / Regional",
   "ticket": "SC-3384",
   "regression": false,
   "title": "Currency \u2018Unit Price Display\u2019 step double-applies FX",
   "step": "Currency Conversion \u2013 Unit Price Display (seq 40 / array-index 38): output UnitPrice = InputUnitPrice \u00d7 IF(ISO=EUR,0.9346,\u2026), but InputUnitPrice is already the currency-converted value carried in from the net steps.",
   "expected": "The persisted UnitPrice equals the per-ISO converted unit price once (e.g. 1575 USD \u00d7 0.9346 = 1471.995 EUR).",
   "observed": "QLI 0QLWC000003kmG14AI (AAM Perpetual EUR): NetUnitPrice/NetTotalPrice/TotalLineAmount/TotalPrice = 1471.995 ALL correct, but UnitPrice is FX-applied a second time. Net channel correct; display channel wrong.",
   "fix": "Source the Unit-Price-Display input from the pre-currency base (Base_Price__c / Source_List_Price__c = 1575 USD) so it converts once, OR assign UnitPrice = NetUnitPrice after the net currency steps.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kmG14AI/view"
  },
  {
   "id": "G-02",
   "pri": "P0",
   "type": "PROCEDURE",
   "cat": "Multi-Currency / Regional",
   "ticket": "SC-3384",
   "regression": false,
   "title": "Configured (ABA) pricing is currency-blind \u2014 USD override leaks into an EUR line",
   "step": "Native RLM Attribute-Based Price step (AttributeBasedAdjustment decision-table lookup) carries no CurrencyIsoCode in its key, so a USD-only Override row matches an EUR line; the EUR PBE list is ignored and some attribute combos collapse to $0.",
   "expected": "Pricing lookups include CurrencyIsoCode in the composite key; non-USD ABA rows + a currency-matched PBE fallback are used; no USD-value leak.",
   "observed": "L1 0QLWC000003kmG14AI: Source_List_Price__c=Base_Price__c=1575 (USD ABA Override leaked), EUR ListPrice 2943.99 ignored. Second SFTP combo nets $0 (row active+unapplied, no PBE fallback).",
   "fix": "Add CurrencyIsoCode to the ABA decision-table key (or seed non-USD override rows) so a USD override cannot match a non-USD line; add a no-match fallback returning the currency-matched PBE list.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view"
  },
  {
   "id": "H-01",
   "pri": "P0",
   "type": "PROCEDURE",
   "cat": "Discounts",
   "ticket": "discount-compounding class (F-07/E-03 family)",
   "regression": true,
   "title": "Manual line-level amount discount compounds across reprices",
   "step": "ManualQuoteLevelAmountBasedLineLevel consumes InputUnitPrice = NetUnitPrice (fed by SyncInputUnitPricefromNet) and subtracts the amount, so each reprice discounts the already-discounted net.",
   "expected": "Net = list \u2212 entered amount, stable on every reprice (e.g. 50000 \u2212 5000 = 45000 each time).",
   "observed": "Fresh fixture (quote 0Q0WC000003Fs1Z0AS, list 50000, amount 5000): reprice #1 net=45000, #2=40500, #3 erodes further \u2014 the 5000/10000 re-subtracts off the prior net, not the list.",
   "fix": "Re-seed the discount base from ListPrice for direct lines before the manual-amount step (mirror the F-07 \u2018Reset Net to Pre-Partner Base\u2019 / E-03 OneTime-seed pattern, extended to the non-partner case).",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fs1Z0AS/view"
  },
  {
   "id": "J-06",
   "pri": "P0",
   "type": "PROCEDURE",
   "cat": "Derived / Maintenance",
   "ticket": "SC-3346 / SC-3359",
   "regression": false,
   "title": "Partner discount on derived maintenance uses the license band, not the New-Maintenance band",
   "step": "PartnerNetPricePosthook.resolveContributorPartnerPercent returns the license contributor\u2019s PartnerDiscountPercent (Software 15%) and carries it onto the derived-maintenance line instead of the New-Maintenance band (12%).",
   "expected": "Maint net = 71 \u00d7 (1\u22120.12) = 62.48 (partner discount applied once at the New-Maintenance %).",
   "observed": "Maint NetUnitPrice = 60.35 = 71 \u00d7 (1\u22120.15): correct single application, WRONG band (15% carried from license). License net 301.75 correct. Stable across reprices (prior one-cycle lag is gone).",
   "fix": "Resolve the derived-maintenance partner % from the Quote\u2019s Partner_Pricing_Model__c via getMarginForProductType(model,'New Maintenance') instead of inheriting the contributor\u2019s license %.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdCD0A0/view"
  },
  {
   "id": "J-09",
   "pri": "P0",
   "type": "ORG-CONFIG",
   "cat": "Derived / Maintenance",
   "ticket": "SC-3372 / M5-PBEDP",
   "regression": false,
   "title": "Derived line with no PBEDP config row prices silently null",
   "step": "Native Derived Products pull (steps 41\u201342) maps the contributing product via a PriceBookEntryDerivedPrice (PBEDP) row; an IsDerived PBE with 0 PBEDP rows yields NetUnitPrice=null with no hard error.",
   "expected": "Backfill PBEDP rows for all IsDerived PBEs (or remove the native element if the Fortra formula suffices); a clear error, not a silent null.",
   "observed": "QLI 0QLWC000003KEbO4AW (GS-GSE-RNM-EF8, PBE IsDerived=true, uncovered): NetUnitPrice=null, ListPrice=0, TotalPrice=0. Only 199 of 1889 active IsDerived PBEs in the live book are PBEDP-covered.",
   "fix": "Backfill PBEDP rows for the uncovered IsDerived PBEs, or remove the native DerivedProducts element (Fortra custom formula already covers it). Config/data only.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view"
  },
  {
   "id": "J-10",
   "pri": "P0",
   "type": "ORG-CONFIG",
   "cat": "Derived / Maintenance",
   "ticket": "SC-3384",
   "regression": false,
   "title": "EUR derived-maintenance line prices $0 \u2014 IsDerived flag only on the USD PBE",
   "step": "The derived-net committer (Derived Maintenance Net Filter / Derived Products \u2013 Renewals) gates on PBE.IsDerived, which is true only on the USD PBE; the EUR PBE has IsDerived=false so the COLA-derived net is never committed.",
   "expected": "Net = priorAssetNet \u00d7 (1+COLA%) \u00d7 currencyMult, committed once; stable across reprices.",
   "observed": "EUR maint line 0QLWC000003kinW4AQ: NetUnitPrice/UnitPrice/ListPrice = 0; COLACalculatedPrice__c=3666.90 stamped but never committed. License line correct. Org-wide ALL 3453 IsDerived=true PBEs are USD.",
   "fix": "Set IsDerived=true on the non-USD PBEs for every product whose USD PBE is IsDerived=true (SC-3384 currency-completeness family). Data-only PricebookEntry fix.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZN70AO/view"
  },
  {
   "id": "K-01",
   "pri": "P0",
   "type": "PROCEDURE",
   "cat": "Edge Cases",
   "ticket": "SC-3441",
   "regression": false,
   "title": "Cancellation reprice hard-aborts on null net \u2014 no credit produced",
   "step": "StampBaseFilter (in StampContributorBasePreDiscount): criterion #5 \u2018NetUnitPrice GreaterThan 0\u2019 has no IsNull guard; condition logic \u2018(1 OR 2) AND 3 AND 4 AND 5\u2019 cannot evaluate GreaterThan on a null net \u2192 SF-BRE-00004 aborts the entire reprice.",
   "expected": "NetUnitPrice = asset net (e.g. 3000); TotalPrice = net \u00d7 \u22121 = \u22123000; header rolls up the negative credit.",
   "observed": "Reprice ERRORS at StampBaseFilter#1 (SF-Pricing-00006 / SF-BRE-00004); cancel QLI (CancelNetUnitPrice__c=15000) stays NetUnitPrice=null, TotalPrice=0, CalculationStatus=PriceCalculationFailed. Reproduced on 3 records incl. a fresh one.",
   "fix": "Add an IsNull guard to criterion #5 (e.g. \u2018(1 OR 2) AND 3 AND 4 AND (5 OR NetUnitPrice IsNull)\u2019), or exclude cancel lines via QuoteTypeText__c before the filter.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FoMA0A0/view"
  },
  {
   "id": "E-04",
   "pri": "P1",
   "type": "ORG-CONFIG",
   "cat": "Deal / Customer Type",
   "ticket": "\u2014",
   "regression": false,
   "title": "Fortra-Originated partner deals get the channel band, not Non_Orig",
   "step": "Active prehook PartnerPricingPrehook V1 calls getMarginForProductType(model, productType) with no dealType argument (reads channel columns only); the Deal_Type\u2192Non_Orig routing exists only in the dormant V2 service.",
   "expected": "Net = List \u00d7 (1 \u2212 Non_Orig_Discount%); a lower discount than channel-originated (e.g. 12% vs 15%).",
   "observed": "Quote 0Q0WC0000039bwH0AQ (Deal_Type=\u2018Fortra Originated\u2019): BoKS Perpetual net = 301.75 = 355 \u00d7 0.85 (15% channel column). Deal_Type has zero effect; all 30 Partner_Pricing_Model rows have null Non_Orig_* columns.",
   "fix": "Wire the Deal_Type-aware V2 prehook into the active plan (or pass dealType in V1) AND populate the Non_Orig_* columns on the 30 PPM rows.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view"
  },
  {
   "id": "F-09",
   "pri": "P1",
   "type": "PROCEDURE",
   "cat": "Transaction Type",
   "ticket": "SC-3384",
   "regression": true,
   "title": "Non-USD partner net double-converted (corporate FX \u00d7 hardcoded FX) \u2014 NEW regression",
   "step": "On non-USD partner lines, the partner-discount base (Pre_Partner_Price__c) is computed as USD_list \u00d7 corporate rate (0.92) BEFORE the discount, and the proc ALSO applies its single hardcoded EUR FX (CurrencyConversionNetUnitPrice seq 35, \u00d70.9346) at the end \u2014 a double conversion.",
   "expected": "Net = currency-converted list \u00d7 (1 \u2212 partner%), single FX (Cobalt Strike EUR: 5514.14 \u00d7 0.82 = 4521.59).",
   "observed": "Net = 4159.87 = (5900 \u00d7 0.92) \u00d7 0.82 \u00d7 0.9346 \u2014 understated ~8%. USD partner control (E-02) correct. This quote PASSed in run-1 at 01:47Z; V21 LastModified 05:56Z (in-place edit) \u2192 now FAILs \u2192 confirmed regression.",
   "fix": "Operate the partner discount on the raw USD list (the same base the non-partner EUR path uses) and let the single intended EUR FX step apply once; remove the corporate-rate pre-conversion from the partner base.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view"
  },
  {
   "id": "F-12",
   "pri": "P1",
   "type": "PROCEDURE",
   "cat": "Transaction Type",
   "ticket": "SC-3441",
   "regression": false,
   "title": "Mid-term amend-remove aborts \u2014 no prorated negative delta",
   "step": "Same null-unsafe StampBaseFilter as K-01; 3 of 6 instances (block lines ~109632 / 116550 / 123457) still carry \u2018(1 OR 2) AND 3 AND 4 AND 5\u2019 with criterion 5 = NetUnitPrice > 0; the amend/cancel path hits an unpatched one and aborts before the seed step runs.",
   "expected": "Credit = removed qty \u00d7 net \u00d7 remaining-term fraction (e.g. remove 50 of 100 at 6/12 months \u2192 \u2212(50 \u00d7 net \u00d7 0.5)).",
   "observed": "Force-reprice isSuccess=false, SF-BRE-00004 at StampBaseFilter#1; QLI Qty=\u221250000, NetUnitPrice=null, TotalPrice=0, PricingTermCount=null. No proration delta.",
   "fix": "Null-safe all remaining StampBaseFilter instances (add a NetUnitPrice IsNull criterion + matching condition logic), and route Amend(qty<0) lines through TermDefined proration so PTC multiplies the negative net.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FapR0AS/view"
  },
  {
   "id": "I-03",
   "pri": "P1",
   "type": "PROCEDURE",
   "cat": "Proration",
   "ticket": "SC-3420 / SC-3411",
   "regression": false,
   "title": "Mid-term Term-Defined net not prorated by fractional PTC (plain list-priced path)",
   "step": "The TermDefined net-proration leg (SubscriptionPricing95 / ListContainer93) prorates only the adjustment/discounted path; a plain list-priced TermDefined line derives the fractional PTC but never multiplies the net by it. (Confirmed by tie-breaker against the original \u2018no writer exists\u2019 mis-diagnosis.)",
   "expected": "Mid-term annual line: PTC=0.7397 (270/365) \u2192 NetTotalPrice = 250 \u00d7 3 \u00d7 0.7397 = 554.79.",
   "observed": "Clean list-priced line 0QLWC000002LCwH4AW: PTC=0.7397 derived, but NetTotalPrice AND TotalLineAmount both come out FULL = 750, stable across 3 reprices. The discounted sibling 0QLWC0000034VY94AM DOES prorate (3170.71 = 3465 \u00d7 0.9151) \u2014 proration only fires on the adjustment path.",
   "fix": "Ensure the net\u00d7PTC multiply applies to non-adjustment (plain list-priced) TermDefined lines too \u2014 gate the proration leg on SellingModelType=TermDefined regardless of whether a discount/adjustment is present.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view"
  },
  {
   "id": "A-07",
   "pri": "P2",
   "type": "ORG-CONFIG",
   "cat": "Pricing Source / Channel",
   "ticket": "SC-3346",
   "regression": false,
   "title": "Maintenance-family inconsistency \u2014 ~1497 products lack the Maintenance-Type attribute",
   "step": "Step 39 Derived Pricing Formula looks up the tier on the Maintenance Type Defn attribute; a product missing the attribute returns tier=0 \u2192 NetUnitPrice=0 (or native 100%-copy). No safe-default tier in the procedure.",
   "expected": "Every maintenance product carries Maintenance Type Defn (or a documented fallback, e.g. Standard 0.20) so the tier resolves.",
   "observed": "BoKS PASSES (has MTD): 0.20 \u00d7 355 = 71. FIM CCM FAILS (no MTD): all CCM New-Maint lines net $0/null. Only 186 of 1683 active New-Maintenance products carry MTD (~89% missing).",
   "fix": "Backfill the Maintenance_Type_Defn attribute on the ~1497 products lacking it (esp. the FIM CCM family), or add a documented Standard 0.20 default to step 39. Config/data, not a procedure bug per se.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view"
  },
  {
   "id": "G-08",
   "pri": "P2",
   "type": "ORG-CONFIG",
   "cat": "Multi-Currency / Regional",
   "ticket": "SC-3384",
   "regression": false,
   "title": "Org FX rates corrupted to 1.0 on 6 currencies (reporting/invoicing only \u2014 proc decoupled)",
   "step": "Admin-maintained CurrencyType.ConversionRate (NOT a V21 step). The pricing steps 33\u201336 are clean (they read Currency_Conversion_Formula__mdt); the defect surface is reports, DocGen FX, and Workday invoicing consolidation.",
   "expected": "Authorized rates maintained per the FX table (ARS 666.67, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.25, NZD 1.6667).",
   "observed": "6 of 11 non-USD currencies sit at placeholder 1.0; DatedConversionRate confirms ARS/CHF/GBP/JPY reset to 1.0 on 2026-02-11/12/13. Any foreign txn since consolidates at face value. Pricing proc unaffected (proven by G-01 reading the mdt).",
   "fix": "Reload CurrencyType.ConversionRate + forward-dated rows from the authoritative table and stop the 2026-02-11 reset automation. No pricing-procedure change.",
   "url": "https://fortra--uat.sandbox.my.salesforce.com/lightning/setup/CurrencySettings/home"
  }
 ],
 "corrections": [
  {
   "id": "D-09",
   "kind": "False defect caught",
   "from": "FAIL (PROCEDURE)",
   "to": "BLOCKED (TEST-DATA-ARTIFACT)",
   "fact": "Live EUR FX is 0.92 (CurrencyType + DatedConversionRate since 2026-02-13); the cited 1268.44 implies 0.9346, which exists nowhere in the org. UnitPrice stayed FROZEN across 3 fresh reprices while the net mutated \u2014 a stale persisted field, not a live V21 output. A clean reprice yields 1357.2 \u00d7 0.92 = 1248.62 (PASS). The genuine currency-idempotency concern is already captured by G-01/G-02.",
   "resolvedBy": "tie-breaker (sided with the data-audit)"
  },
  {
   "id": "I-02",
   "kind": "False defect caught",
   "from": "FAIL (claimed)",
   "to": "BLOCKED (TEST-DATA-ARTIFACT)",
   "fact": "Two identical TermDefined lines differ only in EndDate; the disputed line\u2019s null PTC is caused by a malformed off-by-one EndDate (2027-06-29 vs the org convention StartDate+1yr\u22121day = 2027-06-28). A clean control with the correct EndDate gets PTC=1 on the current V21 \u2014 the mechanism works on valid lines.",
   "resolvedBy": "tie-breaker (sided with the main verifier)"
  },
  {
   "id": "J-05",
   "kind": "False defect caught",
   "from": "FAIL (claimed)",
   "to": "BLOCKED (TEST-DATA-ARTIFACT)",
   "fact": "The \u2018missing-net\u2019 line kbxJ is bound to a QuoteAction of Type=\u2018Amend\u2019, not Renew (the only Renew-bound line is kbxK). A null net on an amend-no-change line is by-design, not a COLA-commit failure \u2014 the fixture used the wrong QuoteAction binding.",
   "resolvedBy": "tie-breaker (sided with the main verifier)"
  },
  {
   "id": "K-02",
   "kind": "Expectation corrected",
   "from": "FAIL (claimed)",
   "to": "PASS (EXPECTATION-ERROR)",
   "fact": "The catalog expected a \u2018MissingContributor\u2019 surfacing that requires step SurfaceMissingContributorK02 \u2014 which exists only in the V22 Draft, not the active V21. A null net on a lone derived line with no contributor is the documented, owner-accepted SC-3346/SC-3372 \u2018no priced node\u2019 behavior. The catalog graded V21 against an un-deployed enhancement.",
   "resolvedBy": "data-audit"
  },
  {
   "id": "K-10",
   "kind": "Expectation corrected",
   "from": "FAIL (claimed)",
   "to": "PASS (EXPECTATION-ERROR)",
   "fact": "The catalog expected ALE=14000 (negative line excluded). But Quote.ALE__c is a Formula(Number) literally = \u2018Subtotal\u2019, so a correctly-priced Qty=\u22121 credit MUST roll into ALE. V21 yields Subtotal=ALE=11200 = 14000 + (2800 \u00d7 \u22121) \u2014 arithmetically correct, no NPE, positive line uncorrupted.",
   "resolvedBy": "data-audit"
  },
  {
   "id": "I-03",
   "kind": "Real defect rescued",
   "from": "BLOCKED (verifier dismissed)",
   "to": "FAIL (PROCEDURE-DEFECT)",
   "fact": "The main verifier dismissed I-03 as a data artifact (\u2018no writer / wrong field / stale\u2019). The tie-breaker disproved that on live data: a CLEAN list-priced TermDefined line with PTC=0.7397 comes out full 750 on BOTH NetTotalPrice and TotalLineAmount; only the adjustment path prorates. The defect is real \u2014 now reported.",
   "resolvedBy": "tie-breaker (sided with the data-audit)"
  }
 ],
 "tallies": {
  "overall": {
   "PASS": 69,
   "BLOCKED": 22,
   "FAIL": 13
  },
  "byPriority": {
   "P0": {
    "PASS": 32,
    "BLOCKED": 9,
    "FAIL": 7
   },
   "P1": {
    "BLOCKED": 11,
    "PASS": 31,
    "FAIL": 4
   },
   "P2": {
    "BLOCKED": 2,
    "FAIL": 2,
    "PASS": 6
   }
  },
  "byCategory": {
   "A": {
    "PASS": 3,
    "BLOCKED": 3,
    "FAIL": 1
   },
   "B": {
    "PASS": 5,
    "BLOCKED": 3
   },
   "C": {
    "PASS": 7
   },
   "D": {
    "BLOCKED": 5,
    "PASS": 5
   },
   "E": {
    "PASS": 7,
    "FAIL": 1
   },
   "F": {
    "BLOCKED": 3,
    "PASS": 7,
    "FAIL": 2
   },
   "G": {
    "FAIL": 3,
    "BLOCKED": 2,
    "PASS": 3
   },
   "H": {
    "FAIL": 1,
    "PASS": 4,
    "BLOCKED": 1
   },
   "I": {
    "PASS": 2,
    "BLOCKED": 4,
    "FAIL": 1
   },
   "J": {
    "PASS": 10,
    "BLOCKED": 1,
    "FAIL": 3
   },
   "K": {
    "FAIL": 1,
    "PASS": 16
   }
  }
 },
 "transitions": {
  "reclassified": [
   "A-02",
   "D-01",
   "D-03",
   "D-09",
   "F-01",
   "F-04",
   "F-05",
   "I-02",
   "J-05"
  ],
  "persistent": [
   "A-07",
   "E-04",
   "F-12",
   "G-01",
   "G-02",
   "G-08",
   "I-03",
   "J-06",
   "J-09",
   "J-10",
   "K-01"
  ],
  "fixed": [
   "F-03",
   "G-04",
   "I-01",
   "K-02",
   "K-09"
  ],
  "newfail": [
   "F-09",
   "H-01"
  ]
 },
 "matrix": [
  {
   "id": "A-01",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Catalog/list-priced new line (PricingSource not LastTransaction)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "NetUnitPrice/UnitPrice resolves from PBE list price; Quantity*Price computes ItemNetTotalPrice = NetUnitPrice * Qty; discounts applied downstream",
   "actual": "QLI 0QLWC0000036BtV4AU (Cobalt Strike, TermDefined Annual, USD, Qty=2, Direct New quote): ListPrice=5900, NetUnitPrice=5900 (NET==LIST), Base_Price__c=5900, Pre_Partner_Price__c=5900, COLACalculatedPrice__c=null, NetTotalPrice=11800 (=5900*Qty 2). Force-repriced via REST place action v67.0, isSucces\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC0000036BtV4AU/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "A-02",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "LastTransaction-sourced line bypasses catalog repricing (carry-forward)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Prior-transaction/order NetUnitPrice preserved; no catalog re-derivation",
   "actual": "ADVERSARIAL RE-MEASURE 2026-06-30 (active V21 9QBWC0000000oWH4AY): both A-02 fixtures still HARD-FAIL force-reprice at StampBaseFilter#1 with SF-Pricing-00006/SF-BRE-00004 'resource has no corresponding value for evaluation'; CalculationStatus=PriceCalculationFailed; NetUnitPrice null. BUT the failu\u2026",
   "url": "",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "A-03",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Derived asset price on renewal (inherit Asset.Price, not catalog)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Renewal line UnitPrice equals the prior invoiced Asset price, not the current pricebook entry",
   "actual": "Live Force-reprice of Draft Renewal quote 0Q0WC000003FY2r0AG via REST v67.0 (isSuccess=true): Cobalt Strike QLI 0QLWC000003khwH4AQ: Asset.Price=5900, Pre_COLA_Price__c=5900, COLACalculatedPrice__c=6265.8, NetUnitPrice=6265.8, ListPrice=5900. beSECURE QLI 0QLWC000003khwI4AQ: Asset.Price=206, Pre_COLA\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FY2r0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "A-04",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Contracted/asset-sourced line stamps PricingDate",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "BLOCKED",
   "rootCause": "N-A(pass)",
   "expected": "PricingDate set from EffectiveDate; contracted price effective-date alignment applied",
   "actual": "V21 ContactedPricing branch present and correctly wired (ListContainer73 seq24: filter IsContracted IsNotNull AND IsContracted=true AND PricingDate IsNull -> ContactedPricing75 assigns PricingDate:=EffectiveDate). Force-reprice isSuccess:true, errorResponse:[]. Amend quote QLI UnitPrice=113593.66 (p\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FNXF0A4/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "A-05",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Derived non-derived exclusion from derived filters",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Standard waterfall applies; derived formula skipped",
   "actual": "Force-reprice v67.0 on quote 0Q0WC000003FTJJ0A4 (QuoteTypeText__c='New') -> isSuccess:true, errorResponse:[]. Standard QLI 0QLWC000003kdnp4AA (PBE 01uWC000005wrrIYAQ IsDerived=false, list=10000 USD, Fortra Price Book active): post-reprice NetUnitPrice=10000, ListPrice=10000, Base_Price__c=10000, Pre\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FTJJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "A-06",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Contracted-vs-catalog source switch mid-quote (IsContracted toggled / asset detach)",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Toggling IsContracted re-routes the line: contracted->catalog clears PricingDate and re-derives from PBE as-of EffectiveDate; catalog->contracted seeds PricingDate; no stale-date carryover",
   "actual": "ContactedPricing branch cannot fire: org-wide re-verify shows 1 QLI with PricingContractId set (0QLWC000003kk694AA, quote 0Q0WC000003FaZJ0A0) and 0 OrderItems. That QLI references Draft contract 800WC00000SFn6jYAD. After force-reprice through V21, IsContracted=null on both contracted L1 and catalog \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FaZJ0A0/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "A-07",
   "cat": "A",
   "category": "A. Pricing Source / Channel",
   "name": "Derived maintenance family inconsistency (BoKS vs FIM)",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "All maintenance products should carry Maintenance Type Defn; if missing, fallback should be a documented standard (e.g. Standard 20%), not variable 100% or $0",
   "actual": "ADVERSARIAL RE-VERIFY 2026-06-30 (v67.0, active V21) CONFIRMS the defect. BoKS PASSES: QLI 0QLWC000003kUpO4AU NetUnitPrice=71, Source_List_Price=355, ratio exactly 0.20, after a fresh independent Force-reprice (isSuccess:true). FIM FAILS: all FIM CCM New Maintenance lines net $0/null after a fresh i\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "B-01",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "One-Time/Perpetual selling model PricingTermCount=1",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "PricingTermCount=1; ItemNetTotalPrice = NetUnitPrice * Qty * 1; Asset.IsSubscription=false, full revenue recognized",
   "actual": "Quote 0Q0WC000003FcG90AK repriced V21 (CompletedWithPricing). QLI 0QLWC000003kli94AA: Product=Abstract (Fortra_Product_Type__c=Perpetual), Qty=2, SellingModelType=OneTime, NetUnitPrice=2200, NetTotalPrice=4400 (=2200*2*1), TotalLineAmount=4400, TotalPrice=4400, PricingTermCount=0 (by-design: ESD One\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcG90AK/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "B-02",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Term-Defined subscription (annual, renewable) with proration enabled",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Term proration computed; PricingTermCount derived (1 annual or fractional); Asset.IsSubscription=true with SubscriptionEndDate=Start+term; renewal auto-created >=90 days prior",
   "actual": "Post-V21 reprice 2026-06-30: QLI 0QLWC000003kaUz4AI Cobalt Strike Qty=1, UnitPrice=5900, NetUnitPrice=5900, ListPrice=5900, NetTotalPrice=5900, TotalLineAmount=5900, PricingTermCount=1, SellingModelType=TermDefined, StartDate=2026-06-29, EndDate=2027-06-28. Pre_Partner_Price__c=5900, Base_Price__c=5\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kaUz4AI/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "B-03",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Usage / tiered-quantity model (PhishLabs, Tripwire, Alert Logic)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Line total = Base + (attribute x multiplier) or tier price, applied per term; ItemNetTotalPrice reflects qty * term-count * unit price",
   "actual": "After Force-reprice (REST place v67.0, isSuccess=true) on V21 active 9QBWC0000000oWH4AY: QLI NetUnitPrice=400, UnitPrice=400, ListPrice=325, NetTotalPrice=400, Qty=1, PricingTermCount=1; Source_List_Price__c=400, Pre_Partner_Price__c=400, Base_Price__c=400, COLACalculatedPrice__c=null, Has_Attribute\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FXpy0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "B-04",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Evergreen subscription (SaaS, no defined term end) full-period count",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "N-A(pass)",
   "expected": "Evergreen term count applied; full evergreen period billed; no fixed-term/partial proration; Asset continues past initial term unless cancelled",
   "actual": "FortraUAT has NO priceable Evergreen product as of 2026-06-30. All 4 Evergreen ProductSellingModels (Evergreen-Monthly 0jPWC00000006C92AI, Quarterly 0jPWC00000006CA2AY, Semi-Annual 0jPWC00000006CB2AY, Yearly 0jPWC00000006CC2AY) remain Status=Inactive. Zero PSMOs map any product to those PSMs (COUNT=\u2026",
   "url": "",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "B-05",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Evergreen anytime proration (partial periods + transient end date)",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Anytime (mid-period) proration computed against the transient end date",
   "actual": "Scenario un-instantiable in FortraUAT (run3, 2026-06-30). PSMO count for Evergreen SellingModelType = 0 (0 PSMOs linked to any of the 4 Evergreen ProductSellingModel records: 0jPWC00000006C92AI Monthly, 0jPWC00000006CA2AY Quarterly, 0jPWC00000006CB2AY Semi-Annual, 0jPWC00000006CC2AY Yearly). Active \u2026",
   "url": "",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "B-06",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Evergreen renewal (auto-continue, no fixed term-end)",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Evergreen renewal carries prior net (or COLA-uplifted net), keeps evergreen term count, no fixed-term proration, no end-date derivation; asset continues",
   "actual": "UNTESTABLE on real data. FortraUAT has NO priceable Evergreen product as of 2026-06-30 (re-verified live after V21 in-place edits today). All 4 Evergreen ProductSellingModels (Evergreen-Monthly 0jPWC00000006C92AI, Quarterly 0jPWC00000006CA2AY, Semi-Annual 0jPWC00000006CB2AY, Yearly 0jPWC00000006CC2A\u2026",
   "url": "",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "B-07",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Usage/tiered model on Quote-to-Order convert + order reprice (tier re-eval on OrderItem context)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "OrderItem tier price identical to quote; matrix attribute hydrated on order context; no $0 no-match from missing order-side attribute mapping",
   "actual": "Quote QLI 0QLWC000003kjq14AA (NoU=1-50, vol=30): V21 Force-reprice -> NetUnitPrice=400, Base_Price__c=400, Attribute_Price_Mode__c='Unit Price', TotalLineAmount=400 (tier 1-50/26-50=400 correct, isSuccess=true). Positive control: Activated order OI 802WC00000OZLOlYAP (NoU=1-50, vol=20) NetUnitPrice=\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FaKn0AK/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "B-08",
   "cat": "B",
   "category": "B. Selling Model",
   "name": "Neither Evergreen nor Term-Defined (one-time) excluded from proration filters",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "No proration applied; one-time treatment",
   "actual": "Fixture QLI 0QLWC000003kjrd4AA (Quote 0Q0WC000003FaMP0A0, Product=Abstract, Fortra_Product_Type__c=Perpetual, SellingModelType=OneTime, Qty=3): V21 Force-reprice isSuccess=true, NetUnitPrice=2200, NetTotalPrice=6600 (=2200x3 exactly, no proration), TotalLineAmount=6600, PricingTermCount=0, EndDate=n\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FaMP0A0/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-01",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Hardware/Power high-quantity line (per-unit decomposition, governor-safe)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Each unit priced; ItemNetTotalPrice correct; no CPU/SOQL governor breach; appliance can link to Hardware record",
   "actual": "Order 00095656 (801WC00000lzWJFYA2, Draft): MessengerConsole OI 802WC00000PX8hxYAD - Qty=5000, UnitPrice=11487, NetUnitPrice=11487, TotalPrice=57435000 (=5000x11487), Is_Split_Line__c=false. V21 Force-reprice returned isSuccess:true, errorResponse:[]. Total OrderItems on order=35, Is_Split_Line__c=t\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000lzWJFYA2/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-02",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Maintenance product type derived pricing (new + renewal, RC_42000/43000/43120)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Maintenance net = contributor base * tier percent; new maint lines included with license, renewal lines created at asset renewal time",
   "actual": "After live Force-reprice (REST place v67.0, isSuccess=true, errorResponse=[], LastModified 2026-06-30T13:13:25Z): License line (BoKS Perpetual) NetUnitPrice=355, Source_List_Price=355, Base_Price=355; New-Maint line (BoKS-NewMaintenance, Fortra_Product_Type__c=New Maintenance) NetUnitPrice=71 (=0.20\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-03",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Software product type aggregation (perpetual, RC_41000)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Software lines summed into Total Software / Software subtotal",
   "actual": "Force-reprice through active V21 (Quote 0Q0WC0000034UvR0AU 'Test GS Quote Tim', isSuccess=true, errorResponse=[], LastModified 2026-06-30T13:13:14Z). Post-reprice: Total_Software__c=27354.0 = EXACT SUM of two Software QLIs (EFT 8 Enterprise GS-GSE-NRPS-E8EP TotalLineAmount=27354 + EFT 8 Continuum GS\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000034UvR0AU/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-04",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Services product type aggregation",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Services lines summed into Total Services bucket; no bundle/subscription splitting",
   "actual": "Quote 0Q0WC0000034UvR0AU: EFT Expert Service Standard (0QLWC000003dYeP4AU) Qty=1 NetUnitPrice=24000 NetTotalPrice=24000; Hourly Rate Sr. Consultant T&M (0QLWC000003dYeQ4AU) Qty=1 NetUnitPrice=275 NetTotalPrice=275; Total_Services__c=24275 (=24000+275). Type segregation holds: Total_Subscription__c=5\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000034UvR0AU/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-05",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Subscription product type / subscription-split aggregation (RC_41202)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Subscription lines summed into bucket; quote shows single bundle price; order creates two Workday lines (license/maintenance deferred separately)",
   "actual": "Force-reprice via REST v67.0 on Quote 0Q0WC000003FN970AG (isSuccess=true, errorResponse=[], CalculationStatus=CompletedWithPricing): 1 Subscription line DM-WCU-RSS-5250SU NetTotalPrice=2021.25; 2 Perpetual lines (2200, 3675) -> Total_Subscription__c=2021.25 (Perpetual correctly EXCLUDED). Quote 0Q0W\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FN970AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-06",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Add-on / modular feature priced separately but grouped",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Add-on line included in same group as primary product; no override unless bundle gate",
   "actual": "Confirmed on real UAT data (re-measured 2026-06-30 against active V21). Order 801WC00000hKXezYAG (Activated) contains GoAnywhere Advanced Workflows OIs with POSITIVE net: OI 802WC00000N2VEOYA3 NetUnitPrice=8152.85, OI 802WC00000N2VEIYA3 NetUnitPrice=1848.24 (prorated). Real UI-priced QLI 0QLWC000002\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000hKXezYAG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "C-07",
   "cat": "C",
   "category": "C. Product Type",
   "name": "Mixed-type quote category-bucket isolation (Software+Services+Subscription+Hardware on one quote)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Each line lands in exactly one bucket; buckets sum to Subtotal/TotalPrice; no line counted twice; empty-bucket reset (K-05) honored if a type absent",
   "actual": "Quote 0Q0WC0000034UvR0AU force-repriced via V21 (isSuccess=true, errorResponse=[], CalculationStatus=CompletedWithPricing, LMD=2026-06-30T13:15:35Z). ISOLATION HOLDS: Total_Software__c=27354 (Software lines: EFT8Enterprise 27354 + EFT8Continuum 0); Total_Services__c=24275 (Services: EFTExpertService\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000034UvR0AU/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "D-01",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute Value Pricing - Calculated Mode",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "InputUnitPrice = Base_Price__c * multiplier; base and net bridged via IF(>0) guards",
   "actual": "Fresh Force-reprice (isSuccess=true, errors=[]) on live V21 (active ESDV 9QBWC0000000oWH4AY, ctx SalesTransactionContextExt_v2 v23): disputed line 0QLWC000003kjjZ4AQ => UnitPrice=0, NetUnitPrice=0, TotalLineAmount=0, Base_Price__c=100, AttributeMultiplierPct__c=null, Source_List_Price__c=100, Pre_Pa\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kjjZ4AQ/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "D-02",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute Value Pricing - Total Price Mode (fixed-price tier lookup)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "InputUnitPrice = Base_Price__c (matrix tier price); net/base bridged with IF(>0) guards",
   "actual": "Force-reprice REST v67.0 isSuccess=true errorResponse=[]. QLI 0QLWC00000311rZ4AQ LastModifiedDate=2026-06-30T13:15:39Z. Base_Price__c=1357.2, NetUnitPrice=1357.2, UnitPrice=1357.2, Pre_Partner_Price__c=1357.2, NetTotalPrice=TotalLineAmount=TotalPrice=1357.2 (Qty=1). ListPrice=2180 (catalog) NOT used\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC00000311rZ4AQ/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "D-03",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute server-type discount config completeness (3-attribute key)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "All valid attribute combinations have config rows; {SFTP,OnPrem,NonProd} -> Net != list; Non-Production deployment -> Net = List x 0.5",
   "actual": "Fresh v67 Force-reprice (isSuccess=true, errorResponse=[]) on all 4 cited quotes reproduces: {SFTP,OnPrem,NonProd} NetUnitPrice=0; {SFTP,OnPrem,Prod} NetUnitPrice=0; {RAA,OnPrem,NonProd} NetUnitPrice=1575 (control). BUT the SFTP $0 lines carry UnitPrice=0, Source_List_Price__c=null, Base_Price__c=nu\u2026",
   "url": "",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "D-04",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "GSA pricing (GSW__c=true) at 50% of list",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "GSW=true: InputUnitPrice = ListPrice * 0.5, no partner stacking; GSW=false: catalog/attribute price retained",
   "actual": "GSW=true QLI 0QLWC000003khzV4AQ: ListPrice=10000, UnitPrice=5000, NetUnitPrice=5000, NetTotalPrice=5000, TotalLineAmount=5000, Source_List_Price__c=5000, Pre_Partner_Price__c=5000, Base_Price__c=5000, COLACalculatedPrice__c=null. GSW=false QLI 0QLWC000003khzW4AQ: ListPrice=10000, NetUnitPrice=0, Sou\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003khzV4AQ/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "D-05",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute Value Pricing - Unit Price Mode (base + multiplier)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "InputUnitPrice = Base + (attribute x multiplier) per tier with bridges; net preserved if >0",
   "actual": "Live Force-reprice REST place v67 2026-06-30T13:17:02Z of UI-built Draft QLI 0QLWC000002UWan4AG (Quote 0Q0WC000002FYt30AG, All Star qty=200): Has_Attribute_Adjustment__c=true, Attribute_Price_Mode__c='Unit Price', Base_Price__c=19.2, NetUnitPrice=19.2 (PRESERVED = Base), Pre_Partner_Price__c=19.2, N\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002UWan4AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "D-06",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute-Based Price decision-table adjustment (contracted vs catalog)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "Attribute_Based_Adjustment_Decision_Table applies adjustment to NetUnitPrice",
   "actual": "Branch cannot fire. ItemContractAttributePasId is platform-managed and transient (customMappingAllowed=false); it is hydrated ONLY when the pricing engine resolves a contracted Attribute-type PriceAdjustmentSchedule. Org has 0 contracted Attribute PAS (ScheduleType=Attribute AND ContractId set): onl\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FaZJ0A0/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "D-07",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Volume / quantity-tiered discount (PriceAdjustmentTier step-down)",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "EXPECTATION-ERROR",
   "expected": "Tier matching ordered qty applies (e.g. Qty=300 uses 251+ band, lower per-unit than 1-100 band)",
   "actual": "The native Volume Discount branch is unreachable in active V21 and cannot fire. (1) In the live V21 (run3 retrieve Jun 30 08:15, ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY VersionNumber=21), every sub-block defines VolumePASIdConstant as the empty string ('') \u2014 so the VolumeDiscountEntries BK\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FXpy0AG/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "D-08",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Bundle-based adjustment / inclusive-price bundle",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Bundle_Based_Adjustment_Decision_Table applies; inclusive bundle price set into TotalLineAmount",
   "actual": "Quote 0Q0WC000002hhJv0AI (OTP Bank renewal, 18 lines) force-repriced through V21 (pricingPref=Force, configurationMethod=Skip, v67.0): isSuccess=true, errorResponse=[], CalculationStatus=CompletedWithPricing. Bundle parent GOA-GAM-NRPS-GASBGP (GoAnywhere Starter Bundle with Gateway) QLI 0QLWC000003F\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002hhJv0AI/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "D-09",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Attribute mode crossed with currency \u2014 Total-Price tier matrix in non-USD",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Tier price read from the EUR/GBP matrix row directly (no FX double-apply); if only USD tier exists, surfaced as no-match/error not silent USD value",
   "actual": "Force-reprice through current active V21 (isSuccess:true, errorResponse:[], LastModified 2026-06-30T13:17:30Z): UnitPrice=1268.43912 = 1357.2 (USD ATPS Total-Price tier) x 0.9346 (EUR FX) exactly to 5 decimal places. Native EUR tier 1248.62 was NOT read. Overcharge = +19.81912 EUR/unit on the TotalL\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000036xy90AA/view",
   "prior": "FAIL",
   "adjudication": "Tie-breaker(audit): live EUR FX=0.92; cited 1268.44 implies 0.9346 (exists nowhere in org). UnitPrice frozen across 3 fresh reprices = stale persisted field, not a current-V21 output. A clean reprice yields 1357.2x0.92=1248.62 (PASS). Currency-idempotency concern is already captured by G-01/G-02."
  },
  {
   "id": "D-10",
   "cat": "D",
   "category": "D. Pricing Mode",
   "name": "Formula-Based pricing",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Unit price computed from the configured formula",
   "actual": "Live V21 Force-reprice 2026-06-30T13:18:29Z (CalculationStatus=CompletedWithPricing, isSuccess=true, errorResponse=[]). Quote 0Q0WC000003FY2r0AG: QLI 0QLWC000003khwH4AQ (Cobalt Strike, COLA 6.2%): NetUnitPrice=6265.8 (=5900*1.062 exact), Qty=3, NetTotalPrice=18797.4, TotalLineAmount=18797.4, TotalPr\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FY2r0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-01",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Direct sale - no partner discount (Fortra Originated)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "No partner discount applied; net stays at list/attribute price; AE approval matrix applies",
   "actual": "Repriced QLI 0QLWC000003klob4AA: Qty=5, UnitPrice=ListPrice=NetUnitPrice=$34,750; NetTotalPrice=TotalPrice=TotalLineAmount=$173,750; PartnerUnitPrice=null, PartnerDiscountPercent=null, Partner_Pricing_Model_Applied__c=null, Partner_Pricing_Source__c=null, Discount=null; Source_List_Price__c=$34,750,\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcMb0AK/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-02",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Channel/Reseller/Distributor partner discount on standard line",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Discount model: Net = List x (1-BillingPartner%); Guaranteed Margin: Net = List x (1-A%) x (1-B%); net != list",
   "actual": "Quote 0Q0WC000003FWCM0A4 / QLI 0QLWC000003kgXC4AY (CCM Limited Scan Engine, Fortra_Product_Type__c=Software, Qty=1). After Force-reprice on live V21 (isSuccess=true, no errors): Source_List_Price__c=2008, Pre_Partner_Price__c=2008, Base_Price__c=2008, PartnerDiscountPercent=15, NetUnitPrice=1706.8, \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FWCM0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-03",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Partner discount calculated but not applied on One-Time/Perpetual (SubscriptionPricing overwrite)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "One-Time line applies partner discount to final net: NetUnitPrice = InputUnitPrice x (1-PartnerDiscountPercent), persisted through subscription pricing",
   "actual": "Force-reprice of Quote 0Q0WC000003FWfO0AW (isSuccess=true, errorResponse=[]). QLI 0QLWC000003khOP4AY: NetUnitPrice=1706.8, NetTotalPrice=1706.8, TotalLineAmount=2008, ListPrice=2008, UnitPrice=2008, Quantity=1. Trace: Source_List_Price__c=2008, Pre_Partner_Price__c=2008, Base_Price__c=2008, Partner_\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FWfO0AW/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-04",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Fortra-Originated partner discount band (Non_Orig_* percents)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "Net = List x (1 - Non_Orig_Discount%); lower discount than channel-originated (e.g. 12% vs 20%)",
   "actual": "Quote 0Q0WC0000039bwH0AQ (Deal_Type__c='Fortra Originated', PartnerAccount='AB Test Partner Account', PPM-00028, BoKS Perpetual). After Force-reprice on live V21 (isSuccess=true, no errors): BoKS Perpetual QLI (0QLWC000003eoAr4AI) Qty=1, ListPrice=355, NetUnitPrice=301.75 = 355 x 0.85 (15% channel c\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "E-05",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "MSP sale - single invoice, lines grouped per end customer",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Single order/invoice to MSP; lines grouped per end customer; co-termed renewals keep grouping",
   "actual": "Force-reprice (v67.0 place, pricingPref=Force, configurationMethod=Skip) isSuccess=true, errorResponse=[]. Post-reprice (2026-06-30): line1 (Qty=3) NetUnitPrice=17463.9 NetTotalPrice=52391.7 Base_Price__c=17463.9 Pre_Partner_Price__c=17463.9 QuoteLineGroupId=1C9WC00000096J70AI; line2 (Qty=5) NetUnit\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003CTVx0AO/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-06",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "GSA (GSW=true) crossed with partner deal \u2014 no discount stacking",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Net = ListPrice*0.5 (GSA); partner percent NOT additionally applied; net != 0.5*list*(1-partner%)",
   "actual": "Quote 0Q0WC000003FO1u0AG QLI 0QLWC000003kbqs4AA (BoKS Perpetual, PBE list=355 USD, GSW__c=true, Deal_Type__c=Channel Originated, PartnerAccountId=001WC00000ZtazZYAR 15% discount): after Force-reprice V21 (isSuccess=true) -> UnitPrice=177.5 (=355*0.5 GSA fired), NetUnitPrice=301.75 (=355*0.85 partner\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kbqs4AA/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-07",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Order line-type FIXED AMOUNT vs BILLING ONLY on splits",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Quantity-split parent (qty>1 -> N qty=1, same product) stays FIXED AMOUNT (revenue recognized); only LIC/MAINT subsplit parent (different products) -> BILLING ONLY",
   "actual": "Order 00095498 (801WC00000kkTSnYAM): 3x 5250 Integrator (Is_Subsplit_Product__c=false) parent 802WC00000Onq1FYAR (Original_Order_Item__c=null) = FIXED AMOUNT; children 802WC00000Onq1GYAR + 802WC00000Onq1HYAR (Original_Order_Item__c=802WC00000Onq1FYAR) = FIXED AMOUNT. Subsplit control order 00095631 \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kkTSnYAM/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "E-08",
   "cat": "E",
   "category": "E. Deal / Customer Type",
   "name": "Partner percent resolved zero/null - no discount applied",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "No partner discount; net unchanged at list",
   "actual": "NEG case (quote 00734224, QLI 0QLWC000002ykbV4AQ): PartnerDiscountPercent=null, Fortra_Product_Type__c=Subscription, Deal_Type__c='Distributor - Fortra Originated', Product Solution_Category__c=null. After V21 Force-reprice (isSuccess=true, errorResponse:[]): NetUnitPrice=250=ListPrice=UnitPrice=Pre\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002dr050AA/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-01",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "New quote standard pricing (full waterfall)",
   "pri": "P0",
   "dataSource": "named-script",
   "preflight": "pass",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Full pricing waterfall; contributor base stamped; full list applied; subject to new-sale approval matrix",
   "actual": "Adversarial re-verification REFUTES the PROCEDURE-DEFECT. Fresh Force-reprice of the disputed Software line 0QLWC000003l0cL4AQ via active V21 (isSuccess=true, errorResponse=[]) reproduced PTC=null, NetUnitPrice=0, all contributor stamps null. BUT a CONTROLLED experiment overturns the product-type ro\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fqar0AC/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "F-02",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Renewal quote preserves prior net (no fresh contributor base)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Renewal carries prior net; NetUnitPrice not reset to 0; no fresh contributor base stamping; renewal maint SKU (RC_43000/43120) created",
   "actual": "FR6D quote (0Q0WC000003FR6D0AW): beSECURE-Cloud QLI 0QLWC000003kbZ74AI NetUnitPrice=7110.41, COLACalculatedPrice__c=7110.41 (COLA_Uplift_Percent__c=6.2%), Base_Price__c=null, TotalPrice=7110.41. Derived maint QLI 0QLWC000003kbZ84AI present (BoKS-NewMaintenance, COLACalculatedPrice=3666.9). FRPZ quot\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FR6D0AW/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-03",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "COLA uplift on renewal (LastTransaction + Renew action)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Both InputUnitPrice and NetUnitPrice uplifted by COLA%; renewal net = Asset.Price(net) x (1+COLA%); e.g. 40k net x 1.05 = 42k (not 50k list x 1.05)",
   "actual": "FY2r quote 0Q0WC000003FY2r0AG (non-partner renewal, Partner_Pricing_Model__c=null): Cobalt Strike QLI 0QLWC000003khwH4AQ: UnitPrice=6265.80, NetUnitPrice=6265.80, COLACalc=6265.80 (ListPrice=5900 x 1.062=6265.8). beSECURE QLI 0QLWC000003khwI4AQ: UnitPrice=218.772, NetUnitPrice=218.77, COLACalc=218.7\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FY2r0AG/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "F-04",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Renewal generation headless bypasses prehook chain (COLA + description null)",
   "pri": "P0",
   "dataSource": "named-script",
   "preflight": "pass",
   "verdict": "BLOCKED",
   "rootCause": "EXPECTATION-ERROR",
   "expected": "Renewal flow must trigger Reprice-All so prehook chain fires, OR move COLA + description onto a post-create trigger/flow; all renewal QLIs get COLA'd UnitPrice and formatted LineItemDescription without manual reprice",
   "actual": "ADVERSARIAL RE-VERIFY 2026-06-30 (-o FortraUAT v67): Fresh independent repro Quote 0Q0WC000003FrlR0AS via the LIVE Active Fortra_Create_Renewal_Quote flow. At generation time both QLIs had NetUnitPrice=0, TotalPrice=0, COLACalculatedPrice__c=null, Description=null; COLAUpliftHandler trigger DID fire\u2026",
   "url": "",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "F-05",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Multi-asset contract COLA override per asset (keying bug)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Each asset uses its own Contract_COLA_Override_Percent__c, not collapsed to the first match -> 4 distinct UnitPrices",
   "actual": "Adversarial re-verify on current V21 (v67.0): (1) The keying bug in AssetContractQueryHelper is REAL at the Apex code level -- live probe F05_PROBE on queryAssetContracts({RVDN,RVDO,RVDP,RVDQ}) returns rowsReturned=1 (only RVDQ survives), MISSING={RVDN,RVDO,RVDP}; buildResults Map<Id,Id> keyed by Co\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000PCpoMYAT/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "F-06",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Renewal maintenance born-net via Renew QuoteAction link",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Line born with Renew QuoteAction commits derived net (COLA pre-applied, corrected partner discount); born without it stays $0/stale and requires line re-creation to heal; No-Change is no-op",
   "actual": "Leg (a) QLI 0QLWC000003dEW24AM after V21 Force-reprice: NetUnitPrice=67.38, NetTotalPrice=67.38, TotalPrice=67.38, Source_List_Price__c=355, Pre_Partner_Price__c=60.64, COLACalculatedPrice__c=65.4, COLA_Uplift_Percent__c=7.85%, Fortra_Product_Type__c=Renewal Maintenance. QuoteAction 7ocWC00000u7yf8Y\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003dEW24AM/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-07",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Quote-to-Order convert (price lock + order-level reprice)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "OrderItem.UnitPrice matches final QuoteLineItem price; order reprice identical to quote; no contextDefinition gack; term fields populated",
   "actual": "Order 00095649 (mixed: beSECURE Subscription + Cobalt Strike Subscription): beSECURE UnitPrice=206/NetUnitPrice=206/TotalLineAmount=412/PricingTermCount=1/EndDate=2027-06-28; Cobalt Strike UnitPrice=5900/NetUnitPrice=5900/TotalLineAmount=11800/PricingTermCount=1/EndDate=2027-06-28; TotalAmount=12212\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000ltWwRYAU/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-08",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Quote->Order convert fails: Prior_* item-attributes missing from Order context",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Order reprice yields CompletedWithPricing, not 'Unable to fetch tags [-1631597440]'",
   "actual": "Force-reprice via REST place() (v67.0, pricingPref=Force, configurationMethod=Skip) on 3 Draft derived-NewMaintenance Orders all returned isSuccess=true, errorResponse=[]; CalculationStatus=CompletedWithPricing on all 4 orders (00095503/00095544/00095644 Draft + 00095651 Activated). BoKS-NewMaintena\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kvqPDYAY/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-09",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "New TermDefined subscription crossed with partner + currency at convert (term fields + discount + FX carry to order)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "OrderItem net = currency-converted list \u00d7 (1\u2212partner%) with PTC and EndDate populated; order activates without REQUIRED_FIELD_MISSING; identical to quote",
   "actual": "ADVERSARIAL RE-VERIFY 2026-06-30 on active V21 (ESDV 9QBWC0000000oWH4AY, VersionNumber 21, Status Active, LastModifiedDate 2026-06-30T05:56:50Z by Liam Jeong - AFTER run1 PASS reprice at 2026-06-30T01:47Z, confirming an in-place V21 edit between PASS and FAIL). Fresh Force-reprice (isSuccess=true, e\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-10",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Renewal generated under RLM Quote DML lock (initiateRenewal headless, no Apex Quote DML)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Renewal QLIs seeded with COLA + description without any Apex Quote DML; if a class attempts Quote DML it must be refactored to event/flow; no silent lock-swallow",
   "actual": "Run3 re-measure on 2026-06-30. Quote 0Q0WC00000382MH0AY (QuoteTypeText__c=Renewal, Status=Draft, USD). Force-reprice v67 REST place: isSuccess=true, errorResponse=[]. Post-reprice QLI 0QLWC000003dEW24AM (Renewal Maintenance): Description='Powertech Identity & Access Manager (BoKS)-RenewalMaintenance\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC00000382MH0AY/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-11",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Amend / co-term line with correct partner band",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Amend line eligible for manual quote-level discount; co-term dates honored; new-maint partner band (e.g. 17%) applied not renewal band; mid-term add/remove prorated",
   "actual": "Quote 0Q0WC0000039Vm10AE (USD, Deal_Type=Channel Originated, Partner=001WC00000ZtazZYAR, Guaranteed Margin). New-Maint Amend QLI 0QLWC000003ehR84AI: NetUnitPrice=60.35 (=71x0.85, 15% Software/contributor-carry band via posthook), NOT renewal band (10%->63.90). Perpetual QLI 0QLWC000003ehR74AI: NetUn\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039Vm10AE/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "F-12",
   "cat": "F",
   "category": "F. Transaction Type",
   "name": "Amend mid-term REMOVE/downgrade produces prorated negative delta (not cancellation, not full credit)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "Credit = removed qty \u00d7 net \u00d7 remaining-term fraction (e.g. remove 50 of 100 users at 6mo into 12mo term -> \u2212(50\u00d7net\u00d70.5)); not full-price, not full-term, not $0",
   "actual": "Force-reprice (v67 place API, pricingPref=Force, configurationMethod=Skip) aborts: isSuccess=false, SF-Pricing-00006 / SF-BRE-00004 at StampBaseFilter#1. QLI post-reprice: Qty=-50000, NetUnitPrice=null, TotalPrice=0, NetTotalPrice=null, PricingTermCount=null. No proration delta produced.",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FapR0AS/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "G-01",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Non-USD currency conversion of unit/net/total/subtotal",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "All currency outputs scaled by the per-ISO multiplier; order/invoice/Workday GL in that currency",
   "actual": "Adversarial re-verify 2026-06-30 on QLI 0QLWC000003kmG14AI (Quote 0Q0WC000003FcrF0AS 'LJ G-02 CurrABA', AAM Perpetual EUR Qty=1). NetUnitPrice=NetTotalPrice=TotalLineAmount=TotalPrice=1471.995 ALL CORRECT (= 1575 \u00d7 0.9346^1). ListPrice=2943.99 correct (EUR PBE). Base_Price__c=Source_List_Price__c=Pr\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kmG14AI/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "G-02",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Configured pricing (ABA/tier/ATPS) ignores quote currency",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "Pricing lookups must include CurrencyIsoCode in the composite key; non-USD ABA/ATPS rows + currency-matched PBE must be seeded; no currency-mismatch error",
   "actual": "V21 Force-reprice 2026-06-30T14:03:36Z (CalculationStatus=CompletedWithPricing), fresh re-measure reproduces. L1 0QLWC000003kmG14AI: Source_List_Price__c=Base_Price__c=1575 (USD ABA Override leaked into EUR line), NetUnitPrice=1471.995 EUR (=1575 USD x 0.9346 proc FX), ListPrice=2943.99 EUR ignored,\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "G-03",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Partner discount on non-USD line (discount % vs converted base ordering)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Net in target currency = currency-converted list \u00d7 (1\u2212partner%); single FX application; no USD partner% leakage",
   "actual": "Quote 0Q0WC000003Fd0v0AC / QLI 0QLWC000003kmPh4AI (CCM Limited Scan Engine, EUR, Qty 3, PartnerDiscountPercent 15, Deal_Type='Channel Originated', Partner_Pricing_Model='Discount'). Force-reprice V21 2026-06-30: isSuccess=true, errorResponse=[]. Post-reprice: UnitPrice=87347.716, NetUnitPrice=1467.5\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fd0v0AC/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "G-04",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Regional services country multiplier (AllowRegionalPricing, LIST channel only)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "List/TotalLineAmount scaled by regional multiplier and rounded to nearest 5; NetTotalPrice from catalog (structural list!=net) per documented design",
   "actual": "V21 Force-reprice 2026-06-30T (isSuccess=true, v67.0). QLI 0QLWC000003kiHF4AY: ListPrice=55000 (PBE catalog), UnitPrice=35200, TotalLineAmount=35200, NetUnitPrice=35200, NetTotalPrice=35200, Regional_NetUnit_Price__c=35200. List==Net==Regional=35200. No RegionalNetReconcileGate group in V21 (130 ste\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FYdx0AG/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "G-05",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "USD line currency conversion no-op (multiplier 1.0)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "No scaling; USD values pass through unchanged; Workday posts USD",
   "actual": "TWO Force-reprices (both isSuccess=true, errorResponse=[]) on Quote 0Q0WC000003DHXZ0A4. PASS 1 and PASS 2 both returned identical values: UnitPrice=NetUnitPrice=ListPrice=2324.15, NetTotalPrice=TotalLineAmount=TotalPrice=6972.45 (Qty=3), Quote GrandTotal=TotalPrice=Subtotal=6972.45 USD. No scaling, \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003DHXZ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "G-06",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Regional pricing disabled (AllowRegionalPricing=false) null-guard",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Standard catalog price; no regional scaling; no null-line failure on add",
   "actual": "Live V21 Force-reprice (isSuccess=true, errorResponse=[]) of USD Draft quote 0Q0WC000003Akvt0AC. Primary QLI 0QLWC000003fxOz4AI (Active Threat Sweep, Services, Qty=5): UnitPrice=3, NetUnitPrice=3, ListPrice=3, TotalLineAmount=15, NetTotalPrice=15, TotalPrice=15 = exact catalog (3) with NO regional s\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Akvt0AC/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "G-07",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "Regional services line in non-USD currency (regional multiplier AND currency conversion together)",
   "pri": "P1",
   "dataSource": "new-script",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "TotalLineAmount = round5(catalogList \u00d7 regionalMult) \u00d7 currencyMult; NetTotalPrice = catalog \u00d7 currencyMult; structural list!=net preserved in target currency; no double-FX",
   "actual": "Three fresh Apex-inserted EUR Italy fixture quotes repriced via V21 Force-reprice (all isSuccess=true, errorResponse=[]): Quote 0Q0WC000003Fr770AC / QLI 0QLWC000003l16z4AA; Quote 0Q0WC000003Fr5V0AS / QLI 0QLWC000003l15N4AQ; prior-run Quote 0Q0WC000003Fakb0AC / QLI 0QLWC000003kkFp4AI. All three produ\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fr770AC/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "G-08",
   "cat": "G",
   "category": "G. Multi-Currency / Regional",
   "name": "FX rates / legal-entity dispatch on non-core currencies",
   "pri": "P2",
   "dataSource": "config-query",
   "preflight": "na",
   "verdict": "FAIL",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "Authorized currency rates maintained per Confluence table; reports/DocGen use CurrencyType.DecimalPlaces (JPY=0); correct legal entity drives currency/Workday ref (e.g. Japan->Fortra Japan KK JPY)",
   "actual": "CurrencyType.ConversionRate corrupted on 6 of 11 non-USD currencies (all at placeholder 1.0): ARS=1.0 (auth 666.6667), CHF=1.0 (auth 0.8850), GBP=1.0 (auth 0.7874), ILS=1.0 (auth 3.6251), JPY=1.0 (auth 149.2537), NZD=1.0 (auth 1.6667). DatedConversionRate (Advanced Currency Mgmt ON) confirms ARS/CHF\u2026",
   "url": "https://fortra--uat.sandbox.my.salesforce.com/lightning/setup/CurrencySettings/home",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "H-01",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Manual quote-level amount-based (line-level) discount",
   "pri": "P0",
   "dataSource": "new-script",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "Net = list - entered amount; ItemNetTotalPrice recomputed",
   "actual": "ADVERSARIAL RE-MEASURE on a FRESH fixture (not the reused run2/run3 record) confirms the defect: built fresh Draft quote 0Q0WC000003Fs1Z0AS / QLI 0QLWC000003l1zp4AA (list=50000, DiscountAmount=5000, Qty=2, USD, non-derived OneTime). Reprice #1 (Force) -> NetUnitPrice=45000, NetTotalPrice=90000, Tota\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fs1Z0AS/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "H-02",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Manual quote-level percent (line-level) discount with approval gate",
   "pri": "P0",
   "dataSource": "named-script",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Net = List x (1-percent); marked 'Sales Rule Broken' and routed for approval if authority exceeded",
   "actual": "Post Force-reprice fresh QLI 0QLWC000003l1Bp4AI: NetUnitPrice=1750, TotalPrice=7000, NetTotalPrice=7000 (=1750x4). UnitPrice/ListPrice=2500, TotalLineAmount=10000 (pre-discount list x qty). Discount=30, Qty=4. Source_List_Price__c=null, Pre_Partner_Price__c=null, Base_Price__c=null. Reprice isSucces\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fr8j0AC/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "H-03",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Manual discount on derived maintenance line",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Manual discount applied to derived net without breaking contributor base",
   "actual": "Maintenance QLI 0QLWC000003kUpO4AU: Discount=20, NetUnitPrice=56.8 (=71x0.80), UnitPrice=71, NetTotalPrice=56.8, Pre_Partner_Price__c=71, Base_Price__c=355, Source_List_Price__c=355, Fortra_Product_Type__c='New Maintenance'. License QLI 0QLWC000003kUpN4AU: NetUnitPrice=355, Fortra_Product_Type__c='P\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "H-04",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Derived line excluded from standard manual + partner discount",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Standard discount steps skip the derived line; only derived-maintenance manual/partner paths apply",
   "actual": "E-02 quote (0Q0WC000003FO1u0AG) fresh V21 reprice 2026-06-30: derived maint line 0QLWC000003kbqr4AA (PIA-PIA-RNM-PIAMBK, New Maintenance, PartnerDiscountPercent=15) -> NetUnitPrice=60.35 = 71*0.85 (single 15% via Post-Procedure path), Partner_Pricing_Source__c='System Calculated (Post-Procedure)', P\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FO1u0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "H-05",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Manual percent + volume-tier + partner discount stacking order on one line",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Net = list \u00d7 volumeTierFactor \u00d7 (1\u2212partner%) \u00d7 (1\u2212manual%) applied once each in order; no step re-reading list and clobbering a prior discount",
   "actual": "Preflight FAIL: test_setup is unsatisfiable. (1) Live V21 (ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY, Status=Active, LastModifiedDate=2026-06-30T05:56:50) has VolumePASIdConstant='' (empty) \u2014 the Volume Discount Entries step (VolumeDiscountEntries, actionType=VolumeDiscount) passes '' as Pri\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FO1u0AG/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "H-06",
   "cat": "H",
   "category": "H. Discounts",
   "name": "Attribute discount entries",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Attribute discount adjustment applied to NetUnitPrice",
   "actual": "Force-reprice via REST place v67.0 (isSuccess=true, errorResponse=[], salesTransactionId=0Q0WC000003FXZp0AO, LastModifiedDate=2026-06-30T13:37:08Z) of existing UI-attributed QLI 0QLWC000003khUt4AI {AAMP, 3 IsPriceImpacting attrs: RAA / On Premise / Non-Production} on Quote 0Q0WC000003FXZp0AO: NetUni\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003khUt4AI/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "I-01",
   "cat": "I",
   "category": "I. Proration",
   "name": "Term-Defined line derives PricingTermCount via Proration step",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Fresh reprice derives PricingTermCount=1 (or fractional) and EndDate automatically; both carry to OrderItem on convert; CalculationStatus=CompletedWithPricing",
   "actual": "PricingTermCount=1, EndDate=2027-06-28 (StartDate=2026-06-29, SubscriptionTerm=1), CalculationStatus=CompletedWithPricing; Base_Price__c=5900, Pre_Partner_Price__c=5900; NetUnitPrice=5900; Fortra_Product_Type__c=Subscription, SellingModelType=TermDefined. Quote 0Q0WC000003FPvd0AG / QLI 0QLWC000003ka\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FPvd0AG/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "I-02",
   "cat": "I",
   "category": "I. Proration",
   "name": "Quote->Order convert fails on null PricingTermCount/EndDate",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Root fix at quote tier so null never reaches order; convert succeeds and order activates without manual EndDate/PTC; backstop is emergency-only",
   "actual": "Adversarial re-measure REFUTES the PROCEDURE-DEFECT classification. Active V21 (9QBWC0000000oWH4AY, Status=Active) DOES write PricingTermCount=1 for TermDefined lines: 13 TermDefined QLIs CREATED after V21 became active (CreatedDate >= 2026-06-29T18:55:54Z, i.e. born entirely under V21) all carry Pr\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FaO20AK/view",
   "prior": "FAIL",
   "adjudication": "Tie-breaker(main): disputed null PTC caused by malformed off-by-one EndDate (2027-06-29 vs org convention 2027-06-28); identical control line with correct EndDate gets PTC=1 on current V21. Mechanism works on valid lines."
  },
  {
   "id": "I-03",
   "cat": "I",
   "category": "I. Proration",
   "name": "Mid-term Term-Defined proration (fractional PTC)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "Mid-term sale of an annual subscription computes fractional PricingTermCount (e.g. 0.5 for 6 months); net prorated; add/remove seats charged/refunded prorata",
   "actual": "REFUTED on active V21 (label 'Rev Mgmt Default Pricing V21', versionNumber 21, Status=Active, design 9QAWC0000003mg14AA). Three Force-reprices via v67.0 REST all isSuccess=true. (1) Executor defectStep is metadata-false: V21 DOES contain a TermDefined net-proration multiply leg. Step SubscriptionPri\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC0000034VY94AM/view",
   "prior": "FAIL",
   "adjudication": "Tie-breaker(audit): clean list-priced TermDefined line, PTC=0.7397 (270/365); NetTotalPrice AND TotalLineAmount both come out full 750 (not prorated 554.79), stable across reprices. Net never multiplied by fractional PTC."
  },
  {
   "id": "I-04",
   "cat": "I",
   "category": "I. Proration",
   "name": "Evergreen anytime / partial-period proration (monthly, mid-month cancel)",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "N-A(pass)",
   "expected": "Partial-period amount computed against end date (e.g. cancel day 15 of 30 of 4000 GBP -> 2000 refund; order 1/15 monthly -> first month prorated)",
   "actual": "UNTESTABLE: FortraUAT catalog has ZERO Evergreen-configured data. ProductSellingModel WHERE SellingModelType='Evergreen' returns 4 model records (Evergreen-Monthly 0jPWC00000006C92AI, Evergreen-Quarterly 0jPWC00000006CA2AY, Evergreen-Semi-Annual 0jPWC00000006CB2AY, Evergreen-Yearly 0jPWC00000006CC2A\u2026",
   "url": "",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "I-05",
   "cat": "I",
   "category": "I. Proration",
   "name": "Pricing effective dates resolution",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "PricingDate correctly set; downstream proration/price-book uses the correct date (e.g. order 1/1, lines start 2/1 -> Feb pricebook)",
   "actual": "V21 proc mechanism confirmed wired and unchanged in fresh V21 (LastModified 2026-06-30T05:56): (1) ContactedPricing gate (AdvancedListFilter, seqNum=1 of ListContainer77): IsContracted=true AND PricingDate IsNull -> passes to seed step. (2) ContactedPricing79 (AssignmentElement renamed from Contacte\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FPvd0AG/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "I-06",
   "cat": "I",
   "category": "I. Proration",
   "name": "Co-termination proration to existing contract end-date (add aligns to anchor term-end)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "PricingTermCount = (anchorEnd \u2212 start)/fullTerm; net prorated to the shared end-date; renewal then co-terms all lines together",
   "actual": "Force-reprice of Quote 0Q0WC000002DWNV0A4 via REST v67 place action (pricingPref=Force, configurationMethod=Skip): isSuccess=true, errorResponse=[]. Control QLI 0QLWC000002SYdV4AW (TermDefined, Fortra_Product_Type__c=Subscription, USD, list/net=$250, Start=2026-04-15, anchor EndDate=2027-03-31): PTC\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002SYdV4AW/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "I-07",
   "cat": "I",
   "category": "I. Proration",
   "name": "Full-period (no partial proration)",
   "pri": "P2",
   "dataSource": "config-query",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "Full-period count used; no fractional proration",
   "actual": "Branch is present and correctly structured in live V21 (re-verified 2026-06-30). FortraUAT has ZERO Evergreen lines anywhere: SELECT COUNT(Id) FROM QuoteLineItem WHERE ProductSellingModel.SellingModelType='Evergreen' = 0; SELECT COUNT(Id) FROM OrderItem WHERE ProductSellingModel.SellingModelType='Ev\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/setup/RevenueManagementProcedures",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "J-01",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Derived non-renewal new-maintenance tier formula",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Net = tierPct(AttributeValue) x base (Base_Price__c, else Pre_Partner_Price, else InputUnitPrice fallback)",
   "actual": "After V21 Force-reprice (2026-06-30T13:40:49Z): maint PIA-PIA-RNM-PIAMBK NetUnitPrice=71, NetTotalPrice=71, TotalPrice=71, TotalLineAmount=71, Source_List_Price__c=355, Base_Price__c=355, Pre_Partner_Price__c=null, Partner_Pricing_Source__c='System Calculated (Post-Procedure)', COLA_Uplift_Percent__\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-02",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Derived formula tier percentages by support level (7-tier completeness)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Correct tier percent per AttributeValue; missing MTD -> documented standard, not silent $0; formula must cover all 8 Maintenance_Rate__mdt tiers",
   "actual": "Force-reprice (v67 place action, pricingPref=Force) on quote 0Q0WC000003Fd2X0AS 2026-06-30: license NetUnit=355 (Source_List_Price__c=355); Standard QLI 0QLWC000003kmSw4AI NetUnit=71 (AttributeValue=Standard, Maintenance_Rate__mdt Standard Rate=0.20); Expert QLI 0QLWC000003kmSx4AI NetUnit=124.25 (At\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fd2X0AS/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-03",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Derived renewal carries prior NetUnitPrice (no tier recompute) + reset on non-renewal",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Renewal net = prior NetUnitPrice (tier recompute suppressed); non-renewal NetUnitPrice cleared to 0 then recomputed",
   "actual": "RENEWAL 0QLWC000003dEW24AM (Quote 0Q0WC00000382MH0AY, QuoteTypeText=Renewal, Fortra_Product_Type=Renewal Maintenance): post-V21-reprice NetUnitPrice=67.38 HELD (prior net carried, NOT 0.20x60.64=12.13 tier; COLACalculatedPrice=65.4 at 7.85% COLA but override suppressed). GrandTotal=67.38. NON-RENEWA\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC00000382MH0AY/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-04",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "COLA uplift on derived renewal net via prehook seed (commit, no $0)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Renewal net = Asset.Price x (1+COLA%) (solution-category-matched from COLA_Uplift_Rules__mdt); both unit and net reflect uplift; no $0 commit",
   "actual": "Force-reprice v67.0 on Quote 0Q0WC000003FY2r0AG (2026-06-30, V21 active): Cobalt Strike 0QLWC000003khwH4AQ COLA_Uplift_Percent__c=6.2%, ListPrice=5900, COLACalculatedPrice__c=6265.8, UnitPrice=6265.8, NetUnitPrice=6265.8, NetTotalPrice=18797.4 (qty=3); beSECURE 0QLWC000003khwI4AQ COLACalculatedPrice\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FY2r0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-05",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "COLA renewal net oscillation / double-discount on partner maintenance",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "fail",
   "verdict": "BLOCKED",
   "rootCause": "TEST-DATA-ARTIFACT",
   "expected": "COLA renewal net stabilizes at correct value (e.g. base 71 x 1.0785 = 67.38 with prior 12% already netted), not oscillating 67.38<->60.64",
   "actual": "Re-measured live on FortraUAT v67.0 (3 fresh Force-reprices, 2026-06-30): kbxJ NetUnitPrice=null, COLACalc=3666.90; kbxK NetUnitPrice=1453.470725671872, COLACalc=5830.54. Stable run-to-run (executor's no-oscillation reproduced). The posthook DOES build correct commit values (prior log 07LWC00000PfR1\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FRPZ0A4/view",
   "prior": "FAIL",
   "adjudication": "Tie-breaker(main): kbxJ bound to QuoteAction Type='Amend' (not Renew); null net is by-design for an amend line, not a COLA-commit failure. Fixture used wrong QuoteAction binding."
  },
  {
   "id": "J-06",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Partner discount on derived maintenance (non-renewal, applied once)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "Partner discount applied once to derived net; no double discount",
   "actual": "Maint NetUnitPrice = 60.35 = 71*(1-0.15). Wrong band: 15% Software band carried from license contributor PartnerDiscountPercent instead of 12% New Maintenance band. PartnerDiscountPercent on maint QLI stamped 15. License net = 301.75 correct. Quote TotalPrice = 362.10. Stable across fresh reprices (\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdCD0A0/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "J-07",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "New-maintenance net posthook fallback when procedure yields $0",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Net = Source_List_Price x Maintenance_Rate(MTD tier) x (1-partner%) x (1-software%); posthook finalizes after procedure",
   "actual": "After Force-reprice on V21 (2026-06-30T13:44:14Z): maint QLI 0QLWC000003kiZ04AI Fortra_Product_Type__c=New Maintenance, Source_List_Price__c=355, QLIA Maintenance_Type_Defn=Standard, UnitPrice=0, ListPrice=0 (procedure $0 as expected), NetUnitPrice=71, NetTotalPrice=71, TotalLineAmount=71, Partner_P\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZ0X0AW/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-08",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Contributor base stamping (pre-discount) for non-derived non-renewal",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Base_Price__c/Pre_Partner_Price__c stamped from net for downstream derived lines",
   "actual": "Quote 0Q0WC000003FZ0X0AW force-repriced through V21 (2026-06-30). License QLI 0QLWC000003kiYz4AI: NetUnitPrice=355, Base_Price__c=355, Pre_Partner_Price__c=355 (stamped from net). Maint QLI 0QLWC000003kiZ04AI: NetUnitPrice=71 (=0.20x355), Source_List_Price__c=355. QuoteTypeText__c=null (not Renewal)\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZ0X0AW/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-09",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Native derived pull requires contributing-product config (PBEDP)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "Backfill PBEDP rows for all IsDerived PBEs, or remove the native element after confirming the formula suffices; clear error not silent null",
   "actual": "V21 Force-reprice (2026-06-30, fresh, independent re-measure) of Quote 0Q0WC0000029Agw0AE / QLI 0QLWC000003KEbO4AW (GS-GSE-RNM-EF8, Fortra_Product_Type__c=New Maintenance, PricebookEntry.IsDerived=true) returned: NetUnitPrice=null, ListPrice=0, UnitPrice=0, TotalLineAmount=null, TotalPrice=0, NetTot\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "J-10",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Derived maintenance renewal crossed with partner AND COLA AND non-USD simultaneously (four-factor stack)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "ORG-CONFIG-DEFECT",
   "expected": "Net = priorAssetNet \u00d7 (1+COLA%) \u00d7 (1\u2212partner% if not already in base) \u00d7 currencyMult, applied once each; stable across multiple reprices; no oscillation, no double-discount, no USD-value leak",
   "actual": "NetUnitPrice=0, NetTotalPrice=0, UnitPrice=0, ListPrice=0 on the derived EUR maint line (QLI 0QLWC000003kinW4AQ) after a fresh Force-reprice through active V21 (2026-06-30, isSuccess:true, errorResponse:[]). COLACalculatedPrice__c=3666.90 is stamped (COLA step fires) but never committed to NetUnitPr\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZN70AO/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "J-11",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Zero-price contributing product -> $0 derived maintenance",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Contributing license must have non-zero list in the relevant pricebook/currency, OR formula uses contract/prior/override base; explicit $0 with explanation if intended",
   "actual": "Force-reprice via REST place v67.0 (isSuccess=true, errorResponse=[]). License QLI 0QLWC000003kkXZ4AY (GS-GSE-NRPS-E8CP, Perpetual): UnitPrice=0, NetUnitPrice=0, ListPrice=0, Source_List_Price__c=null, Pre_Partner_Price__c=null, Base_Price__c=null. Derived maint QLI 0QLWC000003kkXa4AI (GS-GSE-RNM-EF\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fb2L0AS/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-12",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Native pull reads asset COLA/override priority order",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Configured COLA % applied in priority order (e.g. Asset line override 8% overrides CMDT default 5%)",
   "actual": "V21 Force-reprice (REST /services/data/v67.0/connect/rev/sales-transaction/actions/place, isSuccess=true, errorResponse=[] on all 4 quotes) confirmed all three priority tiers correct on 2026-06-30: TIER 1 LINE OVERRIDE: (a) QLI 0QLWC000003abKH4AY (5250 Integrator, Doc Mgmt, CMDT=7.85%): COLA_Uplift_\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000035P8v0AE/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-13",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Derived maintenance net filter aggregation",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Derived maintenance net captured in the correct aggregate bucket",
   "actual": "Fresh Force-reprice via V21 (REST place isSuccess:true, errorResponse:[], repriced 2026-06-30T13:46:43Z). Quote 0Q0WC000003FKRJ0A4: license PIA-PIA-NRPS-PIAP (Fortra_Product_Type=Perpetual, PBE IsDerived=false) NetUnitPrice=NetTotalPrice=355; derived maint PIA-PIA-RNM-PIAMBK (Fortra_Product_Type=New\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "J-14",
   "cat": "J",
   "category": "J. Derived / Maintenance Pricing",
   "name": "Out-year / MyCAP multi-year COLA inert (design drift)",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Either wire Final_Year prices into the procedure for Y2/Y3 billing, or confirm out-year stays flat (single-year per spec, agreed out-of-scope)",
   "actual": "CONFIRMED inert / single-year flat on live active V21 (9QBWC0000000oWH4AY). Quote 0Q0WC000002lf6b0AA QLI 0QLWC0000037ljd4AA (Active Defense BEC Threat Intelligence Service, Subscription, SubscriptionTerm=36, PricingTermCount=36): COLA_Uplift_Percent__c=5, COLA_Outyear_Uplift_Percent__c=3. Pre_COLA_P\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002lf6b0AA/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-01",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Cancellation negative credit at asset NET (not $0)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "FAIL",
   "rootCause": "PROCEDURE-DEFECT",
   "expected": "NetUnitPrice=asset net (e.g. 3000); TotalPrice = NetUnitPrice x -1 = -3000; quote/order header rolls up the negative credit",
   "actual": "Force-reprice ERRORS at StampBaseFilter#1 (SF-Pricing-00006 / SF-BRE-00004). Fresh cancel QLI (CancelNetUnitPrice__c=15000, NetUnitPrice=null) stays NetUnitPrice=null, TotalPrice=0. CalculationStatus=PriceCalculationFailed. Reproduced on 3 independent records: prior quotes 0Q0WC000003FZ290AG (QLI 0Q\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FoMA0A0/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "K-02",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "No-priced-node / missing-contributor derived line surfaced",
   "pri": "P0",
   "dataSource": "named-script",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "EXPECTATION-ERROR",
   "expected": "Formula tries Pre_Partner/InputUnitPrice; if all 0, net=0 flagged as missing contributor (not silently accepted)",
   "actual": "Fresh Force-reprice 2026-06-30 via active V21 on 0Q0WC000003FZ5N0AW: isSuccess=true, errorResponse=[] (NO native error/banner), CalculationStatus=CompletedWithPricing. Line PIA-PIA-RNM-PIAMBK (QLI 0QLWC000003kidp4AA): NetUnitPrice=null, NetTotalPrice=null, TotalLineAmount=null, Base_Price__c=null, P\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZ5N0AW/view",
   "prior": "FAIL",
   "adjudication": "Data-audit: the 'MissingContributor surfacing' expected by the catalog requires step SurfaceMissingContributorK02 which exists only in V22 Draft, not active V21. Null net on a lone derived line w/o contributor is documented owner-accepted SC-3346 A2 / SC-3372 'no priced node'. Catalog graded active V21 against an un-deployed enhancement."
  },
  {
   "id": "K-03",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Large-order governor safety (30+ lines / high-qty Power)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Order reprice/complete succeeds; no SOQL:101, CPU limit, or 'too many DML' error",
   "actual": "Order 00095656 (801WC00000lzWJFYA2): 35 OrderItems incl MessengerConsole qty=5000. TWO REST Force-reprice calls (Order PATCH, v67.0) both returned isSuccess=true, errorResponse=[]. qty=5000 Power line NetUnitPrice=11487, NetTotalPrice=57435000 (11487x5000). Line count stable at 35 after both reprice\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000lzWJFYA2/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-04",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Workday extendedAmount channel mismatch (list vs net)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "extendedAmount == header contract amount (both net); line internally consistent OR Mule maps net-only; no 'Contract Amount and Contract Line Revenue Amount must be equal' error",
   "actual": "Pre-fix repro 00095381 (2026-06-08): TotalLineAmount=3150 (list) vs NetTotalPrice=2835 (net), Workday_Sync_Status=Failure, message='Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.' (K-04 defect confirmed). Regional reconcile 00095398 (2026-06-09): AllowRegionalPric\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kML51YAG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-05",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Order-tier reprice BEFORE Activate vs Convert-with-auto-activate race (reprice ordering)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Order-level reprice completes (CompletedWithPricing, contributor base + term fields stamped) BEFORE Activate; no INVALID_INPUT; auto-activate path waits for reprice",
   "actual": "Order 00095621 (00095621, Services/Accelerated Qty=61 UnitPrice=$1 NetUnitPrice=$1 NetTotalPrice=$61): Force reprice returned isSuccess=true errorResponse=[]; CalculationStatus=CompletedWithPricing. Order 00095635 (5250 Integrator Subscription, EndDate=2027-06-27 PricingTermCount=1): Force reprice r\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000lhZivYAE/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-06",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Zero-dollar / null-missing pricing line safe handling",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "$0 line displays 0.00 with no validation error, included in order/invoice; missing-PBE warns 'No pricing found' or defaults $0, no exception",
   "actual": "REST place Force reprice isSuccess=true errorResponse=[]. $0 line 0QLWC000003kmfq4AA: UnitPrice=0, NetUnitPrice=0, TotalPrice=0, NetTotalPrice=0, ListPrice=0, Source_List_Price__c=null, Pre_Partner_Price__c=null, Base_Price__c=null (expected: no meaningful stamp on $0 line). Anchor 0QLWC000003kmfp4A\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdDp0AK/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-07",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Co-owned version churn drops logic deltas (V16 vs V20 reconcile)",
   "pri": "P0",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Co-owned versions fully validated against the prior version's logic tree before activation; TermDefined/COLA/Derived branches verified end-to-end; always retrieve live before editing",
   "actual": "Force-reprice (v67.0, isSuccess:true) on Quote 0Q0WC000003FZVB0A4 (Q-K07 DERIVED 3TIER REGRESSION K07-030873): Basic=53.25, Standard=71, Expert=124.25, Premium=85.2 - all match expected exactly. Source_List_Price__c=355 on all 4 derived lines. TermDefined control line 0QLWC000003jN8P4AU (Abstract Su\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZVB0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-08",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Cancellation of a derived/maintenance line credits derived asset NET (not list, not license net)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "NetUnitPrice = maintenance asset net (e.g. 67.38); TotalPrice = \u221267.38; not \u2212(license net) and not \u2212(tier%\u00d7list at current catalog)",
   "actual": "Post-reprice V21 (2026-06-30 Force, v67.0, isSuccess=true): QLI 0QLWC000003kkfd4AA Qty=-1, NetUnitPrice=71, TotalPrice=-71, NetTotalPrice=-71, TotalLineAmount=-71, ListPrice=0, Source_List_Price__c=355 (license list stamped but not used), CancelNetUnitPrice__c=71 (seeded from maintenance asset NET).\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FbFF0A0/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-09",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Stale category totals when group empty (Total_Services__c / Total_Software__c)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Empty category -> Total_X__c=0/null on every reprice; pick a unified base so Subtotal matches TotalPrice semantics; Discount% explicit not phantom",
   "actual": "Controlled USD quote 0Q0WC000003FbGr0AK (1 Software/BoKS Perpetual line, Services+Subscription groups EMPTY): seeded Total_Services__c=777, Total_Subscription__c=888 (stale), then V21 Force-reprice (isSuccess=true, errorResponse=[]). RESULT: Total_Services__c->0 (reset, was 777), Total_Subscription_\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FbGr0AK/view",
   "prior": "FAIL",
   "adjudication": ""
  },
  {
   "id": "K-10",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Null-safe filter excludes negative/null qty from positive aggregation",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "EXPECTATION-ERROR",
   "expected": "Negative/null qty excluded from the null-safe aggregate; no NPE",
   "actual": "V21 fresh Force-reprice (isSuccess=true, errorResponse=[], responseError=null, CalculationStatus=CompletedWithPricing) on quote 0Q0WC000003FbDd0AK: posLine 0QLWC000003kke14AA (Qty=5) -> NetUnitPrice=2800, TotalLineAmount=14000, Subtotal=14000. negLine 0QLWC000003kke24AA (Qty=-1) -> NetUnitPrice=2800\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FbDd0AK/view",
   "prior": "PASS",
   "adjudication": "Data-audit: catalog expected ALE=14000 (negative excluded) is wrong. Quote.ALE__c is Formula(Number)='Subtotal'; a correctly-priced Qty=-1 credit (net x -1) MUST roll into ALE. V21 yields Subtotal=ALE=11200=14000+(2800x-1), arithmetically correct; no NPE; positive line uncorrupted."
  },
  {
   "id": "K-11",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Qty=0 auto-add middle maintenance line ($0 but correct net)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Line born with qty>0 so net unit correct and ItemNetTotalPrice = qty x net (not 0); line type (Amend new-biz / Renew renewal) matches quote action",
   "actual": "SMOKE (savepoint+rollback) on defect line 0QLWC000003d2QR4AY (quote 0Q0WC0000037rFZ0AY): BEFORE qty=0.00 startQty=1.00 action=No Change netUnit=71.00 netTotal=0.00 -> AFTER qty=1.00 startQty=0.00 action=Amend netUnit=71.00 expectedTotal=71.0000 (normalizedQtyToSourceAsset=true, startQtyZeroed=true, \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000037rFZ0AY/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-12",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Second-click stale-context on tiered/attribute line",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Correct price after a single reprice; no one-cycle lag",
   "actual": "Single Force-reprice (pricingPref=Force, configurationMethod=Skip) on quote 0Q0WC000002gBPJ0A2 returned isSuccess=true, errorResponse=[]; QLI 0QLWC00000311rZ4AQ: NetUnitPrice=1357.2, UnitPrice=1357.2, Base_Price__c=1357.2, Pre_Partner_Price__c=1357.2, TotalPrice=1357.2, ListPrice=2180, Fortra_Produc\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002gBPJ0A2/view",
   "prior": "BLOCKED",
   "adjudication": ""
  },
  {
   "id": "K-13",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Sync InputUnitPrice when null (discount-base safety)",
   "pri": "P1",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "InputUnitPrice hydrated from NetUnitPrice; discount math safe",
   "actual": "Force-reprice on BoKS demo Quote 0Q0WC000003FKRJ0A4 (non-derived Perpetual line 0QLWC000003kUpN4AU): isSuccess=true, errorResponse=[]. Post-reprice: NetUnitPrice=355, UnitPrice=355, ListPrice=355, NetTotalPrice=355, TotalLineAmount=355, Source_List_Price__c=355, Pre_Partner_Price__c=355, Base_Price_\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-14",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Flow fault handler surfaces real RLM error (not 'unhandled fault')",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "na",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Activating a termed line with null PTC via Update Status shows a clear 'PricingTermCount required' message so the user can Reprice",
   "actual": "LIVE active flow = V16 (FlowDefinition 300WC00000PCNSHYA5, ver 301WC00000lTjmsYAC, Status=Active). Retrieved live metadata (2026-06-30 via sf project retrieve start -o FortraUAT -m Flow:Fortra_Order_Submission_Check) confirms exactly 2 <recordUpdates> elements and exactly 2 <faultConnector> blocks (\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000knHDLYA2/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-15",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Context-definition version parity quote vs order (shared SalesTransactionContextExt_v2)",
   "pri": "P1",
   "dataSource": "config-query",
   "preflight": "na",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Quote and converted order both use the same context version; field API names match schema; re-sync context if fields not hydrating; no contextDefinition gack",
   "actual": "CONFIRMED. V21 (9QBWC0000000oWH4AY) is the sole Active ExpressionSetDefinitionVersion (V22 = Draft, all others Inactive). SalesTransactionContextExt_v2 (11OWC000002m21Z2AQ) has exactly ONE active ContextDefinitionVersion: v23 (11pWC000002TjF7YAK, IsActive=true). Exactly 2 PricingActionParameters bin\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FO1u0AG/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-16",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Delete-group / sparse-context robustness (no proc-side NPE)",
   "pri": "P2",
   "dataSource": "existing",
   "preflight": "pass",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "No procedure-side NPE on a missing context node; the 'Delete Group' Map.get NPE is platform-side (config/context edge), not fixable in the procedure",
   "actual": "Force-reprice (pricingPref:Force, configurationMethod:Skip) of canonical SC-3473 repro quote 0Q0WC000002U2020AC via v67.0 place API returned isSuccess:true, errorResponse:[], CalculationStatus=CompletedWithPricing. All 4 QLIs priced: 2x Suspicious Email Intelligence (TermDefined) NetUnitPrice=20000,\u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002U2020AC/view",
   "prior": "PASS",
   "adjudication": ""
  },
  {
   "id": "K-17",
   "cat": "K",
   "category": "K. Edge Cases",
   "name": "Inactive version delete blocked by PricingActionParameters reference",
   "pri": "P2",
   "dataSource": "config-query",
   "preflight": "na",
   "verdict": "PASS",
   "rootCause": "N-A(pass)",
   "expected": "Leave inactive versions Inactive (accepted clutter); to delete, coordinate Support to null PricingActionParameters.PricingProcedure first then re-create PAP rows",
   "actual": "Live FortraUAT 2026-06-30: ExpressionSet Rev_Mgmt_Default_Pricing_Procedure (9QLWC0000015cDl4AI) now has 22 versions (V22 9QMWC00000025TR4AY added 2026-06-30, inactive). V21 (9QMWC00000025LN4AY) remains the SOLE active version; V1-V20 + V22 all inactive. EXACTLY 2 PricingActionParameters rows still \u2026",
   "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/setup/PricingProcedures",
   "prior": "PASS",
   "adjudication": ""
  }
 ],
 "fixtures": {
  "note": "~30 new/updated Apex fixture scripts under scripts/apex/setup*TestData.compact.apex; per-scenario rows under Data/pricing-v21-validation/rows_run3/, audit under audit_run3/, tie-breaks under tiebreak_run3/.",
  "cleanup": "Created Draft quotes/orders on Account \u2018Fortra, LLC - Test\u2019 (001WC00000XiZP4YAN); each tagged uniquely. Safe to delete the run3 Draft quotes after review."
 },
 "durability": [
  "F-09 proves in-place V21 edits CAN regress passing scenarios silently \u2014 re-run currency + partner scenarios after any in-place edit (the 05:56Z edit regressed a 01:47Z PASS).",
  "K-07 derived-tier formula oscillation and K-15 quote\u2194order context parity were re-confirmed stable this run, but remain watch items on any version churn.",
  "9 scenarios are BLOCKED purely on UAT environment gaps (no Evergreen catalog, no contracted lines) \u2014 they need a seeded catalog to ever reach a PASS/FAIL verdict, not a procedure change."
 ]
};

const VCOL = { PASS: "#16794d", FAIL: "#b3261e", BLOCKED: "#8a6d00" };
const TCOL = { PROCEDURE: "#b3261e", "ORG-CONFIG": "#5b3fb0" };
const S = {
  page: { fontFamily: "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif", color: "#1a1f29", background: "#eef1f5", margin: 0, lineHeight: 1.5 },
  wrap: { maxWidth: 1180, margin: "0 auto", padding: "0 20px 80px" },
  header: { background: "linear-gradient(120deg,#10243e,#1c3a5e)", color: "#fff", padding: "30px 20px 26px" },
  section: { background: "#fff", borderRadius: 12, padding: "24px 26px", margin: "22px 0", boxShadow: "0 1px 3px rgba(16,36,62,.08)" },
  h2: { fontSize: 20, margin: "0 0 16px", paddingBottom: 10, borderBottom: "2px solid #eef1f5" },
  verdict: { fontSize: 16.5, background: "#f8fafc", borderLeft: "5px solid #0b6bcb", padding: "14px 18px", borderRadius: 8, marginBottom: 20 },
  tiles: { display: "grid", gridTemplateColumns: "repeat(5,1fr)", gap: 14, marginBottom: 22 },
  tile: (c) => ({ background: "#fafbfc", border: "1px solid #e7ecf2", borderTop: `5px solid ${c}`, borderRadius: 10, padding: "16px 12px", textAlign: "center" }),
  card: (c) => ({ background: "#fff", border: "1px solid #e7ecf2", borderLeft: `6px solid ${c}`, borderRadius: 11, padding: "16px 18px" }),
  chip: (bg) => ({ color: "#fff", fontWeight: 800, fontSize: 12.5, padding: "3px 9px", borderRadius: 6, background: bg }),
  vcell: (bg) => ({ fontWeight: 800, fontSize: 11, padding: "3px 8px", borderRadius: 5, color: "#fff", background: bg, display: "inline-block", minWidth: 62, textAlign: "center" }),
  th: { fontSize: 11, textTransform: "uppercase", letterSpacing: ".4px", color: "#7a8696", background: "#fafbfc", textAlign: "left", padding: "8px 10px", cursor: "pointer", borderBottom: "1px solid #eef1f5" },
  td: { padding: "8px 10px", borderBottom: "1px solid #eef1f5", verticalAlign: "top", fontSize: 13 },
  rc: { fontSize: 10.5, color: "#7a8696" },
};

function KV({ k, v, obs }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "128px 1fr", gap: 10, fontSize: 12.7, marginBottom: 8 }}>
      <span style={{ color: "#7a8696", fontWeight: 700, fontSize: 11, textTransform: "uppercase" }}>{k}</span>
      <span style={obs ? { background: "#fff6f5", borderRadius: 6, padding: "6px 9px", border: "1px solid #f6dcd9" } : { color: "#2b3646" }}>{v}</span>
    </div>
  );
}

function Bar({ P, F, B }) {
  const t = P + F + B || 1;
  return (
    <div style={{ display: "flex", height: 13, borderRadius: 4, overflow: "hidden", background: "#eef1f5", minWidth: 130 }}>
      <span style={{ width: `${P / t * 100}%`, background: VCOL.PASS }} />
      <span style={{ width: `${F / t * 100}%`, background: VCOL.FAIL }} />
      <span style={{ width: `${B / t * 100}%`, background: VCOL.BLOCKED }} />
    </div>
  );
}

export default function V21Results() {
  const { meta, legend, headlines, defects, corrections, tallies, transitions, matrix, fixtures, durability } = DATA;
  const [fv, setFv] = useState("ALL");
  const [fp, setFp] = useState("ALL");
  const [q, setQ] = useState("");
  const [sortKey, setSortKey] = useState("id");
  const [dir, setDir] = useState(1);

  const ov = tallies.overall, bp = tallies.byPriority;
  const p0 = bp.P0, tested0 = p0.PASS + p0.FAIL;
  const p0rate = tested0 ? Math.round(p0.PASS / tested0 * 1000) / 10 : 0;

  const rows = useMemo(() => {
    let r = matrix.filter((x) => (fv === "ALL" || x.verdict === fv) && (fp === "ALL" || x.pri === fp) &&
      (!q || (x.id + " " + x.name + " " + x.expected + " " + x.actual + " " + x.rootCause).toLowerCase().includes(q.toLowerCase())));
    r = [...r].sort((a, b) => { const A = (a[sortKey] || "") + "", B = (b[sortKey] || "") + ""; return A < B ? -dir : A > B ? dir : 0; });
    return r;
  }, [fv, fp, q, sortKey, dir, matrix]);

  const tiles = [["104", "scenarios", "#1f2937"], [ov.PASS, "PASS", VCOL.PASS], [ov.FAIL, "FAIL (defects)", VCOL.FAIL], [ov.BLOCKED, "BLOCKED", VCOL.BLOCKED], [p0rate + "%", "P0 pass-of-tested", "#0b6bcb"]];
  const procN = defects.filter((d) => d.type === "PROCEDURE").length, orgN = defects.filter((d) => d.type === "ORG-CONFIG").length;
  const transDefs = [["Fixed", "prior FAIL → now PASS", transitions.fixed, VCOL.PASS], ["Reclassified", "prior FAIL → BLOCKED (data-artifact, not a defect)", transitions.reclassified, VCOL.BLOCKED], ["Persistent", "FAIL in both runs", transitions.persistent, VCOL.FAIL], ["New FAIL", "prior PASS → now FAIL", transitions.newfail, "#d9480f"]];
  const sortBy = (k) => { if (k === sortKey) setDir(-dir); else { setSortKey(k); setDir(1); } };

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div style={{ maxWidth: 1180, margin: "0 auto" }}>
          <h1 style={{ margin: "0 0 4px", fontSize: 30 }}>{meta.title}
            <span style={{ background: "#f4b400", color: "#1a1f29", fontWeight: 700, fontSize: 11, padding: "3px 9px", borderRadius: 5, marginLeft: 8, verticalAlign: "middle" }}>VALIDATION ONLY</span></h1>
          <div style={{ fontSize: 16, color: "#bcd3ec", marginBottom: 14 }}>{meta.subtitle}</div>
          <div style={{ fontSize: 12.5, color: "#9fbbd8", display: "flex", flexWrap: "wrap", gap: 16 }}>
            <span>Org <b style={{ color: "#dcebff" }}>{meta.org}</b></span>
            <span><b style={{ color: "#dcebff" }}>{meta.procVersion}</b></span>
            <span>Context <b style={{ color: "#dcebff" }}>{meta.context}</b></span>
            <span>Run <b style={{ color: "#dcebff" }}>{meta.date}</b></span>
          </div>
        </div>
      </div>
      <div style={S.wrap}>

        {/* EXEC */}
        <div style={S.section}>
          <h2 style={S.h2}>Executive summary</h2>
          <div style={S.verdict}>{meta.verdictLine}</div>
          <div style={S.tiles}>{tiles.map(([n, l, c], i) => (
            <div key={i} style={S.tile(c)}><div style={{ fontSize: 30, fontWeight: 800, color: c }}>{n}</div><div style={{ fontSize: 12, color: "#5b6675", marginTop: 6, fontWeight: 600 }}>{l}</div></div>
          ))}</div>

          <h3 style={{ fontSize: 15, margin: "6px 0 12px", color: "#10243e" }}>Legend — what each verdict means &amp; why</h3>
          <div style={{ display: "grid", gridTemplateColumns: "1.35fr 1fr", gap: 22 }}>
            <div>{legend.verdicts.map((v) => (
              <div key={v.key} style={{ display: "flex", gap: 12, marginBottom: 14, alignItems: "flex-start" }}>
                <span style={{ ...S.chip(v.color), minWidth: 78, textAlign: "center", marginTop: 2 }}>{v.key}</span>
                <div><b>{v.meaning}</b><div style={{ fontSize: 13, color: "#5b6675", marginTop: 3 }}>{v.why}</div></div>
              </div>))}</div>
            <div style={{ background: "#f8fafc", borderRadius: 10, padding: "14px 16px" }}>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: "#3a4654", marginBottom: 10, textTransform: "uppercase" }}>Root-cause classes</div>
              {legend.rootCauses.map((r) => (
                <div key={r.key} style={{ fontSize: 12.5, marginBottom: 9, color: "#41506a" }}>
                  <span style={{ background: "#eaeef4", borderRadius: 5, padding: "1px 7px", fontWeight: 700, fontSize: 11 }}>{r.key}</span> {r.desc}
                </div>))}
            </div>
          </div>

          <h3 style={{ fontSize: 15, margin: "22px 0 12px", color: "#10243e" }}>Headline findings</h3>
          {headlines.map((h, i) => (
            <div key={i} style={{ borderLeft: "4px solid #0b6bcb", background: "#f8fafc", padding: "11px 16px", borderRadius: 7, marginBottom: 11 }}>
              <div style={{ fontWeight: 800, fontSize: 13, color: "#10243e", marginBottom: 3 }}>{h.tag}</div>
              <div style={{ fontSize: 13.5, color: "#33415c" }}>{h.text}</div>
            </div>))}
          <div style={{ fontSize: 13, color: "#41506a", background: "#fbfcfe", border: "1px dashed #cdd8e6", borderRadius: 9, padding: "14px 16px", marginTop: 6 }}>
            <b>How this was tested.</b> {meta.method}<br /><br /><b>Data discipline.</b> {meta.dataDiscipline}
          </div>
        </div>

        {/* DEFECTS */}
        <div style={S.section}>
          <h2 style={S.h2}>Defects — {ov.FAIL} reportable ({procN} procedure · {orgN} org-config)</h2>
          {["P0", "P1", "P2"].map((pri) => {
            const ds = defects.filter((d) => d.pri === pri); if (!ds.length) return null;
            return (
              <div key={pri}>
                <h3 style={{ fontSize: 16, margin: "22px 0 12px", color: "#10243e" }}>{pri} defects <span style={{ color: "#8a97a8", fontWeight: 500 }}>({ds.length})</span></h3>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
                  {ds.map((d) => (
                    <div key={d.id} style={S.card(TCOL[d.type])}>
                      <div style={{ display: "flex", flexWrap: "wrap", gap: 7, alignItems: "center", marginBottom: 9 }}>
                        <span style={S.chip(TCOL[d.type])}>{d.id}</span>
                        <span style={{ fontSize: 10.5, fontWeight: 800, border: `1.5px solid ${TCOL[d.type]}`, color: TCOL[d.type], borderRadius: 5, padding: "2px 7px" }}>{d.type}-DEFECT</span>
                        <span style={{ fontSize: 11, color: "#5b6675", background: "#eef1f5", borderRadius: 5, padding: "2px 8px" }}>{d.cat}</span>
                        {d.ticket && d.ticket !== "—" && <span style={{ fontSize: 11, color: "#5b3fb0", background: "#efeafc", borderRadius: 5, padding: "2px 8px", fontWeight: 600 }}>{d.ticket}</span>}
                        {d.regression && <span style={{ fontSize: 10, fontWeight: 800, color: "#fff", background: "#d9480f", borderRadius: 5, padding: "2px 8px" }}>NEW REGRESSION</span>}
                      </div>
                      <div style={{ fontSize: 15, fontWeight: 700, color: "#16202e", marginBottom: 11 }}>{d.title}</div>
                      <KV k="Responsible step" v={d.step} />
                      <KV k="Expected" v={d.expected} />
                      <KV k="Observed (live)" v={d.observed} obs />
                      <KV k="Proposed fix" v={d.fix} />
                      <a href={d.url} target="_blank" rel="noopener noreferrer" style={{ fontSize: 12, fontWeight: 700, color: "#0b6bcb", textDecoration: "none" }}>▶ Evidence record</a>
                    </div>))}
                </div>
              </div>);
          })}
        </div>

        {/* CORRECTIONS */}
        <div style={S.section}>
          <h2 style={S.h2}>Data &amp; expectation corrections</h2>
          <p style={{ fontSize: 13.5, color: "#41506a", marginTop: -6 }}>Scenarios where the first-pass FAIL did <b>not</b> survive scrutiny — proof the run separates a malformed fixture from a real fault.</p>
          {corrections.map((c) => {
            const col = c.kind === "False defect caught" ? "#b3261e" : c.kind === "Expectation corrected" ? "#0b6bcb" : "#16794d";
            return (
              <div key={c.id} style={{ background: "#fff", border: "1px solid #e7ecf2", borderLeft: `5px solid ${col}`, borderRadius: 10, padding: "13px 16px", marginBottom: 12 }}>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 10, alignItems: "center", marginBottom: 7 }}>
                  <span style={S.chip(col)}>{c.id}</span>
                  <span style={{ fontWeight: 800, fontSize: 12.5, color: col }}>{c.kind}</span>
                  <span style={{ fontSize: 12.5, color: "#41506a" }}>{c.from} → <b>{c.to}</b></span>
                  <span style={{ fontSize: 11, color: "#8a97a8", marginLeft: "auto" }}>via {c.resolvedBy}</span>
                </div>
                <div style={{ fontSize: 13, color: "#33415c" }}>{c.fact}</div>
              </div>);
          })}
        </div>

        {/* DELTA */}
        <div style={S.section}>
          <h2 style={S.h2}>What changed since the prior run</h2>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Transition", "Meaning", "#", "Scenarios"].map((h) => <th key={h} style={S.th}>{h}</th>)}</tr></thead>
            <tbody>{transDefs.map(([t, desc, ids, c]) => (
              <tr key={t}><td style={{ ...S.td, color: c, fontWeight: 700 }}>{t}</td><td style={S.td}>{desc}</td><td style={{ ...S.td, textAlign: "center" }}>{ids.length}</td><td style={{ ...S.td, fontFamily: "monospace", fontSize: 11.5, color: "#5b6675" }}>{ids.join(", ") || "—"}</td></tr>
            ))}</tbody>
          </table>
        </div>

        {/* COVERAGE */}
        <div style={S.section}>
          <h2 style={S.h2}>Coverage</h2>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 26 }}>
            <div><h3 style={{ fontSize: 14, margin: "0 0 8px" }}>By priority</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead><tr>{["Pri", "Tot", "P", "F", "B", "Pass%*"].map((h) => <th key={h} style={{ ...S.th, textAlign: h === "Pri" ? "left" : "center" }}>{h}</th>)}</tr></thead>
                <tbody>{["P0", "P1", "P2"].map((p) => { const c = bp[p], P = c.PASS || 0, F = c.FAIL || 0, B = c.BLOCKED || 0, te = P + F; return (
                  <tr key={p}><td style={{ ...S.td, fontWeight: 700 }}>{p}</td><td style={{ ...S.td, textAlign: "center" }}>{P + F + B}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.PASS }}>{P}</td><td style={{ ...S.td, textAlign: "center", color: VCOL.FAIL }}>{F}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.BLOCKED }}>{B}</td><td style={{ ...S.td, textAlign: "center", fontWeight: 700 }}>{te ? Math.round(P / te * 1000) / 10 : 0}%</td></tr>); })}</tbody>
              </table>
              <div style={{ fontSize: 12, color: "#7a8696", marginTop: 8 }}>*Pass% = PASS / (PASS+FAIL), excluding BLOCKED.</div></div>
            <div><h3 style={{ fontSize: 14, margin: "0 0 8px" }}>By category</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead><tr>{["Category", "T", "P", "F", "B", "Mix"].map((h) => <th key={h} style={{ ...S.th, textAlign: h === "Category" ? "left" : "center" }}>{h}</th>)}</tr></thead>
                <tbody>{Object.keys(tallies.byCategory).sort().map((ct) => { const c = tallies.byCategory[ct], P = c.PASS || 0, F = c.FAIL || 0, B = c.BLOCKED || 0; return (
                  <tr key={ct}><td style={{ ...S.td, fontWeight: 600 }}>{ct}</td><td style={{ ...S.td, textAlign: "center" }}>{P + F + B}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.PASS }}>{P}</td><td style={{ ...S.td, textAlign: "center", color: VCOL.FAIL }}>{F || ""}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.BLOCKED }}>{B || ""}</td><td style={S.td}><Bar P={P} F={F} B={B} /></td></tr>); })}</tbody>
              </table></div>
          </div>
        </div>

        {/* MATRIX */}
        <div style={S.section}>
          <h2 style={S.h2}>Full results matrix — 104 scenarios</h2>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center", marginBottom: 14 }}>
            {["ALL", "PASS", "FAIL", "BLOCKED"].map((v) => (
              <button key={v} onClick={() => setFv(v)} style={btn(fv === v)}>{v === "ALL" ? "All" : v}</button>))}
            <span style={{ width: 1, height: 22, background: "#dce3ec", margin: "0 4px" }} />
            {["ALL", "P0", "P1", "P2"].map((p) => (
              <button key={p} onClick={() => setFp(p)} style={btn(fp === p)}>{p === "ALL" ? "All pri" : p}</button>))}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="search id / name / detail…"
              style={{ marginLeft: "auto", border: "1.5px solid #d4dce6", borderRadius: 20, padding: "6px 14px", fontSize: 13, minWidth: 220 }} />
          </div>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{[["id", "ID"], ["cat", "Cat"], ["pri", "Pri"], ["dataSource", "Data"], ["preflight", "Pre"], ["verdict", "Verdict"], ["rootCause", "Root cause"], [null, "Expected → Actual (live)"], [null, "Ev"]].map(([k, h], i) => (
              <th key={i} style={S.th} onClick={() => k && sortBy(k)}>{h}</th>))}</tr></thead>
            <tbody>{rows.map((x) => (
              <tr key={x.id}>
                <td style={{ ...S.td, fontFamily: "monospace", fontWeight: 700 }}>{x.id}</td>
                <td style={S.td}>{x.cat}</td><td style={{ ...S.td, fontWeight: 700, color: "#5b6675" }}>{x.pri}</td>
                <td style={{ ...S.td, ...S.rc }}>{x.dataSource}</td><td style={{ ...S.td, ...S.rc }}>{x.preflight}</td>
                <td style={S.td}><span style={S.vcell(VCOL[x.verdict])}>{x.verdict}</span></td>
                <td style={{ ...S.td, ...S.rc }}>{x.rootCause}</td>
                <td style={S.td}><b style={{ fontSize: 12 }}>{x.name}</b>
                  <div style={S.rc}><b>Exp:</b> {x.expected}</div><div style={S.rc}><b>Act:</b> {x.actual}</div>
                  {x.adjudication && <div style={{ ...S.rc, color: "#0b6bcb" }}>⚖ {x.adjudication}</div>}</td>
                <td style={S.td}>{x.url && <a href={x.url} target="_blank" rel="noopener noreferrer" style={{ color: "#0b6bcb", textDecoration: "none" }}>▶</a>}</td>
              </tr>))}</tbody>
          </table>
          <div style={{ fontSize: 12, color: "#7a8696", marginTop: 8 }}>Showing {rows.length} of {matrix.length} scenarios</div>
        </div>

        <div style={{ fontSize: 12, color: "#7a8696", padding: "0 4px", lineHeight: 1.6 }}>
          <b>Fixtures &amp; cleanup.</b> {fixtures.note} {fixtures.cleanup}<br />
          <b>Durability / follow-ups.</b> {durability.join(" · ")}
        </div>
      </div>
    </div>
  );
}

function btn(on) {
  return { fontSize: 12, fontWeight: 700, border: `1.5px solid ${on ? "#10243e" : "#d4dce6"}`, background: on ? "#10243e" : "#fff", color: on ? "#fff" : "#41506a", borderRadius: 20, padding: "5px 13px", cursor: "pointer" };
}
