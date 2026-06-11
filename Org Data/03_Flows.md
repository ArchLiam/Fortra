# 03 — Flows

## Overview

This org contains **245 custom Flows** spanning lead/quote/order lifecycle automation, Revenue Cloud (RCA) pricing and renewal logic, Workday and HubSpot/MuleSoft integration plumbing, Certinia PSA (`pse__`) automation, and UAT/test-management utilities. The dominant patterns are **record-triggered flows** (before-save field derivation, after-save side-effects), **autolaunched subflows** invoked from Apex/other flows, **screen flows** for guided UI actions, and a large family of **platform-event publisher flows** that push data to Workday and HubSpot.

Two naming conventions matter:
- **`Fortra_*`** — the team's own custom automation (the bulk of the load-bearing business logic). Labels usually follow `Fortra | Object | Trigger - Purpose`.
- **`GearsetCloneSupportFlow*`** — 26 trivial Gearset-generated before-save no-op flows on RCA setup objects (AttributeDefinition, BillingPolicy, Product2, etc.) that exist only to let Gearset clone those platform objects across sandboxes. All Active, all `RecordBeforeSave/Create`. Treat as infrastructure, not business logic.

**Load-bearing / fragile callouts:**
- **Pricing**: `Stamp_Maintenance_Pricing_Inputs`, `Stamp_Source_List_Price`, `Fortra_Quote_Reprice`, `Fortra_Order_Reprice` (now Obsolete), and the `Fortra_Migration_Price_Quote` context-builder feed the gated Maintenance Derived Pricing procedure (SC-3350/COLA work). `Stamp_Maintenance_Pricing_Inputs`'s **RENEWAL branch is explicitly marked UNTESTED**.
- **Workday line-type**: `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (Active) is the live one; `Fortra_Autolaunched_Set_Workday_Contract_Line_Type` and `Fortra_Order_After_Save_Set_Workday_Contract_Line_Type` are Draft/Obsolete (this is the V8/V9/V10 line-type saga from memory — the active Apex flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type` is the contested one).
- **Order/Quote conversion**: `Fortra_Quote_to_Order_Conversion`, `Quote_After_Update_Create_Order_From_Quote`, and the renewal/amendment override flows (`Fortra_Create_Renewal_Quote`, `Fortra_Create_Amendment_Quote`, `Fortra_RCA_Renewal_Enhancement`).
- Several currency/legal-entity flows are **Obsolete** but their replacements coexist — see the Opportunity section.

Status legend: **Active** = running; **Draft** = saved, not activated; **Obsolete** = deactivated/superseded; **InvalidDraft** = draft that fails activation validation (effectively dead).

---

## Account

### Record-triggered — before save

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Account_Account_Type | Before Save (Create+Update) | Active | Derives Account Type. |
| Account_Before_Insert_Update_Sync_Status | Before Save (Create+Update) | Active | Sets HubSpot Sync Status = Pending to queue outbound sync. |

### Record-triggered — after save

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Account_After_Insert_Update_D_B_Enrichment | After Save (Create+Update) | Active | D&B enrichment callout; has data-migration-user bypass. |
| Account_Team_Member_Assignment | After Save (Create) | Active | Assigns Account Team Members on new Accounts. |
| Fortra_Opportunity_Legal_Entity_AutoSelect | After Save (Create+Update) on Account | **Obsolete** | Auto-populated Opportunity Legal Entity/currency from Account default; superseded. |
| Product_Of_Interest_After_Insert_Sales_Territory_Assignment | After Save (Create) | Active | Sales territory assignment (CAM) from product interest. |
| Sales_Inquiry_Territory_Assignment | After Save (Create+Update) | Active | Territory assignment from Marketing Products on Account. |

### Platform-event publisher (on Account)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Account_After_Insert_Update_Platform_Events | After Save on `Account_Upsert_HS__e` | Active | Publishes HubSpot upsert platform event for Accounts. |

### Screen / autolaunched (Account-context UI)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Hardware_Hardware_Management_Orchestrator | Screen Flow | Active | Orchestrates hardware search/selection/status from Account context. |
| Subflow_Account_Team_Member_Assignment | Autolaunched subflow | Active | Finds AE / Account Team Member; checks active user, industry, status. |
| Partner_Product_Compliance_Alert | Screen Flow | Active | Flags Product-of-Interest / Solution Group mismatches. |
| Screen_Flow_Account_Enrichment | Screen Flow | Active | DUNS enrichment screen. |
| Screen_Flow_Create_Account_with_D_B_Integration | Screen Flow | Active | Create Account via D&B DUNS search callout. |
| Fortra_Screen_Flow_Create_Lead_Contact_for_VoiceCall | Screen Flow | Active | Creates Lead/Contact from inbound voice call. |

---

## Contact

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Contact_Before_Insert_Update_Sync_Status | Before Save (Create+Update) | Active | Sets HubSpot Sync Status = Pending (Workday sync assignment removed 2026-05-22). |
| Contact_After_Insert_Update_Contact_Product_Account_Relationships | After Save (Create+Update) | Active | Assigns CPAR (Contact-Product-Account Relationship) fields. |
| Fortra_VoiceCall_Before_Insert_Populate_Related_Record_Field | Before Save (Create) | Active | Links VoiceCall to Contact by caller phone. |
| VoiceCall_Before_Create | Before Save (Create) | **Draft** | Older VoiceCall→Contact linker (superseded by Fortra_ version). |

