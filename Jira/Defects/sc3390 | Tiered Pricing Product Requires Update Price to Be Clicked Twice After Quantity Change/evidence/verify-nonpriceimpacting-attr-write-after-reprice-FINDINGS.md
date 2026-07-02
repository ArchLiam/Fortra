# Adversarial verification — candidate [nonpriceimpacting-attr-write-after-reprice]

Date: 2026-06-11 | Mode: READ-ONLY against FortraUAT | Verdict: plausible-unproven

## What survives
- **IsPriceImpacting=false confirmed at the DEFINITION level**, not just the QLIA instance.
  `ProductAttributeDefinition` for AttributeDefinitionId=0tjWC0000000tqvYAA (Unit Volume) =
  false on all 26 tiered products incl. CLSAAS (PAD 0v7WC0000000TvBYAU). DefaultValue=null on all.
  => candidate refute-condition #1 ("IsPriceImpacting actually true at PAD level") does NOT fire.
  File: verify-nonpriceimpacting-attr-write-after-reprice-PAD.txt
- Prehook reads volume ONLY from the pricing-context snapshot (queryTags
  'SalesTransactionItemAttribute'), never from live QLI/Quantity. cls 121,129,279,783-794.
  Within a single pricing run the prehook output (Base_Price__c/mode) IS consumed same-cycle by
  AttributeValuePricing{UnitPrice,TotalPrice,Calculated}Mode steps, so a stale OUTPUT is not the
  story — a stale INPUT volume would be. Mechanism is internally coherent.
- On null volume OR no-tier-match the prehook RESETS to ListPrice silently (cls 282-303,
  buildResetNodeUpdate). 2180 confirmed = CLSAAS USD ListPrice (PBE 01uWC000004dScBYAU). The
  "reset fingerprint" value is real.

## What is REFUTED (the cited corroboration does not support the timing story)
1. **Timestamp inversion is an artifact.** On quote 0Q0WC0000037swP0AQ the 14:44:51 write is the
   CREATE of an unrelated NON-tiered line (0QLWC000003d4zh4AA ES-CEP-RSL-ACTIDB,
   CreatedDate==LastModified==14:44:51, Has_Attribute_Adjustment__c=false). It is a quote-wide
   bulk save adding a line, NOT a reprice of the tiered line. The tiered CLSAAS QLI writes at
   14:44:50 are not "the first click" and the 14:44:51 QLIA writes are not "the volume committing
   after the reprice." No first-click/second-click pair is demonstrated.
2. **The frozen-2180 cluster is explained by static data, not snapshot lag.**
   12/13 CLSAAS lines: Feature Options="Managed Service", **Unit Volume=null** -> reset on null
   (cls 282). 1 line (0QLWC000003d4Ob4AI): Feature Options="**Console**", Unit Volume=100.0 ->
   reset on no-tier-match, because the CLSAAS tier table has ONLY Self Managed/Managed/Managed
   Service (0 "Console" rows; 0 "Console" rows org-wide). These lines are in their TERMINAL correct
   state for their current data; clicking Update Price again would not change them. This is a
   misattribution of data-gap resets to a click-twice timing lag.
   Files: verify-...-clsaas-attrs.txt, clsaas-tiers.txt.
3. **Zero log evidence of a stale-volume read.** Every captured reprice/place log
   (log-place-04-34-13, log-aura-12-45-03, 4x large place logs OqLKJ/OqLQp/OqQqF/OqXWj) returns
   the prehook early at Pass-1 with earlyReturnMessage="No eligible line items
   (Has_Attribute_Adjustment__c = true)" (cls 201). NONE reaches Pass-2 / reads Attribute_Volume /
   logs a MATCH or RESET. No "Attribute_Volume: <old>" then "<new>" pair exists in any log. The
   candidate's own CONFIRM signature requires an authorized DML repro that was not run.

## Mechanistic gap (why it stays unproven, not confirmed)
- The "place" pricing action in the logs does NO QuoteLineItemAttribute DML (0 DML_BEGIN; the
  action reads the already-committed context and prices). For the candidate to hold, the
  configurator's Unit Volume save must still be in-flight/uncommitted when the first "Update Price"
  price call snapshots the context. That specific UI ordering race is plausible in this codebase
  (documented async disease: quoteLineFlexPanel sleep(2000); COLAUpliftPrehook removed QLI DML to
  stop "prices aren't up to date" flashing; SC-3308 activate-before-reprice) but is NOT
  demonstrated by any captured artifact.
- The candidate's causal phrasing ("IsPriceImpacting=false => the QLIA write is not enlisted in the
  same atomic save+price cycle") is also a questionable reading of RLM semantics. IsPriceImpacting
  primarily governs whether changing the attribute AUTO-triggers a reprice, not whether its write
  commits. The likely-correct adjacent story (non-price-impacting attr change does not auto-reprice,
  so the displayed price lags the typed value until a manual price runs against committed data) is
  related but not identical to the candidate's stated mechanism.

## Bottom line
Direction is right (tiered pricing is driven by the non-price-impacting Unit Volume attribute read
from a context snapshot; a one-cycle input-staleness is consistent with this codebase). But all
three pieces of "already-strong corroboration" the candidate leans on are refuted or
mis-attributed, and the only decisive proof (a paired first/second-click debug log) requires an
authorized live DML repro that was not performed. Verdict: plausible-unproven.
