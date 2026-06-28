# SC-3447 P2 — Partial-Failure, Recovery, Status Surfacing & Convert UX (async pipeline)

**Ticket:** SC-3447 (Blocker) · **Scope:** P2 architecture — the HIGH-risk async tail · **Date:** 2026-06-27
**Author:** read-only design pass (no deploy/DML/flow-run). Every UAT deploy/DML needs a fresh explicit ack
([[feedback_uat_deploy_authorization]]).
**Org:** FortraUAT (00DWC000006eUFF2A2). Live facts re-verified this session where load-bearing.

> **P2 status reminder (DESIGN_FINAL §P2):** P2 is **DEMOTED / contingent**. Workday takes `quantity=N` on one
> line, so seat/sentinel lines must NOT be materialized at all (that is P3, the primary resolution). P2 is the
> answer ONLY for a genuine **per-MACHINE** (Hardware/Partition-driven) split that exceeds the synchronous
> ceiling — dozens to low-thousands of real machine lines. Even then the **10,000-DML-row ceiling still forbids
> seat/sentinel quantities** regardless of sync vs async. This file designs the failure/recovery/UX surface of
> that contingent pipeline so the design is complete if/when Joe confirms a real per-machine case exists.

This file covers the four task items: (1) partial-failure handling, (2) recovery for stuck orders, (3) convert
UX change + hybrid, (4) how the existing `PowerOrderSplittingService` logic is reused from async.

---

## 0. Verified org facts this design builds on (read-only, 2026-06-27)

| Fact | How verified | Why it matters |
|---|---|---|
| Order has a **mature sync-status field family**: `Workday_Sync_Status__c` (picklist: Not Sent/Pending/Success/Failure/Partial Success) + `Workday_Sync_Message__c` (textarea) + `Workday_Sync_Correlation_Id__c` (string). Same triple for **PO_** (Pending/Success/Failure), **HS_**, **Legacy_**. | `sf sobject describe Order` | **Precedent to copy verbatim.** A `Split_Sync_Status__c` + `Split_Sync_Message__c` + `Split_Sync_Correlation_Id__c` triple fits the existing convention exactly — admins already understand this pattern. No need to invent `Split_Status__c` from scratch; mirror the integration-status family. |
| Order has `Order_Integration_Error_Messages__c` (textarea, createable/updateable) | same | A ready-made, existing place to append failure detail without a new field. |
| Existing platform-event convention: `Order_Completed_WD__e` carries exactly **one field `Order_Id__c` (string)**; also `Order_Completed_Legacy__e`, `*_WD__e`, `*_HS__e`. | `sf sobject list` + `sf sobject describe Order_Completed_WD__e` | **Precedent for the completion/error PE.** A lightweight `Order_Split_Status__e` carrying `Order_Id__c` + `Status__c` + `Message__c` matches the house style; the consumer re-reads LIVE Order data (same idempotent pattern as the Workday resubmit, [[project_workday_resubmit_mechanism]]). |
| Order standard `Status` picklist = Draft / Activated / Superseded / Provisioned / Order Complete. `ValidationResult` = TransactionIncomplete / MissingContributor (null = clean). | same | The async tail must end with `Status='Activated'` and `ValidationResult=null`, exactly as the sync flow does today. **A new "Split In Progress" state must NOT live on standard `Status`** (it is RLM/lifecycle-controlled); it lives on the custom `Split_Sync_Status__c`. |
| **The convert flow ALREADY has a "Manual Order Activation" path.** `Screen1_OrderActivation` is a user toggle ("Automatic" vs manual). When NOT 'Automatic', `Decision_Activate_Order_After_Contract` / `Decision_Activate_Order_No_Contract` **skip Reprice + Activate entirely** and route straight to `Get_Created_Contract` / `Screen_4_Confirmation`. The order is left **Draft, un-activated**, and the user activates later. | convert flow `Fortra_Quote_to_Order_Conversion` V27 metadata L295-356 | **The "order exists before activation" UX is NOT new** — it already ships as the manual-activation path. The async UX models itself on this existing, accepted behavior, which de-risks task #3 enormously. |
| Convert flow has a terminal success screen `Screen_4_Confirmation` (`Screen4_SuccessHeader` = "Conversion Complete / Your Quote has been successfully converted to an Order", `Screen4_NextSteps`, `Screen_Navigate_To_Order`). | convert flow metadata L1720-2298 | The screen-flow exit point where the async-handoff message is shown. Existing copy is the template. |
| `OrderValidationTriggerHandler.bypassValidation` (public static Boolean) exists; `Is_Split_Line__c` + `Original_Order_Item__c` exist on OrderItem; all V16 shared-proc staging fields exist on OrderItem. | file 10 §1; file 03 §5 | The async path reuses these exactly — no new bypass plumbing, full-field clone preserved. |
| Existing batch infra in repo: `PbeTeardownBatch`, `RcaTeardownBatch` (Database.Batchable). `AssetizationAsyncJob` is **NOT** in force-app (managed/platform; spawned by `Fortra_Assetize_Order` V17 AsyncAfterCommit, [[project_sc3419_zero_assets]]). | `grep` force-app | A Batchable pattern already exists in the org to follow; assetize remains a separate post-activate async job we must sequence AFTER, never race. |

