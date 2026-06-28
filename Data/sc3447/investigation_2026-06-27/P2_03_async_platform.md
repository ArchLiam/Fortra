# SC-3447 P2 — Async Platform Mechanics + RLM Async-DML Constraints + Split_Status__c Design

**Date:** 2026-06-27  **Org:** FortraUAT (00DWC000006eUFF2A2)  **Mode:** strictly read-only
(Tooling queries, FieldDefinition describe, official-doc WebSearch, local cheatsheet).
**Scope:** P2 = move the WHOLE Split→Reprice→Activate tail OFF the synchronous convert into a CHUNKED
async pipeline. This file answers the 4 platform-mechanics questions; the convert-flow re-sequencing and
the load-bearing "tail moves together / activate LAST" dependency are established in
`03_reprice_activate_async.md` and `DESIGN_FINAL.md §P2`. **P2 remains DEMOTED/CONTINGENT** (per
DESIGN_FINAL §3): Workday accepts quantity=N, so P3 (keep qty-N, split only genuine per-machine lines)
is the primary resolution; P2 is needed ONLY if a genuine per-machine materialization in the
dozens–low-thousands range is confirmed. Even perfectly chunked, P2 **cannot** persist seat/sentinel
quantities (999,999 / 750,000) because the **10,000 DML-rows-per-transaction ceiling is identical in
sync and async** — that population is P3's job, not P2's.

---

## 0. The one limit that decides everything (verified, local cheatsheet + cheatsheet drift confirm)

| Limit | Synchronous | **Asynchronous** | Source |
|---|---|---|---|
| DML rows processed per transaction | 10,000 | **10,000 (SAME)** | cheatsheet L66-67 |
| CPU time | 10,000 ms | **60,000 ms** | cheatsheet (async raises CPU) |
| Heap | 6 MB | **12 MB** | cheatsheet L89 |
| SOQL queries | 100 | **200** | cheatsheet L53 |
| SOQL rows | 50,000 | 50,000 (same) | cheatsheet L55 |
| DML statements | 150 | 150 (same) | cheatsheet L64 |
| **`System.enqueueJob` jobs per txn** | **50** | **1** | **cheatsheet L84-85** ← decisive |
| `@future` methods per invocation | 50 | **0 in batch/future; 50 in queueable** | cheatsheet L78-82 |

**Decisive facts:**
1. **Async does NOT raise the 10k DML-row ceiling — it only raises CPU (10s→60s) + heap (6→12MB) + SOQL
   (100→200).** Therefore async needs **CHUNKING** (each chunk = a fresh transaction with its own 10k
   budget) to exceed 10k rows in aggregate. A single Queueable / single @future cannot exceed 10k rows.
2. **Inside an async transaction you may enqueue only ONE job** (`System.enqueueJob` async limit = 1).
   This is what makes a *self-chaining Queueable* (each instance enqueues exactly one successor) legal,
   and it forbids fan-out (you cannot enqueue 10 chunk-jobs from a Queueable). Batch Apex is NOT
   enqueue-limited — the platform's batch engine sequences `execute()` chunks for you, outside the
   1-per-txn enqueue rule.

---

## 1. Batch vs Queueable for "build N clones in chunks of ~2k, then reprice, then activate" (TASK 1)

### 1a. The shape of the work
Per the partition path, each clone costs **~3 DML rows**: insert OrderItem (Phase 4) + insert Partition
(Phase 6) + update OrderItem partition-ref (Phase 7); the OLH path adds an inserted Hardware (+~1).
`PowerOrderSplittingService.cls` confirms the phases (L218 HW insert, L245 OI insert, L304 Partition
insert, L327 OI partition update). So **DML rows ≈ 3×N (OLO) to ~4×N (OLH)**. The 10k-row ceiling
therefore caps a single transaction at **~3,300 OLO clones / ~2,500 OLH clones** before chunking is
mandatory — independent of CPU. The reprice tail then bulk-UPDATEs all lines ~4× (seedFromWork +
persistFromWork×2 + OrderCommercialNetService.patch), so reprice alone is **O(N) DML and O(N) CPU**.

