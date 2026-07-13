# SC-3505 / SC-3516 — Live-Org Evidence Bundle (FortraUAT, read-only)

**Date:** 2026-07-11 · **Reviewer:** Liam Jeong · **Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`, API 67) · All queries read-only.

Purpose: ground-truth for the SC-3505 root-cause confirmation + SF-side design. Everything below was pulled live today.

---

## 1. Root-cause facts (verified live)

### 1.1 "Workday Contract ID" = the SF Order.Id, stamped for ALL orders, no amendment branch
Flow `Fortra_Order_Workday_Contract_ID` (Tooling): **V3 Active, ProcessType AutoLaunchedFlow, ApiVersion 66, LastModified 2026-04-27 by Ben Kozlowski.** V1 Draft + V2 Obsolete also present.
Flow body (`force-app/main/default/flows/Fortra_Order_Workday_Contract_ID.flow-meta.xml`): RecordAfterSave on Order, CreateAndUpdate, entry filter `Workday_Contract_ID__c = '' OR IsNull` (blank-guard), single `recordUpdates` `Set_ID` → `Workday_Contract_ID__c = $Record.Id`. **No decision, no OriginalActionType branch.** Every order mints its own key.

### 1.2 Outbound = platform event carrying only the Order Id; MuleSoft builds the payload
`Fortra_Subflow_Order_Completed_Platform_Event.flow-meta.xml`: publishes `Order_Completed_WD__e` with a single field `Order_Id__c = orderId`. No contract reference emitted from SF. MuleSoft queries the Order and constructs `Submit_Customer_Contract`.

### 1.3 Both synced amendment payloads echo own-Id + Master_Contract (no original reference)
`evidence/payload_amend_00095512.json`: `sfContractId = orderId = fortraSfdcExternalId = contractReferenceId = 801WC00000koIE3YAM` (the amend order's OWN Id), `customerContractType = Master_Contract`. No original/prior/parent/source key of any name.

### 1.4 No original-reference field exists anywhere in source control
`grep -rInE "Original_Customer_Contract|Original_Workday_Contract|Alternate_Contract" force-app` = **0 hits.**
`objects/Order/fields/` and `objects/Contract/fields/` contain **no** Workday/original/source/amend field files.
`Order.Workday_Contract_ID__c` exists in the org (queried) but has **no field metadata in force-app** → source-control drift. Only reference to the field name in the repo is inside the flow XML.

---

## 2. Live lineage anchors — what is populated vs empty (the crux)

All 8 `Order.OriginalActionType='Amend'` orders in FortraUAT:

| Amend Order | Own Id (=WCID) | Sync | OriginalOrderId | Source_Order_Id__c | PricingContractId | ContractId | Quote_Type__c | Quote.Original_Order_Id__c (→ #) | Quote.Renewal_Contract__c |
|---|---|---|---|---|---|---|---|---|---|
| 00000656 | eL6A9 | Pending | NULL | NULL | NULL | OVQmp | Amendment | eLglE (00000655) | OVQmp |
| 00095512 | koIE3 | **Success** | NULL | NULL | NULL | SLdXh | Amendment | koHXq (00095510, a Renew) | SLdXh |
| 00095531 | ksL59 | Pending | NULL | NULL | NULL | SOGWY | **null** | **NULL** | SOPMv (≠ContractId) |
| 00095635 | lqWKG | Pending | NULL | NULL | NULL | Sw6WL | Amendment | **NULL** | Sw6WL (own) |
| 00095642 | ltUiu | **Success** | NULL | NULL | NULL | Sy3Sp | Amendment | ltV8V (00095639) | Sy3Sp |
| 00095676 | mA6Tc | Pending | NULL | NULL | NULL | T5Usn | **null** | **NULL** | **NULL** |
| 00095693 | mUTgv | Pending | NULL | NULL | NULL | TIVXk | Amendment | mU185 (00095692) | TIVXk |
| 00095724 | mksBU | Pending | NULL | NULL | NULL | TTQ3F | Amendment | mjxwv (00095723) | TTQ3F |

**Native RLM anchors that are EMPTY / self-referential on live data (so a fix cannot rely on them):**
- `Order.OriginalOrderId` = NULL on all 8.
- `Order.Source_Order_Id__c` = NULL on all 8.
- `Order.PricingContractId` = NULL on all 8.
- `Contract.SourceOrderId` = NULL or **the amend order itself** (clobbered to latest by `Fortra_Contract_Populate_From_Order`) — never the original.
- `Contract.AmendedContractId`, `Contract.ParentContractId`, `Contract.Original_Contract__c` = NULL on all amend contracts.
- `Contract` has **no** Workday_Contract_ID__c field at all.

**The only usable links:** `Order.QuoteId` (native, populated) → `Quote.Original_Order_Id__c` and `Quote.Renewal_Contract__c` ("Source Contract").

### Resolution matrix (which amendments can be resolved to an original order, and how)
- **Via `Quote.Original_Order_Id__c` (5/8):** 00000656→eLglE, 00095512→koHXq, 00095642→ltV8V, 00095693→mU185, 00095724→mjxwv. (For these, the original order is also the non-Amend sibling sharing the same ContractId — the two methods agree.)
- **Via `Quote.Renewal_Contract__c`→non-amend order (1/8):** 00095531 → source contract SOPMv (00069312) whose original order is 00095530 (ksZvx). ⚠️ 00095530 is itself `Workday_Sync_Status__c=Pending` — never synced to Workday.
- **Genuinely UNRESOLVABLE in SF (2/8):** 00095635 (Quote.Original_Order_Id__c NULL, Renewal_Contract__c=own amend-only contract Sw6WL, no predecessor order) and 00095676 (Quote_Type__c null, Original_Order_Id__c NULL, Renewal_Contract__c NULL, ContractId T5Usn amend-only). No SF field anywhere links these to an original order.

**Contract sharing pattern (confirms the premise correction):** for the 5 "clean" amendments the amend order REUSES the source order's Contract (e.g. amend 00095512 shares Contract SLdXh with renewal 00095510). Amendments do NOT create a new contract on the native path. The exception 00095531 sourced from SOPMv but landed on a new contract SOGWY.

---

## 3. Workday API capability (from repo API ref, v46.1)
`Jira/Story/sc3143(epic | integration)/workday-api-reference/Submit_Customer_Contract.md` — `Customer_Contract_Data` defines:
- **`Original_Customer_Contract_Reference`** [0..1] `Customer_ContractObject` — "Original Customer Contract. The Customer Contract used as source for this Alternate Customer Contract." ✅ exists.
- **`Alternate_Customer_Contract_Reference`** [0..1] `Customer_Contract_AlternateObject`. ✅ exists.
- `Related_Customer_Contract_Reference` [0..1] — informational only (must share company + sold-to customer).
- `Master_Customer_Contract_Reference` [0..1] — for Linked contracts only.
- Validation strings confirm the amendment model: *"Cannot create Alternate Contract if Original Contract is in Draft status"*, *"Alternate Customer Contract Number must match Original Customer Contract Number if supplied"*, *"You cannot submit an Incremental Contract Amendment for a Draft Contract Amendment."*

So the Workday **API schema** supports an original-contract reference + alternate type. Whether Fortra's Workday **tenant** is configured to accept/process them, and whether MuleSoft's DataWeave maps them, is NOT verifiable from Salesforce.

Live `Order.Workday_Contract_Type__c` picklist = only value `Master_Contract` (no Alternate/Amendment value).

---

## 4. Compliance-relevant environment facts
- Order already has exactly **one** trigger in source control: `OrderValidationTrigger` (apex-compliance §2 → any new Order Apex must route through its handler, not a new trigger). `AssetArrFromOrderItemTrigger` is on OrderItem.
- Flow V3 is API 66 (flow-compliance §1.2 wants latest = 67); stray Draft V1 + Obsolete V2 (§1.6 cleanup).
- This is an Order→Workday **outbound integration** concern, NOT a pricing-procedure concern — it does not touch the V25 pricing procedure.