### Platform-event publisher (on Contact)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Contact_After_Insert_Update_Platform_Events | After Save on `Contact_Upsert_HS__e` | Active | Publishes HubSpot upsert event for Contacts. |

### Screen / routing (Contact-context UI)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| New_Contact_Relationship_Screen_Flow | Screen Flow | Active | Creates contact relationships. |
| Screen_Flow_Assign_Contact_Product_Account_Relationship | Screen Flow | Active | Assigns CPAR roles via multi-select picklist. |
| Fortra_Omni_Flow_Screen_Pop_on_Inbound_Call | RoutingFlow | Active | Omni screen-pop matching inbound caller to Contact. |
| Fortra_Screen_Flow_Screen_Pop_on_Inbound_Call | RoutingFlow | Active | Screen-pop variant matching caller phone to Contact. |

---

## Lead / Inquiry

"Inquiry" is the Fortra label for the Lead object. Heavy before-save derivation plus MuleSoft integration.

### Record-triggered — before save (Lead)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Inquiry_Before_Insert_Set_Defaults | Before Save (Create) | Active | Sets default field values on new Inquiries. |
| Fortra_Inquiry_Before_Insert_Update_Partner_Manager | Before Save (Create+Update) | Active | Assigns Partner Manager. |
| Fortra_Inquiry_Before_Insert_Update_Processing_Status | Before Save (Create+Update) | Active | Sets Processing Status = Ready for Assignment (IsChanged guards added 2026-04-24). |
| Fortra_Inquiry_Before_Insert_Update_Products_of_Interest | Before Save (Create+Update) | Active | Populates POI-related fields. |
| Fortra_Inquiry_Set_MQL_Date_on_Creation | Before Save (Create+Update) | Active | Stamps MQL date (SC-2421). |
| Fortra_Inquiry_Set_SAL_Date_on_Stage_Change | Before Save (Update) | Active | Stamps SAL date on stage change (SC-2421). |
| Inquiry_Before_Insert_Update_Sync_Status | Before Save (Create+Update) | Active | Sets MuleSoft Sync Status = Pending (data-migration-user bypass). |
| Event_Before_Insert_Update | Before Save (Create+Update) on Lead | Active | Record-ID prefix routing; cloned from after→before to stop looping (2026-02-10). |
| Task_Before_Insert_Update | Before Save (Create+Update) on Lead | Active | Updates Task Name ID with Contact record ID. |

### Record-triggered — after save (Lead / related)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Inquiry_After_Insert_Update_Matching_Unsuccessful | After Save (Create+Update) on Group | Active | Handles unsuccessful Inquiry matching when owner is a Queue. |
| Inquiry_After_Insert_Update_Campaign_Member_Automation | After Save (Create+Update) on CampaignMember | Active | Creates Campaign Members from Inquiries. |

### Platform-event publisher (Inquiry → MuleSoft)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Inquiry_After_Insert_Update_Platform_Events | After Save on `Lead_Upsert_Mulesoft__e` | Active | Publishes MuleSoft Lead-upsert event. |

### Screen

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Inquiry_Conversion_Screen_Flow | Screen Flow (Opportunity) | Active | Converts Inquiries; guards OTM creation error when owner is a Queue. |

---

## Opportunity

The largest behavioral cluster. Note the **Legal Entity / currency family**, which has several Obsolete + Active flows coexisting — be careful which is live.

### Record-triggered — before save

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Opportunity_Before_Insert_Update_Sync_Status | Before Save (Create+Update) | Active | Sets HubSpot Sync Status = Pending. |
| Fortra_Opportunity_Derive_Deal_Origin | Before Save (Create+Update) | **Obsolete** | Derived Deal_Origin from partner fields; superseded. |
| Fortra_Opportunity_LE_Currency_Validation | Before Save (Create+Update) on `Legal_Entity_Currency__mdt` | Active | Validates LE+currency combo; resets to LE primary currency if invalid. |

### Record-triggered — after save

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Opportunity_After_Update_Territory_Assignment | After Save (Update) | Active | Territory assignment on Opportunity update. |
| Fortra_Opportunity_Line_Item_Calculate_Total_ARR | After Save (Create+Update) | Active | Calculates Total ARR on Opportunity. |
| Fortra_Opportunity_Currency_Sync | After Save (Update) on LegalEntity | Active | Syncs Opportunity currency when LE changes; skips if related Quotes exist (SC-199). |
| Fortra_Opportunity_Owner_Change | After Save (Update) on OpportunityShare | Active | Maintains OpportunityShare on owner change. |
| Initialize_Operations_Checklist | After Save (Update) | Active | Initializes Operations Checklist when stage → Order Processing. |
| Opportunity_Create_Opportunity_Partners_Sync | After Save (Create) | Active | Syncs Opportunity Partners (Distributor/etc.) on create. |
| Opportunity_After_Insert_Update_Opportunity_Partners_Sync | After Save (Update) on `Opportunity_Partners__c` | Active | Syncs partner records (SC-2528 name-length fix). |
| Opportunity_Partners_After_Insert_Update_Opportunity_Sync | After Save (Create+Update) | Active | Bypasses partner VR / avoids recursion when syncing partners → Opp. |
| Opportunity_Partners_Delete_Opportunity_Sync | Before Delete | Active | Partner-delete sync back to Opportunity. |
| Opportunity_Team_Member_After_Insert_Opportunity_Splits | After Save (Create) on OpportunityTeamMember | Active | Creates Opportunity Splits from team members. |
| PSA_RTF_Opportunity_Created_Update_Practice | After Save (Create+Update) on OpportunityLineItem | Active | PSA: rolls Practice up from OLIs. |
| PSA_RTF_Opportunity_Created_or_Updated_for_Is_service_Opportunity | After Save (Create+Update) on OpportunityLineItem | Active | PSA: flags service Opportunities from service OLIs. |
| FFX_PSA_Opportunity_Product | After Save (Create+Update) on OpportunityLineItem | Active | PSA opportunity-product automation. |

