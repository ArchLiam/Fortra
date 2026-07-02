# SC-3522 Peer Review Report: SC-3506 Asset State Period Behavior

**Reviewer:** Liam Jeong (SC-3522, subtask of SC-3506) · **Org:** FortraUAT (00DWC000006eUFF2A2) · **Date:** 2026-07-01 · **All org queries read-only.**

---

## 1. Executive Summary & Overall Verdict

**Overall verdict: SC-3506's *core* expected behavior HOLDS and the native RCA implementation is CORRECT for the state-period mechanics — but SC-3506 is NOT ready to close.** It needs (a) three factual corrections to the draft findings, (b) explicit re-classification of the real defects as *upstream* (not ASP-engine) bugs, and (c) an expanded test sample before the acceptance criterion "verify current implementation matches expected RCA behavior across amendment/renewal/cancellation scenarios" can be certified.

What is confirmed working (independently re-queried):
- **Amendments** produce a clean effective-date period split (prior period end-dated, new contiguous period with the changed quantity) — verified on 07DSnFYAW and 08MuWnYAK.
- **Renewals** create a new forward-dated AssetStatePeriod whose StartDate is exactly the day after the prior period's EndDate, preserving the prior period — verified on all 4 renewal assets (06tCOTYA2, 08ARwnYAG, 08FcLaYAK, 08LXfZYAW).
- **Cancellations** create an AssetAction (Type=Cancel/Cancellations, Δqty −1) and NO new AssetStatePeriod — verified on the org's only cancellation (08ARwoYAG).

What deviates (real, confirmed defects — all **upstream** of ASP generation):
- **2039 12-year renewal end-date** on 06tCOTYA2 (root cause proven: renewal source line `PricingTermCount=12`) — **HIGH**.
- **mrr=0 renewal periods** on 08FcLaYAK and 08LXfZYAW (root cause: upstream COLA renewal zero-price, SC-3350/SC-3346; the order line carried $0 net *before* assetization) — **HIGH**.
- **Stale Asset current-state rollups** on 08LXfZYAW (`CurrentQuantity=0/CurrentMrr=0` while a live period carries q100/mrr162.5) — **MEDIUM**.

