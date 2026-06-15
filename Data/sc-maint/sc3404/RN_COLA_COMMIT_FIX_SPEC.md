# SC-3404 / RN-COLA-COMMIT — Implementation Spec (owner hand-off)

**Owner:** Liam · **Date:** 2026-06-14 · **Companion RCA:** [RN_COLA_COMMIT_RCA.md](RN_COLA_COMMIT_RCA.md)
**Aligns with + extends** memory `project_sc3346_rncola_commit_fix` (read it first — it has the v1.5 fix, the same-PBE proof, and lever (d)).

---

## 1. Root cause (definitive)
Renewal-maintenance lines use SKU **`PIA-PIA-RRM-PIAM`** (Renewal Maint) but customers own the **`PIA-PIA-RNM-PIAMBK`** (New/year-1 Maint) asset. `initiateRenewal` only creates a `Renew` QuoteAction when it can renew an asset **by matching SKU** → no RRM asset → the RRM line is **configurator-auto-added with no QuoteAction**. A derived (`DerivedPricingAttribute=true`), QuoteAction-less, zero-list line is **born at the partner-discounted `60.64`** and frozen there.

**The 60.64 is a FROZEN FOSSIL, not a live recompute** (memory RE-RCA): all 16 reprice snapshots = 60.64, the COLA net 67.38 commits 0×; the ×0.90 was applied at the line's FIRST reprice under pre-v1.5 deferred-partner and is now immutable. The active double-discount (**A1 / RN-PARTNER-DD**) is **already FIXED** in `PartnerNetPricePosthook` **v1.5** (deferred-partner ×0.90 hard-bypassed for renewal-maint). Within V14 both ×0.90 writers (`PartnerDiscountDerivedMaintenance20` gated `QuoteTypeText__c≠'Renewal'`; `PartnerDiscount30` gated `DerivedPricingAttribute IsNull/false`) are **filter-gated OUT** of renewal-maint lines → the procedure can't re-stack ×0.90.

**Discriminator (same-PBE proof):** the working line (`0QLWC000003dEW24AM`, 67.38) and the broken lines all sit on the SAME derived PBE `01uWC000006XPPBYA4` (IsDerived, ListPrice=0). Derived-ness is the freezing mechanism; the **`Renew`-QuoteAction-at-creation is the SOLE discriminator** (auto-add → born 60.64; Renew path → born 67.38). The asset-inventory proof: the ONE account with a real `PIA-PIA-RRM-PIAM` *asset* commits 67.38; all RNM-only accounts fail.

**New this session:** `RenewalMaintenancePricingService` (built to write the COLA net) is **unwired — 0 dependency references**, called by nothing; and its no-arg `finalizeRenewalMaintenanceAfterPricing` **gacks** at `buildContext('SalesTransactionContextExt_v2')` (`1648396304-208856`, context-sync, see [[project_reprice_contextdef_error]]).

---

## 2. Lever hierarchy (what's dead, what's live)

