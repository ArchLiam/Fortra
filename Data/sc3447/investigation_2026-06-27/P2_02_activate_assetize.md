# SC-3447 P2 — Activate + ValidationResult + Assetize Sequencing in Async (read-only, FortraUAT 2026-06-27)

**Scope:** P2 architecture design sub-task. The async pipeline (split → reprice → activate) must **activate LAST**,
after split+reprice+clearValidation are fully committed, **without racing assetization**. This file answers the 4
activation/assetize/billing/cut-point questions; the split/reprice mechanics live in `03_reprice_activate_async.md`
and the overall P2 architecture in `DESIGN_FINAL.md §P2`.

**Org:** FortraUAT (00DWC000006eUFF2A2). **Mode:** strictly read-only (Tooling queries, metadata retrieve, describe).
All versions re-verified live this date.

**Standing caveat (per memory):** P2 is DEMOTED/contingent. Workday takes quantity=N on one line, so P3 (don't split
seat/sentinel lines) is the primary fix; the 10k-DML-row ceiling forbids materializing sentinel quantities (999,999)
in ANY number of chunks. P2 is only relevant for a confirmed genuine **per-machine** (Partition/Hardware-driven)
split at modest scale (dozens–low thousands). This file designs the activate/assetize tail *if* P2 is ever built.

---

## 0. Live re-verification (drift check vs grounding files)

| Item | Grounding (06-27 earlier) | Live now | Drift |
|---|---|---|---|
| Convert flow active | V27/V28, Id 301WC00000kSRnZYAW | **V28 Active, Id 301WC00000lmnmfYAA**, LastMod 2026-06-27T19:00Z | Id changed (flow re-saved/source-tracked today); chain unchanged |
| Fortra_Assetize_Order | V17 AsyncAfterCommit, Status='Activated' | **V17 Active, Id 301WC00000lZD2XYAW**, LastMod 2026-06-24T20:39Z, api 64 | no drift |
| Order Status picklist | — | Draft, Activated, Superseded, Provisioned, Order Complete | confirmed |
| Order.ValidationResult | RC gate | **EXISTS, picklist, updateable=true**; values `'TransactionIncomplete'`, `'MissingContributor'` (+null=clean) | confirmed |
| Order.Split_Status__c | absent | **CONFIRMED ABSENT** (describe: no Split/Pending field) | must be created if P2 built |

Convert chain (live V28, all `flowTransactionModel=CurrentTransaction`):
`Validate_Checklist_Complete(ChecklistValidationService)` → `Call_Create_Order_From_Quote(createOrderFromQuote)`
→ `Assign_Created_Order_Id` → `MapQuoteLineFieldsToOrderItems(QuoteToOrderFieldMapper)` →
`SplitPowerOrderLines(PowerOrderSplittingService)` → `Decision_Power_Split_Succeeded` →(OK)→ `Get_Created_Order`
→ `Decision_Create_Contract_Record` → [contract branch | no-contract branch] → `Reprice_Order_Before_Activate(_No_Contract)(OrderRepriceInvocable)`
→ `Decision_Order_Priced(_No_Contract)` →(priced)→ `Activate_Order(_No_Contract)`.

---

## 1. How activation happens today + can async Apex activate the Order?  (TASK 1)

### 1a. Today's activation = a plain Order Status update
`Activate_Order` and `Activate_Order_No_Contract` are both **`recordUpdates`** (NOT a special invocable) on object
`Order`, filtered `Id = varCreatedOrderId`, with one `inputAssignment`: **`Status = 'Activated'`** (string literal).
There is NO `activateOrder` action, no ValidationResult write at this step, no other field set. (Convert flow V28
lines 1237–1289.)

→ **Activation is just `order.Status = 'Activated'; update order;`** — exactly what async Apex (Queueable/Batch
`finish()`) would execute. There is nothing flow-specific about it.

### 1b. Order.ValidationResult IS the RC activation gate — confirmed
- `PowerOrderSplittingService` Phase 8 (cls L102–115, L330–341) **captures pre-existing `Order.ValidationResult`
  per order, then restores it to `null`** after its OrderItem DML, with the explicit comment: *"ANY OrderItem DML
  flips a null ValidationResult to 'TransactionIncomplete', blocking activation with the misleading 'prices aren't
  updated' error."* It only restores null for orders it actually split that were clean beforehand
  (`preValidationResultByOrder.get(orderId) == null`).