### Platform-event publisher (on Opportunity)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Opportunity_After_Insert_Update_Platform_Events | After Save on `Opportunity_Upsert_HS__e` | Active | Publishes HubSpot upsert event for Opportunities. |

### Renewal / amendment quote overrides (autolaunched, Opportunity object)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Create_Amendment_Quote | Autolaunched | Active | Override for `quotingAI__createAmendmentQuote`; resolves Asset chain, calls initiateAmendment, sets Quote_Type=Amendment, Amendment_Reason=Upsell. |
| Fortra_Create_Renewal_Quote | Autolaunched | Active | Override for `quotingAI__createRenewalQuote`; resolves Asset chain, calls initiateRenewal, populates Fortra renewal fields. |
| Fortra_RCA_Renewal_Enhancement | After Save (Create) on Opportunity | Active | Enhances RCA renewal/amendment Quotes; traces Asset→Contract, creates Renewal/Amend Opportunity, copies billing/places/terms. |

### Screen / quick actions (Opportunity)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Add_Preferred_Partner_from_Opportunity | Screen Flow (`Preferred_Partners__c`) | Active | Quick action to add Preferred Partner via screen. |
| Fortra_Opportunity_Change_Legal_Entity | Screen Flow (`Legal_Entity_Currency__mdt`) | **Obsolete** | Guided LE change with currency picker + blocker checks; uses LE_Change_In_Progress bypass flag. |
| Fortra_Opportunity_Create_New_Quote_From_Opportunity_Flow | Screen Flow (Quote) | Active | Creates new Quote from Opportunity, counts existing. |

---

## Quote

Approval criteria, conversion, currency, address sync, and pricing all live here. Note the large family of **`*_Approval_Criteria`** flows (mostly screen-context decision flows feeding the approval engine) and the **discount-bracket QLI collection flows**.

### Record-triggered — before save (Quote / QL attributes)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values | Before Save (Create+Update) on Quote | Active | Copies Quote values (e.g. Legal Entity) down to Quote Line Items. |
| Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered | Before Save (Create+Update) | Active | Sets MYCAP Approval flag. |
| Fortra_Quote_Validate_Partner_Pricing_Model | Before Save (Create+Update) on `Partner_Pricing_Model__c` | Active | Validates an active matching Partner Pricing Model exists for the Billing Partner. |

### Record-triggered — after save (Quote)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_Approvals | ApprovalWorkflow, After Save (Update) | Active | Quote approval workflow (cancellation CCO/proxy 250+ routing). |
| Fortra_Quote_Count_Maintenance | After Save (Create+Update) | Active | Maintains Opportunity Quote_Count__c (enables Legal_Entity_Requires_Action VR). |
| Fortra_Quote_Count_Maintenance_Delete | Before Delete | **Obsolete** | Companion delete-side count decrement; superseded. |
| Fortra_Quote_Line_Item_Legal_Entity_Copy (`Fortra_QuoteLineItem_Legal_Entity_Copy`) | After Save (Create) on Quote | Active | Copies Legal Entity from Quote to QLI for Q2O mapping. |
| Quote_After_Update_Create_Order_From_Quote | After Save (Update) | Active | Triggers Create Order from Quote. |
| Warn_Opportunity_Quote_Currency_Mismatch | After Save (Create+Update) | **Draft** | Would warn on Opp/Quote currency mismatch. |
| Warn_Quote_Order_Currency_Mismatch | After Save (Create+Update) | **Draft** | Would warn on Quote/Order currency mismatch. |

### Autolaunched — pricing / repricing (Quote)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_Reprice | Autolaunched | Active | **Pricing**: Quote Migration Tool repricer — builds context, runs RCA pricing, persists to Quote+QLI. |
| Fortra_Migration_Price_Quote | Autolaunched | Active | **Pricing**: hydrates Quote data into a pricing context instance. |
| Fortra_Quote_Reprice_And_Q2O | Autolaunched | **Obsolete** | Test flow: reprice then immediate Q2O in one transaction. |
| Fortra_Quote_Reprice_Test_NoSkipDiscovery | Autolaunched | **Obsolete** | Test flow: reprice with skipDiscovery=false. |
| Fortra_Quote_Check_Approval_Reject_Checkbox | Autolaunched | Active | Reads rejected flag for approval routing. |
| Approvals_Update_Quote_Stage | Autolaunched | Active | Updates Quote stage on approval rejection. |

