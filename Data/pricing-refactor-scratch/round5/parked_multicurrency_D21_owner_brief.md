# Parked Owner-Decision Brief — Multi-Currency FX Removal + D-21 Currency Config-as-Code

**Round 5 · Tab 3 · Read-only close-out · 2026-07-08**
Consolidates the two parked multi-currency items into one decision packet: **(A) the FX-step-removal sequencing** (SC-3384 anti-pattern) and **(B) D-21 / OQ-6 `Currency_Conversion_Formula__mdt` config-as-code**. Both are **non-urgent, owner-gated, native-V21-canvas** items. Sources: memory `reference_rlm_multicurrency_best_practice` and plan §5.4/§7 — not re-researched here; live V21 specifics re-confirmed against today's fresh retrieve.

---

## 0. TL;DR — decision needed

> **Approve the sequence: (1) make the list-price lookup currency-aware → (2) then delete the 4 hardcoded-FX steps → (3) 0-delta debug-verified cutover; and (4) THEN retire/decide `Currency_Conversion_Formula__mdt` (D-21) — do not invest in it before step 2, it likely becomes moot.** Risk today is *latent, not live* (the EUR catalog is uniformly USD×0.9346, 373/373 → converges → no current mispricing). This is a durability/correctness-of-design fix, not an incident.

---

## PART A — Remove the hardcoded-FX anti-pattern (SC-3384)

### A1. What is live in V21 today (re-confirmed 2026-07-08)
- The org **HAS authoritative per-currency PricebookEntries** (USD 19,198 rows; AUD/EUR/GBP/CAD ~18,333; CHF/ARS/JPY/ILS/NZD ~16,410). The real foreign-currency prices already exist as data.
- The **list-price resolver is native**, not Apex: an `actionType=ListPrice` element (full-file ~line 115391) → `ListPriceField = Constant_UnitPrice_Price_Book_Entry_Decision_Table_v2_LP` → decision table **`Price_Book_Entry_Decision_Table_v2`** (~line 115454; the DT-backed element itself is defined ~line 117687). The DT is **currency-keyed** (4-way match `Product2Id AND Pricebook2Id AND ProductSellingModelId AND CurrencyIsoCode`), source `PricebookEntry`, `usageType=DefaultPricing`, and the `CurrencyIsoCode` input is correctly hydrated from `Quote.CurrencyIsoCode`. **BUT** `isIncrementalSyncEnabled=false` → static HBASE snapshot that does not auto-refresh when PBE data changes (stale-index fragility).
- V21 then runs **4 hardcoded-FX "Currency Conversion" steps** (top-level seq **38–41**), each `X * IF(STICurrencyIsoCode='EUR',0.9346, IF('GBP',0.7874, IF('CAD',1.3889, IF('AUD',1.5385, …))))`. The four `X`:

| seq | Label | Formula base `X` → target |
|---|---|---|
| 38 | Currency Conversion – Net Unit Price | `NetUnitPrice * IF(...)` |
| 39 | Currency Conversion – Unit Price Display | `Base_Price__c * IF(...)` |
| 40 | Currency Conversion – Net Total / Subtotal | `ItemNetTotalPrice * IF(...)` |
| 41 | Currency Conversion – Total Line Amount | `TotalLineAmount * IF(...)` |

