# SC-3447 — Reprice / Activate Path + Async Feasibility (read-only, FortraUAT 2026-06-27)

Org: FortraUAT (00DWC000006eUFF2A2). All facts re-verified live this date. Repo source treated as
potentially stale; live ApexClass bodies / pricing config / flow versions retrieved fresh.

## 0. Re-verification vs 2026-06-26 known-state

| Item | Known-state (06-26) | Live (06-27) | Drift? |
|---|---|---|---|
| Convert flow active version | 301WC00000kSRnZYAW (V?) | **V27** active, same Id 301WC00000kSRnZYAW | version label was unstated; chain unchanged |
| Action chain | Checklist → createOrderFromQuote → FieldMapper → Split → Reprice → Activate, all CurrentTransaction | **CONFIRMED identical** | no drift |
| Set_Dates | V6 RecordBeforeSave | **V6 Active, RecordBeforeSave CreateAndUpdate** | no drift |
| Set_Workday_Contract_Line_Type | V11 RecordAfterSave (Get_Product SOQL + $Record update) | **V11 Active, RecordAfterSave CreateAndUpdate, Get_Product SOQL + 5 recordUpdates incl $Record** | no drift |
| Autolaunched_Set_Workday | INACTIVE since 06-08 | **V7 = Draft, V1–V6 Obsolete** (still NOT live) | no drift (Draft not Active) |
| OrderRepriceInvocable | repo body | **LIVE is NEWER than `Org Data/_src` repo copy** | DRIFT — see §1 |
| Order pricing procedure | (not pinned) | **`Rev_Mgmt_Default_Pricing_Procedure` 9QLWC0000015cDl4AI, ACTIVE = V16** (V17–V20 inactive) | new fact |
| Context definition | SalesTransactionContextExt_v2 | **CONFIRMED, LastMod 2026-06-25** | no drift |
| Repro quote 0Q0WC000003AuQb0AK | exists | **0 rows — quote no longer present** (deleted/churned) | DRIFT — repro record gone |
| Repro product 01tWC00000DD11GYAT "Abstract" | Power / Order Line Only / Active | **CONFIRMED Power / Order Line Only / Active** | no drift |
| Power active split-type dist | 3405 OLO / 1 OL+HW | **2781 Order Line Only / 1 Order Line and Hardware** (active only) | counts shifted (active subset) |

## 1. OrderRepriceInvocable — what it does on convert  (TASK 1)

LIVE class `OrderRepriceInvocable` (01pWC000002VIVlYAO, API 62, LastMod 2026-06-24).
Live body saved at `Data/sc3447/investigation_2026-06-27/OrderRepriceInvocable_live.cls`.

**LIVE IS NEWER THAN REPO** (`Org Data/_src/classes/OrderRepriceInvocable.cls`). The live version adds two
SC-3441-era calls that the repo copy lacks:
- `OrderCommercialNetService.patchOrderItemCommercialUnitPrices(orderId)` (new, after the first persist)
- `PartnerNetPricePosthook.applyNetPricesToOrder(orderId)` (new, before the Force reprice)
- a `totalsMatch()` helper using `setScale(2, HALF_UP)` rounding.

`repriceOne(orderId)` flow per Order:
1. `MaintenanceOrderDecompositionService.prepareForReprice(orderId)` → `loadWork` (bulk SOQL on
   Order + `OrderItem WHERE OrderId = :id` + QLI + QLIA tier + Places) then `seedFromWork` →
   **bulk UPDATE of all seed OrderItems** (PartnerUnitPrice/NetUnitPrice/UnitPrice/Fortra_Product_Type).
2. `persistFromWork(work)` → `buildCommercialPatchesFromWork` → **bulk UPDATE of all OrderItems**.
3. `OrderCommercialNetService.patchOrderItemCommercialUnitPrices` → SELECT all OrderItems, **bulk UPDATE**
   those whose Net/Unit price is stale vs TotalPrice.
4. If quote total != order total: `PartnerNetPricePosthook.applyNetPricesToOrder` (the 92KB posthook),
   then builds a **`commerceorders.GraphRequest`** named `SC3308_Reprice` containing ONE
   `RecordWithReferenceRequest` PATCH for the Order + **ONE PATCH per OrderItem** (`for oi : work.allOrderItems`),
   and calls **`commerceorders.PlaceOrderExecutor.execute(graph, PricingPreferenceEnum.Force,
   ConfigurationInputEnum.Skip, ...)`** — this is the RCA / Revenue Cloud "Reprice All" programmatic API.
5. `persistFromWork(work)` again (another bulk UPDATE).
6. `clearOrderValidationResult` → UPDATE Order ValidationResult=null. Sets `pricingReady`.

