# SC-3372 PBEDP Coverage — Resolution Plan

**Status:** Validated, ready to execute. **Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`). **Date:** 2026-06-13. **Mode of this plan:** read-only investigation complete; execution below is **deploy/DML and requires a fresh explicit deploy authorization** (per memory: read-only inspection is fine; any UAT DML — even additive config rows — needs a fresh ack).

**Live facts re-verified for this plan (2026-06-13, FortraUAT, read-only):**
- Derived PBEs (`IsDerived=true`) = **3,453**; PBEDP rows = **176** covering **174** distinct PBEs → **~3,279 (95%) uncovered**. (Re-queried live.)
- PBEDP is **directly insertable** — the 4 most recent rows (`00000691` Liam 06-09, `00000694/695` Nir 06-12, `00000696` Liam 06-13 marker `ZZ_E2E_RCA_260613`) have **no GearsetExternalId** → created via Apex/REST/import, not Gearset Bulk. (Re-queried live.)
- **1:many is real** — `01uWC000005wsfZYAQ` and `01uWC000005wsy8YAA` each carry **2** PBEDP rows (different `ContributingProductId`). (Re-queried live.)
- **`Legacy_Product_Number__c='New'`** for non-FIM families (BI/CS/DM/GOA/SM all returned the literal `'New'`); FIM has real numerics (`FIM-FIM-RNM-TTBELN` = `180000-02`); `GS-GSE-RNM-EFT8` = `'8326, 8327, ...'` (comma list). (Re-queried live.)
- **`GS-GSE-NRPS-E8CP` is zero-list in all 10 PBEs** (every currency, both books). (Re-queried live.)

---

## Decision: BACKFILL vs REMOVE-NATIVE-ELEMENT — pick one, justify

**DECISION: BACKFILL PBEDP. Do NOT remove the native `DerivedProductsRenewals` element.** This is both the safer and the correct lever for the SC-3372 "MissingContributor / contributing products are missing" gap.

**Why backfill is correct and safe:**
1. **The native element is the only `resultIncluded=true` derived committer in the live V14 procedure** (`DerivedProductsNativePull` → `DerivedProductsRenewals`, snapshot lines ~71948–72105). Removing it wholesale converts a hard-error into a **silent $0** for the **~167 PBEDP-only / no-MTD products** (FIM/RPA/PIA families) whose *real* price comes only from the native pull, plus **~536k native-priced lines** depend on it. Removal is a procedure republish — high blast radius, irreversible-in-place, and republish churn is the documented source of regressions (SC-3371, reprice contextDef gack).
2. Backfill is **additive, per-row, reversible config data**: zero triggers on the object, no record-triggered automation, no procedure republish. Risk is bounded to *one field* (`ContributingProductId`).
3. **Precedent already set the direction:** the SC-3403 M-5 fix was resolved by Nir *creating PBEDP rows* (06-12), and Liam created one 06-13. Backfill is the established remediation pattern in this org.

**Why "remove the native element" is a misread of the design note:** the dossier wording "design says remove the native element" is **narrowly about making native NON-AUTHORITATIVE for the 5-line stamped SC-3346 MTD cohort** (where the build's `tier × Source_List_Price__c` formula must win), proven live by PIAMBK netting **71 = 0.20×355** (formula), not 355 (native). It is **not** a wholesale delete. For MTD products native is just a **gate**; for non-MTD products native is the **pricer**. A single global lever cannot serve both — hence backfill (per-cohort), not removal.

**Two cohorts, both served by backfill:**
- **Cohort A — MTD / build-priced (181 lack PBEDP):** backfill PBEDP *purely to satisfy the gate*. The build formula then sets the real net; contributor value is largely irrelevant but must still be a sane license.
- **Cohort B — PBEDP-only / no-MTD (167):** native pull IS the pricer; ensure PBEDP exists **and** data-fix any zero-list contributor (else still $0).

---

## The gap, scoped — the precise IN-SCOPE set

The actionable gap is **far smaller than 3,279.** Scope by three intersecting filters: **active pricebook × in-use × contributor-resolvable.**

| Layer | Count | Decision |
|---|---|---|
| All uncovered derived PBEs | **3,279** | Universe; do NOT backfill blindly |
| …on **Fortra Price Book** (active) | **1,717** | Pricebook filter — Standard Price Book (1,560) excluded |
| …**in-use** (product on a live QLI/OI) on Fortra Price Book | **231 PBEs / 231 products** (New 113 / Renewal 118) | **PRIMARY IN-SCOPE SET** |
| …of those, **contributor auto-resolvable today** (FIM via legacy-key) | **68** (FIM only) | **Phase-1 auto-backfill** |
| …in-use but contributor NOT auto-resolvable (non-FIM) | **~163** | **Phase-2: needs business crosswalk** |

**PRIMARY IN-SCOPE = the 231 live Fortra-Price-Book PBEs.** This is the set that actually throws MissingContributor / prices $0 in real quotes today. Within it:
- **68 (all FIM)** are auto-mappable now via the legacy-number key → Phase 1.
- **~163 (non-FIM: GS, SM, GOA, RPA, NW, DP, BI, CM, IGA, CS, DM, ES, OS)** have `Legacy_Product_Number__c='New'` → no join key → **require a business-owned crosswalk** before insert (Phase 2). Note GS in-use count is large (~141 by BU prefix) but GS legacy numbers are comma-lists, not single keys → still manual.

**Explicitly EXCLUDED from the first fix (and why):**
- **Standard Price Book (1,560 uncovered)** — inactive book, 1,551/1,560 products dead; PBEDP there does not affect live pricing. *Confirm open-question on Standard fallback before fully ignoring, but default = ignore.*
- **Fortra Price Book dead-catalog (1,486)** — never quoted/ordered; adds 14× data volume, zero quoting value. Optionally widen to "Fortra Price Book ALL gap = 1,717" later for catalog completeness, **only after the live-231 are fixed and validated.**
- **2 on Fortra Derived Pricing** — negligible.

---

## Contributor-mapping rule — exact rule, confidence, auto-mappable fraction

**This is the gating work. There is NO deterministic ProductCode transform** — proven false: `FIM-FIM-RNM-TSAENM` maps to **two different** licenses in different existing rows (`VEMEVD` *and* `TRST`), and 4th-segment SKU tokens share no stem. Do **not** build a code heuristic.

**The reliable key is `Legacy_Product_Number__c` (the 6-digit base part number):**
> Maintenance product (suffix `-02` New / `-04` Renewal) → contributing license sharing the same **numeric base** (suffix `-00`), preferring the **NRPS/Perpetual** variant over RSS/Subscription on ambiguity.

Proof (live): `FIM-FIM-RNM-TTBELN` (`180000-02`) → `FIM-FIM-NRPS-TTBELP` (`180000-00`); `FIM-FIM-RNM-IP36TB` (`500104-02`) → `FIM-FML-NRPS-IP36TE` (`500104-00`, vendor seg differs FIM≠FML — proves the legacy base is the key, not ProductCode prefix).

**Confidence / coverage:**
- Reverse-engineered against the 176 hand-curated rows: legacy-base key recovers **150/156 (96%)** of resolvable pairs.
- The competing **name-rule** (`strip "-NewMaintenance"/"-RenewalMaintenance" suffix → match license name, prefer NRPS`) reproduces **156/176 (89%) bare**, **~98% after a ~20-item override list** (RSS-over-NRPS for FIM DPEENM/CCMMSR/DPEERM; strip `-EVAL`/`(Technical)` qualifiers; ~3 arbitrary: TSAENM→VEMEVD, TACADE→TESP, TSARM→TTBELP).

**Auto-mappable fraction of the in-scope set:**
- **Legacy-key (high-precision):** **68 of 231 (all FIM)** auto-map cleanly. The other ~163 are blocked by `Legacy_Product_Number__c='New'`.
- The name-rule is broader on the *full* 3,279 (claims 94% auto) **but is lower-precision and unvalidated against the non-FIM in-use lines** — treat it as a *proposal generator for human review*, NOT a blind apply.

**Unmappable remainder:** the ~163 non-FIM in-use products. For these the contributor must come from **(a)** the legacy `ProductConfigurationRule` referenced by covered rows' `Legacy_Rule_Id__c` (14O prefix) — re-mine it for the new set; **(b)** a business-owned maint→license crosswalk; or **(c)** if no license exists (reinstatement fees, merged bundles like Robot/Classification/Digital Guardian/Vityl), price via the procedure formula instead of PBEDP. **A wrong contributor prices wrong silently** — this is why Phase 2 is human-gated.

---

## Source_List_Price dependency — is SLP backfill also needed?

**No. Do NOT backfill `Source_List_Price__c` independently. PBEDP is the upstream primary; SLP is downstream and self-heals.**

Proven mechanism (live, `Stamp_Source_List_Price` flow v8, `301WC00000kJs76YAC`, before-save on QuoteLineItem):
1. Proceeds only if the QLI's maint PBE `IsDerived=true`.
2. **SOQL `PriceBookEntryDerivedPrice WHERE PricebookEntryId = $Record.PricebookEntryId`; if count = 0 → flow EXITS without stamping.** SLP stamping is **strictly gated on PBEDP existing.**
3. Reads `PBEDP.ContributingProductId` → finds the license's non-derived PBE → stamps its `UnitPrice` into `Source_List_Price__c`.

Therefore: backfilling PBEDP **(a)** clears MissingContributor AND **(b)** automatically enables SLP stamping on the next save/reprice. And for **config-covered MTD-less products, SLP is not even on the critical path** — they price via the native ratio (e.g. net 65 = 0.20×325, `Source=null`). One data change (PBEDP) fixes both symptoms. **Sequence: backfill PBEDP → reprice → SLP self-stamps.**

**Two residual $0 cases PBEDP does NOT fix (handle separately, do not assume backfill closes them):**
1. **Zero-list contributor (19 known, incl. `GS-GSE-NRPS-E8CP` confirmed $0 in all 10 PBEs; + FIM/Tripwire term-based NRPS family):** `rate × 0 = $0` even with correct PBEDP. Needs **Product Management to supply real license list prices** (data), or suppress the auto-maint line if the license is legitimately free. For these, `Formula='ListPrice'` may be the correct value (1 existing outlier already uses it) **and** the PBE.UnitPrice must be fixed.
2. **Multi-derived-line contention (462 vs $0 on identical CCM lines, quote `0Q0WC0000036elp0AA`):** two derived lines share one contributor; native binds it to the first, second → $0. This is a **procedure/native-element behavior**, owner-gated, **separate from this backfill** — track as its own item.

---

## Execution recipe — API/method, field template, idempotency, sample-validate-first

**Method: Bulk/Composite UPSERT keyed on `GearsetExternalId__c`** (idempotent + governor-safe for the batch). Apex `Database.insert` also works, but upsert prevents double-insert on re-runs. **PBEDP is NOT PRTM-class** — do not route through the Connect/Composite-only workaround; standard `sf data upsert` works (proven by 4 human-created rows + describe createable=true, 0 triggers).

**Field template (from real known-good row `182WC000000FN26YAG`, canary PIAMBK):**

| Field | Value | Notes |
|---|---|---|
| `PricebookEntryId` | the uncovered `IsDerived=true` maint PBE (UnitPrice=0) | **required** |
| `ContributingProductId` | resolved license Product2 Id (e.g. `01tWC00000DD1btYAD` = PIA-PIA-NRPS-PIAP) | **the hard part** |
| `DerivedPricingScope` | `Both` | required; 176/176 |
| `Formula` | `UnitPrice` (use `ListPrice` only for the zero-list-price outlier family) | 175/176 |
| `PricingSource` | `Product` | 176/176 |
| `CurrencyIsoCode` | `USD` | all derived PBEs USD-only |
| `EffectiveFrom` | `2026-04-01T00:00:00.000+0000` | 174/176 convention — **confirm vs go-live** |
| `EffectiveTo` | *(null)* | 175/176 leave null |
| `GearsetExternalId__c` | deterministic, e.g. `SC3372-<PricebookEntryId>-<ContributingProductId>` | unique upsert key |
| `Legacy_Rule_Id__c` | source PCR Id (provenance, not unique) | traceability |
| `ProductId`, `ProductSellingModelId`, `Name`, `OwnerId`, `PricebookId` | **OMIT** | auto-derived from PBE |

**Natural key:** `(PricebookEntryId, ContributingProductId, DerivedPricingScope)` — 0 dup triples exist; never insert a second row with the same triple. A maint PBE MAY legitimately need >1 row (different contributors) — support 1:many.

**SAMPLE-VALIDATE-FIRST (mandatory before any batch):**
1. Pick **one currently-uncovered, in-use FIM maint PBE** (e.g. an `FIM-*-RNM-*` from the 68; **not** PIAMBK — already covered).
2. Insert ONE PBEDP via `sf data create record` / single-row upsert.
3. Verify the contributor PBE itself has `UnitPrice>0` (FIM/Tripwire NRPS contributors are often $0 — if so this canary will clear the error but still $0; pick a non-zero-list FIM canary).
4. **Reprice** that product on a test quote (UI **Reprice All** — NOT headless `Fortra_Migration_Price_Quote`, which returns IsSuccess even when the line never prices) with a **FINEST** log. *(Reprice is a separate authorized action.)*
5. Confirm: **no "We can't price when contributing products are missing"** and **non-$0 net via the native path**.
6. **Only then** bulk-upsert the rest of the validated, contributor-confirmed set.

---

## Risks & guardrails

- **NEVER insert a wrong `ContributingProductId`** — it prices wrong **silently** (no error). This is the single highest risk. Mitigation: human-review the full maint→license CSV before load; auto-apply only the 68 legacy-key FIM rows; hand non-FIM to the business.
- **`restrictedDelete=true`** on PBEDP children — fine for insert; for rollback, delete the PBEDP rows first (they don't block their own deletion). Object is `deletable=true`.
- **Idempotency:** upsert on `GearsetExternalId__c` (unique, idLookup) → re-runs never double-insert. Tag every row with `Legacy_Rule_Id__c` provenance and a distinguishable GSX prefix (`SC3372-…`) so the batch is queryable and **rollback = `sf data delete bulk` on `GearsetExternalId__c LIKE 'SC3372-%'`** — clean, reversible, no procedure touch.
- **Do NOT remove the native `DerivedProductsRenewals` element** — 167 PBEDP-only products price only via it; removal = silent $0 + breaks the Stamp flow's contributor resolution.
- **Stale-inventory risk:** re-derive the uncovered set at preflight (Gearset/refresh churn) — same-day inventories go stale.
- **Renewal $0 is OUT of scope** (per 2026-06-13 handoff: renewal/qty0/ListPrice=0 line is not a priced node → needs a `COLAUpliftPrehook` prehook-seed, separate workstream). Confirm with Nir that SC-3372 scope = new-business gate only.
- **High-confidence path:** legacy-key FIM (96% precision) + sample-validate one canary + per-row reversible upsert. Everything non-FIM stays human-gated until the business crosswalk lands.

---

## Step-by-step execution checklist

1. **Get fresh deploy authorization** for FortraUAT DML (this plan's execution is DML; current pass is read-only). Confirm SC-3372 scope = new-business gate only with Nir.
2. **Preflight re-derive (read-only):** re-run the uncovered-set query to refresh counts (currently 3,279). Produce the **231 in-use Fortra-Price-Book** working set.
   `SELECT PricebookEntryId FROM PricebookEntry WHERE IsDerived=true AND Pricebook2.Name='Fortra Price Book' AND Product2.ProductCode IN (<live QLI/OI products>)` minus the 174 covered.
3. **Build the contributor map (gating work):**
   a. Auto-resolve the **68 FIM** rows via `Legacy_Product_Number__c` base-number key, prefer NRPS over RSS, apply the ~20-item override list.
   b. For the **~163 non-FIM** in-use rows, mine `Legacy_Rule_Id__c` PCRs (14O) and/or request a business crosswalk. **Hold these — do not auto-insert.**
   c. Emit a reviewable CSV: `maint PBE Id, maint code, proposed ContributingProductId, license code, license PBE UnitPrice, source (legacy-key|PCR|manual), confidence`. **Product-team sign-off required.**
4. **Pre-screen zero-list contributors:** flag any proposed contributor whose license PBE `UnitPrice=0` (E8CP + 19-product FIM/Tripwire class). These get a **separate list-price data fix** (Product Mgmt) and/or `Formula='ListPrice'`; do not count them as "fixed" until the license has a real price.
5. **Sample-validate ONE FIM canary** (non-zero-list contributor): insert 1 PBEDP → UI Reprice All with FINEST → confirm no MissingContributor + non-$0 net. *(authorized reprice)*
6. **Batch-upsert the validated FIM 68** (and any signed-off non-FIM) keyed on `GearsetExternalId__c='SC3372-<PBE>-<Contrib>'`, `Legacy_Rule_Id__c` set, template fields above.
7. **Reprice affected live quotes** and assert NetUnitPrice>0, MissingContributor gone.
8. **Re-verify coverage:** PBEDP distinct-PBE count rose by the inserted count; the in-use-231 set has 0 remaining uncovered (minus held non-FIM).
9. **Track separately (do NOT close under SC-3372):** (a) zero-list contributor list-price data fix; (b) multi-derived-line contention (462 vs $0); (c) renewal-$0 prehook-seed; (d) optional catalog-completeness widen to all 1,717 Fortra-book gap rows.
10. **Rollback ready:** `sf data delete bulk` on `GearsetExternalId__c LIKE 'SC3372-%'` reverses the entire batch with no procedure republish.

**Artifacts:** gap quantification under `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/sc3372_new/gap_quant/`; PBEDP/license corpus under `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/` (`pbedp_all.json`, `license_catalog.json`, `all_derived_pbe.json`, `prc_*.json`).