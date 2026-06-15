# 14 — DEEP RESEARCH: Definitive RCA of the renewal-maintenance commit defect (MAINT-ONLY / RN-COLA-COMMIT)

Provenance: 10-agent background workflow (6 parallel forensic gatherers over live FortraUAT metadata/data/apex + dossier + RLM web → synthesis → 3 adversarial skeptics), 2026-06-13. Read-only. Run wf_d3710ae6-5e5 / task wwb2lp238. Supersedes the docs-11/12/13 "frozen born value the engine refuses to touch" framing **for the live-current state** (that framing describes the older $0/never-a-node lines).

Canary: Quote `0Q0WC0000038aXd0AI` (00781109, Renewal), line `0QLWC000003e2Sn4AI` = `PIA-PIA-RRM-PIAM` 'Renewal Maintenance'. Commits **NetUnitPrice 60.64**; correct COLA net = (71 − 8.52 − 0)×(1+7.85/100) = **67.38**.

## Definitive root cause

Renewal-maintenance is modeled as an **RLM derived line** (`ItemIsDerived__std=true`, re-derived from the product/Standard-Price every reprice; `ListPrice=0`; `PriceBookEntryDerivedPrice 00000695 Formula='UnitPrice'`, contributor = the license PIA-PIA-NRPS-PIAP). A derived line's committed `NetUnitPrice` is **owned exclusively by the native derived-pricing engine** and is gated behind `AttributePricingFilter` = `DerivedPricingAttribute Equals false`. The only `resultIncluded=true` native net-writer (`DerivedProductsRenewals`) is **gated OUT of renewals** by `DerivedProductsNonRenewal` (`QuoteTypeText__c NotEquals 'Renewal'`), and even un-gated it emits the contributor's UnitPrice (~355), not a per-line COLA net. `NetUnitPrice` is `IsCreatable=false/IsUpdatable=false` — no Apex DML can set it. So the line carries the value it was **born with** and nothing downstream can move it.

## Four routes PROVEN DEAD (all blocked by the same wall)

