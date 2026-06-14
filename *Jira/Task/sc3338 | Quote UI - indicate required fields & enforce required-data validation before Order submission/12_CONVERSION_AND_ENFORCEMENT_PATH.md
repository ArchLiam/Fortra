
# SC-3338 — Dimension C: Quote → Order Conversion + Enforcement Path Walkthrough

**Acceptance Criterion #4 (part 1):** confirm *where* validation fires, whether it is bypassable, and where SC-3338 should move the rep's first signal of missing data.

**Scope of this doc:** the end-to-end mechanical path a rep travels — Quote → (Convert) → Order → (Update Status) → Order Complete → Workday — and exactly which automation enforces what, at which step. All claims verified live against `FortraUAT` 2026-06-12 and cited to source.

---

## 0. Executive answer (the crux)

There are **two distinct enforcement gates**, both screen-flow based, both launched by a manual quick action, and **both bypassable by a direct DML/inline edit**:

| Gate | Launch | Screen flow | What it checks | First-class blocker? |
|---|---|---|---|---|
| **Conversion gate** | Quote quick action **"Convert Quote to Order"** | `Fortra_Quote_to_Order_Conversion` v27 (Active) | A *subset*: Bill To Contact, Bill To Place, Billing Street, Ship To Place, Quote Status=Accepted, pricing complete, IsSyncing, no existing order, contract start date, Operations Checklist complete | Yes — clear per-field error screens, but **does not** require the Account/Contact/Workday-field set |
| **Order-Complete gate** | Order quick action **"Update Status"** (`Order.Order_Complete`) | `Fortra_Order_Submission_Check` v13 (Active) | The full `Order_Submit_Validation__mdt` active set (Account, Contact Workday-phone, Order Workday IDs, OrderItem line-type/tax, plus an inline Bill/Ship presence gate) | Yes — `Validation_Error_Screen` lists each blank field with a record link |

**Neither gate is a record-triggered/validation backstop.** Live UAT has **no Order validation rule and no Order trigger that enforces the required-field set on `Status → Order Complete`**. The only Order trigger (`OrderValidationTrigger`) is `before insert` (account-equality only); the 7 active Order VRs are currency-lock / account-equality rules, none keyed to `Status='Order Complete'`. So **anyone who sets `Order.Status='Order Complete'` by inline edit, Data Loader, or API skips both screen flows entirely** — and that same Status change fires the Workday platform event. This is the "silent blocker" gap SC-3338 must close, *and* it is why the screen-flow validation alone is not a true guarantee.

---

## 1. How a Quote becomes an Order (the conversion entry point)

### 1.1 The rep's path: a Quote quick action → a screen flow → standard RLM `createOrderFromQuote`

This is an **RLM (Revenue Lifecycle Management) org** and conversion uses the **standard `createOrderFromQuote` invocable** wrapped in a custom screen flow — **not** a custom Apex button or a raw `placeQuote`.

- **Primary entry point:** Quote quick action **`Quote.Convert_Quote_to_Order`**, label **"Convert Quote to Order"**, `type=Flow`, launching `Fortra_Quote_to_Order_Conversion`.
  - Source: `Data/sc3338/retrieve/conv_q2o/unpackaged/quickActions/Quote.Convert_Quote_to_Order.quickAction` (`<flowDefinition>Fortra_Quote_to_Order_Conversion</flowDefinition>`, `<type>Flow</type>`).
  - Live quick-action inventory on Quote (`QuickActionDefinition`): `Change_Currency`, **`Convert_Quote_to_Order`**, `Generate_Document`, `Import_Quote_Line`, `SendEmail`, `Submit_Approval`.
