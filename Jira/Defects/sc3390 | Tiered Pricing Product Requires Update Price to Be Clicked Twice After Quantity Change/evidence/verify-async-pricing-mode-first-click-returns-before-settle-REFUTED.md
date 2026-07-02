# SC-3390 — Adversarial verification: [async-pricing-mode-first-click-returns-before-settle]
Verdict: REFUTED (read-only, FortraUAT, 2026-06-11)

## Candidate claim
RLM is in ASYNC/deferred pricing mode; first 'Update Price' enqueues a background
pricing job and the grid returns/refreshes before the recompute settles -> stale tier price.

## CONFIRM signature required by candidate
"RLM pricing settings show async/deferred pricing ENABLED ... progressIndicator telemetry
shows the grid refresh completing before the background recompute."

## Decisive refuting evidence

### 1. RLM pricing is configured SYNCHRONOUS (settings retrieved from org)
File: settings-pricing/unpackaged/settings/IndustriesPricing.settings
  enableLargeTransactionPricing = FALSE   <- THE async/deferred large-txn pricing toggle = OFF
  enablePricingProcParallelization = FALSE
  enableHighAvailability = FALSE
File: settings-retrieve/unpackaged/settings/RevenueManagement.settings
  enableDeltaPricing = FALSE
  enableTransactionProcessor = TRUE (synchronous transaction processor)
There is NO setting enabling async/deferred pricing. The async-mode precondition is FALSE.

### 2. The 'Update Price' (place) call prices INLINE in one synchronous transaction
Log: log-place-04-34-13.txt  (op = /connect/rev/sales-transaction/actions/place, 2,076,769 chars)
  - Whole txn spans 21:34:13 -> 21:34:18 (~5s), single Apex transaction.
  - Pricing context build + ExpressionSet + prehook all run INLINE:
      L273  CODE_UNIT_STARTED Get context price for context id ... 0Q0WC000003671t
      L322/3429/5973 revenue.common.service.RevenueTransactionApexExecutor (prehook host)
      L7365 AttributeVolumePricingPrehook v3.0 START ... L8306 END  (same txn)
  - L26264: "public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest):
      executed 1 time in 367 ms" -> pricing returns a TransactionResponse SYNCHRONOUSLY inline.
  - Fully-priced QLI written back IN-TXN (L25054+, L25628+): NetUnitPrice/Subtotal/ALE computed,
      LastModifiedDate + COLA_Applied_Date__c stamped 2026-06-11T04:34:18 (this txn).
  => price-contexts returns the priced result inline. This is the candidate's own REFUTE branch.

### 3. The ONLY async job after place is NOT pricing
  - L19279 System.enqueueJob -> COLAUpliftPrehook.MyCAPFlagApplier (L1201).
  - L1202 debug: "MyCAP: enqueued - Quotes flag=true:0 flag=false:1" -> writes Quote.Mycap__c only.
  - QueueableHandler tail logs confirm it does NOT reprice or write tier price.

### 4. Prehook source has ZERO async deferral
File: Org Data/_src/classes/AttributeVolumePricingPrehook.cls
  - implements RevSignaling.SignalingApexProcessor (synchronous pricing signal processor).
  - grep enqueueJob/@future/System.schedule/Database.executeBatch = NONE.
  - Writes result inline: L623 industriesContext.updateContextAttributes(updateInput).

### 5. progressIndicator and the PricingApiExecution burst do NOT indicate async mode
  - Quote_Record_Page.flexipage L92-93: runtime_revenue_foundation:progressIndicator present,
    but it is a UI affordance only; nothing in the flexipage enables async pricing.
  - PricingApiExecution object fields (FIELDS(ALL) describe) = ExecutionKey, Status, ReferenceKey,
    ApiEndpoint, ApiType. NO ProcessingMode/Async field exists -> the candidate's required
    "progressIndicator telemetry shows grid refresh before background recompute" is UNOBTAINABLE
    AND nothing about the burst distinguishes async from rapid synchronous clicks. The 14:46:19
    Failure is a single failed synchronous price-contexts POST, equally explained by sync calls.

## Conclusion
Async/deferred pricing mode is DISABLED (enableLargeTransactionPricing=false) and the place
pricing run is provably inline-synchronous, returning the priced TransactionResponse before the
HTTP call completes. The candidate's CONFIRM signature is contradicted on every leg; its own
stated REFUTE condition (synchronous mode) is satisfied. REFUTED.
The real lag is NOT in an async pricing pipeline — it belongs to the synchronous
snapshot/context-commit timing family (the configurator-attribute / Attribute_Volume context
hydration documented in ui-FINDINGS-summary.txt #5), which is a different mechanism.
