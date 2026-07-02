# SC-3338 — DIMENSION A: Required-Field Inventory & Enforcement Map

**Acceptance Criterion #1:** *"Documented inventory of all fields required for a valid Quote→Order, with the metadata enforcing each."*

Sources: live FortraUAT (`liam.jeong.c@fortra.com.uat`), read-only, 2026-06-12. Repo baseline = `force-app/main/default`. Every claim cites a live query or a `file_path:line`.

---

## 1. Executive summary

- The "required for a valid Quote→Order" rule set is enforced **on the Order, not the Quote**, by a metadata-driven Apex validator fired late (when a rep tries to move Order `Status → Order Complete`).
- The canonical machine-readable rule set is **`Order_Submit_Validation__mdt` — 48 records, 25 Active / 23 Inactive** (live count confirmed). Full export: `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv`. The local CSV byte-matches the live org.
- Enforcer = **`OrderSubmissionValidator.cls`** (`force-app/main/default/classes/OrderSubmissionValidator.cls:69`), invoked once per Order in constant SOQL, called by **`Fortra_Order_Submission_Check` flow v13 (Active)** (live action call `Validate_Order_Submission -> OrderSubmissionValidator`).
- **The whole machinery is UAT-only.** In `FortraProd` the `Order_Submit_Validation__mdt` object does not exist, the flow has no active version, and neither Apex class exists (live prod queries). This matches the SC-3291 memory ("do NOT deploy to prod").
- On the **Quote** side there is essentially no required-field signal: only `Name` is hard-required (nillable=false), and only **36 of 237** Quote fields carry inline help text (live describe). The key user-entered drivers (`AccountId`, `BillToContactId`, `StartDate`, `ExpirationDate`) have **no help text**.
- **Provenance is the heart of the ticket:** of the 25 active required fields, only a handful are genuinely **user-entered** (Account `Phone`/`Type`/`DB_DUNS__c`, Bill/Ship Place→Account, Contact name/phone attributes). The Workday_* and OrderItem line fields are **auto-populated** by flows (`Fortra_OrderItem_Set_Workday_Contract_Line_Type` v11, `Fortra_OrderItem_Set_Dates` v5) or are **system** fields. The rep needs guidance only on the user-entered subset.
- **Fill-rate evidence proves the split:** on submitted Orders (Order Complete / Activated) the Order/OrderItem auto-populated fields are 90–100% filled, while the **Account user-entered** fields are sparse (`DB_DUNS__c` 67%, `Type` 56%) — those are the real failure surface.

### Drift discovered vs GROUND_TRUTH.md (live UAT wins)
| # | GROUND_TRUTH said | Live finding |
|---|---|---|
| D1 | "Order validation rules: none in force-app (verify live)" | **7 ACTIVE Order VRs live** (Bill/Ship-To consistency + currency lock). See §6. |
| D2 | Quote VRs = 5 conditional (Amendment_Requires_Contract, Enforce_Discount_Cap, Require_Amendment_Reason, etc.) | Live Quote VRs = **4**: `Enforce_Amendment_Sales_Restriction`, `Sales_Cannot_Create_Downsell`, `Quote_BillToContactAcct_Equal_QuoteAcct`, `Quote_BillToPlacceAcct_Equal_QuoteAcct`. The 3 named in GROUND_TRUTH are NOT live; 2 new Bill-To consistency VRs ARE. See §6. |
| D3 | (implied valid rule fields) | **2 mdt rule fields do not exist in the org**: `Contact.Workday_Customer_Id__c` (X00011/X00041) and `OrderItem.ProductCode` (X00034). Both INACTIVE; validator's `fieldExists()` guard skips them anyway. See §3a. |
| D4 | local force-app submission flow = the active one | **Local force-app flow is STALE**: it still calls deprecated `FieldPopulatedCheck`; live v13 calls `OrderSubmissionValidator`. See §5. |
| D5 | line-type flow version (memory: V8/V9/V10) | Live active = **V11** of `Fortra_OrderItem_Set_Workday_Contract_Line_Type`. |