- `OrderRepriceInvocable` also clears it (`clearOrderValidationResult` → `update Order ValidationResult=null`,
  see `03_reprice_activate_async.md §1` and `OrderRepriceInvocable_live.cls`).
- Live describe: `ValidationResult` is an updateable picklist; clean=null, dirty='TransactionIncomplete'/'MissingContributor'.

→ Activation succeeds only when `ValidationResult IS null` (clean) at the moment Status flips to 'Activated'. Any
OrderItem DML that runs after the last clear, before activate, re-dirties it.

### 1c. Can an Order be activated from async Apex? — YES, no platform block on the *update itself*, with two caveats
- **No describe-level / RLM hard lock on Order Status update.** Order.Status is updateable; the activation is a
  generic field update. (Contrast `project_rlm_quote_dml_lock`: that lock is **Quote**-specific, runtime trigger-tier;
  it does NOT apply to Order/OrderItem — proven by the fact PowerOrderSplittingService already inserts clone
  OrderItems and updates the Order inside the convert today; SC-3447's failure is CPU, not a DML-blocked error.)
- **Caveat A — the activate transition fires a SYNCHRONOUS RLM submit in whatever txn does the update.**
  `Order_Submission_to_Revenue_Orchestrator` (RecordAfterSave/Update, entry `Status='Activated'` +
  requireRecordChanged, **triggerOrder 200**) calls native **`submitOrder`** with **`flowTransactionModel=CurrentTransaction`**
  — i.e. submitOrder runs IN-LINE in the activating transaction (it kicks the Revenue Orchestrator over all order
  lines = a 2nd O(N) tail; see `10_order_header_cascade.md §4.2`). When async Apex flips Status, this flow fires
  in the *async* transaction and submitOrder runs there, on the async 60s CPU / 10k-row budget. This is FINE
  (the whole point of moving async) but means **the activate chunk itself must budget for submitOrder's O(N)
  managed work**, and at extreme N submitOrder may itself need to be the lone work in its own activation txn.
- **Caveat B — re-activating an already-submitted Order from Apex throws** `CANNOT_EXECUTE_FLOW_TRIGGER`
  (the orchestrator flow faults: "Sales Transaction cannot be processed"). This is the SC-3419 B1 finding
  ([[project_sc3419_zero_assets]]): in-place re-fire of an already-Activated/submitted order is blocked. **For our
  pipeline this is a NON-issue** — we activate a FRESH Draft order exactly once (Draft→Activated), never re-activate.
  SC-3419's C/N runtime test proved fresh orders activate cleanly from non-flow context; the block is
  re-submission-specific. The pipeline MUST guard idempotency so it never re-issues the activate update on an
  order already Activated.

**Verdict (Task 1):** Async Apex can activate the Order by a plain `Status='Activated'` update, provided (i)
`ValidationResult IS null` at that instant (no OrderItem DML after the last clear), (ii) it is a first-time
Draft→Activated transition (never a re-activate), and (iii) the activating transaction has headroom for the
in-line synchronous `submitOrder` (O(N) Revenue Orchestrator) that fires on the transition.

---

## 2. Assetize: trigger, gate, async path, and the SC-3419 race under async activation  (TASK 2)

### 2a. Fortra_Assetize_Order V17 — confirmed structure (live retrieve P2_live_retrieve/)
- `<start>`: **object=Order, recordTriggerType=Update, triggerType=RecordAfterSave**, entry filter
  **`Status = 'Activated'`** + `doesRequireRecordChangedToMeetCriteria=true`, **triggerOrder 300**.
- `<scheduledPaths><pathType>AsyncAfterCommit` → `GetApplicationUsageAssignment` → `HaveApplicationUsageAssignmentRecord`
  → (Yes) `Finalize_Order_Commercial_Net` (`AssetRateOverrideConsolidationService` apex, CurrentTransaction)
  → `CreateOrUpdateRelatedAsset` (**native `createOrUpdateAssetFromOrder`**) → `PopulateAssetLegacyFields`
  → `Prior_Assetization_Error` decision → (clears Order_Integration_Error_Messages__c only if it `StartsWith`
  "Assetization failed").
- Fault path: `createOrUpdateAssetFromOrder.faultConnector` → `Assign_Error_Message` → `Stamp_Assetization_Failed`
  (writes `Order_Integration_Error_Messages__c = "Assetization failed: " & faultMessage`, never Status — the SC-3415
  visibility fix; matches [[project_sc3419_zero_assets]] V14, now riding in V17).
- It is an OVERRIDE of `revenue_o2aflows__o2aFlow`.

→ **Assetize runs in its OWN post-commit transaction** (AsyncAfterCommit), spawned only after the activating txn
commits with Status='Activated'. It does NOT run in the async activate chunk; it is scheduled AFTER that chunk
commits. It assetizes ALL OrderItems on the order at that point (one Asset/line, carrying Quantity — per
[[project_sc3419_zero_assets]] this org makes one Asset per ORDER LINE).

### 2b. Does async activation reintroduce the SC-3419 race?
**The SC-3419 race is NOT timing-induced by our async activation, and our design does not make it worse — provided
the N lines are built BEFORE activate, never after.** Reasoning:
- SC-3419's collision (`INVALID_API_INPUT "the asset was updated by another process"`, optimistic-lock) is a
  **data-shape** trigger: multiple duplicate same-product RNM/maintenance lines contending on a PRE-EXISTING
  matching Asset (Account+Product2Id key) already on the account. It was REFUTED as a governor/UNABLE_TO_LOCK/
  async-timing issue (2 SOQL, 0 CPU, deterministic). Fresh accounts / per-line Generate assetize 32 distinct lines
  with zero collision (order 00095537). **So the race is about duplicate-line-vs-existing-asset, not about WHO
  (flow vs async Apex) issued the activate update or WHEN.**
- Power per-machine split clones are the SAME Product2 as the parent (qty-split FK `Original_Order_Item__c`). On a
  per-machine convert with N split clones of one product, if that product already has a matching Asset on the
  account, the N clones DO contend → same SC-3419 collision exists today (sync) and would exist async — **async
  does not create it and does not amplify it** (assetize is single-threaded per order in one AsyncAfterCommit job,
  not parallel chunks). It is an INDEPENDENT, pre-existing risk; the V17 visibility fix surfaces it via
  `Order_Integration_Error_Messages__c` either way.
- **Where async COULD introduce a NEW race:** if the pipeline mutated OrderItem pricing fields (reprice /
  PartnerNetPricePosthook / commercial-net) AFTER Status='Activated' committed — i.e. interleaving OrderItem DML
  with the post-activate assetize job. `OrderCommercialNetService` header (live cls L4–9) warns exactly this:
  re-running the posthook at activation *"can gack or leave createOrUpdateAssetFromOrder stuck at ContextPersistence
  without spawning AssetizationAsyncJob."* → **The pipeline must do ALL OrderItem mutation (split + reprice +
  commercial-net + clearValidation) BEFORE the activate update, and touch NO OrderItem after activate.** The
  assetize flow itself runs its own `Finalize_Order_Commercial_Net` immediately before `createOrUpdateAssetFromOrder`
  inside its post-commit txn — that internal sequence must be left intact (do not duplicate/race it from our code).