### 1b. Why Batch Apex, not a single Queueable, not a Queueable fan-out

| Mechanism | Fit for chunked N-clone build + reprice + activate | Verdict |
|---|---|---|
| **Single Queueable** | One transaction → one 10k-row budget. Cannot build > ~3,300 clones. No native chunk loop. | **NO** — same row ceiling as sync; only buys CPU. |
| **Queueable fan-out** (enqueue M chunk-jobs at once) | **Illegal**: async `enqueueJob` limit = 1. Cannot enqueue M>1 successors from within an async txn. | **NO** |
| **Self-chaining Queueable** (each chunk enqueues exactly ONE successor for the next chunk) | Legal (1 enqueue/txn). Each chunk = fresh 10k/60s txn. Works, but YOU hand-roll cursor/offset state, chunk sizing, and resume. No platform `start()` QueryLocator, no `finish()`. | **Viable fallback**, more code/risk. |
| **Batch Apex** (`start` QueryLocator → `execute` per scope → `finish`) | Platform sequences chunks; each `execute()` = fresh 10k/60s txn; `Database.executeBatch(this, scopeSize)` sets the chunk size; `finish()` is the natural "reprice→clear→activate AFTER all chunks" hook; `Database.Stateful` carries per-chunk results. **Built for exactly this.** | **RECOMMENDED** |

**Recommendation: Database.Batchable (Database.Stateful, with a Transaction Finalizer or a chained
finish-Queueable for the reprice/activate tail).**

- **Why Batch over self-chaining Queueable:** the batch engine *natively* breaks N into chunks and
  resets governor limits between `execute()` calls (cheatsheet/limits doc), so the 10k-row ceiling is
  applied PER CHUNK, not in aggregate — exactly the requirement. It also gives a single `finish()`
  rendezvous to run the reprice→clearValidationResult→activate tail ONLY after all clones are committed
  (the load-bearing "activate LAST" sequencing from `03_reprice_activate_async.md §2`). A Queueable
  chain has no built-in "all chunks done" rendezvous; you must detect terminal-chunk yourself.

### 1c. Chunk size with headroom

- **Build phase chunk size = 1,500 originals' worth of clones, i.e. cap each `execute()` scope so it
  emits ≤ ~1,500 clones** → ~4,500 DML rows on the partition path (1,500 × 3) — comfortably under 10k
  with >50% headroom for the per-chunk Order-header floor + any partition/hardware variance. The task's
  "~2,000" is acceptable (≈6,000 rows, still <10k) but **1,500 is the safe recommendation** because the
  OLH path is ~4 rows/clone (1,500×4 = 6,000) and reprice-phase re-DML must also fit if reprice ever
  runs per-chunk.
- **The batch scope is NOT the clone count.** Batch `execute()` scope = the list of *original*
  OrderItems to expand. Because one original at qty=N produces N−1 clones, a scope of even ONE
  high-qty original can blow 10k rows. So the batch CANNOT be "scope = originals, scopeSize=fixed";
  it must be **a self-bounding clone-budget loop**: the batch start-query returns split-eligible
  originals; each `execute()` materializes clones up to a soft budget (~1,500), persists, stamps the
  original's progress, and **defers the remainder of an oversized original to the next chunk**
  (cursor = (originalId, nextSlotIndex)). This is the only structure that honors the 10k ceiling when a
  single original's N exceeds the chunk budget.
- **Headroom math:** 1,500 clones × 3 rows = 4,500 build rows; the per-chunk Order-header O(1) floor
  (~15 cheap flow interviews, file `10`) is negligible CPU and 0 extra OrderItem DML rows. At
  ~4–10 ms/clone post-P1 (P1_SPEC removes the 208-describe + 3-flow per-clone amplifier), 1,500 clones
  ≈ 6–15s CPU — fits the 60s async budget with margin.