---

## 2. Enforcement architecture (how a field becomes "required for Quote→Order")

```
REP builds QUOTE (only Name hard-required, ~no help text, no submission VR)
        │  RLM native convert (placeQuote)  +  Bill/Ship carryover flow
        ▼
ORDER created (Draft).  Auto-pop flows stamp Workday_* + line-type + dates.
        │  Rep clicks the "Order Submission Check" screen-flow action
        ▼
Fortra_Order_Submission_Check  v13 (Active, screen flow on Order)
        │  action: Validate_Order_Submission  ──►  OrderSubmissionValidator.validate(orderId)
        │     reads Order_Submit_Validation__mdt WHERE Active__c=true (25 rules)
        │     constant SOQL: 1 Order + 1 OrderItem + 1/related-object (Account, Contact)
        ▼
   hasErrors? ── yes ──►  Validation_Error_Screen lists blank required fields (blocks)
              └─ no  ──►  Status → Order Complete
```

- Validator entry point & "populated" semantics: `OrderSubmissionValidator.cls:69` (invocable), `:245` (`isFieldPopulated`), `:254` (`isValuePopulated` — **Boolean `false` counts as populated**, line 258-259; text must be non-blank; everything else non-null).
- `Relationship_Field_API_Name__c` resolves the target record from the Order: `Id`=the Order itself, `OrderId`=per-line OrderItem (every line), else a FK on the Order (`AccountId`, `BillToContactId`, `ShipToContactId`, `Bill_To_Address__c`, `Ship_To_Address__c`) — documented at `OrderSubmissionValidator.cls:21-26`.
- **Safety guard:** `fieldExists()` (`OrderSubmissionValidator.cls:102, 297-303`) drops any rule whose field is absent from `getGlobalDescribe()`, so a misconfigured rule can't break the run (relevant to D3).

---

## 3. MASTER required-field inventory

Legend — **Provenance**: `USER` = rep enters on Quote (or related record); `AUTO` = flow/Apex/integration populates downstream; `INT` = integration/order-only, no Quote analog; `SYS` = system field (Id/LineNumber/Status). **Active?** from live `Order_Submit_Validation__mdt`. Error message is the same templated string for every mdt rule (*"Required Field: {Object} {Label} is required to be populated to save the Order's Status as 'Order Complete'. Action: Populate the field with the accurate value."*) except `Order.EffectiveDate` (X00028) which has a **blank** Error_Message__c — validator then emits the generic *"Required field is missing."* (`OrderSubmissionValidator.cls:230`).

### 3a. From `Order_Submit_Validation__mdt` (48 rules — the canonical set)

