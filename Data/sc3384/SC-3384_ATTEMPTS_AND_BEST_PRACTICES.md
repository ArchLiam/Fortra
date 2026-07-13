# SC-3384 — Non-USD Quote Pricing Using USD Values for Configured Products
### Remediation attempts + multi-currency best practices (authoritative sources)

**Ticket:** SC-3384 (Critical) — "Investigate Non-USD Quote Pricing Using USD Values for Configured Products"
**Owner:** Liam Jeong (all SC-3384 pricing-engine workstreams)
**Date:** 2026-07-09
**Org:** FortraUAT

---

## 1. The defect in one paragraph

On a non-USD quote, the **base list price localizes correctly** (per-currency PricebookEntry exists), but the **configured Net / Subtotal / Total carry raw USD values** with a foreign currency symbol. Root cause: the approved multi-currency design (per-currency *static stored* prices, see §4) was applied to **list PricebookEntries only** and never extended to the **configured-pricing layer** — attribute/tier/server-discount adjustments and auto-add maintenance — whose lookups are currency-blind over USD-only data.

The ticket's five reported mechanisms collapse to **three root causes**:

| # | Root cause | Ticket lines | Driving component | Data state |
|---|---|---|---|---|
| 1 | Currency-blind **ABA** decision table | L1 tier-based, L2 server-discount, L3 attribute-based | `Attribute_Based_Adjustment_Decision_Table` (`0lDa50000007BEuEAM`) — no `CurrencyIsoCode` input | `AttributeBasedAdjustment` = 13,073/13,073 **USD-only**, 100% `AdjustmentType='Override'` (absolute price) |
| 2 | Attribute-tier storage data gap | L4 attribute tier | `AttributeVolumePricingPrehook` + `Attribute_Tier_Pricing_Storage__c` | EUR tiers for **1 SKU only**; CAD/GBP/AUD/JPY = 0 tier rows |
| 3 | Auto-add maintenance binds wrong-currency PBE | Auto-add maint | Managed RLM auto-add PCR | PBE resolved USD on a EUR quote → save blocked |

