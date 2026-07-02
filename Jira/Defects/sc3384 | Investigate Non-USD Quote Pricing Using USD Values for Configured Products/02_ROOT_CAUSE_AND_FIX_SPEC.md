<!-- Focused per-defect RCA + fix spec (workflow ww5pz6xfz: 13 agents, 5 defects, adversarially verified). Companion to 10_ORG_WIDE_REACH_IMPACT_ASSESSMENT.md. -->

# SC-3384 — Root-Cause Analysis & Fix Specification
## "Non-USD Quote Pricing Using USD Values for Configured Products"

**Status:** Read-only RCA complete. No DML/deploy performed.
**Target org:** FortraUAT
**Repro quote:** `0Q0WC0000036xy90AA` — "Q-Wren - Test Currencies-2026-06-09", `CurrencyIsoCode=EUR`, Pricebook `01sWC0000022GHFYA2`
**Audience:** Liam, Nir, Marc (engineering) + leadership summary below
**Authors' confidence:** 4 of 5 defects **confirmed** end-to-end against live data + live code; 1 family (auto-add maintenance) **partial** — the causal element is re-attributed below.

---

## 1. TL;DR

On a non-USD quote, base **list** prices are correct (the PricebookEntry read filters by currency), but **every configured/derived price** (attribute, tier, server-type discount, attribute-tier) is pulled from a **USD** supporting record and written verbatim onto the EUR line. The unifying root cause is **two reinforcing failures**: (1) **DATA** — the entire configured-pricing supporting dataset exists *only* in USD: `AttributeBasedAdjustment` = **13,072 rows, 100% USD** (reconfirmed live), `Attribute_Tier_Pricing_Storage__c` = **1,115 rows, 100% USD**, and there is exactly **one** `PriceAdjustmentSchedule`, USD-pinned; and (2) **CONFIG/CODE** — the lookups that consume that data are **currency-blind** (the `AttributeBasedAdjustment` decision table has no `CurrencyIsoCode` input column; the `AttributeVolumePricingPrehook` SOQL omits `CurrencyIsoCode`). With only USD rows present and no currency in the match key, an EUR line deterministically grabs the USD value.

**Verdict on Wren's hope that this is "only a data issue": No — it is BOTH, and the two must ship together.** Seeding EUR rows without adding currency to the lookups is *unsafe* (the currency-blind key would then match USD *and* EUR rows non-deterministically); adding currency to the lookups without seeding EUR rows would flip lines from "wrong USD number" to "reset to list / 0." DATA is the dominant volume of work, but CONFIG is a hard prerequisite for correctness.

The 5th defect (auto-add maintenance `PIAMBK` fails with *"price book entry currency code is different than the one assigned to the Quote"*) is a **different** problem: the EUR PBE **already exists**, so it is **wrong-PBE-selection**, not missing data — and the originally-cited flow element is **not** the throw point (re-attributed in §2.5).

---

## 2. Per-Defect RCA

### 2.1 BESEPB — TIER / Override (`VM-BSL-RSL-BESEPB`) — **CONFIRMED**