| Object | Field (API) | Field Label | DevName | Rel. path from Order | Active? | Provenance | Driving automation / Quote source |
|---|---|---|---|---|---|---|---|
| Account | `DB_DUNS__c` | D&B DUNS | X00002 | AccountId | **Active** | USER | Manual on Account (not on Quote); D&B enrichment |
| Account | `Name` | Account Name | X00003 | AccountId | **Active** | USER | Account.Name (set at account creation) |
| Account | `Phone` | Phone | X00001 | AccountId | **Active** | USER | Manual on Account |
| Account | `Type` | Type | X00004 | AccountId | **Active** | USER | Manual on Account |
| Contact (Bill) | `FirstName` | First Name | X00013 | BillToContactId | **Active** | USER | Quote `BillToContactId`→Order→Contact |
| Contact (Ship) | `FirstName` | First Name | X00036 | ShipToContactId | **Active** | USER | Quote contact / Ship carryover→Contact |
| Contact (Bill) | `LastName` | Last Name | X00014 | BillToContactId | **Active** | USER | Contact (required on Contact too) |
| Contact (Ship) | `LastName` | Last Name | X00037 | ShipToContactId | **Active** | USER | Contact |
| Contact (Bill) | `Workday_MobilePhone_Device_Type__c` | Workday MobilePhone Device Type | X00018 | BillToContactId | **Active** | USER/AUTO | Contact attr; manually maintained |
| Contact (Ship) | `Workday_MobilePhone_Device_Type__c` | … | X00042 | ShipToContactId | **Active** | USER/AUTO | Contact attr |
| Contact (Bill) | `Workday_MobilePhone_Primary__c` | Workday MobilePhone Primary | X00019 | BillToContactId | **Active** | AUTO | **Boolean — `false` passes validator** (`:258`); effectively always satisfied |
| Contact (Ship) | `Workday_MobilePhone_Primary__c` | … | X00043 | ShipToContactId | **Active** | AUTO | Boolean, always passes |
| Contact (Bill) | `Workday_MobilePhone_Usage_Type__c` | Workday MobilePhone Usage Type | X00020 | BillToContactId | **Active** | USER/AUTO | Contact attr |
| Contact (Ship) | `Workday_MobilePhone_Usage_Type__c` | … | X00044 | ShipToContactId | **Active** | USER/AUTO | Contact attr |
| Order | `Bill_To_Account__c` | Bill To Account | X00024 | Id | **Active** | AUTO | Derived from Quote `Bill_To_Place__c` (place→account) at convert |
| Order | `EffectiveDate` | Order Start Date | X00028 | Id | **Active** | AUTO/USER | Quote `StartDate`; **nillable=false on Order** (hard-required) |
| Order | `Ship_To_Account__c` | Ship To Account | X00025 | Id | **Active** | AUTO | Derived from Quote `Ship_To_Place__c` |
| Order | `Status` | Status | X00022 | Id | **Active** | SYS | Order lifecycle; **nillable=false** |
| Order | `Workday_Contract_ID__c` | Workday Contract Id | X00021 | Id | **Active** | AUTO | **= Order Id** (30/30 sample); defaulted to record Id |
| Order | `WorkdayReferenceID__c` | Legal Entity's Workday Reference ID | X00023 | Id | **Active** | AUTO/INT | Legal-entity derived; integration value |
| OrderItem | `Billing_Frequency__c` | Billing Frequency | X00031 | OrderId | **Active** | AUTO | Line billing template (e.g. `Yearly_Billing_Template`) |
| OrderItem | `Id` | Id | X00032 | OrderId | **Active** | SYS | System Id (always present) |
| OrderItem | `LineNumber` | Line Number | X00029 | OrderId | **Active** | SYS | System line number |
| OrderItem | `TotalLineTaxAmount` | Product Subtotal Tax | X00033 | OrderId | **Active** | AUTO | Pricing/tax engine (0 if untaxed) |
| OrderItem | `Workday_Contract_Line_Type__c` | Workday Contract Line Type | X00030 | OrderId | **Active** | AUTO | **`Fortra_OrderItem_Set_Workday_Contract_Line_Type` v11** |
| Contact (Bill) | `Business_Entity_Contact_ID__c` | Business Entity Contact ID | X00012 | BillToContactId | Inactive | INT | Workday round-trip id |
| Contact (Ship) | `Business_Entity_Contact_ID__c` | … | X00035 | ShipToContactId | Inactive | INT | Workday round-trip id |
| Contact (Bill) | `MobilePhone` | Mobile | X00017 | BillToContactId | Inactive | USER | Contact phone |
| Contact (Ship) | `MobilePhone` | Mobile | X00038 | ShipToContactId | Inactive | USER | Contact phone |
| Contact (Bill) | `Workday_Customer_Id__c` | Workday Customer Id | X00011 | BillToContactId | Inactive | INT | **FIELD DOES NOT EXIST on Contact** (live describe) |
| Contact (Ship) | `Workday_Customer_Id__c` | … | X00041 | ShipToContactId | Inactive | INT | **FIELD DOES NOT EXIST on Contact** |
| Contact (Bill) | `Workday_MobilePhone_Country_ISO_Code__c` | Mobile Phone Country | X00015 | BillToContactId | Inactive | AUTO | Contact attr |
| Contact (Ship) | `Workday_MobilePhone_Country_ISO_Code__c` | … | X00040 | ShipToContactId | Inactive | AUTO | Contact attr |
| Contact (Bill) | `Workday_MobilePhone_International_Phone__c` | Mobile Phone Code | X00016 | BillToContactId | Inactive | AUTO | Contact attr |
| Contact (Ship) | `Workday_MobilePhone_International_Phone__c` | … | X00039 | ShipToContactId | Inactive | AUTO | Contact attr |
| Order | `Billing_Frequency__c` | Billing Frequency | X00027 | Id | Inactive | AUTO | Order-level billing freq |
| Order | `Workday_Contract_Type__c` | Workday Contract Type | X00026 | Id | Inactive | AUTO/INT | Workday contract type |
| OrderItem | `ProductCode` | Product Code | X00034 | OrderId | Inactive | AUTO | **NOT in OrderItem describe / not queryable** (metadata FieldDefinition only) |
| Places (Bill) | `Location_Type__c` | Location Type | X00010 | Bill_To_Address__c | Inactive | USER | Place attribute (see §7) |
| Places (Ship) | `Location_Type__c` | … | X00045 | Ship_To_Address__c | Inactive | USER | Place attribute |
| Places (Bill) | `Primary__c` | Primary | X00008 | Bill_To_Address__c | Inactive | USER | Place attribute (Boolean) |
| Places (Ship) | `Primary__c` | … | X00046 | Ship_To_Address__c | Inactive | USER | Place attribute |
| Places (Bill) | `Public__c` | Public | X00007 | Bill_To_Address__c | Inactive | USER | Place attribute (Boolean) |
| Places (Ship) | `Public__c` | … | X00047 | Ship_To_Address__c | Inactive | USER | Place attribute |
| Places (Bill) | `Street_Address_Line_2__c` | Street Address Line 2 | X00005 | Bill_To_Address__c | Inactive | USER | Place attribute |
| Places (Ship) | `Street_Address_Line_2__c` | … | X00048 | Ship_To_Address__c | Inactive | USER | Place attribute |
| Places (Bill) | `Street_Address_Line_3__c` | Street Address Line 3 | X00006 | Bill_To_Address__c | Inactive | USER | Place attribute |
| Places (Ship) | `Street_Address_Line_3__c` | … | X00049 | Ship_To_Address__c | Inactive | USER | Place attribute |