**Net design decision from these facts:** do **NOT** invent a bespoke `Split_Status__c` lifecycle from
nothing. Mirror the established **`<System>_Sync_Status__c` / `_Message__c` / `_Correlation_Id__c`** family,
and model the user-facing "order created, not yet activated" UX on the **already-shipping manual-activation
path**. This makes P2 a far smaller behavioral delta than the wave-1 DESIGN.md implied.

---

## 1. PARTIAL-FAILURE HANDLING

### 1.1 The committed-convert invariant (the whole point)

Step 1 (the thin synchronous convert: validate → `createOrderFromQuote` → `QuoteToOrderFieldMapper` → stamp
`Split_Sync_Status__c='Pending'` → commit) has **already committed and returned to the user** before any async
work runs. Async runs in **separate transactions** (Batch `execute()` / Queueable). Therefore:

- **An async chunk failure CANNOT roll back the committed convert.** The Order + base OrderItems already exist.
  This is the documented async guarantee ("a failure in the asynchronous processing won't cause the user's
  record save to roll back" — file 08 §"Platform Events / CDC"; `_record_triggered_guide.md`).
- **A chunk's own DML is still atomic within that chunk.** If chunk K throws, only chunk K's clones roll back
  (its transaction); chunks 1..K-1 stay committed. This is exactly why we chunk: a fresh transaction per chunk
  = a fresh failure boundary, not just a fresh 10k-row/60s budget.

### 1.2 Per-chunk `Database.SaveResult` inspection (allOrNone=false within a chunk)

Inside each chunk's clone insert, use **`Database.insert(clones, false)`** (allOrNone=false) so a single bad row
does not throw the whole chunk:

```
List<Database.SaveResult> srs = Database.insert(cloneChunk, false);
Integer ok = 0; List<String> errs = new List<String>();
for (Integer i = 0; i < srs.size(); i++) {
    if (srs[i].isSuccess()) { ok++; }
    else {
        for (Database.Error e : srs[i].getErrors()) {
            errs.add('clone slot ' + cloneChunk[i].Original_Order_Item__c + ': ' + e.getStatusCode() + ' ' + e.getMessage());
        }
    }
}
```

- **Decision rule per chunk:**
  - all rows OK → mark the chunk's source slices `Split Complete`, accumulate `ok` into a stateful counter.
  - some rows failed → record the per-row errors (capped, see §1.4), DO NOT re-mark those slices Complete; leave
    them `Pending` so the recovery path (§2) or a bounded re-enqueue can retry just the failed slices.
- **Idempotency guard (DESIGN_FINAL §P2 / file 08 §3):** every chunk first **re-queries** which slices of its
  scope are still un-materialized, keyed on `Original_Order_Item__c` (the existing qty-split FK) + the parent's
  `Split_Sync_Status__c`. A clone is "already done" if a child OrderItem with `Original_Order_Item__c = parent.Id`
  and `Is_Split_Line__c = true` already exists for that slot. So a retried chunk **never double-creates** — it
  only fills the gap. (This is why allOrNone=false + re-query is safe: re-running tops up, never duplicates.)

> **Chunking mechanism choice (from file 08):** **Batch Apex**, not a single Queueable, because each Batch
> `execute()` is a fresh 10k-row/60s transaction and Batch is the documented tool for "thousands of records." A
> Queueable's single `execute()` is still ONE 10k-row transaction — fine only for ≤ a few thousand clones. For
> the genuine-per-machine P2 range (dozens–low thousands) a **chained Queueable** is acceptable and simpler; for
> anything larger use Batch with explicit scope `Database.executeBatch(b, ~2000)`. Either way the failure-surface
> design below is identical.

### 1.3 Transaction Finalizer (the reliability backbone)

`Database.SaveResult` covers *row-level* failure inside a successful chunk transaction. It does **NOT** cover the
chunk's transaction itself dying — an **uncatchable** `LimitException` (CPU/heap), an unexpected gack, or the
platform dropping the job (flex-queue eviction). For that, attach a **Transaction Finalizer** to each Queueable
chunk (`System.Finalizer` / `attachFinalizer`), or use Batch `finish()` for the batch variant.

Verified rationale (file 08 §"Async finalizers", Apex Dev Guide *Transaction Finalizers*): a Finalizer runs
**even if the queueable's `execute()` throws an unhandled exception** — the standard way to handle partial
failure, retry, or emit a completion event.

The Finalizer (one per chunk) does:

1. Inspect `FinalizerContext.getResult()` → `SUCCESS` or `UNHANDLED_EXCEPTION`.
2. On `UNHANDLED_EXCEPTION`:
   - Read `getException()`, write a truncated message to `Order.Split_Sync_Message__c` /
     `Order_Integration_Error_Messages__c` and set `Split_Sync_Status__c='Failure'`.
   - **Bounded re-enqueue** of the SAME chunk: keep a stateful retry counter on the job (or a
     `Split_Retry_Count__c` field). Re-enqueue up to **N times (e.g. 2)**, because the idempotency guard (§1.2)
     makes a retry safe (it tops up the missing slices). After N, **quarantine** (set `Failure` + a clear
     message, stop) rather than loop forever.
   - **A Finalizer can enqueue exactly ONE Queueable** (platform rule) — so it either re-enqueues the failed
     chunk OR advances to the next chunk, never both; the chain stays single-threaded by design.
3. On `SUCCESS`: enqueue the **next** chunk (the chain link), or — if this was the last chunk — enqueue the
   **finalization Queueable** (reprice → clear ValidationResult → activate, §1.6).

> **Why Finalizer + SaveResult are both needed:** SaveResult = "some rows in a healthy chunk failed (validation,
> FLS, lock)"; Finalizer = "the whole chunk transaction died (CPU/heap/gack/eviction)". Without the Finalizer, a
> CPU-killed chunk leaves the order stuck in `Pending` with no signal — exactly the "stuck forever" failure mode
> task #2 must recover. The Finalizer is what guarantees a terminal status is ALWAYS written.