### Approval-criteria / discount-bracket flows (screen-context decision, object = Quote/QuoteLineItem)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_Discount_Renewal_ARR_Approval_Criteria | Flow (Quote) | Active | Renewal ARR discount approval check. |
| Fortra_Quote_Displaced_ARR_Approval_Criteria | Flow (Quote) | Active | Displaced ARR approval check. |
| Fortra_Quote_Legal_Support_Approval_Criteria | Flow (Quote) | Active | Legal-support-needed approval check. |
| Fortra_Quote_License_Key_Extension_Approval_Criteria | Flow (Quote) | Active | License-key-extension approval check. |
| Fortra_Quote_MYCAP_Sale_Approval_Criteria | Flow (Quote) | Active | MYCAP approval check. |
| Fortra_Quote_Net_Terms_Approval_Criteria | Flow (Quote) | Active | Net-terms > 30 days approval check. |
| Fortra_Quote_Renewal_Cancellation_Approval_Criteria | Flow (Quote) | Active | Renewal cancellation approval check. |
| Fortra_Quote_Renewal_Recognition_Approval_Criteria | Flow (Quote) | Active | Credit-renewal-ARR recognition approval check. |
| Fortra_Quote_Signed_Quote_Approval_Criteria | Flow (Quote) | Active | Signed-quote approval check. |
| Fortra_Quote_Unsigned_Quote_Approval_Criteria | Flow (Quote) | Active | Unsigned-quote approval check. |
| Channel_MSP_Pricing_Discounts_Approval_Criteria | Flow (QuoteLineItem) | **Draft** | MSP pricing discount bracket (QLI 16-20). |
| Fortra_Quote_Tech_Maintenance_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Tech maintenance discount bracket (50+). |
| Fortra_Quote_Tech_Perpetual_License_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Tech perpetual-license discount bracket (1-25). |
| Fortra_Quote_Tech_Services_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Tech services discount bracket (16-20). |
| Fortra_Quote_Tech_Subscription_Pricing_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Tech subscription discount bracket (16-20). |
| Maintenance_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Maintenance discount bracket (1-50). |
| Perpetual_License_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Perpetual-license discount bracket (1-25). |
| Services_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Services discount bracket (16-20). |
| Subscription_Pricing_Discounts_Approval_Criteria | Flow (QuoteLineItem) | Active | Subscription discount bracket (16-20). |
| Approval_Template | Flow (Quote) | Active | Generic approval-template decision. |
| Main_Approvals_Flow_Screen | Screen Flow (Quote) | Active | Surfaces found approvals to user. |

### Address sync (Quote)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_Sync_Address_From_Place | After Save (Update) on `Places__c` | Active | Re-populates Quote Billing/Shipping address when Bill_To/Ship_To Place changes. |

### Screen / conversion (Quote-context UI)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Quote_to_Order_Conversion | Screen Flow (AppUsageAssignment) | Active | Create Order from Quote; maps custom Hardware/Partition lookups the standard Q2O omits. |
| Fortra_Renewal_Quote_Creation | Screen Flow (Quote) | Active | Renew button on Contract: creates renewal Quote, copies fields, applies COLA via COLAUpliftHandler, sets Contract Renewal_Status. |
| Fortra_Set_Amendment_Details | Screen Flow (Quote) | Active | Edits Amendment Reason on amendment Quotes. |
| Quote_Handle_Quote_Currency_Change | Screen Flow (Quote) | **Draft** | Apex-backed currency-change handler. |

---

## QuoteLineItem (record-triggered, non-approval)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Quote_Line_Item_On_Create | After Save (Create) on QuoteLineItemAttribute | Active | QLI on-create attribute setup. |
| Fortra_Quote_Line_Item_Before_Insert_Update_Set_Services_Hourly_Rate | After Save (Create+Update) on QuoteLineItemAttribute | **Obsolete** | Set Services Hourly Rate for hourly prepaid; superseded. |
| Fortra_Quote_Line_Item_Calculate_Total_ARR | After Save (Create+Update) on QuoteLineItem | **Obsolete** | Calculated base/total ARR on QLI; superseded. |
| Fortra_QuoteLineItem_Calculate_ARR | Before Save (Create+Update) on ProductSellingModel | **Obsolete** | ARR calc from selling model; superseded. |
| Delete_Related_QLI_upon_deletion_of_EPI | Before Delete on QuoteLineItem | **InvalidDraft** | Would delete QLIs when Estimate Product Instance deleted (dead). |
| POI_Update_Opportunity_From_Sync | After Save (Update) on QuoteLineItem | Active | Syncs POI from QLI back to Opportunity. |
| POI_Update_Opportunity_From_QLI | After Save (Create+Update) on Opportunity | Active | Updates Opportunity Product_of_Interest when QLI IsProductOfInterest changes. |

---

## Order

Order automation centers on **Workday sync**, **assetization**, **address/place sync**, and **payment terms / billing schedule**. Several Workday line-type and platform-event flows are Obsolete/Draft — see Workday notes.

### Record-triggered — before save (Order)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_OrderItem_Set_Dates | Before Save (Create+Update) on OrderItem | Active | **SC-3297**: defaults null From/To on non-perpetual lines to 12-mo term off Order EffectiveDate. |
| Order_Before_Insert_Update_Sync_Status | Before Save (Create+Update) | Active | Sets Legacy Sync Status = Pending (2026-05-01). |

