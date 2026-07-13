# LANE 4 — PROCEDURE VERSION REALITY

Scope: active version (V21) deep; inactive by summary; V20 reconciliation by label+function; intra-V21 clone artifacts; null-safety inventory; file authority (scratch_v210.xml, .bak_preedit).
Evidence base: `soql/esd_versions.txt`, `live-esd/ACTIVE_V21_steps.tsv` (128 rows), `live-esd/ACTIVE_V21_block.xml` (6,895 ln), full live ESD (124,657 ln), repo-root `scratch_v210.xml` (6,912 ln). Read-only; no org calls this run.

---

## AXIS 1 — PER-VERSION PROLIFERATION

### VR-1 — 22-version inventory & status split — CONFIRMED
`soql/esd_versions.txt:5-26` lists exactly 22 ExpressionSetDefinitionVersion rows under DeveloperName family `Rev_Mgmt_Default_Pricing_Procedure_*`. Status split is **1 Active / 1 Draft / 20 Inactive**:
- **Active** = V21, Id `9QBWC0000000oWH4AY`, DeveloperName `..._Rev_Mgmt_Default_Pricing_V210`, VersionNumber 21, MasterLabel "Rev Mgmt Default Pricing V21", LastModified 2026-07-03T00:06:43Z (`esd_versions.txt:6`).
- **Draft** = V22, Id `9QBWC0000000ofx4AA`, DeveloperName `..._V220`, MasterLabel "(Deprecated) Rev Mgmt Default Pricing V22" (`esd_versions.txt:5`). CONFIRMS ground-truth correction: the `...V220` fullName is a **separate Draft/deprecated V22, NOT the active version**.
- **20 Inactive** = V1-V20 (`esd_versions.txt:7-26`).

All V1-V20 (and the V22 Draft) share LastModified **2026-06-30T19:30:54Z** by `005WC00000MgTN2YAN` (`esd_versions.txt:5,7-26`) = the single bulk metadata deploy. Only V21 has a later stamp (2026-07-03). This makes the whole inactive tail inert clutter frozen at one instant — no independent evolution.

### VR-2 — Deprecated-vs-kept label convention — CONFIRMED
Label-prefix scan of `esd_versions.txt` MASTERLABEL column:
- `(Deprecated)`/`(deprecated)` prefix present on V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12,V13,V17,V18,V19,V22 (`esd_versions.txt:5,8-24`).
- **No** deprecated prefix — deliberately kept — on **V14, V15, V16, V20** (`esd_versions.txt:7,11-13`) and V21 (Active) and V1 (the genesis "V1"). V20 = "Rev Mgmt Default Pricing V20" clean (`esd_versions.txt:7`).
- Casing is inconsistent ("(Deprecated)", "(deprecated)", "(Deprecated) " with trailing space) — cosmetic label drift, no functional meaning.

### VR-3 — V20 is the live-backup of V21 — CONFIRMED (by function, label-level reconcile)
V20 is the only clean-labelled Inactive version immediately below the Active V21 and is the closest sibling by content (see VR-4). It is the roll-back target if V21 must be deactivated. Note the runtime is version-pinned by the two `PricingActionParameters` bindings to the *procedure* (`soql/pricing_action_parameters.txt`), and activation is toggled at the version level — so "restore V20" = activate V20, deactivate V21.

### VR-4 — V20→V21 reconciliation BY LABEL+FUNCTION — CONFIRMED (with one nuance UNVERIFIED)
Blocks: V20 = full-ESD lines **104365-110854**; V21 = `ACTIVE_V21_block.xml` (also full-ESD 110855-117749). Label-multiset diff (`<label>` extraction, both blocks):