- **The conversion flow:** `Fortra_Quote_to_Order_Conversion` — **v27 Active, ProcessType=Flow (screen flow)**, apiVersion 62.0, 2454 lines. Source: `Data/sc3338/retrieve/conv_q2oflow/unpackaged/flows/Fortra_Quote_to_Order_Conversion.flow`.
  - Calls the **standard Revenue Cloud invocable** `createOrderFromQuote` (action `Call_Create_Order_From_Quote`, `actionType=createOrderFromQuote`) — 7 references in the flow. Flow self-description: *"Converts a Quote to an Order using the standard Revenue Cloud createOrderFromQuote invocable action, enabling the Context Mapping Engine for field mapping."*
  - It also lets the rep **select or create a Contract**, choose Order/Contract activation modes, and routes queues; on a new Contract it creates an `AppUsageAssignment (AppUsageType=RevenueLifecycleManagement)` to enable `AssetContractRelationship` on activation.

### 1.2 What data carries over (and the known Bill-To bug)

The standard `createOrderFromQuote` does **not** map custom lookup fields, so the flow bridges that with custom Apex **`QuoteToOrderFieldMapper`** (invocable `MapQuoteLineFieldsToOrderItems`), invoked **between** `createOrderFromQuote` and `PowerOrderSplittingService`. Verified connector order in the flow: `Call_Create_Order_From_Quote → … → MapQuoteLineFieldsToOrderItems (QuoteToOrderFieldMapper) → SplitPowerOrderLines (PowerOrderSplittingService) → Get_Created_Order`.

Header carryover (from `force-app/main/default/classes/QuoteToOrderFieldMapper.cls:112-185`):

| Order field | Sourced from | Note |
|---|---|---|
| `Bill_To_Account__c` | `Quote.AccountId` | **SC-3339 / Ben Kozlowski rule "Account Name → Bill To Account"** — `QuoteToOrderFieldMapper.cls:135-141`. **Matches the memory flag: this is wrong for ~36% partner-billing cases** (partner billing is place-derived, not the customer Account). Documented gap, not yet fixed. |
| `Ship_To_Account__c` | `Quote.Ship_To_Place__r.Account__c` | place-derived; left null when no Ship_To_Place (`:144-148`) |
| `Bill_To_Address__c` | `Quote.Bill_To_Place__c` | `:151-155` |
| `Ship_To_Address__c` | `Quote.Ship_To_Place__c` | `:158-162` |
| `BillToContactId` | `Quote.BillToContactId` | `:165-169` |
| `ShipToContactId` | `Quote.ContactId` | `:172-176` |

Line carryover (`:198-270`): `QLI.Hardware__c→OI.Hardware__c`, `QLI.Hardware_ID__c→OI.Hardware_ID__c`, `QLI.Partition_Reference__c→OI.Partition_Record__c`, `QLI.Quote.Ship_To_Place__c→OI.Ship_To_Address__c`. The Order's own `Bill_To_Place__c/Ship_To_Place__c` are carried by the platform **Context Mapping Engine** during `createOrderFromQuote` and intentionally untouched by the mapper.

> **Drift note (memory):** Memory "Quote→Order Bill/Ship carryover" says carryover was "already live in flow V23 (Andy's)" and the planned fix was "Apex-consolidate." That Apex consolidation **has happened** — `QuoteToOrderFieldMapper.cls` now owns the header carryover (its header comment: *"replaces the prior Update_Order_Record_with_Bill_to_Ship_To_Address flow element"*), and the conversion flow is now **v27** (not v23). The `Bill_To_Account__c=Quote.AccountId` problem the memory flags is still present (`:135-141`).

### 1.3 Secondary/alternate conversion trigger (record-triggered, not the rep's button)