### Record-triggered — after save (Order / OrderItem)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_OrderItem_Set_Workday_Contract_Line_Type | After Save (Create+Update) on OrderItemAttribute | Active | **Workday**: Prepaid service → PREPAID, else USAGE BASED (the live line-type flow). |
| Fortra_Order_After_Save_Set_Workday_Contract_Line_Type | After Save (Update) on OrderItem | **Obsolete** | Stamped line type on Order Complete via subflow; superseded. |
| Fortra_Order_Workday_Contract_ID | After Save (Create+Update) on Order | Active | Stamps Workday Contract ID. |
| Fortra_Order_Set_Workday_and_PO_Fields | After Save (Create+Update) on Order | **Obsolete** | Set Workday/PO fields; superseded. |
| Fortra_Order_Workday_Status | After Save (Update) on Order | **Draft** | Order/OrderItem Workday sync-failure notification. |
| Fortra_Order_Integration_Check_Notification | After Save (Create+Update) on Order | **Draft** | Order integration-check notification. |
| Fortra_Order_to_Contract_Field_Mapping | After Save (Create) on Order | Active | Maps Fortra custom fields (Partner, Deal Type, Legal Entity) Order/Quote → Contract on conversion. |
| Order_After_Update_Platform_Events | After Save (Update) on `Invoice_PO_Updated_WD__e` | **Draft** | Older Order platform-event publisher (superseded by Fortra_ version). |
| Fortra_Order_After_Update_Platform_Event_Workday | After Save (Update) on `Invoice_PO_Updated_WD__e` | Active | Publishes Workday Invoice/PO-updated event (entry criteria removed 2026-05-01). |
| Fortra_Order_Sync_Address_From_Place | After Save (Update) on `Places__c` | Active | Re-populates Order Billing/Shipping address when Bill_To/Ship_To Place changes. |
| Fortra_Order_to_Billing_Schedule | After Save (Update) on PaymentTerm | Active | Calls Order→Billing Schedule action once required fields present. |
| Fortra_Order_Set_Payment_Terms | After Save (Create) on PaymentTerm | Active | Sets Order payment terms. |

### Assetization (Order → Asset)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Assetize_Order | After Save (Update) on AppUsageAssignment | Active | Creates/updates Asset related to the Order (live assetizer). |
| Order_Submission_to_Revenue_Orchestrator | After Save (Update) on AppUsageAssignment | Active | Submits Order to Revenue Orchestrator. |
| Create_Asset_From_Order | After Save (Update) on AppUsageAssignment | **Draft** | Earlier asset creator (superseded by Fortra_Assetize_Order). |
| Fortra_Order_Assetize_Order | After Save (Update) on AppUsageAssignment | **InvalidDraft** | Dead duplicate assetizer. |

### Delete guards (Globalscape integration user)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Order_Disallow_delete_for_Globalscape_Integration_User | Before Delete on Order | Active | Blocks Order delete for users with GlobalscapeNoDelete custom perm. |
| Order_Product_Disallow_delete_for_Globalscape_Integration_User | Before Delete on OrderItem | Active | Blocks Order Product delete for same custom perm. |

### Order — pricing / repricing (autolaunched)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Order_Reprice | Autolaunched | **Obsolete** | **SC-3308**: programmatic Order reprice (context + RCA pricing) before Activate; superseded. |
| Fortra_Autolaunched_Set_Workday_Contract_Line_Type | Autolaunched on OrderItemAttribute | **Draft** | Subflow stamping Workday line type from an OrderItem collection. |

### Order — screen / utility

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Order_Submission_Check | Screen Flow (Order) | Active | Order submission check (refresh page). |
| Fortra_Screen_Send_Order_to_Workday | Screen Flow | Active | Manual "Send Order to Workday" action. |
| Fortra_Cascade_Delete_Order | Screen Flow | Active | Cascade-deletes an Order and children. |
| Fortra_Subflow_Order_Completed_Platform_Event | Autolaunched on `Order_Completed_WD__e` | Active | Publishes Order Completed event (Workday re-submit mechanism). |

### Order — obsolete integration-check / place

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Order_Integration_Check | Before Save (Create+Update) on `Places__c` | **Obsolete** | Order integration validation; superseded. |
| Fortra_Order_Places_Primary_Check | Before Save (Create+Update) on `Places__c` | **Draft** | Order primary-place check. |

---

## Asset

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Asset_Copy_ARR_From_OrderItem | After Save (Create+Update) on AssetAction | Active | Copies ARR from OrderItem to Asset (via AssetAction). |
| Fortra_Asset_Populate_Legacy_Fields | After Save (Create) on AssetAction | Active | Populates legacy Asset fields from a Generate-type AssetAction. |

---

## Contract

The renewal/co-termination engine. Contract.Status is RCA-owned for CLM record types, so Fortra uses the custom `Renewal_Status__c` field for succession.

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Contract_Amendment_CoTermination | After Save (Create) | Active | Auto-sets amendment End Date to co-terminate with parent (FORTRA-CONTRACT-008). |
| Contract_Amendment_CoTerm_Override_Detection | After Save (Update) | Active | Sets Co_Term_Overridden__c when amendment end date manually diverges (FORTRA-CONTRACT-008). |
| Fortra_Renewal_Contract_Succession | After Save (Create+Update) | Active | On renewal Order activation, marks original Contract Renewal_Status = Accepted. |
| Fortra_Contract_Renewal_Window_Monitor | **Scheduled** (2:00 AM daily) | Active | Daily: flags Contracts entering 120-day renewal window as Renewal_Status = Pending. |

---

## Places (`Places__c`)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Locations_Enforce_Single_Primary_Address | After Save (Create+Update) | Active | Enforces single primary address per Account. |
| Fortra_Locations_Generate_Composite_Address_Key | Before Save (Create+Update) | Active | Generates composite address key for dedupe/matching. |
| Fortra_Locations_Deactivate_Expired_Locations | **Scheduled** | Active | Deactivates expired locations. |
| Fortra_Places_Platform_Event_Geocoding_Trigger | PlatformEvent-triggered | **Draft** | Geocoding trigger via platform event. |
| Fortra_Places_Validation | Autolaunched | **InvalidDraft** | Places validation (dead). |
| Places_After_Insert_Update_Platform_Events | After Save (Create+Update) on `Account_Updated_WD__e` | **Obsolete** | Published Workday account-updated event from Places. |
| Places_Before_Delete_Platform_Events | Before Delete on `Account_Updated_WD__e` | **Obsolete** | Published Workday event on Place delete. |

