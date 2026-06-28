# SC-3447 P2 — BUILDABLE SPEC: Move the Split→Reprice→Activate Tail to a Chunked Async Pipeline

**Ticket:** SC-3447 (Blocker) · **Reporter:** Joe Romo · **Assignee:** Liam Jeong
**Date:** 2026-06-27 · **Author:** P2 synthesis lead (read-only research; nothing below deployed)
**Org:** FortraUAT (00DWC000006eUFF2A2)
**Status:** DESIGN ONLY / **CONTINGENT**. Every UAT deploy/DML (even validate-only) needs a fresh explicit
authorization ([[feedback_uat_deploy_authorization]]). Re-verify all "live" facts at build (daily churn).
**Inputs:** P2_01_reprice_async.md, P2_02_activate_assetize.md, P2_03_async_platform.md, P2_04_failure_ux.md,
03_reprice_activate_async.md, 10_order_header_cascade.md, DESIGN_FINAL.md §P2, P1_SPEC.md, the live
`OrderRepriceInvocable_live.cls` / `OrderCommercialNetService_live.cls`, force-app
`PowerOrderSplittingService.cls`.

---

## 0. ONE-LINE VERDICT

**P2 is technically feasible** — the whole Split→Reprice→Activate tail CAN run from async Apex (no platform
ban on async OrderItem DML, no async-Apex prohibition on the RLM Force reprice, no lock on Order activation) —
**but only as a multi-stage chunked Batch pipeline, and only for genuine per-machine orders in the LOW
THOUSANDS of clones.** It **cannot and does not** materialize seat/sentinel quantities (9,999 / 99,999 /
999,999 / 750,000); those are forever P3's job. And as of the live data, **P2 is NOT justified by evidence**:
exactly **4 OrderItems org-wide are split-eligible under the P3 predicate, all at Quantity=3 (2 clones each).**
P2 is shelf-ready contingency, gated on Joe confirming a real large per-machine case exists.

---

## 1. FEASIBILITY VERDICT (up front)

### 1.1 Can the tail run async at all? — YES (verified, with named hazards, not bans)

| Stage | Async-runnable? | Evidence | Hazard to engineer |
|---|---|---|---|
| **Split** (clone OrderItems) | YES | No RLM OrderItem-DML lock (the RLM lock is **Quote**-only, [[project_rlm_quote_dml_lock]]); `PowerOrderSplittingService` already inserts clones + updates originals in the convert today — failure is **CPU**, not a DML-blocked error (P2_03 §2). OrderItem describe createable/updateable=true. | 10k-DML-row ceiling → chunk. |
| **Reprice** (`OrderRepriceInvocable`→`commerceorders.PlaceOrderExecutor.execute(...Force...)`) | YES | In-process Apex API, **NOT an HTTP callout**; no `Database.AllowsCallouts` needed (grep=0); only input is an Order Id; already runs in a plain `CurrentTransaction` flow action today (P2_01 §2a,2d). No documented async-Apex prohibition. | (a) **PlaceOrderResult is part-sync/part-async** — the invocable trusts only `r.success` and never polls `requestIdentifier`/`statusURL`; at >100 lines (`isHighVolumeLineItems`) pricing may defer to the platform's own async tail (P2_01 §2b). (b) **execute() poisons same-transaction RLM state** (org-proven INVALID_CROSS_REFERENCE_KEY, `OrderRepriceInvocableTest` header) → each Force reprice needs its OWN transaction (P2_01 §2c). |
| **Clear ValidationResult** | YES | Plain `update Order(Id, ValidationResult=null)` (live `clearOrderValidationResult`, OrderRepriceInvocable L146-151). | Must be the LAST OrderItem-affecting write before activate (P2_02 §2c). |
| **Activate** (`Status='Activated'`) | YES | Today's activation is a plain `recordUpdate` Order Status='Activated' (V28 Activate_Order); nothing flow-specific; no RLM/platform lock on Order Status update (P2_02 §1a,1c). | (a) ValidationResult must be null at that instant; (b) it must be a first-time Draft→Activated (re-activating an already-submitted order throws `CANNOT_EXECUTE_FLOW_TRIGGER`, SC-3419 B1 — guard idempotency); (c) the transition fires the in-line **synchronous** `submitOrder` (Revenue Orchestrator, triggerOrder 200, O(N)) on the async budget (P2_02 §1b,1c, caveat A). |
| **Assetize / Billing** (post-commit) | AUTOMATIC | `Fortra_Assetize_Order` V17 (AsyncAfterCommit, triggerOrder 300) + `Fortra_Order_to_Billing_Schedule` (AsyncAfterCommit, triggerOrder 1200) fire on their own post-commit transactions after Status='Activated' (P2_02 §2a, §3). | Do NOT call them; they fire automatically. Touch NO OrderItem after activate or you re-create SC-3441/SC-3419 (P2_02 §2b, P2_03 §2.4-2.5). |

**No mechanics agent found that reprice/activate CANNOT run async.** Context binding
(`SalesTransactionContextExt_v2`) is a **DATA-level** prerequisite (V16 staging fields must exist + be carried
on the clones), **not** a UI-thread requirement — which is precisely what makes async feasible. All V16
staging fields are present + createable+updateable on OrderItem, and the existing full-field `createFullClone`
stamps them (P2_01 §4). **This is the load-bearing "it works" finding.** If a future build discovers the
executor refuses to run outside the flow's RLM running context, P2 becomes infeasible as designed and the
fallback is "stay sync under a hard cap (P0) + P3 for everything above" — call that out at the build's first
spike (E13 in DESIGN_FINAL).

