# SC-3384 — Comprehensive Report: Non-USD Quote Pricing Uses USD Values for Configured Products

**Ticket:** SC-3384 (Jomil's multi-currency priority; build by Marc/Nir/Liam)
**Repro:** Quote `0Q0WC0000036xy90AA` (# 00780956, **EUR**), Pricebook `01sWC0000022GHFYA2`, FortraUAT
**Status:** RCA complete + adversarially peer-reviewed (`20_PEER_REVIEW.md`) + **all 6 gating blockers re-verified live 2026-06-11** (read-only). Build-ready **except one live gate** (a fresh FINEST reprice — §6). No DML/deploy performed.
**This document** supersedes the framing in `02_ROOT_CAUSE_AND_FIX_SPEC.md` where they differ; 02 remains the detailed per-defect appendix, `10_…` the org-wide reach, `03_…` the currency/rate authority. Live evidence: `evidence/LIVE_REVERIFY_2026-06-11.md`.

---

## 1. BLUF (one paragraph)

On a non-USD quote, **base list prices are correct** (the PricebookEntry read is currency-keyed) but **every configured/derived price** — attribute overrides, server-type discounts, attribute-tier prices — is read from a **USD-only** supporting record by a **currency-blind lookup** and written verbatim onto the EUR line. The cause is **two reinforcing failures that must ship together**: (1) **DATA** — the configured-pricing datasets are 100% USD (`AttributeBasedAdjustment` = **13,072 rows, 0 non-USD**, confirmed live; `Attribute_Tier_Pricing_Storage__c` = 1,115 rows, USD); and (2) **CONFIG/CODE** — the lookups that consume them omit currency (the ABA decision table `0lDa50000007BEuEAM` has no `CurrencyIsoCode` key; `AttributeVolumePricingPrehook` omits currency from its SOQL and composite key). It is **not** "only a data issue." **The single remaining gate before build** is a fresh FINEST reprice of the repro quote: the headline AAMP line shows `Has_Attribute_Adjustment__c=false`, so its 3150/1575 may be stored/migration residue rather than live engine output — that must be re-grounded before anyone edits the shared ABA override layer.

---

## 2. The 6 gating blockers (B1–B6) — live-verified + resolution

These are the peer-review BLOCKERs. Each is now confirmed against the live org; "Resolution" is what the builder does.

### B1 — The Advanced-Auth EUR price is not proven live engine output
- **Claim:** the AA line's net 3150/1575 may be migration/stored residue; the server-type override has never actually fired on it (configured attribute combo matches no live-active override row; the attribute-pricing gate flag is false). Re-price fresh with FINEST before treating it as a currency bug.
- **Live verify:** QLI `0QLWC000003cBGr4AM` = EUR, **`Has_Attribute_Adjustment__c=false`**, Unit 3150 / Net 1575 / List 2898 / Qty 1. (Correction to the source note: the *QLI* CreatedDate is **2026-06-09**, not 2026-05-06 — the 2026-03-24/migration date belongs to the ABA rows, not this line.)
- **Resolution / what it means:** **TOP GATE.** Force a fresh Reprice with a FINEST pricing log on the repro quote and read each QLI's price-impacting attributes, `Has_Attribute_Adjustment__c`, `PricingSource`, `LastPricedDate`. If the override genuinely doesn't fire on a live reprice, the *Family-A "currency-blind lookup grabs USD" headline does not apply to AAMP* and the AAMP fix is moot for this SKU — re-ground on freshly-priced data first. (Records: Quote `0Q0WC0000036xy90AA #00780956 EUR`; QLI `0QLWC000003cBGr4AM`; Product2 `01tWC00000DD11YYAT` GS-GSE-NRPS-AAMP.)

### B2 — One step cannot have produced both 3150 and 1575
- **Claim:** the two server-type override rows apply to mutually-exclusive attribute combinations — `00000219 {SFTP, On-Prem, Production}→3150` and `00000220 {Remote Agent, On-Prem, Non-Production}→1575` — so a single line can't pick up both; 3150 (subtotal) and 1575 (net) must come from two different pricing steps (the procedure has two AttributeBased steps on this table). Trace the actual emitter of each value before changing any override.
- **Live verify:** product `01tWC00000DD11YYAT` has **3 USD Override rows**: `00000220`=**1575** (hash `9da979e8…`, active), `00000219`=3150 (hash `adf67826…`, **expired 2026-06-01**), `00022777`=**3150** (hash `adf67826…`, active). The two **active** rows have **different hashes** ⇒ mutually-exclusive combos ⇒ one match can't yield both. Confirmed.
- **Resolution:** rewrite the AAMP mechanism to span **both** ABA steps in V13 (an `AttributeBasedPrice`-type step writing Subtotal 3150 and an `AttributeDiscountEntries` step writing Net 1575), each keyed on its own hash/effective-date inputs. Pin each emitter with the B1 FINEST trace before any override edit. (Records: ABARule 00000219→3150, 00000220→1575, 00022777→3150; steps `AttributeBasedPrice` + `AttributeDiscountEntries` in Rev_Mgmt_Default_Pricing_Procedure V13.)

### B3 — Build from the active version (V13), with a context re-sync
- **Claim:** active pricing procedure is **V13** (the only Active version; the SC-3393 services-add null-guard). Branch from V13, republish, re-sync the context; pull the active version live every time (it moved V9→V12→V13 within days). Editing an older version in place has caused `contextDefinitionName` gacks.
- **Live verify:** V13 active (confirmed via the SC-3393 V130 retrieve + SC-3346 work). API `Rev_Mgmt_Default_Pricing_Procedure`; context `SalesTransactionContextExt_v2`.
- **Resolution:** every config change = **new ExpressionSet version off live V13 → republish → re-sync `SalesTransactionContextExt_v2`**. Never edit an older/inactive version in place. Version hard-delete is blocked; do not remove the two `PricingActionParameters` (Quote/Order) bindings. (Records: Setup → Price Management → Pricing Procedures → Revenue Management Default Pricing Procedure → Versions → V13 = Active.)

### B4 — Adding a currency key to `0lDWC0000000Gft2AE` would do nothing
- **Claim:** decision table `0lDWC0000000Gft2AE` (Attribute Tier Pricing Matrix) is **not referenced by any procedure version, including V13**, so currency-keying it has no effect; the attribute-tier pricing is computed in **Apex** reading the storage object, not a procedure matrix. The table that needs the key is `0lDa50000007BEuEAM` (used **twice** in V13).
- **Live verify (grep of the live V13 body):** `0lDa50000007BEuEAM` appears **2×**; `0lDWC0000000Gft2AE` appears **0×**; volume-tier `0lDa50000007BEsEAM` **1×**; PBE table `0lDa50000007BErEAM` **1×**. Confirmed.
- **Resolution:** **STRIKE `0lDWC0000000Gft2AE`** from the config work. The currency key goes on **`0lDa50000007BEuEAM`** only (Workstream B). The attribute-tier (CLSAAS) currency fix is **Apex + data only** (Workstream C). Also add `0lDa50000007BEsEAM` to the audit — it is a second absolute-value table and a candidate source of BESEPB's 824. (Records: DecisionTable `0lDWC0000000Gft2AE` (unused), `0lDa50000007BEuEAM` (used 2×).)

### B5 — The line-item currency attribute is `STICurrencyIsoCode`
- **Claim:** the Apex hook needs the *line's* currency, but at the line node the attribute is **`STICurrencyIsoCode`**; plain `CurrencyIsoCode` exists only on the transaction header, so reading it on a line returns nothing. Separately, filtering the storage SOQL by currency makes EUR lines return zero rows and **keep their old prices** (early-return) instead of resetting — so the currency match must be enforced in the **lookup KEY, not the query filter**.
- **Live verify:** context def `SalesTransactionContextExt_v2` — header node `CurrencyIsoCode` (line 60-61); **item node `STICurrencyIsoCode`** (line 903-905, inherited from `SalesTransactionItem/STICurrencyIsoCode`). Confirmed.
- **Resolution (Workstream C):** capture **`STICurrencyIsoCode`** from the item context tag (fail-open: blank token → no currency filter + log). Thread currency into the **composite key** (`buildCompositeKey`, `buildTierLookupMap`, `lookupTierFromMap`) — **do NOT add a currency predicate to the bulk SOQL** (`cls:211-219`), because an empty result hits the `allTiers.isEmpty()` early-return (`cls:224-227`) and the line keeps **stale** values rather than resetting. A no-match in the key falls through to `buildResetNodeUpdate` (the intended reset). Test rework is ~12 methods (5-part key fixtures + `STICurrencyIsoCode` on every item fixture). (Records: ApexClass `01pWC000001wAzJYAU` AttributeVolumePricingPrehook; context line node `STICurrencyIsoCode`.)

### B6 — Load the EUR data before the config goes live
- **Claim:** a currency-key change is a single republish + context re-sync; loading EUR rows is a separate job. If the republish lands first, every live non-USD line that re-prices in that window loses its configured price (resets to list, or to 0 on the attribute-tier line). Load + verify EUR data first; deploy config in a low-traffic window.
- **Live verify:** ABA = **13,072 rows, 100% USD (0 non-USD)**; CLSAAS EUR line `0QLWC000003cE8H4AU` already shows **Net=0** with Unit=1357.2 (USD tier) despite its EUR PBE `01uWC000005wyVjYAI` (2005.6) existing. Confirmed — the corruption window is real.
- **Resolution:** **strict sequencing — EUR data loaded AND verified, THEN config/code deploy.** Not "concurrently." Pause reprice automation if feasible; low-traffic window. (Records: QLI `0QLWC000003cE8H4AU` (Net=0); PBE `01uWC000005wyVjYAI` (EUR).)

---

## 3. Confirmed root cause — currency-blind lookups over USD-only data

The base list read filters by currency; every other pricing surface does not.

| Pricing surface | Lookup target | Currency in match key? | Data | Defect |
|---|---|---|---|---|
| PBE read (`0lDa50000007BErEAM`) | PricebookEntry | **YES** | per-currency PBEs exist | none (list correct) |
| ABA override steps → `0lDa50000007BEuEAM` (V13 ×2) | AttributeBasedAdjustment | **NO** (schedule/product/PSM/dates/hash) | 13,072 USD | BESEPB 824, AAMP 3150/1575, VMA 500 |
| Volume-tier → `0lDa50000007BEsEAM` (V13 ×1) | (tier) | **NO** | USD | candidate BESEPB 824 source — verify |
| Apex `AttributeVolumePricingPrehook` SOQL+key | `Attribute_Tier_Pricing_Storage__c` | **NO** | 1,115 USD | CLSAAS 1357.2 (Net=0 downstream) |
| Auto-add maintenance resolver (managed) | PricebookEntry | **NO** | EUR PBE exists | PIAMBK add failure (wrong PBE) |
| Hardware / Regional / Partner / COLA prehooks | multipliers/% | n/a | currency-agnostic | none |

**Pattern:** wherever pricing stores an **absolute amount per currency** and the lookup is currency-blind over USD-only data → the EUR line consumes USD. Wherever pricing is a **multiplier/%** off the already-correct context price → no defect.

---

## 4. Per-line-family classification (corrected post-peer-review)

| SKU / line | Family | Mechanism | DATA fix | CONFIG/CODE fix | Status |
|---|---|---|---|---|---|
| **CLSAAS** (HRM-HRM-RSL-CLSAAS) | attribute-tier (Apex) | `AttributeVolumePricingPrehook` hits USD tier 1357.2; Net=0 downstream | EUR tier rows | **Apex** SOQL/key currency (WS-C) | **build-grade** (the one ready leg) |
| **BESEPB** (VM-BSL-RSL-BESEPB) | tier/override | 824 = USD ABA Override (or volume-tier `…BEsEAM` — **pin live**) | EUR ABA rows | currency key on `…BEuEAM` (WS-B) | confirmed mechanism; **824 emitter unpinned** |
| **AAMP** (GS-GSE-NRPS-AAMP) | server-type discount | 3150 + 1575 via **two** ABA steps (B2); flag=false (B1) | EUR rows *(Option B)* / none *(Option A %)* | **durable** (WS-B) | **GATED on B1 fresh reprice + B2 two-step trace** |
| **VMA** (VM-VLM-NRSU-VMA) | attribute override | USD ABA Override 500 | EUR ABA rows | **reclassified DATA+CONFIG** — routes through the same no-currency `…BEuEAM` (peer-review correction) | not "pure data"; verify with a one-row EUR sandbox |
| **PIAMBK** (PIA-PIA-RNM-PIAMBK) | auto-add maint | wrong-PBE pick; EUR PBE `01uWC000005wzX8YAI` exists | none | **CONFIG** — currency filter on the (unidentified) auto-add resolver | **PARTIAL** — resolver unidentified (may be a non-editable managed PCR); couples to SC-3346 (NO-GO) |

Net: only **PIAMBK** is purely CONFIG; **no** family is purely DATA after VMA's reclassification (peer-review flipped "1 of 5 pure data" → 0). Wren's "only a data issue" is **false**.

---

## 5. Build-ready fix spec (corrected)

> **Sequencing (non-negotiable, B6):** EUR data **loaded AND verified**, THEN config/code deploy. Low-traffic window; pause reprice automation if feasible. Every procedure change = new version off **live V13** → republish → **re-sync `SalesTransactionContextExt_v2`** (B3).

- **WS-A — DATA seed (EUR-only MVP).** Seed `AttributeBasedAdjustment` EUR rows (BESEPB, AAMP per Option choice, VMA full matrix) + `Attribute_Tier_Pricing_Storage__c` EUR rows (CLSAAS 37-row mirror). Derive values via the documented `CEILING(EUR_list × multiplier / 5) × 5`, **not** hand-authored absolutes and **not** mechanical USD×0.92 (the repro EUR lists are built at the corrupted 0.92, not authoritative 0.9346 — `03_…`). ABA is platform-managed (no Apex DML) → REST/composite-key load. **Owner: Marc.** *Split A1 (4 SKUs × EUR, this ticket) / A2 (org-wide backfill, separate ticket).*
- **WS-B — CONFIG: currency key.** Add `CurrencyIsoCode` (Equals/Required) to **`0lDa50000007BEuEAM` only** (strike the phantom `0lDWC0000000Gft2AE`, B4) + matching input to **both** ABA steps in a new V14 off V13; add `0lDa50000007BEsEAM` if the live trace shows BESEPB prices there. **AAMP Option A** (server-discount as a %, currency-neutral, also fixes SC-3360 sparse-matrix) is a **candidate pending business sign-off** (it sets EUR net 1449 vs observed 1575 — a business decision, not a refactor). **Owner: Nir** (coordinate with SC-3360 — same matrix).
- **WS-C — CODE: prehook currency.** `AttributeVolumePricingPrehook`: capture **`STICurrencyIsoCode`** (B5), thread currency into the **composite key only** (not the SOQL), fail-open on blank. ~12 test methods reworked. **Owner: Liam.**
- **WS-D — CLSAAS Net=0.** Trace the downstream `'Total Price'`-mode net-channel step in V13 (FINEST) and seed `NetUnitPrice/NetTotalPrice/TotalPrice`. Currency-independent; validate against a line that **stays in 'Total Price' mode** (i.e. after EUR data lands), since a WS-C miss flips the line to 'Unit Price' mode. **Owner: Nir.**
- **WS-E — PIAMBK auto-add.** Identify the auto-add resolver (likely a managed RLM `ProductConfigurationRule` — may not be editable per `project_pcr_no_migration_path`); add `CurrencyIsoCode = Quote.CurrencyIsoCode`; defensively filter `Get_Maint_PBE` in the (today-re-versioned) `Stamp_Maintenance_Pricing_Inputs`. **PARTIAL** — resolver ID is a hard gate. **Owner: Liam → Marc/Nir.**

**Out of scope (state explicitly):** existing non-USD Orders/Assets/Invoices/renewals already carry wrong configured nets (locked-currency design propagates Quote→Order→Asset→Invoice). 10_… shows 5,162 non-USD orders. Go-forward quoting only; the backfill is a separate ticket coordinated with SC-3350/SC-3346. Non-EUR currencies are **blocked on the rate reload** (7 currencies at ConversionRate=1.0; JPY doubly-wrong: rate 1.0 + zero-decimal DocGen).

---

## 6. The one remaining live gate (before any build)
A **fresh FINEST reprice of the repro quote `0Q0WC0000036xy90AA`** (a pricing/DML action — needs explicit go-ahead) to: (a) re-ground B1 (does the AAMP override fire live, or is 3150/1575 residue?); (b) pin the B2 emitters of 3150 and 1575 to exact V13 steps; (c) pin the BESEPB 824 source (ABA `…BEuEAM` vs volume-tier `…BEsEAM`); (d) localize the CLSAAS Net=0 element. Everything else in this report is verified read-only.

## 7. Effort & acceptance
- **Effort:** ~2 weeks parallelized — WS-A (L, Marc), WS-B (M, Nir), WS-C (M, Liam), WS-D (S, Nir), WS-E (S, gated). Org-wide backfill + rate reload + JPY DocGen are separate, larger.
- **Acceptance:** on the EUR repro quote — BESEPB net = EUR-correct (not 824 USD); VMA net = EUR-correct (not 500 USD); CLSAAS Subtotal pulls the EUR tier **and** Net ≠ 0; AAMP per the chosen Option; PIAMBK auto-adds without the PBE-currency error; **all USD lines byte-identical (3150/1575/824/500)**; full regression across AUD/CAD/GBP (and JPY/ILS once rates reloaded).

## 8. Records index (live-verified 2026-06-11 — `evidence/LIVE_REVERIFY_2026-06-11.md`)
Quote `0Q0WC0000036xy90AA` (#00780956 EUR; **4 lines — the 5th, PIAMBK maintenance, FAILS to auto-add on EUR, so the derived product is absent from the quote: that absence is the WS-E currency symptom, not a missing example**) · AAMP QLI `0QLWC000003cBGr4AM` (flag=false, 3150/1575) · Product `01tWC00000DD11YYAT` · ABA `00000219/00000220/00022777` · CLSAAS QLI `0QLWC000003cE8H4AU` (Net=0) · EUR PBEs `01uWC000005wyVjYAI` (CLSAAS), `01uWC000005wzX8YAI` (PIAMBK — this EUR PBE **exists** but a currency-blind resolver picks the USD PBE `01uWC000005wsbUYAQ`, so the maintenance line is rejected and never lands on the quote) · DecisionTables `0lDa50000007BEuEAM` (ABA, V13×2), `0lDa50000007BEsEAM` (volume-tier, V13×1), `0lDa50000007BErEAM` (PBE, V13×1), `0lDWC0000000Gft2AE` (phantom, V13×0) · ApexClass `01pWC000001wAzJYAU` · Context `SalesTransactionContextExt_v2` (item tag `STICurrencyIsoCode`) · Procedure `Rev_Mgmt_Default_Pricing_Procedure` V13 · USD schedule `84Xa50000010nWQEAY` · ABA census 13,072 USD / 0 non-USD.