1. **Prehook input-seed** (InputUnitPrice/ListPrice + DerivedPricingAttribute=false): engine re-derives `DerivedPricingAttribute=true` each pass and excludes derived lines from the standard `InputUnitPrice→NetUnitPrice` assignment. Seed never lands. (seed_reprice.log)
2. **Posthook `updateContextAttributes` NetUnitPrice write**: returns `isSuccess:true` but the engine **silently drops** the write for a derived line. **This is the F1 fix and it is ALREADY DEPLOYED as `PartnerNetPricePosthook` v1.5 (live, modified 2026-06-14T02:35Z) — canary still commits 60.64 after its reprice (07LWC00000Oy1Zh2AJ).** (posthook_test.log / seed_proper.log: 67.38 emitted, `NetUnitPrice={canary=67.38}` count = 0, 60.64 persists)
3. **In-procedure `DerivedPricingRenewals` formula `resultIncluded=true`**: A/B-tested (this session's V14 edit + doc-13) → output never reaches NetUnitPrice (write-back gated); left line at 60.64/$0.
4. **Native-config rewrite** (PBEDP Formula / un-gate DerivedProductsNonRenewal): PBEDP Formula can't reference per-line COLA fields (emits contributor ~355); touches the path shared by **~464K** derived renewal lines = catastrophic blast radius.

## The lever (what actually works)

A renewal-maintenance line **created correctly** prices correctly: live line **dEW24 holds NetUnitPrice = 67.38** because its **`UnitPrice` (writable) was set to the COLA net at *creation*** via `COLAUpliftHandler` (which fires when `QuoteAction.Type='Renew'`, i.e. asset-copied renewals). The canary broke because its maintenance line was **AUTO-ADDED ~17h later by the Year-2 Maintenance Product Configuration Rule/TLE** (`QuoteAction.Type ≠ 'Renew'`), so `COLAUpliftHandler` **skipped it** → no creation-time price → stale 60.64. **The fix belongs at line creation, not at reprice.**

## Cohort size (any fix is tiny blast radius)

464,002 RM-on-renewal QLIs exist, but only **6** have `Base_Price__c>0`, only **7** have `NetUnitPrice>0`, only **4** reach the partner path (the COLA cohort cy334/dAaT4/e2Sn4/dEW24). The ~464K legacy lines are `Net=0/null` and triple-gated out of every code path (no partner pricing, NetUnitPrice not >0, Base not >0). 55 total partner-priced lines org-wide (41 non-RM).

## Two viable fix directions (both owner-gated)

- **A — Creation-time `UnitPrice` = COLA net** for auto-added renewal-maintenance lines (replicate the dEW24 path in the Year-2 config-rule / auto-add handler or COLAUpliftHandler). `UnitPrice` is writable and born-values stick. More tractable; **must validate that committed NetUnitPrice follows UnitPrice on a derived line** (engine-mechanics skeptic flagged dEW24 as possibly correlational — needs a fresh FINEST reprice proof).
- **B — De-derive the line** (catalog/PBE/PSM so it's a normal priced line; `DerivedPricingAttribute=false` sticks → standard assignment + COLA seed land). Architecturally correct, heavier; needs product-catalog impact analysis; must isolate from the new-business derived-maintenance path (tier×Source_List_Price__c).

## Gates before any fix
1. **Pricing policy (Nir/COLA owner):** is ANY partner discount intended on the RM **net**, given `Prior_Partner_Discount__c` (8.52) is already subtracted inside the COLA net? (Determines single-vs-double discount.)
2. Procedure reactivated/resynced (was mid-republish, 0 active ExpressionSetVersions) to validate.
3. **Order-side parity:** `PartnerNetPricePosthook.applyNetPricesToOrder` is structurally inert for this (queries QuoteLineItem with OrderItem ids → 0 rows); OrderItem 802WC00000OgsuEYAR on order 00095475 carries the same 60.64 → Workday exposure. Any fix must address the order side.

## Residual unknowns
- Whether creation-time `UnitPrice` durably forces `NetUnitPrice` on a derived line (needs fresh FINEST proof).
- The nested **54.58** line (cy334, COLA 60.64) = second-generation double-discount (renewal of an already-corrupted line promoted to Base) — confirm fix corrects multi-generation chains.
- `$0` no-contributor lines (cN584, ck6X4) are a separate sub-defect (never become priced nodes) — not fixed by either direction without a contributor/seed.
- Why `PartnerDiscountPercent` flips 10↔12 (likely PartnerPricingService bulk-overload Software-15 vs Maintenance-12, peer-review B-3).

## ADDENDUM 2026-06-14 — 5th route tested + CREATION-PATH RCA (the actual fix locus)

**5th reprice-layer route DEAD:** seeded `UnitPrice=colaNet` in `COLAUpliftPrehook` (the deep-research direction-A lever). On reprice the canary's `UnitPrice` committed **67.38** (it IS writable) but `NetUnitPrice` stayed **60.64** (FINEST `unitprice_seed.log`: Net never 67.38). → setting `UnitPrice` post-creation does NOT propagate to the born `NetUnitPrice`; the dEW24 "UnitPrice→Net" link is **correlational, not causal**. Reverted to pristine. So all FIVE reprice-layer routes are dead; `NetUnitPrice` for a derived RM line is **born at creation, immutable thereafter**.

**CREATION-PATH RCA (definitive, data-proven):**
- A `Type='Renew'` QuoteAction line gets COLA applied AT CREATION: **dEW24** source asset `02iWC000008GKPaYAO` Price=**60.64** (prior net) → line **born NUP=67.38** (COLA applied), `QuoteActionId=7ocWC00000u7yf8YAA`.
- The **canary** maintenance line has **`QuoteActionId=null`** — auto-added ~17h post-creation by the **Year-2 Maintenance Product Configuration Rule**, bypassing the renewal pricing path → **born NUP=60.64, no COLA** → stuck.
- `COLAUpliftHandler` only processes lines with `QuoteActionId`→`QuoteAction.Type='Renew'` (lines 24, 39); auto-added lines are skipped at creation.

**Creation-path fix design (owner-gated, needs V14 + Nir):** make the auto-added Year-2 maintenance line get COLA at birth — (a) route it through the `Renew` QuoteAction / renewal pricing path, or (b) extend creation-time logic to stamp net=COLA at insert for auto-added RM lines. Existing ~6 wrong lines need re-creation/data fix. Next dig (owner-territory): the exact mechanism by which the `Renew` path lands the born NUP (RenewalQuoteLineHandler / platform initiateRenewal), to replicate for the auto-add.

### ADDENDUM 2026-06-14 — MULTI-ASSET confirms the cluster; defect locus = first-renewal RNM→RRM transition

MULTI-ASSET quote `0Q0WC0000037muD0AQ` (contract 00069264 / `800WC00000S99woYAB`): license leg `VM-BSL-RSL-BESECB` renewed via QuoteAction `7ocWC00000u7tqlYAA` (Type=Renew, src asset `02iWC000008F71PYAS`) → born-correct **4442.35**; maintenance leg `0QLWC000003cy334AA` (PIA-PIA-RRM-PIAM, `QuoteActionId=null`) auto-added → born-wrong **54.58** (=60.64×0.90), COLAcalc 60.64 correct. **The contract HAS a renewable maintenance asset `02iWC000008F71NYAS` PIA-PIA-RNM-PIAMBK Price 62.48** — but the renewal **auto-added a fresh RRM line via the Year-2 config rule instead of renewing the RNM asset** → no QuoteAction → born wrong. **Defect locus precisely = the FIRST renewal (RNM new-maintenance → RRM renewal-maintenance transition).** Subsequent renewals (prior asset already RRM, e.g. dEW24 src asset `02iWC000008GKPaYAO` PIA-PIA-RRM-PIAM Price 60.64) renew the RRM asset → Renew QuoteAction → born-correct 67.38 (lever (a) positive control). **All 4 SC-3404 lines = ONE defect, ONE fix (lever a); no per-line work remains.** RCA + fix COMPLETE; implementation owner-gated (renew the RNM maintenance asset on first renewal, or price the config-rule auto-add at birth) + re-create existing wrong lines.

### ADDENDUM 2026-06-14 (2) — lever (a) limited to 2nd+ renewals; F2 de-derive BLOCKED; SC-3404 needs build/catalog redesign

Empirical follow-up (read-only + 1 reverted prehook test):
- **Renewed RNM lines (New Maintenance + QuoteAction) commit NUP=null** (`0QLWC000003cMIj4AM` etc.) — the QuoteAction path does NOT apply COLA to RNM. **Only RRM+QuoteAction is born-correct** (dEW24=67.38), which needs a pre-existing RRM asset → **exists only on 2nd+ renewals.** At FIRST renewal there is NO born-correct path (renew RNM → born null + deleted by `RenewalQuoteLineHandler` carryover cleanup; config-rule auto-add RRM → born wrong on the derived line).
- Renewal pipeline = platform Asset-Renew (copies license + RNM) + Year-2 config rule (auto-adds RRM) + `RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes` (DELETES New-Maintenance + Perpetual carryover) + 4 post-creation pricers (`COLAUpliftPrehook`, `PartnerNetPricePosthook`, `RenewalMaintenancePricingService` @InvocableMethod, the V14 formula) — **all 4 no-op on the derived line.**
- **F2 (de-derive RRM-PIAM) BLOCKED:** `PricebookEntry.IsDerived` is `updateable=False` (can't flip existing PBE `01uWC000006XPPBYA4`); re-pointing its 6 QLIs to a new non-derived PBE needs Quote/QLI DML (RLM-locked). De-derive ⇒ deactivate+recreate PBE + re-create lines = catalog redesign, not a reversible flip. (PBE `01uWC000006XPPBYA4` = RRM-PIAM/Fortra-PB, IsDerived=true, only 6 QLIs; 464K legacy RRM use other PBEs.)
- **CONCLUSION: SC-3404 has NO surgical UAT fix. Resolution = build/catalog redesign (Nir):** recreate RRM-PIAM as a non-derived/born-priceable product, OR redesign the first-renewal RNM→RRM transition to born-price the line, + re-create the ~6 existing wrong lines. Every other lever is validated-dead.

### ADDENDUM 2026-06-14 (3) — selling-model dimension + F2 PBE de-derive DEFINITIVELY blocked (executed + reverted)

- **Why the line is derived (precise):** the Year-2 config rule `14OWC0000022Eyb2AE` AutoAdds RRM-PIAM with **empty actionParameters** → the line takes the product's **default ProductSellingModelOption**, which is **One Time (OneTime, derived)** (PSMO-000011295 `IsDefault=True`, PSM `0jPWC00000005yz2AA`). The other PSMO is Term-Based-Annual (`0jPWC000000060b2AA`).
- **Multi-currency split (SC-3384 family):** USD RRM = **derived** + COLA-stamped but born-wrong (72 live lines, both One-Time PBE `01uWC000006XPPBYA4` and Term-Based PBE `01uWC000005wsbVYAQ` are IsDerived=true); **EUR/GBP RRM = non-derived** but **flat UnitPrice, NO COLA** (51 lines, NUP/Base/COLACalc all null). So renewal-maintenance COLA works in **no** currency. No EUR/GBP positive control (all on non-Draft quotes).
- **F2 PBE de-derive EXECUTED + REVERTED (pristine):** deactivating the derived PBE `01uWC000006XPPBYA4` succeeded, but **creating a non-derived replacement FAILED** — "This price definition already exists in this price book": the PBE uniqueness key (Product2+Pricebook2+ProductSellingModel+Currency) **stays occupied even when the PBE is IsActive=false**; combined with `IsDerived` updateable=False and the PBE being undeletable (6 QLI refs + RLM), **the derived USD RRM PBE is PERMANENT.** Reactivated `01uWC000006XPPBYA4` → IsActive=true/IsDerived=true (pristine).
- **DEFINITIVE FINAL: no config/data surgery can make USD RRM-PIAM non-derived.** Resolution requires a BUILD change: a NEW non-derived renewal-maintenance SKU (or new non-derived selling model) that the config rule auto-adds instead, + the COLA InputUnitPrice seed + re-create existing lines. Owner/build (Nir), entangled with SC-3384.