(Four hardcoded rates verbatim from today's retrieve; match the memory note exactly.)

### A2. Why this is the documented anti-pattern
Salesforce RLM best practice (RLM Dev Guide + Object Reference, adversarially verified): **per-currency `PricebookEntry` is the authoritative price; FX rates are for display/rollup conversion of already-stored amounts only, NEVER a price-derivation mechanism.** Deriving a foreign price as `base × FX-constant` in the procedure is the explicitly-named anti-pattern. Runtime evidence: a EUR line commits `Base_Price__c = 15000` (the USD PBE figure) and `NetUnitPrice = 14019` (= 15000 × 0.9346) → **the lookup effectively yields USD and the FX steps do the only conversion → the FX steps are LOAD-BEARING today.**

### A3. The trap (why you cannot just delete the 4 steps)
Because the resolver currently returns the **USD** figure, **deleting the 4 FX steps in isolation strands every non-USD line at the USD price.** The steps must be made *redundant* before they are removed.

### A4. Recommended sequence (owner-gated; DO NOT reorder)
1. **Make the list-price lookup currency-aware** so a EUR line draws the real **EUR** PBE (native config — the DT is already currency-keyed; ensure the resolved amount is the transaction-currency PBE `UnitPrice`, and address the `isIncrementalSyncEnabled=false` staleness so the snapshot reflects live PBEs). *This is the core SC-3384 fix.*
2. **THEN delete the 4 `Currency Conversion` FX steps** (seq 38–41) — now genuinely redundant. Deleting before step 1 = regression (strands USD).
3. **0-delta debug-verified cutover:** gate on S9(EUR)/S10(GBP)/S11b(EUR) + full currency matrix; a **UI reprice** (not API — programmatic reprice lacks native-engine internals) to prove per-line amounts are unchanged where the catalog already converges and *correct* where a PBE was set independently.
4. **THEN** the currency-CHANGE handler (**OQ-2 / D-10b**: wired `QuoteCurrencyChangeService` no-op vs orphan `_Fixed` reconverter) Force-reprices on top — downstream of, and dependent on, steps 1–2.

### A5. Risk posture
- **Live risk today: none observed.** The EUR catalog is uniformly `USD × 0.9346` (373/373 products, 0 exceptions) → FX path and PBE path converge → no current mispricing.
- **Latent risk: real.** The anti-pattern breaks the instant any single PBE is set independently of the FX constant, or the FX rate drifts from the catalog ratio, or a currency without a hardcoded branch is quoted. It also compounds with the stale DT snapshot.
- **Fix risk:** moderate — native V21 canvas, in-place (per `pricing-proc-v21-inplace`), co-owned change window (OQ-7). Behavioral → parallel-run/matrix-gated.

---

## PART B — D-21 / OQ-6: `Currency_Conversion_Formula__mdt` config-as-code

### B1. The item
`Currency_Conversion_Formula__mdt` stores **executable formula strings parsed/evaluated at runtime** (config-as-code; INV-24). D-21 composite score 6 (S3/E4/R4) — behavioral, boundary, map-only unless approved.

### B2. The decision (OQ-6)
> Keep the executable-string formulas, or migrate to **pure `Conversion_Rate__c` decimal** config (data, not code)?

- **Owner:** Pricing/Finance config owner.
- **Argument to migrate:** an executable string in an MDT is opaque, untestable, and a code-injection/parse-failure surface; a plain decimal rate is inspectable data with no runtime `eval`.
- **Argument to leave:** if Part A proceeds, **FX is removed from price derivation entirely** — the MDT's formulas may become **legacy/unreferenced**, in which case the right move is to *retire* it, not refactor it into decimals.

### B3. Recommended sequencing (ties B to A)
**Defer the D-21 decision until AFTER Part A step 2.** Do not invest in converting executable strings → decimals for a config object that the FX-removal may render moot. Order:
1. Complete Part A steps 1–2 (per-currency PBE authoritative; 4 FX steps deleted).
2. **Re-grep** for live references to `Currency_Conversion_Formula__mdt` (procedure, Apex, flows). If **zero live readers remain** → **retire the MDT** (map-only, then delete-after-confirm) and OQ-6 is closed by deletion. If a genuine non-price-derivation reader remains → **then** decide executable-string vs `Conversion_Rate__c` decimal for that residual use only.

### B4. Risk posture
Map-only today (no action without approval). Migrating executable→decimal is behavioral (changes how a rate is produced) and must be parallel-run-gated; retiring after Part A is low-risk (reference-proof + 0-delta).

---

## Consolidated recommendation

| # | Action | Gate | Owner |
|---|---|---|---|
| 1 | Currency-aware list-price lookup (EUR line ⇒ EUR PBE); fix DT staleness | S9/S10/S11b + matrix, UI reprice | Pricing owner (Marc/Joe) + Rev Cloud admin |
| 2 | Delete the 4 FX steps (seq 38–41) — **only after #1** | full-matrix 0-delta, UI-verified | Pricing-proc admin (Liam/Nir), OQ-7 window |
| 3 | Currency-change handler decision (OQ-2/D-10b) on top | reprice a currency-change scenario | Pricing owner |
| 4 | D-21/OQ-6: re-grep `Currency_Conversion_Formula__mdt`; retire if unreferenced, else decide decimal-vs-string | reference-proof; parallel-run if kept | Pricing/Finance config owner |

**One-line decision for the owner:** *approve sequence 1→2→3, then handle D-21 (#4) as a consequence of #2 — and do not delete FX steps or touch the FX MDT before the currency-aware lookup is proven.*