> Two inactive rules reference fields that do not exist in the org (`Contact.Workday_Customer_Id__c`, `OrderItem.ProductCode`). They are inert because they are inactive AND because `OrderSubmissionValidator.fieldExists()` (`:297-303`) would skip them even if reactivated. **Do not reactivate them without first creating the fields.**

### 3b. Platform / hard-required fields NOT in the mdt (also required for a valid Order/Quote)

| Object | Field (API) | Label | Enforcement layer | Active? | Provenance |
|---|---|---|---|---|---|
| Order | `EffectiveDate` | Order Start Date | nillable=false (describe) **+** mdt X00028 | Yes | AUTO/USER (Quote `StartDate`) |
| Order | `Status` | Status | nillable=false (describe) **+** mdt X00022 | Yes | SYS |
| Order | `AccountId` | Account ID | required-on-layout (Order-Order Layout, per GROUND_TRUTH) | Yes | USER (Quote `AccountId`) |
| Order | `ContractId` | Contract | required-on-layout | Yes | INT |
| Quote | `Name` | Quote Name | nillable=false (describe) + required-on-layout | Yes | USER |
| Quote | `Amendment_Reason__c` | Amendment Reason | required-on-layout (Amendment Quote Layout) **+** VR `Require_Amendment_Reason`* | Conditional | USER |
| OrderItem | `Id`, `LineNumber` | — | system / nillable behavior | Yes | SYS |