### 1.2 Realistic max N (clones) P2 can handle

The 10,000-DML-rows-per-transaction ceiling is **identical sync and async** (P2_03 §0; async raises only CPU
10s→60s, heap 6→12MB, SOQL 100→200). So async buys CPU headroom but **never** more DML rows in one
transaction. Aggregate scale comes ONLY from chunking (each chunk = fresh 10k budget). The binding walls,
per stage:

| Stage | Per-N cost | Single-txn wall | Aggregate ceiling (chunked) |
|---|---|---|---|
| Build (OLO partition path) | ~3 DML rows/clone (OI insert + Partition insert + OI partition-ref update) | ~3,300 clones | chunked → thousands |
| Build (OLH path) | ~4 DML rows/clone (+Hardware) | ~2,500 clones | chunked → thousands |
| **Reprice** | 1 GraphRequest PATCH/OrderItem + ~4×N bulk OrderItem UPDATE passes (seedFromWork + persistFromWork×2 + OrderCommercialNetService.patch) + 92KB PartnerNetPricePosthook | **~10k rows binds near N≈1,000–1,250; reprice-tail CPU may bind first (~315–1,230 est., P1_SPEC §3)** | chunked reprice → thousands, but each chunk poisons RLM state (own txn) + a final whole-order reconciliation is mandatory |
| Activate `submitOrder` (managed, O(N), in-line sync on activate txn) | O(line-count) managed work, NOT chunkable | hard RCA ceiling at extreme N | **cannot chunk — managed** |
| Billing schedule (managed, AsyncAfterCommit, 1/OrderItem) | N rows in its own async txn | 10k-row wall at extreme N | **cannot chunk — managed** |

**Realistic max N = low thousands of genuine per-machine clones.** The HARD un-chunkable ceilings are the
managed `submitOrder` at activate and the managed per-OrderItem billing-schedule job — neither of which P2
can break apart. So even with perfect build/reprice chunking, **practical P2 ceiling ≈ 2,000–5,000 clones**,
and that band must be validated by measurement at build (the reprice ms/line and submitOrder O(N) cost are
both unmeasured estimates).

### 1.3 What P2 explicitly CANNOT do (P3's job, not P2's)

- **Seat/sentinel quantities (9,999 / 99,999 / 999,999; requirement up to 750,000) are NEVER materializable** —
  ≥75–100 chunks, ~1M+ DML rows, plus the un-chunkable managed `submitOrder`/billing tails. Async does NOT
  raise the 10k-row ceiling (P2_01 §5.4, P2_03 §0, §5, P2_04 blocker 2).
- **The P3 per-machine predicate is the gate, sync AND async.** It is already live in
  `queryOrderItemsToSplit` (force-app L394-395): split only lines with a genuine Partition (OLO) or Hardware
  (OLH). Seat lines carry neither → never enter the clone loop. P2 reuses this predicate **verbatim** — it
  does NOT relax it (P2_04 §4.3). Async never makes seat lines splittable.

### 1.4 Mechanism verdict: BATCH (multi-stage), not Queueable

| Mechanism | Verdict | Why |
|---|---|---|
| Single Queueable | NO | One transaction = one 10k-row budget; cannot exceed ~3,300 clones; no native chunk loop (P2_03 §1b). |
| Queueable fan-out | NO | Async `System.enqueueJob` limit = **1** — cannot enqueue M>1 successors from an async txn (P2_03 §0, §1b). |
| Self-chaining Queueable | Viable fallback | Legal (1 enqueue/txn), but hand-rolls cursor/chunk-sizing/resume and has no "all chunks done" rendezvous (P2_03 §1b). Acceptable only at the low end (dozens–~2k clones). |
| **Database.Batchable (Database.Stateful)** | **RECOMMENDED** | Platform sequences chunks; each `execute()` = fresh 10k/60s txn; `Database.executeBatch(this, scopeSize)` sizes the chunk; `finish()` is the natural "reprice→clear→activate AFTER all chunks" rendezvous; `Database.Stateful` carries per-chunk results (P2_03 §1b). **And** Batch gives each Force reprice its own transaction, which is mandatory given the executor's same-transaction state poisoning (P2_01 §2c). |

**Decisive constraint that forces Batch over a single looping Queueable:** `PlaceOrderExecutor.execute()`
poisons same-transaction RLM/commerce state, so you cannot loop multiple Force reprices in one transaction —
each needs a fresh transaction boundary, which Batch provides natively and a looping Queueable does not
(P2_01 §2c, asyncImplication 2).

---

## 2. THE PIPELINE (sync cut → async stages → activate last → assetize post-commit)

### 2.1 Sync cut-point (what stays in the convert flow)

The convert flow `Fortra_Quote_to_Order_Conversion` (live **V28**, re-verify active version at build — its Id
moves on every save) keeps a THIN synchronous head and cuts the tail **between `MapQuoteLineFieldsToOrderItems`
and `SplitPowerOrderLines`** (P2_02 §4a):

