# SC-3346 MDT-RECORDS / DEFECT-A — Orphan `platinum` Maintenance Tier: Resolution Dossier

**Org:** FortraUAT (Revenue Cloud Advanced / RLM)
**Ticket:** SC-3346 (Maintenance Derived Pricing), peer-review SC-3403, parent of COLA SC-3350
**Scope:** MDT-RECORDS DEFECT-A — the maintenance tier-designation (MTD) picklist value `platinum` (lowercase) has no matching `Maintenance_Rate__mdt` row.
**Date:** 2026-06-14 (all evidence live-retrieved this session)
**Posture:** READ-ONLY synthesis. No DML / metadata deploy / reprice performed. All facts re-verified live before writing.

---

## 0. TL;DR

- **Definitive live state:** `platinum` is a real, selectable MTD picklist value (lowercase, the only lowercase of 8). It has **18 live quote usages + 5 live order usages**, ALL Renewal Maintenance / Approved-or-Activated, ALL correctly priced via COLA carry-forward. The active **V14** derived formula handles **exactly 3 tiers** (Premier 0.30 / Standard 0.20 / Professional 0.20, else `0`) and **never references `platinum`** — nor any CMDT.
- **Mispricing today: NO.** Zero live platinum line touches the tier formula; all carry real non-zero prices ($208.04–$2,468.80). The $0 trap is **latent**, not active.
- **Owner-gated: YES** for the full fix (the platinum RATE / intent is a business call). **Executable now: a narrow, safe structural action exists** — deactivate the orphan picklist value to stop *future* selection — but it does not by itself close the formula gap and touches the platinum-default PAD, so I recommend pairing it with the owner decision rather than firing it blind. See §6–§8.
- **Both retest claims were wrong; the prior memory was right.** Retest "0 live usage" = false; retest "platinum 15" = a 50,000-row export truncation (real universe 102,122). Memory `project_nb_derived_tier_fix` "3→7 tiers completed, 1,031 lines un-$0'd" = **NOT live** (that 7-tier formula exists only as an un-deployed local candidate in `retrieve_tier/`).

---

## 1. Confirmed live CMDT rows — `Maintenance_Rate__mdt` (7 rows)

`sf data query -o FortraUAT`, re-run this session:

| MaintenanceType__c | Rate__c |
|---|---|
| Basic | 0.15 |
| Expert | 0.35 |
| Express | 0.30 |
| Premier | 0.30 |
| Premium | 0.24 |
| Professional | 0.20 |
| Standard | 0.20 |

There is **no `platinum` row** (no exact-case, no case-variant `Platinum`).

---

## 2. Picklist value set vs rate rows — orphan analysis

**MTD attribute:** `AttributeDefinition` `0tjWC000000096bYAA` (DeveloperName `Maintenance_Type_Defn`, Code `MTD`, DataType `Picklist`, IsActive true). It is the **only** AttributeDefinition bound to `AttributePicklist 0v5WC00000005RBYAY` ("Maintenance Type", Active, **unrestricted Text-backed**).

**Picklist values (live, `AttributePicklistValue WHERE PicklistId='0v5WC00000005RBYAY' ORDER BY Sequence`):**

| Seq | Value | Code | Picklist Value Id | Has rate row? | Notes |
|---|---|---|---|---|---|
| 1 | Basic | APV_1557 | 0v6WC0000000A5QYAU | yes (0.15) | unhandled by V14 formula |
| 2 | Expert | APV_1558 | 0v6WC0000000A5RYAU | yes (0.35) | unhandled by V14 formula |
| 3 | **platinum** | **APV_1559** | **0v6WC0000000A5SYAU** | **NO (orphan)** | **ONLY lowercase value** |
| 4 | Premier | APV_1560 | 0v6WC0000000A5TYAU | yes (0.30) | handled by V14 |
| 5 | Premium | APV_1561 | 0v6WC0000000A5UYAU | yes (0.24) | unhandled by V14 formula |
| 6 | Professional | APV_1562 | 0v6WC0000000A5VYAU | yes (0.20) | handled by V14 |
| 7 | Standard | APV_1563 | 0v6WC0000000A5WYAU | yes (0.20) | handled by V14 |
| 8 | Express | EX | 0v6WC0000000Dy9YAE | yes (0.30) | unhandled by V14 formula |

