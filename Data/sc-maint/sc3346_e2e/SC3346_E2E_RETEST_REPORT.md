# SC-3346 Maintenance (Derived) Pricing — E2E Re-Test Report (post-fix, integration excluded)

> **Audience:** Build owner (Nir Kailash) + peer reviewer (SC-3403)
> **Scope:** End-to-end re-test of the SC-3346 Maintenance (Derived) Pricing build on FortraUAT after this session's fixes. **Workday/MuleSoft integration explicitly excluded.**
> **Tracking tickets:** SC-3346 (build), SC-3403 (peer review), SC-3404 (renewal-commit cluster), SC-3372 (PBEDP coverage), SC-3350 (COLA rates grain).

---

## Run metadata

| Field | Value |
|---|---|
| **Org** | FortraUAT |
| **Active pricing procedure** | `Rev_Mgmt_Default_Pricing_Procedure` **V14** — ExpressionSet `9QLWC0000015cDl4AI`, ExpressionSetVersion `9QMWC00000023eX4AQ` (`VersionNumber=14`, `IsActive=true`, **sole** active; V1–V13 all `IsActive=false`, V13 now labeled "(Deprecated)") |
| **Re-test date** | 2026-06-14 |
| **Scenarios** | 30 (re-tested live; 19 had prior verdicts, 11 are net-new or first-executed) |
| **Method** | Read-only SOQL / Tooling / metadata retrieve (fresh, api v67) + non-destructive `Place Sales Transaction` Force reprices (`configurationMethod=Skip`) on **Draft** quotes only; FINEST ApexLog capture; SOLO Apex test runs (`--synchronous --code-coverage`) |
| **Integration** | **EXCLUDED** — no Workday/MuleSoft, no Order activation, no platform events |
| **Guardrails respected** | No DML on Quote/QLI; no deletes; no activation/submit; no integration; Accepted/Ordered quote **00781068 untouched**; reused existing TraceFlags (none created/deleted) |
| **Artifacts root** | `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_rca/work/` (one subdir per scenario_id) |

---

## Build-readiness verdict — **CONDITIONAL NO-GO**

**The build cannot ship to production as-is.** The structural pillars are sound and improving, but a **critical** renewal-pricing commit defect and a **high** new-business tier defect both still produce wrong/zero money on live renewal and new-business paths, and the deploy package is incomplete.

**Justification:**

1. **CRITICAL blocker — RN-COLA-COMMIT (SC-3404).** Renewal-maintenance lines that lack a `QuoteAction.Type='Renew'` still commit the **wrong** `NetUnitPrice` (canary 00781109 = 60.64 vs correct COLA net 67.38; sibling lines commit 0 and 54.58). The in-flight COLA math is correct (RN-COLA-MATH pass) and the posthook now actively writes 67.38, but the engine silently no-ops the write on the structurally-excluded derived/zero-list node. This is owner-gated (engine-owned persistence wall).
2. **HIGH — NB-DERIVED-TIER.** The V14 derived formula hard-codes only 3 of 7 tiers (Premier/Standard/Professional); Basic/Premium/Express/Expert and orphan `platinum` fall through to **$0** maintenance net (207 live QLI-attribute rows on minority tiers).
3. **HIGH — PBEDP / M-5 (SC-3372).** 94.2% of active derived-maintenance PBEs still lack `PriceBookEntryDerivedPrice` config (3254 of 3453 uncovered) — improved from 95.0% by this session's 25-FIM backfill, but systemically open.
4. **HIGH — TEST-SUITE / M7-COVERAGE regression.** A same-session prehook refactor (renamed `buildOverrideMap`→`getContractOverrides`) broke `COLAUpliftTest` compilation, dropping `COLAUpliftPrehook` to **0%** and `COLAUpliftHandler` to 39% — below the 75% deploy gate. A `RunSpecifiedTests` deploy would fail.
5. **MEDIUM packaging gap — FIELD-PACKAGING / M-3/M-6/B-2.** Load-bearing SC-3346 fields (all OrderItem-side fields, both Order-side gate fields, 5 QLI fields) are **absent from deployable `force-app/main/default`** and staged in **no** `package.xml` — a standard prod promotion would omit them.

**Path to GO** is well-defined and mostly UAT-fixable (tier completion, PBEDP backfill, test re-sync, field packaging); the **only true blockers requiring owner/design decisions** are SC-3404's commit mechanism, the COLA rates grain (SC-3350 D1), and the B-5 decision-table re-key. See **Recommendations**.

---

## What changed since the last run — fixes landed this session

| Change | Scenario(s) affected | Effect on scorecard |
|---|---|---|
| **PBEDP 25-FIM backfill** (`Legacy_Rule_Id__c='SC3372BACKFILL'`, all Formula=UnitPrice/Source=Product/Scope=Both, 14 NewMaint + 11 RenewMaint, all 14 contributors priced) | PBEDP-COVERAGE, ZERO-LIST-PBE, M5-PBEDP | Coverage 176→201 rows, 174→199 distinct, gap 95.0%→**94.2%**. Closes the in-use FIM new-business "contributing products are missing" gate. **Still fail** (systemic). |
| **M-2 dead-code removal** — `DerivedPricingNewBusiness` (`Base_Price__c × tier`, dead `MDT` gate) removed from active V14 block (diff-confirmed vs 2026-06-13 snapshot; V14 block shrank 5616→5551 lines) | NB-DERIVED-FORMULA, M2-DEADCODE, SDD-CONFORMANCE | **partial→pass** (NB-DERIVED-FORMULA), **partial→pass/low** (M2-DEADCODE). One live new-business formula, no competing arm. |
| **RN-MULTIYEAR reclassified** — multi-year/out-year/MyCAP proven inert at the commit layer (0 procedure refs; out-year used only for a Deal-Desk approval flag) | RN-MULTIYEAR | **fail/high (SC-3404) → out-of-scope/none.** Prior "multi-year defect" was the single-year RN-COLA-COMMIT defect mislabeled. |
| **RN-COLA-RATES data clean** — BoKS duplicate CMDT pair consolidated (22→21 rows, single `Powertech_IAM_BoKS` row, SystemModstamp 2026-06-14); 0 null-category active RRM products | RN-COLA-RATES, MDT-RECORDS | Data-quality clean; **MDT-RECORDS severity medium→low.** Residual grain exceptions still wrong (owner-gated). RN-COLA-RATES stays partial. |
| **Posthook rework** (`PartnerNetPricePosthook`, LMD 2026-06-14T02:35) — now actively writes `NetUnitPrice=colaNet=67.38` (no ×0.90) and submits via `updateContextAttributes` | RN-COLA-COMMIT, RN-PARTNER-DD, MAINT-ONLY, M1-SDD | **Partial improvement:** lines WITH `QuoteAction='Renew'` (e.g. 00781084) now commit correct 67.38; `$0`-commit sub-defect resolved (UnitPrice 0→67.38). Lines WITHOUT a Renew QuoteAction **still wrong** (no-op on excluded node). Severity RN-COLA-COMMIT **critical→high**. |
| **Prehook refactor** (`COLAUpliftPrehook`, LMD 2026-06-14T04:20) — `buildOverrideMap`→`getContractOverrides` | TEST-SUITE, M7-COVERAGE | **Introduced a regression:** `COLAUpliftTest` no longer compiles → `COLAUpliftPrehook` 0% coverage. |
| **SOLO tests un-blocked** — admin-lock that previously blocked `PartnerNetPricePosthookTest` / `MaintenanceOrderDecompositionServiceTest` cleared on retry | DECOMP-SPLIT, DECOMP-BASE, TEST-SUITE | Corroborating coverage now measured (84% decomposition SOLO; posthook 77%). |