### 1.4 Re-enqueue vs quarantine policy (explicit)

| Failure shape | Detected by | Action |
|---|---|---|
| Row-level (a few clones fail FLS/validation/lock) | `Database.SaveResult.getErrors()` | Leave those slices `Pending`; next chunk/retry tops them up via idempotency guard. If still failing after the chain completes, the order ends `Partial Success` (some clones, not all) → manual recovery (§2). |
| Whole-chunk transient (lock contention, momentary platform error) | Finalizer `UNHANDLED_EXCEPTION` | **Re-enqueue same chunk**, bounded (≤2 retries), idempotent. |
| Whole-chunk structural (CPU/heap → chunk too big) | Finalizer `UNHANDLED_EXCEPTION` w/ LimitException | **Do NOT blindly re-enqueue** (will fail again). Quarantine: `Split_Sync_Status__c='Failure'`, message = "chunk exceeded limits; reduce chunk size / per-machine count" → recovery path can re-run with smaller scope. |
| Job dropped by platform flow-control (flex queue eviction, never starts) | NOT detectable by Finalizer (it never ran) → **left in `Pending`/`Split In Progress` forever** | This is the §2 recovery case: a scheduled sweep finds stale `Pending` orders and re-enqueues. |

### 1.5 Error surfacing on the Order (status field + platform event)

**Two surfaces, mirroring the existing integration-status convention:**

**(a) On the Order record (durable, admin-visible) — new `Split_` sync triple:**
- `Split_Sync_Status__c` (picklist) values: **`Not Started` / `Pending` / `Split In Progress` / `Split Complete`
  / `Partial Success` / `Failure`** — modeled on `Workday_Sync_Status__c`'s value set.
- `Split_Sync_Message__c` (textarea) — human-readable last status / error detail (truncate to field length).
- `Split_Sync_Correlation_Id__c` (string) — the async job correlation id (`AsyncApexJob.Id` / a generated GUID)
  so an admin can find the job in **Setup → Apex Jobs** and the platform-event consumers can correlate.
