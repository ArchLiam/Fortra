# SC-3346 / SC-3404 — Born-net fix (Fix Path A) — DRAFT for review

Stamps a `Type='Renew'` QuoteAction on configurator-auto-added **renewal-maintenance** lines so they
price as **born-net priced nodes** and commit the correct COLA net (e.g. 67.38) instead of the frozen
fossil (60.64 / 54.58 / $0).

## Why this is the fix (one paragraph)
The committed `NetUnitPrice` on a renewal-maintenance line is wrong because the line is auto-added
**without** a Renew QuoteAction. The native RLM committer `DerivedProductsRenewals` is **contributor-keyed**;
a line with no contributor is skipped, so its `NetUnitPrice` never recomputes and freezes at the
pre-procedure fossil. Proven by elimination — three independent reprice-time writes (posthook v1.5,
a `resultIncluded=true` procedure committer, and `RenewalMaintenancePricingService` via V27) each
returned `isSuccess=true` yet left `NetUnitPrice` unchanged on a settled derived node. The **only** line
in the org that commits correctly is the only one carrying a Renew QuoteAction — field-for-field identical
to a fossil except `QuoteActionId`. Giving the line that QuoteAction (its `SourceAsset` = the contributor)
is the fix. Full RCA: `Data/sc-maint/rca_deep/SC3346_RNCOLA_DEEP_RCA.md` and
`SC3346_FIX_PATH_RECOMMENDATION.md`.

## What's in this package
| File | Purpose |
|---|---|
| `classes/RenewalQuoteActionStamp.cls` | The handler — mints/reuses a Renew QA and links QA-less renewal-maintenance lines |
| `classes/RenewalQuoteActionStampTest.cls` | Unit tests for the stamp logic |
| `triggers/QuoteLineItemTrigger.trigger` | Live trigger **+ one new after-insert line** (`RenewalQuoteActionStamp.stampRenewalMaintenance(Trigger.new);`) |

## How it works
On **after insert**, for each inserted line that is `QuoteActionId == null` AND
`Product2.Fortra_Product_Type__c = 'Renewal Maintenance'` AND on a renewal quote (`Quote.Quote_Type__c = 'Renewal'`):
1. Resolve the owned **source asset** on the quote's Account by matching `Product2.Solution_Category__c`,
   preferring `Fortra_Product_Type__c = 'New Maintenance'` (the RNM asset), else `'Perpetual'` (Price required).
2. Reuse an existing `Type='Renew'` QuoteAction for that `(quote, asset)`, else create one.
3. Set `QLI.QuoteActionId`.

The committed net is recomputed by the procedure from `Base_Price__c` (provenance-independent), **not** the
asset price — so anchoring to the owned RNM asset (e.g. 62.48) still yields the correct net (67.38).
Bulk-safe (one asset query, one QA query, one QA insert batch, one QLI update batch) with a recursion guard
and a `@TestVisible bypass` kill-switch.

> Gate note: gated on the settable picklist `Quote_Type__c` because `QuoteTypeText__c` (used elsewhere in
> the COLA stack) is a **formula** and can't be set in tests. Confirm both are aligned on your renewal quotes;
> switch the gate if your renewal driver differs.

## Deploy (you run this)
1. **Re-confirm the live `QuoteLineItemTrigger`** matches the base of the trigger here (it's co-owned; diff
   before overwriting) — the only change is the one added after-insert call.
2. Deploy the two classes + the trigger:
   ```
   sf project deploy start -o FortraUAT --source-dir Data/sc-maint/sc3404/bornnet_fix \
     --test-level RunSpecifiedTests --tests RenewalQuoteActionStampTest
   ```
   (or move the files under `force-app/main/default/` first, per your pipeline.)

## ⭐ Acceptance test — the REAL validation (run in UAT after deploy)
The unit tests validate the **stamp wiring**, not the end-to-end commit (the 67.38 comes from the live RLM
engine, not available in Apex tests). Prove the fix end-to-end on a **fresh renewal**:
1. Create a fresh renewal quote for an account that owns a BoKS RNM-PIAMBK asset (e.g. the canary account
   `001WC00000kTYyNYAW`, asset `02iWC000008DmS1YAK`) so the configurator auto-adds the RRM-PIAM line.
2. Confirm the trigger stamped a Renew QuoteAction on that line (`QuoteActionId` populated, `Type='Renew'`,
   `SourceAssetId` = the RNM asset).
3. Reprice (managed `Force`/`Skip`) and assert the line commits `NetUnitPrice = COLACalculatedPrice__c`
   (e.g. 67.38) and the Quote rollups reflect it.
4. Regression: a non-renewal-maintenance line is unaffected; NB-derive = 71; perpetual = 301.75/355.

**If step 3 does not flip** (the line was born already settled at the fossil before the after-insert stamp):
move the synthesis to **before insert** — call the stamp from `COLAUpliftHandler.handleBeforeInsert`
(Fix Path B). The DML-lock probe showed QuoteAction insert + QLI update are permitted; the only added risk
of Path B is before-insert DML during the managed persist.

## Open items for review (Nir / Marc)
- **Sequencing assumption** above — settle with the acceptance test.
- **`RenewalAssetQuantityHandler` interaction** — it runs (after insert) on the QA-less line and its async
  Queueable processes `QuoteActionId != null` lines; verify the newly-stamped line isn't quantity-normalized
  unintentionally.
- **Source-asset selection** when an account owns multiple RNM/Perpetual assets in the same category
  (current rule: prefer most-recent RNM, else Perpetual) — confirm the desired selection.
- **Minting QuoteActions outside `initiateRenewal`** — Nir owns the renewal architecture; confirm this is acceptable.
- **Existing fossils are NOT healed by this** (new lines only). They must be **re-created born-correct**
  (setting `QuoteActionId` on an existing settled line + reprice is a false positive). Accepted quote
  `00781068` / line `0QLWC000003dAaT4AU` must **not** be touched. Order/Asset/Workday remediation is a
  separate owner-gated workstream.
- **Keep `PartnerNetPricePosthook v1.5`** (the floor — closes the active pre-v1.5 partner re-discount).
- **Prereq for any prod promotion:** fix the `COLAUpliftTest.buildOverrideMap` 41-error drift (0% compile →
  0% coverage), independent of this fix.
