# SC-3447 — Completeness Critique of the Consolidated Fix Design

**Date:** 2026-06-27 · **Role:** completeness critic (read-only) · **Org:** FortraUAT (00DWC000006eUFF2A2)
**Reviewed:** `DESIGN.md` + detail files `01`–`09` + live verification queries this session.

**Verdict: partially-sound.** The root-cause analysis (per-clone describe ×N + per-clone OrderItem
flow re-entrancy ×N, all in one synchronous CPU budget) is correct and well-evidenced, and the layered
plan is directionally right. But the investigation has a **systematic blind spot: it audited only
OrderItem-level automation and never enumerated the Order-header automation cascade**, which I verified
live this session and which is real, uncounted CPU. Several plan claims also rest on facts that were NOT
re-verified this session (they are inherited from 06-26 or assumed). None of the gaps overturn the root
cause; two of them (Order-header cascade, reprice-tail O(N)) materially affect the sizing/scope of P1/P2.

---

## A. Live-UAT claims asserted but NOT verified this session (stale/assumed)

1. **The "dead-txn snapshot" (SOQL 19/100, DML 480/10000, CPU >10000)** is quoted as the binding-limit
   proof in `DESIGN §2`, `rootCauseConfirmed`, and file `08`. **It was NOT captured this session** — the
   repro quote is gone and we are read-only. It is a 06-26 artifact. The design correctly flags "current
   empirical CPU threshold unknown" in `openRisks[0]`, but then still leans on the 480-DML/CPU>10k numbers
   as present-tense evidence. They should be labeled point-in-time. *(Whose job: the data/repro agent — file
   06 — should have stated the snapshot is historical, not re-measured.)*

2. **`MAX_SYNC_CLONES=200` "is below the empirical CPU cliff."** This is an *assumption*, not a measurement.
   File `05 §6` infers the cliff "well below 100" from the fact that the largest successful split is 9 clones
   — but 9-clones-succeeded does not establish where the cliff is; it only proves nothing large was ever
   *attempted-and-succeeded*. With the SC-3366 dup subflow now off, the true cliff could be far above 200 or
   (less likely) below it. **The cap value is a guess presented with false precision.** Plan is honest that
   Joe must set it, but the "200 is safe" framing is unverified. *(Whose job: file 05/06 should have said the
   cliff is unmeasured, not "well below 100.")*

3. **Active Order pricing proc = V16, OrderRepriceInvocable live body, SalesTransactionContextExt_v2.**
   These are flagged "move daily — re-verify at build" — good. But the design's P2 reprice-sequencing logic
   is built on the *current* V16/live-OrderRepriceInvocable shape; if these have already moved (they move
   daily and the design itself notes 06-24/06-25 changes), parts of P2 §3 may already be stale. This is
   disclosed, so it is a caveat, not a defect.

4. **"createFullClone copies ALL createable fields, so clones already carry the V16 staging fields"**
   (`openRisks[5]`, file `03 §5`). Verified true in source. OK.

---

## B. Modalities NOT investigated (the real coverage holes)