- (reuse existing) `Order_Integration_Error_Messages__c` to append the failing-slice detail.
- The status field flips: thin convert sets `Pending` → first chunk sets `Split In Progress` → finalization sets
  `Split Complete` (or `Partial Success` / `Failure`). **These are the keys the recovery sweep (§2) queries on.**

**(b) Platform event (real-time, decoupled) — new `Order_Split_Status__e`:**
- Fields: `Order_Id__c` (string), `Status__c` (string), `Message__c` (string) — matches the house
  `Order_Completed_WD__e` style (lightweight, Order-keyed; consumer re-reads LIVE Order data).
- Published by the Finalizer / `finish()` on **terminal** outcomes (`Split Complete`, `Partial Success`,
  `Failure`). Consumers:
  - A record-triggered-flow-free **lightweight subscriber** could post a Chatter/bell notification to the convert
    running user ("Order O-12345: line splitting complete / failed").
  - The **Lightning page** on Order can subscribe via `lightning/empApi` (an LWC) to update the on-screen status
    live without refresh — same UX the user already gets for Workday sync status.
- **Best-practice basis (WebSearch + file 08):** Salesforce's documented async-status pattern is "set a
  `Status__c` to 'pending' in the synchronous step; a separate async/scheduled job processes and updates status;
  surface completion via Platform Event / notification." Platform Events are the recommended decoupling for
  "async job done / async job failed" signals because they don't roll back the producer and are replayable up to
  72h (file 08 §"Platform Events / CDC"). Combine **durable status field (poll/refresh)** + **platform event
  (push)** — the durable field is the source of truth; the PE is the notification accelerant. This is exactly how
  the org already does Workday/PO/HS/Legacy sync status.

