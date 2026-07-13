# SC-3384 Workstream B+A Build Scope (ABA multi-currency) — 2026-07-09

Scoping workflow (3 understand agents -> plan -> adversarial verify). The verify pass found 2 SHOWSTOPPERS — read §ADVERSARIAL first.

---

## BUILD PLAN

## Workstream B+A Build Scope (SC-3384 ABA multi-currency)

### 1. Root mechanism + why B+A are one fix

**CONFIRMED root cause.** All three ticket symptoms (L1 tier, L2 server-type discount, L3 attribute-based) resolve through ONE native, auto-generated `DecisionTable` — `Attribute_Based_Adjustment_Decision_Table` (Id `0lDa50000007BEuEAM`, source object `AttributeBasedAdjustment`). That table has 6 inputs and **no `CurrencyIsoCode` column**, and its backing data is **13,073/13,073 rows `CurrencyIsoCode='USD'`** with **`AdjustmentType='Override'` on 100% of rows** — i.e. every row is an *absolute stored USD price*, not a currency-invariant percentage. A EUR/GBP/AUD/CAD line therefore matches a USD Override row and stamps the raw USD dollar figure onto the localized line: LIST localizes correctly (per-currency PBE exists) but configured Net/Subtotal/Total carry the raw USD number under a foreign symbol (~+7% EUR overcharge), or Net=0 where the USD PBE base is $0 (the Workstream D cohort). Blast radius: **71,502 non-USD QLIs on 603 products** (EUR 35,641 / GBP 26,098 / AUD 7,843 / CAD 1,920).

**Why B and A are inseparable (CONFIRMED constraint from smoke).** B adds the currency key to the lookup; A supplies the per-currency rows that key must match. Ship **B without A** → non-USD lines find no matching row and regress to list/$0 (the key has no fallback). Ship **A without B** → the extra currency rows are invisible to a currency-blind match and USD-vs-EUR rows collide non-deterministically. The concrete coupling point: the ABA DecisionTable is `executionType=HBASE` with `isIncrementalSyncEnabled=false`, so **A's rows must be loaded before the post-B table refresh/re-index** or the new column indexes empty.

---

### 2. Workstream B — currency-aware ABA lookup

Template throughout: `Price_Book_Entry_Decision_Table_v2` (Id `0lDa50000007BErEAM`), which is currency-aware by carrying `CurrencyIsoCode` as INPUT seq 4, `operator=Equals`, `isRequired=true`, `conditionCriteria = 1 AND 2 AND 3 AND 4`. Its calling `ListPrice` BKM threads line currency with a `<parameters>` block whose `value=CurrencyIsoCode` is a **context-field reference** from `SalesTransactionContextExt_v2` — so **no new `<variables>` declaration is needed**.

**Edit 1 — ABA DecisionTable (add 7th input column).**
- File to deploy from: `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/dt_retrieve/decisionTables/Attribute_Based_Adjustment_Decision_Table.decisionTable-meta.xml`. Also commit a source-controlled copy under a new `force-app/main/default/decisionTables/` folder (the table is not currently in the repo).
- Change `<conditionCriteria>1 AND 2 AND 3 AND 4 AND 5 AND 6</conditionCriteria>` → `…AND 6 AND 7`.
- Add one `<decisionTableParameters>` block mirroring PBE exactly:
```xml
<decisionTableParameters>
    <dataType>String</dataType>
    <fieldName>CurrencyIsoCode</fieldName>
    <fieldPath>CurrencyIsoCode</fieldPath>
    <isGroupByField>false</isGroupByField>
    <isRequired>true</isRequired>
    <operator>Equals</operator>
    <sequence>7</sequence>
    <usage>INPUT</usage>
</decisionTableParameters>
```

**Edit 2 — Pricing procedure (thread line currency into BOTH ABA steps).**
- Live Active version is **v23** (CONFIRMED — repo is STALE at v22/shows v20 active). Start from the fresh retrieve: `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/proc_live/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`. ExpressionSetDefinition MDAPI carries all 23 versions inline.
- Two native `AttributeDiscount` BKM steps invoke the ABA table and **neither passes any currency param today**:
  - `AttributeBasedPrice` (`IsContractEnabled=true`) — ABA id at live line 125549, name at 125618.
  - `AttributeDiscountEntries` (`IsContractEnabled=false`) — ABA id at live line 125726, name at 125788.