```
SYNC head (stays in the screen flow, returns to user):
  1. Validate_Checklist_Complete (ChecklistValidationService)           — unchanged
  2. Call_Create_Order_From_Quote (createOrderFromQuote, native RLM)    — creates Order in Draft, qty=N on Power line
  3. Assign_Created_Order_Id
  4. MapQuoteLineFieldsToOrderItems (QuoteToOrderFieldMapper)           — MUST stay sync + before cut: P3 split gate
                                                                          reads OrderItem.Partition_Record__c / Hardware__c
                                                                          which only this mapper populates
  5. Decision_Split_Path: compute totalGenuineMachineClones = Σ(qty-1)  — over P3-eligible (Partition/Hardware) lines only
       ├─ totalGenuineMachineClones == 0
       │    → set Order.Split_Status__c='Not Required' → run today's SYNC tail UNCHANGED (Reprice→Activate). [common case, no regression]
       ├─ totalGenuineMachineClones <= SYNC_THRESHOLD (CMDT Max_Sync_Clones__c, default 200)
       │    → run today's SYNC tail UNCHANGED (split→reprice→activate inline). [Branch A — instant activate]
       └─ totalGenuineMachineClones > SYNC_THRESHOLD
            → BRANCH B (async):
               a. set Order.Split_Status__c='Pending Split' (+ Split_Sync_Correlation_Id__c)
               b. COMMIT the Order header update
               c. enqueue PowerOrderSplitBuildBatch(orderId) via an @InvocableMethod wrapper
               d. return to Screen_4_Confirmation_Async ("Order created — splitting in progress")
--- CUT (everything below is async) ---
```

**Why commit before enqueue:** the batch runs in a separate transaction and must READ a committed
`Split_Status__c='Pending Split'` to own the work and stay idempotent; enqueuing inside an uncommitted unit
that later rolls back would orphan a job against a non-existent order (P2_03 §3c). Flow action ordering + the
platform commit-then-async contract guarantees the header UPDATE commits before the job dequeues.

**The "valid-but-pending" posture:** order is Draft, custom lookups mapped, `Split_Status__c='Pending Split'`,
NOT activated. All `Status='Activated'`-gated automation (assetize, billing, orchestrator submit) stays
correctly **dormant** until the async activate (P2_02 §4b). This mirrors the **already-shipping manual-activation
branch** (`Screen1_OrderActivation != 'Automatic'` leaves the order Draft un-activated) — so "order exists
before activation" is NOT a new UX (P2_04 §0, §3.1).

### 2.2 Async stages

```
STAGE A — PowerOrderSplitBuildBatch (Database.Batchable, Database.Stateful)   [chunked clone build]
  start():   QueryLocator over split-eligible originals on Pending/In-Progress/Failed orders (P3 predicate)
  execute(scope):  for each original, count existing clones (idempotency gate, §5.1), materialize up to the
                   clone budget (~1,500 clones ≈ 4,500 DML rows, >50% headroom under 10k), insert clones
                   (ASYNC_CHUNK mode of processOrders — §3.1), insert/wire partitions+hardware, defer the
                   original's Quantity N→1 flip until its FINAL chunk completes it.
                   Is_Split_Line__c=true on clones → P1 flow-suppression skips per-clone Set_Dates/Set_Workday.
                   Apex-stamps Workday_Contract_Line_Type__c + date/term fields on clones (P1 #1b).
                   Database.insert(clones, false) + SaveResult inspection (§5.2). attachFinalizer per chunk.
  finish():  if every in-scope original satisfies existingClones == N-1 → enqueue STAGE B; else mark
             Split_Status__c='Partial Success'/'Split Failed' (recovery, §5).
             set Split_Status__c='Split In Progress'.

STAGE B — PowerOrderSplitRepriceBatch (Database.Batchable) or, at modest N, a single repriceOne call
  Reprice the now-N-line order via OrderRepriceInvocable.repriceOne(orderId) → PlaceOrderExecutor Force.
  - Each Force reprice = its OWN transaction (executor state poisoning, §1.1). At N small enough for one
    whole-order reprice (within 10k rows / 60s), do it once. At larger N, chunk per-line Force across
    transactions THEN run a FINAL whole-order reconciliation (reprice or total-match check) — mandatory
    because Order totals + the pricingReady total-match (quoteTotal == Order.TotalAmount) are whole-order
    (P2_01 §3, asyncImplication 5).
  - totalsAlreadyMatch short-circuit (OrderRepriceInvocable L45-49): if quote nets are already stamped on the
    order, reprice SKIPS the posthook + Force executor entirely — cheap path. An async design that re-stamps
    commercial nets first can avoid the expensive Force path on chunks where totals already match (P2_01
    asyncImplication 8).
  finish():  WAIT on real pricing completion (Order.CalculationStatus='CompletedWithPricing' AND
             ValidationResult cleared AND totals match — the isPricingReady gate, OrderRepriceInvocable
             L106-121). Do NOT trust bare r.success: at >100 lines pricing may complete in the platform's own
             async tail (PlaceOrderResult part-sync/part-async, §1.1 hazard a). Then enqueue STAGE C.

STAGE C — PowerOrderSplitActivateQueueable  [the ONLY place Branch B activates]
  1. Re-confirm pricingReady (CalculationStatus='CompletedWithPricing', ValidationResult null, totals match).
  2. clearOrderValidationResult(orderId)  — the LAST OrderItem-affecting write.
  3. COMMIT (end this txn's OrderItem-affecting work).
  4. update Order(Id, Status='Activated')  — FINAL write; idempotent (skip if already Activated).
        ├─ triggerOrder 200 Order_Submission_to_Revenue_Orchestrator → submitOrder (SYNC, in this txn, O(N))
        └─ COMMIT
  5. set Order.Split_Status__c='Split Complete'; publish Order_Split_Status__e.
--- post-commit (automatic, NOT called by P2) ---
  triggerOrder 300  Fortra_Assetize_Order (AsyncAfterCommit) → Finalize_Order_Commercial_Net →
                    createOrUpdateAssetFromOrder (N Assets, own txn)
  triggerOrder 1200 Fortra_Order_to_Billing_Schedule (AsyncAfterCommit) → N Billing_Schedules (own txn)
```