| Lever | What | Status |
|---|---|---|
| (b) PBEDP / zero-list list price | give the PBE a list price | **REFUTED** — same product prices 71 with ListPrice=0 when a contributor is on the quote; canary PBE already has a PBEDP |
| (c) prehook seed `ListPrice`/`InputUnitPrice`=colaNet | hydrate a priced node pre-procedure | **REFUTED** (empirically) — context write of engine-owned fields no-ops on a non-priced/QA-less node; the working line has ListPrice=0 anyway |
| wire `RenewalMaintenancePricingService` (this session's "B") | call its `updateContextAttributes` NetUnitPrice write | **Likely DEAD** — same context-write mechanism the v1.5 posthook already uses, which no-ops on the QA-less node. Wiring it in won't escape the wall. Don't pursue as primary. |
| **(a) Renew QuoteAction at creation** | born-link the RRM line to a `Renew` action | **PROVEN-working config**; fixes NEW lines only (not existing fossils); renewal-flow/creation change |
| **(d) procedure commit-path** | add a `resultIncluded=true` element committing `COLACalculatedPrice__c → NetUnitPrice` | **UNTRIED, single change, self-heals existing + new regardless of QuoteAction** — but crux assumption + co-owned V14 republish |

---

## 3. Lever (a) — born-link a Renew QuoteAction (proven, fixes new lines)
**Cleanest form (config, not Apex):** set the **renewal/substitution product** of every `*-RNM-*` New-Maint SKU to its `*-RRM-*` counterpart (e.g. `PIA-PIA-RNM-PIAMBK` → `PIA-PIA-RRM-PIAM`) so `initiateRenewal` renews the RNM asset **into** the RRM line and stamps a `Renew` QuoteAction. Then suppress the Year-2 configurator auto-add (`14OWC0000022Eyb2AE`) so it doesn't double-add. Verify the RLM renewal-product mechanism in this org.
**Apex fallback:** in `RenewalQuoteLineHandler`/`QuoteRenewalTypeHandler`, when an RRM line is added on a Renewal quote and the account has the matching RNM asset, create `QuoteAction(Type='Renew', SourceAssetId=<RNM asset>)` + set `QLI.QuoteActionId`. **Caveat:** cross-SKU link (RRM line → RNM asset) — validate the engine routes it to a writable node before trusting.
**Limit:** does NOT heal the ~35,810 existing Draft QA-less lines / fossil assets; only new renewals.

## 4. Lever (d) — procedure commit-path (untried; the single change that self-heals)
Add (or flip) a **`resultIncluded=true`** element in V14 that commits `COLACalculatedPrice__c → NetUnitPrice` for renewal-maint lines, gated `Fortra_Product_Type__c='Renewal Maintenance' AND COLACalculatedPrice__c>0`, **contributor-UNgated** (today the sole committer `DerivedProductsRenewals` is contributor-gated, so it skips MissingContributor lines; the COLA values reach NetUnitPrice only via `resultIncluded=false` elements `DerivedPricingRenewals`/`COLAUpliftonRenewalNet` which don't persist).
**Crux assumption (MUST test):** whether an ungated committing element **overwrites a *settled* derived node** on reprice. Current engine never recomputes the fossil — but that's under the contributor gate; an ungated committer may or may not break the freeze. **Test before trusting.**
**Cost:** co-owned V14 → offline window + Nir republish + ~100k-line regression sweep; ESV delete is platform-blocked (no clean rollback) → stage as a new version, validate, then activate.

## 5. Recommended path
1. **(d) first** if you accept a V14 republish — it's the single change that heals existing fossils + all new lines regardless of QuoteAction. Gate-test the crux assumption on one canary in an offline window.
2. If (d)'s ungated committer won't overwrite settled nodes → **(a)** for new lines + a one-time data remediation (re-create/repair the fossil lines) for existing.
3. Either way: **wire or delete** the dead `RenewalMaintenancePricingService`, and **guard its gacking `buildContext` fallback**; re-sync `SalesTransactionContextExt_v2` after any V14 republish.

---

## 6. Verification protocol
Canaries (all `PIA-PIA-RRM-PIAM`, Draft) — re-query Ids live (they churn on reprice):

| Line | Quote | QuoteAction | Now | Expect |
|---|---|---|---|---|
| 0QLWC000003e2Sn4AI | 0Q0WC0000038aXd0AI | none | 60.64 | **67.38** |
| 0QLWC000003cy334AA | 0Q0WC0000037muD0AQ | none | 54.58 | (COLACalc 60.64) |
| 0QLWC000003cN584AE | 0Q0WC0000037AKH0A2 | none | 0 | **67.38** |
| 0QLWC000003dEW24AM | 0Q0WC00000382MH0AY | **Renew** | 67.38 | 67.38 (regression guard) |

Checks: NetUnitPrice==COLACalc on every renewal-maint line; PartnerUnitPrice==NetUnitPrice (no ×0.90); rollups + Quote GrandTotal consistent; Renew-QA line stays 67.38; NB derived line still `tier×SLP` (no regression). Reprice = PlaceQuote `POST /services/data/v67.0/commerce/quotes/actions/place` `{"pricingPref":"Force",…}` async → poll `AsyncOperationTracker`; intermittently gacks (retry). Draft canaries only; **00781068 (Accepted) untouched**.

## 7. Guardrails
V14 sole-active, ESV delete platform-blocked (no clean rollback) → stage-validate-activate. Prehook/posthook move minute-to-minute across sessions → re-retrieve before editing. Renewal universe is small (~43 quotes, not 1.2M) but validate auto-add suppression doesn't drop maintenance lines. Test data is degraded (MissingContributor/null COLAcalc) — build a fresh clean license+maintenance renewal to validate E2E.