---

## Product / Pricebook / Pricing

Includes the **multi-currency PBE generation** family and the **Maintenance Derived Pricing stamping** flows that feed the gated RCA pricing procedure (COLA / SC-3350).

### Maintenance Derived Pricing stamping (record-triggered, before save)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Stamp_Maintenance_Pricing_Inputs | Before Save (Create+Update) on `COLA_Uplift_Rules__mdt` | Active | **Load-bearing, fragile**: stamps Base_Price__c, partner/discretionary $, and resolved COLA rate for the gated procedure (FORTRA-PRODUCT-018). **RENEWAL branch is UNTESTED**; prior-OrderItem lookup is not account/asset-scoped. |
| Stamp_Source_List_Price | Before Save (Create+Update) on `PriceBookEntryDerivedPrice` | Active | Stamps non-derived contributing-license list price into Source_List_Price__c for derived maintenance lines (multi-contributor → left null). |

### Multi-currency pricebook generation

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Bulk_Price_Update_Flow | Screen Flow (Pricebook2) | Active | Bulk multi-currency price update across products by Solution Category; launches batch. |
| Fortra_Product_Update_Multi_Currency_Prices | Screen Flow (PricebookEntry) | Active | Quick-action multi-currency PBE update; creates Standard entries first. |
| Fortra_Product_Create_Multi_Currency_PBE | Autolaunched subflow on `Currency_Conversion_Formula__mdt` | Active | Creates multi-currency PBEs from currency-conversion CMDT. |
| Fortra_Product_Update_Currency_Prices_SubFlow | Autolaunched subflow on `Currency_Conversion_Formula__mdt` | Active | Updates/creates multi-currency PBEs via Apex invocable. |
| Create_New_Product | Screen Flow (Pricebook2) | Active | Create-product screen (multi-currency selection removed). |
| Fortra_Product_Populate_Product_Hierarchy_Fields | **Scheduled** on ProductCategory | **Draft** | Populates product hierarchy fields. |

### Product configurator / catalog screens

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Product_Configurator_Flow | Screen Flow | Active | Product configurator UI. |
| Add_Product_of_Interest | Screen Flow (Marketing_Product__c) | Active | Adds Product of Interest (record-type check). |

---

## Hardware (`Hardware__c`)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Hardware_Hardware_Management_Orchestrator | Screen Flow (Account) | Active | Top-level hardware management orchestrator. |
| Fortra_Hardware_Hardware_Creation_Subflow | Autolaunched subflow | Active | Creates hardware records (cross-platform values). |
| Fortra_Hardware_Hardware_Search_Selection_Subflow | Autolaunched subflow | Active | Hardware search + auto-select-single. |
| Fortra_Hardware_Hardware_Status_Management_Subflow | Autolaunched subflow | Active | Hardware status transitions (decommission handling). |
| Hardware_Selection_Screen | Screen Flow | Active | Displays hardware records for selection. |

---

## Certinia PSA (`pse__` / `ffscpq__` / FFX)

Professional Services Automation automation. The `Fortra_FFX_*` flows are the team's re-cloned/active versions of the older `FFX_PSA_*` flows (several originals are Draft/Obsolete).

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Certinia_Auto_Populate_Project_from_Milestone | Before Save (Create) on `pse__Project_Task__c` | Active | Auto-populates Project from Milestone. |
| Certinia_PSA_Project_Milestone_Check | After Save (Update) on `pse__Milestone__c` | Active | Checks for open milestones. |
| Certinia_PSA_Project_Stage_Update | After Save (Create+Update) on `pse__Proj__c` | Active | Updates project stage. |
| Fortra_FFX_PSA_Budget | After Save (Create+Update) on `pse__Budget__c` | Active | Defaults PSA Budget name/status on Customer PO create. |
| Fortra_FFX_PSA_Milestone | After Save (Create+Update) on `pse__Milestone__c` | Active | Defaults on Milestone when Actual Date populated. |
| Fortra_FFX_PSA_Resource_Requests | After Save (Create+Update) on `pse__Resource_Request__c` | Active | Resource-request automation. |
| Fortra_FFX_PSA_Assignment | After Save (Create+Update) on `pse__Assignment__c` | **Obsolete** | Captured PM email; superseded. |
| FFX_PSA_Assignment | After Save (Create+Update) on `pse__Assignment__c` | **Draft** | New-assignment email alert. |
| FFX_PSA_Budget | After Save (Create+Update) on `pse__Budget__c` | **Draft** | Original budget defaulting. |
| FFX_PSA_Milestone | After Save (Create+Update) on `pse__Milestone__c` | **Draft** | Original milestone updates. |
| FFX_PSA_Miscellaneous_Adjustment | After Save (Create+Update) on `pse__Miscellaneous_Adjustment__c` | Active | Updates billing/IIF fields on Misc Adj status change. |
| FFX_PSA_Missing_Timecard | After Save (Create+Update) on `pse__Missing_Timecard__c` | **Draft** | Missing-timecard email to resource. |
| FFX_PSA_Project | After Save (Create+Update) on `pse__Proj__c` | Active | Closes project for time/expense entry. |
| FFX_PSA_Project_Reactivation_from_Closure | After Save (Update) on `pse__Proj__c` | Active | Re-opens project records when stage reactivated. |
| FFX_PSA_Resource_Requests | After Save (Create+Update) on `pse__Resource_Request__c` | **Draft** | Original resource-request flow. |
| FFX_PSA_Rev_Forecast_Set_Deliverable_Recognition_Method_on_Expenses | After Save (Create) on `pse__Expense__c` | **Draft** | Sets Deliverable recognition method on expenses. |
| FFX_PSA_Rev_Forecast_Set_Deliverable_Recognition_Method_on_Timecard_Splits | After Save (Create) on `pse__Timecard__c` | **Draft** | Sets Deliverable recognition method on timecard splits. |
| FFX_PSA_Submit_Skill_Cert_Rating_for_Approval | After Save (Create+Update) on `pse__Skill_Certification_Rating__c` | Active | Auto-submits skill/cert rating for approval. |
| FFX_PSA_Timecard_Split | After Save (Create+Update) on `pse__Timecard__c` | Active | Excludes $0 timecard splits from billing. |
| FFX_PSA_Timecard_Submitted | Before Save (Create+Update) on `pse__Timecard_Header__c` | Active | Sets Submitted flag to push timecard to approval. |
| Fortra_Billing_Event_Item_Set_WD_Status_Pending | After Save (Create+Update) on `pse__Billing_Event_Item__c` | **Draft** | Sets BEI WD Sync Status = Pending to fire Workday event. |
| PSA_RTF_APC | After Save (Update) on `ffscpq__Estimate_Product_Instance__c` | Active | Adds estimate products to Project (branch PSA). |
| Push_Estimate_to_Quote | Screen Flow (`ffscpq__Estimate_Product_Instance__c`) | **InvalidDraft** | Would push estimate to related Quote (dead). |
| Certinia_Auto_Populate_Project_from_Milestone | (listed above) | Active | — |