### 1d. Reprice + activate placement
- **Do NOT reprice per build-chunk** (re-pricing the partial order N/1500 times is wasteful and the V16
  Force reprice over a partial line set produces wrong totals vs Quote). Reprice **once, after all clones
  committed**, in `finish()` — BUT reprice is itself O(N) (one PATCH/OrderItem in
  `OrderRepriceInvocable`, L57-61) and the four bulk OrderItem UPDATE passes are O(N) DML. So at high N
  the reprice tail ALSO exceeds 10k rows / 60s and must itself be a **second Batch/chunked pass**
  (chunked reprice), with **activate only after the reprice batch's own `finish()`**. This is the
  multi-stage pipeline:
  `Batch A (build clones, chunked)` → `finish A enqueues` → `Batch B (chunked reprice)` →
  `finish B` → `single activate txn` (Status='Activated', the only step that must be O(1) header DML).
- **Activate is one Order-header UPDATE** (Status→'Activated') — O(1) DML, but it kicks native
  `submitOrder` (Revenue Orchestrator) whose INTERNAL cost is O(line-count) on the same async budget
  (file `10 §4.2`). At extreme N even the activate transaction's managed `submitOrder` can hit CPU; this
  is a hard RCA ceiling P2 cannot chunk (managed code), reinforcing that **sentinel/750k populations are
  not viable under P2 at all** — they need P3.

---

## 2. RLM async-DML lock on OrderItem? (TASK 2)

**Verdict: NO platform lock blocks OrderItem insert/update in async Apex on this RLM org (unlike the
RLM Quote-DML lock).** Evidence and caveats:

1. **No analogue to the Quote lock.** Memory `project_rlm_quote_dml_lock`: RLM/Subscription-Management
   blocks ALL **Quote** DML at the platform trigger tier (Apex == REST error, no workaround). That block
   is Quote-specific. **OrderItem has no such block** — `PowerOrderSplittingService` TODAY successfully
   inserts qty−1 clone OrderItems and updates originals **inside the synchronous convert transaction**;
   the failure mode is **CPU time**, not a DML-blocked platform error. OrderItem describe shows
   createable/updateable/deletable = true (same posture as the non-blocked path).
2. **Async OrderItem DML is permitted.** Nothing in the async-engine limitations forbids OrderItem
   insert/update from Batch/Queueable. The Quote lock is runtime-trigger-tier and Quote-scoped; it does
   not project onto OrderItem in async. (Verified by absence: no RLM doc enumerates an OrderItem async
   DML restriction; the documented async-engine limitations concern callouts/mixed-DML/ordering, not an
   OrderItem write ban.)
3. **`PlaceOrderExecutor.execute(... Force ...)` from async = the real risk, not raw DML.** The reprice
   step is not plain DML — it invokes the managed RCA pricing engine (`commerceorders.PlaceOrderExecutor`,
   `OrderRepriceInvocable` L64). This is a heavy managed operation; running it from Batch is supported in
   principle (it is ordinary Apex), but it: (a) consumes the async CPU budget with O(N) managed work;
   (b) requires the V16 proc + `SalesTransactionContextExt_v2` context to resolve — which needs the
   shared-proc staging fields present on BOTH QLI and OrderItem and BOTH context nodes
   (`project_v16_order_pricing_contextfetch_incident`); clones MUST keep the full-field copy or the
   context fetch HARD-FAILS in the async txn (file `03 §5`). **Mitigation in P2 reprice:** prefer
   `PricingPreference=System` + RLM high-volume line-item handling over blanket `Force` where the totals
   already match, to reduce managed CPU (DESIGN_FINAL §P2). `Force` is only needed when Quote totals ≠
   Order totals.