*`Require_Amendment_Reason` VR was named in GROUND_TRUTH but is **not** in the live Quote VR list (D2) — treat the layout-required as the live enforcer.

---

## 4. Provenance roll-up (the rep-guidance vs automation split)

This is the decision table for which active required fields need Quote help text / guidance-modal coverage.

| Provenance | Active required fields | Needs rep guidance? |
|---|---|---|
| **USER (rep must ensure)** | Account `DB_DUNS__c`, `Phone`, `Type` (Name auto-present); Contact (Bill+Ship) `FirstName`, `LastName`, `Workday_MobilePhone_Device_Type__c`, `Workday_MobilePhone_Usage_Type__c` | **YES** — these are the genuine gaps; Account fields especially under-filled (§5 fill-rates) |
| **AUTO (flow/Apex/integration)** | Order `Bill_To_Account__c`, `Ship_To_Account__c`, `Workday_Contract_ID__c`, `WorkdayReferenceID__c`; OrderItem `Billing_Frequency__c`, `TotalLineTaxAmount`, `Workday_Contract_Line_Type__c`; Contact `Workday_MobilePhone_Primary__c` (Boolean, always passes) | No — automation owns these; surfacing them confuses the rep |
| **SYS** | Order `Status`; OrderItem `Id`, `LineNumber` | No |
| **AUTO via Quote source** | Order `EffectiveDate` (Quote `StartDate`) | Indirect — guidance belongs on the Quote `StartDate`, not the Order field |

**Implication for SC-3338:** the guidance modal + help text should center on the **USER** row above, expressed in **Quote** terms (Account completeness; Bill-To/Ship-To Place & Contact selection; Start Date). The AUTO/SYS rows should be explicitly excluded from rep-facing guidance.

---

## 5. Fill-rate evidence (live FortraUAT samples)

### Order — 30 most recent (mixed) vs submitted-only (Order Complete/Activated)
| Field | All recent (n=30) | Submitted only (n=30) | Reading |
|---|---|---|---|
| Bill_To_Account__c | 100% | 100% | AUTO reliable |
| Ship_To_Account__c | 83% | 100% | AUTO; blanks were Drafts |
| BillToContactId | 80% | 100% | AUTO; blanks were Drafts |
| ShipToContactId | 73% | 93% | mostly AUTO |
| EffectiveDate | 100% | 100% | reliable |
| Workday_Contract_ID__c | 100% | 100% | **= Order Id, 30/30** (defaulted) |
| WorkdayReferenceID__c | 53% | 90% | AUTO; late-populated |
| Bill_To_Address__c | 83% | 100% | AUTO |
| Ship_To_Address__c | 83% | 100% | AUTO |

Status distribution of the 30 recent: Draft 15 / Order Complete 8 / Activated 7 — so blanks cluster on pre-submission Drafts, confirming downstream auto-population.

### OrderItem — 40 most recent lines
| Field | Fill | Reading |
|---|---|---|
| LineNumber | 100% | SYS |
| Billing_Frequency__c | 100% | AUTO (`Yearly_Billing_Template`) |
| TotalLineTaxAmount | 100% | AUTO (0 when untaxed) |
| Workday_Contract_Line_Type__c | 100% | AUTO (flow v11: FIXED AMOUNT / USAGE BASED / FIXED AMOUNT BILLING ONLY) |

### Account — referenced by submitted Orders (n=9)
| Field | Fill | Reading |
|---|---|---|
| Name | 100% | always present |
| Phone | 89% | USER — occasionally blank |
| DB_DUNS__c | **67%** | USER — frequent gap |
| Type | **56%** | USER — frequent gap |

(30 most-recent Accounts overall are far sparser — DB_DUNS 13%, Phone 13%, Type 23% — i.e. these are reliably blank until someone fills them for an order.)