**Pricing procedure used by the Order Force reprice:** `Rev_Mgmt_Default_Pricing_Procedure`
(ExpressionSet 9QLWC0000015cDl4AI, UsageType=DefaultPricing). **Currently ACTIVE version = V16**
(ExpressionSetVersion 9QMWC00000024PJ4AY, IsActive=true). V17–V20 exist but are inactive (daily churn).
**Context definition:** `SalesTransactionContextExt_v2` (11OWC000002m21Z2AQ, LastMod 2026-06-25) — confirmed.

The flow gates: Reprice action → `Decision_Order_Priced` → Activate. `faultConnector` → Screen_Error.
Activation only proceeds when reprice returns pricingReady (Order CompletedWithPricing / ValidationResult null
/ totals match).

## 2. Does reprice/activate DEPEND on split having happened in-transaction?  (TASK 2)

YES — there is a hard same-transaction data dependency, on TWO levels:

A. **Reprice graph membership.** `repriceOne` reprices `work.allOrderItems` = whatever OrderItems exist on
   the Order *at the moment reprice runs*. The split (PowerOrderSplittingService) runs immediately BEFORE
   reprice in the chain and (a) inserts the qty−1 clones and (b) sets the original line Quantity=1. If split
   is moved async (Queueable/Batch after convert), then at reprice time the Order still has the ONE original
   line at Quantity=N. Reprice would price one line at qty N, Activate would activate a 1-line order, and the
   split clones would be created AFTER activation → they would be **unpriced** (CalculationStatus not Completed,
   NetUnitPrice null) and would arrive on an already-Activated order. That breaks the convert contract
   (each Power unit must be its own qty=1, priced, activated line) and re-creates the SC-3441-class
   "TotalPrice=0 / null NetUnitPrice on lines with no waterfall row" defect on every clone.

B. **Order.ValidationResult activation gate.** PowerOrderSplittingService Phase 8 explicitly restores
   `Order.ValidationResult = null` after its OrderItem DML, because "ANY OrderItem DML flips a null
   ValidationResult to 'TransactionIncomplete', blocking activation." OrderRepriceInvocable also clears it.
   If split runs async AFTER activate, the async OrderItem inserts will re-dirty ValidationResult on an
   already-active order with no reprice/clear following → order left in an inconsistent pricing-incomplete
   state, and (per SC-3441 memory) the misleading "prices aren't updated" error surfaces.

**Net:** a naive "move split to async after convert" breaks both reprice membership and the activation gate.
A correct async design must (i) split, (ii) reprice the now-N-line order, (iii) clear ValidationResult,
(iv) THEN activate — i.e. the entire Split→Reprice→Activate tail must move async together, not just the split.
Activation cannot precede the split.

## 3. RLM / Subscription-Management locks on OrderItem DML  (TASK 3)

- Memory `project_rlm_quote_dml_lock`: RLM blocks **Quote** DML at platform tier. That is a *runtime trigger-tier*
  block (not visible in describe — Quote describe still shows createable/updateable/deletable = true, same as
  OrderItem).
- **No equivalent hard lock applies to OrderItem during/after convert.** Proof: PowerOrderSplittingService
  TODAY successfully inserts qty−1 clone OrderItems and updates originals inside the sync convert transaction.
  The current failure is **CPU time**, not a DML-blocked error. So OrderItem insert/update is permitted on a
  converting/converted order.
- **Async Apex OrderItem DML post-convert is allowed** in principle (Queueable can insert/update OrderItem).
  BUT two platform constraints matter:
  1. **Do not mutate OrderItems on an Order after Activate** without re-running reprice + clearing
     ValidationResult — activated-order line DML dirties the RC pricing/validation state (see §2B). RCA also
     restricts edits on activated orders for priced fields. So async work must finish (split+reprice+clear)
     BEFORE Activate, OR the order must be returned to a draft/edit posture, repriced, then re-activated.
  2. **Assetization runs post-activate** (`Fortra_Assetize_Order` V17 active; `createOrUpdateAssetFromOrder`
     spawns AssetizationAsyncJob — see SC-3415/3419 memory). If split lands async and interleaves with the
     post-activate assetize job, you get optimistic-lock collisions / 0-Assets (the SC-3419 swallow). Async
     split MUST be sequenced to complete before activation, never racing assetization.
- `OrderCommercialNetService` header comment itself warns the *opposite* race: re-running
  `PartnerNetPricePosthook` at activation "can gack or leave createOrUpdateAssetFromOrder stuck at
  ContextPersistence without spawning AssetizationAsyncJob" — i.e. the RC context engine is sensitive to
  when OrderItem pricing fields are mutated relative to assetization. Async ordering is load-bearing.

## 4. Reprice cost at scale — does async just move the CPU wall?  (TASK 4)

LARGELY YES, the reprice step ALSO scales with N and will hit the same wall at extreme quantities.