What the draft got wrong (corrections that MUST be folded in before close):
- The claimed **"overlapping periods on 08LXfZYAW" is FALSE** — the periods tile contiguously; the "overlap" was an artifact of ordering by CreatedDate. **Retract.**
- The **"open-ended EndDate on a termed product" gap (G1) is misdiagnosed** — BoKS-NewMaintenance is a **OneTime** product (confirmed: its only ProductSellingModelOption is "One Time"/OneTime), for which null ASP EndDate is *correct native behavior*, and ~42% of all ASP rows org-wide carry null EndDate. **Downgrade** to a Contract-vs-ASP sourcing design question.
- The **"same-day amendments produce no split" gap (G2) is expected native behavior**, not a contradiction — the discriminator is *effective date == asset start date* (proven: 08MuWnYAK's two actions were on the same calendar day yet it DID split). **Downgrade** to a documented exception.

**Gap count folded into this report: 11** (2 HIGH confirmed, 3 MEDIUM, 4 LOW, 1 INFO, plus the retraction).

---

## 2. What SC-3506 Requires

**Parent ticket SC-3506** — "RCA Investigation Task: Validate Asset State Period Behavior for Amendments and Renewals" (Marc Debrey, reporter Dawn Krauss).

**Stated motivation (verbatim):** "As per the 6/29 Demo, please confirm the expected Asset State Period creation behavior for amendment and renewal processing… Validation of expected Asset State Period generation has been requested because **license key processing depends on the latest state period attributes**. Alice indicated Asset State Periods are generated when changes take effect, but team requested confirmation of expected behavior across amendment and renewal scenarios."

**Acceptance Criteria:**
1. Document expected Asset State Period behavior for **Amendments, Renewals, Cancellations**.
2. Verify current implementation matches expected RCA behavior.
3. Identify any gaps requiring fixes.

**The license-key (LKG) motivation:** when an amendment/renewal/cancellation takes effect, the new/latest state period is supposed to define the correct **expiration date** and **entitlement quantity** that a generated license key must reflect. So any wrong state-period date/quantity is a *potential* corruption of license-key inputs — this is precisely why the ASP behavior must be confirmed before it is relied upon.

---

## 3. Expected Asset State Period Behavior — Per-Scenario Spec

Sourced from the Salesforce RLM Developer Guide (AssetStatePeriod object reference), the Subscription Management "Renew Subscription Example," and the Trailhead "Asset Lifecycle Management with Revenue Cloud" module (Amendments; Renewals & Cancellations). Foundational rule (verbatim, RLM Dev Guide): *"Represents a time span when an asset has the same quantity, amount, and monthly recurring revenue (MRR). An asset has as many asset state periods as there are changes to it (asset actions) during its lifecycle."*

| Scenario | AssetAction Type / CategoryEnum | Expected AssetStatePeriod effect | Source |
|---|---|---|---|
| **Amendment** (Upsell/Downsell/Cross-Sell/Upgrade/Downgrade/Swap/T&C/FieldAmendment) | `Change` / `Upsells` (etc.); Subtype e.g. `FieldAmendment` | Prior period **end-dated at the amendment effective date**; a **new period** created from the next boundary carrying the changed Quantity/Mrr. Quantity entered as a **delta** (+8, −3). *Exception:* if the amendment's **effective date == the asset's start date**, no non-degenerate prior slice exists, so a single period holds the final totals (verified native behavior). | Trailhead "Managing Customer Asset Amendments" ("a new asset state period… reflects the updated quantity"); live-org verification |
| **Renewal** | `Change` / `Renewals` | A **new forward-dated period** whose StartDate = day after prior period's EndDate, carrying the renewal term's quantity/MRR/dates; **prior period unchanged**. Native uplift is expressed via `PriceRevisionPolicy` (CPI/index) or `UnitPriceUplift` (flat %). | Subscription Mgmt "Renew Subscription Example" (verbatim: "The original asset state period is unchanged" / "A new asset state period is created"); Trailhead |
| **Cancellation** | `Cancel` / `Cancellations` | **NO new period.** The existing period closes; Asset current qty/MRR → 0. Cancel quantity = negative delta (e.g. −1). | Trailhead (verbatim: "unlike amendments and renewals, a new Asset State Period isn't created for cancellations") |

**Supporting field semantics:** `EndDate` is null **only** for an evergreen subscription's final open-ended period **OR** for non-term (OneTime) lines that carry no term end (see §5 correction). `SegmentType` values are Yearly/Custom/FreeTrial/Prorated. `UnitPrice` is **not populated in API v66.0+**. Object chain: OrderItem → AssetActionSource → AssetAction → Asset, time-sliced by AssetStatePeriod.

> **Documentation caveat:** Official docs do **not** explicitly state that state periods must be non-overlapping, nor the exact prior-period EndDate-truncation contract; the split contract is inferred from the definition. Salesforce doc pages are JS-rendered SPAs — the AssetStatePeriod reference and Renew example fetched as full static HTML (high confidence); the AssetAction/AssetActionSource references and the CPI Help page returned SPA shells (medium confidence on exact wording). The exact CategoryEnum/Subtype **API literals** were confirmed only via live `sf sobject describe`.

---

## 4. Observed Behavior in FortraUAT vs Expected

Population baseline (independently reproduced, exact match): AssetStatePeriod = **430,642**; AssetAction = **430,646**. AssetAction by Type/CategoryEnum: Generate/Initial Sale **430,630**; Change/Upsells **10**; Change/Renewals **5**; Cancel/Cancellations **1**. Only **16** records are live-lifecycle-generated; the rest is bulk migration.

### Amendment — VERDICT: MATCH (with an expected exception)
| Asset | Observed | Verdict |
|---|---|---|
| 07DSnFYAW (Upsell q1→2) | ASP-1645 2026-03-31→2026-04-01 q1 → ASP-1671 2026-04-02→2027-03-30 q2. Textbook effective-date split. | **MATCH** |
| 08MuWnYAK (Upsell q250→550) | ASP-598 2026-04-01→2026-06-15 q250 → ASP-602 2026-06-16→2027-03-31 q550. Contiguous split. | **MATCH** |
| 08deyfYAA / 08deygYAA (Generate + Upsell 16 min later, **both effective 2026-06-29**) | ONE period each (q3, final totals), created at Generate time, LastModified at upsell time = **in-place update, no split**. AssetActionSource proves both actions had **identical effective StartDate 2026-06-29**. | **MATCH (expected exception)** — same-effective-date collapses to one period; NOT a defect (see §5 G2) |
| 08DFvvYAG (Upsell/FieldAmendment) | ASP-481 2026-06-05→2026-06-14 q1 → ASP-564 2026-06-15→**null** q1. | **MATCH** — split is correct; the null EndDate is correct for this **OneTime** product (see §5 G1) |

### Renewal — VERDICT: MATCH (structure); DEVIATION confined to upstream-supplied values
| Asset | Observed | Verdict |
|---|---|---|
| 08ARwnYAG | ASP-403 2026-06-05→2027-06-04 mrr3.83 → ASP-544 2027-06-05→2028-06-04 mrr4.13. Day-after start, uplifted. | **MATCH** (clean baseline) |
| 06tCOTYA2 | ASP-077 2026-02-26→2027-02-25 (1 yr) → ASP-083 2027-02-26→**2039-02-25** (12 yr), propagated to Asset.LifecycleEndDate=2039. Start contiguity correct; term wrong. | **DEVIATION** — upstream PTC=12 (§5 GAP-1) |
| 08FcLaYAK | ASP-543 mrr557.94 → ASP-548 2027-06-11→2028-06-10 **mrr0**. Dates/qty correct. | **DEVIATION** — upstream $0 net (§5 G4) |
| 08LXfZYAW | ASP-561 2026-07-01→07-31 q100 mrr162.5 · ASP-568 2026-08-01→2027-06-30 q275 mrr162.5 · ASP-566 2027-07-01→2028-06-30 q275 **mrr0**. Periods tile **contiguously** (1-sec boundaries), **no overlap**. | **DEVIATION** — mrr=0 renewal (§5 G4) + stale Asset rollups (§5 G6); the bundle's "overlap" claim is **retracted** (§5 G5) |

**Nuance not in the draft (confirmed):** the native uplift mechanism is **entirely unused org-wide** — 0 `PriceRevisionPolicy` records; 0 ASPs with non-null `UnitPriceUplift` or `PriceRevisionPolicyId`; and `UnitPrice` is null on **all** 430,642 rows. All renewal MRR values are raw upstream-computed `Mrr`; the ASP layer is not the uplift owner (§5 GAP-3).

### Cancellation — VERDICT: MATCH (structure)
| Asset | Observed | Verdict |
|---|---|---|
| 08ARwoYAG (Generate → Renewal[$0] → Cancel) | ONE period only: ASP-404 2026-06-05→2026-06-10 q1 mrr0. Cancel = AA-000543546 Δqty−1. Asset Status=Installed, CurrentQty=0, CurrentMrr=0. | **MATCH** — no new period on cancel |

**Edge case corrected:** the draft's "cancel rolled back the just-created renewal period" is **unprovable** — the preceding renewal AA-000543545 was the org's ONLY zero-delta renewal (Δqty=0 AND Δmrr=0), `--all-rows` shows no soft-deleted period, and there are **zero** soft-deleted AssetActions/AssetStatePeriods and **zero** Rollback-subtype actions org-wide. So "a $0/no-op renewal never materialized a distinct period" is equally consistent. **Reframe** (§5 G1-ROLLBACK).

---

## 5. Gaps Requiring Fixes — Ranked

Verdicts reflect independent verification. REFUTED premises are dropped/downgraded per instructions.

| # | Sev (post-verify) | Scenario | Description | Evidence | Verdict | Recommendation |
|---|---|---|---|---|---|---|
| **GAP-1** | **HIGH** | Renewal | 06tCOTYA2 renewal produced a **12-year** period (ASP-083 2027-02-26→2039-02-25) vs a 1-yr prior; propagated to Asset.LifecycleEndDate=2039. | Independently re-queried: renewal source line **AAS-000000083 `PricingTermCount=12`** (vs AAS-000000077 PTC=1); TotalLineAmount 4649.4 = 387.45×12. ASP faithfully copied the source term. | **CONFIRMED** (root cause proven stronger than draft) | Fix **upstream** renewal term/date derivation (PTC unit-of-measure: 12 months read as 12 years), cf. SC-3297. Trace `Fortra_Create_Renewal_Quote` output. Re-derive Asset.LifecycleEndDate. NOT an ASP-engine bug. |
| **G4 / GAP-2** | **HIGH** | Renewal | Zero-priced renewal periods: 08FcLaYAK ASP-548 mrr0 (from 557.94); 08LXfZYAW ASP-566 mrr0. | Re-queried: MrrChange −557.94 / −162.5; **order lines carried $0 net BEFORE assetization** (OI 0000564346 net/total 0; OI 0000564406 NetUnitPrice=0/TotalPrice=0). Matches COLA repro (beSECURE / SECURE Email Gateway). | **CONFIRMED** | Route to the **SC-3350/SC-3346 COLA renewal zero-price** workstream. ASP is structurally correct (right dates/qty) — this is a **pricing-derivation** bug. Validate renewal MRR ≠ 0 before relying on ASP. |
| **G6 / GAP-4** | **MEDIUM** | Renewal+Upsell | 08LXfZYAW Asset CurrentQuantity=0 / CurrentMrr=0 while the period active today (ASP-561) is q100/mrr162.5. | Re-queried: Current 0/0/0; active-today period = ASP-561 (q100/mrr162.5); latest AssetAction TotalQuantity=**275** yet CurrentQuantity=0. Only stacked renew+upsell asset in org. | **CONFIRMED** (draft's proposed cause **refuted**: picking the future $0 period would give qty 275, not 0 — CurrentQuantity=0 is unexplained by any period/action total) | Investigate the current-state rollup on stacked renew+upsell. **Correction to draft:** the active period carries q100 (not q275); ASP-568/566 are future. SC-3506 guidance should specify **date-window selection** (StartDate≤date≤EndDate), not "latest period," which is ambiguous here. |
| **GAP-3** | **MEDIUM** | Renewal | Native uplift mechanism entirely unused: 0 PriceRevisionPolicy records; 0 ASPs with UnitPriceUplift/PriceRevisionPolicyId. | Re-queried: all counts 0; `UnitPrice` null on all 430,642 rows; positive control (Mrr!=null) returns all rows. | **CONFIRMED** | SC-3506 write-up must **not** attribute renewal uplift to native PriceRevisionPolicy/UnitPriceUplift here; Fortra computes COLA upstream and writes raw `Mrr`. Any design reading UnitPriceUplift/UnitPrice off the ASP is invalid in this org. |
| **G1-ROLLBACK** | **MEDIUM** | Cancellation | Draft asserts cancel "rolled back" the renewal period; mechanism is unprovable. | Re-queried: renewal AA-000543545 is the org's only Δqty=0 & Δmrr=0 renewal; `--all-rows`=1 period; **0 soft-deleted AA/ASP org-wide, 0 Rollback actions**. | **CONFIRMED (gap valid)** | Reframe to "renew-then-cancel left only the original closed period; hard-delete vs never-created is undetermined at n=1." Run a controlled non-zero renew→cancel test to disambiguate. |
| **G3 / GAP-6** | **LOW→MEDIUM** | All lifecycle | Lifecycle ASPs have SegmentType=null; migrated = Yearly. | Re-queried: null=921 / Yearly=429,721; all 26 lifecycle-asset ASPs null; **BUT** 110 non-migration ASPs are Yearly and 141 migration rows are null. | **PARTIALLY-CONFIRMED** (framing corrected) | State as "SegmentType is populated **inconsistently** (some Yearly, some null), driven by per-order config — NOT a clean lifecycle-vs-migration split." No repo code (incl. LKG) references SegmentType → forward-looking consistency risk only. |
| **G5** | **LOW (RETRACT)** | Renewal+Upsell | The bundle's "overlapping periods on 08LXfZYAW" is **false**. | Re-queried by StartDate: three periods tile contiguously with exact 1-second boundaries; overlap check False on all pairs; coverage = Asset lifecycle 2026-07-01→2028-06-30. | **CONFIRMED (retract the overlap claim)** | Retract "overlap" from Marc's write-up; replace with the real 08LXfZYAW defects (G4 mrr=0, G6 stale rollup). Note CreatedDate order ≠ StartDate order is normal for stacked transactions. |
| **G3-ZERO-CANCEL** | **LOW** | Cancellation | The single cancel has MrrChange=0 / TotalCancellationsAmount=0 — validates structure only, not credit economics. | Re-queried: TotalCancellationsAmount=0 on **every** row org-wide; only Generate migration rows carry negative economics. | **CONFIRMED** | Scope SC-3506 cancellation validation to **structure**; cross-reference **SC-3441** for cancellation credit pricing; add a non-zero-priced cancel test. |
| **G4-STATUS** | **LOW** | Cancellation | Cancelled asset stays Status=Installed (no terminal status) despite qty/mrr=0. | Re-queried: Status=Installed, CurrentQty=0, LifecycleEndDate 2026-06-10 (elapsed). "Obsolete" status exists but is not applied. | **PARTIALLY-CONFIRMED** (LKG impact corrected) | Native behavior, not a defect. **Correction:** production LKG reads **Asset.Quantity (=1 here)**, not CurrentQuantity, and gates the key path on **LifecycleEndDate**, not Status. So "rely on CurrentQuantity=0" would NOT protect the current code; use elapsed LifecycleEndDate and/or change the code to read the current period. |
| **G1 (open-ended EndDate)** | **DOWNGRADE HIGH→LOW** | Amendment | Draft: 08DFvvYAG "termed maintenance product" has null ASP EndDate = defect. | Re-queried & **REFUTED**: BoKS-NewMaintenance's only ProductSellingModelOption is **"One Time"/OneTime** (all 40 OrderItems OneTime); null EndDate is correct native behavior for OneTime; **~42% of all ASP rows (181,955) carry null EndDate**. | **PARTIALLY-CONFIRMED, core premise REFUTED** | **Do NOT** force a bounded ASP EndDate (would fight correct native behavior). Reframe as a **design question**: license expiration for OneTime maintenance can't come from the (correctly null) ASP EndDate — source it from the **Contract** (800WC00000S3fOLYAZ EndDate 2027-06-04, term 12) or a dedicated term field. |
| **G2 (no same-day split)** | **DOWNGRADE HIGH→INFO** | Amendment | Draft: same-day amendments produce no split, "contradicts the documented model." | Re-queried & **REFUTED as contradiction**: discriminator is **effective date vs asset start date**, not calendar day — 08MuWnYAK's Generate+Upsell were on the **same calendar day** yet it split (effective 04-01 vs 06-16); 08deyf/08deyg were both effective 06-29 (identical → one period). | **PARTIALLY-CONFIRMED, mislabeled** | **Document as an expected native exception** (effective date == start date → no distinct prior slice), not a defect. Ensure license-key logic handles the single-period case. |

---

## 6. License-Key (LKG) Dependency & Impact

The LKG analysis materially **lowers the real-world blast radius** of the ASP anomalies and corrects the draft's assumptions:

- **LKG does not read AssetStatePeriod directly** — 0 references across the 174 `Lkg*` classes. It reaches the latest state only **indirectly via Asset rollups**, and only in the **hardware key path**, which is currently **WIP/inert**.
- **Attributes consumed:** ASP.EndDate via `Asset.LifecycleEndDate`; ASP.Quantity via `Asset.Quantity`; `StartDate` is hardcoded `Date.today()` (not from ASP); expiration is sourced from the **UI payload today**, not the ASP.
- **Important correction to draft (G4-STATUS):** `LkgProcessorHardwareKeys` reads **`Asset.Quantity`** (still 1 on the cancelled asset), **not `CurrentQuantity`** (0). So the draft's "rely on CurrentQuantity=0" advice would NOT protect the code as written. The only cancellation signal the current path reads that actually moves is **`Asset.LifecycleEndDate`**. The only Status gate is an optional caller-supplied `statusFilter` in a **UI picker** (`LkgUiHardwareController.getAssets`) — the key-gen path applies no Status filter.
- **Risk if ASP is wrong (prospective, once the path is live):** null EndDate → perpetual key; 2039 EndDate → 12-yr instead of 1-yr entitlement; renew-then-cancel → latest ASP is expired/qty0. Today the path is inert, so these are **forward-looking** risks, not confirmed live key defects.

**Net:** the two HIGH gaps (GAP-1 2039 date, G4 mrr=0) are genuine data-integrity defects, but their *license-key* impact is (a) prospective and (b) mediated through Asset rollups, not direct ASP reads. Severity for the ticket should reflect data integrity + prospective LKG risk, not a proven live mis-issued key.

---

## 7. Caveats & Limitations

1. **Thin sample (confirmed exact).** The entire empirical basis is **16 live lifecycle AssetActions** (10 Upsells, 5 Renewals, 1 Cancellation); ~430k rows are bulk migration (Generate/Initial Sale). Only **1 FieldAmendment** and **0** Downsell/Cross-Sell/Upgrade/Downgrade/Swap/T&C. Renewals rest on ~2 clean cases (06tCOTYA2 has the 2039 anomaly). Cancellation is **n=1** and atypical (preceded by a $0 renewal). AC #2 ("across all scenarios") is only weakly satisfiable.
2. **Migrated vs lifecycle data.** SegmentType/EndDate patterns differ between the migration load and native runtime creation; conclusions about "expected" values must distinguish the two.
3. **Docs are SPA-rendered.** Non-overlap and exact EndDate-truncation contracts are inferred, not verbatim-documented. CPI formula wording is medium-confidence.
4. **Marc Debrey's actual SC-3506 write-up is not in the repo and there is no Jira MCP.** This review is an independent ground-truth reconstruction to check his findings against, not a line-by-line diff of his document.
5. **Provenance gaps.** `AssetActionSource.ReferenceEntityItemId` is null on the 06tCOTYA2 renewal, hampering source-line trace.

---

## 8. Peer-Review Disposition

**Disposition: SC-3506 NEEDS REWORK before close.** The investigation's core conclusion (native ASP mechanics are correct) is sound and validated, but the deliverable cannot be certified as-is.

**What Marc must ADD or CORRECT:**

1. **Retract the "overlapping periods on 08LXfZYAW" finding** (G5) — factually false; replace with the real 08LXfZYAW defects (mrr=0 renewal, stale Asset rollup).
2. **Reclassify the open-ended-EndDate finding (G1)** — BoKS-NewMaintenance is **OneTime**, so null ASP EndDate is correct; convert to a Contract-vs-ASP expiration-sourcing design question. Do not recommend forcing a bounded ASP EndDate.
3. **Reclassify the same-day "no split" finding (G2)** as an **expected native exception** (effective date == start date), documented in the answer — not a contradiction or defect.
4. **State the two HIGH defects as UPSTREAM, not ASP-engine, bugs:** the 2039 date (upstream `PricingTermCount=12`; fix at renewal term derivation, cf. SC-3297) and the mrr=0 renewals (upstream COLA zero-price; route to SC-3350/SC-3346). The ASP engine faithfully persisted bad inputs.
5. **Add the "native uplift unused" fact (GAP-3):** no PriceRevisionPolicy/UnitPriceUplift/UnitPrice anywhere; uplift is upstream-computed `Mrr`. The expected-behavior doc must not attribute uplift to native fields.
6. **Correct the LKG dependency section:** LKG reads `Asset.Quantity` and `Asset.LifecycleEndDate` (not AssetStatePeriod, not CurrentQuantity), and the hardware path is inert. Frame ASP anomalies as prospective/data-integrity risks. Specify **date-window** period selection, not "latest period."
7. **State the sample limitations explicitly** and generate the missing scenarios (Downsell/Cross-Sell/Upgrade/Downgrade/Swap/T&C, a clean full cancel, a non-zero renew→cancel) via `scripts/apex/setupSC3502Lineage.apex` + `f04_initiateRenewal.apex` before signing off AC #2.
8. **Reframe the renew-then-cancel edge case (G1-ROLLBACK)** as undetermined at n=1; disambiguate with a controlled non-zero renewal→cancel test.

Once items 1–8 are addressed, AC #1 and AC #3 are satisfied; AC #2 is satisfied for Upsell/Renewal/Cancel structure but should be flagged as unvalidated for the untested amendment subtypes.