4. **Activation = one OrderItem-free Order-header UPDATE; allowed in async.** Setting Status='Activated'
   in a Batch `finish()` / chained job is a normal Order UPDATE. The **constraint is sequencing, not a
   lock**: per Salesforce docs the Activated state means the order "is complete and cannot be changed"
   (Order Activation Limitations) — so **all OrderItem DML (build + reprice + ValidationResult-clear)
   MUST finish BEFORE activate**. Mutating OrderItems after activate re-dirties RC pricing/validation
   state and re-creates the SC-3441 null-price + SC-3419 0-Asset class defects (file `03 §2`).
5. **Assetization race (SC-3419) is the load-bearing async ordering rule.** `Fortra_Assetize_Order` V17
   is `AsyncAfterCommit` + `Status='Activated'`-gated → `AssetizationAsyncJob` (file `10 §2b`). The P2
   build/reprice async DML must COMPLETE before activate, and activate must be the FINAL serialized step,
   so the post-activate assetize job never interleaves with split DML (the SC-3419 optimistic-lock
   swallow). `OrderCommercialNetService` header even warns the inverse race: re-running
   `PartnerNetPricePosthook` at activation can leave `createOrUpdateAssetFromOrder` stuck at
   ContextPersistence without spawning the assetize job. **Net rule: build → reprice → clear
   ValidationResult → activate, each fully committed before the next; assetize fires only after the final
   activate, untouched by P2.**

**Bottom line for TASK 2:** OrderItem insert/update + Order activation CAN happen in async on this
RLM org. There is no OrderItem-DML platform lock. The hard constraints are (i) the 10k-row ceiling
(needs chunking), (ii) activate-LAST sequencing, (iii) assetize-after-activate non-race, and (iv)
context-fetch survival (full-field clones + staging fields on both objects/context nodes). None of
these is a "lock"; all are sequencing/limit constraints the chunked pipeline must honor.

---

## 3. `Order.Split_Status__c` field design (TASK 3)

### 3a. Existence — VERIFIED ABSENT (must be created)
`FieldDefinition WHERE EntityDefinition.QualifiedApiName='Order'` for `Split_Status__c` → **0 rows**
(only `ValidationResult` and `CalculationStatus` returned, both non-calculated Picklists — i.e. writable
gate fields). The idempotency FK already exists: `OrderItem.Original_Order_Item__c` (Lookup→OrderItem)
and `OrderItem.Is_Split_Line__c` (Checkbox) are both LIVE (FieldDefinition confirmed). **So the only new
field P2 needs is `Order.Split_Status__c`.**

### 3b. Field definition (design)
- **Object:** Order. **API name:** `Split_Status__c`. **Type:** Picklist (restricted), default = first
  value. **Not** a formula/rollup (must be writable by the convert flow and the batch). **FLS:** visible
  to the integration/convert running user + admins; read-only on layout (system-managed).
- **Picklist values + state machine:**

| Value | Meaning | Set by | Next |
|---|---|---|---|
| **Not Required** (default) | Convert produced no split-eligible Power line; nothing to do. | Convert flow (thin sync), when no qualifying Power line. | terminal |
| **Pending Split** | Order committed; split work enqueued but not started. | Convert flow, stamped + committed BEFORE enqueuing the batch. | → Split In Progress |
| **Split In Progress** | Build batch is running / partially done. | Batch `start()` (or first `execute()`), transitionally. | → Split Complete / Split Failed |
| **Split Complete** | All clones built, repriced, ValidationResult clear, order Activated. | The terminal `finish()`/activate step. | terminal |
| **Split Failed** | A chunk failed irrecoverably; convert NOT rolled back; needs admin recovery. | Transaction Finalizer / `finish()` on error. | → (admin "resume split") → Pending Split |

  (Optional sixth value **Reprice In Progress** between Split In Progress and Split Complete if the
  reprice batch is a separate stage you want observable; otherwise fold into Split In Progress.)