Per-N costs in the reprice tail (N = number of split lines):
- `OrderRepriceInvocable` builds the Force-reprice **GraphRequest with 1 PATCH record per OrderItem**
  (`for oi : work.allOrderItems`). `commerceorders.PlaceOrderExecutor.execute(...Force...)` runs the V16
  pricing procedure against all N lines synchronously → CPU scales ~linearly with N (plus the procedure's
  own per-line element cost).
- Four bulk OrderItem UPDATE passes over all N lines: seedFromWork, persistFromWork (×2), and
  OrderCommercialNetService.patch — each UPDATE fires the **RecordAfterSave** `Set_Workday_Contract_Line_Type`
  flow V11 once per line (Get_Product SOQL + 5 recordUpdates incl `$Record` re-update, which re-fires
  RecordBeforeSave Set_Dates). This is the same per-line flow re-entrancy that drives the convert CPU blowup
  in the split phase. It re-fires here on every reprice-phase UPDATE.
- `PartnerNetPricePosthook` is a 92KB class (LengthWithoutComments 92,263) — heavy per-line work.

So the CPU problem is NOT confined to the splitting loop; the in-transaction reprice of N lines is itself an
O(N) CPU consumer, amplified by the per-line RecordAfterSave flow firing on each of ~4 bulk updates and the
Force pricing procedure pricing N lines. With client quantities up to 750,000, even a perfectly bulkified
async split cannot reprice 750k OrderItems in a single 60s async CPU window, and the platform also caps
PlaceOrderExecutor graph size / records.

**Implication for the fix:** moving split async does NOT by itself solve the limit at the client's true scale.
The reprice + assetize + the RecordAfterSave flow must also be made N-scalable (e.g. Batch Apex chunking the
reprice graph, suppressing the per-line Workday line-type flow during bulk convert and running it once in a
controlled batch, or — strategically — questioning whether one OrderItem per unit is the right model when
Power "quantity" is a seat/user count up to 999,999, not a machine count). Async chunking (Batchable over
OrderItem chunks, each chunk reprices its own slice) is the realistic path, but it requires the whole
Split→Reprice→Activate tail to be reworked as a multi-chunk async pipeline with a final activation step that
runs only after all chunks are priced and ValidationResult is clean.

## 5. OrderItem staging fields (shared-proc prereq)  (TASK 5)

All shared-procedure staging fields from `project_v16_order_pricing_contextfetch_incident` EXIST on OrderItem:
- `Pre_Partner_Price__c` — FOUND
- `Partner_Pricing_Source__c` — FOUND
- `CancelNetUnitPrice__c` — FOUND (SC-3441 cancellation seed)
- `RegionalNetUnitPrice__c` — FOUND
- `Original_Order_Item__c` — FOUND (the qty-split FK set by PowerOrderSplittingService)
- `Is_Split_Line__c` — FOUND
- Plus: `PartnerUnitPrice`, `PartnerDiscountPercent`, `Partner_Discount_Type__c`, `Prior_Partner_Discount__c`,
  `NetTotalPrice`, `NetTotalPrice_Calculated__c`, `AllowRegionalPricing__c`, `OriginalOrderItemId` (standard).
- NOT present: `Partner_Net_Price__c` (does not exist; `Solution_Group__c` is NOT on OrderItem — split gate
  reads `Product2.Solution_Group__c` via relationship, confirmed in PowerOrderSplittingService SOQL).

**Clone-stamping note:** `PowerOrderSplittingService.createFullClone` copies ALL createable OrderItem fields
from the original, so split clones DO carry Pre_Partner_Price__c / Partner_Pricing_Source__c /
RegionalNetUnitPrice__c etc. from the parent. That means clones are already stamped to survive the V16
shared-proc context fetch — important: an async re-implementation must preserve this full-field clone (a
"lite" clone that only copies a few fields would re-trigger the V16 "couldn't fetch SalesTransactionContextExt_v2"
incident on the clones during reprice).

## Conclusion (async feasibility verdict)

- Reprice = RCA `PlaceOrderExecutor` Force against active Order proc **V16** / context **SalesTransactionContextExt_v2**.
- Reprice and Activate DEPEND on the split already being committed in the same transaction (graph membership +
  ValidationResult gate). You cannot move only the split async and leave reprice/activate where they are.
- OrderItem DML is not platform-locked (unlike Quote), and async OrderItem DML post-convert is allowed, but it
  must finish before Activate and must not race the post-activate assetize async (SC-3419 risk).
- Async split does NOT by itself remove the CPU wall: the in-transaction reprice of N lines + the per-line
  RecordAfterSave Workday line-type flow on ~4 bulk updates + the Force pricing of N lines is itself O(N).
  A real fix needs to chunk the whole Split→Reprice→Activate tail (Batch Apex) and/or suppress the per-line
  flow during bulk convert, and likely revisit one-OrderItem-per-unit for seat-count Power lines.
- All staging fields exist; full-field clone already stamps them — preserve that in any rewrite.