| | |
|---|---|
| **Line** | QLI `0QLWC000003cAr34AE`, Product2 `01tWC00000DD15FYAT`, PSM `0jPWC000000060b2AA` |
| **Observed** | List **758.08** (EUR PBE, correct) → Net = Total = Unit = **824** = the **USD PBE** value |
| **Mechanism** | Despite the "TIER" label, BESEPB has **0 rows** in `Attribute_Tier_Pricing_Storage__c`, so the Apex tier prehook early-returns. The 824 comes from an **`AttributeBasedAdjustment` Override row** matched via the **`Attribute_Based_Adjustment_Decision_Table`** (`0lDa50000007BEuEAM`, SourceObject=`AttributeBasedAdjustment`). Base list (758.08) is produced separately by `Price_Book_Entry_Decision_Table_v2`, which *is* currency-correct — so list and net diverge. |
| **Root cause** | **BOTH.** The decision table's input keys = `PriceAdjustmentScheduleId, ProductId, ProductSellingModelId, EffectiveFrom(≥), EffectiveTo(<), AttributeAdjConditionsHash` — **no `CurrencyIsoCode`**. The single matching ABA row for BESEPB is `AdjustmentType=Override, AdjustmentValue=824, CurrencyIsoCode=USD` (Id `12DWC00000Jupkg2AB`). The EUR line matches the USD row and is overridden to 824. By contrast `Price_Book_Entry_Decision_Table_v2` has `CurrencyIsoCode` as a **Required Equals** input (seq 4) — which is exactly why list stays EUR-correct. |
| **Data/Config** | **both** |
| **Evidence** | BESEPB: 11 ABA rows, **all USD**, all Override, each with a distinct `AttributeAdjConditionsHash` (824-row hash `3484bd85…`), so the hash-Equals key deterministically picks the single 824 row; 0 EUR ABA rows. DecisionTableParameter (Tooling API) confirms `0lDa50000007BEuEAM` has no `CurrencyIsoCode` input while `0lDa50000007BErEAM` does. |
| **Fix** | **Both axes.** (a) Add a `CurrencyIsoCode` input column to `Attribute_Based_Adjustment_Decision_Table`; (b) seed EUR ABA rows for BESEPB. *See unified fix spec §5.* |

> **Note (from verify):** the previously cited "all 21 `CalculationMatrix` records are USD" is the matrix *metadata-record* currency (org default), **not** a per-row filter — do **not** cite it as a cause. What gates currency-correctness is purely the presence/absence of a `CurrencyIsoCode` **input key column**, proven by `Price_Book_Entry_Decision_Table_v2` resolving EUR correctly despite its own matrix record being USD.

---

### 2.2 AAMP — SERVER-TYPE DISCOUNT (`GS-GSE-NRPS-AAMP`) — **CONFIRMED**