**Orphan analysis:**
- `platinum` is the **ONE and ONLY** picklist value with no matching rate row.
- It is **NOT a case-only mismatch** — no `Platinum` rate row of any casing exists.
- It is **NOT a typo / near-edit of an existing tier** (no edit-distance-1 match to Premier/Premium/Professional/etc.).
- The single anomaly is **casing**: `platinum` is the sole lowercase value among 7 TitleCase values → consistent with a one-off bad import / hand-entry (migration residue), NOT a deliberately-designed tier name with matching infrastructure.

**Decoupling caveat (load-bearing):** the V14 formula hard-codes rates inline and reads `Maintenance_Rate__mdt` **0 times** (grep over the whole 75,347-line definition: `Maintenance_Rate=0`, `MaintenanceType=0`). The "CMDT lacks a platinum row" framing is therefore a **symptom of an incomplete picklist↔tier design, not the live pricing mechanism.** The live pricing lever is the formula's hard-coded branch list, not the CMDT.

---

## 3. K1 RESOLVED — exact live `platinum` usage + breakdown

**Methodology note:** `AttributeValue` is NOT SOQL-equality-filterable (`WHERE AttributeValue='platinum'` returns 0). Mandatory method = full Bulk-API export + python tally. Three independent fresh exports (incl. the freshest `mtd_refresh_0938.csv` @ 09:38) all agree.

**Full MTD `QuoteLineItemAttribute` distribution (102,122 rows, `AttributeDefinitionId='0tjWC000000096bYAA'`):**

| AttributeValue | Count |
|---|---|
| Premier | 42,604 |
| Professional | 41,881 |
| Standard | 16,588 |
| Premium | 833 |
| Basic | 185 |
| **platinum** | **18** |
| Expert | 13 |
| Express | 0 (live) |

**Quote-side breakdown (all 18, from `platinum_qli_detail.csv`):**
- **Product:** GS-GSE-RRM-EFWO ×13, GS-GSE-RRM-EFSMB ×5.
- **Line type:** 18/18 `Fortra_Product_Type__c = 'Renewal Maintenance'` (0 New).
- **Quote status:** 18/18 `Approved` (0 Draft).
- **Pricing:** `ListPrice=0` (IsDerived PBE), `UnitPrice = TotalPrice` real non-zero, **`NetUnitPrice`/`NetTotalPrice`/`Source_List_Price__c` all BLANK** → priced via COLA carry-forward, NOT the tier formula. UnitPrice set: {208.04, 208.04, 309.93, 334.25, 345.51, 360.42, 372.64, 400.88, 414.97, 419.22, 423.28, 892.24, 914.17, 952.88, 985.93, 1027.70, 1108.39, 2468.80}.
- **Created/stable:** all created 2026-05-04 (seed/migration batch), all stable (no in-flight reprice).
- **PBEs:** EFWO `01uWC000005wsaxYAA` (IsDerived, UnitPrice 0); EFSMB `01uWC000005wt89YAA` (IsDerived, UnitPrice 0); both on "Fortra Price Book".

**Order-side (also exhaustive — only one MTD AttributeDefinition exists):** `OrderItemAttribute` MTD = 19,231 rows; **platinum = 5**, all `Renewal Maintenance` on `Activated` orders, `Net=Unit=TotalLineAmount` all >0 (208.04, 360.42, 423.28, 985.93, 1108.39). Orders 00017591/00016534/00016551/00016781/00017583. These mirror 5 of the 18 quote lines. None $0.

**18 platinum QLI Ids:** `0QLWC000003DTLI4A4, 0QLWC000003DURq4AO, 0QLWC000003ENbx4AG, 0QLWC000003DFhT4AW, 0QLWC000003E03u4AC, 0QLWC000003E0424AC, 0QLWC000003DDY44AO, 0QLWC000003DUQ64AO, 0QLWC000003E03y4AC, 0QLWC000003DuNK4A0, 0QLWC000003DuMo4AK, 0QLWC000003DLAm4AO, 0QLWC000003DLAf4AO, 0QLWC000003DIDH4A4, 0QLWC000003DIDB4A4, 0QLWC000003DDY64AO, 0QLWC000003DIDT4A4, 0QLWC000003ERcK4AW`.

