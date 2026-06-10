# SC-3360 — Perpetual Advanced Authentication SKU: Deep-Investigation RCA (supersedes prior README)

> Read-only deep investigation, FortraUAT, 2026-06-08. Re-done against the **live ACTIVE V9** pricing procedure (the prior RCA's Issue #1 analysis used the stale local **V1** XML). Each root cause was adversarially verified under multiple lenses; the corrected version is reflected below, not the original.

---

## Executive summary

Three distinct defects cluster on one product (`Advanced Authentication Modes`, `GS-GSE-NRPS-AAMP`, `01tWC00000DD11YYAT`, Perpetual / "One Time" / list $3,150). They have three different root causes, three different fix layers, and three different owners. None is a duplicate of the others.

| # | Severity | Root cause (corrected) | Fix layer | Confidence |
|---|---|---|---|---|
| **1** | PRIMARY | Pure **data/config gap**: no `AttributeBasedAdjustment` row for `{SFTP Server, On Premise, Non-Production}`. The ABA Override branch is structurally live for One-Time lines and **would persist** a matched override; it simply never matches. | config/data | High |
| **2** | LOWER | **Deterministic, provenance-keyed** incremental price-waterfall mis-seed: a duplicate-config One-Time line added to a container that already holds an identical line gets `NetUnitPrice` seeded to 0 by `PricingSettings` (seq 1). The −$3,150 is a *derived residue*, not an applied adjustment. SC-3345/SC-3347 net<list family. | combination | Medium |
| **3** | BLOCKER | **Re-activation of an order that already carries an in-flight decomposition plan**: the record-triggered flow re-fires a plain `submitOrder` (CurrentTransaction) → synchronous throw → rollback to Draft. Missing in-flight guard / amendment routing. Independent of #1/#2. | flow/process | High |

The single most important correction: **prior Issue #1 was analyzed on the stale local V1 XML** (≈14.8k lines, labeled "V1 Active"). The live active procedure is **V9** (the 9th `<versions>` block — lines 41155-46538 of `Data/sc3359/uat-pricing-extracted/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` — is the only one with `<status>Active</status>`; V1–V8 are Inactive). The V9 trace **confirms the missing-row conclusion** but **changes the mechanics** and **refutes the inherited SC-3359 "the override would be discarded anyway" hypothesis** that the foundation's `beSecureComparator` note asserted.

---

## Ground-truth corrections vs the prior RCA

1. **Stale V1 → live V9 (Issue #1).** The prior README/evidence files (`server-type-pricing.md`, `net-price-propagation.md`) reasoned over the stale local V1 force-app. Re-done against V9 (101 steps, ordered by true runtime = top-level `parentStep` sequence then child sequence, NOT XML document order). The missing-row *conclusion* survives; the procedure *write-back* description in the V1-based files is obsolete.

2. **The two contradictory prior files reconciled.** V9 has **two independent attribute mechanisms**:
   - **(a) the ABA Override path** — `AttributeBasedPrice` (seq 17.2) + `AttributeDiscountEntries` (18.2), gated by `ListOperation42` = `ItemContractAttributePasId IsNotNull AND ItemPricingSource != 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute = false`. **NOT** gated on `Has_Attribute_Adjustment__c` and **NOT** on `SellingModelType`. This is AA's path.
   - **(b) the AttributeValuePricing*Mode tier path** — `AttributeValuePricingUnitPriceMode28`/`Calculated31`/`TotalPrice34` (seq 12–14), gated on `Has_Attribute_Adjustment__c = true` + `Attribute_Tier_Pricing_Storage__c`. AA never uses this (0 tier-storage rows; flag = false on all 54 OI / 588 QLI).
   - `server-type-pricing.md`'s **conclusion** (missing row) is **confirmed**; its procedure mechanics were V1. `net-price-propagation.md` is **refuted** — it diagnosed branch (b), which AA does not use.

3. **The inherited SC-3359 "override gets discarded by the One-Time branch" hypothesis is REFUTED for Issue #1.** Verified directly in V9: `SubscriptionPricing74` (One-Time branch, seq 26.3) reads INPUT `NetUnitPrice <- InputUnitPrice` and writes ONLY `SubscriptionNetUnitPrice -> InputUnitPrice` and `TotalSubscriptionPrice -> TotalLineAmount`. It does **NOT** write `NetUnitPrice` or `ItemNetTotalPrice`. Across all 101 V9 steps, **no step copies `InputUnitPrice -> NetUnitPrice`** (the only Input/Net assignment is `DerivedPricing13` at seq 7.2, which goes `NetUnitPrice -> InputUnitPrice` and is gated `DerivedPricingAttribute=true`, off for plain AA). Therefore a matched ABA Override at seq 17 would **persist** on the One-Time line; it is not clobbered. SC-3359's real defect bites the `InputUnitPrice/TotalLineAmount/header-rollup` channel, **not** the per-unit `NetUnitPrice` that lands on the AA OrderItem. ⚠️ The foundation's own `beSecureComparator` field contains the opposite (wrong) sentence ("the fix MUST include making SubscriptionPricing74 read NetUnitPrice"); that sentence is **disregarded** — it contradicts direct V9 inspection.

4. **The "Override fired silently to 1575" counter-theory is dead (Issue #1).** The only two AA `net=1575` lines (`802WC00000MvwDOYAZ`/00017786, `802WC00000Mvx3ZYAR`/00017868) carry `Server Type = Production` (= rule 219's hash → would be 3150, not 1575). Both are migration data: `UnitPrice == NetUnitPrice`, CreatedDate 2026-05-06 by Marc DeBrey, 00017xxx series, `LastPricedDate=null`. The ABA Override has fired **zero** times on any live-engine-priced AA line.

5. **Issue #2 reclassified: deterministic, not a timing race.** The prior RCA (and the foundation's first pass) called it a "non-deterministic race, timing-correlated (20s spacing)." That framing is **refuted** by live data: on 00095353 all 6 OrderItems share `LastModifiedDate = 17:04:28` (one order-wide reprice) and the same waterfall run-suffix `:87207268135033`, yet the two order-level adds (created **7m38s apart**) both zeroed while the three converted lines priced correctly. A single deterministic run cannot be a "race," and 7m38s is not "tight-spacing batch." The discriminator is **operation order / provenance**, not timing.

6. **Issue #2: the prior "QLineItemId=null = order-level add zeroes" discriminator is FALSIFIED.** On 00095355 the zeroed OrderItem has a **non-null** `QuoteLineItemId` and inherited $0 from a quote line that was already net=0/TLA=3150/TP=0. The real unifying signature is **`NetUnitPrice=0` while `TotalLineAmount=3150`** (list channel survives), occurring at quote OR order.

7. **Issue #3 over-confidence resolved both ways.** 00095293 is **not** transient/self-recovered (prior adversarial doubt) — it is frozen in the identical Draft/Decomposed/`ActivatedDate=null` state with a single fully-healthy line (net=3675, no $0). This **proves $0 lines are not necessary** → fixing #1/#2 will NOT clear the Activate. But the prior "user reopened, appended lines 5/6, then a SECOND submitOrder failed" causal chain for 00095353 is **not provable from OrderHistory** and is corrected below.

---

## Issue #1 — Server Type = Non-Production does not lower Net Unit Price  🔴 PRIMARY

**Root cause (HIGH).** Pure data/config gap. The AA product has exactly **2** `AttributeBasedAdjustment` Override rows on decision table `0lDa50000007BEuEAM` (schedule `84Xa50000010nWQEAY`, Active; both `SellingModelType=OneTime`, `AttributeCount=3`):
- rule 219 (`12DWC00000JupTQ2AZ`): `{SFTP Server, On Premise, Production}` → Override **3150**
- rule 220 (`12DWC00000JupTR2AZ`): `{Remote Automation Agent, On Premise, Non-Production}` → Override **1575**

The decision table matches by **exact `AttributeAdjConditionsHash` equality** across all 3 attributes (`DecisionTable.Metadata` `ConditionCriteria '1 AND 2 AND 3 AND 4 AND 5 AND 6'`, `SourceObject=AttributeBasedAdjustment`, `Status=Active`, `RefreshStatus=Completed`, `LastSyncDate 2026-06-06`). The user keeps default Feature = SFTP Server and flips only Server Type → `{SFTP Server, On Premise, Non-Production}`, whose hash matches **neither** row (the two rules differ on **both** Feature and Server Type, so a single-attribute flip can never land on either). `Get` returns nothing → `AttributeBasedPrice` (seq 17.2) leaves `NetUnitPrice` unchanged at list $3,150.

**Why this is the *complete* cause (procedure verified on V9):**
- The ABA Override branch is **structurally live** for One-Time/Perpetual lines — `ListOperation42` has no `SellingModelType`/OneTime exclusion (`/tmp/v9.xml` lines 2584-2613).
- When a row matches, `AttributeBasedPrice` writes `NetUnitPrice -> NetUnitPrice` and `Subtotal -> ItemNetTotalPrice` **directly** (V9 lines 667-764 / 4386-4455 in the active-block extract), and that value **persists**: `SubscriptionPricing74` (One-Time, seq 26.3) operates on the `InputUnitPrice/TotalLineAmount` channel, not `NetUnitPrice`; `QuantityPrice55` (seq 21.2) recomputes `ItemNetTotalPrice = NetUnitPrice * Qty` from the current (overridden) net before the subscription branches; and no step copies `InputUnitPrice -> NetUnitPrice`. So a One-Time AA line's `NetUnitPrice` is frozen after the last line-level discount/override (latest seq 22).
- **beSECURE proof of the mechanism:** comparator `01tWC00000DD10zYAD` is TermDefined and fires the SAME decision table — its `Has_Attribute_Adjustment__c=true` lines persist Override values (net=875/6221/206/1652 over list=0). It works because TermDefined (seq 24) reads `NetUnitPrice -> NetUnitPrice` symmetrically. AA fails purely because no row matches, not because the One-Time route discards it.

**Confidence / adversarial outcome.** HIGH. Three lenses (v9-step-ordering, historical-data, sc3359-equivalence) all returned **not refuted**, `residualConfidence=high`. The historical lens added that the Override has fired **zero times** across all 54 OI + 588 QLI; the 19 post-migration (genuinely engine-priced) AA OrderItems are only ever net=3150 (passthrough) or net=0 (the #2 zeroing) — exactly what the missing-row theory predicts and inconsistent with any "computed-then-clobbered" mode.

**Minimal complete fix.** **Config/data only — Option (B): add the one missing ABA row** for `{SFTP Server, On Premise, Non-Production}` (Override + `AttributeBasedAdjRule` + 3 `AttributeAdjustmentConditions`) on `01tWC00000DD11YYAT`, ProductSellingModel "One Time", schedule `84Xa50000010nWQEAY`, `AttributeCount=3`, at the business-confirmed value; then refresh decision table `0lDa50000007BEuEAM`. **No procedure code change.** The SC-3359 SubscriptionPricing74 fix is **NOT required** and would not by itself fix #1 (no row → nothing to preserve).
- **Strongly recommended Option (A) variant if Non-Production is a uniform discount:** replace the brittle per-combo 3-attribute Overrides with a **single adjustment keyed only on `Server Type = Non-Production`** (percentage or override) so it applies across every Feature × Deployment — eliminates the recurring missing-row class of bug (today only 1 of N Feature combos has any Non-Production row).

**Dependencies.** SC-3359: **symptom-share only, NOT a shared fix or root cause** — do not co-fix (wrong layer). SC-3143: suggested parent.

**Residual caveat (read-only).** The override gate also requires `ItemContractAttributePasId IsNotNull`, a runtime engine variable not stored on the OrderItem; data alone cannot 100% distinguish "no hash row" from "PasId null on One-Time lines." beSECURE fires through the **same gate/table**, making PasId-null unlikely; final closure is the post-fix live reprice (see Open questions).

---

## Issue #2 — $0.00 Net on duplicate AAM lines  🟡 LOWER

**Root cause (MEDIUM).** The −$3,150 is a **derived residue**, not an applied adjustment: `OrderItemAdjustmentLineItem WHERE OrderItem.OrderId='801WC00000kGxGCYA0'` = **0 rows**, so `TotalAdjustmentAmount = ListPrice*Qty − NetTotalPrice = 3150 − 0 = −3150`. The only event to explain is `NetUnitPrice` becoming 0.

**Exact emitter (pinned on V9):** `PricingSetting` (step 1, `actionType=PricingSettings`, top-level/ungated; OUTPUTs `PriceWaterfall -> price_water_fall`, `NetUnitPrice -> NetUnitPrice`, `Subtotal -> ItemNetTotalPrice`). It materializes the line's net from the platform-managed price-waterfall and is the **only** `NetUnitPrice` writer that runs *and* can surface 0 for a clean AA One-Time line. Adversarial correction folded in: V9 *does* contain two literal/conditional-zero net writers the first pass missed — `FormulaBasedPricing2` (seq 4, formula = literal 0, gate `ItemIsDerived__std=true`) and `FormulaBasedPricing1` (seq 6, tier-formula yielding 0 for non-Premier/Standard/Professional, gate `AttributeDefinitionCode='MTD'`) — but **both are gated OFF for AA** (AA runs non-derived and has no MTD attribute), so the emitter for this SKU remains `PricingSetting` (seq 1). All other config-defined net writers are gated off or pass-through (0 `BundleBasedAdjustment` rows; no Partner/Manual/Volume data; TermDefined/Evergreen skipped). `QuantityPrice55` (seq 21) only *propagates* the already-0 net; the SUM/dedup theory (`AggregatePrice96`) is refuted (it sums `ItemNetTotalPrice` into a *group* field, never `NetUnitPrice`).

**Why some duplicates zero and others don't — DETERMINISTIC, by provenance (corrected).** The discriminator is **operation order**, not timing:
- The **first-priced occurrence** of an identical-config One-Time line in a container survives.
- A **subsequently-added identical** line gets `NetUnitPrice` seeded to 0 by `PricingSettings` on the next reprice, because the platform price-waterfall for the new duplicate is materialized as 0.
- Holds at **both** Quote level (00095355's 2nd quote dup, zeroed) and **Order** level (00095353's order-adds onto an order already carrying 3 converted AA lines).
- This single rule unifies all 4 true-Issue-#2 zeros and explains the per-order counts: 00095353 = 3 converted healthy + 2 incremental adds zeroed (**2/5**); 00095354 = 3 converted, 0 incremental adds (**0/3**); 00095355 = quote had 1 first + 1 incremental dup (the dup zeroed) → both converted preserving state (**1/2**).
- **Killer evidence the "race" framing is wrong:** on 00095353 all 6 lines share `LastModifiedDate 17:04:28` (one order-wide Reprice All) and run-suffix `:87207268135033`; the two order-adds were created **7m38s apart** yet both zeroed; the zeroed and healthy lines are **byte-identical** in attributes (`{SFTP Server, On Premise, Non-Production}`, all `IsPriceImpacting=true`), product, PSM, PBE, qty. A single deterministic run with byte-identical inputs producing divergent outputs ⇒ the divergence lives in the per-line **input state** (the seeded price-waterfall for the later duplicate), not stochastic timing.

**Confidence / adversarial outcome.** MEDIUM root cause overall. The `v9-step-identification` lens: **not refuted** (emitter confirmed; one false universal claim in the prior enumeration corrected). The `determinism` lens: prior "non-deterministic race" framing **REFUTED** and reclassified to deterministic-by-provenance, `residualConfidence=high` on the corrected characterization. The emitter sits in a **platform-managed BKM** with no editable logic, which is why I hold the overall root-cause confidence at MEDIUM (the *internal* trigger inside the platform incremental-reprice/waterfall materialization is not directly observable read-only).

**Minimal complete fix (combination):**
1. **Defense-in-depth / scope-complete (primary):** adopt SC-3347's middleware mapping (`extendedAmount <- net`, not `TotalLineAmount`) so the Workday-sync break is neutralized for ANY net<list line; add the SC-3347 Salesforce-side submit guard (`Fortra_Order_Submission_Check` / `Order_Submit_Validation__mdt`) that blocks submit when any line has `NetUnitPrice=0` with non-zero `TotalLineAmount`.
2. **Upstream root:** because it is **deterministic and reproducible** (re-add an identical AA line to a container that already has one → it zeros), file it as a **reproducible** Salesforce RLM / Revenue Cloud platform case (NOT a flaky race) and build a regression test from the repro. Optionally add a **late defensive procedure guard**: for One-Time lines, when `NetUnitPrice=0` AND `TotalLineAmount>0` AND no adjustment record exists, re-seed `NetUnitPrice` from `InputUnitPrice/ListPrice`.
3. **Do NOT** add an ABA/decision-table row for #2 — that is Issue #1's fix and is orthogonal (zeroed and healthy lines are attribute-identical).
4. **Do NOT** present "space the adds out / single final Reprice All" as a fix — it is disproven (the 00095353 order-level zeros already occurred under exactly one final order-wide Reprice All).

**Dependencies.** SC-3345 (owns the why-net-zeroed RLM pricing question; the −3150/net<list family root); SC-3347 (RESOLVED — owns the Workday-sync break; its middleware + SF guard is the scope-complete symptom fix; lists 00095353 as a recurrence); SC-3359 (sibling net-not-applied family; distinct mechanism); SC-3308 (precedent that RLM async pipelines have intermittent failures — corroborative only).

---

## Issue #3 — "Order Submission to Revenue Orchestrator" fails on Activate  🟠 BLOCKER

**Root cause (HIGH).** A flow/process defect, independent of pricing. The active record-triggered flow **`Order_Submission_to_Revenue_Orchestrator`** (V2 Active, ApiVersion 64, `triggerOrder=200`, after-save on Order Update where `Status=Activated`) looks up `AppUsageAssignment(RevenueLifecycleManagement)` and, on the single decision "Is Revenue Cloud Record?" (which only checks the usage-assignment Id is non-null — **no pricing condition, no in-flight-plan guard, no amendment routing**), unconditionally calls the standard `submitOrder` with `flowTransactionModel=CurrentTransaction`, `orderId=$Record__Prior.Id`. Re-activating an order that **already carries an in-flight decomposition plan** re-fires a plain (non-amendment) `submitOrder` against that in-flight plan → synchronous throw → `CurrentTransaction` rolls the whole activation save back → order stays Draft. The supported way to add/change lines on an in-flight order is the **amendment / supplemental (change-order)** path (`initiateAmendment` / Place-Supplemental-Transaction), which this flow never invokes.

**Evidence (live, 2026-06-08).**
- 00095353 (`801WC00000kGxGCYA0`): Draft / CompletedWithPricing / `ValidationResult=null` / Decomposed / `ActivatedDate=null`, LastModified 17:04:28.
- One STFR `1FjWC000006Vegr0AC`: `Status=Fulfilling`, `PlanExecutionStatus=InProgress`, `DecompositionStatus=Completed`, `PreviousRequestId=null`, created 16:38:40 (first-pass decomposition). 4 FulfillmentOrders + 4 FOLIs (the original 4-line plan; appended lines absent). Single OrderAction Type=Add — **no amendment STFR/action anywhere**.
- **$0-independence (decisive, multi-order):** of the 8-order anomalous cohort (`OrchestrationSbmsStatus=Decomposed AND Status=Draft`: 00095353, 00095293, 00095316, 00095274, 00004790, 00004781, 00004815, 00004810), **6 have ZERO $0 lines** (min line price > 0; e.g. 00095293 single line net=3675; 00004781 net=188000); only the anchor 00095353 has a $0 line; 00004815 has no OrderItems. Fully-healthy-priced orders are frozen in the identical stuck state ⇒ **fixing #1/#2 will NOT clear the Activate.**
- **Shared signature:** all 8 carry an in-flight STFR `Status=Fulfilling / PlanExecutionStatus=InProgress / PreviousRequestId=null`. Org-wide, **0 of 54,943+ Fulfilling/Fulfilled STFRs** have `PreviousRequestId` populated ⇒ the supported amendment/supplemental re-decompose has never executed in this org. No `RevenueTransactionErrorLog` references the order ⇒ synchronous throw rolled back (the "Error ID" is a platform SBMS reference, not a stored message).
- **Not SC-3308:** SC-3308 v21's `Reprice_Order_Before_Activate` lives in the `Fortra_Quote_to_Order_Conversion` screen/wizard flow (fires only on auto-activate during quote→order conversion, addressing a `CompletedWithoutPricing` pre-pricing race). It never touches the record-triggered re-activate path and provides no in-flight-plan guard. **Related-to, not duplicate-of.**

**Confidence / adversarial outcome.** HIGH on the core conclusion and on the dependency answer (separate fix required; independent of #1/#2). Two narrative corrections from the mechanism lens (`residualConfidence=medium` there) and the dependency lens (`high`):
- **(A) The 00095353 "second submitOrder after appending lines" chain is NOT provable from OrderHistory.** The order has exactly one committed Status cycle: Draft→Activated (16:38:18) → Activated→Draft (16:43:20), which occurred with the **original 4 healthy lines**, BEFORE lines 5/6 were appended (16:44:03 / 16:51:41). There are **zero** committed Status transitions after 16:44. The failing re-activation left no history row (consistent with a pre-commit synchronous throw bumping LastModifiedDate to 17:04:28). Also, the STFR (created 16:38:40) **survived** the 16:43:20 rollback — so even the **first** activation reverted to Draft while decomposition committed asynchronously. A clean 4-line first activation reverting to Draft (rather than reaching Order Complete) is itself anomalous and is **not fully explained**.
- **(B) The 8-order cohort is not mechanistically uniform.** OrderHistory shows ≥2 sub-paths to the same end-state: (i) Draft→Activated→Draft, never completed (00095353, 00095293, 00095316); (ii) Draft→Activated→Order Complete→…→Draft, fully completed (even Provisioned, e.g. 00004781) then manually reopened hours later. Group (ii) is the genuine "re-submit of an already-completed/decomposed order"; group (i) got stuck via a first-activation rollback whose trigger is unproven. Accurate statement: **all 8 share the in-flight-STFR + Draft END STATE**, reached by ≥2 paths. Minor precision: 00095293's STFR shows `AssetizationStatus=NotStarted` (not all Completed), but the load-bearing signature (`Fulfilling + InProgress + PreviousRequestId=null`) holds for all 8. Also, for 00095293 the line was created/modified, not appended — so the precise trigger is **"Status→Activated on an order that already has an in-flight plan,"** regardless of whether lines were added/modified/unchanged.

**Minimal complete fix (flow/process; SEPARATE from #1/#2). Owner Nir Kailash (sibling of SC-3308).**
1. **Guard the re-activation against the generic condition** "Status→Activated on an order that already has an in-flight `SalesTransactionFulfillReq` (`Status=Fulfilling`/`PlanExecutionStatus=InProgress`, `DecompositionStatus=Completed`)": either (a) **block** the transition with a clear custom error pointing the user to the amendment/change-order flow (replacing the silent CurrentTransaction rollback toast), or (b) **route** appended/changed lines through `initiateAmendment` / Place-Supplemental-Transaction so they decompose into the existing plan and populate `PreviousRequestId`.
2. **Decommission** the reopen-Draft + bare-re-Activate UX for already-decomposed orders; modify-after-activate must go through the amendment path.
3. **Separately investigate** the unexplained **first-activation rollback** on group-(i) orders (a pure re-submit guard would not address it).
4. **Remediate** the 8 already-stuck orders (manual STFR cleanup vs amendment adoption).

**Dependencies.** SC-3308 (sibling, same flow family, distinct trigger; co-own under Nir); SC-3347 (RESOLVED; Workday-side analogue of the $0 lines, but #3 is independent of $0); SC-3345 (#2 cause ownership); SC-3143 (suggested parent).

---

## Cross-issue fix plan & sequencing

The three are independent in *cause* but interact in *user experience* (you can't cleanly Activate 00095353 until both the pricing and the activation paths are sound). Recommended sequence:

1. **Issue #1 — config/data, fastest, highest business value (do first, in parallel with #3 design).**
   - Get business sign-off on the Non-Production value/rule shape (uniform Server-Type % vs per-combo). Then load the row (Option B) or the single Server-Type adjustment (Option A), refresh decision table `0lDa50000007BEuEAM`, and run the post-fix verification reprice.
   - **No dependency on SC-3359** — explicitly do *not* bundle the SubscriptionPricing74 flip into #1.

2. **Issue #3 — flow/process, BLOCKER for end-to-end (do in parallel with #1; needed before any Activate-to-Workday demo).**
   - Owner Nir Kailash. Build the in-flight-plan guard / amendment routing in `Order_Submission_to_Revenue_Orchestrator`. Coordinate with SC-3308 (same flow family) to avoid double-guarding the convert path. Plan the 8-order cleanup.
   - **Independent of #1/#2** (proven by the 6 healthy-priced stuck orders).

3. **Issue #2 — pricing platform, deepest, do last / route to SC-3345 + SC-3347.**
   - Symptom-side (scope-complete) fix ships with the SC-3347 middleware mapping + SF submit guard (largely RESOLVED already). Cause-side belongs to SC-3345 / a reproducible Salesforce RLM platform case for the incremental-waterfall mis-seed; optional late defensive procedure re-seed.
   - **Sequencing note:** the SC-3347 submit guard (#2 defense) and the SC-3360 #3 in-flight guard both sit on the activation path — coordinate so the two guards compose (block-on-$0 vs block-on-in-flight-plan) rather than conflict.

**Dependency summary on the named tickets:**
- **SC-3359** → #1: symptom-share only; its SubscriptionPricing74 fix is real for partner/header totals but **does not** touch the per-unit AA net. Not a shared fix.
- **SC-3345** → #2: owns the net-zeroing cause (RLM waterfall). **SC-3347** → #2 symptom (Workday) — RESOLVED, provides the scope-complete mapping + guard.
- **SC-3308** → #3: sibling flow fix, different trigger; v21 reprice-before-activate does not cover manual reopen + re-Activate.
- **SC-3143** → suggested parent for all three.

---

## Updated acceptance criteria

**Issue #1 — Server Type drives net price (config/data)**
- [ ] Business sign-off on the Non-Production rule shape (uniform Server-Type adjustment vs per-Feature/Deployment) and value.
- [ ] ABA row(s) created for `{SFTP Server, On Premise, Non-Production}` (or single Server-Type adjustment); decision table `0lDa50000007BEuEAM` refreshed (`RefreshStatus=Completed`).
- [ ] **Post-fix live reprice** on a `{SFTP Server, On Premise, Non-Production}` One-Time line: `NetUnitPrice` drops to the override value AND **persists** on the OrderItem; `Has_Attribute_Adjustment__c` flips true; a `{…, Production}` line still prices $3,150. (This also closes the residual PasId-null caveat.)
- [ ] **No** `Rev_Mgmt_Default_Pricing_Procedure` code change required (confirm SubscriptionPricing74 untouched).

**Issue #2 — duplicate AAM lines price correctly**
- [ ] Reproduce deterministically: add an identical AA line to a container already holding one → confirm the second zeroes (`NetUnitPrice=0`, `TotalLineAmount=3150`, 0 `OrderItemAdjustmentLineItem`).
- [ ] SC-3347 middleware mapping (`extendedAmount <- net`) + SF submit guard (block on `NetUnitPrice=0 & TotalLineAmount>0`) in place and exercised.
- [ ] Reproducible Salesforce RLM platform case filed (NOT as a flaky/intermittent race); regression test built from the repro.
- [ ] After cause fix, re-priced duplicate lines show `Net=List` with no derived −$3,150.

**Issue #3 — Activate of an already-decomposed order is safe**
- [ ] Re-activating an order with an in-flight STFR is **guarded** (blocked with a clear message OR routed via `initiateAmendment`), not silently rolled back.
- [ ] Modify-after-activate goes through the amendment path; the new STFR populates `PreviousRequestId`.
- [ ] A healthy already-decomposed order (e.g. 00095293-shaped, no $0) activates/amends cleanly — demonstrating independence from #1/#2.
- [ ] First-activation-rollback on group-(i) orders investigated and explained.
- [ ] The 8 stuck orders remediated.

---

## Open questions (mostly require a write/Simulate; out of read-only scope)

1. **Issue #1 business rule:** is Non-Production a uniform discount (→ single Server-Type adjustment, Option A) or per-Feature/Deployment (→ per-combo rows, Option B)? Drives the fix shape.
2. **Issue #1 post-fix verification** (needs a write): after loading the row + refresh, live-reprice a `{SFTP, On Prem, Non-Production}` One-Time line to confirm the override fires AND persists on the OrderItem — definitively closes the `ItemContractAttributePasId`-null residual caveat.
3. **Issue #2 internal trigger** (needs Debug Pricing / waterfall trace on a controlled duplicate-line repro): confirm `PricingSettings` is reading a 0-net waterfall for the later duplicate and identify the platform condition that materializes it as 0.
4. **Issue #3 live log** (needs a controlled non-prod re-activate): capture submitOrder's exact errorCode/submitStatus to convert the in-flight-block mechanism from strongly-inferred to directly-observed.
5. **Issue #3 first-activation rollback:** why did the clean 4-line first activation of 00095353 (and group-(i) peers) revert to Draft instead of reaching Order Complete, while the STFR committed asynchronously? Not explained by the re-submit mechanism alone.
6. **Issue #3 cleanup:** can the amendment path adopt the 8 stuck orders, or do their in-flight STFRs need manual cancel/re-create?
7. **GUARD vs ROUTE** decision for #3 (hard-block with message vs full amendment routing) — confirm with Nir Kailash.
