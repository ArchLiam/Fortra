# 06 - Platform Events (`__e`)

## Overview

The Fortra org uses **15 custom Platform Events** as the asynchronous, decoupled
integration backbone between Salesforce and three external systems: **Workday**
(`*_WD__e`, finance/ERP), **HubSpot** (`*_HS__e`, marketing/CRM sync), and **MuleSoft**
(`*_Mulesoft__e`, the integration middleware that brokers most of these). Two events
(`Geocoding_Request__e`, `Quote_Line_Update__e`) are purely **intra-org** signals.

The dominant pattern is **publish-in-org, consume-out-of-org**: a record-triggered
Flow (or, in 3 cases, an Apex class) creates the event via `EventBus.publish` /
Flow `recordCreates`, and an **external CometD / Streaming-API subscriber** owned by
MuleSoft/Workday/HubSpot listens. Only **one** event (`Geocoding_Request__e`) has an
in-org subscriber Flow. Most event payloads are intentionally **thin** — usually just a
record Id — because the external subscriber re-queries Salesforce for live data rather
than trusting the event payload (the event is a *trigger/log*, not a data carrier).

> **Load-bearing re-submit mechanism:** publishing `Order_Completed_WD__e` with an
> `Order_Id__c` re-sends that Order to Workday **headlessly** — see the dedicated note below.

---

## Event Catalog

| Event | Fields | Published by | Consumed by | Purpose |
|---|---|---|---|---|
| **Order_Completed_WD__e** | `Order_Id__c` (Text 18) | Flow `Order_After_Update_Platform_Events` (on Order, when Order completed + WD status = Success); Flow `Fortra_Subflow_Order_Completed_Platform_Event` (autolaunched, **re-submit subflow**) | **MuleSoft → Workday** (external CometD subscriber); no in-org consumer | Signals an Order is finalized and ready to push to Workday for contract/billing creation. The canonical Workday hand-off + manual re-submit hook. |
| **Order_Completed_Legacy__e** | `Order_Id__c` (Text 18) | Flow `Order_After_Update_Platform_Events`; Flow `Fortra_Order_After_Update_Platform_Event_Workday` | External (legacy MuleSoft/Workday subscriber) | Legacy variant of the Order-completed signal kept for the older integration path; published alongside `Order_Completed_WD__e`. |
| **Invoice_PO_Updated_WD__e** | `Contract_Id__c`, `Invoice_Id__c`, `WorkDay_Order_Id__c` (Text 18/255), `PO_URL__c` (Text 255) | Flow `Order_After_Update_Platform_Events` (when **PO URL changed**); Flow `Fortra_Order_After_Update_Platform_Event_Workday` | **Workday / MuleSoft** (external) | Notifies Workday that a PO URL / invoice reference on an Order has changed so it can update the matching contract/invoice. |
| **Billing_Event_Item_Released_WD__e** | `Billing_Event_Item_ID__c` (Text 20), `Contract_Line_Reference__c` (Text 100), `Currency_Reference__c` (Text 100), `Quantity__c`, `Rate__c` (Number), `Transaction_Date__c` (DateTime), `Unit_of_Measure_Reference__c` (Text 50), `Submit_for_Review__c` (Checkbox) | **Apex** `FortraBillingEventItemTriggerHandler.handleAfterInsertOrUpdate` (on `pse__Billing_Event_Item__c`) | **Workday** (external billing intake) | Pushes a *released* PSA billing event item to Workday for invoicing. The only **fat-payload** WD event — carries full transaction detail (qty/rate/UoM/date) because it maps a PSA record Workday cannot re-query. |
| **Account_Created_WD__e** | `Account_Id__c` (Text 18) | *(no in-org publisher found — external/outbound only)* | Workday (external) | Reserved/external-driven signal for a new Account to provision in Workday. No in-org Flow/Apex references it — likely published by an outbound integration or pending wiring. |
| **Account_Updated_WD__e** | `Account_Id__c` (Text 18) | Flows `Places_After_Insert_Update_Platform_Events` & `Places_Before_Delete_Platform_Events` (on `Places__c`) | Workday (external) | Account-change signal to Workday. Notably published from **Places__c** address-change Flows (insert/update/before-delete), i.e. a billing/ship address change on a Place propagates an Account update to Workday. |
| **Contact_Created_WD__e** | `Contact_Id__c` (Text 18) | *(no in-org publisher found — external/outbound only)* | Workday (external) | Reserved/external-driven new-Contact provisioning signal for Workday. |
| **Contact_Updated_WD__e** | `Contact_Id__c` (Text 18) | *(no in-org publisher found — external/outbound only)* | Workday (external) | Reserved/external-driven Contact-change signal for Workday. |
| **Account_Upsert_HS__e** | `Account_Id__c` (Text 18) | Flow `Account_After_Insert_Update_Platform_Events` (on **Account**, Create+Update, after-save) | **HubSpot** (external sync subscriber) | Mirrors Account create/update into HubSpot. |
| **Contact_Upsert_HS__e** | `Contact_Id__c` (Text 18) | Flow `Contact_After_Insert_Update_Platform_Events` (on **Contact**, Create+Update, after-save) | **HubSpot** (external) | Mirrors Contact create/update into HubSpot. |
| **Opportunity_Upsert_HS__e** | `Opportunity_Id__c` (Text 18) | Flow `Opportunity_After_Insert_Update_Platform_Events` (on **Opportunity**, Create+Update, after-save) | **HubSpot** (external) | Mirrors Opportunity create/update into HubSpot. |
| **Lead_Upsert_Mulesoft__e** | `Lead_Id__c` (Text 18) | Flow `Inquiry_After_Insert_Update_Platform_Events` (on **Lead**, Create+Update, after-save) | **MuleSoft** (external) | Pushes Lead (a.k.a. "Inquiry") create/update to MuleSoft for downstream routing. (Lead is labeled "Inquiry" in this org.) |
| **License_Key_Email_Event__e** | `Account_Id__c`, `License_Key_Id__c` (Text 18), `License_Key_Name__c` (Text 255), `Email_Status__c` (Text 50), `Last_Email_Date__c` (DateTime), `Error_Message__c` (LongText 32768) | **Apex** `LicenseKeyNotificationPublisher.publishEmailNotifications(List<License_Key__c>)` | External email/notification integration (no in-org subscriber) | Notifies an external system of license-key email delivery status (sent/failed + error detail) so a license key can be (re)emailed to the customer. |
| **Quote_Line_Update__e** | `Quote_Id__c` (Text 18), `Update_Type__c` (Text 50), `Lines_Updated__c` (Number) | **Apex** `FlexPanelBulkUpdateController.bulkUpdateDates` (`Update_Type__c = 'BULK_DATE_UPDATE'`) | **Intra-org UI** (LWC/FlexCard refresh; no Flow/Apex subscriber) | Signals that N quote lines were bulk-updated (e.g. dates) so the FlexPanel/Quote UI can refresh after the async bulk edit. |
| **Geocoding_Request__e** | `Location_ID__c` (Text 18), `Priority__c` (Text 10) | *(no explicit in-org publisher found — expected from Places__c automation / external geocoder request)* | **In-org Flow** `Fortra_Places_Platform_Event_Geocoding_Trigger` (`triggerType = PlatformEvent`) → reads `Places__c`, geocodes | Asynchronous geocoding queue: decouples the (rate-limited) geocode callout for a Place from the triggering DML. The **only event with an in-org subscriber Flow.** |