### B1. ORDER-HEADER automation cascade — completely uninvestigated (verified live this session)
Every detail file audited **OrderItem** automation; **none enumerated Order-object automation**, yet the
convert chain updates the Order header repeatedly (createOrderFromQuote insert; QuoteToOrderFieldMapper
header update; OrderRepriceInvocable's ~4 bulk Order/OrderItem update passes + clearValidationResult;
Activate's status update). I verified live:

- **`OrderValidationTrigger`** (Apex, Active, on Order, **before insert**, api 65) → `OrderValidationTriggerHandler.handleBeforeInsert`. O(1) per convert (one Order). Not N-scaling, but **never mentioned** — and `04`'s "no OrderItem Apex triggers" claim quietly skips that there IS an Order trigger.
- **Active Order record-triggered flows that fire on Order header insert/update** (verified via FlowDefinition active versions; names are self-describing):
  - `Order_Before_Insert_Update_Sync_Status` (Before Insert/Update)
  - `Fortra_Order_Sync_Address_From_Place`
  - `Fortra_Order_to_Billing_Schedule` — **RecordAfterSave / Update, verified**; updates Order + has a PaymentTerm reference
  - `Fortra_Order_Set_Payment_Terms`
  - `Fortra_Order_to_Contract_Field_Mapping`
  - `Order_Submission_to_Revenue_Orchestrator`, `Fortra_Order_After_Update_Platform_Event_Workday`, etc.

  These fire **once per Order-header DML**, and the chain does ~6+ Order updates → these flows run several
  times each per convert. That is real baseline CPU the design's CPU model entirely omits (the model is
  100% OrderItem-flow + describe-loop). **At low N this baseline may be a meaningful fraction of the 10s
  budget**, and it means even after P1 fully suppresses per-clone OrderItem work, there is a fixed
  Order-cascade floor the design hasn't measured.

  **Action needed:** an agent must (a) confirm each is RecordBefore/AfterSave on Order, (b) confirm none
  performs **per-OrderItem** work (e.g. `Fortra_Order_to_Billing_Schedule` — does it create one Billing
  Schedule child per OrderItem? If so it is a *hidden N-scaling contributor* that survives the P1 OrderItem-
  flow suppression entirely). I confirmed it updates Order + references PaymentTerm and has only 1
  recordUpdate (not an obvious per-line loop), but its full body and any subflows were not traced.
  *(Whose job: a NEW agent — "Order-header automation audit" — that 01/02 should have included.)*

### B2. ChecklistValidationService and QuoteToOrderFieldMapper cost contribution — under-investigated
- `ChecklistValidationService` is **not in the repo** (`force-app` has no such class) and its body/cost was
  never retrieved or audited. It runs first in the chain (`CurrentTransaction`, no faultConnector). Cost
  unknown. *(Whose job: file 01 named it but never opened it.)*
- `createOrderFromQuote` is the **native RLM action** — its internal cost (it inserts the order + all
  OrderItems, firing the OI flows once per original line) is real and unmeasured. At a quote with many
  *distinct* lines (not just one high-qty line) this is itself O(line-count) before any split.
- `QuoteToOrderFieldMapper` (in repo, 271 lines) — I verified it is **bulkified** (fixed 3 SOQL + ≤2 DML,
  no loop DML) BUT it does `update toUpdate` over **all** OrderItems (L188 header, L260 items). **That bulk
  update fires `Set_Dates` V6 + `Set_Workday` V11 once per original OrderItem, BEFORE the split runs.** So
  the per-OrderItem flow re-entrancy is paid **twice** on the originals (once at createOrderFromQuote
  insert, once at mapper update) — the design's CPU model only counts the per-*clone* firings, missing the
  per-*original* double-fire. For a multi-line quote this is non-trivial. The P1 `Is_Split_Line__c=false`
  entry guard does **NOT** suppress these (originals are `Is_Split_Line__c=false` by design). *(Whose job:
  file 02/04 — they traced the flows but not the mapper's bulk-update trigger of them on originals.)*

### B3. Reprice as a PARALLEL CPU/limit risk — identified but under-weighted in the plan's framing
File `03 §4` correctly finds the reprice tail is **itself O(N)** (one PATCH per OrderItem; 4 bulk OrderItem
UPDATE passes each re-firing `Set_Workday` V11 → re-firing `Set_Dates`; the 92KB `PartnerNetPricePosthook`
per line). This is a strong finding. **But the executive summary and P1 present reprice as a P2-only
concern.** In reality: even at moderate N where P1 makes the *split* fit, the *reprice* may not, because
the 4 reprice-phase bulk updates re-fire the OI flows on **all N lines including the suppressed clones**
(the `Is_Split_Line__c=false` guard suppresses clones, but the reprice updates touch clones too — clones
are `Is_Split_Line__c=true`, so they ARE suppressed there, good — but the originals and any non-split lines
are not). The net: **P1's CPU headroom estimate must include the reprice tail, not just the split loop.**
The plan should explicitly state P1 alone may not make the repro converge if reprice O(N) dominates after
the split is cheap. *(Whose job: file 03 found it; the synthesis under-weighted it in P1 sizing.)*

### B4. Managed-package / RLM trigger surface in the convert path — not checked
The design asserts "no managed-package or RLM trigger" only implicitly. `createOrderFromQuote`,
`OrderRepriceInvocable`'s `commerceorders.PlaceOrderExecutor.execute(...Force...)`, and assetize all invoke
**RLM/`commerceorders` managed package code**, which per cheatsheet footnote-5 **accrues to the same CPU
budget**. No agent enumerated whether the `commerceorders` package registers its own Order/OrderItem
triggers or flows that fire during convert. The Force-reprice running the V16 pricing procedure over N
lines is managed-package CPU inside the user transaction. **This is acknowledged for reprice but not
audited as a trigger surface.** *(Whose job: a managed-package trigger audit — missing entirely.)*

---

## C. Business-process gap: does WORKDAY need one line per seat, or quantity=N?

**This is the single most important unanswered business question and the design does not ask it.**

The whole justification for *ever* materializing per-unit OrderItems (the P2 async build) presumes some
downstream consumer needs one row per unit. The design's Joe-questions Q1–Q3 ask what Quantity *means* and
whether per-unit is needed, but **never asks the decisive integration question: does the Workday contract
integration require one contract line per seat, or one contract line with quantity=N?**

- If Workday wants **quantity=N on one line**, then per-unit splitting is unnecessary for Workday too, P2
  collapses entirely, and P3 ("don't explode seat lines") is the *only* needed track — a much smaller
  project.
- The data hints the answer is "quantity=N": `Set_Workday_Contract_Line_Type` stamps a line *type*, and the
  Workday memory entries (SC-3347/3368/3374) all describe **per-line** contract amounts, not per-seat. But
  this is **inferred, not verified.** No agent examined the Workday Mule contract-line payload mapping to
  confirm whether it reads OrderItem.Quantity or expects one OrderItem per unit.

**Action needed:** verify the Workday contract-line integration's quantity handling (Mule mapping / the
`Set_Workday_Contract_Line_Type` + order-completion payload from `project_workday_*` memories) BEFORE
committing any P2 build. If Workday takes quantity=N, P2 is dead and P3 is the resolution. *(Whose job: a
Workday-integration agent — entirely absent from the 9-file investigation, despite the convert's terminal
step being Workday submission.)*

