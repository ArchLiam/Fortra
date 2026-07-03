# SC-3473 "Issue Deleting a Quote Group" — Reverification vs live FortraUAT + Roadmap
Date: 2026-07-02 · Org: FortraUAT (`liam.jeong.c@fortra.com.uat`) · Read-only reverification (no deploys/DML)

## 1. The knowledge on file (prior RCA)
- **Symptom:** Clicking **Delete Group** on a quote group throws the toast
  *"Your quote was not updated. Cannot invoke Object.toString() because the return value of java.util.Map.get(Object) is null."*
- **Nature of the throw:** a **native managed RLM/Revenue-Cloud NPE** (JVM JEP-358 helpful-NPE) thrown inside the
  Place-Sales-Transaction save+force-reprice engine — **NOT custom Apex** (Apex NPEs read "Attempt to de-reference a
  null object" and never name `java.util.Map`; not in ApexLogs).
- **Root DATA trigger:** the to-be-deleted group contained a **TermDefined/Annual line with `EndDate=NULL` +
  `PricingTermCount=NULL`**. That malformed line is produced by **SC-3420** — the *guarded TermDefined Proration
  writer* (which stamps `PricingTermCount`) was deleted from the pricing procedure in the V11→V12 rework. Same defect
  family as SC-3420 / SC-3411 / SC-3406 / SC-3415.
- **Fix that was applied:** re-add the 3-step guarded writer sub-tree → **deployed + validated on V16, 2026-06-29**;
  the repro quote went `SaveFailedOrIncomplete → CompletedWithPricing`.
- **Second, independent prong:** Salesforce platform case for the *unguarded native NPE* (raw exception + no header
  rollback) — the true fix for the hard "quote was not updated" failure.

## 2. Reverification against live FortraUAT (today)

### 2a. The specific repro quote is HEALED ✅
| Item | Live value |
|---|---|
| Quote `0Q0WC000002U2020AC` "Test Wren - Order Processing" | Status=Accepted, **CalculationStatus=CompletedWithPricing** (was SaveFailedOrIncomplete) |
| Abstract line `0QLWC000003jN8P4AU` (the malformed one) | SellingModelType=TermDefined, **EndDate=2027-06-25**, **PricingTermCount=1**, SubscriptionTerm=1, PeriodBoundary=Anniversary |

→ The exact instance in the ticket will **no longer reproduce** the NPE. The 6/29 fix reprice healed the line.

### 2b. BUT the root-cause fix is MISSING from the currently-active version ❌ (REGRESSION)
Active pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` is now **V21** (ESDV `9QBWC0000000oWH4AY`, Status=Active,
owner **Nir Kailash**, last edited **2026-07-01 20:17Z**). A **V22 draft** also exists (Liam, 6/30). The 6/29 fix
was on **V16**.

Per-version presence of the guarded TermDefined proration writer (parsed from the live MDAPI retrieve of all 22 versions):

| Versions | `ProrationTermDefined` writer | Proration actions | Meaning |
|---|---|---|---|
| V1–V11 | (original naming) | 2 | TermDefined proration present |
| V12–V15 | **absent** | 1 | SC-3420 breakage introduced |
| **V16** | **present** | 2 | SC-3473/SC-3420 fix (6/29) |
| V17–V19 | **absent** | 1 | regressed |
| **V20** | **present** | 2 | COLA V16→V20 reconcile patch |
| **V21 (ACTIVE)** | **ABSENT** | 1 | ⚠️ fix lost again |
| V22 (draft) | absent | 1 | would re-ship the bug if activated |

**The guarded writer exists in only V16 and V20. It was NOT carried forward into Nir's V21** (the same drop that
happened in V20 before it was patched). Because `QuoteLineItem.PricingTermCount` is platform read-only, only an engine
Proration writer can set it — so **V21 structurally cannot stamp PTC on TermDefined lines.**

### 2c. Live behavioral proof V21 does not stamp PTC
Last 7 days, TermDefined QuoteLineItems: **93 of 114 (82%) have null `PricingTermCount`.** Breaking down the nulls:
- **17 are fully configured** (PeriodBoundary + SubscriptionTerm + EndDate all set) yet null PTC — these are exactly the
  lines the guarded writer *should* stamp. The most recent was **created & modified TODAY (2026-07-02)** under active V21
  (Cobalt Strike `0QLWC000003lizx4AA`, Accepted).
- 19 have null PeriodBoundary and 32 have null SubscriptionTerm (the guard correctly skips these by design).

By contrast, all **21 lines that DO have PTC** were last repriced **6/29–7/01 during/just-after the V16/V20 window**;
PTC persists once stamped, so they retain it even through later V21 reprices. The 6/30 V21 activation is the clean
dividing line.

### 2d. Retrieve freshness validated
The MDAPI retrieve reflects runtime canvas edits: V21 carries the **K-01 canvas fix** (extra `NetUnitPrice`/Stamp-Base-Filter
criterion, StampBase refs 6 vs 5 in V16/V20), confirming the retrieved V21 includes the 6/30 canvas fixes and Nir's
7/01 edit — i.e. the "writer absent" reading is current, not stale.

### Conclusion
The specific ticket instance is fixed, but **the SC-3420/SC-3473 root condition is actively regenerating in production
pricing (V21)**: new fully-configured TermDefined lines are being created with null PTC right now. Any new quote whose
deleted group contains such a malformed TermDefined line can re-throw the native Delete-Group NPE. **The durable fix must
be re-applied to the active V21.**

## 2e. SHARPENED ROOT CAUSE + CAPACITY CONSTRAINT (added after "element limit ~129" heads-up)
The V21 regression is not a plain deletion — it's a **broken merge**. Nir folded the TermDefined proration into the
Evergreen proration container (`EvergreenanytimeprorationfilterLinelevel`, seq 27), almost certainly to stay under the
**~129 pricing-procedure element ceiling** (V21 = 128 elements: 64 BKM + 32 AdvancedListFilter + 32 ListGroup). The merge
fails two ways:
1. **Guard filters TermDefined out.** `ListOperation85` conditionLogic `(1 AND 2 AND 3) OR (4 AND 3)` admits TermDefined
   only via `(4 AND 3)` = `SellingModelType='TermDefined' AND itemTransientEndDate IsNotNull`. `itemTransientEndDate` is a
   **context transient that no procedure step writes** (0 writers in V16/V20/V21) and is **null for TermDefined in the
   reprice/save path** → TermDefined lines never enter the container → `PricingTermCount` never stamped.
2. **Shared BKM can't serve both selling models.** The Proration BKM input `EffectiveTo = itemTransientEndDate` is right
   for Evergreen (anytime) but null for TermDefined (which needs the real EndDate). One input mapping can't be both — which
   is exactly why V16/V20 kept **two** writers.

`ProrationMultiplier → PricingTermCount` output IS still present on the merged BKM; it just never receives TermDefined lines.
**Consequences for the fix:**
- There is **no net-zero in-procedure lever**: the transient can't be hydrated by a step, and the merged BKM can't be made
  to prorate both models from one `EffectiveTo`.
- A correct restore needs a **dedicated TermDefined writer = 3 elements** (ListGroup + AdvancedListFilter + Proration BKM,
  guarded `SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull`,
  BKM `EffectiveTo=EffectiveTo`). Against ~1 element of headroom → **capacity must be reclaimed first.**
- The generic "List Container" churn (incl. "Copy 1 of / Copy 1 of Copy 1 of List Container 8") was checked and is
  **functional** (Services/Software/Subscription totals) — not free deletions. Reclamation needs a real element audit.

**This is now a capacity + ownership problem, not a drop-in re-add.** The writer has been dropped 3× (V12, V17–19, V21)
under element pressure by a co-owned, churning procedure — that's the durable organizational root cause.

## 2f. Element-reclamation audit (read-only, 2026-07-02) — outcome: reclamation NOT needed
Mapped all 128 V21 elements (48 top-level: BKMs, Formula, ListGroup containers). Findings:
- **No fully-dead container.** Dead-output scan (fields written but never read downstream) flagged only final persist-to-field
  outputs (`Base_Price__c`, `Pre_Partner_Price__c`, `PartnerUnitPrice`, `PricingDate`) — intentional, not reclaimable.
- **"Copy 1 of / Copy 1 of Copy 1 of List Container 8"** (seq 35–37) are FUNCTIONAL — they compute
  `Total_Services__c` / `Total_Software__c` / `Total_Subscription__c` (distinct product-type totals). Not deletable.
- **Two "Aggregate Price" BKMs** (seq 45, 46) are NOT duplicates — one aggregates `TotalLineAmount→Subtotal`, the other
  group-aggregates `ItemNetTotalPrice→ItemGroupSummarySubtotal`. Both functional.
- **The decisive find:** the proration/PTC cluster (seq 27–30) sets `PricingTermCount` via **constant-assignment**
  (`AssignmentElement`), not only via Proration BKM — which makes the fix net-zero (see Prong A). PTC constants:
  `OneTimePricingTermCountConstant`=0, `EvergreenPricingTermCountConstant`=1, `PricingTermCountValueOneConstant`=1.
→ Because the fix is net-zero, the element ceiling is a non-issue for THIS change. It remains a standing risk for future
  procedure work (the proc is at 128/~129), so the process guard in Phase 2 still applies.

## 3. Solution — prongs (re-prioritized for the capacity constraint)

**Prong B — Salesforce platform case (DO FIRST; capacity-independent, highest value).** File a case for the unguarded
native NPE: the RLM engine leaks a raw `Map.get→null→.toString()` JEP-358 exception during Delete-Group force-reprice and
does **not** roll back the quote header ("quote was not updated"). This is the only fix that removes the *hard failure* for
any null-key edge, needs no procedure element budget, and is unblocked today. Attach: the repro dossier, the finding that
the throw is native (not in ApexLogs), and that `PricingTermCount`/`itemTransientEndDate` are null on the deleted line.

**Prong A — Restore TermDefined PricingTermCount (durable data fix). ✅ NET-ZERO ELEMENTS — no reclamation needed.**
The element audit (§2f) found the cheap lever: PricingTermCount is set across the proration cluster **by assigning a constant
variable, not only by a Proration BKM**. seq 28 (OneTime) assigns `OneTimePricingTermCountConstant` (=0); seq 29 (Evergreen,
no proration) assigns `EvergreenPricingTermCountConstant` (=1). Every healed TermDefined line observed has **PTC=1**. So:
- **THE FIX (net-zero): broaden seq 29's filter (`ListContainer92` → `ListOperation93`) to also admit TermDefined.**
  Current `conditionLogic = 1 AND (2 OR 3)` over `[SellingModelType=Evergreen, AllowPartialProrationPeriods=false,
  itemTransientEndDate IsNull]`. Add **criterion 4 = `SellingModelType Equals 'TermDefined'`** and change conditionLogic to
  **`(1 AND (2 OR 3)) OR (4 AND 3)`** (reuse criterion 3 = `itemTransientEndDate IsNull`). The existing `AssignmentElement`
  then stamps `PricingTermCount = 1` on exactly the broken cohort — TermDefined lines with a null transient (the ones seq 27
  filters out). **Zero new canvas elements** (criteria are sub-elements of the filter step); count stays 128, under the ceiling.
  It mirrors seq 27's own `(4 AND 3)` TermDefined branch, so it is structurally consistent, and it does NOT disturb Evergreen
  (branch 1) or TermDefined lines that already prorate in seq 27 (those have a non-null transient, excluded by criterion 3).
- Optional polish (still net-zero): switch the assignment input from `EvergreenPricingTermCountConstant` to the neutrally
  named `PricingTermCountValueOneConstant` (both = 1) for maintainer clarity.
- **Precision caveat:** a constant PTC=1 matches ALL current TermDefined data (single full-term lines). If Fortra later needs
  a *computed* PTC for multi-term/partial TermDefined, that requires the 3-element proration writer (V20 template retained in
  `V20_writer_subtree_template.xml`) and element budget — out of scope for stopping the NPE, and unsupported by current data.
- **Rejected alternatives (documented so they aren't retried):** (a) merged-BKM approach — one BKM can't prorate both
  Evergreen (`EffectiveTo=itemTransientEndDate`) and TermDefined (`EffectiveTo=EffectiveTo`); (b) hydrating
  `itemTransientEndDate` in-proc — no step writes it (it's context-only); (c) reclaiming the "Copy of List Container 8" or
  the two "Aggregate Price" steps — all confirmed functional (Services/Software/Subscription totals; two distinct group
  aggregations), not free deletes.

**Prong C — Interim operational mitigation (no proc change, no element budget).** While A is capacity-gated: for any
Delete-Group failure, **do NOT run a naked Reprice-All** (it force-reprices the same malformed line and re-throws). Instead
heal the specific offending line's term fields and reprice it so PTC stamps, *then* Delete Group. (The §2a repro quote is
already healed.) Also add the writer to the **V22 draft** so activating V22 doesn't re-ship the bug.

## 4. Step-by-step roadmap

### Phase 0 — now (no deploy auth needed) ✅ audit done
1. **File the Salesforce platform case** (Prong B) — unblocked, highest value, capacity-independent.
2. ~~Element-reclamation audit~~ — DONE (§2f). Result: fix is net-zero; no reclamation needed.

### Phase 1 — apply the net-zero PTC fix (needs fresh explicit UAT deploy authorization; single-owner change)
> Deploy mechanism (per [[reference_pricing_procedure_deploy_mechanics]] + [[feedback_pricing_proc_v21_inplace]]): this is a
> single-filter criteria edit — cleanest via **canvas** (open V21 → the seq-29 filter → add the criterion + fix conditionLogic
> → Save in-place → Activate from the Versions list). If deploying by MDAPI instead: **close all canvas tabs → deactivate
> V21 → deploy to the inactive version (api 67, `--metadata-dir`) → reactivate from the Versions list in a FRESH tab →
> re-retrieve to confirm no clobber**. Criteria are position-referenced 1..N — keep them contiguous and match conditionLogic.
3. **Re-retrieve live V21** immediately before editing (co-owned, churns — Nir edited it 7/01).
4. **Edit `ListOperation93` (seq 29 filter):** add criterion `SellingModelType Equals 'TermDefined'` (position 4) and set
   `conditionLogic = (1 AND (2 OR 3)) OR (4 AND 3)`. (Optional: repoint the assignment input to `PricingTermCountValueOneConstant`.)
5. Save/deploy → activate (fresh tab) → **re-retrieve and confirm** the criterion + conditionLogic persisted (no clobber).
6. **Verify runtime** (§5). Apply the same one-criterion edit to the **V22 draft** so activating V22 can't reintroduce null PTC.

### Phase 2 — stop the recurrence
7. Add "TermDefined lines must receive a non-null PricingTermCount (seq-29 branch or a proration writer)" to the
   pricing-procedure branch/PR checklist; note the proc is at 128/~129 elements so any new work must budget elements. The
   TermDefined-PTC gap has regressed 3× (V12, V17–19, V21) — it will recur without a guard.

## 5. Acceptance criteria / verification
- Force-reprice a fully-configured TermDefined line (e.g. clone of `0QLWC000003lizx4AA`) → **PricingTermCount populates** (was null).
- Org-wide: new fully-configured TermDefined lines stop being created with null PTC (the "17" cohort → ~0 going forward).
- Build a fresh repro (group with a TermDefined line) on a clone and **retry Delete Group → no NPE** (closes the ⏳ open item
  from the prior dossier: "retry actual Delete Group end-to-end").
- Note the honest limit from the prior RCA: null-PTC is a *necessary contributing* trigger but not proven *sufficient*
  org-wide — hence Prong B (platform case) remains the true guarantee against the raw NPE.

## Artifacts
- `expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` — live retrieve, all 22 versions
- `V20_writer_subtree_template.xml` — the 3-step guarded writer to rebase onto V21
- This file