---

## Patterns & Notes

### Publishers
- **Record-triggered Flows** are the primary publishers (HubSpot, Mulesoft, and most
  Workday events). They follow the naming convention
  `<Object>_After_Insert_Update_Platform_Events` and use a Flow `recordCreates` element
  on the `__e` object. The Account/Contact/Opportunity/Lead "Upsert" Flows are after-save,
  Create+Update triggered.
- **Apex publishers** (3): `FortraBillingEventItemTriggerHandler` (Billing item → WD),
  `LicenseKeyNotificationPublisher` (license email status), and
  `FlexPanelBulkUpdateController` (quote-line bulk-update UI signal). All use
  `EventBus.publish(...)` and check `Database.SaveResult`.
- `Account_Updated_WD__e` is published from **`Places__c`** Flows (insert/update and
  before-delete) — non-obvious: a Place (address) change is what triggers the Account-to-Workday update.

### Consumers
- **External subscribers dominate.** All `*_WD__e` (except the in-org re-submit publisher),
  all `*_HS__e`, and `Lead_Upsert_Mulesoft__e` are consumed by **MuleSoft / Workday / HubSpot
  via CometD/Streaming API** — there is **no in-org trigger or Flow** subscribing to them.
  Do not expect to find the consumer in this repo.
- **`Geocoding_Request__e` is the lone in-org subscriber** (Flow with
  `triggerType=PlatformEvent` → `Fortra_Places_Platform_Event_Geocoding_Trigger`).
- `License_Key_Email_Event__e` and `Quote_Line_Update__e` are published but have **no
  in-org consumer** (external email integration and client-side UI refresh respectively).

### Thin vs. fat payloads
- Most events carry **only a record Id** by design: the external subscriber re-queries
  Salesforce for **live** data, so the event is a trigger/log, not a snapshot. The stored
  middleware payload is just a log.
- The exception is **`Billing_Event_Item_Released_WD__e`**, which carries full transaction
  detail (qty, rate, UoM, currency, dates) because it represents a PSA billing item the
  external system maps directly.

### Load-bearing / non-obvious
- **`Order_Completed_WD__e` re-submit mechanism (verified):** publishing this event with
  `Order_Id__c = <OrderId>` re-sends that Order to Workday **headlessly** — no UI action
  needed. The autolaunched Flow **`Fortra_Subflow_Order_Completed_Platform_Event`** exists
  specifically to (re)publish the event when an Order Id is provided. MuleSoft middleware
  reads **LIVE** Order data when it receives the event (the previously stored payload is only
  a log), and the upsert is **idempotent by Order Id**. This is the standard way to retry a
  failed Workday Order sync (see SC-3347 / SC-3143 work).
- **`Order_Completed_Legacy__e`** is published in lock-step with `Order_Completed_WD__e`
  for a legacy integration path — don't assume it's dead; both fire from the same Flow.
- **`Account_Created_WD__e`, `Contact_Created_WD__e`, `Contact_Updated_WD__e`** have **no
  in-org publisher or subscriber** in this source. They are defined for outbound/external
  use (or are reserved/incompletely wired) — flag before assuming they fire from Salesforce.