**Net effect on scorecard:** 4 scenarios improved verdict (NB-DERIVED-FORMULA, M2-DEADCODE, RN-MULTIYEAR, MDT-RECORDS severity drop); 1 new regression introduced (TEST-SUITE / M7-COVERAGE COLAUpliftTest); the two headline blockers (SC-3404 commit, NB-DERIVED-TIER) **unchanged in verdict** (SC-3404 severity lowered critical→high on RN-COLA-COMMIT due to partial improvement).

---

## Results at a glance

**Counts (30 scenarios):**

| Status | Count | Scenario IDs |
|---|---|---|
| **pass** | 11 | CFG-AUTOADD, NB-DERIVED-NET, NB-DERIVED-FORMULA, RN-COLA-MATH, DECOMP-BASE, STAMP-FLOW, SLP-CARRY, PROC-V14, B3-PARTNER, B4-NULLGUARD, M2-DEADCODE |
| **fail** | 10 | NB-DERIVED-TIER, RN-COLA-COMMIT, RN-PARTNER-DD, MAINT-ONLY, MULTI-ASSET, PBEDP-COVERAGE, ZERO-LIST-PBE, B5-DECISIONTABLE, M5-PBEDP, M7-COVERAGE, TEST-SUITE |
| **partial** | 7 | RN-COLA-RATES, DECOMP-SPLIT, MDT-RECORDS, DATA-FIELD-POP, FIELD-PACKAGING, M1-SDD, SDD-CONFORMANCE |
| **out-of-scope** | 1 | RN-MULTIYEAR |

> Note: fail row lists 11 IDs because TEST-SUITE and M7-COVERAGE are both fail — total fail = 11. Re-tabulated: **pass 11 / fail 11 / partial 7 / out-of-scope 1 = 30.**

**Severity (fail+partial only):** critical 0 · high 7 (NB-DERIVED-TIER, RN-COLA-COMMIT, RN-PARTNER-DD, MULTI-ASSET, PBEDP-COVERAGE, ZERO-LIST-PBE, M5-PBEDP, TEST-SUITE) + MAINT-ONLY (critical). MAINT-ONLY remains the single **critical** (wrong committed GrandTotal on a live maint-only renewal cart).

**One row per scenario:**