### Contact — Bill/Ship-To on submitted Orders (n=12)
| Field | Active? | Fill | Reading |
|---|---|---|---|
| FirstName | Active | 100% | reliable |
| LastName | Active | 100% | reliable |
| Workday_MobilePhone_Device_Type__c | Active | 92% | USER/AUTO — 1 gap |
| Workday_MobilePhone_Usage_Type__c | Active | 92% | USER/AUTO — 1 gap |
| Workday_MobilePhone_Primary__c | Active | non-null 12/12 (True=5, False=7) | Boolean — validator passes `false`, so always satisfied |
| MobilePhone | inactive | 58% | — |
| Workday_MobilePhone_Country_ISO_Code__c | inactive | 58% | — |
| Workday_MobilePhone_International_Phone__c | inactive | 58% | — |
| Business_Entity_Contact_ID__c | inactive | 25% | INT — why it's inactive |

**Bottom line:** the active Order/OrderItem/Contact-name set is 90–100% reliable by submission time (automation handles it). The real, recurring user gaps are the **Account** fields (`DB_DUNS__c`, `Type`, `Phone`) and the two Contact Workday mobile-phone attributes — exactly the USER-provenance rows in §4.

### Source staleness (D4)
- Local `force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml` still calls the deprecated `FieldPopulatedCheck` (grep: `<actionName>FieldPopulatedCheck</actionName>`).
- Live v13 (FlowId `301WC00000kNX46YAG`, `Status=Active`) calls `Validate_Order_Submission -> OrderSubmissionValidator [apex]`. **Live wins; do not trust the local flow XML for current behavior.**
- Quote help text: live describe = **36 / 237** Quote fields have `inlineHelpText` (local field-meta count is 37/182 — local source is also slightly out of sync). Key user-entered drivers `AccountId`, `BillToContactId`, `StartDate`, `ExpirationDate` have **no** help text; only `Bill_To_Place__c`, `Ship_To_Place__c`, `ContactId` do.

---

## 6. Validation rules (the OTHER enforcement layer — live, not in GROUND_TRUTH)

### Order VRs — 7 ACTIVE (D1; GROUND_TRUTH said "none")
| VR | Active | Purpose |
|---|---|---|
| `Lock_Currency_At_Order_Activation` | true | currency immutability post-activation |
| `Order_ShipToPlaceAcct_Equal_OrderAcct` | true | Ship-To Place's account must equal Order account |
| `Order_ShipToContactAcct_Equal_OrderAcct` | true | Ship-To Contact account consistency |
| `Order_ShipToAddressAcct_Equal_OrderAcct` | true | Ship-To Address account consistency |
| `Order_BillToPlaceAcct_Equal_OrderAcct` | true | Bill-To Place account consistency |
| `Order_BillToContactAcct_Equal_OrderAcct` | true | Bill-To Contact account consistency |
| `Order_BillToAddressAcct_Equal_OrderAcct` | true | Bill-To Address account consistency |

These are **consistency** rules (cross-field), not blank-required rules, but they CAN block an Order save if a rep mismatches Bill/Ship account vs Order account — relevant to the "submission blocked" experience. Source family ties to SC-3298/SC-3308 Bill/Ship carryover work.

### Quote VRs — 4 ACTIVE (D2)
| VR | Active | Type |
|---|---|---|
| `Enforce_Amendment_Sales_Restriction` | true | conditional (amendment) |
| `Sales_Cannot_Create_Downsell` | true | conditional (amendment) |
| `Quote_BillToContactAcct_Equal_QuoteAcct` | true | Bill-To consistency |
| `Quote_BillToPlacceAcct_Equal_QuoteAcct` | true | Bill-To consistency (note the `Placce` typo in the dev name) |

None of these is a blanket "required for submission" rule — confirming the core gap: **no Quote-time blank-required validation exists.** OrderItem VRs: **0** live.

---