There is a **second**, record-triggered path: `Quote_After_Update_Create_Order_From_Quote` (AutoLaunched, `RecordAfterSave`, object=Quote). It fires when `Quote.Create_Order_from_Quote__c = true` and calls `createOrderFromQuote` (`quoteRecordId = $Record.Id`).
- Source: `Data/sc3338/retrieve/conv_retrieve/unpackaged/flows/Quote_After_Update_Create_Order_From_Quote.flow` (start filter `Create_Order_from_Quote__c EqualTo true`, action `createOrderFromQuote`).
- The screen flow `Fortra_Quote_to_Order_Conversion` does **NOT** set `Create_Order_from_Quote__c` (grep = 0 occurrences) — it calls `createOrderFromQuote` directly. So the checkbox-triggered flow is an **independent alternate path** (e.g. data-load / programmatic), and it has **no conversion-time validation at all** — a second bypass surface.
- `Create_Order_from_Quote__c` is a plain Checkbox defaulting false (`force-app/main/default/objects/Quote/fields/Create_Order_from_Quote__c.field-meta.xml`).

### 1.4 Live active Quote/Order flow inventory (for completeness)

`FlowDefinitionView` (IsActive=true) on Quote/Order shows the supporting automation, including the conversion trigger and the downstream Workday/sync flows:
- Quote: `Fortra_Quote_Approvals`, `Quote_After_Update_Create_Order_From_Quote`, `Fortra_Quote_Sync_Address_From_Place`, `Fortra_Quote_Validate_Partner_Pricing_Model`, `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered`, etc.
- Order: `Fortra_Order_After_Update_Platform_Event_Workday`, `Order_Before_Insert_Update_Sync_Status`, `Fortra_Order_Workday_Contract_ID`, `Fortra_Order_Set_Payment_Terms`, `Fortra_Order_Sync_Address_From_Place`, `Order_Submission_to_Revenue_Orchestrator`, `Fortra_Assetize_Order`, etc.

---

## 2. The Order-Complete enforcement gate — `Fortra_Order_Submission_Check` v13 walkthrough

**Live status confirmed:** `Fortra_Order_Submission_Check` v13 = **Active** (v12 and below Obsolete) — matches GROUND_TRUTH. ProcessType=Flow (screen flow), object=Order. Source retrieved at `Data/sc3338/retrieve/unpackaged/flows/Fortra_Order_Submission_Check.flow`, apiVersion 66.0.

### 2.1 How it is launched

- **Order quick action `Order.Order_Complete`**, **label "Update Status"**, `type=Flow`, `flowDefinition=Fortra_Order_Submission_Check`.
  - Source: `Data/sc3338/retrieve/conv_qa/unpackaged/quickActions/Order.Order_Complete.quickAction`.
  - It is placed on the **active Order Lightning page `Order_Record_Page_Fortra`** (flexipage references `Order.Order_Complete` and `Order.Send_to_Workday`; `Data/sc3338/retrieve/conv_flexi/unpackaged/flexipages/Order_Record_Page_Fortra.flexipage`).
- The flow receives the Order Id via input variable `recordId` (assigned to `Order_ID` at `Set_Order_Id`, flow lines 128-143).

### 2.2 End-to-end element walk