### 2c. Required ordering guarantees (the load-bearing invariant)
The async pipeline MUST enforce, in order, with COMMITS between the phases that other automations key on:
1. **Build all N lines** (split clones inserted, originals reset to qty=1, FK + Is_Split_Line__c stamped, Apex-stamped
   line-type/dates) — chunked, each chunk a fresh ≤10k-row txn.
2. **Reprice the now-N-line order** (OrderRepriceInvocable / PlaceOrderExecutor over all N) — itself O(N), may need
   chunking at extreme N; this is the last phase allowed to mutate OrderItem pricing fields.
3. **Clear `Order.ValidationResult = null`** (after the final OrderItem DML, so nothing re-dirties it).
4. **Commit.** (End the building/repricing transaction(s). The order is now N-line, priced, ValidationResult clean,
   still Draft.)
5. **Activate**: `Status='Activated'; update order;` as the FINAL step, in its own transaction, only after #1–#4
   succeeded for the whole order. This transition fires `submitOrder` (sync, triggerOrder 200) in-line.
6. **Assetize fires post-commit** (AsyncAfterCommit, triggerOrder 300) on the full N-line order — automatically,
   correctly, once. Billing-schedule fires post-commit too (triggerOrder 1200). The pipeline does nothing further
   to OrderItems.

