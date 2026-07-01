# V21 Fix — Portion 3 (Derived-PBE Data) — Results

**Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`) · **Date:** 2026-06-30 · Active proc **V21** (ESDV `9QBWC0000000oWH4AY`).
**Status:** Read-only preflight complete. **No DML performed.** J-09 ready-to-fire pending Marc DeBrey sign-off + DML auth. J-10 **blocked as specified** (escalation required).

---

## J-09 — Derived line prices silent-null (SC-3372 / M5-PBEDP) — READY, GATED

**Symptom reproduced live:** QLI `0QLWC000003KEbO4AW` (EFT 8 Express-NewMaintenance, PBE `01uWC000005wsZpYAI`, IsDerived=true, 0 PBEDP rows): NetUnitPrice=null, ListPrice=0, Source_List_Price__c=null. `DerivedProductsNativePull` returns silent null when an IsDerived PBE has no PBEDP contributor row.

**Mechanism validated:** all PBEDP insert fields are createable (`PricebookEntryId`, `ContributingProductId`, `Formula`, `PricingSource`, `DerivedPricingScope`, `EffectiveFrom`, `EffectiveTo`, `Legacy_Rule_Id__c`). `ProductId`/`ProductSellingModelId` are read-only/auto-derived (not set). Reversible by deleting `Legacy_Rule_Id__c='M5-PBEDP-20260630'`.

**Scope correction (staged CSV was stale, built 2026-06-14 V14-era):**
| `backfill_HICONF.csv` scope | rows | disposition |
|---|---|---|
| Active **Fortra Price Book** `01sWC0000022GHFYA2` | **253** | ✅ actionable — IsDerived+active+uncovered; all 137 contributors have an active priced USD FPB PBE |
| Standard Price Book | 221 | ❌ excluded (hard-rule forbids; doesn't price live quotes) |
| "Fortra Derived Pricing" (inactive) | 2 | ❌ excluded |
| **Total CSV** | 476 | → **253 actionable** |

**Ready-to-fire payload:** `Data/pricing-v21-validation/portion3/j09_import_253.csv` (253 rows, marker `M5-PBEDP-20260630`).

**Blast radius:** 47,039 existing QLIs sit on these 253 PBEs (20,385 Approved · 9,237 Draft · 16,982 no-status · 434 In Review). New PBEDP rows change pricing on next reprice — bulk write needs Marc's contributor confirmation, not a casual insert.

**Decisive single-row proof (no quote-building needed):** insert PBEDP for PBE `01uWC000005wsZGYAY` (Advanced Authentication Modes-NewMaintenance) ← contributor `01tWC00000DD11YYAT`, then Force-reprice DRAFT QLI `0QLWC000003DAHl4AO` (Quote `0Q0WC00000297R80AI`, currently Net=null/List=0); expect Source_List_Price__c + NetUnitPrice to resolve. Regression control (covered, untouched): BoKS USD PBE `01uWC000005wsbVYAQ`.

**Evidence case (EFT 8 Express) needs Marc:** name "EFT 8 Express" resolves to 4 products (2 active: `GS-GSE-NRPS-EFEP` perpetual, `GS-GSE-RSS-EFES` subscription) → ambiguous; not in the 253. On the evidence quote the paired license line is **GS-GSE-RSS-EFES** (`01tWC00000DD1E4YAL`, List=958.8) → recommend RSS subscription as contributor, **pending Marc's confirmation**.

**GATE:** SC-3372 standing rule requires fresh explicit DML auth + Marc DeBrey contributor-mapping confirmation before write. **Held.**

---

## J-10 — EUR derived-maintenance prices $0 (SC-3384) — BLOCKED AS SPECIFIED

**Symptom reproduced live:** EUR QLI `0QLWC000003kinW4AQ` (BoKS NewMaintenance): Net=0, ListPrice=0, **COLACalculatedPrice__c=3666.90 stamped but never committed**. EUR PBE `01uWC000005wzX8YAI` IsDerived=**false**; USD twin `01uWC000005wsbUYAQ` IsDerived=true. Committer (`DerivedMaintenanceNetFilter`/`DerivedProductsRenewals`) gates on `ItemIsDerived__std` ← PBE.IsDerived.

**The specified fix is impossible.** `PricebookEntry.IsDerived` REST describe = **`updateable=False`, `createable=True`** — set-on-create only, cannot be PATCHed. So "Bulk/REST update IsDerived=true on non-USD PBEs" cannot run.

**Only data path is destructive.** Delete+recreate the non-USD PBEs is the sole way to set IsDerived, but the flip set = **17,001 PBEs** (1,889 products × 9 currencies: ARS/AUD/CAD/CHF/EUR/GBP/ILS/JPY/NZD), referenced by **131,331 QLIs + 29,710 OrderItems**. Recreating would orphan all of them. Not viable.

**Why the dossier missed it:** it asserted "REST/Bulk update only" without checking field updateability; and "0 non-USD derived PBEs exist" is itself a *symptom* of create-only (the flag was never settable post-creation).

**Real lever is the V21 procedure (Portion 1 boundary):** the non-USD derived-maintenance commit gates on the non-settable `PBE.IsDerived`. The fix is procedure/architecture — either stop gating the commit on PBE.IsDerived for the non-USD path, or source `ItemIsDerived__std` from a settable proxy. **Out of Portion 3's data-only boundary → escalate to Portion 1 / architecture.**

---

## Artifacts (`Data/pricing-v21-validation/portion3/`)
- `j09_import_253.csv` — ready-to-fire 253-row PBEDP payload (marker `M5-PBEDP-20260630`)
- `j09_actionable.json` / `j09_proof_candidates.json` — the 253 + ready proof targets
- `preflight_pbes.json` — live validation of all 476 CSV PBEs (pricebook/derived/active/coverage)
- `j10_flip.json` — the 17,001 non-USD PBEs that *would* need IsDerived (blocked)
- `preflight_pbes.py` / `preflight_j10.py` — reproducible preflight scripts

## Definition-of-done status
- J-10: **blocked** — cannot commit NetUnitPrice via data; IsDerived not updateable. Escalated.
- J-09: **staged + verified-ready**, single-row proof designed; **held** for Marc + DML auth.
- No regression risk to covered derived lines (J-09 only inserts; never touches existing PBEDP). UAT only — **nothing deployed to prod.**

---

# RE-EXAMINATION after Portion 1 partial deploy (2026-06-30, later)

Re-measured both evidence records against the **current** live V21 (post Portion 1's K-01/F-12 + G-01 canvas fixes), with a fresh MDAPI retrieve mapped to version blocks.

## J-10 — RECLASSIFIED: not a derived-PBE data defect; now a Portion 1 procedure defect
- **The $0 is GONE.** EUR QLI `0QLWC000003kinW4AQ` now commits a net (PBE.IsDerived still **false**). Portion 1's null-safe StampBaseFilter (K-01/F-12) removed the abort that was the real cause of the $0 — **IsDerived was never the gate**, and is `updateable=False` anyway (original fix doubly invalid).
- **Residual = FX-compounding (unstable).** Net compounds DOWN every reprice: **2613.44 → 2149.42 → 1767.79** (×0.8225 = 0.9346 EUR-FX × ~0.88/reprice). Root cause confirmed in active V21 metadata: step **`CurrencyConversionNetUnitPrice`** reads the *persisted* `NetUnitPrice * IF(STICurrencyIsoCode='EUR',0.9346,…)` — the **NetUnitPrice analog of G-01** (which Portion 1 fixed for `CurrencyConversionUnitPriceDisplay` → `Base_Price__c`, now stable; UnitPrice held steady at 3177.64 across my 3 reprices).
- **Hand-off to Portion 1:** change `CurrencyConversionNetUnitPrice` formula-section-0-input base from `NetUnitPrice` → a pre-FX base (`Base_Price__c` / `COLACalculatedPrice__c`), apply FX once. Expected ≈ 3666.9 (COLA) × FX ≈ 3427, stable. SC-3384 currency family (sibling of G-01/G-02). **Nothing for Portion 3.**
- Version mapping (fresh retrieve): `NetUnitPrice*FX` present in V20/**V21**/V22; `Base_Price__c*FX` (G-01 fix) in V20/**V21**. The lone unpatched StampBaseFilter `…AND 5` and stale `InputUnitPrice` copies are in **V22 (inactive)** only — active V21 is clean on those (no false alarm for Portion 1).

## J-09 — UNCHANGED by Portion 1; still a Portion 3 data defect
- EFT8 QLI `0QLWC000003KEbO4AW` still Net=null/List=0 after current-V21 reprice. The null-safe StampBaseFilter lets repricing proceed but leaves the line unpriced because there is still **no PBEDP contributor row** to source a price. Still needs the **253-row PBEDP backfill** (held for Marc + DML auth). The native-pull data gap is orthogonal to Portion 1's proc fixes.

**Net effect of re-examination:** Portion 3's actual remaining work = **J-09 only** (the 253-row PBEDP backfill, gated). J-10 leaves this work-stream entirely → Portion 1 (`CurrencyConversionNetUnitPrice`).