1. **`Set_Order_Id`** (line 128) → copies `recordId` into `Order_ID` → **`Get_Order`** (line 330): single SOQL on Order by Id.
2. **`ShipTo_BillTo_Account_Contact_Validation`** decision (line 198): an **inline pre-gate**. Rule `ShipTo_BillTo_Present` requires all six non-null: `BillToContactId`, `ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, **`Bill_To_Place__c`, `Ship_To_Place__c`** (lines 211-251). 
   - **All present → `Status_Selection`** screen.
   - **Any missing → `BillShipTo_Validation_Screen`** (line 405): displays *"We can't update the order status, make sure the below fields are populated:"* and an ordered list — Bill To Account, Ship To Account, Bill To Contact, Ship To Contact, Bill To Address, Ship To Address. This screen has **no link to the record** (plain text list) and is a dead-end (Finish), so the rep must navigate manually.
   - **Drift note:** GROUND_TRUTH lists this decision's fields but omits the two Place checks (`Bill_To_Place__c`, `Ship_To_Place__c`); the live v13 flow checks them too (lines 238-251).
3. **`Status_Selection`** screen (line 453): prompt *"Select the Order Status."*, a required `DropdownBox` `Order_Status_Picker` bound to a dynamic Order.Status picklist, defaulted to the current `Get_Order.Status`. Button label **"Select & Save Status"**. → `Status_Route`.
4. **`Status_Route`** decision (line 258):
   - Picked status **≠ "Order Complete"** → **`Update_Order_Stage`** (line 384): simply writes the chosen Status and ends. (No validation — any non-complete status saves freely.)
   - Picked status **= "Order Complete"** (default outcome) → **`Validate_Order_Submission`**.
5. **`Validate_Order_Submission`** (line 90): Apex invocable **`OrderSubmissionValidator`**, input `orderId=Order_ID`. → `Set_Validation_Results` copies `errorCount` and `errorMessages` → `Error_s_Exist`.
   - `OrderSubmissionValidator.cls` (`force-app/main/default/classes/OrderSubmissionValidator.cls`) reads **active `Order_Submit_Validation__mdt`** rules and returns one error per blank required field, in **constant SOQL** (1 Order + 1 OrderItem + 1 per related object). It was introduced by SC-3366 (2026-06-08) to replace the per-field `FieldPopulatedCheck` that breached the 100-SOQL limit on ~16+ line orders (class header lines 1-32). Each error is formatted with a `<a href=".../lightning/r/{Object}/{Id}/view">Link to Record</a>` (`:228-238`).
6. **`Error_s_Exist`** decision (line 173):
   - `ErrorCount = 0` (rule "No") → **`Set_Order_Status_Order_Complete`** (line 351): updates the Order to **`Status='Order Complete'` AND `Workday_Sync_Status__c='Pending'`** (lines 370-381). The `Pending` flag is what arms the Workday platform-event flow (§4). → `Refresh_Page` (`c:RefreshPage`) → `Toast_Success` ("Order sent to Workday.") . A DML fault routes to `Error_Screen` (shows `$Flow.FaultMessage`).
   - `ErrorCount > 0` (default "Yes") → loops `errorDisplayLoop` over `Error_Message_Collection`, concatenating into `Error_Display` → **`Validation_Error_Screen`**.
7. **`Validation_Error_Screen`** (line 500): *"Please see the errors below that prevent you from submitting. You must resolve them before submitting. … Please click the link to update the record. {!Error_Display}"* — i.e. the per-field messages **with clickable record links**, then → `Toast_Failure` ("Order NOT sent to Workday."). The Status is **not** changed; the rep stays in Draft/Activated.

### 2.3 When Status actually flips to "Order Complete"

**Only** at `Set_Order_Status_Order_Complete` (flow line 351), reached **only** when (a) the inline Bill/Ship pre-gate passed, (b) the rep selected "Order Complete", and (c) `OrderSubmissionValidator` returned `errorCount=0`. That single record update sets `Status='Order Complete'` + `Workday_Sync_Status__c='Pending'` in the same DML.

### 2.4 Is the error noticeable / actionable?

Yes, within this flow: the `Validation_Error_Screen` lists each missing field as a bullet with *"Link to Record"* hyperlinks (built in `OrderSubmissionValidator.addError`), plus an error toast. The earlier `BillShipTo_Validation_Screen` is weaker (plain list, no links). Both are genuine blockers **inside the flow** — but see §3 for the bypass.

> **Drift note (force-app is stale):** The local `force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml` is the **OLD** version — it still calls `FieldPopulatedCheck` inside `Get_OrderItem_s` / OrderItem loops (labels "Non OrderItem(s) - Check If Field Is Populated", "OrderItem(s) - Check If Field Is Populated"). Live v13 uses the single `OrderSubmissionValidator` call. force-app holds only 2 flows total and is a sparse working set, not a mirror — always trust live for this flow. (`FieldPopulatedCheck.cls` still exists in the org but is no longer called by the active flow.)

---

## 3. Is the blocker bypassable? — YES (the central finding)

**The required-field set is enforced ONLY by the `Fortra_Order_Submission_Check` screen flow. There is no record-triggered or VR backstop.** Verified live:

- **Order validation rules (7, all active):** `Lock_Currency_At_Order_Activation`, `Order_ShipToPlaceAcct_Equal_OrderAcct`, `Order_ShipToContactAcct_Equal_OrderAcct`, `Order_ShipToAddressAcct_Equal_OrderAcct`, `Order_BillToPlaceAcct_Equal_OrderAcct`, `Order_BillToContactAcct_Equal_OrderAcct`, `Order_BillToAddressAcct_Equal_OrderAcct`. Inspected formulas (`Data/sc3338/retrieve/conv_retrieve2/unpackaged/objects/Order.object`): `Lock_Currency…` only fires on `ISCHANGED(CurrencyIsoCode)` for activated/closed statuses; the `*_Equal_OrderAcct` rules only enforce that the chosen Place/Contact/Address belongs to the Order's Account. **None reference `Status='Order Complete'` or the required-field presence set.**
- **Order triggers (live):** only **`OrderValidationTrigger` (Active)**, and it is **`before insert` only** → calls `OrderValidationTriggerHandler.handleBeforeInsert`. It does **not** run on update, so it cannot gate a `Status → Order Complete` update. (Source: `Data/sc3338/retrieve/conv_retrieve2/unpackaged/triggers/OrderValidationTrigger.trigger`.)
- **Order before-save flow:** `Order_Before_Insert_Update_Sync_Status` (RecordBeforeSave) only manages `Workday_Sync_Status__c / PO_Sync_Status__c / Legacy_Sync_Status__c` flags; it performs **no required-field validation and blocks nothing** (`Data/sc3338/retrieve/conv_retrieve/unpackaged/flows/Order_Before_Insert_Update_Sync_Status.flow`).
- **`Order Complete` is a real `Order.Status` picklist value** with live records in it (live GROUP BY: Activated, **Order Complete**, Draft, Provisioned, Superseded).

**Consequence:** A direct inline edit on the Order detail page, a Data Loader update, a Flow, or any API call that sets `Status='Order Complete'` **skips both screen flows** and is **not** caught by any VR/trigger. Worse, that same Status change is exactly the trigger condition for the Workday platform-event flow (§4) — so a bypassed, incomplete order would still be pushed to Workday. The conversion gate (§1.3 checkbox path) is likewise unvalidated. **This is the "no silent blockers" weakness SC-3338 must address** — the guidance/help-text + Quote-time validation must be paired with a recommendation that the Order-Complete enforcement also gain a record-triggered/VR backstop (or that Status='Order Complete' be settable only via the flow), otherwise the screen-flow guard remains optional.

---

## 4. Downstream tie-in: Order Complete → Workday submission, and which fields are auto-populated

### 4.1 "Order Complete" is the Workday trigger

`Fortra_Order_After_Update_Platform_Event_Workday` (AutoLaunched, `RecordAfterSave`, Update, triggerOrder 500; `Data/sc3338/retrieve/conv_retrieve/unpackaged/flows/Fortra_Order_After_Update_Platform_Event_Workday.flow`):
- `Order_Completed_Decision` (lines 44-82): fires when `Prior.Status ≠ 'Order Complete'` **AND** `Status = 'Order Complete'` **AND** `Workday_Sync_Status__c = 'Pending'` → **creates `Order_Completed_WD__e` platform event** with `Order_Id__c = $Record.Id` (lines 161-177).
- The submission-check flow set both `Status='Order Complete'` and `Workday_Sync_Status__c='Pending'` in the same update (§2.3), so the event fires immediately. This matches the memory **"Workday re-submit mechanism"**: the `Order_Completed_WD__e` event carries only `Order_Id__c`; MuleSoft middleware then reads live Order data and upserts to Workday.
- A manual re-send exists: Order quick action **`Order.Send_to_Workday`** → `Fortra_Screen_Send_Order_to_Workday` screen flow, which also publishes `Order_Completed_WD__e` (3 references). So Workday submission has two entry points (auto on Order Complete + manual re-send), **both keyed off the Order, not the Quote**.

### 4.2 The Workday required fields are auto-populated, NOT rep-entered

This is why the active `Order_Submit_Validation__mdt` set is dominated by `Workday_*` fields: Workday genuinely requires them, but **Salesforce automation fills them** — they are not something a rep types on the Quote. Verified populating mechanisms (live active flows + field describe):

| Required field (active rule) | Object | Populated by | Evidence |
|---|---|---|---|
| `Workday_Contract_ID__c` | Order | flow `Fortra_Order_Workday_Contract_ID` (RecordAfterSave) | live FlowDefinitionView; `IsCalculated=false` (set by flow) |
| `WorkdayReferenceID__c` | Order | **formula** (legal entity's Workday ref) | `FieldDefinition.IsCalculated = true` |
| `Workday_Contract_Line_Type__c` | OrderItem | flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (the V8/V10 line-type logic; SC-3347/3210/3368) | live FlowDefinitionView; `IsCalculated=false` |
| `Billing_Frequency__c` | OrderItem | **formula** | `FieldDefinition.IsCalculated = true` |
| `Billing_Frequency__c` (rule INACTIVE) | Order | flow `Fortra_Order_Set_Payment_Terms` | live FlowDefinitionView |
| `TotalLineTaxAmount`, `LineNumber` | OrderItem | platform pricing / line numbering | `IsCalculated=false` but system-managed |
| `Bill_To_Account__c`, `Ship_To_Account__c` | Order | `QuoteToOrderFieldMapper` at conversion (§1.2) | `IsCalculated=false`; set by Apex from the Quote |
| `EffectiveDate`, `Status` | Order | conversion / activation / the flow itself | — |
| `DB_DUNS__c`, `Phone`, `Type`, `Name` | Account | **rep/data-quality entered on the Account** | — |
| Contact `FirstName`/`LastName`/`Workday_MobilePhone_Device_Type__c`/`_Primary__c`/`_Usage_Type__c` | Contact (Bill+Ship) | **mostly rep/data-quality entered on the Contact** | — |

**Implication for SC-3338:** Of the active required set, the **Workday_* Order/OrderItem fields and Bill/Ship Account fields are auto-populated downstream** and should *not* get Quote help text framed as "rep must enter" — at most they belong in the guidance-modal "system fills this at conversion" note. The genuinely rep/data-owner-entered ones that deserve Quote-time visibility are the **Account** fields (DUNS, Phone, Type, Name) and the **Bill/Ship Contact** fields (names + the three Workday mobile-phone attributes), plus the Quote-side Bill/Ship Place + Contact lookups that the conversion gate already checks.

---

## 5. Where the rep learns about missing data today vs where SC-3338 moves it

### 5.1 Today — the rep's signal arrives in two late waves

1. **Quote build:** Quote has **only `Name` required** (1 of 237 fields), partial help text (36 fields), 5 conditional VRs (none submission-blocking). **Zero visual cue** that DUNS / Contact Workday-phone / etc. will be needed. (Per GROUND_TRUTH §"Quote side (the GAP)".)
2. **First real signal — Convert Quote to Order:** the conversion flow (`Fortra_Quote_to_Order_Conversion` v27) blocks with friendly screens for a **subset**: Bill To Contact, Bill To Place, Billing Street, Ship To Place, Quote Status=Accepted, pricing complete, IsSyncing, no existing order, contract start date, **Operations Checklist complete** (decisions + `Screen_Error_*` text verified in `Data/sc3338/retrieve/conv_q2oflow`). This is the **earliest** the rep learns of *those* gaps — but it does **not** cover Account DUNS/Phone/Type or the Contact Workday mobile-phone attributes or the Workday Order/line fields.
3. **Second, latest signal — Update Status → Order Complete:** only here does `OrderSubmissionValidator` surface the **full** active set (Account/Contact/Order/OrderItem Workday fields). By this point the Order already exists, the Quote is converted, and the rep is deep in the Order UI — the worst possible place to discover that the **Account's** DUNS or a **Contact's** mobile-phone device type is blank. Many of these are owned by other records/teams (Account data quality, Contact enrichment), so the rep is often blocked on data they can't quickly fix. And because the gate is bypassable (§3), a determined/automated path can even skip this signal entirely and fail at Workday instead.

So today the **first** signal is at **conversion** (partial) and the **complete** signal is at **Order Complete** (very late) — or, in the bypass/data-load case, at **Workday rejection** (latest of all).

### 5.2 Where SC-3338 should move it — Quote time

SC-3338's intent (AC #2-4) is to pull the signal **left to Quote build**:
- **Help text** on each genuinely-rep-owned required field surfaced on the Quote layout (Quote-side Bill/Ship Place + Contact lookups; and, for the cross-object Account/Contact prerequisites, guidance pointing to those records).
- **A Flow guidance modal** reachable from the Quote that enumerates every field required for a clean Quote→Order→Order Complete→Workday run, grouped by where it lives (Quote / Account / Bill Contact / Ship Contact) and flagged auto-populated vs must-enter — so the rep can fix data **before** converting.
- **Confirmed blocking validation** at the earliest sensible point. The conversion gate (`Fortra_Quote_to_Order_Conversion`) is the natural home to *extend* — it already runs at Quote time with the right UX pattern (per-field error screens) and already validates a subset. Extending it to check the rep-owned Account/Contact prerequisites would move the full signal to conversion. **Crucially**, because the Order-Complete enforcement is bypassable, SC-3338 should also recommend a **record-triggered/VR backstop** so `Status='Order Complete'` cannot be set with missing data outside the flow ("no silent blockers" / no silent bypass).

---

## Appendix — verification index (all live FortraUAT 2026-06-12)

- Conversion quick action: `Data/sc3338/retrieve/conv_q2o/unpackaged/quickActions/Quote.Convert_Quote_to_Order.quickAction`
- Conversion flow (v27 Active): `Data/sc3338/retrieve/conv_q2oflow/unpackaged/flows/Fortra_Quote_to_Order_Conversion.flow`
- Record-triggered alt conversion: `Data/sc3338/retrieve/conv_retrieve/unpackaged/flows/Quote_After_Update_Create_Order_From_Quote.flow`
- Carryover Apex: `force-app/main/default/classes/QuoteToOrderFieldMapper.cls`
- Order-Complete quick action ("Update Status"): `Data/sc3338/retrieve/conv_qa/unpackaged/quickActions/Order.Order_Complete.quickAction`
- Submission-check flow (v13 Active): `Data/sc3338/retrieve/unpackaged/flows/Fortra_Order_Submission_Check.flow`
- Validator Apex: `force-app/main/default/classes/OrderSubmissionValidator.cls`
- Order VRs + trigger (backstop check): `Data/sc3338/retrieve/conv_retrieve2/unpackaged/objects/Order.object`, `.../triggers/OrderValidationTrigger.trigger`
- Workday platform-event flow: `Data/sc3338/retrieve/conv_retrieve/unpackaged/flows/Fortra_Order_After_Update_Platform_Event_Workday.flow`
- Send-to-Workday flow + quick action: `Data/sc3338/retrieve/conv_wd/...`, `Data/sc3338/retrieve/conv_qa/.../Order.Send_to_Workday.quickAction`
- Active Order Lightning page: `Data/sc3338/retrieve/conv_flexi/unpackaged/flexipages/Order_Record_Page_Fortra.flexipage`