If steps are interleaved (activate before all lines built, or OrderItem DML after activate), you re-create
SC-3441 (clones unpriced / null NetUnitPrice) and/or the ContextPersistence-stuck assetize (0 Assets).
**This is the same "whole tail moves async together, activate LAST" rule the grounding files establish; the
specific addition here is: assetize/billing are AUTOMATIC post-commit consequences of the activate update — you do
NOT call them; you only need to make the activate update the genuine last write and ensure ValidationResult is
clean at that instant.**

---

## 3. Fortra_Order_to_Billing_Schedule — async-tail scaling concern  (TASK 3)

`Fortra_Order_to_Billing_Schedule`: RecordAfterSave/Update, entry `Status='Activated'` + requireRecordChanged,
**`AsyncAfterCommit`**, **triggerOrder 1200**. Delegates to managed action `createBillingSchedulesFromBillingTransaction`
(`revenue_o2bsflows`) which creates **one `Billing_Schedule` per OrderItem** internally
(`10_order_header_cascade.md §2b`, §5).

→ At N lines it creates N Billing_Schedules in ITS OWN AsyncAfterCommit transaction (separate budget from convert
AND from our activate chunk). It therefore has the **same 10k-DML-row wall** at extreme N, in its own txn —
but it is a managed, single delegated action (not hand-rolled), so we cannot chunk it. **Async-tail scaling note:**
even after P2 builds N lines, billing-schedule generation is a third independent O(N) async consumer (alongside
reprice and submitOrder). For genuine per-machine N in the low thousands this is fine (one Billing_Schedule per
machine line, well under 10k); for any path approaching ~10k lines it is a hard ceiling we do not control →
reinforces that P2 is viable only for modest per-machine N, and sentinel/seat quantities must never materialize
(P3). No action required for P2 build beyond DOCUMENTING this ceiling and keeping the per-machine cap well below it.

---

## 4. The exact CUT POINT — thin sync convert vs async hand-off  (TASK 4)

### 4a. Where the sync flow stops (the cut)
Today's V28 chain runs split→…→reprice→activate all in CurrentTransaction. For P2 the **synchronous convert must
stop immediately after the field-map + a status stamp + commit**, and hand the rest to async:

**SYNC (keep in the convert screen flow, returns to user immediately):**
1. `Validate_Checklist_Complete` (ChecklistValidationService) — unchanged (and the redundant trigger-side copy can
   be bypassed via `OrderValidationTriggerHandler.bypassValidation`, `10_order_header_cascade.md §5`).
2. `Call_Create_Order_From_Quote` (native `createOrderFromQuote`) — creates the Order in **Draft** with the
   un-split original lines (qty=N on the Power line). This is the O(1)-ish native step; it is NOT the N-scaler.
3. `MapQuoteLineFieldsToOrderItems` (QuoteToOrderFieldMapper) — maps custom lookups (Hardware, Partition) onto
   OrderItems. **MUST stay sync and before the cut** because P3's split gate reads `OrderItem.Partition_Record__c`
   / `Hardware__c`, which only this mapper populates (memory: mapper sets OI.Partition_Record__c←QLI.Partition_Reference__c).
4. **NEW: stamp `Order.Split_Status__c = 'Pending Split'`** (field must be created; confirmed absent today) — single
   O(1) header update. Optionally also persist the cap/eligibility decision so the async job knows what to do.
5. **Commit** (flow returns; user sees "order created, finalizing in background"). The Order is Draft, valid,
   un-split, NOT repriced beyond createOrderFromQuote's defaults, NOT activated.
6. Enqueue the async pipeline (Batch/Queueable) keyed on the Order Id.

**The cut is BETWEEN step 3 (mapper) and today's `SplitPowerOrderLines` action.** Everything from
`SplitPowerOrderLines` onward (split → reprice → clearValidation → activate) moves to async.

### 4b. What the sync part must still do so the order is "valid-but-pending"
- Order exists in **Draft** (createOrderFromQuote default) — a legitimate, non-activated, editable RC posture.
- Custom lookups mapped (so the async split gate can evaluate Partition/Hardware).
- `Split_Status__c='Pending Split'` stamped — the recovery/idempotency key and the "do not treat as finished" flag.
  (Drives the C7 admin "resume split" recovery path for orders stuck Pending Split, `DESIGN_FINAL.md §P2`.)