**The whole tail moves async TOGETHER.** Moving ONLY the split async is wrong: reprice prices ALL lines and
activate is gated on `Order.ValidationResult`; if split is async but reprice/activate stay sync, reprice
prices the un-split line, activate activates a 1-line order, and clones land unpriced on an active order
(re-creates SC-3441 null-price + SC-3419 0-Assets). Activate is LAST (DESIGN_FINAL §P2; P2_02 §2c; P2_03 §2).

---

## 3. NEW COMPONENTS

### 3.1 Apex

**(1) Refactor `PowerOrderSplittingService` (the existing P0+P3 class) — surgical, no forked logic:**
- Change `processOrders(Set<Id>, Map<Id,SplitResult>)` from **`private`** (force-app L108) to **`public static`**
  so the orchestrator can call it per-chunk (it is currently only reachable via the invocable).
- Add a mode/cap overload:
  ```apex
  public enum SplitMode { SYNC, ASYNC_CHUNK }
  public static void processOrders(Set<Id> orderIds, Map<Id,SplitResult> r, SplitMode mode)
  ```
  - `SYNC` → keep the current `MAX_SYNC_CLONES` cap check (force-app L137-148) — friendly bail above the cap.
  - `ASYNC_CHUNK` → SKIP the sync cap (the orchestrator has already chunked to a safe per-txn size); the only
    ceiling that still applies is the per-chunk 10k-DML-row budget, enforced by the orchestrator's scoping.
  - The existing 1-arg `processOrders` delegates with `SYNC` (no behavior change for the invocable / Branch A).
- Add a **slice bound** to the build (process up to K un-materialized slots per original, or a sub-range) so
  each chunk stays under 10k rows even when a single original's N exceeds the chunk budget (P2_03 §1c —
  scope is NOT "originals, fixed scopeSize"; one high-qty original can blow 10k rows).
- **REUSE UNCHANGED:** `queryOrderItemsToSplit` (P3 per-machine predicate — the correct async gate too),
  `createFullClone` (FULL-field copy — preserves V16 `SalesTransactionContextExt_v2` staging fields; a "lite"
  clone re-triggers the context-fetch incident, [[project_v16_order_pricing_contextfetch_incident]], P2_01 §4,
  P2_04 §4.3), and the P1 `Is_Split_Line__c=false` flow-suppression + Apex-stamp (P1_SPEC §1b, §2).
- Apply the **P1 describe-hoist** (`createableOrderItemFields`/`accessibleOrderItemFields` statics) — it
  benefits the async path identically (P1_SPEC §1a).

**(2) `PowerOrderSplitAsyncOrchestrator` — the new thin async wrapper (the only net-new Apex logic):**
- `@InvocableMethod enqueue(List<Id> orderIds)` — called by the thin convert (Branch B). Stamps
  `Split_Status__c='Pending Split'`, computes the chunk plan, `Database.executeBatch(new
  PowerOrderSplitBuildBatch(orderId), 1500)`.
- `PowerOrderSplitBuildBatch implements Database.Batchable<SObject>, Database.Stateful` — STAGE A above.
  `start()` QueryLocator over split-eligible originals on Pending/In-Progress/Failed orders;
  `execute(scope)` calls `PowerOrderSplittingService.processOrders({orderId}, results, SplitMode.ASYNC_CHUNK)`
  scoped to the chunk's slice + SaveResult inspection + `System.attachFinalizer`; `finish()` enqueues
  STAGE B or marks Partial Success/Failed.
- `PowerOrderSplitRepriceBatch implements Database.Batchable<SObject>` (or a single `repriceOne` call at
  modest N) — STAGE B; `finish()` waits on real pricing completion, enqueues STAGE C.
- `PowerOrderSplitActivateQueueable implements Queueable` — STAGE C; clear ValidationResult → activate →
  Split Complete → publish PE. **The ONLY place Branch B activates.**
- `SplitChunkFinalizer implements System.Finalizer` — per-chunk reliability backbone: on
  `UNHANDLED_EXCEPTION` write a terminal status + bounded re-enqueue (≤2, idempotent) or quarantine; a
  Finalizer can enqueue exactly ONE Queueable (chain stays single-threaded) (P2_04 §1.3).
- `resume(Id orderId)` (`@AuraEnabled` + anon-apex entry) — recovery: re-enters the pipeline, idempotent via
  the existing FK; tops up only the gap (P2_04 §2.2).