| | |
|---|---|
| **Line** | QLI `0QLWC000003cBGr4AM`, Product2 `01tWC00000DD11YYAT` (Perpetual / One-Time). Same SKU as SC-3360. |
| **Observed** | List **2898** (EUR, correct) → Unit = Subtotal = **3150** (USD Override), Net = TotalPrice = **1575** (USD Override) |
| **Mechanism** | Native **AttributeDiscount BKM step** `AttributeDiscountEntries` in active V9 of `Rev_Mgmt_Default_Pricing_Procedure` resolves ABA rows via decision table `0lDa50000007BEuEAM` and writes **both** `NetUnitPrice` and `Subtotal`. **No SOQL** — pure native matrix lookup. (Inverse of SC-3360: there the Override *didn't* fire on a USD quote due to a missing `{SFTP,OnPrem,Non-Production}` row; here on EUR it *does* fire and returns USD-denominated flats.) |
| **Root cause** | **BOTH.** (Data) the 3 AAMP ABA rows are all USD: `00000219`=3150 (Override, expired 2026-06-01), `00022777`=3150 (Override, **active**, same hash `adf67826…`), `00000220`=1575 (Override, active, hash `9da979e8…`). (Config) the step passes inputs `PriceAdjustmentScheduleId(=AttributePASIdConstant), ProductId, ProductSellingModelId, EffectiveFrom/To, AttributeName, AttributeValue, Quantity, IsPriceImpacting, InputUnitPrice` and `LookUpId=0lDa50000007BEuEAM` — **no `CurrencyIsoCode`**; `AttributePASIdConstant` is hardcoded to the USD schedule `84Xa50000010nWQEAY`. |
| **Data/Config** | **both** — and **non-determinism proven**: the two 3150 rows share the same hash and are disambiguated *only* by date window, not currency. Seeding an EUR row with the same hash + overlapping dates would match alongside the USD row → **seeding without a currency key is unsafe.** |
| **Evidence** | Live line + ABA rows as above. Tooling-API DecisionTable metadata: `conditionCriteria='1 AND 2 AND 3 AND 4 AND 5 AND 6'`, no `CurrencyIsoCode` parameter. The ListPrice step (`PartnerDiscount13`) *does* pass `CurrencyIsoCode`, isolating the defect to the Override layer. |
| **Fix** | **CONFIG-durable; data alone insufficient.** *Option A (preferred):* model the server-type discount as a **percentage** adjustment off the already-correct EUR list (2898) → currency-neutral, no per-currency rows. *Option B:* keep flat Overrides but add `CurrencyIsoCode` to the decision-table key + the step inputs **and** seed per-currency ABA rows. *See §5 + open question on which is intended.* |

> **Caveat:** the AttributeDiscount step was verified from the **local force-app copy** (line numbers ~off by 2 vs the README; `AttributeDiscountEntries` at lines 797–957) — the **live** ExpressionSetVersion could not be retrieved metadata-only this session. The **DecisionTable key** *was* verified directly against the live org (Tooling API) and is authoritative.

---

### 2.3 VMA — ATTRIBUTE Override (`VM-VLM-NRSU-VMA`) — **CONFIRMED (DATA)**

| | |
|---|---|
| **Line** | QLI `0QLWC000003cAEM4A2`, Product2 `01tWC00000DD1qnYAD` |
| **Observed** | List = Unit = **460** (EUR, correct) → Net = NetTotal = Subtotal = TotalPrice = **500** (USD value) |
| **Mechanism** | Native `AttributeBasedAdjustment` engine. The line's 3 price-impacting attributes (`PS Service Type=Senior`, `Unit Type=Hours`, `Number of Units=1-8`) match rule **`ABARule_13348`** (`12HWC000001QV8O2AW`) → ABA `12DWC00000JwPOv2AN` (`00016416`): `Override, AdjustmentValue=500, USD`. Override forces net to the flat 500, overriding EUR list 460. |
| **Root cause** | **DATA.** The matching ABA Override row exists **only in USD**; no EUR equivalent. All 12 VMA rows are USD; the whole 13,072-row object is USD; the lone schedule is USD. The native engine **can** filter by currency (ABA + PriceAdjustmentSchedule both carry `CurrencyIsoCode`) — so this is *moot* until EUR rows exist. **This is the one purely-DATA defect.** |
| **Data/Config** | **data** |
| **Evidence** | The 12 rules form a complete value-differentiated matrix (Senior 1-8=500 / 9-24=450 / 25-80=375 / >80=300; Analyst 400/360/300/240; Junior 250/225/188/150), so the engine selected the Senior/1-8 row **by attribute condition** — proving 500 is a *matched Override*, not a list fallback (which would be value-invariant). The prehook is ruled out: VMA has 0 `Attribute_Tier_Pricing_Storage__c` rows. |
| **Fix** | **DATA only.** Seed EUR ABA Override rows for VMA (and the full attribute matrix) under a EUR-appropriate `PriceAdjustmentSchedule`, with EUR-correct values. No Apex change for VMA. |

> **Nuance (adversarial test, from verify):** EUR rate is 0.92 and 500×0.92 = 460.0 exactly, so EUR list 460 is the precise conversion of USD 500 — a coincidence. The attribute-matrix evidence decisively refutes a "conversion/list-fallback" alternative (GBP/CAD/AUD prices are *not* simple conversions → per-currency catalog maintenance). The correct EUR Override must encode the *intended* EUR amount, not merely mirror list (the USD row overrides 460→500, a ~+8.7% uplift). **Open question:** is the intended EUR override 460 (no uplift) or a EUR-specific catalog figure?

---

### 2.4 CLSAAS — ATTRIBUTE-TIER via Apex prehook (`HRM-HRM-RSL-CLSAAS`) — **CONFIRMED (BOTH)**

| | |
|---|---|
| **Line** | QLI `0QLWC000003cE8H4AU`, Product2 `01tWC00000DD17PYAT` |
| **Observed** | List **2005.6** (EUR, correct) → `Base_Price__c` = Subtotal = Unit = **1357.2** (USD tier value); **Net = NetTotal = TotalPrice = 0** |
| **Mechanism** | This is the **only** line driven by Apex prehook **`AttributeVolumePricingPrehook`** (live class `01pWC000001wAzJYAU`, body byte-equivalent to the local mirror). It bulk-reads `Attribute_Tier_Pricing_Storage__c`, builds a composite key, range-matches on volume, and writes `Base_Price__c` + `Attribute_Price_Mode__c='Total Price'`. |
| **Root cause** | **BOTH.** (Code) the SOQL `Org Data/_src/classes/AttributeVolumePricingPrehook.cls:212-219` filters `WHERE Product__c IN :productIds AND Product_Selling_Model__c IN :psmIds` — **no `CurrencyIsoCode`**; the composite key `buildCompositeKey()` (cls **358-363**) = `productId\|psmId\|normalizedName\|attrValue` — **no currency**. (Data) the table is 100% USD; CLSAAS has 37 USD rows incl. `Feature Options\|Managed Service\|50-99` `Tier_Value__c=1357.2 Price_Mode__c='Total Price'` = the observed value. |
| **Data/Config** | **both** |
| **Smoking gun** | The EUR PBE (`01uWC000005wyVjYAI`, 2005.6) and all 37 USD tier rows use the **same** PSM `0jPWC000000060b2AA` (PSM is currency-agnostic), so the no-currency composite key **provably** retrieves the USD row for the EUR line. End-to-end mechanism closed. |
| **Fix** | **Both:** (Code) add `AND CurrencyIsoCode IN :currencyIsoCodes` to the SOQL + `SELECT CurrencyIsoCode` + thread line currency into the composite key (`buildCompositeKey`, `buildTierLookupMap`, `lookupTierFromMap`); (Data) seed EUR `Attribute_Tier_Pricing_Storage__c` rows for CLSAAS (and peers). |

> **Two corrections to carry into the fix doc:**
> 1. The task header's gloss *"EUR attr-tier lookup MISSES entirely"* is **backwards** — the lookup **HITS** a USD row and **writes** `Base_Price__c=1357.2`. The `Net/Total=0` is a **downstream** consequence of how the procedure consumes `'Total Price'` mode, **not** a second currency-miss.
> 2. The **`Net=0`** is **currency-independent** and was **not** traced to the exact procedure element (the `rca_*.json` inventory stubs are near-empty 2–814 bytes; the step mapping rests on the prehook header contract + live QLI behavior). Treat the Total-Price net-channel gap as a **separate sub-fix** and verify it persists/resolves after EUR data lands. Live QLI `Price_Mode__c` reads **None/null** at line level — the `'Total Price'` mode lives on the storage row / `Attribute_Price_Mode__c`, not the QLI field.

---

### 2.5 PIAMBK — AUTO-ADD MAINTENANCE FAILURE — **PARTIAL (re-attributed)**

| | |
|---|---|
| **Symptom** | Auto-add of maintenance line `PIA-PIA-RNM-PIAMBK` (`01tWC00000DD1bsYAD`) fails: *"The price book entry currency code is different than the one assigned to the Quote.: Price Book Entry ID"* |
| **Root cause** | **CONFIG — wrong-PBE-selection, NOT missing data.** `PIAMBK` has **two** active PBEs in the quote's Fortra book `01sWC0000022GHFYA2`: USD `01uWC000005wsbUYAQ` and **EUR `01uWC000005wzX8YAI`** (both price 0). The EUR PBE **exists** → not a data gap. The auto-add automation resolves the maintenance `PricebookEntryId` **without a currency filter** against duplicate same-book EUR/USD PBEs and picks the USD one, tripping the platform validation at insert time. |
| **Re-attribution (the substantive correction)** | The originally-cited `Get_Maint_PBE` lookup in **`Stamp_Maintenance_Pricing_Inputs`** is currency-blind (`Product2Id + Pricebook2Id` only, `getFirstRecordOnly=true`, no `CurrencyIsoCode`, lines ~339-365) — **but that flow is a `RecordBeforeSave` AutoLaunched flow with ZERO DML** that runs *after* the line exists. It **cannot** throw an insert-time error. The throw point is the **separate auto-add automation that INSERTS the maintenance QLI**. It is **not** a `ProductRelatedComponent` (0 rows for `PIAP→PIAMBK`) and is not in the `_src` flow mirror → **likely a managed RLM `ProductConfigurationRule` add action** (302 PCRs exist). |
| **Data/Config** | **config** |
| **Fix** | Add a `CurrencyIsoCode = $Record.CurrencyIsoCode` filter to the **auto-add resolver** (once identified). Also add the same filter to `Get_Maint_PBE` defensively (it would otherwise corrupt derived inputs), **but that alone will not fix the add failure.** |

> **Staleness caveat:** the live `Stamp_Maintenance_Pricing_Inputs` was **re-versioned today 2026-06-11T14:08:16Z** (newer than the analysis source). Re-retrieve the active version before any Family-B work.

---

## 3. Unifying Root Cause — currency-blind lookups over USD-only data

The base list-price read filters by currency; **every other pricing surface does not.** Audit table:

| Prehook / Step | Lookup target | Currency in the match key? | Supporting data | Defect explained |
|---|---|---|---|---|
| **PricebookEntry read** (`Price_Book_Entry_Decision_Table_v2` `0lDa50000007BErEAM`) | `PricebookEntry` | **YES** — `CurrencyIsoCode` Equals/Required (seq 4) | Per-currency PBEs exist | *(correct — list prices are right)* |
| **AttributeDiscount BKM** (`AttributeDiscountEntries`, V9) → `Attribute_Based_Adjustment_Decision_Table` `0lDa50000007BEuEAM` | `AttributeBasedAdjustment` | **NO** — key is Schedule/Product/PSM/Eff dates/AttrHash; schedule hardcoded USD `84Xa50000010nWQEAY` | 13,072 rows **100% USD** | **BESEPB** (824), **AAMP** (3150/1575), **VMA** (500) |
| **Apex `AttributeVolumePricingPrehook`** SOQL (cls:212-219) + composite key (cls:358-363) | `Attribute_Tier_Pricing_Storage__c` | **NO** — `Product__c + Product_Selling_Model__c` only; key `product\|psm\|attr\|value` | 1,115 rows **100% USD** | **CLSAAS** (1357.2; Net=0 downstream) |
| Auto-add maintenance resolver (managed; *to be identified*) | `PricebookEntry` | **NO** — `Product2Id + Pricebook2Id`, first-record | EUR PBE **exists** | **PIAMBK** add failure (wrong PBE) |
| `HardwareAttributePricingPrehook` | `Hardware__c` (multipliers) | n/a — multiplies the already-EUR context price | currency-agnostic | *(not implicated)* |
| `RegionalServicesPricingPrehook` | `Services_Regional_Pricing__mdt` (multiplier) | n/a | currency-agnostic | *(not implicated)* |
| `PartnerPricingPrehook` / `V2` | `Partner_Pricing_Model__c` (%) | n/a | currency-agnostic | *(not implicated)* |
| `COLAUpliftPrehook` | CMDT % + Asset | n/a | currency-agnostic | *(not implicated)* |
| `SourceListPricePrehook` | — | n/a (disabled / no-op) | — | *(not implicated)* |

**Pattern:** wherever pricing depends on an **absolute amount stored per currency** (ABA Override values, tier `Tier_Value__c`, a specific PBE Id), the lookup is currency-blind AND the data is USD-only → the EUR line consumes USD. Wherever pricing is a **multiplier/percentage** off the already-correct context price, there is no defect.

---

## 4. Is it "only a data issue"? — explicit verdict

**No. It is BOTH, and they are interdependent.** Quantified by defect:

| Defect | DATA fix needed? | CONFIG/CODE fix needed? | If you do DATA only | If you do CONFIG only |
|---|---|---|---|---|
| BESEPB (TIER/Override) | Yes (EUR ABA rows) | Yes (currency key on `0lDa50000007BEuEAM`) | **Unsafe** — currency-blind hash matches USD+EUR non-deterministically | Misses → resets to list |
| AAMP (server-type) | Yes *(Option B)* / No *(Option A %)* | **Yes (durable fix)** | **Unsafe** (same-hash multi-currency match) | (Option A) sufficient & currency-neutral |
| VMA (attribute) | **Yes — DATA only** | No (native engine already carries `CurrencyIsoCode`) | **Sufficient** | n/a |
| CLSAAS (attr-tier) | Yes (EUR tier rows) | Yes (Apex SOQL + key) | No-op (no-currency query still grabs USD) | Resets to list / stays 0 |
| PIAMBK (auto-add) | **No** (EUR PBE exists) | **Yes — CONFIG only** (currency filter on auto-add resolver) | n/a | **Sufficient** |

- **DATA is the dominant *volume* of work** (seeding EUR — and any other transacting currency — across ABA 13,072 + ATPS 1,115 rows, scoped to the affected products at minimum).
- **CONFIG/CODE is a hard correctness prerequisite** for BESEPB, AAMP, CLSAAS: without it, seeding EUR data is either *unsafe* (non-deterministic multi-currency hash matches) or a *no-op*.
- **Only VMA is purely DATA. Only PIAMBK is purely CONFIG.** So Wren's "data-only" hope holds for exactly **1 of 5** defects.

---

## 5. Fix Spec (ordered, with validation)

**Sequencing rule (non-negotiable):** for any line where we add a currency filter, **EUR data must land first or concurrently** — otherwise EUR lines flip from "wrong USD number" to "reset to list / 0" (a visible regression).

### Workstream A — DATA seed (EUR + all transacting currencies)
1. **`AttributeBasedAdjustment` EUR rows** for the affected products (min: BESEPB 824-equiv, AAMP 3150/1575-equiv, VMA full 12-rule matrix), with **EUR-correct** `AdjustmentValue` (catalog-defined, *not* mechanical USD×0.92), plus matching `AttributeBasedAdjRule` + `AttributeAdjustmentCondition` rows. Decide schedule strategy: reuse the single schedule `84Xa50000010nWQEAY` (relying on the new currency input column to disambiguate) **or** create parallel per-currency schedules — **confirm against native matcher behavior before building** (open question).
2. **`Attribute_Tier_Pricing_Storage__c` EUR rows** mirroring the 37 USD CLSAAS rows (and other affected products) with EUR `Tier_Value__c`/`Multiplier__c`, reusing the **same currency-agnostic PSM** `0jPWC000000060b2AA`.
- *Load mechanism:* ABA is platform-managed — no Apex DML path; use REST/composite-key load per the SC-3137 playbook.
- *Validation:* on the EUR repro quote, BESEPB net=824→EUR-correct; VMA net=500→EUR-correct; CLSAAS Subtotal pulls the EUR tier.

### Workstream B — CONFIG: decision-table currency key
3. Add `CurrencyIsoCode` as an **input key column** (Equals, Required) to **`Attribute_Based_Adjustment_Decision_Table` `0lDa50000007BEuEAM`** and **`Attribute_Tier_Pricing_Matrix` `0lDWC0000000Gft2AE`**; add a matching `CurrencyIsoCode` input parameter to the **AttributeDiscount step** (`AttributeDiscountEntries`). Re-sync/refresh the decision table after the change.
- **AAMP Option A (recommended):** instead of/in addition to the currency key, redefine the server-type adjustment as a **percentage** so it applies to the correct EUR list — currency-neutral, removes per-currency rows, and also addresses the SC-3360 sparse-matrix bug. Requires business sign-off (open question).
- *Validation:* USD lines byte-identical (3150/1575/824/500); EUR lines derive from EUR list.

### Workstream C — CODE: Apex prehook currency-awareness
4. **`AttributeVolumePricingPrehook.cls`**: (a) capture line currency from the context tag in Pass-1 (~cls:187-188) into a `Set<String>`; (b) add `AND CurrencyIsoCode IN :currencyIsoCodes` + `SELECT CurrencyIsoCode` to the SOQL (cls:212-219); (c) extend the composite key to `product\|psm\|currency\|attr\|value` in `buildCompositeKey` (358-363), `buildTierLookupMap` (336-338), `lookupTierFromMap` (409). With currency in the key + no EUR data, it cleanly resets to EUR list (correct interim).
- *Prereq:* confirm `CurrencyIsoCode` is a mapped `SalesTransactionItem` context tag before coding the capture (open question).
- *Validation:* USD CLSAAS lines unchanged; EUR CLSAAS pulls EUR tier; full USD regression.

### Workstream D — CLSAAS Net=0 (Total-Price net-channel)
5. Trace and fix the downstream `Rev_Mgmt_Default_Pricing_Procedure` `'Total Price'`-mode step so `NetUnitPrice/NetTotalPrice/TotalPrice` are seeded (currently 0). **Currency-independent** — do not conflate with the currency fix; verify it persists after EUR data lands.

### Workstream E — PIAMBK auto-add (Family B)
6. Identify the auto-add automation that inserts the maintenance QLI and resolves its `PricebookEntryId` (likely a managed RLM `ProductConfigurationRule` add action). Add a `CurrencyIsoCode = Quote.CurrencyIsoCode` filter so it selects EUR PBE `01uWC000005wzX8YAI`. Defensively add the same filter to `Get_Maint_PBE` in the (re-retrieved, today-re-versioned) `Stamp_Maintenance_Pricing_Inputs`.
- *Validation:* the 5th maintenance line auto-adds successfully on the EUR quote.

**Platform constraints to respect (from memory):** `Rev_Mgmt_Default_Pricing_Procedure` version hard-delete is blocked — any change is a **new ExpressionSet version + republish + decision-table re-sync**; the two `PricingActionParameters` bindings (Quote/Order context wiring) **must not** be removed; in-place V9 edits without context re-sync have historically caused `contextDefinitionName` and Order-creation gacks — **re-sync `SalesTransactionContextExt_v2` after any matrix-key change.** This is the **same matrix SC-3360 depends on** — coordinate to avoid double-changing it.

---

## 6. Effort & Load-Share

| Workstream | Change type | T-shirt / days | Suggested owner |
|---|---|---|---|
| **A — EUR data seed** (ABA + ATPS, multi-currency) | Data (REST/composite-key load + generation job) | **L — 4-6 d** (bulk of the work; scope = how many products beyond the 4 SKUs need currencies) | **Marc** (data lead; owns the live pricing data + knows the catalog) |
| **B — Decision-table currency key + AAMP %-vs-flat** | Config (ExpressionSet new version + DecisionTable + re-sync) | **M — 3-5 d** | **Nir** (pricing-procedure/RCA owner; coordinates with SC-3360) |
| **C — `AttributeVolumePricingPrehook` currency** | Apex + test | **M — 3-5 d** | **Liam** (owns the prehook; SC-3349/3350 context) |
| **D — CLSAAS Net=0** | Procedure step trace + fix | **S — 1 d** (after waterfall trace) | **Nir** (procedure) |
| **E — PIAMBK auto-add** | Config (identify + filter auto-add resolver) | **S — 1-2 d** (gated on identifying the resolver) | **Liam** (investigation) → **Marc/Nir** if managed RLM |
| Regression: multi-currency reprice (USD must be byte-identical; check GBP/CAD/AUD/JPY/ILS) | QA | **S — 1-2 d** across all | shared |

**Total:** ~**M-L, ~2 weeks** with the three streams parallelized. **Shared-load split (per Jomil):** Marc=DATA, Nir=CONFIG/procedure, Liam=Apex+investigation, regression shared. A/B sign-off (percentage vs per-currency flat) and the EUR-value source (catalog vs FX) are business decisions that gate Workstreams A & B.

---

## 7. Open Questions / Not-Verified / Risks

**Open questions (need answers before building):**
- **Is the AAMP server-type discount intended as a uniform percentage or genuinely per-currency flat amounts?** Decides Option A (clean, currency-neutral) vs Option B (currency-keyed matrix + per-currency data).
- **Does the native AttributeDiscount BKM even support a `CurrencyIsoCode` input dimension,** or is the supported currency-aware pattern to store Override as a percentage / use per-currency schedules? Needs SF Revenue Cloud confirmation.
- **Are EUR configured-pricing values catalog-defined or FX-derived?** (USD list 2005.6 = EUR list 2005.6 for CLSAAS, and GBP/CAD/AUD PBEs are *not* simple conversions → catalog-maintained.) Determines who supplies the load file and the VMA "460 vs 500" target.
- **Which automation creates the PIAMBK auto-add QLI** and resolves its `PricebookEntryId`? Not a `ProductRelatedComponent`; likely a managed RLM `ProductConfigurationRule`. Must be identified to fix Family B.
- **Is `CurrencyIsoCode` available as a `SalesTransactionItem` context tag** for the prehook to read? Confirm in the Context Definition before coding Workstream C.
- **Scope of the data seed:** how many products beyond the 4 SKUs need EUR (and other-currency) ABA/ATPS rows? (ABA = 13,072 USD rows across many products.)

**Not independently verified (residual uncertainty):**
- The **live ExpressionSetVersion** of `Rev_Mgmt_Default_Pricing_Procedure` was **not** retrievable metadata-only this session; the AttributeDiscount step rests on the **sc3374 V9 retrieve + local force-app copy** (line numbers ~off by 2). The **DecisionTable key was verified live** (authoritative). Confirm the retrieve equals current live V9 before any change.
- The **CLSAAS Net=0 downstream step** was not pinned to an exact ExpressionSet element (inventory stubs near-empty); mechanism direction is right, exact element is not. Needs a debug-log/waterfall trace.
- The **native ABA matcher's** internal currency behavior cannot be directly inspected by reading config — immaterial given zero EUR rows exist, but relevant once data lands.
- The **PIAMBK throw point** (native RLM add vs other) needs a debug-log reprice trace to pin exactly.
- `Stamp_Maintenance_Pricing_Inputs` was **re-versioned today (2026-06-11T14:08:16Z)** — re-retrieve before Family-B work.

**Regression risks:**
- **Currency filter without EUR data = silent regression** (lines reset to list / 0, losing intended discounts) — enforce the data-first sequencing rule.
- **Seeding EUR data without a currency key = unsafe** (currency-blind hash matches USD+EUR non-deterministically; proven by AAMP's same-hash rows).
- **Option A (percentage Override) changes net for ALL currencies incl. USD** — must verify USD lines still price to 3150/1575/824/500.
- **Editing active V9 ExpressionSet / decision-table key** risks reprice regressions and `contextDefinitionName`/Order-creation gacks (memory) — new version + republish + **context re-sync** mandatory; version hard-delete is blocked; do not remove `PricingActionParameters` bindings.
- **Composite-key shape change in `AttributeVolumePricingPrehook`** affects *every* attr-tier product — full USD regression required (USD behavior byte-identical); class is v64, confirm the test class adds currency-branch assertions (currently 0).
- **Other currencies beyond EUR:** the org has active **AUD, CAD, GBP, JPY, ILS** rates — every one is affected identically. Scope the data seed and regression to **all** transacting currencies, not just EUR.
- **SC-3360 coupling:** the AAMP fix touches the same ABA matrix SC-3360 depends on — coordinate to avoid double-changing it.