> **WebSearch confirmation of best practice for async job status + error surfacing to the user:** the canonical
> SF guidance (Apex Dev Guide *Transaction Finalizers*; Architect async-processing patterns; Help "Monitor
> Async Apex"): (1) use a **Transaction Finalizer** to guarantee a completion/error hook even on unhandled
> exception; (2) persist outcome to a **custom status field** on the parent record (don't rely on the user
> watching `AsyncApexJob`); (3) push a **Platform Event / Custom Notification** for real-time UX; (4) expose
> `AsyncApexJob` (Status, ExtendedStatus, NumberOfErrors) to admins via the Apex Jobs page for triage; (5) make
> the work **idempotent** so retries/replays are safe. This design implements all five.

---

## 2. RECOVERY FOR STUCK ORDERS

### 2.1 The stuck states

An order can be stranded in a non-terminal `Split_Sync_Status__c` because:
- the chain Queueable/Batch was **dropped by platform flow-control** (flex-queue eviction; the job never ran, so
  no Finalizer fired) → stuck `Pending` or `Split In Progress`;
- a chunk hit an **uncatchable LimitException** and the Finalizer's bounded re-enqueue exhausted → `Failure`
  (terminal but un-activated);
- `Partial Success` — some slices materialized, some failed FLS/lock — order has the wrong number of lines and
  is un-activated.

All three share the property: **the committed Order exists, but lines are not finalized and the order is not
activated.** None of these can self-heal without an admin-runnable resume.

### 2.2 Manual admin recovery path — "Resume Split" keyed on `Split_Sync_Status__c`

A single, idempotent, admin-runnable entry point that **re-drives the same async pipeline from where it stopped**.

**Form factor (three layers, all calling the SAME Apex resume method):**

1. **Quick Action / LWC button on the Order page** — "Resume Power Split". Visible to admins / a permission set.
   Calls `PowerOrderSplitAsyncOrchestrator.resume(orderId)` (an `@AuraEnabled` wrapper). The button is enabled
   only when `Split_Sync_Status__c IN ('Pending','Split In Progress','Partial Success','Failure')` and
   `Status != 'Activated'`. Shows the current `Split_Sync_Message__c` so the admin sees why it stalled.

2. **Bulk scheduled sweep (`Schedulable`)** — the safety net for silently-dropped jobs. A scheduled Apex
   (e.g. hourly) queries:
   ```
   SELECT Id FROM Order
   WHERE Split_Sync_Status__c IN ('Pending','Split In Progress')
     AND Status != 'Activated'
     AND LastModifiedDate < :System.now().addMinutes(-30)   // stale = dropped/stuck
   ```
   and re-enqueues each. **The 30-minute staleness fence prevents racing a healthy in-flight job.** This is the
   documented "scheduled job drains the pending state" pattern (file 08 §5: "query for all records in the pending
   state, execute the complex logic in a controlled context, update as processed"). It is also why the status
   field (not standard `Status`) carries the lifecycle: the sweep keys on it.

3. **Anonymous-apex / dev-console one-liner** for ad-hoc ops: `PowerOrderSplitAsyncOrchestrator.resume(orderId);`
   (documented runbook in P4; never auto-run; needs deploy auth like everything else).

**What `resume(orderId)` does (idempotent by construction):**
- Re-reads the order + its current `Split_Sync_Status__c`. If already `Split Complete` and `Status='Activated'`,
  no-op (returns "already done").
- Re-computes the un-materialized slices via the §1.2 idempotency guard (which `Original_Order_Item__c` parents
  still lack their full clone count). **Tops up only the gap** — never double-creates.
- Re-enters the chunked pipeline at the split stage; on completion runs the same finalization
  (reprice → clear ValidationResult → activate) (§1.6).
- Sets `Split_Sync_Status__c='Split In Progress'`, refreshes `Split_Sync_Correlation_Id__c` to the new job id,
  and re-publishes terminal status on completion.

**Why this is safe (no SC-3441 / SC-3419 re-break):** resume runs the **whole tail** (split → reprice → clear →
activate) in order, exactly like the first attempt. It never activates a half-split order, never leaves clones
unpriced, and never races assetize (activation is the final serialized step, §1.6). The idempotency key
(`Original_Order_Item__c` + `Is_Split_Line__c`) is the existing qty-split FK — no new key invented.

### 2.3 Visibility for triage
- Admins see stuck orders via a **list view / report** on `Split_Sync_Status__c NOT IN ('Split Complete') AND
  CreatedDate = last N days` — same way they triage `Workday_Sync_Status__c='Failure'` today.
- The async job itself is in **Setup → Apex Jobs** (`AsyncApexJob`: Status, ExtendedStatus, NumberOfErrors),
  correlated via `Split_Sync_Correlation_Id__c`.

---

## 3. CONVERT UX CHANGE (task #3)

### 3.1 The good news: the "order before activation" UX already exists

The single biggest de-risker (verified §0): the convert flow **already** lets the user create the order WITHOUT
activating it — the **"Manual Order Activation"** branch (`Screen1_OrderActivation != 'Automatic'`). On that
path today: order is created Draft, the flow **skips Reprice + Activate**, and lands on `Screen_4_Confirmation`
("Conversion Complete … converted to an Order") with `Screen4_NextSteps` and a `Screen_Navigate_To_Order`
button. The user activates later from the Order page.

**So "the Order exists before its lines finalize / before activation/Workday" is NOT a new, scary UX** — it is a
variant of behavior users already accept. The async path reuses this exact screen and copy, with a one-line
status addition.

### 3.2 Proposed UX (the hybrid — RECOMMENDED)

**Keep today's instant path for the common case; go async only when the per-machine split would blow the
synchronous ceiling.** This is acceptable and recommended (file 08 §5 "hybrid: synchronous activate only for
small lines under a safe qty threshold, async above"; and it is the question posed to Joe in DESIGN_FINAL §6 Q6).

**Decision point (in the thin convert, right after field-map, BEFORE the split):**
- Compute `totalGenuineMachineClones = Σ(qty-1)` over lines that pass the **P3 per-machine predicate** (real
  `Partition_Record__c` / Hardware, NOT seat counts — already the live `queryOrderItemsToSplit` WHERE clause).
- **Branch A — `totalGenuineMachineClones <= SYNC_THRESHOLD`** (e.g. the CMDT `Max_Sync_Clones__c`, default 200):
  **run today's fully synchronous tail unchanged** (split → reprice → activate inline). User gets the instant
  "Conversion Complete" + activated order, exactly as now. **No UX change for the 99.x% common case.**
- **Branch B — `totalGenuineMachineClones > SYNC_THRESHOLD`** (genuine large per-machine order):
  - Thin convert commits the base order, stamps `Split_Sync_Status__c='Pending'`, enqueues the async chain, and
    **returns immediately** to a NEW terminal screen variant `Screen_4_Confirmation_Async`:
    > **Order created — line splitting in progress**
    > "Your Quote was converted to Order {OrderNumber}. Because this order has {N} per-machine lines, the lines
    > are being created and priced in the background. You'll be notified when it's ready to activate; you can also
    > check the **Split Status** field on the order. Activation and Workday submission happen automatically once
    > splitting completes."
  - `Screen_Navigate_To_Order` button → the Order page, where the user watches `Split_Sync_Status__c`
    (live via the `Order_Split_Status__e` LWC subscriber, §1.5b) progress Pending → Split In Progress →
    Split Complete → (auto) Activated.

### 3.3 Activation + Workday timing in Branch B
- **Activation is NOT performed by the screen flow** in Branch B. It is the **last step of the async chain**
  (finalization Queueable, §1.6): reprice the now-N-line order → clear `ValidationResult` → set
  `Status='Activated'`. Only then do the existing AsyncAfterCommit Order automations fire
  (`Fortra_Order_to_Billing_Schedule`, `Fortra_Assetize_Order`) — exactly as they do after a sync activate, just
  later in wall-clock.
- **Workday** (`Order_Completed_WD__e` / the send screen) fires on the normal post-activation path, so it
  **automatically waits** for async completion — no separate change needed. The user does NOT (and must not)
  send to Workday before lines finalize.
- **Honors the activate-LAST constraint** (file 03 §2): split → reprice → clear → activate, never activate a
  1-line order. Never re-creates SC-3441 (null price on clones landing on an active order) or SC-3419 (assetize
  racing async OrderItem DML) because activation only runs after every chunk is committed and repriced.

### 3.4 What the user sees — summary table

| Case | Convert returns | Order Status at return | What finalizes the order | User-visible signal |
|---|---|---|---|---|
| Manual-activation (exists today) | "Conversion Complete" | Draft | user clicks Activate later | none new |
| **Branch A** (small/no per-machine split — the common case) | "Conversion Complete" (today's screen) | Activated (if auto-activate chosen) | synchronous, inline | none new |
| **Branch B** (large genuine per-machine split) | "Order created — splitting in progress" (new variant) | Draft, `Split_Sync_Status__c=Pending` | async chain → reprice → activate | live `Split_Sync_Status__c` + `Order_Split_Status__e` notification |
| Branch B failure | "Order created — splitting in progress" (same) | Draft, ends `Failure`/`Partial Success` | recovery / Resume Split (§2) | `Failure` status + message + notification |

### 3.5 Is the hybrid acceptable? — YES, and recommended
- **Preserves today's instant-activate for the common case** (Branch A) — zero regression for the vast majority
  of converts (largest real per-machine split ever seen org-wide is single digits; seat lines go to P3 and never
  enter the split at all).
- Only genuine large per-machine orders (which **cannot** complete synchronously anyway — they'd governor-crash
  today) take the async path. For them, "async with no instant activation" is strictly better than "fails
  entirely," and it mirrors an already-accepted UX (manual activation).
- **Must be sized with Joe** (DESIGN_FINAL §6 Q5/Q6): the `SYNC_THRESHOLD` value (start at the CMDT default 200)
  and confirmation that delayed activation is acceptable for large orders (no SLA on async — file 08 §5). Note
  again: **even async cannot persist seat/sentinel quantities** (10k-row ceiling) — those are P3, never P2.

---

## 4. REUSING `PowerOrderSplittingService` FROM ASYNC (task #4)

### 4.1 Principle: call the SAME split Apex, just from a Queueable/Batch, cap removed/raised for async

The async pipeline must NOT fork/duplicate the split logic. It reuses the verified, tested clone logic in
`PowerOrderSplittingService` (the P0+P3 class). The only changes are (a) make the core callable per-chunk from an
async context, and (b) replace the single sync cap with a per-chunk-size + async-ceiling model.

### 4.2 Current structure (verified, force-app `PowerOrderSplittingService.cls`)

- `@InvocableMethod splitPowerOrderLines(List<SplitRequest>)` → builds `orderIds` + `resultByOrderId` →
  calls `processOrders(orderIds, resultByOrderId)` (L38-60).
- `processOrder(Id)` (L96) — backward-compatible single-order shim → delegates to the invocable.
- **`private static void processOrders(Set<Id> orderIds, Map<Id,SplitResult>)` (L108)** — the real engine:
  captures pre-`ValidationResult`, savepoint, `queryOrderItemsToSplit` (P3 per-machine WHERE clause, L389-396),
  the `MAX_SYNC_CLONES` cap check (L137), Phase 1–8 (build clones → insert HW → insert clones → update originals
  → clone partitions → wire partitions → restore ValidationResult), catch+rollback.

### 4.3 The refactor (minimal, surgical)

**(1) Make `processOrders` callable from async, per-chunk, cap-parameterized.**
- Change visibility from `private` to **`public static`** so a Queueable/Batch in the same namespace can call it
  directly (it is currently only reachable via the invocable).
- **Replace the hard-coded `MAX_SYNC_CLONES` static with the CMDT-backed `getMaxSyncClones()`** (this is already
  P0/C4 scope in DESIGN_FINAL §P0) AND add an overload that takes an explicit **mode/cap**:
  ```
  public enum SplitMode { SYNC, ASYNC_CHUNK }
  public static void processOrders(Set<Id> orderIds, Map<Id,SplitResult> r, SplitMode mode)
  ```
  - `SYNC` → keep the current cap check (bail with friendly error above `getMaxSyncClones()`).
  - `ASYNC_CHUNK` → **skip the sync cap** (the async caller has already chunked to a safe per-transaction size);
    the only ceiling that still applies is the **per-chunk 10k-DML-row** budget, which the orchestrator enforces
    by scoping. The existing 1-arg `processOrders` keeps its current behavior by delegating with `SYNC`.
- **`queryOrderItemsToSplit(orderIds)` is reused unchanged** — the P3 per-machine predicate (real
  Partition/Hardware) is exactly the right gate for async too: seat/sentinel lines must never enter even the
  async path (10k-row ceiling). For chunking, add an overload that also accepts a slice bound (e.g. process only
  the first K un-materialized slots per original, or a sub-range of orders) so each chunk stays under 10k rows.
- **`createFullClone` is reused unchanged** — preserves the FULL-FIELD copy that carries the V16 shared-proc
  staging fields (`Pre_Partner_Price__c`, `Partner_Pricing_Source__c`, `RegionalNetUnitPrice__c`, etc., file 03
  §5). A "lite" clone would re-trigger the "couldn't fetch SalesTransactionContextExt_v2" incident
  ([[project_v16_order_pricing_contextfetch_incident]]). The P1 describe-hoist optimization (P1#1) applies
  equally and benefits the async path.
- **The per-clone flow suppression is reused unchanged** — clones carry `Is_Split_Line__c=true` before insert →
  the `Is_Split_Line__c=false` Start entry conditions on `Fortra_OrderItem_Set_Dates` (V6) and
  `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (V11) skip them (P1#2b). Apex-stamps clones (P1#2a). This is
  the same suppression the sync path uses; no async-specific variant.

**(2) New thin orchestrator class `PowerOrderSplitAsyncOrchestrator` (the async wrapper):**
- `enqueue(Id orderId)` — called by the thin convert (Branch B). Stamps `Split_Sync_Status__c='Pending'`,
  computes chunk plan, enqueues the first chunk Queueable (or `Database.executeBatch`).
- `SplitChunkQueueable implements Queueable, Database.AllowsCallouts?` (no callouts needed for split) — each
  `execute()`:
  1. set `Split_Sync_Status__c='Split In Progress'` (first chunk only);
  2. call `PowerOrderSplittingService.processOrders({orderId}, results, SplitMode.ASYNC_CHUNK)` scoped to this
     chunk's slice;
  3. inspect `Database.SaveResult` (§1.2), update progress;
  4. `System.attachFinalizer(new SplitChunkFinalizer(orderId, chunkNo, retryCount))` (§1.3) which either
     re-enqueues this chunk (bounded), enqueues the next chunk, or — if last — enqueues `SplitFinalizeQueueable`.
- `SplitFinalizeQueueable` — the §1.6 tail: reprice (`OrderRepriceInvocable.repriceOne` /
  `PlaceOrderExecutor` with `PricingPreference=System` + `isHighVolumeLineItems`, per DESIGN.md §P2 / file 09) →
  clear `Order.ValidationResult=null` → `Status='Activated'` → set `Split_Sync_Status__c='Split Complete'` →
  publish `Order_Split_Status__e`. **This is the only place activation happens in Branch B.**
- `resume(Id orderId)` — the §2 recovery entry; re-enters `enqueue` after the idempotency top-up computation.
- `SplitResumeScheduler implements Schedulable` — the §2.2 stale-sweep.

**(3) The invocable stays for Branch A / the sync path.** `splitPowerOrderLines` is unchanged externally; the
convert flow's `SplitPowerOrderLines` action still calls it in Branch A. The async path simply calls the now-
public `processOrders(..., ASYNC_CHUNK)` directly, bypassing the invocable wrapper (invocables can't be called
from Queueable cleanly anyway). **Same logic, two entry points.**

### 4.4 What does NOT change (guardrails honored)
- **No Quote DML** anywhere (RLM lock, [[project_rlm_quote_dml_lock]]) — the async path touches OrderItem only.
- **Clones inherit parent line type verbatim** (full-field copy) — does not re-break SC-3210/3368; the live V11
  flow is product-boolean (no reverse-lookup, DESIGN_FINAL C1). Re-verify V11 at build (daily churn).
- **V16 shared-proc context** survives because the full-field clone is preserved.
- **10k-DML-row ceiling** is honored by per-chunk scoping; **seat/sentinel quantities are still excluded** by the
  P3 predicate — async does NOT make them splittable (DESIGN_FINAL §P2 ceiling note).
- **Assetize sequencing** (SC-3419): activation (hence assetize) is the FINAL serialized step in
  `SplitFinalizeQueueable`, after all chunk DML committed — never races the async split.

---

## 5. New metadata this design implies (for P4 packaging, if P2 is ever built)

| Component | Type | Purpose | Precedent |
|---|---|---|---|
| `Split_Sync_Status__c` | Order picklist (Not Started/Pending/Split In Progress/Split Complete/Partial Success/Failure) | durable status + recovery key | `Workday_Sync_Status__c` |
| `Split_Sync_Message__c` | Order textarea | last status / error detail | `Workday_Sync_Message__c` |
| `Split_Sync_Correlation_Id__c` | Order string | job id correlation → Apex Jobs page | `Workday_Sync_Correlation_Id__c` |
| `Split_Retry_Count__c` | Order number (optional) | bounded re-enqueue counter | n/a (or hold in stateful job) |
| `Order_Split_Status__e` | Platform Event (`Order_Id__c`, `Status__c`, `Message__c`) | real-time push to UX/notification | `Order_Completed_WD__e` |
| `PowerOrderSplitAsyncOrchestrator` | Apex (Queueable orchestrator + Finalizer + Schedulable + resume) | async pipeline | `PbeTeardownBatch` (batch pattern) |
| `Screen_4_Confirmation_Async` | convert-flow screen variant | Branch B "splitting in progress" UX | `Screen_4_Confirmation` |
| `SC3447_Split_Config__mdt.Max_Sync_Clones__c` | CMDT (already P0) | SYNC_THRESHOLD + kill-switch | new (P0) |
| Resume-Split Quick Action / LWC + perm set | UI | admin recovery | n/a |

> Reuse `Order_Integration_Error_Messages__c` (exists) for appended failing-slice detail rather than a new field.

---

## 6. Honesty ledger

**Verified live this session (HIGH):** Order `*_Sync_Status__c/_Message__c/_Correlation_Id__c` family + values;
`Order_Integration_Error_Messages__c`; `Order_Completed_WD__e` = single `Order_Id__c`; 23 `__e` objects + house
naming; Order standard Status/ValidationResult value sets; **the convert flow's existing manual-activation branch
(order created without activation → Screen_4_Confirmation)** and the `Screen1_OrderActivation` toggle;
`Screen_4_Confirmation` success copy; existing batch classes in repo; `AssetizationAsyncJob` not in force-app;
`PowerOrderSplittingService` structure (processOrders private, P3 predicate, MAX_SYNC_CLONES static).

**Design/recommended (not yet built — P2 is contingent):** the `Split_` field family, `Order_Split_Status__e`,
the orchestrator/Finalizer/scheduler classes, the async confirmation screen, the hybrid threshold. None deployed.

**Best-practice basis (file 08 + WebSearch grounding):** Transaction Finalizer for guaranteed completion/error
hook on unhandled exception; `Database.SaveResult` (allOrNone=false) for row-level partial failure;
status-field-then-scheduled-drain pattern; Platform Events for decoupled, non-rollback-coupled, replayable async
notification; idempotency keyed on the existing FK; expose `AsyncApexJob` to admins.

**Re-verify at build (daily churn):** V16 active proc, live `OrderRepriceInvocable` body, V6/V11 flow versions +
V11 product-boolean, convert flow active version (V27→V28 after P0). And — gating all of P2 — **Joe's
confirmation that a genuine large per-machine split case exists at all** (DESIGN_FINAL §6 Q1/Q3); if not, P2 is
dropped and this design is shelf-ready contingency only.