---

## User / Partner Portal / Domain (`Domain__c`)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_User_After_Insert_Update_Partner_Users | After Save (Create+Update) on `Domain__c` | Active | Grants Fortra Academy access to approved partner contacts. |
| Fortra_User_After_Insert_Process_Partner_Users | After Save (Create) on `Domain__c` | **Draft** | Sends pending-approval email for partner users. |
| Fortra_Screen_Flow_Partner_Portal_Login | Screen Flow | Active | Partner portal login / approval gate. |
| Screen_Flow_Partner_Portal_Deal_Registration_Form | Screen Flow (Marketing_Product__c) | Active | Partner portal deal-registration with DUNS callout. |
| Partner_Solution_Categories_Manager | Screen Flow | Active | Manages partner solution categories. |

---

## Account / Opportunity Team & Splits (subflows)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Subflow_Opportunity_Team_Member_Assignment | Autolaunched subflow (Marketing_Product__c) | Active | Finds OTM (system-context with sharing). |
| Subflow_Opp_Team_to_Opp_Split | Autolaunched subflow (OpportunitySplit) | Active | Builds Opportunity Splits from team members. |
| Screen_Flow_Bulk_Update_Account_Team | Screen Flow | Active | Bulk account-team update. |
| Screen_Flow_Update_Account_Team | Screen Flow (AccountTeamMember) | Active | Single account-team update. |

---

## Marketing / MDF

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Marketing_Fund_Request_MDF_Request_Submission_Flow | Screen Flow (`Marketing_Fund_Request__c`) | Active | MDF request submission with approval. |
| Fortra_Marketing_Fund_Request_MDF_Request_Submission_Flow_Internal | Screen Flow | Active | Internal MDF submission wrapper (lives on Contact page). |

---

## Export License (`Export_License_Document__c`)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Expire_Export_License_After_End_Date | After Save (Create+Update) | **Draft** | Sets status Expired when End Date in the past. |
| Send_Export_License_Notification_Email | **Scheduled** | **Draft** | Sends expiring-export-license email. |

---

## Sales Territory

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Sales_Territories_Before_Insert_Update | Before Save (Create+Update) on `Sales_Territory__c` | Active | Sets unique value on Sales Territory. |

---

## Temperature History (`Account_Temperature_History__c`)

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Fortra_Account_Account_Temperature_History_After_Save | After Save (Update) | Active | Captures Account Temperature change into history record. |
| Account_Account_Temperature_History_After_Save | After Save (Update) | **Obsolete** | Older temperature-history flow (superseded by Fortra_ version). |

---

## UAT / Test Management

A self-contained test-management subsystem on `Test_Cases__c` / `Test_Case_Issues__c`.

| Flow | Type/Trigger | Status | Purpose |
|---|---|---|---|
| Field_Updates_on_Test_Cases | Before Save (Create+Update) on `Test_Cases__c` | Active | Field updates on Test Cases. |
| Test_Case_Issue_On_Edit_After_Save | After Save (Update) on `Test_Cases__c` | Active | Chatter "ready for retest" on edit. |
| UAT_Test_Case_Identifier | After Save (Create) on `Test_Cases__c` | **Draft** | Assigns test-case identifier. |
| Test_Case_Issue_After_Save | After Save (Create) on `Test_Case_Issues__c` | **Obsolete** | Set severity on issue create; superseded. |
| UAT_Post_Notification_of_newly_assigned_TCI_Resolver | After Save (Update) on `Test_Case_Issues__c` | Active | Chatter alert to new TCI resolver. |
| UAT_close_all_duplicate_TC_Issues | After Save (Update) on `Test_Case_Issues__c` | Active | Closes duplicate TC issues / posts for retest. |
| UAT_Log_Test_Results_Pass_Fail_Enhancement | Screen Flow (`Test_Case_Issues__c`) | Active | Logs pass/fail results with Chatter feedback. |
| UAT_Assign_Test_Case_to_Tester | Screen Flow | Active | Assigns test case to tester + notifies. |
| UAT_Delete_TestCase_Records | Screen Flow | Active | Bulk-deletes test-case records. |
| Mass_Assign_Master_Test_Cases_to_User_s | Screen Flow | Active | Mass-assigns master test cases; Chatter notify. |

