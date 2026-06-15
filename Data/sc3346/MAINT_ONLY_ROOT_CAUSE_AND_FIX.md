# SC-3346 MAINT-ONLY — Root Cause (PROVEN) + Resolution

**Date:** 2026-06-14 · **Org:** FortraUAT · **Method:** read-only forensics + 5-agent root-cause workflow + a reversible live `initiateRenewal` experiment (test data created + deleted; no asset mutated).

## Root cause (definitive, live + code + experiment proven)

A maintenance-only renewal commits a **born-stale net** (e.g. `60.64 = 67.38 × 0.90`, never the COLA net) because **the renewal-maintenance QuoteLineItem is created WITHOUT a QLI-linked `Renew` QuoteAction**. Two consequences, one cause:

1. **The COLA write-path early-returns.** `COLAUpliftHandler.handleBeforeInsert` returns early when no inserted QLI carries a `QuoteActionId` (cls:29-31), filters QuoteActions to `Type='Renew'` (cls:39), and `populateCOLAFields` skips any line with `QuoteActionId==null` (cls:280-282). `COLAUpliftPrehook` has the identical gate (`QuoteAction.Type='Renew'`, skip `stActionType!='Renew'`). `QuoteLineItemTrigger` wires only this handler before-insert. → a QuoteAction-less RenewalMaintenance line **never gets COLA fields written**.
2. **The engine routes it to a derived/zero-list UNPRICED node**, so the COLA net can never commit and reprice/posthook context-writes **no-op**.

### Proof
- **Live (read-only):** the lone org line that commits the COLA net (00781084 / `0QLWC000003dEW24AM`, 67.38) has `QuoteActionId` populated + `QuoteAction.Type='Renew'` + `COLA_Source__c` set (handler ran). Both 60.64 defect lines (`…dAaT4AU`, `…e2Sn4AI`) have `QuoteActionId=null` + `COLA_Source__c=null` (handler never ran) **despite** `Base_Price__c=71` / `COLA_Uplift_Percent__c=7.85` already stamped — so the fault is the missing QuoteAction, **not** the COLA computation. **Of 498,250 RenewalMaintenance QLIs org-wide, exactly 1 carries a QuoteAction.**
- **Experiment (decisive, reversible):** `initiateRenewal` on a renewable-term asset (`02iWC000007Y3M1YAK` IP360-RenewalMaintenance, `CurrentLifecycleEndDate=2027-02-28`, qty 300), maintenance-only, with a **term-advancing window** (`renewStartDate=2027-03-01`) produced a QLI **born with a linked `Renew` QuoteAction** → `COLA_Source` set → priced node → **`NetUnitPrice` committed `2097.9` (= 1998 × 1.05 COLA) and HELD through a Force reprice** (NetTotalPrice 629,370). The QuoteAction-less control (NewMaintenance asset) → `Type='No Change'`, qty 0, born-stale. (Quote + Opportunity deleted; asset unmutated.)

### Determinant (corrected vs earlier leans)
The `Renew` vs `No Change` outcome is **per-`initiateRenewal`-call** — the renew window advancing a renewable term — **not** a static OneTime-vs-TermDefined attribute (the same OneTime asset produced `Renew` on one call and `No Change` on another minutes apart; the working 67.38 line is itself OneTime). The load-bearing requirement is that the resulting **`Renew` QuoteAction is LINKED to the QLI** (`QLI.QuoteActionId` populated) at line **birth**.

### Why the line is born QuoteAction-less (both production entry points)
- **`Fortra_Create_Renewal_Quote`** → `initiateRenewal` on the **prior** assets (Y1 license + the OneTime `New Maintenance` asset, product `01tWC00000DD1bsYAD`, which has only a OneTime PSMO → `No Change`/unlinked). The **Year-2 AutoAdd ProductConfigurationRule `14OWC0000022Eyb2AE`** (keyed off the perpetual code `PIA-PIA-NRPS-PIAP` + `QuoteTypeText__c='Renewal'`) then adds the RenewalMaintenance SKU as a **configurator line that by platform design has NO QuoteAction**. `RenewalQuoteLineHandler` deletes the carried-over NewMaintenance/Perpetual lines.
- **`Fortra_Renewal_Quote_Creation`** (Contract "Renew" screen flow) inserts QLIs straight from ContractLineItems with `QuoteActionId=null`.
There is **no Product2 renewal-product mapping and no ProductRelatedComponent**; the Y1→Y2 substitution is purely the two AutoAdd PCRs + carryover-delete. So the renewal-maintenance line is **never** born from an asset-renewal that mints a linked `Renew` QuoteAction.

## Resolution

**The fix is to make the renewal-maintenance line born WITH a QLI-linked `Renew` QuoteAction** (the proven-working shape). Writing the net post-hoc cannot work — it no-ops on the unpriced node (empirically refuted), and there is no QuoteAction to stamp on first-renewal lines.

- **Track A (durable; owner-gated renewal design — recommended).** Re-architect renewal-maintenance creation so the RenewalMaintenance line originates from an **asset-renewal chain that yields a QLI-linked `Renew` QuoteAction**, replacing the AutoAdd-PCR + carryover-delete substitution (which strips the QuoteAction). For the first renewal (Y1 OneTime NewMaintenance → Y2 RenewalMaintenance) this requires either (i) modeling maintenance as a TermDefined subscription so renewing it naturally mints the `Renew` QuoteAction, or (ii) the renewal flow creating the RenewalMaintenance line **born-linked** to a `Renew` QuoteAction on the prior maintenance asset. Owner = renewal-flow owner (Nir Kailash / SC-3346 build owner).
- **Track B (refuted as a standalone fix):** wiring the dead `RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices` or stamping `QuoteActionId` post-insert — both fail because (a) the COLA handler runs *before-insert* (the link must exist at birth), (b) net writes no-op on the unpriced node, (c) RLM blocks direct Quote/QLI DML, and (d) first-renewal lines have no `Renew` QuoteAction to stamp.

### Do NOT (refuted/unsafe)
- Add a TermDefined PSMO to the New Maintenance product (working line is OneTime, so unnecessary; risks the PSMO↔PBE delete-order interlock).
- Posthook/prehook `NetUnitPrice` context-writes on the unpriced node (proven no-op).
- Rely on `RenewalAssetQuantityHandler` No-Change→Renew flip (needs a pre-existing `QuoteActionId`; it is unwired/dead).

### Risks for any fix
- **Scale:** 498,250 RenewalMaintenance QLIs are already QuoteAction-less/born-stale — a creation-path fix only corrects NEW renewals; retroactive remediation of the existing population is a separate, large data decision.
- **Blast radius:** the renewal flow + AutoAdd PCRs feed all renewals (513K+ lines); RLM Quote-DML lock; PCR has no migration tooling; product-config durability (Gearset/refresh can revert PSMO/PBE/PAD flags).
- The SC-3346 renewal build is red/low-coverage and prod-readiness is NO-GO per peer review; this is UAT-only and must not be promoted without separate review.

## Status
Root cause **found and proven**. The fix is an **owner-gated renewal-architecture change** (Track A) — not safely implementable unilaterally on the live 498K-line renewal flow. This doc is the proven hand-off spec; recommend Nir implement Track A, or grant explicit authorization for a scoped prototype validated against the proven experiment.