**Blast radius (real UAT records):** the ABA cause (#1) alone = **71,502 non-USD quote lines on 603 products** (EUR 35,641 / GBP 26,098 / AUD 7,843 / CAD 1,920).

---

## 2. What has been attempted / delivered this session

| Workstream | Scope | Status | Evidence | Commit |
|---|---|---|---|---|
| **E — Auto-add maintenance** | `QuoteLineItemCurrencyCorrectionHandler` (QLI before-insert) re-points a mis-currencied PBE to the quote-currency sibling before the platform's native currency validation | ✅ **DONE / PASS** | Live-confirmed on quote 00781700: both PIAMBK lines swapped USD→EUR PBE `01uWC000005wzX8YAI`; 0 mis-currencied QLIs across ~131k non-USD lines; tests 3/3 | `43fa4d1` |
| **C — Attribute tier lookup** | `AttributeVolumeCalculator` composite key + `AttributeVolumePricingPrehook` SOQL now include `CurrencyIsoCode` (tier lookup is currency-scoped) | ⚠️ **CODE DONE, DATA-BLOCKED** | Live-identical to force-app; 75/75 tests + 37/37 real EUR-tier smoke. Works for **EUR on 1 SKU**; every other currency has no tier data → needs Workstream A | `255f7c5` |
| **Smoke test** | Read-side smoke of all 5 mechanisms vs a fair sample of real UAT records; adversarially verified (blast radius independently recomputed) | ✅ Complete | `Data/sc3384/smoke_20260709.md` | — |
| **B + A — ABA fix (SUPERSEDED)** | Make the ABA decision table currency-aware (B) + seed per-currency ABA/ATPS data (A) — the 71k-line fix | ❌ **RETIRED** — 2 showstoppers (native element won't forward currency; value-factor Finance decision). Replaced by the posthook approach below. | `Data/sc3384/workstream_BA_scope_20260709.md` | — |
| **ABA currency-correction posthook** (the actual B+A fix) | Provenance-based Apex correction folded into `PartnerNetPricePosthook`: the procedure snapshots the raw per-unit USD ABA net into new field `ABA_Raw_Net__c`; the posthook localizes it by the static CMDT rate (`raw × 0.9346` = confirmed AAMP target 1471.995), per-unit, idempotent. Sidesteps BOTH showstoppers (no native forwarding, no 52k-row seed; CMDT rate resolves the value factor). | 🟡 **BUILT — deploy gated** (validated by 9-agent adversarial workflow; Apex+field+tests done; context-def + proc stamp staged) | code below; `Data/sc3384/GATED_ORG_STEPS_currency_correction.md` | (pending) |
| **Bulk-PBE tool review** | Investigated the "Bulk Price Update" generator's interaction with derived/maintenance pricing | 🅱️ **Backlogged** (per owner) | memory `project_bulk_pbe_derived_maint` | — |

### Smoke verdict table (real records)

| Ticket line | Mechanism | Verdict | Owner |
|---|---|---|---|
| L5 | Auto-add maintenance | ✅ **PASS** | E — done |
| L4 | Attribute tier storage | ⚠️ **PARTIAL** (code fixed, data-blocked) | C done + A |
| L1 | Tier-based (beSECURE) | ❌ **FAIL** — raw USD via ABA table | B + A |
| L2 | Server-type discount | ❌ **FAIL** — 50%×USD via ABA table (also Net=0 → D) | B + A (+ D) |
| L3 | Attribute-based (VM Analyst) | ❌ **FAIL** — USD override via ABA table (~+7%) | B + A |
| — | Base **list** price | ✅ PASS — per-currency PBEs ~100% coverage | (not the gap) |

---

## 3. Why B+A is not a same-day build (2 showstoppers from adversarial review)

1. **B likely cannot be wired like the currency-aware PBE table.** The ABA lookup is invoked by a **native `actionType=AttributeDiscount` Business Knowledge Model** with a *fixed* parameter contract that has **no `CurrencyIsoCode`**, and it builds its own match key (`AttributeAdjConditionsHash`, which does not encode currency). Adding a currency parameter is probably **inert**, and adding a `isRequired=true` currency column could regress **even USD** to list/$0. There is **zero in-org precedent** for this native element forwarding currency. → The real B fix likely needs an **Apex / generic-decision-table** approach (the Workstream C pattern), proven first by a **sandbox spike (hard gate)**.

2. **A's per-currency value factor is ambiguous and live data already disagrees.** Two EUR factors are live today: **0.9346** (static CMDT / PBE-list ratio — reproduces the AAMP target 1471.995) and **0.92** (runtime `CurrencyType.ConversionRate` — the existing EUR ATPS tier data, e.g. HRM 2,373.60). A single uniform rule cannot reproduce both. **Which factor is authoritative for configured net/tier values is an open Finance/Marc decision**, and the existing EUR ATPS data must be reconciled before seeding.

**Other scoping facts:** ship **B+A together** (key without data → list/$0; data without key → non-deterministic USD match); live pricing proc is **v23** (repo stale); `PriceAdjustmentTier` table is **out of scope** for this ticket (L1 routes through ABA); 61 `$0`-USD-PBE products overlap Workstream D — don't seed $0. Estimate ~6–10 dev-days if native wiring works; +3–5 if it forces the Apex fallback.

---

## 4. Multi-currency best practices — authoritative sources in the repo

> **Primary source:** *"Currency Conversion for Pricebooks"* — `Confluence/Currency+Conversion+for+Pricebooks.doc` (also under the SC-3384 Jira folder). Confirmed by **Marc DeBrey (2026-06-11)** as the authoritative design; references the Salesforce **AutoFX User Guide v1.3** and Salesforce native Multi-Currency framework.
> **Supporting source:** *Fortra Orders MultiCurrency Solution Design* — `docs/RCA Solution Guide/kb/Fortra-Orders-MultiCurrency-Solution-Design-Doc.md`.
> **Currency authority research:** SC-3384 Jira `03_CURRENCY_AUTHORITY_AND_RATES.md`.

### 4.1 The core principle (verbatim from the authoritative doc)

> *"The USD-based pricing formulas that Fortra requires are applied at the **product/pricebook level, NOT during the quoting process. This is a critical** [distinction]."*
>
> **Product Setup Phase:** *"Define master price in USD. Create pricebook entries for each currency using Fortra's conversion [rates]. Example: USD $1,000 → EUR €920, GBP £840, CAD $1,350. **These converted prices are stored as static values in pricebook entries.** Revenue Cloud automatically selects the EUR pricebook entries."*

**Restated as rules:**

1. **Per-currency prices are pre-generated STATIC stored values** — computed once, at product setup or on rate change, and read directly at quote time. **No runtime currency conversion in the quoting path.** (MultiCurrency SDD **A-008**: *"Product pricebook entries pre-created for all active currencies during initial product setup, NOT generated on-demand during quoting."*)
2. **USD is the master / corporate currency.** Every per-currency value = `USD master × Fortra conversion rate`.
3. **Use Fortra's governed conversion rates, NOT live exchange rates.** Doc: *"Using the rates below not current Exchange rates."* Rates live in `Currency_Conversion_Formula__mdt` (relative to USD), maintained by Finance — **not** the org's native `CurrencyType.ConversionRate` (which is unreliable here: e.g. GBP=1.0, JPY=1.0 live).
4. **Round up to the nearest $5.** (Doc, verbatim.)
5. **Revenue Cloud auto-selects the correct-currency PricebookEntry** via native parent→child currency inheritance (`CurrencyIsoCode`).
6. **Currency is set upstream and locked.** Set on the Opportunity (Legal-Entity-driven) **before** a Quote exists; the platform blocks currency change once Quotes exist — treated as a **design constraint, not a defect** (SDD BR-003 / A-004).
7. **On rate change**, `ExchangeRateUpdateTrigger` → `PricebookCurrencyUpdateBatch` re-generates PBEs across currencies, with `PricebookUpdateRollbackService` for recovery.

### 4.2 Currency scope (authoritative)

Core set = **USD, EUR, GBP, AUD, CAD** (the doc's rate table + SDD A-001), with **JPY** the only non-core currency carrying real volume → **core 5 + JPY** is the MVP. **MXN and SEK appear nowhere in the authoritative doc, have no ARR rate, and should not be in scope without a decision** (they are also active org currencies with zero conversion rows — a latent gap).

### 4.3 How the best practice maps to the SC-3384 fix

The best practice is already correct and implemented **for list PBEs** (`Price_Book_Entry_Decision_Table_v2` is currency-aware; base list ~100% covered). **SC-3384 is that same design not yet extended to the configured layer.** The compliant fix is therefore:

- **Data (Workstream A):** pre-generate the configured-pricing rows (ABA `AttributeBasedAdjustment`, `Attribute_Tier_Pricing_Storage__c`) per currency as **static stored values**, using the governed rate — exactly the A-008 pattern already used for list PBEs. **Not** a runtime conversion, **not** the native live FX rate.
- **Lookup (Workstream B / C):** ensure the configured-pricing lookup keys on `CurrencyIsoCode` so it selects the correct-currency row (C already does this for attribute tiers; B must do it for ABA).
- **Maintenance/derived products:** keep the PBE `$0` at list in every currency (net derives downstream) — the per-currency PBE must **exist** but must **not** carry a converted value. (See memory `project_bulk_pbe_derived_maint`.)

### 4.4 Anti-patterns (each reproduces or worsens SC-3384)

- ❌ Converting currency **at quote time** (runtime FX) instead of reading pre-generated static values.
- ❌ Using the native **`CurrencyType.ConversionRate`** for pricing math (GBP=1.0 / JPY=1.0 live → would leave those currencies at USD).
- ❌ Adding a currency **key without the per-currency data** (regresses non-USD to list/$0), or **data without the key** (non-deterministic USD/EUR collision) — they must ship together.
- ❌ Stamping a converted (non-zero) value onto a **derived/maintenance** PBE that must stay `$0`.
- ❌ Seeding **MXN/SEK** (or other non-authoritative currencies) without a rate/decision.

---

## 5. Recommended next steps

1. **Confirm Workstream C live (in progress):** UI-reprice `HRM-HRM-RSL-CLSAAS` on test quote **00781712** (`0Q0WC000003JasT0AS`) → expect EUR tier **€2,373.60**, not USD **2,580**.
2. **Escalate to Finance/Marc:** the per-currency **value factor** for configured net/tier (static 0.9346 vs the live 0.92 ATPS data) + the **currency scope** (core 5 + JPY vs all active).
3. **Phase-0 sandbox spike (hard gate)** for Workstream B: prove whether the native ABA element can forward `CurrencyIsoCode`; if not, pivot to the Apex/generic-DT fix.
4. **Then build B+A together** as one release (data seed via the governed static rate, currency-keyed lookup), validated with a real-records reprice like the C smoke.
5. **Workstream D (Net=0)** rides the ABA path — quantify and fold in with B.

---

## 6. Source index

| Source | Path | Type |
|---|---|---|
| Currency Conversion for Pricebooks | `Confluence/Currency+Conversion+for+Pricebooks.doc` | Authoritative design (Confluence, Marc-confirmed) |
| Orders MultiCurrency Solution Design | `docs/RCA Solution Guide/kb/Fortra-Orders-MultiCurrency-Solution-Design-Doc.md` | SDD (A-008, BR-003) |
| Currency Authority & Rates | `Jira/Defects/sc3384 .../03_CURRENCY_AUTHORITY_AND_RATES.md` | Research (rate table, scope) |
| Root Cause & Fix Spec | `Jira/Defects/sc3384 .../02_ROOT_CAUSE_AND_FIX_SPEC.md` | Research (workstreams A–E) |
| Smoke test (real records) | `Data/sc3384/smoke_20260709.md` | This session |
| Workstream B+A scope | `Data/sc3384/workstream_BA_scope_20260709.md` | This session |
| Bulk-PBE tool review | memory `project_bulk_pbe_derived_maint` | This session |

---

## 7. DELIVERED FIX — ABA currency-correction posthook (2026-07-09 build)

A 9-agent adversarial validation workflow (`sc3384-aba-posthook-validation`) confirmed the posthook
approach is the right path (native-forwarding+seed is dead; CMDT rate == PBE ratio == the factor that
generated the PBEs, so the value factor is decided, not a Finance blocker). The **first** design (naive
value-identity MVP) was **broken by the adversarial pass** with three live-record defects; the shipped
design fixes all three:

| Adversarial defect (live records) | Severity | Fix in the delivered design |
|---|---|---|
| Order-path double-scale on the **collision cohort** (VLM CAD `360×1.3889≈500`, and `500` is itself a raw override) → 38.9% overcharge frozen | 🔴 Fatal | **Provenance, not value-identity.** Procedure snapshots the raw per-unit net into `ABA_Raw_Net__c`; the posthook reads that, so a localized value coinciding with a USD override is never re-scaled. Snapshot carries Quote→Order on convert → order path stays idempotent. |
| `UnitPrice` / `Source_List_Price__c` still show raw USD (the ticket's named field) | 🟠 Major | Posthook localizes `UnitPrice`; SC-3544 `resolveSalesPrice`/Source_List_Price stamp currency-gated so raw-USD `Base_Price__c` is never stamped onto a non-USD line. |
| Per-unit vs total confusion missed 42% of blast radius at qty>1 (or 2× overcharge) | 🟠 Major | Scales the **per-unit** snapshot; totals = unit × qty. Never reads `Subtotal`. Regression test on single-override product `01tWC00000DD1YwYAL`. |

**Components (all built this session):**
- `AbaCurrencyCorrectionService.cls` (+Test) — pure per-unit CMDT scaling + idempotency (`raw × rate`, epsilon 0.005).
- `PartnerNetPricePosthook.cls` — new first pass `applyCurrencyCorrection` (mutates tags before the partner "lower-of"), `mergeCurrencyCorrectionIntoUpdate` (add-if-absent so partner net is never clobbered), SC-3544 currency gate. `PartnerNetPriceCurrencyCorrectionTest.cls`.
- `ABA_Raw_Net__c` (Number 18,2) on QuoteLineItem + OrderItem.
- `QuoteToOrderFieldMapper.cls` + `MaintenanceOrderDecompositionService.cls` — carry `ABA_Raw_Net__c` on convert.
- **Gated org-only** (staged, not applied): context-def `SalesTransactionContextExt_v2` (3 blocks) + procedure provenance stamp — see `Data/sc3384/GATED_ORG_STEPS_currency_correction.md`. Deploy manifest: `Data/sc3384/deploy/package.xml`.

**Safety:** until the procedure stamps `ABA_Raw_Net__c`, the posthook is a strict no-op — the Apex/field
half deploys non-breaking on its own; the correction only activates once the gated context-def + proc
stamp land. USD lines 0-delta by construction.

**Not yet done:** org validation (compile + tests) and deploy are **gated pending explicit authorization**;
real-record reprice validation (AAMP EUR → 1471.995, USD 0-delta, re-reprice/convert idempotency).