---

## Gearset Clone-Support Flows (RCA setup objects)

26 auto-generated **before-save / Create**, all **Active**, all trivial no-ops that exist purely to enable Gearset clone of these platform/setup objects. Listed compactly; not business logic.

| Flow | Object |
|---|---|
| GearsetCloneSupportFlowAccountingPeriod | AccountingPeriod |
| GearsetCloneSupportFlowAttributeBasedAdjRule | AttributeBasedAdjRule |
| GearsetCloneSupportFlowAttributeCategory | AttributeCategory |
| GearsetCloneSupportFlowAttributeCategoryAttribute | AttributeCategoryAttribute |
| GearsetCloneSupportFlowAttributeDefinition | AttributeDefinition |
| GearsetCloneSupportFlowAttributePicklist | AttributePicklist |
| GearsetCloneSupportFlowAttributePicklistValue | AttributePicklistValue |
| GearsetCloneSupportFlowBillingPolicy | BillingPolicy |
| GearsetCloneSupportFlowBillingTreatment | BillingTreatment |
| GearsetCloneSupportFlowBillingTreatmentItem | BillingTreatmentItem |
| GearsetCloneSupportFlowCostBook | CostBook |
| GearsetCloneSupportFlowLegalEntity | LegalEntity |
| GearsetCloneSupportFlowLegalEntyAccountingPeriod | LegalEntyAccountingPeriod |
| GearsetCloneSupportFlowPaymentTermItem | PaymentTermItem |
| GearsetCloneSupportFlowPricingAdjBatchJob | PricingAdjBatchJob |
| GearsetCloneSupportFlowPricingAdjBatchJobLog | PricingAdjBatchJobLog |
| GearsetCloneSupportFlowProduct2 | Product2 |
| GearsetCloneSupportFlowProductAttributeDefinition | ProductAttributeDefinition |
| GearsetCloneSupportFlowProductConfigurationFlow | ProductConfigurationFlow |
| GearsetCloneSupportFlowProductUsageResourcePolicy | ProductUsageResourcePolicy |
| GearsetCloneSupportFlowUnitOfMeasure | UnitOfMeasure |
| GearsetCloneSupportFlowUnitOfMeasureClass | UnitOfMeasureClass |
| GearsetCloneSupportFlowUsageCommitmentPolicy | UsageCommitmentPolicy |
| GearsetCloneSupportFlowUsageOveragePolicy | UsageOveragePolicy |
| GearsetCloneSupportFlowUsageResourceBillingPolicy | UsageResourceBillingPolicy |
| GearsetCloneSupportFlowUsageResourcePolicy | UsageResourcePolicy |

---

## Surveys & Platform / Security

| Flow | Type | Status | Purpose |
|---|---|---|---|
| customer_satisfaction | Survey | Active | Customer satisfaction survey. |
| net_promoter_score | Survey | Active | NPS survey. |
| discovery_call_assessment | Survey | Active | Discovery-call assessment survey. |
| test | Survey | **Draft** | Test survey (scratch). |
| sfdc_default_ReportExport_Protection_Flow | TransactionSecurityFlow | **Draft** | Default ReportEvent transaction-security policy condition builder. |

---

## Notes & Gotchas

- **Status counts**: roughly 175 Active, plus a long tail of Draft / Obsolete / InvalidDraft. Always confirm a flow is Active before assuming it runs — many obvious-looking flows (e.g. `Fortra_Order_Reprice`, `Fortra_Order_After_Save_Set_Workday_Contract_Line_Type`, `Fortra_Opportunity_Change_Legal_Entity`) are Obsolete and replaced by a sibling.
- **InvalidDraft** flows (`Delete_Related_QLI_upon_deletion_of_EPI`, `Fortra_Order_Assetize_Order`, `Fortra_Places_Validation`, `Push_Estimate_to_Quote`) cannot be activated as-is — treat as dead.
- **Duplicate/superseded pairs to watch**: `Fortra_Account_Account_Temperature_History_After_Save` (Active) vs `Account_Account_Temperature_History_After_Save` (Obsolete); `Fortra_Order_After_Update_Platform_Event_Workday` (Active) vs `Order_After_Update_Platform_Events` (Draft); the `Fortra_FFX_PSA_*` (Active) vs `FFX_PSA_*` (Draft) families; the Quote reprice test flows.
- **Pricing risk cluster** (SC-3350 / COLA): `Stamp_Maintenance_Pricing_Inputs` (renewal branch untested), `Stamp_Source_List_Price`, `Fortra_Quote_Reprice`, `Fortra_Migration_Price_Quote`. Treat as the most fragile automation in the org.
- **Object as listed = the flow's `<object>` element**, which for many record-triggered flows is the *triggering* object even when the business intent targets a related record (e.g. several Order/Quote address-sync flows trigger on `Places__c`; renewal-quote flows trigger on `Opportunity`). Read descriptions for true intent.
- **`Fortra_` prefix** reliably marks team-authored, business-critical automation; unprefixed flows are older or third-party-cloned (Gearset, Certinia, survey, platform defaults).