### 3c. How the thin convert flow stamps 'Pending Split' and commits BEFORE enqueue
The synchronous convert (V28+) becomes thin: `Validate_Checklist_Complete` →
`Call_Create_Order_From_Quote` (native RLM) → `MapQuoteLineFieldsToOrderItems` → **decision: any
split-eligible Power line?**
- **No** → set `Order.Split_Status__c='Not Required'`, then continue the EXISTING sync tail
  (Reprice→Activate) unchanged — small orders never go async (preserve today's UX).
- **Yes** (and clone count > the sync ceiling, e.g. the existing P0 `MAX_SYNC_CLONES`=200 guard) → set
  `Order.Split_Status__c='Pending Split'` and **commit the Order header UPDATE**, then in a SUBSEQUENT
  action call an `@InvocableMethod` that does `Database.executeBatch(new PowerSplitBatch(orderId), 1500)`.
  Do **NOT** split/reprice/activate inline. The flow returns to the user with the Order created + status
  'Pending Split' (async UX: order exists before lines finalize; activation + Workday wait for async
  completion — no SLA; DESIGN_FINAL open question Q6).
  - **Why commit before enqueue:** the batch runs in a separate transaction and must READ a committed
    'Pending Split' status to (a) confirm it owns the work and (b) make the work idempotent (§4). If the
    flow enqueued in the same uncommitted unit and the convert later rolled back, you'd have an orphan
    job referencing a non-existent order. Flow's action ordering + the platform's commit-then-async
    contract guarantees the header UPDATE is committed before the async job dequeues.
  - **Hybrid threshold:** keep the P0 sync ceiling as the sync/async switch — under it, split sync
    (today's path, fast UX); over it, go async. (DESIGN_FINAL §P2 / Q6: "hybrid sync under a small
    threshold, async above".)

---

## 4. Idempotency — never double-create clones on re-run/retry (TASK 4)

**Idempotency key = the existing `OrderItem.Original_Order_Item__c` FK + per-original progress, gated by
`Order.Split_Status__c`.** No new key is needed beyond `Split_Status__c`.

### 4a. The invariant
For any original split-eligible OrderItem `O` with stored `Quantity_To_Split = N` (captured at
'Pending Split' time — see 4d), the order is "fully split for O" iff:
`count(OrderItem WHERE Original_Order_Item__c = O.Id) == N - 1` AND `O.Quantity == 1`.
A clone is uniquely attributable to its original via `Original_Order_Item__c`; the batch NEVER inserts a
clone whose `(Original_Order_Item__c, slotIndex)` already exists.

### 4b. Per-chunk transition (the safe step)
Each `execute(scope)` does, in ONE committed transaction:
1. Re-query, for each original in scope, the **existing** clone count
   `existingClones = count(OrderItem WHERE Original_Order_Item__c = :O.Id)`.
2. Compute `remaining = (N - 1) - existingClones`. If `remaining <= 0`, **skip** this original
   (already fully split — idempotent no-op on re-run).
3. Materialize up to `min(remaining, chunkBudget)` clones, assigning `slotIndex = existingClones+1 …`,
   insert (Phase 4), partitions (Phase 6), partition-ref update (Phase 7).
4. When an original reaches `existingClones == N-1`, set `O.Quantity=1` + redistribute amounts
   (the existing Phase 5 in-place update) and unmark — this happens exactly once because step 2's count
   gate prevents re-entry.
   Note: the **original's Phase-5 `Quantity=N→1` flip is the irreversible operation** — once flipped,
   N is no longer readable from the live Quantity, which is why `N` must be persisted at enqueue time
   (4d), not re-derived from the original after partial splitting.

Because each chunk re-derives `existingClones` from committed data, a chunk that re-runs (Apex retry,
finalizer re-enqueue, admin resume) **observes the clones the prior attempt committed and only fills the
gap** — never double-creates.

### 4c. How a resumed batch skips already-split originals
- The batch `start()` QueryLocator selects only originals that are **not yet fully split**:
  `SELECT ... FROM OrderItem WHERE OrderId IN :pendingOrders AND <Power-split-eligible> AND
   (SELECT COUNT() ...) < Quantity_To_Split - 1` — i.e. it self-excludes completed originals. (Subquery
  COUNT is not directly expressible in the locator; in practice `start()` returns all eligible originals
  and `execute()` applies the 4b count gate, which is equivalent and cheaper to reason about.)
- `pendingOrders` = `Order WHERE Split_Status__c IN ('Pending Split','Split In Progress','Split Failed')`
  — so a crashed batch left at 'Split In Progress', or a quarantined 'Split Failed' order, is re-picked
  by an admin "resume split" action (DESIGN_FINAL C7 / §P4) WITHOUT double-creating, because the 4b gate
  holds regardless of how the batch was (re)started.
- The terminal `finish()`/activate step is itself idempotent: it only flips to 'Split Complete' +
  Activates when EVERY in-scope original satisfies `existingClones == N-1`; if any are short it re-enqueues
  the build stage (or marks 'Split Failed') rather than activating a partially-split order.

### 4d. Persisting N (the one extra piece of state)
Because Phase 5 destroys the original's Quantity (N→1), the batch must know N independently. Two options:
- **Preferred:** capture N at 'Pending Split' stamp time into a per-original field (reuse or add an
  OrderItem number field, e.g. stamp `Quantity_To_Split__c` on each eligible original before commit) so
  the batch's 4b gate compares `existingClones` against a stable target even after Phase 5 has flipped
  some originals. (`Original_Order_Item__c` on clones + this target on originals = the full idempotency
  state.)
- **Alternative (no new field):** only flip the original's Quantity in the FINAL chunk that completes it
  (defer Phase 5 until `existingClones == N-1`), so until completion the live `Quantity` still equals N
  and the gate can read it directly. This keeps idempotency state to `Original_Order_Item__c` +
  `Split_Status__c` ONLY (no new OrderItem field) at the cost of the original carrying Quantity=N (and
  thus wrong line amount) until its last chunk commits — acceptable because reprice runs AFTER all chunks
  anyway. **This is the leaner design** and avoids a second new field; recommend it unless a target field
  is wanted for observability.

### 4e. Partial-failure recovery (idempotency's safety net)
- A **Transaction Finalizer** attached to each chunk Queueable (or `Database.RaisesPlatformEvents` +
  `finish()` SaveResult inspection in Batch) records per-chunk success on the Order and, on
  `UNHANDLED_EXCEPTION`, can re-enqueue the failed slice or set `Split_Status__c='Split Failed'`. Because
  the next attempt re-applies the 4b count gate, re-enqueue is safe. **A failed async chunk does NOT roll
  back the committed convert** (the Order + 'Pending Split' status persist) — the order is recoverable,
  never lost. (Finalizer + Queueable run in separate transactions, so the finalizer's re-enqueue is a
  fresh unit — verified in the Transaction Finalizers doc.)

---

## 5. Net P2 platform verdict

- **Mechanism:** **Batch Apex** (`Database.Batchable`, `Database.Stateful`) for the build stage and a
  second chunked Batch for the reprice stage, with a single terminal activate transaction. Chunk
  budget **~1,500 clones/execute (~4,500 DML rows, >50% headroom under 10k)**. Self-chaining Queueable is
  the fallback but hand-rolls chunking/resume. Single Queueable / Queueable fan-out are RULED OUT (10k
  row ceiling + async enqueue limit = 1).
- **RLM async DML:** **no OrderItem/Order-activation lock** (the RLM lock is Quote-only). OrderItem
  insert/update + activate are permitted in async; the constraints are 10k-row chunking, activate-LAST
  sequencing, assetize-after-activate non-race (SC-3419), and V16 context-fetch survival (full-field
  clones + staging fields on both objects/context nodes).
- **New field:** `Order.Split_Status__c` (restricted Picklist: Not Required / Pending Split / Split In
  Progress / Split Complete / Split Failed) — **confirmed absent today, must be created.** Convert flow
  stamps 'Pending Split' + commits the Order header BEFORE enqueuing the batch.
- **Idempotency:** key off existing `OrderItem.Original_Order_Item__c` + per-original count gate, gated
  by `Split_Status__c`; lean design defers the original's Quantity N→1 flip to its final chunk so the
  only idempotency state is `Original_Order_Item__c` + `Split_Status__c` (no extra field). Re-run/retry
  fills only the gap; admin "resume split" re-picks Pending/In Progress/Failed orders without
  double-creating.
- **CEILING (unchanged):** even perfectly chunked, P2 cannot persist seat/sentinel quantities
  (≥100 chunks / ~1M+ rows, and managed `submitOrder`/PlaceOrderExecutor O(N) at activate). Those need
  P3. **P2 stays DEMOTED/CONTINGENT.**

---

## 6. Evidence index
- `Order.Split_Status__c` ABSENT, `Order.ValidationResult`/`CalculationStatus` non-calc Picklists:
  Tooling `FieldDefinition WHERE EntityDefinition.QualifiedApiName='Order'` (this session).
- `OrderItem.Original_Order_Item__c` (Lookup→OrderItem) + `Is_Split_Line__c` (Checkbox) PRESENT:
  Tooling `FieldDefinition WHERE EntityDefinition.QualifiedApiName='OrderItem'` (this session).
- Async enqueue limit = 1, DML rows 10k sync==async, CPU 10s→60s, heap 6→12MB, SOQL 100→200:
  `_limits_cheatsheet.txt` L35-89 (Salesforce Developer Limits & Allocations Quick Ref, updated 2026-05-08).
- Batch resets governors per `execute()`; 10k rows/chunk: Apex Developer Guide, Execution Governors and
  Limits + Use Batch Apex (WebSearch).
- Queueable: 50 enqueue sync / 1 async; AsyncInfo stack-depth control; finalizer separate txn:
  Apex Developer Guide Queueable Apex + Transaction Finalizers (WebSearch).
- Activated order "cannot be changed": Salesforce Help Order Activation Limitations (WebSearch).
- PlaceOrderExecutor is the managed RCA reprice engine; `OrderRepriceInvocable` L64 calls
  `commerceorders.PlaceOrderExecutor.execute(...Force...)`, one PATCH/OrderItem L57-61.
- Split phase DML (per-clone ~3 rows): `PowerOrderSplittingService.cls` L218/245/304/327.
- Tail-moves-together + activate-LAST dependency: `03_reprice_activate_async.md §2`.
- Order-header async cascade (Billing_Schedule + Assetize AsyncAfterCommit, submitOrder O(N)):
  `10_order_header_cascade.md §2b, §4`.
- Quote-only RLM DML lock: memory `project_rlm_quote_dml_lock`. V16 context-fetch prereq: memory
  `project_v16_order_pricing_contextfetch_incident`. Assetize swallow: memory `project_sc3419_zero_assets`.

## Sources (official docs)
- Apex Governor Limits — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
- Limits & Allocations Quick Ref (Apex Gov) — https://developer.salesforce.com/docs/atlas.en-us.salesforce_app_limits_cheatsheet.meta/salesforce_app_limits_cheatsheet/salesforce_app_limits_platform_apexgov.htm
- Queueable Apex — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_queueing_jobs.htm
- Use Batch Apex — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_batch_interface.htm
- Transaction Finalizers — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_transaction_finalizers.htm
- PlaceOrderExecutor Class (RLM) — https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/apex_class_commerceorders_PlaceOrderExecutor.htm
- Order Activation Limitations — https://help.salesforce.com/s/articleView?id=sales.order_activate.htm