- `SplitResumeScheduler implements Schedulable` — hourly stale-sweep for silently-dropped jobs (30-min
  staleness fence, P2_04 §2.2).

**(3) The invocable `splitPowerOrderLines` stays for Branch A / the sync path — unchanged externally.** Same
logic, two entry points (P2_04 §4.3).

### 3.2 Fields

| Field | Object | Type | Values / notes | Status |
|---|---|---|---|---|
| `Split_Status__c` | Order | Picklist (restricted), default `Not Required`, system-managed (read-only on layout) | **Not Required** / **Pending Split** / **Split In Progress** / **Split Complete** / **Partial Success** / **Split Failed** (P2_03 §3b) | **CONFIRMED ABSENT — must create** (P2_03 §3a) |
| `Split_Sync_Message__c` | Order | Long text area | last status / error detail (truncate to length); mirrors `Workday_Sync_Message__c` | new (optional but recommended) |
| `Split_Sync_Correlation_Id__c` | Order | Text | AsyncApexJob.Id / GUID → find job in Setup → Apex Jobs; mirrors `Workday_Sync_Correlation_Id__c` | new (optional but recommended) |
| `Split_Retry_Count__c` | Order | Number | bounded re-enqueue counter (or hold in stateful job) | new (optional) |
| (reuse) `Order_Integration_Error_Messages__c` | Order | Long text area | append failing-slice detail — EXISTS, no new field needed | exists (P2_04 §0) |
| (reuse) `OrderItem.Original_Order_Item__c` + `Is_Split_Line__c` | OrderItem | Lookup + Checkbox | idempotency FK + flow-suppression gate — EXIST | exist (P2_03 §3a) |

> **Naming note:** P2_03/P2_02 call the field `Split_Status__c`; P2_04 proposes the parallel
> `Split_Sync_Status__c` family to mirror the existing `<System>_Sync_Status__c` convention exactly. **Pick
> ONE at build.** Recommendation: use `Split_Status__c` as the lifecycle field (matches the design's idempotency
> references) and ADD `Split_Sync_Message__c`/`Split_Sync_Correlation_Id__c` for the message+correlation triple
> (admins already understand the `_Sync_` family). Whichever name, it MUST NOT be a formula/rollup (must be
> writable by flow + batch) and MUST NOT live on standard `Status` (RLM/lifecycle-controlled).

### 3.3 Platform event

| Component | Fields | Purpose | Precedent |
|---|---|---|---|
| `Order_Split_Status__e` | `Order_Id__c` (string), `Status__c` (string), `Message__c` (string) | real-time push to UX / Chatter / `lightning/empApi` LWC; consumer re-reads LIVE Order data | `Order_Completed_WD__e` (single `Order_Id__c`) — house lightweight Order-keyed style (P2_04 §0, §1.5b) |

Published by the Finalizer / activate step on **terminal** outcomes (Split Complete / Partial Success / Split
Failed). Durable status field = source of truth; PE = notification accelerant — same dual pattern the org uses
for Workday sync status.

### 3.4 Flow changes to convert flow V28 (→ V29)

- **Cut the tail:** remove `SplitPowerOrderLines → Reprice → Activate` from the Branch B path (Branch A keeps
  them).
- **Add `Decision_Split_Path`** after `MapQuoteLineFieldsToOrderItems` (§2.1): Not Required / Branch A (sync,
  unchanged) / Branch B (async).
- **Branch B:** stamp `Split_Status__c='Pending Split'` (recordUpdate) → commit → call
  `PowerOrderSplitAsyncOrchestrator.enqueue` (invocable action) → route to new screen
  `Screen_4_Confirmation_Async`.
- **New screen `Screen_4_Confirmation_Async`** (clone of `Screen_4_Confirmation`): "Order created — line
  splitting in progress. Activation and Workday submission happen automatically once splitting completes; watch
  the Split Status field." + `Screen_Navigate_To_Order` (P2_04 §3.2).
- Keep the P0 fault connectors on all three Apex actions; keep the `Is_Split_Line__c=false` entry conditions on
  `Set_Dates` (V6→) and `Set_Workday_Contract_Line_Type` (V11→) from P1. Bump `<description>` to a single terse
  `2026-06-27: …` line (no ticket IDs, [[feedback_flow_description_style]]).
- **Coordinate the line-type flow family with Ben Kozlowski** (SC-3210/3366/3368). Re-verify V11 is still
  product-boolean (no `Original_Order_Item__c` reverse-lookup) at build — daily churn could reintroduce it
  and re-break SC-3210/3368 (P1_SPEC §0; DESIGN_FINAL C1).

### 3.5 CMDT

`SC3447_Split_Config__mdt.Max_Sync_Clones__c` (already P0 scope) doubles as the **SYNC_THRESHOLD** for the
Branch A/B switch (default 200, admin-tunable kill-switch). Reuse, do not invent a second knob (P2_04 §3.2).

---

## 4. EXACT SEQUENCING + GUARANTEES AT EACH BOUNDARY

The load-bearing invariant (P2_02 §2c, P2_03 §2.4-2.5): **build ALL N lines → reprice → clear
ValidationResult → COMMIT → activate (LAST) → assetize/billing fire post-commit automatically.** No OrderItem
DML after activate.