- Add the PBE-template `<parameters>` block (`name=CurrencyIsoCode`, `value=CurrencyIsoCode`, `input=true`, `type=Parameter`) into the `<customElement>` of **both** steps, after `ProductSellingModelId` (named-param match is order-independent).
- Per repo memory: edit on the **Pricing Procedure CANVAS**, not raw MDAPI.

**Deploy dance.**
- DecisionTable: `sf project deploy`, api 67. Then **re-sync/refresh the table in Setup** (HBASE, incremental sync off → full rebuild) so it re-indexes ABA including the new column. **A's rows must be loaded before this refresh** — the ship-together coupling.
- ExpressionSetDefinition: api 67 + `--metadata-dir`; **deactivate → deploy → reactivate**; edit CANVAS; retrieve live v23 first.

**⚠️ Single most important thing to prove before wiring A (gating unknown, ASSUMPTION until tested).** The native `AttributeDiscount` element is a black box. `ListPrice` is *proven* to forward `CurrencyIsoCode`; `AttributeDiscount` is a **different** native element and its DT was auto-generated *without* a currency column — attribute-based pricing may not natively forward currency in this release. **Validate in a sandbox that `name=CurrencyIsoCode` actually participates in the ABA match** (a EUR line matches only a EUR ABA row). If it does not forward, Edit 2 is inert; fallback is to replace the native `AttributeDiscount` steps with a generic decision-table-lookup element, or move to the Apex path (Workstream C pattern).

**Scope check for A (CONFIRMED sibling gap).** `Price_Adjustment_Tier_Decision_Table` (Id `0lDa50000007BEsEAM`, source `PriceAdjustmentTier`) is **also currency-blind** (7 inputs, no CurrencyIsoCode). If any L1 tier symptom resolves through its `TierValue` output rather than ABA, it needs the identical B treatment + a per-currency tier seed. Confirm against the smoke element trace before finalizing A's seed set.

---

### 3. Workstream A — per-currency data seed

**Value-derivation rule (CONFIRMED, uniform — single AdjustmentType).** All 13,073 rows are `Override` (absolute price), so per-currency values MUST be re-derived; a percentage type would be currency-invariant, but none exist. The rule:

> **localized_value = USD_AdjustmentValue × (per-currency_PBE_list ÷ USD_PBE_list)**

