# H3-opp-sync-reconciliation — VERDICT: REFUTED (native-semantics lens)

## Confirmed the VERIFIED facts (re-read)
- 19_opp.json: Opp 006WC00000NMOODYA5 SyncedQuoteId=quote, IsClosed=false (StageName re-queried = "Pre-Qualified").
- 20_oli.json: all 4 OLIs Product_Selling_Model__c = null.
- qli_oli_linkage.txt: all 4 QLIs carry ProductSellingModelId + OpportunityLineItemId. Quote.IsSyncing=True. Asymmetry real.

## Refutation pillars
1. OLI.Product_Selling_Model__c is a CUSTOM field (FieldDefinition: DataType "Lookup(Product Selling Model)", __c suffix). 
   OpportunityLineItem has NO standard ProductSellingModel relationship (full field dump: oli_all_fields.txt).
   Native quote->opp sync syncs STANDARD fields ONLY and explicitly ignores custom fields (Salesforce Help, multiple).
   => A native Map.get() cannot be keyed on Product_Selling_Model__c; native code is custom-field-blind. The null is the
      EXPECTED benign state (native sync never wrote it because it's custom). Matches the contradicting-evidence the mission flagged.
2. RLM Place Sales Transaction pipeline has ZERO coupling to opportunity sync:
   grep of full 4MB RLM Dev Guide => "OpportunityLineItem"=0 hits, "SyncedQuote"=0 hits in calc/place docs. 
   Only opp-sync mention in guide = contract-amendment context (different flow).
3. Custom sync stack retrieved LIVE (verify/sync_src/): 
   - QuoteSyncingTrigger = after-update on Quote; handler fires ONLY when IsSyncing flips false->true AND opp StageName='Order Processing'
     (this opp = Pre-Qualified => early return). Initializes a CHECKLIST. No line reconciliation, no PSM map, not on delete.
   - QuoteSyncQueueable = ASYNC (Queueable), only sets Opportunity.SyncedQuoteId=quoteId. No line reconciliation, no PSM map.
   => No custom code does QLI<->OLI per-line reconciliation keyed on selling model. Sync is async/separate-txn; cannot throw the
      SYNCHRONOUS toast inside the Place Sales Transaction reprice.
4. The exact error string is a DOCUMENTED Context Service / pricing-calc failure (Salesforce KB 005316661): extra Context Tags in the
   SalesTransaction node -> calc engine Map.get()==null -> CalculationStatus=PriceCalculationFailed. Pricing/context frame, NO sync.
   Mission A independently traced the throw to industries.context.api.service (context hydration for the pricing procedure).

## What only a live trace can settle (out of scope here)
- A debug-logged repro would positively confirm the throwing stack frame is context/pricing (refute) vs any sync frame (would resurrect H3).