| ID | Domain | Status | Severity | Fixability | Note |
|---|---|---|---|---|---|
| CFG-AUTOADD | Auto-add 1st-yr maint | pass | none | na | Configurator rule fires live, gated New vs Renewal, no double-add; 99 all-Active rules |
| NB-DERIVED-NET | Derived (NB) pricing | pass | none | na | 0.20×355=71 exact on 9 lines; reproducible under Force reprice |
| NB-DERIVED-FORMULA | Derived (NB) pricing | pass | none | already-fixed | Live formula = tier×Source_List_Price; M-2 dead-code now removed |
| NB-DERIVED-TIER | Derived (NB) pricing | **fail** | **high** | owner-gated | Only 3 of 7 tiers handled; Basic/Premium/Express/Expert/platinum → $0 (207 live rows) |
| RN-COLA-MATH | Renewal COLA | pass | none | na | In-flight (Base−priorP−priorD)×(1+COLA%)=67.38 exact; FINEST-proven |
| RN-COLA-COMMIT | Renewal COLA | **fail** | **high** | owner-gated | SC-3404. Commit correct only with Renew QuoteAction; canary 60.64≠67.38 |
| RN-PARTNER-DD | Renewal COLA | **fail** | **high** | owner-gated | 60.64=67.38×0.90 frozen fossil on QuoteAction=null nodes; ×0.90 not actively recomputed |
| RN-COLA-RATES | Renewal COLA | partial | medium | owner-gated | 21/21 category rates exact; 2 solution-grain exceptions still wrong (SC-3350 D1) |
| RN-MULTIYEAR | Renewal COLA | out-of-scope | none | out-of-scope | Multi-year/MyCAP inert at commit layer; single-year per both SDDs |
| DECOMP-SPLIT | Order decomposition | partial | medium | owner-gated | Original_Order_Item__c FK-split model not in build; value-stamping instead; doc reconcile |
| DECOMP-BASE | Order decomposition | pass | none | na | B-6 holds; 0 license-base leaks; 84% SOLO coverage |
| STAMP-FLOW | Stamp / data flow | pass | none | na | All stamps exact, re-fire on reprice; COLACalc 67.38/60.64 correct |
| SLP-CARRY | Stamp / data flow | pass | none | already-fixed | M-4 active; 23/23 OI match QLI SLP across 6 distinct prices |
| MAINT-ONLY | Edge cases | **fail** | **critical** | owner-gated | MissingContributor graceful (pass-a); committed net 60.64≠67.38 (fail-b); GrandTotal wrong |
| MULTI-ASSET | Edge cases | **fail** | **high** | owner-gated | License leg correct (4442.35); maint leg 54.58≠60.64; SC-3404 in multi-asset |
| PBEDP-COVERAGE | Config & data integrity | **fail** | **high** | uat-fixable | 94.2% derived PBEs uncovered (was 95.0%); +25 FIM backfill clean |
| ZERO-LIST-PBE | Config & data integrity | **fail** | **high** | uat-fixable | 100% zero-list; canonical BoKS repro still $0 (null Source_List_Price) |
| MDT-RECORDS | Config & data integrity | partial | low | uat-fixable | Maint_Rate 7/7 exact; BoKS dup resolved; orphan `platinum` unused |
| PROC-V14 | Config & data integrity | pass | none | na | V14 sole-active; all elements present, ISNULL-guarded, runs clean |
| DATA-FIELD-POP | Config & data integrity | partial | medium | uat-fixable | Build cohort exact; 3 gaps (44 legacy null-prior, NB SLP, OI carry-forward) |
| FIELD-PACKAGING | Config & data integrity | partial | medium | uat-fixable | Fields/picklists live in UAT; **missing from force-app/prod manifest** |
| B3-PARTNER | Peer-review findings | pass | none | already-fixed | 15%-vs-12% map-miss fixed; 28/28 test; 61,321 lines rescued |
| B4-NULLGUARD | Peer-review findings | pass | none | already-fixed | All 4 operands ISNULL-guarded in V14 only; live all-null reprice = clean 0 |
| B5-DECISIONTABLE | Peer-review findings | **fail** | medium | owner-gated | AssetActionSource DT RefreshStatus=Failed; **off the build path** (0 refs) |
| M1-SDD | Peer-review findings | partial | medium | owner-gated | Prehooks present + write net; SDD .docx "no prehook" claim unreconciled |
| M2-DEADCODE | Peer-review findings | pass | low | already-fixed | DerivedPricingNewBusiness removed from active V14; dead `MDT` literal residue only |
| M5-PBEDP | Peer-review findings | **fail** | **high** | uat-fixable | RRM subject 1603/1703 still uncovered; +25 FIM backfill resolvable |
| M7-COVERAGE | Peer-review findings | **fail** | medium | uat-fixable | 10/12 ≥75% SOLO; COLAUpliftPrehook 0%, COLAUpliftHandler 39% (test won't compile) |
| TEST-SUITE | Quality | **fail** | **high** | uat-fixable | 11/12 green; COLAUpliftTest compile break (buildOverrideMap signature drift) |
| SDD-CONFORMANCE | Quality | partial | low | uat-fixable | Single-year + derived formula conform; "no prehook" + Asset.Price base diverge |

---

## Fixability breakdown

### ALREADY-FIXED (verified live this session — no further action)
- **NB-DERIVED-FORMULA** — M-2 dead `Base_Price__c × tier` formula removed from active V14; one live SDD-canonical formula.
- **SLP-CARRY (M-4)** — `QuoteToOrderFieldMapper` SLP-carry active; 23/23 OI match across 6 distinct prices; 9/9 test.
- **B3-PARTNER (B-3)** — bulk product-type map-miss → maintenance margin fallback fixed; 28/28 test; 61,321 lines rescued from the 15% Software default.
- **B4-NULLGUARD (B-4)** — all 4 renewal operands ISNULL-guarded in V14 only; live all-null reprice yields clean 0, no error; 50/50 test.
- **M2-DEADCODE (M-2)** — dead-code formula element removed from active V14 (diff-confirmed). Residual: harmless always-false `MDT` literal in a live filter branch (cosmetic).

### UAT-FIXABLE (fixable + validatable in UAT now; no prod org, no owner design decision strictly required)
- **PBEDP-COVERAGE / ZERO-LIST-PBE / M5-PBEDP (SC-3372)** — data-only REST PBEDP backfill (the 25-FIM pattern is proven). *Caveat:* ~163 non-FIM in-use rows need an owner contributor crosswalk; 4 zero-list contributors need a list-price fix first — those sub-items are owner-input-gated.
- **MDT-RECORDS** — add/retire `platinum` Maintenance_Rate row or remove the orphan picklist value (the *policy* for what `platinum` maps to is owner-gated — see NB-DERIVED-TIER).
- **DATA-FIELD-POP** — GAP2 (NB SLP stamping), GAP3 (`QuoteToOrderFieldMapper` add SLP + COLA% to renewal OI path), GAP1 (legacy stamp re-run/backfill). No owner decision required.
- **FIELD-PACKAGING / M-3 / M-6 / B-2** — retrieve live fields into `force-app` and add to deploy manifest (the `Org Data/_src` copies prove recoverability). Fix lives in UAT/repo; symptom is prod-promotion.
- **M7-COVERAGE / TEST-SUITE** — re-sync `COLAUpliftTest` L1813-1814 to `getContractOverrides(Set<Id>)` (or re-add a `@TestVisible buildOverrideMap` seam). Restores compile → both classes back above 75%.
- **SDD-CONFORMANCE** — SDD-update (doc) or re-scope prehook; low severity.

### OWNER-GATED (UAT-fixable in place, but requires a business/design sign-off before any change)
- **NB-DERIVED-TIER (high)** — complete the inline IF for all 7 tiers OR data-drive from `Maintenance_Rate__mdt`; needs tier-policy + `platinum`/`Express` decision; rides a V14 republish behind the FIM-462 regression gate. *No existing ticket captures the incomplete-tier-set specifically — recommend a new ticket bundled with V15.*
- **RN-COLA-COMMIT / RN-PARTNER-DD / MAINT-ONLY / MULTI-ASSET (SC-3404)** — either (a) ensure every renewal-maint line carries a `Renew` QuoteAction (lower-risk; already makes 00781084 commit 67.38), or (b) make the derived renewal line a writable priced node / native PBEDP-for-renewal config (FIM-462-gated, ~513K-line blast, no rollback net — ESV delete platform-blocked). Open design question: whether any partner factor should re-apply at all (the COLA base already nets the prior $8.52).
- **RN-COLA-RATES (SC-3350 D1)** — migrate to Solution-Name-keyed store (or add per-solution override rows + re-key Apex from `Solution_Category__c` to `Solution__c`). Fields/data exist; needs grain-model sign-off.
- **DECOMP-SPLIT** — doc/SDD reconciliation only (math is correct, FK-absence is by design).
- **B5-DECISIONTABLE** — re-key HBASE hash to higher-cardinality key (e.g. `Asset.Id`); UI-only deploy; 3 dependent discovery procs → change-managed window. *Off the build path.*
- **M1-SDD** — one-paragraph .docx edit + "Apex components in the pricing path" subsection (doc owner).

### OUT-OF-SCOPE
- **RN-MULTIYEAR** — multi-year/out-year/MyCAP COLA is inert at the commit layer (0 procedure refs; out-year drives only a Deal-Desk approval flag). Both SDDs scope renewal as single-year. Not a defect; if business later wants multi-year it is a NEW feature build.

---

## PROD-ONLY items — cannot be fixed/validated in UAT (drives the cutover memo)

The build is **UAT-only and absent from `force-app`/prod**. The following are genuinely prod-blocked or prod-validation-blocked and must be carried in the cutover plan:

| Item | Source scenario | Prod-only reason |
|---|---|---|
| **M-6: stale prod prehook + missing context** | M1-SDD (`prod_only_reason`), FIELD-PACKAGING | Prod's `COLAUpliftPrehook` is the **stale Marc lineage (39,956 chars)** vs UAT's Nir lineage (43,272), and **prod lacks `SalesTransactionContextExt_v2`**. A prod cutover that omits the live hook stack cannot be validated in UAT — renewal/partner maintenance would price $0 in prod. |
| **M-3 / B-2: entire build absent from force-app/prod** | PROC-V14 (`prod_only_reason`), FIELD-PACKAGING | The V14 procedure, the Apex hook stack, and load-bearing fields are not in version-controlled deployable source. The *fix action* (repackage) lives in UAT, but **end-state validation that prod prices correctly is prod-only.** |
| **Field-presence in prod** | FIELD-PACKAGING | All OrderItem-side SC-3346 fields, both Order-side gate fields (`Quote_Type__c`, `QuoteTypeText__c`), and 5 QLI fields exist live in UAT but **not in any `package.xml`**; a standard pipeline would deploy procedure/Apex referencing fields that do not exist in prod → deploy failure. Remediation is UAT/repo; the **risk only manifests in prod.** |

> **Note:** NB-DERIVED-TIER, SC-3404, PBEDP, COLA-rates grain, and the test/packaging fixes are all reproducible and fixable **in UAT** — they are **not** prod-only. The prod-only set is narrowly the cutover/packaging/parity items above.

---

## Domain detail — expected vs actual + evidence

### REGRESSIONS vs KNOWN

- **REGRESSION (new this session):** TEST-SUITE / M7-COVERAGE — `COLAUpliftTest` compile break introduced by the 2026-06-14T04:20Z prehook refactor (`buildOverrideMap`→`getContractOverrides`). `COLAUpliftPrehook` 0%, `COLAUpliftHandler` 39%. Freshly-introduced suite-green regression; not present before this session.
- **KNOWN-OPEN (unchanged verdict):** NB-DERIVED-TIER (byte-identical formula), RN-COLA-COMMIT/RN-PARTNER-DD/MAINT-ONLY/MULTI-ASSET (SC-3404 cluster), PBEDP/ZERO-LIST/M5 (SC-3372), B5-DECISIONTABLE.
- **KNOWN-IMPROVED:** NB-DERIVED-FORMULA, M2-DEADCODE (dead-code removed); RN-MULTIYEAR (reclassified out-of-scope); RN-COLA-RATES/MDT-RECORDS (BoKS duplicate resolved, severity drop).

---

#### Auto-add (CFG-AUTOADD) — pass/none
**Expected:** Adding a Perpetual license to a New quote auto-adds the matching first-year (New) maintenance SKU via an Active ProductConfigurationRule, gated to `QuoteTypeText__c='New'`.
**Actual:** PASS. Implemented as a ProductConfigurationRule (`14OWC0000022ULp2AM`, RuleType=Configurator, ProcessScope=Transaction), NOT a bundle (0 `ProductRelatedComponent` rows under `01tWC00000DD1btYAD`). Criteria `ItemProductCode='PIA-PIA-NRPS-PIAP'` AND `QuoteTypeText__c='New'` → AutoAdd `01tWC00000DD1bsYAD` (PIA-PIA-RNM-PIAMBK). Fires live: 9 Draft New quotes carry both lines with exact same-second CreatedDate (configurator signature), most recent 2026-06-11. Companion Year-2 rule `14OWC0000022Eyb2AE` gated to `Renewal` → different SKU; mutually exclusive, no double-add. 99 "Year 1 Maintenance Sku added…" rules, ALL Active. No false negatives (4 license-only Drafts explained: 2 Renewal gate-suppressed, 1 QuoteType=None, 1 pre-rule artifact). **Out of scope:** downstream pricing of the auto-added line (NB-DERIVED-TIER $0; SC-3404 renewal commit).
**Artifacts:** `…/work/cfg-autoadd/` (esv.json, pcr.json, piam_rule.json, pairs.json).

#### Derived NB net value (NB-DERIVED-NET) — pass/none
**Expected:** NB derived `NetUnitPrice` = tier × `Source_List_Price__c`; Standard 0.20×355=71.
**Actual:** PASS on Draft 00781057. All 9 active New-Maint lines commit 71 with SLP=355, ListPrice=0, MTD='Standard'. Reproducible: identical before/after a Force reprice (Skip, isSuccess:true, line count 32→32, LMD advanced 2026-06-14T04:51:44Z). Contributing license lines price at catalog 355. Live formula (snapshot L42894) confirms 3-tier limit (NB-DERIVED-TIER boundary).
**Artifacts:** `…/work/nb-derived-net/body.json`.

#### Which NB formula (NB-DERIVED-FORMULA) — pass/none/already-fixed (**IMPROVED**)
**Expected:** One live formula = tier × `Source_List_Price__c`; competing `DerivedPricingNewBusiness` (Base_Price × tier, dead `MDT` gate) removed.
**Actual:** PASS (improved from partial). Empirical proof on line `0QLWC000003cL1i4AE` (Premier 0.30, Source=10000, **Base=0**, Net=**3000**) — a Base_Price formula would yield $0, falsifying it. M-2 dead-code now **removed from active V14** (0 occurrences in block 69795-75346; prior snapshot had it at L71820; block shrank 5616→5551). Live reprice (Draft 00780977) isSuccess:true, 3000 re-committed.
**Artifacts:** `…/work/nb-derived-formula/` (body.json, retrieve/).

#### Tier lookup (NB-DERIVED-TIER) — **fail/high/owner-gated** (KNOWN, unchanged)
**Expected:** Tier rate resolved for ALL 7 tiers; no value falls to $0.
**Actual:** DEFECT PERSISTS. Rates are **hard-coded inline** in V14 `DerivedPricingFormula` (L71642): `IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,0)))*Source_List_Price__c`. `Maintenance_Rate__mdt` referenced **0×** (the 7-row table is decorative). Else=0 → Basic/Premium/Express/Expert/`platinum` derive $0. Positive control: Standard lines = 71 (re-confirmed post-reprice, 32→32, LMD 2026-06-14T05:00:23). Negative case: Basic lines (`0QLWC000002QdKj4AK`, `0QLWC000002Qxo54AC`) = **0**. Live tally (50k-row CSV+Python sample): 207 unhandled (Basic 182, platinum 15, Expert 8, Premium 2). *Methodology note: `QuoteLineItemAttribute.AttributeValue` is not SOQL-equality-filterable; tallies via CSV export.*
**Artifacts:** `…/work/nb-derived-tier/` (retrieve/, body.json, mtd_full.csv, minority_ids.json).

#### Renewal COLA math (RN-COLA-MATH) — pass/none
**Expected:** In-flight COLA net = (Base−priorP−priorD)×(1+COLA%/100); 67.38 / 60.64.
**Actual:** PASS. 4/4 canary lines match stamped `COLACalculatedPrice__c` exactly. Live Force reprice (Draft 00781109) isSuccess:true, 1→1, LMD 04:51:12→04:52:39. FINEST log `07LWC00000Oy7Oz2AJ` decomposes: preColaNet=62.48 (=71−8.52−0) → colaNet=67.38 (=62.48×1.0785). COLA% 7.85 = `COLA_Uplift_Rules__mdt` Powertech_IAM_BoKS. **The downstream commit (60.64/$0) is SC-3404, out of scope here.**
**Artifacts:** `…/work/rn-cola-math/` (body.json, log_07LWC00000Oy7Oz2AJ.txt).

#### Renewal COLA commit (RN-COLA-COMMIT) — **fail/high/owner-gated** (KNOWN — **partially improved**, severity critical→high)
**Expected:** Committed `NetUnitPrice` = COLACalc on every renewal-maint line regardless of QuoteAction.
**Actual:** PARTIALLY IMPROVED, STILL FAILS on canary. Post-reprice: canary 00781109 `UnitPrice=67.38` (improved 0→67.38) but **`NetUnitPrice=60.64`=67.38×0.90** (wrong). Differentiator: only `0QLWC000003dEW24AM` (00781084) — the sole line carrying `QuoteActionId=7ocWC00000u7yf8YAA` (Type='Renew') — commits correct 67.38. The 3 QuoteAction=null lines commit 0 / 54.58 / 60.64. FINEST `07LWC00000Oy7FJ2AZ`: prehook computes 67.38; "Found 0 renewal QLIs from 1 total"; procedureNet=60.64; posthook now actively emits override but write is a **silent no-op** on the IsDerived/ListPrice-0 node. Subtotal/NetTotalPrice/TotalLineAmount roll up the wrong 60.64.
**Artifacts:** `…/work/rn-cola-commit/` (body.json, body84.json, canary_real_log.txt).

#### Partner double-discount (RN-PARTNER-DD) — **fail/high/owner-gated** (KNOWN — **mechanism corrected**)
**Expected:** No additional partner factor (prior partner already embedded once via `Prior_Partner_Discount__c=8.52`).
**Actual:** STILL OPEN; mechanism re-characterized. 3 of 4 lines diverge (60.64 / 54.58 / $0); only `0QLWC000003dEW24AM` (Renew QuoteAction) commits 67.38. **MECHANISM CORRECTION:** the prior "posthook re-stamps PartnerDiscountPercent → engine re-applies ×0.90" narrative is **REFUTED**. FINEST `07LWC00000OxswE2AR`: `NetUnitPrice={…=60.64}` appears in the **earliest pre-hook snapshot (L1423)** and never changes; count of `=67.38` snapshots = 0. The 60.64 is a **frozen historical fossil** on the derived/zero-list node, not an actively recomputed factor. Node signature: `ItemIsDerived__std=true`, `DerivedPricingAttribute=true`, `ListPrice=0.0`.
**Artifacts:** `…/work/rn-partner-dd/` (body109.json, body84.json, log109.txt, PartnerNetPricePosthook.live.cls).

#### COLA rates (RN-COLA-RATES) — partial/medium/owner-gated (**data-clean improved**)
**Expected:** Category rates exact; two **solution-grain** exceptions (MessengerConsole 12.00, SecureCare 4.70) override category default.
**Actual:** PARTIAL. 21/21 category rates exact (BoKS duplicate **resolved** 22→21, single `Powertech_IAM_BoKS` row, SystemModstamp 2026-06-14); 0 null-category active RRM products. **Residual:** store + lookup still category-keyed (`Product2.Solution_Category__c`), so per-solution exceptions are structurally unrepresentable. MessengerConsole/Plus/PeekPlus (24 active, 'Systems Management') → 7.85 instead of **12.00** (under 4.15 pts); SecureCare (2 active, 'Cybersecurity') → 7.85 instead of **4.70** (over 3.15 pts). 0 override rows. Fix = SC-3350 D1.
**Artifacts:** `…/work/rn-cola-rates/live_rules.json`.

#### Multi-year (RN-MULTIYEAR) — out-of-scope/none (**RECLASSIFIED**)
**Expected:** Determine whether multi-year/out-year/MyCAP COMPUTES and COMMITS a distinct price.
**Actual:** INERT + OUT-OF-SCOPE. Live V14 procedure has 0 refs to outyear/mycap/final_year. Live `COLAUpliftPrehook` reads `COLA_Outyear_Uplift_Percent__c` only for a below-minimum approval check (L1064-1067) and enqueues `MyCAPFlagApplier` (sets `Quote.Mycap__c`, no reprice). **Data correction:** field populated on **15** QLIs (FIX-STATE said 0), but all 15 are Subscription/null non-maintenance lines whose committed price tracks the year-1 COLA. Prior "fail/SC-3404" canary `0QLWC000003e2Sn4AI` is `Renewal Maintenance` with out-year=null — i.e. the single-year RN-COLA-COMMIT defect mislabeled as multi-year.
**Artifacts:** `…/work/rn-multiyear/` (retrieve/, COLAUpliftPrehook.live.cls).

#### Decomposition split (DECOMP-SPLIT) — partial/medium/owner-gated (KNOWN)
**Expected:** Derived maintenance CHILD OrderItem linked to parent license via `Original_Order_Item__c`.
**Actual:** The FK-split model **does not exist** in SC-3346. 40 OIs carry `Original_Order_Item__c` — all 40 are same-product quantity-splits (PowerOrderSplittingService / SC-3210/SC-3368), 0 license→maintenance. 19,844 maintenance OIs, 0 with the FK. The build value-stamps a self-contained maintenance SKU (`MaintenanceOrderDecompositionService` v62, FK referenced 0×; `maintenanceBase=sourceBase×tierRate` L869 → `Base_Price__c` L312). B-6 holds (16 OIs, 0 license-base leaks). SOLO test now self-ran: 40/40 Pass, 84% coverage. Feature works via a different mechanism → doc reconciliation.
**Artifacts:** `…/work/decomp-split/` (fk_populated.json, maint_ois.json, MaintenanceOrderDecompositionService.live.cls).

#### B-6 base (DECOMP-BASE) — pass/none
**Expected:** Maintenance OI carries maintenance base, never raw license base (no Base==SLP).
**Actual:** PASS. 0 OIs with Base=355; 0 license-base leaks across 16 positive-Base OIs. Chains proven: PIAMBK OI `802WC00000OcIChYAN` (00095455) Base 71=355×0.20; Automate Ultimate `802WC00000OdgjEYAR` (00095467) Base 55000=275000×0.20. SOLO 40/40, coverage 79→84%. The one Renewal-Maint OI's wrong NetUnitPrice is SC-3404, not B-6.
**Artifacts:** `…/work/decomp-base/`.

#### Stamp flow (STAMP-FLOW) — pass/none
**Expected:** `Stamp_Maintenance_Pricing_Inputs` (V13) stamps Base/COLACalc/priors/COLA%/type before-save and re-fires on reprice.
**Actual:** PASS. Flows Active (V13 + Stamp_Source_List_Price V8). 4/4 COLACalc exact; re-fires on Force reprice (Draft 00781043, 1→1, LMD 2026-06-14T04:58:31Z). NB 00780964: Base=355 matches source `Pre_Partner_Price__c=355`. **Stamps the flow owns are all correct;** committed Net (0/60.64/54.58) is SC-3404. Adjacent flags: NB 00780964 SLP=null (ZERO-LIST-PBE), COLAUpliftTest/code drift (build-hygiene).
**Artifacts:** `…/work/stamp-flow/body.json`.

#### SLP carry-forward (SLP-CARRY / M-4) — pass/none/already-fixed (**IMPROVED**)
**Expected:** `QuoteToOrderFieldMapper` copies QLI.SLP → OI.SLP across all values.
**Actual:** PASS, strengthened. Live class `01pWC000002IuvRYAS` (LMD 2026-06-12T20:21:26Z, unchanged) has the mapping active. Data join: **23/23 match, 0 mismatch, 0 miss** (grew from 15), across **6 distinct prices** {33, 325, 355, 2008, 34750, 275000} — value-agnostic. SOLO 9/9, 77% coverage (gap = DML-lock fallback, not the SLP block). README's "commented out" claim reflects only the stale repo copy.
**Artifacts:** `…/work/slp-carry/` (QuoteToOrderFieldMapper.live.cls, slp_join.apex).

#### Maintenance-only renewal (MAINT-ONLY) — **fail/critical/owner-gated** (KNOWN — part-b improved)
**Expected:** (a) MissingContributor graceful, non-blocking; (b) commit correct COLA net 67.38.
**Actual:** (a) PASS — `ValidationResult=MissingContributor` (169×) but `CalculationStatus=CompletedWithPricing`, reprice isSuccess:true. (b) STILL FAIL — canary 00781109 UnitPrice improved 0→67.38, posthook active, but `NetUnitPrice=60.64`=67.38×0.90; **Quote GrandTotal=60.64 vs expected 67.38**. FINEST `07LWC00000Oy7f72AB` L6980: "PERCENT ONLY: … PartnerDiscountPercent 10.00%". Secondary inconsistency: applied factor 0.90 (10%) though log shows Partner%=12.00 stamped. **Critical** because wrong GrandTotal commits on a live maint-only renewal path.
**Artifacts:** `…/work/maint-only/` (reprice.log, body.json).

#### Multi-asset renewal (MULTI-ASSET) — **fail/high/owner-gated** (KNOWN, unchanged)
**Expected:** Both legs commit correct net; GrandTotal 4502.99.
**Actual:** Split outcome. License leg correct: beSECURE `NetUnitPrice=4442.35`=5417.50×0.82. Maint leg wrong: `NetUnitPrice=54.58`=60.64×0.90, UnitPrice=0; COLACalc=60.64 correct. GrandTotal=4496.93=4442.35+54.58 (wrong maint net into header). Post-reprice LMD advanced 2026-06-14T04:59:52 (active re-commit). SC-3404 in multi-asset context.
**Artifacts:** `…/work/multi-asset/body.json`.

#### PBEDP coverage (PBEDP-COVERAGE) — **fail/high/uat-fixable** (KNOWN — **improved**)
**Expected:** Every IsDerived zero-list maintenance PBE has a PBEDP row pointing to a priced contributor.
**Actual:** 201 PBEDP rows (was 176), 199 distinct covered (was 174), **3254/3453 uncovered = 94.2%** (was 95.0%). All 3453 derived PBEs zero-list + active. 25 backfill rows (`SC3372BACKFILL`) all FIM-family, uniform (UnitPrice/Product/Both), all 14 contributors priced → SC-3372 gate satisfied for FIM cohort. Regression-gate FIM-FIM-RNM-CCMLSE still carries a **duplicate uncovered** active zero-list PBE `01uWC000005q7HbYAI`. No Draft QLIs on backfilled FIM NewMaint products → config-level proof only; backfilled RRM products route through SC-3404.
**Artifacts:** `…/work/pbedp-coverage/`.

#### Zero-list PBE → $0 (ZERO-LIST-PBE) — **fail/high/uat-fixable** (KNOWN — improved coverage)
**Expected:** Zero-list PBE must NOT yield $0; canonical 00780964 → 71.
**Actual:** STILL FAILS. Canonical BoKS repro 00780964 line `0QLWC000003cFh44AE` commits `NetUnitPrice=0`, `Source_List_Price__c=NULL`, Base=355 (persists post-reprice, lines 2→2, LMD 2026-06-14T05:01:42). Maint PBE `01uWC000004dT3QYAU` (BoKS) not in FIM backfill, 0 PBEDP rows. Dominant root cause = **null Source_List_Price__c** starving the formula (12 of 14 zero-net Draft NB lines), a Stamp_Source_List_Price coverage gap **not** addressed by PBEDP backfill. Inconsistency control: same product prices 71 elsewhere → the $0-list PBE itself does not block pricing.
**Artifacts:** `…/work/zero-list-pbe/` (body.json, body_broQ.json, RETEST_NOTES.md).

#### CMDT records (MDT-RECORDS) — partial/low/uat-fixable (**severity medium→low**)
**Expected:** Maint_Rate (7), COLA_Uplift_Rules (per-category), MTD gate present, correct, no dead/dup.
**Actual:** Core data correct + consumed. Maint_Rate 7/7 exact (stable since 2026-04-17). COLA 21 rows, all Active, all match D4. **DEFECT-B resolved** (TEMP_/duplicate BoKS consolidated this session). **DEFECT-A persists (inert):** MTD picklist value `platinum` (lowercase) has no Maintenance_Rate row → formula else=0 → silent $0 if ever configured; **0 live usage**. Live consumption proven on canary `0QLWC000003dEW24AM` (COLA% 7.85, Base 71=355×0.20, COLACalc 67.38).
**Artifacts:** `…/work/mdt-records/`.

#### V14 active + elements (PROC-V14) — pass/none
**Expected:** V14 sole-active; all SC-3346 elements present/correct; runs clean.
**Actual:** PASS. V14 sole-active (fresh v67 retrieve, status Active L69796-75347). All elements present byte-exact: DerivedPricingFormula (tier×SLP), DerivedPricingRenewals (ISNULL-guarded all 4 operands — B-4), DerivedPricingNetUnitPriceValueReset + COLAUpliftonRenewalNet (new-in-V14), native DerivedProductsRenewals (resultIncluded=true, MTD-gated), full partner chain. Live reprice (Draft 00781053) isSuccess:true, 2→2, no gack/ScaleCache desync; COLACalc 60.64 exact. SOLO `QuoteRenewalTypeHandlerTest` 5/5, 100%. Open defects in/around V14 (SC-3404, NB-DERIVED-TIER, M-2 `MDT` residue) are out of scope for this scenario.
**Artifacts:** `…/work/proc-v14/` (v14_live_20260614.xml, body.json, retr/).

#### Field population (DATA-FIELD-POP) — partial/medium/uat-fixable (**first execution**)
**Expected:** Carry-forward fields populate, re-fire on reprice, copy to OI at Q2O.
**Actual:** Build-cohort CORRECT (6/6 renewal COLACalc exact; 9 NB lines Base=355/SLP=355→71; re-fires on reprice, LMD 2026-06-14T05:07:33Z). **3 gaps:** GAP1 — 44 of 50 renewal-maint QLIs on legacy migrated quotes (created 2018/2024) have Base/SLP/priors all NULL → COLACalc=0 (B-4 guard masks with $0). GAP2 — NB line `0QLWC000003cFh44AE` SLP=NULL (license-base leak, 2 lines systemic). GAP3 — renewal OI `802WC00000OgsuEYAR` (00095475) missing SLP + COLA% on carry-forward (0/13695 renewal OIs carry either).
**Artifacts:** `…/work/data-field-pop/` (body.json, body_nb.json).

#### Field packaging (FIELD-PACKAGING) — partial/medium/uat-fixable (**net-new**)
**Expected:** Fields + picklists exist live; force-app carries every field-meta for prod promotion.
**Actual:** SPLIT. (1) Live UAT = PASS: all fields exist with section-2.4 types (FieldDefinition + describe); picklists active (`New/Renewal Maintenance`, `Renewal`). (2) force-app/prod = FAIL: QLI missing 5 fields (Source_List_Price__c, Prior_Partner/Discretionary_Discount__c, COLA_Outyear, Final_Year_COLA), ALL 7 OrderItem-side fields, BOTH Order-side fields absent; **0 package.xml staging**. Present in `Org Data/_src` (recoverable). Data correction: `COLA_Outyear_Uplift_Percent__c` populated on 15 (not 0).
**Artifacts:** `…/work/field-packaging/`.

#### B-3 partner overload (B3-PARTNER) — pass/none/already-fixed (**first execution**)
**Expected:** Null line-level type resolves to maintenance margin (12/10), not 15% Software.
**Actual:** PASS. Live `PartnerPricingService` (`01pWC000001wAzPYAU`, Nir 2026-06-12): `loadProductTypesForLines` Product2 fallback + 3-arg `resolveProductType` delegates map-miss to single-arg lookup (not Software default). Precondition real: **61,312** maintenance QLIs with null line-level type + 9 mis-set Software — all rescued. SOLO 28/28, 81%, with dedicated B-3 assertions. Default model gap confirmed (Software 15 / NewMaint 12 / RenewMaint 10).
**Artifacts:** `…/work/b3-partner/` (PartnerPricingService.live.cls, PartnerNetPricePosthook.live.cls, PartnerPricingServiceTest.live.cls).

#### B-4 null-guard (B4-NULLGUARD) — pass/none/already-fixed
**Expected:** All 4 renewal operands ISNULL-guarded in V14; clean number on null.
**Actual:** PASS, strengthened. Guard exclusive to active V14 (5 inactive V9-V13 blocks unguarded). Function = ISNULL (BLANKVALUE/NULLVALUE/ISBLANK=0). **Live all-null reprice** (Draft `0Q0WC000002A7Wv0AK`, 5 lines) isSuccess:true → COLACalc=0 clean, no error. Carry-forward arm: 67.38 exact. SOLO 50/50, 92%. SC-3404 $0/commit caveat is separate.
**Artifacts:** `…/work/b4-nullguard/` (retrieve/, body_allnull.json, body_canary.json).

#### B-5 decision table (B5-DECISIONTABLE) — **fail/medium/owner-gated** (**first execution**)
**Expected:** `Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`) RefreshStatus=Complete; build path independent of it.
**Actual:** FAIL. RefreshStatus=**Failed** (touched 2026-06-12T20:52:58Z but did not clear; metadata byte-identical to prior). AssetActionSource = 430,335 rows; HBASE hash key = AccountId+Product2Id; pairs with >200 history rows overflow the 200-row group limit. **Off the build path:** active V14 procedure has **0 refs**; `Salesforce_Default_Pricing_Discovery_Procedure_v2` references it 3× (`IsRealTime=false`). Build renewals price without it. Genuine >12-month failed native-discovery index.
**Artifacts:** `…/work/b5-decisiontable/` (live_retrieve/, rev_active.json, discovery_procs.json).

