# SC-3447 P2 — Reprice Mechanics in Async (read-only, FortraUAT 2026-06-27)

Org: FortraUAT (00DWC000006eUFF2A2). Scope = P2 architecture: can the Split→Reprice→Activate tail
move OFF the synchronous convert into a chunked async pipeline, focusing on whether/how
`OrderRepriceInvocable` (the RLM Force reprice) can run from async Apex on async-built lines.
All facts re-verified live this date; repo `force-app` is STALE for this stack (PlaceOrderExecutor
not present locally; live classes newer — see §6).

---

## 0. Live re-verification (this task)

| Item | Live (06-27) | Evidence |
|---|---|---|
| `OrderRepriceInvocable` live body | **IDENTICAL** to saved `OrderRepriceInvocable_live.cls** (only EOF-newline diff) | retrieved to `P2_retrieve/`, `diff` clean |
| Active pricing procedure | `Rev_Mgmt_Default_Pricing_Procedure` (ExpressionSetDefinition `9QAWC0000003mg14AA` / ExpressionSet `9QLWC0000015cDl4AI`) | data query |
| Active version | **V16** (`ExpressionSetVersion 9QMWC00000024PJ4AY` IsActive=true; `ExpressionSetDefinitionVersion 9QBWC0000000niH4AQ` Status=Active). V17–V20 Inactive. | data query |
| Context definition | `SalesTransactionContextExt_v2` (confirmed in 03_reprice; LastMod 06-25) | prior doc + memory |
| V16 staging fields on OrderItem | **ALL present, createable+updateable** (see §4) | `sf sobject describe OrderItem` |
| Convert flow wiring | Split(#4) → Reprice(#5, `OrderRepriceInvocable`) → Activate(#6), **all `flowTransactionModel=CurrentTransaction`**, strictly sequential | 01_convert_flow_chain.md |
| Class API versions | OrderRepriceInvocable 62, OrderCommercialNetService 62, PartnerNetPricePosthook **65**, MaintenanceOrderDecompositionService 62, PowerOrderSplittingService 62 | tooling query |

---

## 1. OrderRepriceInvocable — entry, behaviour, return, UI reliance (TASK 1)

### Entry signature
- `@InvocableMethod` `reprice(List<Request> requests)` → `List<Result>`.
- `Request`: `Id orderId` (single field). `Result`: `success`, `calculationStatus`, `validationResult`,
  `pricingReady`, `errorMessage`. **No screen/flow-only inputs** — the only input is an Order Id. It can
  be invoked from anything that has an Order Id (flow, trigger, Queueable, Batch).
- Class is `public without sharing` (relevant: it bypasses sharing, so async user context is not a blocker).

### What `repriceOne(orderId)` does (the tail, in order)
1. `MaintenanceOrderDecompositionService.prepareForReprice(orderId)` → `loadWork` (bulk SOQL: Order + all
   `OrderItem WHERE OrderId=:id` + linked QLI + QLIA tier + Places) then `seedFromWork` → **bulk UPDATE of
   all new-business seed OrderItems** (PartnerUnitPrice/NetUnitPrice/UnitPrice/Fortra_Product_Type).
2. `persistFromWork(work)` → `buildCommercialPatchesFromWork` → **bulk UPDATE of all OrderItems**.
3. `OrderCommercialNetService.patchOrderItemCommercialUnitPrices(orderId)` → SELECT all OrderItems,
   **bulk UPDATE** lines whose Net/Unit price is stale vs TotalPrice (commercial-net alignment).
4. `resolveQuoteTotal` / `resolveOrderTotal` → `totalsMatch()` (HALF_UP setScale(2)).
5. **Short-circuit (the `totalsAlreadyMatch` gate, TASK-1 question = YES it exists):** if
   `totalsAlreadyMatch == true` (quote total already == order total) AND there are line items, it **SKIPS**
   the posthook + Force reprice entirely ("Quote commercial nets are already on the order — skip RCA context
   posthook and Force reprice (the original stamp-without-reprice path)") and sets `res.success = true`.
   This is the cheap path; when nets are already stamped the RLM engine is never invoked.
6. Else (totals differ, lines present): `PartnerNetPricePosthook.applyNetPricesToOrder(orderId)` (the 92KB
   posthook, API 65) → build `commerceorders.GraphRequest('SC3308_Reprice', records)` with **ONE
   `RecordWithReferenceRequest` PATCH for the Order + ONE PATCH per OrderItem** (`for oi : work.allOrderItems`)
   → **`commerceorders.PlaceOrderExecutor.execute(graph, PricingPreferenceEnum.Force,
   ConfigurationInputEnum.Skip, new ConfigurationOptionsInput())`**. This is the RLM/RCA programmatic
   "Reprice All" (Force = recompute pricing on the whole graph). `Configuration = Skip` (no configurator).
7. `res.success = (r != null && r.success == true)` — **reads ONLY `r.success`, the SYNCHRONOUS part of the
   Place Order result** (see §2 — PlaceOrderResult also exposes async status). On failure: capture
   `r.responseError`, populate from Order, return.
8. `persistFromWork(work)` again (bulk UPDATE) — re-stamps commercial nets AFTER the Force reprice so RLM
   can't leave the line at the discount-immune maintenance base.
9. `clearOrderValidationResult(orderId)` → `update new Order(Id, ValidationResult=null)`.
10. `pricingReady = isPricingReady(orderId, quoteTotal)`: true iff Order.ValidationResult==null AND
    (CalculationStatus=='CompletedWithPricing' OR quote total matches Order.TotalAmount).

### What it returns / what gates activation
- Returns `pricingReady` (Boolean). The flow's `Decision_Order_Priced` gates `Activate_Order` on it.
  `faultConnector` → Screen_Error. So activation only proceeds when reprice reports pricing complete &
  ValidationResult clean.

### Reliance on screen-flow / UI context
- **NONE that is UI-specific.** No `contextDefinitionName` is passed in the Apex — context resolution is
  the platform's responsibility via the active pricing procedure (V16) bound to context
  `SalesTransactionContextExt_v2`. The binding lives in pricing-procedure config, not in the screen flow.
- BUT context resolution is **data-dependent**: PlaceOrderExecutor Force runs the V16 proc which hydrates
  `SalesTransactionContextExt_v2`, and that hydration reads partner/regional staging fields on the
  Order AND OrderItem (the [[project_v16_order_pricing_contextfetch_incident]] rule: shared proc fields must
  exist on BOTH objects + BOTH context nodes or context-fetch hard-fails). Async-built clones MUST carry
  these fields (§4) or reprice gacks on "couldn't fetch SalesTransactionContextExt_v2". This is a *data*
  prerequisite, not a UI-context one — which is what makes async feasible at all.

---

## 2. Can the RLM Force reprice run inside a Queueable/Batch? (TASK 2)

**Verdict: YES it is technically runnable from async Apex — there is no documented async-Apex prohibition and
it does not require `Database.AllowsCallouts` — BUT it carries a same-transaction state-poisoning hazard that
makes the chunking design non-trivial.**

Evidence:

**(a) It is a synchronous in-process Apex API, not an HTTP callout.**
RLM Developer Guide (v67 Summer '26, `rlm_dev_guide.pdf` p.1547–1551), `commerceorders.PlaceOrderExecutor`:
- Signature used here: `public static commerceorders.PlaceOrderResult execute(GraphRequest, PricingPreferenceEnum,
  ConfigurationInputEnum, ConfigurationOptionsInput)`. Confirmed verbatim.
- The doc calls it "the Place Order **Apex API**" that "ingest[s]" an sObject graph; the example invokes it
  inline and inspects `result.success` / `result.responseError` (`ConnectApi.PlaceOrderErrorResponse`). It does
  **internal DML** (creates/patches Order + OrderItems and runs pricing/config/validation). It is NOT shown
  making an `Http` callout, and **no `Database.AllowsCallouts` is implemented** anywhere in the calling stack
  (grep of repo classes = 0). RLM HTTP callouts are confined to DRO fulfillment "callout step types" and tax
  callout extensions (dev guide §"Callouts in Dynamic Revenue Orchestrator", §Tax callout) — both *separate*
  subsystems, neither on the reprice path. → No callout-from-batch restriction applies.

**(b) PlaceOrderResult is explicitly part-sync / part-async (the load-bearing nuance for P2).**
Dev guide PlaceOrderResult properties (p.1551), verbatim:
- `success` — "Get the request status of the **synchronous part** of the processing."
- `responseError` — "errors encountered during the **synchronous processing** of the API request."
- `requestIdentifier` — "request ID of the process to query the **asynchronous status** of the Place Order Apex API."
- `statusURL` — "the **asynchronous status URL** of the request, if available."
→ `execute()` runs a synchronous portion in-transaction (which is what `OrderRepriceInvocable` checks via
`r.success`) and **may spawn its own asynchronous tail**. At small line counts the sync part finishes the
pricing; at high line counts (>100 — see the platform's `isHighVolumeLineItems` flag, dev guide p.851/p.48347:
"Indicates whether the pricing API returns pricing details for **more than 100 line items**") the platform may
defer work asynchronously. The current invocable does NOT poll `requestIdentifier`/`statusURL`; it reads Order
fields immediately and computes `pricingReady` synchronously. **In an async/high-volume P2 pipeline this is a
correctness gap**: reprice could report `success=true` (sync part) while pricing of N lines completes in the
platform's own async tail, and the immediate `pricingReady` check (and any subsequent Activate) would race it.
A P2 design must wait on the Place Order async completion (poll status, or gate on a CompletedWithPricing
signal) before activating — not just trust `r.success`.

**(c) Documented same-transaction state poisoning (from the live test).**
`OrderRepriceInvocableTest` header (retrieved live) states, proven by bisection in THIS org:
> "commerceorders.PlaceOrderExecutor.execute() leaves the RLM / commerce pricing engine in a state that
> makes a subsequent QuoteLineItem INSERT in any sibling method of the SAME Apex test job fail with
> INVALID_CROSS_REFERENCE_KEY ('you don't have the required access'). … a QLI insert that passes in isolation
> fails the moment an executor-calling method shares the job."
This tells us the executor mutates commerce/sharing/context state mid-transaction. **Implication for chunked
async:** you cannot safely call `execute()` once per chunk inside one long-lived transaction, and you cannot
freely interleave executor calls with other RLM-object DML in the same transaction. Each Force reprice wants
its own clean transaction boundary. This *favours* the Batch model (each `execute()` chunk = a fresh
transaction) and *argues against* a single Queueable that loops executor calls.

**(d) Today it already runs in a synchronous user transaction.** All five convert Apex actions are
`flowTransactionModel=CurrentTransaction` (01_convert_flow_chain.md). So the call has no UI-thread dependency
beyond "a transaction with an Order Id" — moving the same call into a Queueable/Batch execute() keeps the
identical Apex surface. No documented blocker prevents the call class running async; the practical blockers are
(b) the async-completion gap and (c) state isolation, both solvable by re-architecture, not platform limits.

---

## 3. Cost / chunking — is reprice itself O(N) past the async budget? (TASK 3)

**Verdict: YES, reprice is itself O(N) and will hit CPU/DML walls; and RLM reprice is whole-order, NOT a
documented per-subset operation — so "reprice after async split" does not scale by simply moving it async.**

Per-N cost inside the reprice tail (N = number of OrderItems on the order at reprice time):
- **One GraphRequest PATCH record per OrderItem** (`for oi : work.allOrderItems`) fed to PlaceOrderExecutor
  Force → the V16 pricing procedure prices all N lines in one engine invocation. CPU scales ~linearly with N
  plus the procedure's per-line element cost.
- **Four bulk OrderItem UPDATE passes over all N lines** (seedFromWork; persistFromWork ×2;
  OrderCommercialNetService.patch). Each UPDATE fires the **RecordAfterSave `Set_Workday_Contract_Line_Type`
  V11** once per line (Get_Product SOQL + 5 recordUpdates incl `$Record` re-update, which re-fires
  RecordBeforeSave `Set_Dates` V6). This is the same per-line flow re-entrancy that drives the convert split
  CPU blowup — it re-fires here on every reprice-phase bulk update (≈4×N flow executions).
- `PartnerNetPricePosthook.applyNetPricesToOrder` = 92KB class (heavy per-line work) before the Force call.

**Hard limits identical sync vs async** (per task constraint + 08_web_governor_async.md): 10,000 DML
rows/transaction is the same async; async only raises CPU (10s→60s) + heap. So:
- At N = a few hundred genuine per-machine lines (the P2 target band), reprice's ~4×N bulk-update DML rows
  (e.g. N=2,000 → ~8,000 OrderItem update rows across the 4 passes, plus the GraphRequest's internal DML) can
  approach the 10k-row cap **within a single transaction** even before CPU. The 60s async CPU budget buys head-
  room over the 10s sync wall, but the 10k-row DML cap is the binding ceiling and is **not** raised by async.
- **Is RLM reprice subset-able?** The dev guide documents Place Order Force as operating on the supplied
  GraphRequest (whatever records you put in the graph). So you *can* build a graph for a SUBSET of the order's
  OrderItems and call Force on just that slice — pricing is per-line in the V16 proc. **HOWEVER** (i) Order
  totals/rollups and any cross-line pricing (tiers, bundle adjustments) assume the whole order; repricing
  slices independently risks wrong order-level totals and the `pricingReady` total-match check
  (`quoteTotal == Order.TotalAmount`) which is inherently whole-order; and (ii) the executor's per-call
  state-poisoning (§2c) means each slice should be its own transaction. So subset-reprice is *possible
  per-line* but **not safe to do as many calls in one transaction**, and a final whole-order reconciliation /
  total check is still required. Net: reprice must be **chunked across transactions** (Batch `execute()` per
  slice) with a **final whole-order pass** (or final total reconciliation) before Activate.

**Scale ceiling:** at the client's true Power quantities (seat/sentinel counts up to 999,999 / 750,000),
materialising one OrderItem per unit is impossible regardless of async chunking — ≥75–100 chunks and ~1M+ DML
rows. That is **P3's job** (don't materialise seat/sentinel lines; keep Quantity=N). P2 is only viable for
**genuine per-machine** orders that exceed the synchronous ceiling but stay within a chunkable count (low
thousands). At that band reprice-after-async-split is *feasible* but requires: Batch chunking of both the
split AND the reprice, suppression of the per-line Workday line-type flow during bulk convert, and a deferred
final reprice + activate in `finish()`.

---

## 4. V16 staging fields on OrderItem (async-clone survival prereq) (TASK 4)

`sf sobject describe OrderItem` (live) — all shared-proc / partner / split staging fields exist and are
createable+updateable, so async-built clones can carry them and survive the V16 context fetch:

| Field | createable | updateable | type |
|---|---|---|---|
| `Pre_Partner_Price__c` | yes | yes | currency |
| `Partner_Pricing_Source__c` | yes | yes | string |
| `CancelNetUnitPrice__c` | yes | yes | currency |
| `RegionalNetUnitPrice__c` | yes | yes | currency |
| `Original_Order_Item__c` | yes | yes | reference (qty-split FK) |
| `Is_Split_Line__c` | yes | yes | boolean (flow-suppression gate) |
| `PartnerUnitPrice` | yes | yes | currency |
| `PartnerDiscountPercent` | yes | yes | percent |
| `Partner_Discount_Type__c` | yes | yes | picklist |
| `Prior_Partner_Discount__c` | yes | yes | currency |
| `NetTotalPrice` | yes | yes | currency |
| `NetUnitPrice` / `UnitPrice` / `TotalLineAmount` | yes | yes | currency |
| `Fortra_Product_Type__c` | yes | yes | picklist |
| `AllowRegionalPricing__c` | yes | yes | boolean |
| `OriginalOrderItemId` | yes | **no** | reference (standard; set-on-insert only) |
| `TotalPrice` | no | no | currency (formula/derived — read-only) |

Note: `CalculationStatus` and `ValidationResult` live on **Order** (read by the invocable from Order), NOT on
OrderItem — expected; the pricing-ready gate is order-level.

**Active proc version = V16** (re-confirmed §0). Force reprice runs V16 against
`SalesTransactionContextExt_v2`. Because `PowerOrderSplittingService.createFullClone` copies ALL createable
OrderItem fields, today's clones already carry these staging fields → they survive context fetch. **Any async
re-implementation MUST preserve full-field cloning**; a "lite" clone that copies only a few fields would
re-trigger the [[project_v16_order_pricing_contextfetch_incident]] gack on every clone during reprice.

---

## 5. Async-feasibility verdict for P2 reprice

1. **Runnable async?** Yes — `PlaceOrderExecutor.execute(...Force...)` is an in-process Apex API (no HTTP
   callout, no `Database.AllowsCallouts` needed), and `OrderRepriceInvocable`'s only input is an Order Id, so
   it can be called from Queueable/Batch. No documented async-Apex prohibition.
2. **Two real hazards, not platform bans:**
   - (a) PlaceOrderResult is part-sync/part-async; the invocable trusts only `r.success` (sync part) and
     computes `pricingReady` immediately. At high line counts the platform may defer pricing to its own async
     tail → a P2 pipeline must wait on Place-Order async completion (poll `requestIdentifier`/`statusURL` or
     gate on CompletedWithPricing) **before Activate**, else it re-creates the unpriced-then-activated defect
     class (SC-3441/3419).
   - (b) Executor poisons same-transaction RLM/commerce state (proven INVALID_CROSS_REFERENCE_KEY on sibling
     DML). → each Force reprice wants its own transaction → **Batch (one execute() per chunk) is the right
     async model; a single looping Queueable is not.**
3. **Reprice is itself O(N)** (1 PATCH/OrderItem + ~4×N bulk updates each firing the per-line Workday flow +
   92KB posthook). Async raises CPU 10s→60s but NOT the 10k-DML-row cap → reprice must be chunked across
   transactions, with per-line Workday-flow suppression during bulk convert and a **final whole-order
   reprice/total reconciliation + activate** after all chunks. RLM Force can price a subset graph per-line,
   but order totals + the total-match `pricingReady` check are whole-order, so a final reconciliation pass is
   mandatory.
4. **Seat/sentinel quantities (999,999) are never materialisable** even chunked (≥1M rows) → out of P2 scope;
   that is P3 (keep Quantity=N). P2 reprice-async is only feasible for genuine per-machine orders in the low
   thousands.
5. **All V16 staging fields exist + are writable; full-field clone already stamps them — preserve that.**

---

## 6. Source-drift note

`force-app/main/default/classes/` does NOT contain the live reprice stack (PlaceOrderExecutor call /
OrderCommercialNetService SC-3441 additions absent locally). Live tooling versions are newer
(OrderRepriceInvocable LastMod 2026-06-24, PartnerNetPricePosthook API 65 / 92,263 chars,
OrderCommercialNetService LastMod 2026-06-24). The retrieved `P2_retrieve/` copies are the live truth used
for this analysis. Per memory [[feedback_org_data_src_can_be_stale]] / [[feedback_fortra_source_drift]],
always retrieve live before editing this stack.

## Sources
- RLM Developer Guide v67 (Summer '26) PDF — `commerceorders.PlaceOrderExecutor` (p.1546–1551),
  `PlaceOrderResult` properties (p.1551, sync vs async), `isHighVolumeLineItems` >100-line flag (p.851),
  Callouts in DRO / Tax callout extensions (separate subsystems).
  https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf
- Live FortraUAT: ApexClass tooling, ExpressionSetVersion/ExpressionSetDefinitionVersion data query,
  OrderItem describe, OrderRepriceInvocable + OrderRepriceInvocableTest retrieve (`P2_retrieve/`).
- Prior P0/P1 docs: 01_convert_flow_chain.md, 03_reprice_activate_async.md, 08_web_governor_async.md,
  09_web_rlm_quantity.md, DESIGN_FINAL.md §P2.
