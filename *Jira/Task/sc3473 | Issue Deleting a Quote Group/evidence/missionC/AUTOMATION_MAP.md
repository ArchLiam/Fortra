# SC-3473 Mission C — Trigger + Flow audit (delete & reprice path), FortraUAT live

Repro quote 0Q0WC000002U2020AC: Status=Accepted, Quote_Type__c=NULL, OriginalActionType=NULL,
IsSyncing=TRUE, OpportunityId=006WC00000NMOODYA5, USD. NOT a renewal quote.
Group deleted: 1C9WC00000097of0AA "Test HW1" (only group). Deletes 2 grouped lines:
 - 0QLWC000003jN6n4AE Advanced Job Scheduler (SM-AJS-NRPS-AJSP) FPT=Perpetual
 - 0QLWC000003jN8P4AU Abstract (BI-ABS-RSS-ABSTSU) FPT=Subscription
Survivors repriced (UPDATE): 2x Suspicious Email Intelligence (ES-ETM-RMS-SUSPIN) FPT=Subscription, COLA all null.

## APEX TRIGGERS (all Active; NONE have delete context)
| Trigger | api | DML events | Fires on grouped-line DELETE? | Fires on survivor UPDATE (reprice)? | Net effect for this quote |
|---|---|---|---|---|---|
| QuoteLineItemTrigger | 61 | before insert/update, after insert | NO | before update: yes | before-update path only calls COLAUpliftHandler.handleBeforeUpdate + QLITriggerHandler.handleHardwareLinking. RenewalMaintenanceAutoAdd/RenewalAssetQuantity are after-insert ONLY -> skip on update. |
| QuoteLineGroupTrigger | 61 | after update ONLY | NO (no delete ctx) | n/a (group is deleted, not updated) | dormant on delete |
| QuoteLineItemExchangeRateTrigger | 62 | before/after insert+update | NO | yes | before: stamps Exchange_Rate_To_USD__c; after: best-effort Opp update (allOrNone=false). Apex; no Java map. |
| QuoteTrigger | 66 | before insert/update | NO | n/a (quote update fires it) | both handlers gate on OriginalActionType='Renew' OR Quote_Type__c='Renewal' -> NO-OP (quote is neither) |
| QuoteSyncingTrigger | 62 | after update | NO | quote update fires it | only acts when IsSyncing flips false->true; already TRUE -> NO-OP |

handleHardwareLinking: only mutates when QuoteLineGroupId CHANGED on the line; survivors are ungrouped and stay ungrouped -> no-op.
COLAUpliftHandler.handleBeforeUpdate: only mutates COLA fields when COLA_Uplift_Percent__c changed; survivors have COLA null -> no-op. Pure Apex; cannot emit java.util.Map NPE.

## RECORD-TRIGGERED FLOWS on Quote/QLI/QLG (active inventory via FlowDefinitionView)
NONE are BeforeDelete/AfterDelete. Org-wide, the ONLY 4 active delete-triggered flows are on Product of Interest, Opportunity Partners, Order, Order Product — none on the group-delete path.

| Flow (active V) | obj | triggerType | recordTrigger | Entry filter | Fires on grouped-line DELETE? | Fires on survivor UPDATE? | Relevance |
|---|---|---|---|---|---|---|---|
| Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values (V1) | QLI | BeforeSave | CreateAndUpdate | none | NO | YES | stamps LegalEntityId on $Record only; no extra DML |
| Stamp_Maintenance_Pricing_Inputs (V21) | QLI | BeforeSave | CreateAndUpdate | none | NO | YES but entry decision requires FPT IN (New/Renewal Maintenance) -> survivors=Subscription -> branch skipped |
| Stamp_Source_List_Price (V8) | QLI | BeforeSave | CreateAndUpdate | none | NO | YES; "Is Derived Line" gate; non-derived survivors short-circuit |
| Fortra_QuoteLineItem_Legal_Entity_Copy | QLI | AfterSave | Create ONLY | LegalEntityId IsNull | NO | NO (create only) |
| Quote_Line_Item_On_Create | QLI | AfterSave | Create ONLY | none | NO | NO (create only) |
| POI_Update_Opportunity_From_QLI (V1) | QLI | AfterSave | CreateAndUpdate | none | NO | YES; updates parent Opportunity only (not QLI/Quote) |
| Fortra_Quote_Count_Maintenance (V9) | Quote | AfterSave | CreateAndUpdate | OpportunityId IsNull | NO | quote update: SKIPPED (quote HAS an Opportunity) |
| Fortra_Quote_Sync_Address_From_Place | Quote | AfterSave | (n/a delete) | - | NO | possible on quote update; address only |
| Fortra_RCA_Renewal_Enhancement | Quote | AfterSave | Create ONLY | Quote_Type__c IsNull | NO | NO (create only) |
| Quote_After_Update_Create_Order_From_Quote | Quote | AfterSave | Update | Create_Order_from_Quote__c = true | NO | only if that flag set |
| Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered | Quote | BeforeSave | - | - | NO | possible on quote update; field stamping |
| Fortra_Quote_Validate_Partner_Pricing_Model | Quote | BeforeSave | - | - | NO | validation only |

## REPRICE MECHANISM
Fortra_Quote_Reprice (active V27) = AutoLaunchedFlow, input QuoteId. Calls native invocables:
buildContext (buildContext) -> Run_Pricing (runSalesforcePricing = the MANAGED Java pricing engine) -> persistContextData,
plus Apex posthooks PartnerNetPricePosthook, RenewalMaintenancePricingService. The runSalesforcePricing /
buildContext / persistContextData invocables are the platform-native code that emits JEP-358 "java.util.Map.get" NPEs.

## CONCLUSION (mission C)
No custom Apex trigger and no custom flow runs on the DELETE of the two grouped lines.
All custom automation that could fire is on the survivor UPDATE / quote UPDATE during reprice, and every
piece is gated OFF or no-op for this quote (not a renewal; survivors are Subscription non-maintenance,
COLA null; quote already syncing; quote has an Opportunity). The custom layer therefore does NOT throw the
java.util.Map NPE and does not null a lookup on the delete path. The throw is inside the native engine
(buildContext/runSalesforcePricing/persistContextData) on a Map keyed by something missing for the surviving
config after the grouped lines are gone — a DATA/CONFIG condition, not a trigger/flow fault.