#### M-1 prehooks (M1-SDD) — partial/medium/owner-gated (**net-new**)
**Expected:** Reconcile SDD "no custom Apex pricing prehook" with as-built; hooks present + write net; manifest from live org.
**Actual:** Present + writing net CONFIRMED. Both `COLAUpliftPrehook` (43,272 chars, Nir lineage) + `PartnerNetPricePosthook` `implements RevSignaling.SignalingApexProcessor`, both edited 2026-06-14. FINEST `07LWC00000Oy8Uj2AJ`: prehook computes/stamps COLACalc 67.38; posthook does NOT short-circuit, builds full price-field update set =67.38, submits `updateContextAttributes` (linesUpdated=1) — **no ×0.90 in code now**. PARTIAL because (a) SDD .docx still falsely says "no custom Apex pricing prehook" (owner edit prepared in `08_M1_SDD_RECONCILIATION.md`, not applied → M-6 manifest trap), and (b) the correct write is a silent no-op on the excluded node (committed stays 60.64 — that's SC-3404, not M1-SDD).
**Artifacts:** `…/work/m1-sdd/` (COLAUpliftPrehook.live.cls, PartnerNetPricePosthook.live.cls, log_07LWC00000Oy8Uj2AJ.txt).

#### M-2 dead-code (M2-DEADCODE) — pass/low/already-fixed (**IMPROVED**)
**Expected:** Exactly one live NB formula; `DerivedPricingNewBusiness` removed.
**Actual:** RESOLVED. Active V14 block: 0 `DerivedPricingNewBusiness`, 0 `Base_Price__c * IF` formulas; 5 remaining occurrences confined to inactive V8-V13. Diff-confirmed vs 2026-06-13 snapshot (had it at block-local L1978). Residual (severity=low): misspelled `MDT` literal survives as an always-false OR-branch in the live filter (`MDT`=0 AttributeDefinitions); live branches (4∧5)/(6∧7∧8) correctly admit renewal-maint lines. Reprice clean; NB net 71 materializes.
**Artifacts:** `…/work/m2-deadcode/` (v14_active.xml, retr/, body.json).

#### M-5 PBEDP RRM (M5-PBEDP) — **fail/high/uat-fixable** (KNOWN — improved)
**Expected:** RRM derived PBEs covered by PBEDP.
**Actual:** 201/199/3254 (94.2% gap). +25 FIM backfill (Liam 2026-06-14T02:44Z) — resolvable chains verified (e.g. FIM-FIM-RRM-CCMSCA←FIM-FIM-NRPS-CCMSEP). RRM subject overwhelmingly open: 1603 of 1703 RRM PBEs uncovered (94.1%); only ~11 of 25 backfill rows were RRM. Remainder spans all families (SM 720, DM 449, FIM 331…). Clean (no dup-key rows). End-to-end RRM proof blocked by SC-3404; backfill proven structurally.
**Artifacts:** `…/work/m5-pbedp/` (SUMMARY.txt, backfilled_p2.json, uncovered_full.json).

#### M-7 coverage (M7-COVERAGE) — **fail/medium/uat-fixable** (**first execution; new regression**)
**Expected:** All 12 build classes ≥75% SOLO.
**Actual:** 10/12 PASS (QuoteRenewalTypeHandler 100, RenewalQuoteHeaderHandler 100, RenewalAssetQuantityHandler 98, RenewalQuoteLineHandler 93, RenewalMaintenancePricingService 92, OrderRepriceInvocable 91, MaintenanceOrderDecompositionService 84, PartnerPricingService 83, PartnerNetPricePosthook 77, QuoteToOrderFieldMapper 77). **FAIL:** COLAUpliftPrehook 0%, COLAUpliftHandler 39% — `COLAUpliftTest` won't compile (L1813: `buildOverrideMap(List<SObject>)` removed by 2026-06-14T04:20 refactor → `getContractOverrides(Set<Id>)`; test not re-synced). Cached aggregate badly under-reports — SOLO is required.
**Artifacts:** `…/work/m7-coverage/SOLO_COVERAGE_2026-06-14.md`.

#### Test suite green (TEST-SUITE) — **fail/high/uat-fixable** (**net-new; regression**)
**Expected:** All 12 build test classes compile + pass green ≥75%; RunSpecifiedTests-deployable.
**Actual:** Does NOT run green. 11/12 pass green SOLO (100% class coverage each); **COLAUpliftTest fails to compile** (same `buildOverrideMap` signature drift) → covers nothing → COLAUpliftPrehook 0.0% (0/575), COLAUpliftHandler 38.8% (71/183) below gate. A RunSpecifiedTests deploy including the test fails on compile; excluding it leaves the central prehook at 0%. `PartnerNetPricePosthookTest` (previously admin-locked) now ran 47/47.
**Artifacts:** `…/work/test-suite/` (COLAUpliftTest.json, COLAUpliftPrehook.live.cls, COLAUpliftTest.live.cls).

#### SDD conformance (SDD-CONFORMANCE) — partial/low/uat-fixable (**net-new; improved**)
**Expected:** Conform to both SDDs — single-year scope + derived tier×SLP formula.
**Actual:** Conforms on structural pillars. Single-year: 0 outyear/final_year/mycap in active V14; multi-year inert (15/1,223,409 QLIs). Derived formula: sole new-business formula = tier×SLP (M-2 competitor removed). Renewal carry-forward ISNULL-guarded. **Residual divergences (→partial/low):** (a) Maintenance SDD says "No custom Apex pricing prehook" yet build ships COLAUpliftPrehook + PartnerNetPricePosthook; (b) COLA SDD's literal base is `Asset.Price` while build uses decomposed `(Base − priorP − priorD)`. Both are design evolutions, reconcilable via doc update. 4 minority-tier $0 cases are SDD-deferred (line 178 "re-tag the four straggler products").
**Artifacts:** `…/work/sdd-conformance/v14_fresh_retrieve.xml`.

---

## Critical findings (severity critical / high)

| # | Scenario | Severity | Finding | Fix lever |
|---|---|---|---|---|
| 1 | **MAINT-ONLY** | **critical** | Maint-only renewal cart commits wrong GrandTotal (60.64 vs 67.38) — wrong money on a live renewal path. MissingContributor handling itself is graceful. | Owner-gated: SC-3404 commit + remove `PartnerDiscountPercent` re-stamp (A1 design decision). |
| 2 | **RN-COLA-COMMIT** | high | Renewal-maint `NetUnitPrice` wrong unless line carries a `Renew` QuoteAction (60.64/$0/54.58). Posthook write no-ops on derived/zero-list node. | Owner-gated: (a) ensure Renew QuoteAction on every renewal-maint line, or (b) writable priced node / native PBEDP-for-renewal (FIM-462-gated). |
| 3 | **RN-PARTNER-DD** | high | Partner factor ×0.90 persists as a frozen fossil on QuoteAction=null nodes; engine-owned NetUnitPrice. | Owner-gated: same as #2; decide whether partner factor should re-apply at all. |
| 4 | **MULTI-ASSET** | high | License leg correct (4442.35); maint leg 54.58≠60.64; wrong maint net into header. | Owner-gated (SC-3404). |
| 5 | **NB-DERIVED-TIER** | high | Only 3 of 7 tiers handled; Basic/Premium/Express/Expert/platinum → $0 (207 live rows). | Owner-gated (tier policy) → procedure edit (new ticket / V15). |
| 6 | **PBEDP-COVERAGE / M5-PBEDP** | high | 94.2% of active derived PBEs lack PBEDP config (3254/3453). | UAT-fixable REST backfill (FIM pattern proven); ~163 non-FIM need owner crosswalk. |
| 7 | **ZERO-LIST-PBE** | high | Canonical BoKS NB repro commits $0 (null Source_List_Price). | UAT-fixable: Stamp_Source_List_Price coverage gap is the real lever. |
| 8 | **TEST-SUITE** | high | COLAUpliftTest compile break → COLAUpliftPrehook 0% → not RunSpecifiedTests-deployable. **NEW REGRESSION.** | UAT-fixable: re-sync test to `getContractOverrides(Set<Id>)`. |

---

## Recommendations / next actions (ordered)

1. **[P0 — UAT, no owner decision] Fix the test regression** (TEST-SUITE / M7-COVERAGE). Re-sync `COLAUpliftTest` L1813-1814 to the current `getContractOverrides(Set<Id>)` seam (or re-add a `@TestVisible buildOverrideMap`). Re-run SOLO to restore COLAUpliftPrehook/COLAUpliftHandler above 75%. **Unblocks any deploy.**
2. **[P0 — owner decision required] SC-3404 renewal-commit cluster** (RN-COLA-COMMIT, RN-PARTNER-DD, MAINT-ONLY, MULTI-ASSET). Decide between lever (a) guarantee a `Renew` QuoteAction on every renewal-maintenance line (lower-risk; already makes 00781084 commit 67.38) and lever (b) writable-priced-node / native PBEDP-for-renewal redesign. Also resolve the **partner-factor question** (should ×0.90 apply at all — the COLA base already nets the prior $8.52; **Accepted quote 00781068 also carries 60.64**, so the "working" value may itself be the double-count).
3. **[P1 — owner decision then UAT edit] NB-DERIVED-TIER.** Complete the inline IF for all 7 tiers (or data-drive from `Maintenance_Rate__mdt`) and decide `platinum`/`Express` policy. Open a **new ticket** (no existing ticket captures the incomplete-tier-set); bundle with V15 republish behind the FIM-462 gate.
4. **[P1 — UAT, owner crosswalk for remainder] PBEDP backfill** (PBEDP-COVERAGE / ZERO-LIST-PBE / M5-PBEDP). Continue the proven REST backfill pattern; obtain the business contributor crosswalk for ~163 non-FIM in-use rows; fix 4 zero-list contributor list prices; fix the duplicate uncovered Standard-PB PBE on CCMLSE. Separately, close the **Stamp_Source_List_Price coverage gap** (the real lever for the canonical $0 NB repro).
5. **[P1 — UAT/repo] Field packaging** (FIELD-PACKAGING / M-3/M-6/B-2). Retrieve the live fields into `force-app` and add to the deploy manifest; align the prod prehook lineage and `SalesTransactionContextExt_v2` in the cutover plan. **This is the prod-cutover gate.**
6. **[P2 — owner decision] COLA rates grain** (RN-COLA-RATES / SC-3350 D1). Migrate to Solution-Name-keyed store or add per-solution override rows + re-key the Apex lookup, to honor MessengerConsole=12.00 / SecureCare=4.70.
7. **[P2 — doc owner] SDD reconciliation** (M1-SDD, SDD-CONFORMANCE, DECOMP-SPLIT). Apply the prepared `.docx` edit (scope "no prehook" to the new-business path; add the Apex-components subsection; reconcile decomposition mechanism + `Asset.Price` base).
8. **[P3 — UAT, change-managed] B-5 decision-table** re-key (off the build path; does not gate SC-3346 acceptance but is a genuine >12-month failed index on the native discovery path).
9. **[P3 — UAT data] DATA-FIELD-POP gaps** — stamp NB SLP (GAP2), add SLP+COLA% to the renewal OI carry-forward in `QuoteToOrderFieldMapper` (GAP3), re-run/backfill the 44 legacy renewal lines (GAP1).

---

## Appendix

**A. Active procedure identifiers (re-verified live 2026-06-14)**
- ExpressionSet: `9QLWC0000015cDl4AI` (`Rev_Mgmt_Default_Pricing_Procedure`)
- ExpressionSetVersion (active): `9QMWC00000023eX4AQ`, `VersionNumber=14`, `IsActive=true` (sole active; V1–V13 inactive, V13 "(Deprecated)")
- Fresh ESD retrieve: api v67, active V140 block file lines 69795–75347

**B. Key formulas (active V14, byte-exact)**
- `DerivedPricingFormula` (NB net, block-local L1850 / file L71642): `IF(AttributeValue='Premier',0.30,IF('Standard',0.20,IF('Professional',0.20,0)))*Source_List_Price__c`
- `DerivedPricingRenewals` (file L71772): `IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (IF(ISNULL(Base_Price__c),0,Base_Price__c)-IF(ISNULL(Prior_Partner_Discount__c),0,Prior_Partner_Discount__c)-IF(ISNULL(Prior_Discretionary_Discount__c),0,Prior_Discretionary_Discount__c))*(1+(IF(ISNULL(COLA_Uplift_Percent__c),0,COLA_Uplift_Percent__c)/100))), NetUnitPrice)`

**C. Canary worked examples**
- New-business Standard tier: 0.20 × 355 = **71.00**
- Renewal COLA (no discretionary): (71 − 8.52 − 0) × 1.0785 = **67.38**
- Renewal COLA (discretionary 6.25): (71 − 8.52 − 6.25) × 1.0785 = **60.64**
- Partner double-discount fossil: 67.38 × 0.90 = **60.64**; 60.64 × 0.90 = **54.58**
- Multi-asset license leg: 5417.50 × 0.82 = **4442.35**

**D. FINEST logs cited**
- RN-COLA-MATH: `07LWC00000Oy7Oz2AJ` (preColaNet 62.48 → colaNet 67.38)
- RN-COLA-COMMIT: `07LWC00000Oy7FJ2AZ` ("Found 0 renewal QLIs"; procedureNet 60.64)
- RN-PARTNER-DD: `07LWC00000OxswE2AR` (no-op proof: 60.64 from L1423 pre-hook, never 67.38)
- MAINT-ONLY: `07LWC00000Oy7f72AB` ("PERCENT ONLY … PartnerDiscountPercent 10.00%")
- M1-SDD: `07LWC00000Oy8Uj2AJ` (posthook active write, linesUpdated=1)

**E. Key live data points**
- Derived PBEs: 3453 (100% zero-list, all active); PBEDP rows 201 / distinct covered 199 / uncovered 3254 (94.2%)
- B-3 precondition: 61,312 maintenance QLIs with null line-level type + 9 Software
- Maintenance_Rate__mdt: 7 rows (Basic 0.15 / Professional 0.20 / Standard 0.20 / Premium 0.24 / Express 0.30 / Premier 0.30 / Expert 0.35) — referenced 0× by the procedure
- COLA_Uplift_Rules__mdt: 21 rows (was 22), all active, 21/21 category rates exact; BoKS duplicate consolidated 2026-06-14
- AssetActionSource: 430,335 rows (B-5 HBASE overflow)

**F. Build-class SOLO coverage (M7-COVERAGE / TEST-SUITE, 2026-06-14)**

| Class | SOLO coverage | Tests | Gate (≥75%) |
|---|---|---|---|
| QuoteRenewalTypeHandler | 100% | 5/5 | PASS |
| RenewalQuoteHeaderHandler | 100% | 20/20 | PASS |
| RenewalAssetQuantityHandler | 98% | 24/24 | PASS |
| RenewalQuoteLineHandler | 93% | 8/8 | PASS |
| RenewalMaintenancePricingService | 92% | 50/50 | PASS |
| OrderRepriceInvocable | 91% | 10/10 | PASS |
| MaintenanceOrderDecompositionService | 84% | 40/40 | PASS |
| PartnerPricingService | 83% | 28/28 | PASS |
| PartnerNetPricePosthook | 77% | 47/47 | PASS |
| QuoteToOrderFieldMapper | 77% | 9/9 | PASS |
| **COLAUpliftHandler** | **39%** | n/a | **FAIL** |
| **COLAUpliftPrehook** | **0%** | 0 (compile break) | **FAIL** |

**G. Artifact index** — all under `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_rca/work/<scenario_id>/` (one directory per scenario; 30 directories confirmed present). Peer-review dossier and SDD reconciliation: `*Jira/Task/sc3403 | Peer Review - SC-3346 …/` (incl. `08_M1_SDD_RECONCILIATION.md`).