---

## D. Rollback / feature-flag / UAT-validation-without-Workday

1. **No feature-flag / kill-switch design.** P1 changes the split class + 2 flow versions; P2 reroutes the
   entire tail async. There is **no custom-setting / custom-metadata gate** to toggle new vs old behavior
   without a redeploy. For a Blocker on a live backlog, a `MAX_SYNC_CLONES` that is a **custom metadata
   value (not a hardcoded `static final 200`)** would let admins tune/disable without a deploy. The design
   hardcodes the constant — a rollback/tuning gap. *(Correction below.)*

2. **Flow rollback is version-based (revert to V27) — fine**, but the design doesn't state the rollback
   procedure (deactivate V28, reactivate V27) or that the entry-condition flow versions are independently
   revertible from the Apex change. The Apex cap and the flow result-branch must be deployed/rolled back
   **together** (a cap that sets `success=false` with no flow branch to read it = silent swallow again).
   This coupling is not called out as a rollback hazard.

3. **UAT validation without firing Workday.** The E2E matrix (E1–E9) all imply full convert→activate→
   Workday. There is **no described way to validate the split/reprice/activate fix in UAT without triggering
   the Workday submission** (the terminal flow step `Fortra_Screen_Send_Order_to_Workday` /
   `Order_Completed_WD__e`). Given Workday is an external system with real side effects, P4 needs an
   explicit "validate up to activation, suppress/stub Workday send" path. The `Order_Completed_WD__e`
   platform-event re-submit mechanism (per memory) means an accidental publish sends real data. **Not
   addressed.** *(Whose job: P4/test-strategy agent.)*

4. **Idempotency on re-run is designed for P2 (batch), but P0/P1 have no "partially-converted order"
   recovery.** If a convert fails mid-chain today it fully rolls back (good). But once P2 commits the thin
   convert first and then splits async, a **failed async chunk leaves a half-split, never-activated order**
   — the design covers re-enqueue/quarantine but not the **manual admin recovery / cleanup** path for an
   order stuck in `Pending Split` forever (e.g. if the batch is dropped by a platform flow-control event).
   This is the SC-3419-class "stuck state" risk applied to the new async pipeline.