- **Do NOT** activate, do NOT reprice-to-completion, do NOT clear ValidationResult in the sync part — those belong
  to the async tail and must run AFTER all lines are built. (Leaving the order Draft + Pending Split is the
  "valid-but-pending" state; it simply isn't activated yet, which is correct — assetize/billing/orchestrator are
  all Status='Activated'-gated and therefore correctly DORMANT until the async activate.)
- The convert flow's downstream contract branch (`Decision_Create_Contract_Record`, Activate_Contract, link, etc.)
  must also move into / be coordinated by the async tail or be made Pending-aware, since contract activation and
  order activation are interleaved in V28 (Activate_Order targets Get_Created_Contract). At minimum, order
  activation (the Status='Activated' write) must be the async tail's final step; contract creation/linking can
  stay sync (it does not depend on the split) but contract *activation* timing relative to order activation should
  be preserved (out of scope detail for this sub-task; flag for the full P2 build).

### 4c. Idempotency / recovery hooks the cut enables
- Async job keys on `Order.Split_Status__c='Pending Split'` + `OrderItem.Original_Order_Item__c` (qty-split FK) so
  re-runs never double-create clones (`DESIGN_FINAL.md §P2`, test A18). Flip `Split_Status__c` per chunk →
  'Splitting' → (after activate) 'Complete' / on failure 'Split Failed'.
- A committed Draft+Pending order survives async chunk failure without rolling back the convert (the convert
  already returned to the user). Failed slices re-enqueue or quarantine; admin "resume split" runbook handles stuck
  Pending orders.

---

## 5. Net sequencing diagram (the P2 activate/assetize tail)

```
SYNC convert (returns to user):
  Checklist → createOrderFromQuote(Draft, qty=N) → QuoteToOrderFieldMapper(map Hardware/Partition)
            → stamp Order.Split_Status__c='Pending Split' → COMMIT → enqueue Batch(orderId)
--- cut ---
ASYNC Batch:
  execute() chunk 1..k:  insert clones (≤10k rows/chunk) + reset originals qty=1 + stamp FK/IsSplit/line-type/dates
                         [Is_Split_Line__c=false flow-suppress; Apex-stamp]   (commit per chunk)
  finish():              reprice now-N-line order (PlaceOrderExecutor, O(N), chunk if extreme)
                         → clear Order.ValidationResult=null   (last OrderItem-affecting write)
                         → COMMIT
                         → update Order Status='Activated'      (FINAL write; idempotent: skip if already Activated)
                              ├─ triggerOrder 200 Order_Submission_to_Revenue_Orchestrator → submitOrder (SYNC, in this txn, O(N))
                              └─ COMMIT
                                   ├─ triggerOrder 300 Fortra_Assetize_Order (AsyncAfterCommit) → Finalize_Order_Commercial_Net → createOrUpdateAssetFromOrder (N Assets, own txn)
                                   └─ triggerOrder 1200 Fortra_Order_to_Billing_Schedule (AsyncAfterCommit) → N Billing_Schedules (own txn, 10k wall at extreme N)
                         → stamp Order.Split_Status__c='Complete'
```