**Where the sources were wrong:**
- Retest report **"0 live usage" = WRONG.**
- Retest report **"platinum 15" = WRONG** — a 50,000-row export-cap truncation artifact (`mtd_full.csv` was exactly 50,001 lines; the real universe is 102,122). The 15 IDs are a strict subset of the live 18; the 3 missed: `0QLWC000003DTLI4A4, 0QLWC000003ENbx4AG, 0QLWC000003ERcK4AW`.
- Prior memory **"18 / EFWO ×13 / EFSMB ×5 / Renewal Maintenance / Approved / COLA carry-forward" = CORRECT.**

---

## 4. K2 RESOLVED — live formula tier count + platinum handling

**Active version = V14** (`ExpressionSetDefinitionVersion 9QBWC0000000nIT4AY`, VersionNumber 14, Status **Active**; V1–V13 all Inactive). Confirmed by Tooling API this session AND by `<status>Active</status>` on the V14 block (line 69805) of the fresh metadata retrieve. ESD `9QAWC0000003mg14AA` (`Rev_Mgmt_Default_Pricing_Procedure`).

**Live V14 `DerivedPricingFormula` (verbatim, `src_fresh/...meta.xml` line 71642):**
```
IF ( AttributeValue = 'Premier' , 0.30 , IF ( AttributeValue = 'Standard' , 0.20 , IF ( AttributeValue = 'Professional' , 0.20 , 0 ) ) ) * Source_List_Price__c
```
- **Tier count = 3** (Premier / Standard / Professional). Terminal **else = 0**.
- **`platinum` references in entire definition = 0.** `Maintenance_Rate` references = 0. `MaintenanceType` references = 0. (grep over all 75,347 lines, all 14 version blocks.)
- **Silent $0:** the formula element has `resultIncluded=false`, `shouldShowExplExternally=false`, output → `NetUnitPrice` via `DerivedPricingValuesAssignment` (NetUnitPrice→InputUnitPrice) with no `>0` guard. No error / validation / MissingContributor / flag in the V14 derived path. A tier with no branch → `0 * Source_List_Price__c = $0` **silently**.
- **5 of 8 picklist values are unhandled by the formula even though they have valid CMDT rows** (Basic, Premium, Express, Expert, plus orphan platinum) → the formula is independently out of sync with both the picklist AND the CMDT. This is a wider design gap than DEFECT-A alone.
- **Why live platinum lines are safe:** sibling step `DerivedPricingNetUnitPriceValueReset` (line ~71707/71755) = `IF ( QuoteTypeText__c = 'Renewal' , NetUnitPrice , 0 )` carries Renewal net forward and bypasses the tier formula. All 18 platinum lines are Renewal → never reach the else=0.

**Where the sources were wrong:**
- Retest report **"3 tiers" = CORRECT and current.**
- Memory **`project_nb_derived_tier_fix` "completed 3→7 tiers; platinum left $0+flagged; 1,031 lines un-$0'd" = NOT LIVE.** The 7-tier formula exists only as an un-deployed local candidate (`Data/sc-maint/sc3346_fix/retrieve_tier/...meta.xml`, 7-tier: Basic 0.15/Premium 0.24/Express 0.30/Expert 0.35 added). It was staged but **never deployed/reactivated**. The live V14 is byte-identical across two independent fresh retrieves (`myretrieve/` and `src_fresh/`, diff exit 0) and shows 3 tiers.
  - **Action item for the owner/team:** memory `project_nb_derived_tier_fix` should be corrected — the 7-tier completion it asserts is not live.

---

## 5. Mispricing-today verdict

**NO live platinum line is committing wrong money right now.**

- 18 quote lines + 5 order lines = the **complete** platinum population (only one MTD AttributeDefinition exists; QLIA+OIA exhaust it).
- Adversarial sweep (re-exported 09:38–09:39) found: platinum non-Renewal = 0; UnitPrice==0 = 0; NetUnitPrice==0 = 0; TotalPrice==0 = 0; Source_List_Price__c populated = 0; non-Approved/non-Activated = 0; in-flight reprice = 0 (all LastModified 2026-05-07, 35+ days stable).
- All 23 platinum lines carry real non-zero COLA carry-forward prices ($208.04–$2,468.80).
- **The $0 tier-formula trap is genuinely LATENT.** It fires only on a **NEW-maintenance** platinum line with `Source_List_Price__c` populated — of which there are **zero** in 102,122 QLIA + 19,231 OIA rows.