| Boundary | Guarantee that must hold | How it's enforced | Trap avoided |
|---|---|---|---|
| Sync commit → enqueue | Order header (`Split_Status='Pending Split'`) is COMMITTED before the batch dequeues | Flow commits the recordUpdate before the enqueue action; platform commit-then-async contract | orphan job vs rolled-back convert (P2_03 §3c) |
| Build chunk K → K+1 | Chunk K's clones are committed; K+1 re-derives existing clone count and only fills the gap | `Database.insert(clones,false)` per chunk (fresh txn) + §5.1 count gate | double-create on retry (P2_04 §1.2, P2_03 §4b) |
| Build done → reprice | EVERY in-scope original has `existingClones == N-1` and `Quantity` finalized to 1 | `finish()` verifies completion before enqueuing reprice; else Partial Success/Failed | repricing a partially-split order (wrong totals) |
| Reprice (per Force call) | Each Force reprice runs in its OWN transaction | Batch `execute()` per chunk = fresh txn | executor same-transaction state poisoning → INVALID_CROSS_REFERENCE_KEY (P2_01 §2c) |
| Reprice done → activate | Pricing TRULY complete (not just sync `r.success`): CalculationStatus='CompletedWithPricing' AND ValidationResult null AND totals match | STAGE B `finish()` waits on the real isPricingReady gate before STAGE C | activating on bare success while platform async-tail pricing is in flight → **SC-3441 null-price clones on an active order** (P2_01 §1.1 hazard a) |
| Clear ValidationResult → activate | ValidationResult is null at the instant Status flips, and NO OrderItem DML runs after the clear | clearValidationResult is the last OI-affecting write; STAGE C does only the Order Status update after it | any OrderItem DML re-dirties ValidationResult to 'TransactionIncomplete' → activation blocked / **assetize stuck at ContextPersistence** (OrderCommercialNetService header; P2_02 §2b) |
| Activate | First-time Draft→Activated, exactly once (idempotent) | STAGE C skips if `Status='Activated'` already | re-activating an already-submitted order → `CANNOT_EXECUTE_FLOW_TRIGGER` (SC-3419 B1, P2_02 §1c) |
| Activate → assetize/billing | All N lines built + priced + committed BEFORE the post-commit assetize job runs | Assetize is AsyncAfterCommit, spawned only after the activate txn commits; P2 touches NO OrderItem after activate | **SC-3419 0-Assets** (assetize racing async split DML) — async does NOT amplify the SC-3419 race; that race is a duplicate-line-vs-pre-existing-asset DATA-shape issue, not a flow-vs-Apex timing issue (P2_02 §2b) |

**On the SC-3419 race specifically (P2_02 §2b):** the SC-3419 collision (optimistic-lock "asset updated by
another process") is a **data-shape** trigger (N duplicate same-Product2 lines contending on a PRE-EXISTING
matching Asset on the account), REFUTED as a governor/timing issue. It exists today sync and would exist
async; **async does not create or amplify it** (assetize is single-threaded per order in one AsyncAfterCommit
job). The V17 visibility fix surfaces it via `Order_Integration_Error_Messages__c` either way. The ONLY NEW
race P2 could introduce is mutating OrderItem pricing AFTER activate — forbidden by the "no OI DML after
activate" rule.

---

## 5. IDEMPOTENCY, PARTIAL-FAILURE/RECOVERY, STATUS SURFACING, CONVERT UX

### 5.1 Idempotency (no double-create on retry/resume/replay)

Key = existing `OrderItem.Original_Order_Item__c` FK + per-original count gate, gated by `Split_Status__c`
(P2_03 §4, P2_04 §1.2). For each original with target N:
- Order is "fully split for O" iff `count(OrderItem WHERE Original_Order_Item__c = O.Id) == N-1` AND
  `O.Quantity == 1`.
- Each `execute(scope)` re-queries existing clone count, computes `remaining = (N-1) - existingClones`, skips
  if `<= 0`, materializes up to `min(remaining, chunkBudget)` with `slotIndex = existingClones+1…`.
- **Persisting N (Phase 5 destroys the original's Quantity N→1):** **leaner recommended design (P2_03 §4d
  alternative)** — DEFER the original's Quantity flip until the FINAL chunk completes it, so the live Quantity
  still equals N until completion and the gate reads it directly. This keeps idempotency state to
  `Original_Order_Item__c` + `Split_Status__c` only (no new OrderItem field). Trade-off: the original carries
  Quantity=N (wrong line amount) until its last chunk — acceptable because reprice runs AFTER all chunks
  anyway. (Alternative: stamp `Quantity_To_Split__c` on originals at enqueue for observability.)

### 5.2 Partial-failure handling

- **Committed-convert invariant:** the thin convert already committed + returned; async runs in separate
  transactions, so a chunk failure CANNOT roll back the convert (P2_04 §1.1).
- **Row-level:** `Database.insert(cloneChunk, false)` (allOrNone=false) + `Database.SaveResult` inspection;
  failed slots stay un-materialized → next chunk/retry tops them up via the §5.1 gate (P2_04 §1.2).