**Three O(N) tails ride the activate transition, in two budgets:** submitOrder (sync, in the activate txn) +
assetize (own post-commit txn) + billing-schedule (own post-commit txn). Async only raises CPU 10s→60s and heap;
it does NOT raise the 10k-DML-row wall, so each of these is independently bounded by ~10k rows in its own txn →
P2 is viable for modest per-machine N only; seat/sentinel quantities are NEVER viable (P3's job).

---

## 6. Answers to the 4 task questions (condensed)

1. **Activation today** = plain `recordUpdate` Order `Status='Activated'` (V28 Activate_Order / Activate_Order_No_Contract).
   `Order.ValidationResult` IS the RC gate (PowerOrderSplittingService Phase 8 + OrderRepriceInvocable clear it;
   describe-confirmed updateable picklist, clean=null). **Async Apex CAN activate** via the same Status update — no
   RLM/platform lock on Order Status update (the RLM lock is Quote-only) — IFF ValidationResult is null at that
   instant, it is a first-time Draft→Activated (re-activating an already-submitted order throws
   CANNOT_EXECUTE_FLOW_TRIGGER, SC-3419 B1), and the txn has headroom for the in-line synchronous submitOrder.
2. **Assetize** = Fortra_Assetize_Order V17: RecordAfterSave/Update, entry `Status='Activated'`+requireChanged,
   triggerOrder 300, **AsyncAfterCommit** → createOrUpdateAssetFromOrder (own post-commit txn). **Async activation
   does NOT reintroduce the SC-3419 race** (that race is a duplicate-line-vs-pre-existing-asset DATA-shape issue,
   not a flow-vs-Apex timing issue; refuted as governor/timing). A NEW race appears ONLY if OrderItem pricing is
   mutated after activate commits (OrderCommercialNetService warns of ContextPersistence-stuck assetize) → forbid
   any OrderItem DML after activate. **Required ordering:** build all N lines → reprice → clear ValidationResult →
   commit → activate (last) → assetize fires post-commit automatically on the full N-line order.
3. **Fortra_Order_to_Billing_Schedule** = AsyncAfterCommit, triggerOrder 1200, one Billing_Schedule per OrderItem
   via managed `createBillingSchedulesFromBillingTransaction` → **N rows in its own async txn → 10k-row wall at
   extreme N**, uncontrollable (managed). Third independent O(N) async tail; bounds P2 to modest per-machine N.
4. **Cut point** = between `MapQuoteLineFieldsToOrderItems` and `SplitPowerOrderLines`. Sync keeps Checklist +
   createOrderFromQuote (Draft) + QuoteToOrderFieldMapper + stamp **new** `Order.Split_Status__c='Pending Split'`
   + commit + enqueue. Async owns split→reprice→clearValidation→activate. The "valid-but-pending" order = Draft,
   custom lookups mapped, Pending Split stamped, not activated (so all Status='Activated'-gated automation stays
   correctly dormant until the async activate). `Order.Split_Status__c` does NOT exist today — must be created.

---

## 7. Verified vs assumed (honesty ledger)

**Verified live this session (HIGH):**
- V28 activation = plain Order Status='Activated' recordUpdate, two paths (contract / no-contract); all convert
  actions CurrentTransaction (live retrieve P2_live_retrieve/).
- Fortra_Assetize_Order V17: RecordAfterSave/Update, Status='Activated' entry, AsyncAfterCommit, triggerOrder 300;
  fault→Stamp_Assetization_Failed; success→conditional clear (live retrieve).
- Order_Submission_to_Revenue_Orchestrator: Status='Activated', RecordAfterSave, triggerOrder 200, submitOrder
  **CurrentTransaction (synchronous)** (order_flows_retrieve/).
- Fortra_Order_to_Billing_Schedule: AsyncAfterCommit, triggerOrder 1200, per-OrderItem (order_flows_retrieve/, file 10).
- Order.ValidationResult exists/updateable; Order.Split_Status__c ABSENT; Order Status values
  Draft/Activated/Superseded/Provisioned/Order Complete (describe).
- PowerOrderSplittingService Phase 8 captures/restores ValidationResult (cls L102–115, 330–341).
- OrderCommercialNetService header documents the ContextPersistence-stuck assetize race on activation-time posthook
  re-run (live cls L4–9).

**Assumed / point-in-time (re-verify at build — daily churn):**
- SC-3419 race characterization (duplicate-line-vs-pre-existing-asset, NOT timing) is from [[project_sc3419_zero_assets]]
  runtime tests (2026-06-16), not re-run this session (read-only; would require activating orders).
- No platform hard-block on activating an RLM Order from async Apex: established by (a) no describe lock, (b)
  RLM lock is Quote-only, (c) PowerOrderSplittingService already does Order/OrderItem DML in convert; NOT proven by
  an actual async-activate run (read-only). Web search surfaced no documented async-activate restriction but also no
  explicit endorsement — confirm with a sandbox async-activate test in the P2 build (E13).
- submitOrder's exact O(N) cost in the async budget is inferred (managed action over all lines); measure at build.
- Convert flow active Id moves on every save (was kSRnZYAW, now lmnmfYAA); re-verify the active version at build.