**Labels present in V21 but ABSENT in V20 (13)** — the "V21 = V20 + …" additions:
- COLA/amend seed carry: `Amend Filter`, `Amend Net Carry`, `Amend Seed Net Total`, `Amend Seed Net Unit`
- one-time/partner seed: `OneTime Net Seed`, `OneTime Net Seed Filter`, `Seed OneTime Net Before Partner`, `Reset Net to Pre-Partner Base`
- guard/reset: `Reset Amount Base From List`, `Reset Total Services (K-09 zero-init)`, `Reset Total Software (K-09 zero-init)`, `Reset Total Subscription (K-09 zero-init)`
- (plus the version's own title label `Rev Mgmt Default Pricing V21`)

**Labels present in V20 but REMOVED in V21 (4 functional + title):**
- `Partner Percent Procedure Audit`, `Partner Percent Resolved Filter`, `Resolve Partner Discount Percent` — the **partner-percent resolution trio was deleted from the ESD** in V21. This aligns with memory J-06 (`computeNewBusinessMaintenanceNets`): partner-maint-band resolution moved into Apex, so the in-procedure percent-resolution steps were retired.
- `Term-Defined proration filter (Line level)` — present in V20, **absent in V21**. V20 has TWO `Proration` labels + the Term-Defined filter; V21 has only ONE `Proration` + `Evergreen anytime proration filter (Line level)`. This is the Term-Defined proration path that memory "COLA V16→V20 reconcile" flagged as dropped between V16 and V20 — it is STILL absent in V21. **OPEN QUESTION (owner: pricing lead / Nir):** the active <description> claims V21 adds "COLA proration"; yet the Term-Defined proration filter step V16 once had is not label-present in V21. Confirm whether Term-Defined proration is now handled inside the single `Proration` BKM step (line-level EffectiveFrom) rather than a dedicated filter, or whether this is a residual COLA regression.

Currency: all four `Currency Conversion - {Net Unit Price | Unit Price Display | Net Total / Subtotal | Total Line Amount}` labels are present in **both** V20 and V21 (identical multiset). So the "+ currency" clause of the description is NOT a V20→V21 delta — currency conversion already existed in V20. **CORRECTED nuance:** the description's "(… + currency)" over-states; currency steps predate V21.

### VR-5 — Derived-pricing "3-tier" reversion — UNVERIFIED at the formula body
Active <description> (`ACTIVE_V21_block.xml:4`): *"V21 - V20 (COLA proration + guards + currency) with Derived Pricing Formula reverted to 3-tier. DRAFT."* Both V20 and V21 carry the same `Derived Pricing Formula` step (parentStep `ListContainer9`, actionType `FormulaBasedPricing`), and its `formula-section-0-input` body is **byte-identical** across V20 and V21: `IF ( QuoteTypeText__c = 'Renewal' , NetUnitPrice , 0 )` (`ACTIVE_V21_block.xml:~2645`; V20 block same). There is no 3-way CASE/7-branch tier ladder inside this step in either version — tiering is delegated to decision tables (`Price_Adjustment_Tier_Decision_Table`, `ACTIVE_V21_block.xml:6565`) and the `Formula Based Pricing 3` step (TSV seq44). **Therefore the "reverted to 3-tier" claim cannot be confirmed from the Derived Pricing Formula step body; V20↔V21 are equivalent there.** The reversion (if real) was relative to the V22 Draft or an in-tree 7-tier experiment (see memory NB-DERIVED-TIER), not a V20→V21 change. Flag: the word "DRAFT" is stale on an Active version — description hygiene defect.

### VR-6 — IsNotNull guard count is LOWER in V21, not higher — CORRECTED
Raw `IsNotNull` operator count: **V20 = 12** (`/tmp/v20_block.xml` grep) vs **V21 = 9** (`ACTIVE_V21_block.xml:1124,1136,2083,2088,2100,2171,3452,3515,4930`). The description's "+ guards" does NOT manifest as more IsNotNull operators; the three removed partner-percent steps (VR-4) carried IsNotNull checks, netting the count down. V21's guarding is instead concentrated in dedicated null-safe *filter* steps (VR-8). Do not read "guards" as "more IsNotNull".

### VR-7 — Inactive tail = inert clutter — CONFIRMED (summary only, per scope)
V1-V19 + V22-Draft are non-runtime, all frozen at 2026-06-30T19:30:54Z (VR-1). They are never referenced by the two live PricingActionParameters bindings. No per-version diff performed (out of scope). Recommendation for the refactor plan: these 20 dormant versions are safe to leave but are pure noise in MDAPI retrieves (each retrieve pulls all 22 inline, ~124k lines — see memory "ESD multi-version metadata"); a future cleanup could hard-deprecate-label the four unlabelled kept versions (V14/15/16) once V20 backup is confirmed, but **ExpressionSetVersion hard-delete is blocked** (memory "Proc version delete blocked") so they cannot be removed.

---

## AXIS 2 — INTRA-V21 CLONE ARTIFACTS (Priority-A proliferation)

### VR-8 — Null-safety / seed / guard filter inventory in ACTIVE V21 — CONFIRMED
From `ACTIVE_V21_steps.tsv`, the single active version contains exactly ONE of each of these AdvancedListFilter guard steps (name / label / parentStep):
| name | label | parentStep | count in V21 |
|---|---|---|---|
| `StampBaseFilter` | Stamp Base Filter | StampContributorBasePreDiscount | **1** |
| `AllLinesNullSafeFilter` | All Lines Null Safe Filter | ListContainer11 | 1 |
| `OneTimeNetSeedFilter` | OneTime Net Seed Filter | SeedOneTimeNetBeforePartner | 1 |
| `AmendFilter` | Amend Filter | AmendNetCarry | 1 |
| `DerivedMaintenanceNetFilter` | Derived Maintenance Net Filter | ListContainer9 | 1 |
| `DerivedPricingFilter` | Derived Pricing Filter | ListContainer10 | 1 |
| `AttributePricingFilter` | Attribute Pricing Filter | ListContainer | 1 (twin: see VR-9) |
| `AttributePricingFilter8` | Attribute Pricing Filter | ListContainer7 | 1 |

Plus null-safe **formula** BKM steps (parent ListContainer11 / ListContainer57): `Null-Safe Line Adjustment`, `Null-Check for Line Adjustment` (TSV seq2, lines 52-53).

**RESOLVES the K-01 / SC-3441 "3 of 6" StampBaseFilter story: in the ACTIVE V21 there is exactly ONE `StampBaseFilter` step** (`ACTIVE_V21_block.xml:5689`, sole `<name>StampBaseFilter</name>`; grep count = 1). The "3 of 6" was a per-version tally across historical versions, not the active-version reality. The active version's StampBaseFilter is the null-guarded one (Portion-1 K-01/F-12 fix, memory "V21 Portion-1 fixes").

### VR-9 — Duplicated `<label>` collisions in ACTIVE V21 — CONFIRMED (Priority-A evidence)
128 steps but many share a `<label>`. Label collisions (label × occurrences), from TSV col3:
| label | # steps sharing it |
|---|---|
| List Container | 12 |
| List Operation | 8 |
| Assignment | 4 |
| Subscription Pricing | 3 |
| Partner Discount - Derived Maintenance | 3 |
| Aggregate Price | 2 |
| Attribute Pricing Filter | 2 |
| Attribute Value Pricing - Calculated Mode | 2 |
| Attribute Value Pricing - Total Price Mode | 2 |
| Attribute Value Pricing - Unit Price Mode | 2 |
| COLA Uplift on Renewal | 2 |
| Contacted Pricing [sic] | 2 |
| GSA Pricing | 2 |
| Partner Discount | 2 |
| Quantity * Price | 2 |
| Regional Services Price | 2 |

**16 distinct labels are non-unique**, covering ~50 of the 128 steps. Identity therefore requires label + parentStep + function (as ground-truth rule 7 states). "Contacted Pricing" is also a persistent **typo** ("Contracted") — cosmetic but propagated to two steps (TSV:10,46).

### VR-10 — `<name>` collisions in ACTIVE V21 — CONFIRMED
Non-unique `<name>` values (TSV col2):
| name | # steps |
|---|---|
| `formula-section-0-input` | 28 |
| `section-0-input1` | 14 |
| `section-count` | 6 |
| `AdjustmentType` | 5 |
| `Quantity` | 4 |
| `PriceAdjustmentScheduleId` | 4 |
These are Salesforce's generic BKM I/O parameter slot names, reused across every formula/assignment/aggregate step — so **`<name>` is worthless as a step identity key** (confirms ground-truth rule 7: never diff by `<name>`). 61 of the 128 rows carry one of these six shared names.

### VR-11 — Numeric-suffix twin steps in ACTIVE V21 — CONFIRMED (integer-suffix proliferation)
Suffix-numbered container/operation identifiers actually present in the live active version (TSV col2):
- **ListContainer family (28 containers):** `ListContainer`, `ListContainer1..11`, `ListContainer25/28/57/720/75/78/81/88/92/95/98`, plus `AmendNetCarry`, `DerivedProductsNativePull`, `EvergreenanytimeprorationfilterLinelevel`, `PartnerDiscountDerivedMaintenance`, `SeedOneTimeNetBeforePartner`, `StampContributorBasePreDiscount`, `SyncInputUnitPriceforDiscountBase`. The numbering is **non-contiguous** (jumps 11→25→28→57→75→720) = accreted over versions, gaps where intermediate containers were deleted. `ListContainer720` is a mislabel/fat-finger (label "List Container 7").
- **ListOperation twins (8):** `ListOperation`, `ListOperation38/82/85/89/93/96/99` — all label "List Operation" (VR-9).
- **`AttributePricingFilter` + `AttributePricingFilter8`** — same label "Attribute Pricing Filter", two parents (ListContainer / ListContainer7).
- **`PartnerDiscountDerivedMaintenance64`** — filter twin of container `PartnerDiscountDerivedMaintenance`.
- **`Copy1ofListContainer8` + `Copy1ofCopy1ofListContainer8`** — the classic canvas copy-of-copy clones: List Container 8 (`Total Services`/`Services Aggregate Price`) cloned once → Software (`Copy1ofListContainer8` → `Total Software`/`Software Aggregate Price`) and twice → Subscription (`Copy1ofCopy1ofListContainer8` → `Total Subscription`/`Subscription Aggregate Price`). Three near-identical aggregate sub-trees differing only by category filter — prime Priority-A dedup candidate (TSV:32-34,62-64,113-118).
- AggregatePrice / Assignment integer suffixes (`AggregatePrice124`, `Assignment100/128`, etc.) are visible in the block XML but are auto-generated internal node names, not step-level identities.

**Net Priority-A read:** the active version alone carries ≥16 duplicate-label groups, 6 heavily-overloaded generic names, a 28-member non-contiguous ListContainer sprawl, and an explicit copy-of-copy triad — all *intra-version* clutter independent of the 22-version tail.

---

## FILE AUTHORITY

### VR-12 — scratch_v210.xml is a NON-authoritative, FUNCTIONALLY divergent snapshot — CONFIRMED (drift hazard)
`scratch_v210.xml` (repo root, 6,912 ln) vs `ACTIVE_V21_block.xml` (6,895 ln): raw `diff` = 546 marker lines. **Most of that is cosmetic integer-renumbering** (e.g. `AggregatePrice126`↔`124`, `ListContainer90`↔`88`, `Assignment102/ListContainer100`↔`Assignment100/ListContainer98`, `sequenceNumber` +1 offsets) — same class of re-serialization noise as ground-truth #8. BUT the **label-multiset diff is NOT empty — there are 4 functional label deltas**:
- scratch_v210 **HAS** `Partner Percent Procedure Audit`, `Partner Percent Resolved Filter`, `Resolve Partner Discount Percent` — the exact partner-percent trio that live V21 **removed** (VR-4).
- scratch_v210 **LACKS** `Reset Amount Base From List` — a step live V21 **added**.

Those are precisely the V20-lineage labels. **scratch_v210.xml is therefore a pre-J-06-refactor / V20-content hybrid mislabeled "v210" — it is behind the live active version, not equal to it.** Deploying it would (a) re-introduce the retired in-procedure partner-percent resolution steps (double-count risk vs the Apex `computeNewBusinessMaintenanceNets` path) and (b) drop the `Reset Amount Base From List` guard. **This is a live drift/regression hazard, not cosmetic.**
- **Recommendation:** treat `scratch_v210.xml` as a discardable working snapshot; the authoritative V21 = the org's active version, mirrored read-only by `live-esd/ACTIVE_V21_block.xml`. Do NOT deploy `scratch_v210.xml`. **OPEN QUESTION (owner: pricing engineer / Liam):** delete or clearly quarantine `scratch_v210.xml` from repo root so it is never mistaken for the deployable V21 source.

### VR-13 — .bak_preedit is a pre-edit backup of the repo ESD mirror — CONFIRMED (map-only)
`force-app/main/default/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml.bak_preedit` (5,603,854 B) is a byte-near sibling of the current repo meta.xml (5,604,550 B) — an all-22-versions inline MDAPI snapshot saved before an in-tree edit (dated Jun 30 13:14). It is the **repo** re-serialized variant (ground-truth #8: cosmetic renumbering vs live), NOT a runtime artifact. Neither the repo meta.xml nor its .bak is authoritative for runtime — the **live org active version is** (edit the canvas, per memory "Pricing proc V21 in-place only"). **Recommendation:** the repo `expressionSetDefinition/*.xml` + `.bak_preedit` should carry a header comment or be git-ignored to signal non-authoritative; flag as low-risk drift, owner pricing engineer.

---

## SUMMARY FOR ORCHESTRATOR
- **Version proliferation is real but frozen:** 22 versions, 20 inactive at one 2026-06-30 timestamp, only V21 live, V20 clean backup, hard-delete blocked → dormant clutter, low active risk.
- **V21 = V20 minus the partner-percent ESD trio (moved to Apex) and minus the Term-Defined proration filter, plus amend/one-time-seed/reset guards.** "Currency" and "3-tier revert" clauses of the description are NOT V20→V21 deltas (VR-4, VR-5) — description is partly stale/mislabeled ("DRAFT" on Active).
- **Priority-A intra-version clutter is the bigger dedup target:** 16 duplicate-label groups, 6 overloaded names, 28-member non-contiguous ListContainer sprawl, explicit Copy-of-Copy aggregate triad — all inside the single active version.
- **Two file-authority hazards:** `scratch_v210.xml` is a V20-lineage hybrid (functional regression if deployed) and `*.bak_preedit`/repo ESD are non-authoritative re-serializations. Authoritative source = the org's active V21 (mirrored `ACTIVE_V21_block.xml`), editable only via canvas in-place.
- **Open questions to route:** Term-Defined proration status in V21 (owner: pricing lead/Nir); quarantine/delete `scratch_v210.xml` (owner: Liam).