- **Whole-chunk death** (uncatchable LimitException/gack/flex-queue eviction): `System.Finalizer` per chunk
  runs even on unhandled exception → writes a terminal status, bounded re-enqueue (≤2, idempotent) for
  transient, quarantine (don't re-loop) for structural CPU (P2_04 §1.3, §1.4).
- **Dropped job** (never started, no Finalizer): the §5.3 Schedulable stale-sweep (P2_04 §1.4, §2.2).

### 5.3 Recovery for stuck orders

Three layers, all calling the SAME idempotent `resume(orderId)` (P2_04 §2.2):
1. **Order-page Quick Action / LWC "Resume Power Split"** — enabled when `Split_Status__c IN
   ('Pending Split','Split In Progress','Partial Success','Split Failed')` AND `Status != 'Activated'`; shows
   the last `Split_Sync_Message__c`.
2. **Hourly `Schedulable` stale-sweep** — `Split_Status__c IN ('Pending Split','Split In Progress') AND Status
   != 'Activated' AND LastModifiedDate < now-30min` (30-min fence avoids racing a healthy in-flight job).
3. **Anon-apex one-liner** `PowerOrderSplitAsyncOrchestrator.resume(orderId);` (runbook; never auto-run).

`resume` re-enters the WHOLE tail (split→reprice→clear→activate) idempotently — never activates a half-split
order, never leaves clones unpriced, never races assetize. No new idempotency key (P2_04 §2.2).

### 5.4 Status surfacing

Durable field (`Split_Status__c` + `Split_Sync_Message__c` + `Split_Sync_Correlation_Id__c`, mirrors
`Workday_Sync_*`) = source of truth (poll/refresh/list-view/report). `Order_Split_Status__e` PE = real-time
push (`lightning/empApi` LWC on Order page, Chatter/bell notification). `AsyncApexJob` (Status/ExtendedStatus/
NumberOfErrors) for admin triage via Apex Jobs, correlated by the correlation id (P2_04 §1.5, §2.3).

### 5.5 Convert UX (the hybrid — RECOMMENDED)

- **Branch A (totalGenuineMachineClones ≤ SYNC_THRESHOLD, the 99.x% case):** today's fully synchronous tail
  UNCHANGED — instant activate, zero regression.
- **Branch B (large genuine per-machine):** return immediately to `Screen_4_Confirmation_Async`; activation +
  Workday deferred to async completion (no SLA). Workday auto-waits (fires on the normal post-activation path).
- Hybrid is acceptable AND recommended (P2_04 §3.2, §3.5): preserves instant-activate for the common case;
  only orders that would governor-crash synchronously today take the async path, for which "async with
  deferred activation" is strictly better than "fail entirely," and it mirrors the already-accepted
  manual-activation UX.

---

## 6. TEST + ROLLOUT, EFFORT, GATING DECISIONS

### 6.1 Test plan (extends DESIGN_FINAL §6; the P2-specific additions)

**Apex unit (new `PowerOrderSplitAsyncOrchestratorTest` + extend `PowerOrderSplittingServiceTest`):**
- Idempotency: re-running a build chunk on a partially-split order does NOT double-create (key on
  `Original_Order_Item__c` + count gate) — DESIGN_FINAL A18.
- ASYNC_CHUNK mode skips the sync cap but honors the per-chunk budget; SYNC mode keeps the cap (A14 variants).
- Full-field clone survives V16 context fetch (staging fields present on clones) — assert no
  "couldn't fetch SalesTransactionContextExt_v2" path.
- Finalizer: simulate UNHANDLED_EXCEPTION → terminal status written + bounded re-enqueue (≤2) then quarantine.
- resume(orderId) on Pending/In-Progress/Partial/Failed tops up only the gap; no-op when already
  Split Complete + Activated.
- SC-3210/3368 guard: clone Workday_Contract_Line_Type__c == parent (product-boolean), never reverse-lookup.
- Deferred Quantity flip: original keeps Quantity=N until its final chunk; final chunk flips to 1 exactly once.

**E2E (post-deploy, explicit auth; build fresh per-machine quotes — the documented repro quote is gone):**
- E13 (P2-contingent, DESIGN_FINAL): assetize sequencing — post-activate assetize does not race async split;
  Assets created once. **THE go/no-go spike:** confirm `PlaceOrderExecutor.execute()` actually runs from a
  Batch/Queueable against the V16 context (the one finding that, if false, kills P2 as designed — §1.1).
- Branch A unchanged (small per-machine split → instant activate).
- Branch B (large genuine per-machine, build a synthetic OLO+Partition quote at N=300/600/1000): Pending Split
  → Split In Progress → reprice → clear → activate → Split Complete; Assets + Billing Schedules created once;
  Workday send waits for async completion (validate with Workday SUPPRESSED — E11).
- Negative: seat/sentinel line (Partition null) → 0 clones, single qty-N line (P3 predicate; A16/E5) — proves
  async NEVER materializes seat lines.
- CPU/DML measurement at build: reprice ms/line and submitOrder O(N) (both unmeasured) to size the real P2
  ceiling and the chunk budget (P1_SPEC §4 harness, extended through reprice+activate).

**Coverage:** the class is 0% today (deploy blocker, org 75% gate). P2 tests + P1 tests are the coverage gate.

### 6.2 Rollout

Standard gated UAT → validate → prod, AFTER P0 (live) + P1 + P3. Coordinate line-type owners. Re-verify at
build (daily churn): V16 active proc, live `OrderRepriceInvocable` body, V6/V11 flow versions + V11
product-boolean, convert flow active version, `Split_Status__c` still absent. New CMDT/fields/PE/orchestrator
all need fresh deploy authorization — **nothing here is deployed.** UAT validate-to-activation MUST run with
Workday SUPPRESSED (the PE resubmit mechanism means an accidental publish sends real data — DESIGN_FINAL P4 /
C7).

### 6.3 Effort estimate

**~5–8 dev-days + heavy E2E (~2–3 days), IF pursued** (DESIGN_FINAL §P2 ~4–7 + the multi-stage reprice/activate
batches + Finalizer/Scheduler/resume + PE + status field + LWC + the go/no-go spike). HIGH risk: the
reprice/activate/assetize sequencing is load-bearing and must be validated E2E; the executor-runs-from-async
finding is the single biggest unknown.

### 6.4 GATING DECISIONS (state plainly)

1. **Is P2 justified by evidence? — NO, not currently.** Under the live P3 predicate, exactly **4 OrderItems
   org-wide are split-eligible, all at Quantity=3 (2 clones each)** (P1_SPEC §3, §7; DESIGN_FINAL §2). The
   largest split that has EVER succeeded org-wide is single digits (9, which then FAILED Workday); the
   largest Workday-clean is 4. **There is zero evidence of genuine per-machine volume in the thousands.** P2
   is **speculative contingency**, not an evidenced need. Build P0 (done) + P1 + P3; hold P2 on the shelf.
2. **[DECISIVE — Workday quantity=N]** Confirm with Joe/Workday owners that the contract integration takes ONE
   line with `quantity=N` (API spec + captured payload + SC-3347 mapping all converge — DESIGN_FINAL §3). **If
   yes, P3 is the resolution and P2 is DROPPED.** Per-unit splitting is unnecessary AND breaks Workday
   (SC-3210/3368 subsplit conflation).
3. **Is a genuine per-machine (Hardware/Partition-driven) split case real, and at what scale?** P2 is needed
   ONLY if Joe confirms a real per-machine materialization in the dozens–low-thousands. If not, P2 is shelf
   contingency only (DESIGN_FINAL §6 Q1/Q3).
4. **SYNC_THRESHOLD value + acceptance of no-SLA delayed activation** for large orders — size WITH Joe (default
   200; DESIGN_FINAL §6 Q5/Q6).
5. **Spike before commit:** confirm `PlaceOrderExecutor.execute()` runs from Batch/Queueable against the live
   V16 context (E13). If it cannot (context binding), P2 is INFEASIBLE as designed → fallback is hard-cap
   (P0) + P3 for everything above.

---

## 7. VERIFIED vs ASSUMED (honesty ledger)

**Verified live this wave (HIGH):**
- Reprice is an in-process Apex API (no HTTP callout, no AllowsCallouts), only input = Order Id, runs in a
  plain CurrentTransaction flow action today (P2_01 §2). Live `OrderRepriceInvocable` body confirmed
  (totalsAlreadyMatch short-circuit L45-49; clearValidationResult; isPricingReady gate).
- 10k-DML-row ceiling identical sync/async; async enqueue limit = 1; CPU 10s→60s (P2_03 §0, cheatsheet).
- No OrderItem-DML / Order-activation platform lock (RLM lock is Quote-only); `PowerOrderSplittingService`
  already does OrderItem DML in convert (P2_03 §2; P2_02 §1c).
- Activation = plain Order Status='Activated' recordUpdate; assetize V17 + billing are AsyncAfterCommit,
  Status-gated, own post-commit txns (P2_02 §1a, §2a, §3).
- `Order.Split_Status__c` ABSENT; idempotency FK (`Original_Order_Item__c`+`Is_Split_Line__c`) PRESENT; V16
  staging fields present + createable+updateable on OrderItem (P2_03 §3a; P2_01 §4).
- Convert flow already ships the manual-activation "order created without activation" UX; mature
  `*_Sync_Status__c` field family + `Order_Completed_WD__e` PE convention exist (P2_04 §0).
- Live split-eligible population = 4 lines, all N=2 (P1_SPEC §3) — the gating-decision driver.

**Assumed / point-in-time (re-verify at build):**
- `PlaceOrderExecutor.execute()` runs cleanly from async against the V16 context — established by no
  describe-lock + Quote-only RLM lock + the call already running in a plain transaction, but NOT proven by an
  actual async run (read-only). **This is the single highest-risk assumption (§1.1, gating decision 5).**
- PlaceOrderResult part-sync/part-async behavior at >100 lines is from RLM Dev Guide; the exact deferral
  threshold in THIS org is unmeasured (P2_01 §2b).
- Reprice ms/line + submitOrder O(N) cost (the real P2 ceiling + chunk budget) are estimates — measure at build
  (P1_SPEC §4).
- SC-3419 race characterization (data-shape, not timing) is from prior runtime tests, not re-run this session
  (P2_02 §7).
- Workday `line.quantity ← OrderItem.Quantity` mapping is inferred (strongly) — gating decision 2 confirms it.

**Constraints respected:** read-only (design doc, no deploy/DML/flow-run); 10k-row ceiling honored by chunking
+ P3 predicate (seat/sentinel never materialized); no Quote DML (RLM lock); SC-3210/3368 (clones inherit
parent line type verbatim; live V11 product-boolean); V16 context survival (full-field clone preserved).