---

## E. Missing test / E2E scenarios

The A1–A14 / E1–E9 matrix is strong. Gaps:

1. **No test asserting the Order-header automation does NOT do per-OrderItem work** (B1) — i.e. a test that
   `Fortra_Order_to_Billing_Schedule` etc. produce O(1) records, not O(N), on a high-N convert.
2. **No test for the multi-distinct-line quote** (B2): a quote with, say, 50 *different* Power+non-Power
   lines (each qty modest) to exercise the createOrderFromQuote + mapper double-fire of OI flows on
   originals, independent of the single-high-qty-line case. The whole investigation fixates on one big line;
   the backlog also contains multi-line quotes.
3. **No reprice-only CPU regression test** (B3): assert reprice headroom at N~50 with clones suppressed, to
   prove the tail isn't the new bottleneck after P1.
4. **No negative test that the P1 entry-condition does not regress NON-split OrderItem stamping** (a normal
   single-line order with `Is_Split_Line__c=false` must still be fully stamped by both flows). A14/A7 test
   the clone path; nothing guards the *un-split* path against the new entry filter.
5. **No "Workday-suppressed UAT validation" E2E** (D3).
6. **Concurrency/lock test for P2** vs the post-activate assetize job (SC-3419 race) — called out as a risk
   but no test scenario asserts the sequencing holds.

---

## F. Corrections (specific)

1. **Add a faultConnector to `Validate_Checklist_Complete` (ChecklistValidationService) too.** P0 only
   adds faults to Split + Mapper; I verified live that **ChecklistValidationService also has no
   faultConnector** (3 unguarded actions, not 2). An unhandled checklist-validation exception is the same
   silent-fault class the P0 change is meant to close.
2. **Make `MAX_SYNC_CLONES` a Custom Metadata value, not `private static final 200`.** Enables
   admin-tunable cap + instant kill-switch without redeploy (rollback/feature-flag gap, D1).
3. **P1 sizing must include the reprice tail and the Order-header cascade, not just the split loop.** State
   explicitly that P1 may not make the repro converge if reprice-O(N) + Order-cascade dominate; add a
   build-time CPU measurement step (Limits.getCpuTime() instrumentation in a sandbox convert) before
   declaring P1 sufficient.
4. **Account for the per-ORIGINAL double-fire of the OI flows** (createOrderFromQuote insert + mapper
   update). The P1 `Is_Split_Line__c=false` guard does NOT suppress these (originals are false by design).
   If the originals' flow cost is material on multi-line quotes, consider a transient bypass (custom
   permission on the convert running user) for the mapper's bulk update specifically.
5. **Add the decisive Workday question to the Joe/integration block:** "Does the Workday contract
   integration require one contract line per seat, or one line with quantity=N?" — and verify it against the
   Mule mapping before any P2 commit (C).
6. **Add a "validate-to-activation, Workday-suppressed" UAT path to P4** (D3).
7. The design's "no OrderItem Apex triggers" is true but should be amended to "**no OrderItem triggers; one
   Order before-insert trigger (`OrderValidationTrigger`) and ~6 active Order record-triggered flows fire
   during convert — audited as O(1)/per-header, not per-line, EXCEPT `Fortra_Order_to_Billing_Schedule`
   which must be confirmed not per-OrderItem.**"

---

## G. What is solid (so the team doesn't re-litigate)

- Root cause (describe ×N + OI-flow re-entrancy ×N in one sync CPU budget): **correct, well-evidenced.**
- The two hard ceilings (10k DML rows identical sync/async; seat/sentinel semantics): **correct and
  decisive** — these alone justify P3 over P2 for seat lines.
- `Is_Split_Line__c=false` entry-guard safety analysis (file 02 §6): **rigorous and convincing.**
- Describe-hoist (208×N → 208): **correct, low-risk, high-value.**
- Class source == live (newline only): **verified, source trustworthy.**
- Billing field-name correction (`Billing_Schedule_From/To_Date__c`): **verified, important.**
- 0% coverage deploy-gate: **verified, correctly flagged.**
- The reprice-tail-must-move-with-split dependency (file 03 §2): **correct and load-bearing.**