This is answer **(b) compute-from-per-currency-PBE**, and it is **numerically identical to FX-multiply** because the per-currency PBEs were themselves built as `USD × Currency_Conversion_Formula__mdt.Conversion_Rate__c`. The static ratio is one factor per currency, identical across all products (CONFIRMED on 1256/1256 priced ABA products): **EUR 0.9346 / GBP 0.7874 / AUD 1.5385 / CAD 1.3889**. These are the design-aligned *static-stored* values.
- **MUST NOT use runtime FX** `CurrencyType.ConversionRate` (EUR 0.92, **GBP 1.0**, AUD 1.52, CAD 1.35) — GBP=1.0 would leave GBP=USD and *reproduce the bug*.
- Preferred generator: per USD Override, emit currency-siblings via `USD_value × (currency_PBE_list / USD_PBE_list)`, rounded to 2 dp — self-corrects if a product ever gets bespoke localization.
- Fallback (identical today): `USD_value × Conversion_Rate__mdt`. Use for the **61 ABA products with a $0 USD PBE** (list-ratio divides by zero; these overlap Workstream D — coordinate so A doesn't seed 0-valued rows off a broken base).

**Seed volumes (CONFIRMED counts).**

*ABA — `AttributeBasedAdjustment`, 13,073 USD rows, 1,661 distinct products (0 non-USD today):*
| Currency | Non-USD lines today | ABA rows to create | Priority |
|---|---|---|---|
| EUR | 35,641 | 13,073 | P1 |
| GBP | 26,098 | 13,073 | P1 |
| AUD | 7,843 | 13,073 | P1 |
| CAD | 1,920 | 13,073 | P1 |
| **P1 subtotal (100% of today's affected lines)** | **71,502** | **52,292** | |
| JPY/CHF/NZD/ILS/ARS (~0 lines each) | | 65,365 | P2 |
| **Full 9-currency** | | **117,657** | |

*ATPS — `Attribute_Tier_Pricing_Storage__c` (Workstream C's table), 1,117 USD rows / 28 products; EUR partially seeded = 37 rows on 1 product:*
| Currency | ATPS rows to create | Priority |
|---|---|---|
| EUR | 1,117 − 37 = **1,080** | P1 |
| GBP/AUD/CAD | 3,351 | P1 |
| **P1 subtotal** | **4,431** | |
| JPY/CHF/NZD/ILS/ARS | 5,585 | P2 |
| **Full 9-currency net-new** | **10,016** | |

Only money fields FX-scale: ABA `AdjustmentValue`; ATPS `Tier_Value__c`. Currency-invariant (copy verbatim): ATPS `Multiplier__c` (percent), `Lower_Bound__c`/`Upper_Bound__c` (volume); both objects' `EffectiveFrom`/`EffectiveTo`, `ScheduleType`, `SellingModelType`, `AdjustmentType`.

**Grand totals:** P1 (4 demand currencies) = **56,723 new rows** (52,292 ABA + 4,431 ATPS). Full 9-currency = **127,673** (117,657 + 10,016).

**Recommendation: seed all 9 active non-USD currencies.** The currency key has NO fallback — the moment a rep quotes JPY/CHF/etc. with no matching row, that line regresses to list/$0. Today those match a wrong USD row; B makes them *worse* unless seeded. P1 is ship-minimum for current demand; P2 is cheap insurance in the same job.

**Generation job + idempotency.** New Stateful Apex batch (mirror `AttributeLoadingBatch` pattern: idempotent skip, `Migration_Run_Log__c`, completion email), composed from two REUSE classes:
- FX engine — `Fortra_CurrencyConversionService.cls` (`convertPrice(usdValue, iso)` = `usdPrice × Conversion_Rate__c`; `convertToAllCurrencies()` returns the map).
- Closest existing FX-multiply seed batch to clone — `Fortra_BulkPriceUpdateBatch.cls` (+ `Fortra_BulkPriceUpdateInvocable.cls`); retarget from `PricebookEntry` to ABA + ATPS.
- **NO existing class writes ABA or ATPS** (grep-confirmed; only test classes touch them). Both objects are DML createable/updateable/deletable (verified) — no PriceAdjustmentTier/PCR-style platform block. Alternative load path: extract-to-CSV + Bulk API upsert on `GearsetExternalId__c` (ABA exposes it) for a governor-free, Gearset-native load. Verify no RLM/expression-set lock at deploy time.
- Dedup keys (hash into `GearsetExternalId__c` for re-run idempotency):
  - ABA: `ProductId + ProductSellingModelId + AttributeBasedAdjRuleId + AttributeAdjConditionsHash + PriceAdjustmentScheduleId + PricingTerm(+Unit) + CurrencyIsoCode`.
  - ATPS: `Product__c + Product_Selling_Model__c + Attribute_Name__c + Attribute_Value__c + Lower_Bound__c + Upper_Bound__c + CurrencyIsoCode`.
- **Re-run a full `UnitPrice>0` both-currency recount at build time** — the 1256/1661 snapshot is point-in-time.

---

### 4. Sequenced plan (must ship together — one release)

1. **PROVE the gating unknown (sandbox).** Add the 7th column to a sandbox copy of the ABA DT + wire `CurrencyIsoCode` into one ABA step; seed a handful of EUR rows for AAMP; reprice a EUR AAMP line. Confirm it matches the EUR row (expected 1471.995), not the USD row. **If it does not forward, STOP** and pivot to the generic-DT-lookup or Apex fallback before any further build. Gate for everything below.
2. **Build + dry-run the A seed job** (no commit): generate all currency-siblings, write to CSV, spot-check AAMP/VLM/BESEPB worked values against §5, and run the $0-USD-PBE fallback path for the 61 products. Coordinate the D cohort so no $0 rows seed.
3. **Confirm the tier-table branch.** From the smoke element trace, determine whether any symptom resolves via `Price_Adjustment_Tier_Decision_Table`'s `TierValue`; if yes, fold its column edit + per-currency `PriceAdjustmentTier`/ATPS rows into this same release.
4. **Load A rows** (ABA + ATPS, all in-scope currencies) into UAT — **before** any DT refresh.
5. **Deploy B Edit 1** (DecisionTable column) + **refresh/re-index** the ABA table so it indexes the new rows with the currency column.
6. **Deploy B Edit 2** (proc CANVAS, both ABA steps): deactivate → deploy → reactivate v23.
7. **Validate** per §5 (unit + real-records reprice).
8. **Rollback approach.** B is reversible: revert the proc to the prior active version (v22/v23 predecessor) via reactivate, and drop column 7 from the DT (revert `conditionCriteria` + re-refresh). A is reversible by deleting seeded rows on the `GearsetExternalId__c`/currency selector (`CurrencyIsoCode != 'USD'` AND job-run tag) — the seed adds only non-USD rows, so USD data is untouched and cleanup is a scoped delete. Because B without A regresses, **roll back in reverse order: proc → DT column → refresh → (optionally) delete A rows.**

---

### 5. Test / validation

**Unit (Apex).** Cover the seed job: (a) `USD_value × ratio` matches per-currency PBE list to 2 dp; (b) the 61 $0-USD-PBE products route to the CMDT fallback (no divide-by-zero, no $0 seed); (c) idempotency — re-run creates 0 duplicates on the `GearsetExternalId__c` key; (d) currency-invariant fields (`Multiplier__c`, bounds, effective dates, types) copy verbatim.

**Real-records reprice (mirror the Workstream C smoke).** Reprice live EUR/GBP/AUD/CAD lines on the 3 named SKUs and assert configured Net (not just LIST):
- **AAMP** (product `01tWC00000DD11YYAT`, USD list 3150, EUR list 2943.99): 50% tier → **EUR Net = 2943.99 × 0.50 = 1471.995** (CONFIRMED smoke target; the bug produced 1575 with a € symbol).
- **VLM** (`01tWC00000DD1qnYAD`, USD list 500): e.g. 90% rung → EUR 450 × 0.9346 = 420.57; verify the discount ladder localizes.
- **BESEPB** (`01tWC00000DD15FYAT`): tier/overage rows — EUR 1944 × 0.9346 = 1816.86; 3400 → 3177.64; overage 3.74 → 3.50.
- Assert **0-delta on USD lines** (regression guard) and that each non-USD line matches its *own-currency* row (not USD).

---

### 6. Risk + blast radius

- **Blast radius:** 71,502 non-USD QLIs on 603 products (CONFIRMED); full ABA population 1,661 products. Fix touches a **native, auto-generated decision table with no Apex hook** — the native `AttributeDiscount` element is opaque; the currency-forwarding assumption (§2 gating unknown) is the top risk.
- **0-delta on USD:** the seed adds only non-USD rows and the column key defaults matching to same-currency, so USD pricing is unchanged — but *must be proven* with a USD regression pass, because the DT refresh re-indexes the whole table.
- **Refresh timing:** HBASE + incremental-sync-off means a wrong load order (refresh before A) silently indexes an empty currency column → mass non-USD regression. Mitigated by the §4 ordering.
- **$0-USD-PBE (61 products) / Workstream D overlap:** seeding off a $0 base yields $0 non-USD rows (reproduces the Net=0 symptom). Fallback path + D coordination required.
- **Repo staleness:** live proc is v23; building off the stale repo (v20/v22) would deploy against the wrong active version.
- **Tier-table branch:** if L1 resolves via `Price_Adjustment_Tier_Decision_Table`, an ABA-only fix leaves L1 broken.

---

### 7. Open DECISIONS to escalate (Finance / Marc)

1. **Per-currency value source of truth (Marc).** Confirm the design-aligned rule = static per-currency PBE list ≡ `Currency_Conversion_Formula__mdt` static rate, explicitly **NOT** runtime `CurrencyType.ConversionRate` (the GBP=1.0 trap). Evidence says they converge today; get written sign-off that this is the intended standing rule (matches "Currency Conversion for Pricebooks").
2. **Currency scope (Finance).** Seed 4 demand currencies (P1, 56,723 rows) or all 9 active (127,673)? Recommend all 9 — the key has no fallback and JPY/CHF/NZD/ILS/ARS quotes would regress the day they occur.
3. **$0-USD-PBE (61 products).** Confirm CMDT-fallback is acceptable vs. finance-provided values, and align with Workstream D so those aren't seeded at $0.
4. **Tier-table inclusion.** Decide whether `Price_Adjustment_Tier_Decision_Table` gets the same B treatment in this release (depends on the smoke element trace).
5. **Bespoke localization exceptions.** Confirm no product has a hand-set per-currency price that the uniform ratio would overwrite (evidence: 1256/1256 uniform, but snapshot-based).

---

### 8. Effort estimate + phasing

**ASSUMPTION-based rough estimate (dev-days):**
- **Phase 0 — Gating proof (§4 step 1): 1–2 d.** Highest-leverage; blocks everything. If the native element does not forward currency, re-scope (Apex/generic-DT fallback) adds ~3–5 d.
- **Phase 1 — B metadata (DT column + proc CANVAS wiring, both steps, deploy dance): 1–2 d.**
- **Phase 2 — A seed job (clone `Fortra_BulkPriceUpdateBatch` + `Fortra_CurrencyConversionService`, ABA + ATPS, idempotency, $0 fallback, unit tests, dry-run CSV): 3–4 d.**
- **Phase 3 — Integrated UAT load + refresh + reprice validation (§5): 1–2 d.**
- **Contingency — tier-table branch if in scope: +1–2 d.**

**Total ≈ 6–10 dev-days** for the ABA path, ship as **one coupled release** (never B or A alone). Suggested phasing: gate first (Phase 0), then build A and B in parallel, converge for the ordered load/deploy/validate in Phase 3.

**Key artifacts (absolute paths):**
- `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/dt_retrieve/decisionTables/Attribute_Based_Adjustment_Decision_Table.decisionTable-meta.xml`
- `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/dt_retrieve/decisionTables/Price_Book_Entry_Decision_Table_v2.decisionTable-meta.xml`
- `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/dt_retrieve/decisionTables/Price_Adjustment_Tier_Decision_Table.decisionTable-meta.xml`
- `/Users/liamjeong/Documents/Code/Fortra/Data/sc3384/proc_live/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (live v23; ABA steps at 125451/125618 and 125628/125788; PBE template at 128981–128987)
- Reuse: `/Users/liamjeong/Documents/Code/Fortra/force-app/main/default/classes/Fortra_CurrencyConversionService.cls`, `Fortra_BulkPriceUpdateBatch.cls`, `Fortra_BulkPriceUpdateInvocable.cls`; pattern: `AttributeLoadingBatch.cls`; C consumer reference: `AttributeVolumeCalculator.cls`

---

## ADVERSARIAL VERIFICATION (read this — refutes 2 core assumptions)

Verification complete. All evidence gathered from live FortraUAT metadata + data. Here is my adversarial verdict.

---

# ADVERSARIAL VERDICT — SC-3384 B+A Build Plan

Stress-tested against live metadata (3 decision tables + the 131,338-line proc) and real UAT data. Two of the three riskiest assumptions do NOT survive as stated.

## Point 1 — FEASIBILITY of B: **RISKY, leaning REFUTED for the described wiring**

**DT column (Edit 1): CONFIRMED feasible + table is NOT locked.**
- ABA DT on disk has exactly 6 inputs, `conditionCriteria = 1 AND 2 AND 3 AND 4 AND 5 AND 6`. Adding `CurrencyIsoCode` as seq 7 → `…AND 6 AND 7` is structurally valid.
- The ABA table is `status=Active`, no namespace prefix, standard `sourceObject=AttributeBasedAdjustment` — **not managed/locked**; deployable via the api-67 path.
- PBE precedent CONFIRMED byte-for-byte: `Price_Book_Entry_Decision_Table_v2` carries `CurrencyIsoCode` as INPUT seq 4, `operator=Equals`, `isRequired=true`, `conditionCriteria = 1 AND 2 AND 3 AND 4`. The plan's description of the precedent is accurate.

**Proc wiring (Edit 2): REFUTED as a mechanical PBE mirror — false-analogy risk.** The plan treats the ABA step as wireable "exactly like PBE." The metadata says otherwise:
- The PBE currency param lives in a native **`ListPrice`** element whose parameter contract *includes* `CurrencyIsoCode` (confirmed at proc line 2905: `name=CurrencyIsoCode`, `value=CurrencyIsoCode`, context field, `type=Parameter`).
- The ABA step is a **different** native element: `actionType=AttributeDiscount`, `stepType=BusinessKnowledgeModel`, with a **fixed, curated parameter contract** — `AttributeName, AttributeValue, InputUnitPrice, AdjustmentValueField, AdjustmentTypeField, LookUpId, IsContractEnabled, IsPriceImpacting, Quantity, EffectiveFrom/To …` — and **no `CurrencyIsoCode`**. Its DT is keyed on `AttributeAdjConditionsHash` (an internally-computed hash), so the element constructs its own match key; it does not passthrough arbitrary DT columns.
- **Zero** AttributeDiscount steps forward currency anywhere in the 131k-line proc (all 23 inline versions). Every `CurrencyIsoCode` param occurrence sits in a ListPrice block. There is **no in-org precedent** that `AttributeDiscount` honors an added currency parameter.
- Consequence: dropping a `<parameters>CurrencyIsoCode</parameters>` into the AttributeDiscount `customElement` is **likely inert** (unknown param ignored by the managed element). Combined with Edit 1's `isRequired=true` 7th column, if the element does not supply currency at match time, the required input is unsatisfied and **no rows match — regressing ALL lines including USD to list/$0.** The plan's §2 "gating unknown" is not an edge case; the metadata makes it the **most probable outcome**. The plan should be re-weighted so the generic-DT-lookup / Apex fallback is the expected path, not the contingency, and Phase-0 sandbox proof is a hard gate before any A build.

## Point 2 — VALUE-CORRECTNESS of A: **REFUTED (internal contradiction between the two targets)**

**AAMP EUR 1471.995: CONFIRMED.** Real data — USD ABA override `1575` (verified: AAMP rows are 3150/1575/1575, all `Override`, all USD), EUR PBE 2943.99, USD PBE 3150 → ratio **0.9346** (= CMDT `EUR_Euro.Conversion_Rate__c` 0.9346 exactly). `1575 × 0.9346 = 1471.995`. The rule reproduces AAMP.

**HRM EUR tier 2373.60: REFUTED against the plan's own rule.** Real data:
- HRM USD ATPS tier (Self Managed, 50-99) = **2580**; EUR ATPS tier = **2373.60**.
- Actual factor = 2373.60 / 2580 = **0.9200** — this is the **runtime `CurrencyType.ConversionRate` EUR=0.92** (verified live), **NOT** the static 0.9346 the plan prescribes.
- The plan's rule (`× 0.9346`) yields `2580 × 0.9346 = 2411.27`, which does **not** equal the existing/"correct" 2373.60.

So the smoke's two "correct" targets were produced by **two different EUR factors**: ABA/AAMP at **0.9346** (static/list-derived) and ATPS/HRM at **0.92** (runtime FX — the exact rate the plan says "MUST NOT use … would reproduce the bug"). The already-shipped Workstream C EUR ATPS seed used 0.92. The plan's claim that one uniform ratio reproduces **both** numbers is arithmetically false.

- The "1256/1256 uniform ratio" claim is true **only for PBE LIST prices** — I independently confirmed 0.9346/0.7874/1.3889/1.5385 uniform across all 4 SKUs (AAMP/HRM/VLM/BESEPB). That uniformity does **not** extend to seeded net/tier values, one of which (HRM EUR ATPS) is 0.92.
- PBE-list-ratio ≡ CMDT-rate (both 0.9346): CONFIRMED — those two converge, as the plan says. The defect is the **third** live value (0.92 ATPS) the plan mislabels as reproducible.
- **Impact:** seeding ATPS at 0.9346 will disagree with the 37 existing EUR HRM rows (2411.27 vs 2373.60) — the idempotency key will either skip them (leaving a 0.92/0.9346 split inside one table) or overwrite finance-blessed values. **Which factor is authoritative for net/tier values is a genuine open Finance/Marc question the plan resolves prematurely.** This must be escalated before A runs, and Workstream C's already-seeded EUR ATPS data must be reconciled to whatever ruling lands.
- Supporting the plan's runtime-FX warning: JPY `CurrencyType.ConversionRate = 1` (=USD numerically) vs CMDT JPY = 149.2537 — runtime FX for JPY would be catastrophic. The "never use runtime rate" instinct is right; the contradiction is that the org's own ATPS seed already violated it for EUR.

## Point 3 — MUST-SHIP-TOGETHER + 0-delta: **CONFIRMED coupling; 0-delta RISKY; dedup under-verified**

- **Must-ship-together: CONFIRMED mechanism.** `AttributeAdjConditionsHash` does **not** encode currency, so USD and EUR siblings share an identical 6-key match today; only the added 7th column disambiguates. Hence A-without-B → non-deterministic USD/EUR collision; B-without-A → required input unmatched → regression. Real coupling.
- **0-delta on USD: RISKY, not proven.** All 13,073 ABA rows are `CurrencyIsoCode='USD'`, so USD data exists to match a required currency input (as PBE proves for its USD rows). **But this is conditional on the element forwarding currency (Point 1).** If it doesn't, `isRequired=true` breaks USD too. The plan's phrasing "seed adds only non-USD rows so USD is untouched" is true for the DATA but false for the LOOKUP — the DT schema change touches USD matching. A USD regression pass is mandatory, not optional.
- **Dedup / duplicates: RISKY / under-verified.** `GearsetExternalId__c` exists on ABA (confirmed), and the dedup-key fields (`AttributeAdjConditionsHash, PricingTerm, PricingTermUnit, PriceAdjustmentScheduleId`) all exist. Two gaps: (1) I did **not** confirm `GearsetExternalId__c` is a true **unique** External-Id index — a Bulk upsert on a non-unique field silently creates duplicates; a query-then-skip batch is safer. (2) **Pre-existing USD duplicates**: AAMP already has two byte-identical `Override 1575` rows. If the dedup hash collapses them, the seed emits one EUR sibling for two USD sources (row-count/coverage mismatch); if it doesn't, the hash isn't unique. The "can't create duplicates" claim requires the existing USD dupes to be handled first.

## Additional under-scoped flags

- **Tier-table branch is likely OUT of scope, not "TBD."** The smoke L1 row is explicit: BESEPB tiers resolve through **ABA** (`0lDa50000007BEuEAM`), "NOT the ATPS/C path." `Price_Adjustment_Tier_Decision_Table` (`0lDa50000007BEs…`) is indeed currency-blind (I confirmed: 7 inputs, no currency), but no SC-3384 ticket line routes through it. The smoke already answers the plan's open question — L1/L2/L3 are all ABA. PAT is a latent gap for other flows, not this ticket's hot path. Don't fold PAT seed rows into this release without a fresh trace.
- **ATPS 0.92 reconciliation (biggest under-scoped item)** — see Point 2. The live Workstream C EUR data is on a different FX regime than B/A will use.
- **Proc reactivation weight:** the ExpressionSetDefinition is 131,338 lines with **23 inline versions** (confirmed). Deactivate→edit-canvas→reactivate on a file this size, with a currency change that may prove inert, is a heavy, reversible-but-risky operation — sequence it last and only after the Phase-0 gating proof passes.

## Bottom line

- **B feasibility:** column = fine and unlocked; **wiring = probably won't work as a PBE mirror** because ABA uses a different native element with a fixed contract that exposes no currency param and has zero in-org precedent for forwarding one. Treat the Apex/generic-DT fallback as the likely real path. Gate hard on Phase-0.
- **A value rule:** reproduces AAMP but **not** HRM — the two smoke targets use 0.9346 vs 0.92. The plan cannot claim its single rule matches both; the correct net-value FX regime is an unresolved Finance decision, and the shipped C data already contradicts the plan's rule.
- **Ship-together + dedup:** coupling is real; 0-delta-on-USD is gated on the same unproven element behavior (so not guaranteed); idempotency needs a uniqueness check and handling of pre-existing USD duplicate rows.

Key evidence paths: `Data/sc3384/dt_retrieve/decisionTables/*.decisionTable-meta.xml`, `Data/sc3384/proc_live/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (ABA step `customElement` at ~640-760, `actionType=AttributeDiscount`, no currency param; PBE `ListPrice` currency param at line 2905), `Data/sc3384/smoke_20260709.md`.