## 7. Places rules — why all 10 are INACTIVE

All 10 `Places` rules (X00005-X00010, X00045-X00049, on `Bill_To_Address__c` / `Ship_To_Address__c`) are `Active__c=false`. This aligns with **SC-3298 / BUG-MTC-388**, which was resolved **documented-only** (memory: *"Place-attribute fields are optional in Workday … layout experiment reverted"*). The address/Place attributes (`Location_Type__c`, `Primary__c`, `Public__c`, `Street_Address_Line_2/3__c`) are not mandatory for the Workday round-trip, so requiring them would block valid Orders. They remain in the mdt as **disabled, documented** placeholders. **Do not activate them** as part of SC-3338.

---

## 8. Quote→Order source-field mapping (each USER-required field back to its Quote driver)

Verified field existence via live Quote/Order describes. Note the Quote uses **Places** and standard Contact/Account lookups; the Order's `Bill_To_Account__c`/`Ship_To_Account__c` are *derived from the Quote Places at convert*, not direct Quote fields.

| Order/related required field | Quote-side source (verified exists) | Mechanism |
|---|---|---|
| Order `Bill_To_Account__c` | Quote `Bill_To_Place__c` (reference) | Place→account resolution at convert / carryover flow |
| Order `Ship_To_Account__c` | Quote `Ship_To_Place__c` (reference) | Place→account resolution |
| Order `BillToContactId` → Contact `FirstName`/`LastName`/Workday phone | Quote `BillToContactId` (reference) / `ContactId` | carryover; Contact must be complete |
| Order `ShipToContactId` → Contact fields | Quote `Ship_To_Place__c` contact / `ContactId` | Quote has **no** `ShipToContactId` field (MISSING in describe) — Ship contact derived from Place/carryover |
| Order `EffectiveDate` | Quote `StartDate` (date) | mapped at convert; **Order field is nillable=false** |
| Account `DB_DUNS__c`, `Phone`, `Type` | Quote `AccountId` → Account | no Quote analog; rep maintains the Account |
| Order `Workday_Contract_ID__c`, `WorkdayReferenceID__c` | (none) | AUTO/INT — no Quote source; not a rep concern |

> Quote fields confirmed **absent** (so cannot be a source / cannot be help-texted): `ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Bill_To_Address__c`, `Ship_To_Address__c`, `EffectiveDate`, `Billing_Frequency__c`, `Workday_Contract_Type__c`. Quote uses `Bill_To_Place__c`/`Ship_To_Place__c`, `BillToContactId`, `ContactId`, `AccountId`, `StartDate`, `ExpirationDate`, `Status` instead.

---

## 9. Prod vs UAT parity

| Artifact | FortraUAT | FortraProd |
|---|---|---|
| `Order_Submit_Validation__mdt` | 48 records | **Object does not exist** (query errors at column 21) |
| `Fortra_Order_Submission_Check` flow | v13 Active | **No active version** (0 records) |
| `OrderSubmissionValidator` / `FieldPopulatedCheck` classes | present | **Neither exists** (0 records) |

The entire blank-required enforcement layer is **UAT-only**, consistent with SC-3291 ("do NOT deploy to prod, 2026-06-01"). Any SC-3338 build must decide deliberately whether Quote-time guidance ships to prod independent of this UAT-only Order enforcer.

---

## 10. Key file & query references
- Rule export: `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` (byte-matches live mdt).
- Validator: `force-app/main/default/classes/OrderSubmissionValidator.cls` (entry `:69`; populated-semantics `:245-265`; fieldExists guard `:297-303`).
- Active flow (live): FlowId `301WC00000kNX46YAG`, v13, action `OrderSubmissionValidator`. Local XML `force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml` is **stale** (calls FieldPopulatedCheck).
- Auto-pop flows: `Fortra_OrderItem_Set_Workday_Contract_Line_Type` v11, `Fortra_OrderItem_Set_Dates` v5 (live, active).