**Residual risk that keeps this from being "no action ever":** `platinum` is **globally selectable** on all 186 MTD-bearing products (the picklist value set is shared; no per-PAD value override exists), AND `GS-GSE-RRM-EFSMB`'s PAD (`0v7WC0000000EP7YAM`) **defaults to `platinum`** (the only one of 186 that does). So a future new-maintenance platinum line is plausible, especially on the EFSMB product, and would silently derive $0.

**Honest gap (out of DEFECT-A scope):** this check confirms platinum lines are NOT $0 and NOT routed through the tier formula; it does not independently re-derive each renewal's COLA carry-forward against a business baseline. A numerically-wrong-but-nonzero COLA price would be a *different* defect (SC-3350 family), and no evidence suggests one exists here.

---

## 6. Resolution options

| Option | What it does | Fixes the $0 trap? | Needs business RATE? | Deploy mechanics | Risk | Verdict |
|---|---|---|---|---|---|---|
| **A. Add CMDT row + add platinum branch to V14 formula** | CMDT `Maintenance_Rate__mdt.platinum` row + `IF(AttributeValue='platinum',<rate>,…)` branch | Formula branch: YES. CMDT row: **INERT** (formula ignores CMDT). | YES (the rate value) | CMDT = trivial (cola_fix pattern, CustomMetadata member, api 67, no version dance). **Formula = live Active-V14 edit: deactivate→deploy api67 --metadata-dir→UI reactivate (offline pricing window)→Force-reprice verify** (`reference_pricing_procedure_deploy_mechanics`). | HIGH on the formula edit: V14 formula is shared by ~100,012 non-platinum derived-maintenance lines (Premier 42,604 + Professional 41,881 + Standard 16,588); malformed edit regresses all. | The real fix, but rate-gated + offline-window. CMDT-alone is a no-op for this defect. |
| **B. Remap platinum → existing tier + retire the orphan picklist value** | Deactivate `platinum` picklist value (stop future selection) + (optionally) DML-remap the 18 QLIA rows to e.g. Standard | Picklist retire alone: **NO** (doesn't touch the formula). Future-selection: YES. | YES (which tier / "is it an error?") | Picklist value `Status` Active→Inactive = metadata edit (safe: Text-backed unrestricted, existing free-text rows persist). 18-row QLIA remap = DML (out of scope). | Picklist retire on existing rows = LOW (free text persists). But leaves the `DefaultValue='platinum'` PAD dangling; doesn't fix formula gap; declaring platinum invalid IS the business judgment. | Good **hygiene** half-measure; incomplete on its own. |
| **C. Interim non-silent guard (no rate chosen)** | Make a platinum NEW-maint line visibly wrong instead of silently $0 | Partially (visibility only) | No (but…) | `FormulaBasedPricing` can only emit a number — "non-silent" = a sentinel (−1/large value), fragile. A real guard = new before-save validation/flow OUTSIDE the procedure (new automation). | Sentinel inside V14 = SAME offline-window cost as A with no rate fixed. New automation = owner-gated, arguably unnecessary at zero live exposure. | **NOT recommended** — same cost as the real fix, leaves rate undecided. |

**Data-inferred rate (for the owner's benefit, NOT a decision):** the data points weakly to **Standard (0.20)** — the same products' non-platinum renewal lines use Standard (EFWO has Standard ×5), and the direct New-Maintenance twin `GS-GSE-RNM-EWWM` is 100% Standard (6/6). BUT the literal name "platinum" connotes a premium tier (could be Premier 0.30 / Premium 0.24 / Expert 0.35), and two RRM products are not an unambiguous corpus. **The data does not unambiguously resolve the rate.**

---

## 7. Recommended resolution

**Primary recommendation: route the RATE/INTENT decision to the business owner (Nir / pricing owner) NOW, and do NOT touch the live V14 procedure until that answer is in.** Urgency is LOW (zero live mispricing), so there is no justification for incurring the offline-window risk of a live Active-V14 formula edit on an undecided rate.

**Safe interim structural action I can stage (does not require the rate decision):** prepare — but gate on a one-line owner ack — the **deactivation of the orphan `platinum` AttributePicklistValue** (`0v6WC0000000A5SYAU`, Active→Inactive). This stops *future* selection of an un-priced tier (closing the latent-trap entrance) without touching the live pricing procedure, without DML on the 18 existing rows (Text-backed/unrestricted → their `platinum` free-text persists and they keep their correct COLA prices). **Caveat that makes me gate it rather than fire it:** retiring the value leaves `GS-GSE-RRM-EFSMB`'s PAD `DefaultValue='platinum'` dangling, so it should be paired with re-defaulting that PAD (to Standard, matching its sibling EFWO) — which is itself a small business-flavored choice. I therefore recommend presenting B-as-interim and A-as-full-fix together to the owner rather than unilaterally deactivating.

**When the rate comes back:**
- If owner says **"platinum is a data-entry error, remap to Standard"** → Option B: deactivate picklist value + re-default the EFSMB PAD to Standard + (separately scoped) DML-remap the 18 QLIA rows. No formula edit needed (Standard already handled). Lowest-risk path.
- If owner says **"platinum is a real tier at rate R"** → Option A (formula branch): the formula must be extended on the live V14 procedure via the deactivate→deploy→reactivate window. **Strongly recommend bundling the other 4 unhandled-but-valid tiers (Basic/Premium/Express/Expert) into the same edit** — they are independently silent-$0 risks — i.e. promote the staged 7-tier `retrieve_tier/` candidate (after re-validation) so the formula matches the full picklist+CMDT set. This converts a one-off into closing the whole class.

---

## 8. exactSteps (precise, both branches)

**Files / IDs in play**
- Live procedure metadata: `Data/sc-maint/sc3346_fix/mdt_records/src_fresh/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (V14 block lines 69799–75345; tier formula line 71642; Renewal carry-forward ~71707/71755).
- Staged 7-tier candidate (NOT live, re-validate before use): `Data/sc-maint/sc3346_fix/retrieve_tier/...expressionSetDefinition-meta.xml`.
- CMDT deploy pattern proof: `Data/sc-maint/sc3346_fix/cola_fix/package.xml` (`<members>COLA_Uplift_Rules.Powertech_IAM_BoKS</members>`, `CustomMetadata`, version 67.0).
- Orphan picklist value: `AttributePicklistValue 0v6WC0000000A5SYAU` (`platinum`, APV_1559, Active).
- platinum-default PAD: `0v7WC0000000EP7YAM` on `GS-GSE-RRM-EFSMB` (`01tWC00000DD1G7YAL`).
- Active version: `ExpressionSetDefinitionVersion 9QBWC0000000nIT4AY` (V14), ESD `9QAWC0000003mg14AA`.

**Step 0 (do first, no deploy):** Put the owner question (§9) to Nir/pricing owner with the §3 usage profile + §6 inferred-rate table attached. Block all metadata changes until answered.

**Branch ERROR (remap to Standard):**
1. Stage CustomMetadata-free change — no CMDT row needed (Standard already priced).
2. Re-default PAD `0v7WC0000000EP7YAM` (EFSMB) `DefaultValue platinum→Standard` (metadata, matches EFWO sibling).
3. Deactivate `AttributePicklistValue 0v6WC0000000A5SYAU` (Active→Inactive) — metadata, no version dance. Existing 18 free-text rows persist with correct COLA prices.
4. Separately scope a one-time DML remap of the 18 QLIA + 5 OIA `platinum`→`Standard` rows (the 23 IDs in §3) **only if** the business wants the historical data normalized — these are Approved/Activated and correctly priced, so this is cosmetic/optional.
5. No live V14 formula edit required → no offline window.

**Branch REAL TIER (rate = R):**
1. Add `Maintenance_Rate__mdt.platinum = R` CMDT row (cola_fix pattern: CustomMetadata member, `sf project deploy`, api 67) — *documentary/forward-looking; note it is inert to the current formula which hard-codes rates.*
2. Edit the V14 `DerivedPricingFormula` (line 71642) to add `IF(AttributeValue='platinum', R, …)`. **Recommended: promote the full 7-tier formula** (Basic 0.15 / Premium 0.24 / Express 0.30 / Expert 0.35 / platinum R + existing 3) so all 8 picklist values are handled and aligned to the CMDT.
3. Deploy via `reference_pricing_procedure_deploy_mechanics`: deactivate V14 → `sf project deploy start -o FortraUAT --metadata-dir ... ` (api 67) → UI reactivate → **Force-reprice verify** on a canary derived-maintenance line per tier.
4. Optionally also re-default the EFSMB PAD and/or retire the picklist value per the business' intent for "platinum" going forward.
5. **Regression guard:** because the formula is shared by ~100,012 non-platinum derived lines, validate Premier/Standard/Professional outputs are unchanged post-deploy before closing the window.

---

## 9. The exact owner decision needed

> **Question to Nir / pricing owner:** "The maintenance tier-designation picklist has a value `platinum` (lowercase) that has no maintenance rate and is not handled by the live pricing formula. It is used on **18 quote lines + 5 order lines, all Renewal Maintenance** for two EFT-WSM products (`GS-GSE-RRM-EFWO`, `GS-GSE-RRM-EFSMB`), all currently priced correctly via COLA carry-forward (no mispricing today). However, the `GS-GSE-RRM-EFSMB` product **defaults new lines to `platinum`**, and any future **new-maintenance** line on `platinum` would silently price at **$0**. Is `platinum` (a) a **data-entry/migration error** that should be remapped to an existing tier (the data suggests **Standard, 0.20**), or (b) a **real maintenance tier**, and if so **at what rate** (existing rates: Basic 0.15, Standard/Professional 0.20, Premium 0.24, Premier/Express 0.30, Expert 0.35)?"

**Data the owner needs to answer (all in this dossier):** the §3 usage profile (18+5 lines, 2 products, all Renewal/Approved/Activated, correct prices), the §6 inferred-rate rationale (Standard 0.20 from sibling/twin products) with the competing "premium-name" reading, and the §4 note that 4 other valid tiers (Basic/Premium/Express/Expert) are also unhandled by the formula (so a "real tier" answer should trigger a full-tier-set formula completion, not a one-off).

---

## 10. Owner-gated vs executable-now (explicit)

- **Owner-gated (cannot be done unilaterally):** the platinum RATE/INTENT decision; the V14 formula edit (Option A); the QLIA/OIA data remap (Option B DML); any new before-save guard automation (Option C).
- **Executable now without the rate decision (but I recommend gating on a one-line ack, see §7):** deactivating the orphan `platinum` picklist value (`0v6WC0000000A5SYAU`) is a safe metadata-only change that stops future selection and provably does not break the 18 existing free-text rows. It must be paired with re-defaulting the EFSMB PAD, which is a minor business-flavored choice — hence "stage + ack," not "fire blind."
- **No safe unilateral action fully resolves DEFECT-A.** The only mechanically-trivial piece (CMDT row) is **inert** because the live formula hard-codes rates and never reads the CMDT.

---

## Evidence index (all under `Data/sc-maint/sc3346_fix/mdt_records/`)
- `mtd_refresh_0938.csv` / `mtd_full_live.csv` / `mtd_ids_full.csv` / `mtd_qlia_live_full.csv` — full 102,122-row MTD QLIA export (platinum=18, all 3 agree).
- `platinum_qli_detail.csv` — the 18 platinum quote lines with prices.
- `oia_refresh_0939.csv` / `oia_mtd_full.csv` — 19,231-row MTD OIA export (platinum=5).
- `src_fresh/` + `myretrieve/` — byte-identical fresh V14 metadata retrieves (3-tier formula @ line 71642, `<status>Active</status>` @ 69805; platinum/Maintenance_Rate/MaintenanceType = 0 occurrences).
- `EVIDENCE.txt` — investigator evidence summary.
- Contrast (NOT live): `Data/sc-maint/sc3346_fix/retrieve_tier/...meta.xml` — the staged-but-undeployed 7-tier candidate.
- Live re-verifications this session: `ExpressionSetDefinitionVersion` (V14 sole Active), `Maintenance_Rate__mdt` (7 rows), `AttributePicklistValue` (8 values, platinum lowercase Seq 3), PAD count 186, EFSMB PAD `DefaultValue='platinum'`.
