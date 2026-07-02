# SC-3338 — Dimension B: Quote UI / Help-Text / Indicator Audit

**Acceptance Criterion #2:** "Each required field has descriptive help text on the Quote layout."

**Scope of this doc:** current-state audit of the two Quote page layouts + the Lightning Quote Record Page, a field-by-field gap table for every user-entered Quote driver of an Order-submission requirement, the full inventory of existing help text (what NOT to disturb), the asterisk/indicator options analysis (Ashley's "even an asterisk?"), and the record-page/FlexiPage surface inventory.

All facts cite either the retrieved artifacts (`Data/sc3338/retrieve/...`) or a live read-only query against **FortraUAT** run 2026-06-12. Drift from `GROUND_TRUTH.md` is flagged in §7.

---

## 0. Executive snapshot

- Both Quote layouts are **wide but nearly indicator-free**: Quote-Quote Layout = **128 placed layout items, exactly 1 Required-on-layout (`Name`)**; Quote-Amendment Quote Layout = **127 items, 2 Required (`Name`, `Amendment_Reason__c`)**. Confirms GROUND_TRUTH.
- Only **36 of 237 Quote fields carry inline help text** (`Quote_describe.json`). The help text that exists is good quality and clusters on **Place fields, partner fields, amendment/financial fields, and discount fields** — it does **NOT** systematically cover the Order-submission required set.
- **Critical structural fact:** the live **Quote Lightning record page (`Quote_Record_Page`) is a dynamic FlexiPage built from 16 `fieldSection` components with explicit `fieldItem`s — it does NOT embed the classic layout via `force:recordDetail`.** So the *layout* file and the *Lightning page* are two different field surfaces. Inline help text still renders on the Lightning page (the field component reads `inlineHelpText` from the field metadata), but **"Required-on-layout" dots from the classic layout do NOT carry to the dynamic FlexiPage** — required-ness on a dynamic page is controlled by component-level field properties / the field's own `nillable`, not by the layout `<behavior>Required</behavior>`. This materially changes how AC#2 should be satisfied (see §5).
- **Most Order-submission required fields are NOT user-entered Quote fields at all.** The Account/Contact/OrderItem/Workday_* requirements live on downstream objects and are auto-derived. The genuine **Quote-side user-entered drivers** reduce to roughly **8 Place lookups + `StartDate` + `Status` + a small partner/currency set**, and the most important of those (the 8 Place fields) **already have help text**. The real gaps are concentrated and small (see §3).

---

## 1. Layout audit — both Quote layouts

Source: `Data/sc3338/retrieve/unpackaged/layouts/Quote-Quote Layout.layout`, `.../Quote-Amendment Quote Layout.layout`. Parsed by counting `<layoutItems><behavior>…</behavior><field>…</field></layoutItems>` blocks.

| Metric | Quote-Quote Layout | Quote-Amendment Quote Layout |
|---|---|---|
| Total placed layout items | **128** | **127** |
| `Edit` behavior | 103 | 97 |
| `Readonly` behavior | 24 | 28 |
| **`Required` behavior** | **1** | **2** |
| Required-on-layout field(s) | `Name` | `Name`, `Amendment_Reason__c` |
| Section count | 9 | 12 |

**Quote-Quote Layout sections** (`Quote-Quote Layout.layout:7,402,421,464,499,526,553,583,606`): Quote Information · Pricing Information · Place Information · Totals · Prepared for · Address Information · Approval Flow Checkboxes · System Information · Custom Links.

**Quote-Amendment Quote Layout sections** (`Quote-Amendment Quote Layout.layout:7,69,83,115,433,452,495,530,557,584,615,633`): Amendment Details · Related Contract Information · Financial Impact · Quote Information · Pricing Information · Place Information · Totals · Prepared for · Address Information · Approval Flow Checkboxes · System Information · Custom Links.

**Where the user-relevant required-ish drivers live on the classic layout:**

| Driver field | On Quote-Quote Layout? | Section | Behavior | Notes |
|---|---|---|---|---|
| `Name` | Yes | Quote Information | **Required** | The only required field (`Quote-Quote Layout.layout:14`) |
| `Status` | Yes | Quote Information (col 2) | Edit | `:361` |
| `StartDate` | Yes | Quote Information | Edit | `:151` — maps to Order `EffectiveDate` |
| `ExpirationDate` | Yes | Quote Information (col 2) | Edit | `:353` |
| `CurrencyIsoCode` | Yes | Quote Information | Edit | `:35` |
| `Bill_To_Place__c` | Yes | Place Information | Edit | `:425` |
| `Ship_To_Place__c` | Yes | Place Information | Edit | `:429` |
| `Service_Place__c` / `Install_Place__c` / `End_User_Place__c` / `Regulatory_Place__c` / `Partner_Place__c` / `Primary_Place__c` | Yes | Place Information | Edit | `:433–455` |
| `BillToContactId` | Yes | Quote Information | Edit | `:247` |
| `LegalEntityId` | Yes | Quote Information (col 2) | Edit | `:385` |
| `PartnerAccountId` | Yes | Quote Information (col 2) | Edit | `:393` |
| `Account_Billing_Account__c` | Yes | Quote Information | Edit | `:331` |
| **`ShipToContactId`** | **MISSING — field does not exist on Quote** | — | — | Order-only (verified live, §2) |
| **`Bill_To_Account__c` / `Ship_To_Account__c`** | **MISSING — Order-only fields** | — | — | Derived from Place at conversion |
| **`Billing_Frequency__c`** | **MISSING — Order/OrderItem-only field** | — | — | Not on Quote |
| `Amendment_Reason__c` | Amendment layout only | Amendment Details | **Required** (Amendment) | `Quote-Amendment Quote Layout.layout:48` |

**Takeaway:** the layout is *not* missing the key user-entered drivers — all 8 Place fields, `Status`, `StartDate`, `BillToContactId`, `LegalEntityId`, `PartnerAccountId` are present. What's missing from the *Quote object entirely* are the **Order-side fields** (`ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Billing_Frequency__c`) — these are populated by the Quote→Order conversion from the Place lookups, so the rep never types them on the Quote. AC#2 therefore cannot literally apply to those four; it applies to their **Quote-side source fields**.

---

## 2. Quote-field driver gap table (the AC#2 deliverable)

**Derivation method:** From `GROUND_TRUTH.md` §"ACTIVE required-field rules" and the live `Order_Submit_Validation_LIVE.csv`, every active requirement is on **Account / Contact / Order / OrderItem / Places** — never directly on the Quote. I mapped each back to the **Quote-side field a rep actually enters** that feeds it through Quote→Order conversion (Place lookups carry account+contact+address; `StartDate→EffectiveDate`; currency/legal-entity/partner carry across). Fields that are **purely auto-populated downstream** (`Workday_*`, `WorkdayReferenceID__c`, `Workday_Contract_ID__c`, `TotalLineTaxAmount`, `LineNumber`, OrderItem `Id`, `Status`=Order Complete, etc.) are intentionally **excluded** — they are not a rep concern and must not get Quote help text per scope rule #2 ("do NOT hard-require every field").

Verification of existence/help-text: `Data/sc3338/retrieve/Quote_describe.json` (237 fields); live `FieldDefinition` query on FortraUAT confirms `ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Billing_Frequency__c` are **absent** from Quote and **present** on Order.

Legend: On Layout? = present on Quote-Quote Layout classic layout. On FlexiPage? = present on live `Quote_Record_Page`. "Req-on-layout?" = classic `<behavior>Required</behavior>`.

| Quote Field | Feeds Order requirement(s) | On Layout? | On FlexiPage? | Req-on-layout? | Has help text? | Current help text | RECOMMENDED help text |
|---|---|---|---|---|---|---|---|
| `Bill_To_Place__c` | Order `Bill_To_Account__c`; Account `Name/Phone/Type/DB_DUNS__c`; BillTo Contact set; Places fields | Yes | Yes | No | **Yes** | "Select the place where invoices should be sent for this quote" | "Bill To Place — required before the Order can be completed. Drives the billing Account, Bill To Contact, and billing address sent to Workday. Choose a Place tied to this Quote's Account." |
| `Ship_To_Place__c` | Order `Ship_To_Account__c`; ShipTo Contact set; Places fields | Yes | Yes | No | **Yes** | "Select the place where products should be delivered" | "Ship To Place — required before the Order can be completed. Drives the shipping Account, Ship To Contact, and ship-to address. Choose a Place tied to this Quote's Account." |
| `BillToContactId` | Contact `FirstName/LastName/Workday_MobilePhone_*` (BillTo) | Yes | Yes | No | No | — | "Bill To Contact — required for Order completion. This contact's name and Workday mobile-phone fields are validated before the Order can be submitted; pick a contact on this Quote's Account." |
| `Service_Place__c` | (Services lines) downstream service location | Yes | Yes | No | **Yes** | "Select the place where services will be delivered or performed" | *(keep as-is — clear and correct)* |
| `Install_Place__c` | downstream install location | Yes | Yes | No | **Yes** | "Select the location where installation services will occur" | *(keep as-is)* |
| `End_User_Place__c` | downstream end-user account/regulatory | Yes | Yes | No | **Yes** | "Select the primary place of the end user for this quote" | *(keep as-is)* |
| `Regulatory_Place__c` | export/compliance routing | Yes | Yes | No | **Yes** | "Select the place that determines regulatory requirements and compliance" | *(keep as-is)* |
| `Partner_Place__c` | partner billing/place | Yes | Yes | No | **Yes** | "Select the place of the partner involved in this quote" | *(keep as-is)* |
| `Primary_Place__c` | default place fallback | Yes | Yes | No | **Yes** | "Select the primary or default place for this quote" | *(keep as-is)* |
| `StartDate` | Order `EffectiveDate` (Order Start Date) | Yes | Yes | No | No | — | "Quote Start Date — becomes the Order Start Date (Effective Date), which is required before the Order can be completed. Set the date the contract/term should begin." |
| `Status` | Order `Status` lifecycle gate | Yes (col 2) | Yes | No | No | — | "Quote Status — must advance through the standard stages; the Order cannot be completed until the Quote is converted from an accepted status." |
| `CurrencyIsoCode` | Order currency; Workday legal-entity currency | Yes | Yes | No | No | — | "Quote Currency — locks at Order activation and must match the Legal Entity. Set before adding products; it cannot be changed once the Order is active." |
| `LegalEntityId` | Order `WorkdayReferenceID__c` (Legal Entity's Workday Reference ID) | Yes (col 2) | Yes | No | No | — | "Legal Entity — determines the Workday Reference ID required for Order completion. Select the Fortra legal entity that owns this deal." |
| `PartnerAccountId` | partner billing path on Order | Yes (col 2) | No | No | No | — | "Partner Account — set for channel/partner deals so partner billing and the Bill To Account resolve correctly on the Order." |
| `Billing_Partner__c` | partner billing path | No (FlexiPage only) | Yes | No | **Yes** | "Select the billing partner for this quote." | *(keep as-is)* |
| `Amendment_Reason__c` | (amendment governance, not Order-submit) | Amendment layout | Yes | **Yes (Amendment)** | **Yes** | "Select the primary reason for this amendment to the original contract." | *(keep as-is)* |
| `Name` | (required by schema; not an Order-submit field) | Yes | Yes | **Yes** | No | — | *(standard; help text optional — "A descriptive name for this Quote, e.g. Account – Product – Term.")* |

**Fields intentionally NOT given Quote help text** (auto-populated downstream; per scope rule #2): all `Workday_*` Contact/Order fields, `WorkdayReferenceID__c`, `Workday_Contract_ID__c`, `Workday_Contract_Line_Type__c`, OrderItem `Id/LineNumber/Billing_Frequency__c/TotalLineTaxAmount`, Account `DB_DUNS__c/Name/Phone/Type` (those are Account-page concerns, surfaced by the Order-side validator's record links, not the Quote).

**Net help-text gap for AC#2:** of the ~14 genuine Quote-side drivers, **9 already have help text** (all 8 Place fields + `Billing_Partner__c`). The concrete additions needed are **5 fields: `BillToContactId`, `StartDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId`** (+ optionally `PartnerAccountId`, `Name`). This is a small, low-risk change set.

---

## 3. Inventory of all 36 fields that currently HAVE help text (do NOT disturb)

Source: `Data/sc3338/retrieve/Quote_describe.json` (`inlineHelpText` populated). These are existing, business-approved strings; any new help text must be additive and leave these untouched.

| # | Field API name | Label | Current help text |
|---|---|---|---|
| 1 | `Amendment_ARR_Impact__c` | Amendment ARR Impact | Enter the ARR change resulting from this amendment. Use positive for increases, negative for decreases. |
| 2 | `Amendment_Effective_Date__c` | Amendment Effective Date | Enter the date when this amendment should take effect. |
| 3 | `Amendment_Reason__c` | Amendment Reason | Select the primary reason for this amendment to the original contract. |
| 4 | `Amendment_Request_Date__c` | Amendment Request Date | Enter the date when this amendment was originally requested. |
| 5 | `Approval_Justification__c` | Approval Justification | Used to justify any approvals or discounts. This will be sent in the approval emails. |
| 6 | `Bill_To_Place__c` | Bill To Place | Select the place where invoices should be sent for this quote |
| 7 | `Billing_Partner__c` | Billing Partner | Select the billing partner for this quote. |
| 8 | `ContactId` | Contact ID | This is the Fortra Quote Contact. |
| 9 | `Credit_Amount__c` | Credit Amount | Enter the credit amount to be issued to the customer for this downgrade or cancellation. |
| 10 | `Days_Until_Renewal__c` | Days Until Renewal | Days remaining until the original contract expires. |
| 11 | `Discount` | Discount | Enter the overall quote discount percentage |
| 12 | `DiscountApprovalStatus__c` | Discount Approval Status | Status of discount approval request |
| 13 | `DiscountApprover__c` | Discount Approver | User who approved the discount exception |
| 14 | `Distributor__c` | Distributor | Select the distributor partner if applicable. |
| 15 | `End_User_Place__c` | End User Place | Select the primary place of the end user for this quote |
| 16 | `Hardware__c` | Hardware | Hardware record driving product eligibility and pricing for this quote. Selected in hardware-first workflow by Power team. |
| 17 | `Install_Place__c` | Install Place | Select the location where installation services will occur |
| 18 | `Latest_Effective_End_Date__c` | Latest Effective End Date | This field automatically displays the furthest subscription end date from all Quote Lines |
| 19 | `Manual_Discount__c` | Manual Discount % | Enter the manual discount percentage to apply to this quote (e.g., enter 10 for 10% discount) |
| 20 | `Net_Contract_Change__c` | Net Contract Change | The net financial change resulting from this amendment after credits. |
| 21 | `Original_Contract_ARR__c` | Original Contract ARR | The current ARR of the contract being amended. |
| 22 | `Partner_Place__c` | Partner Place | Select the place of the partner involved in this quote |
| 23 | `Partner_Pricing_Model_Source__c` | Partner Pricing Model Source | Shows whether the pricing model was automatically set from partner defaults or manually selected |
| 24 | `Partner_Pricing_Model__c` | Partner Pricing Model | Guaranteed Margin: All partner margins are summed and applied. Discount: Only billing partner discount applies. |
| 25 | `Primary_Place__c` | Primary Place | Select the primary or default place for this quote |
| 26 | `Pro_Rated_Amount__c` | Pro-Rated Amount | The pro-rated amount to be charged or credited for this amendment. |
| 27 | `Pro_Ration_Method__c` | Pro-Ration Method | Select how pro-rated charges should be calculated for this amendment. |
| 28 | `Referral_Partner__c` | Referral Partner | Select the referral partner if applicable. |
| 29 | `Regulatory_Place__c` | Regulatory Place | Select the place that determines regulatory requirements and compliance |
| 30 | `Reseller__c` | Reseller | Select the reseller partner if applicable. |
| 31 | `Service_Place__c` | Service Place | Select the place where services will be delivered or performed |
| 32 | `Ship_To_Place__c` | Ship To Place | Select the place where products should be delivered |
| 33 | `Terms_and_Conditions__c` | Enable Terms and Conditions | Please check this box to make edits to the Custom Text field. |
| 34 | `TotalDiscount__c` | Total Discount | Total discount percentage applied to the quote |
| 35 | `Total_Discount_Amount__c` | Total Discount Amount | Calculated total discount amount for the quote |
| 36 | `Within_Renewal_Window__c` | Within Renewal Window | Checked if this contract is within 120 days of renewal. Sales users have restrictions during this window. |

---

## 4. Asterisk / indicator question — "even an asterisk?" (Ashley Gabbert)

The ask is: how do we **visually indicate** a field is required without breaking save. Options, with the regression trade-off:

| Option | How it shows | Blocks SAVE? | Blocks Order submit? | Regression risk | Verdict for SC-3338 |
|---|---|---|---|---|---|
| **A. Mark field Required-on-layout** (`<behavior>Required</behavior>`) | Red asterisk (`*`) on the field, classic layout | **YES — blocks save of the Quote** | No (separate gate) | **HIGH.** Many "required for Order" fields are **conditionally** required (e.g. Place fields differ for partner vs direct; `LegalEntityId` only some deals). Hard-requiring them blocks early Quote drafting, breaks clone/Apex/test/integration inserts, and contradicts scope rule #2. Also **does not even render on the dynamic FlexiPage** (§5). | **Reject as a blanket approach.** Acceptable only for the already-true case `Name` (and Amendment `Amendment_Reason__c`). |
| **B. Inline help text** (the `?` bubble) | Hover/`?` icon next to the field | No | No | **None** — purely informational. | **Adopt** — this is AC#2 itself. Add the 5 missing strings from §2; gives a per-field "this is needed for the Order" cue. |
| **C. A "Required for Order" custom section / fieldSection** on the Lightning page grouping the driver fields, with the section description text | Visual grouping + section header text | No | No | **Low** — layout-only, no behavior change. | **Adopt** — pair with B. Put the ~14 driver fields (or the Place set + Status/StartDate/Currency/LegalEntity) in one clearly-labeled fieldSection so the rep sees them together. |
| **D. Flow Screen guidance modal** (the ticket's chosen mechanism) listing all required fields + their current blank/filled state, reachable from the Quote | Button/quick action → modal checklist | No | No (it informs; the Order-side validator blocks) | **Low** — net-new Flow, no schema change. | **Adopt** — this is scope item #3 and the most honest "indicator": it shows *exactly* what's still missing, including downstream Account/Contact fields the rep can't see on the Quote. |
| **E. Pre-built guidance/Path component** already on the page | `runtime_sales_pathassistant:pathAssistant` + `interaction_orchestrator:workGuide` + `operationsChecklistPanel` (Operations Checklist tab) | No | No | None | **Leverage** — the page already has Path, Work Guide, and an Operations Checklist; the guidance text/key-fields can be surfaced there without a new component. |

**Recommended approach (combine, lowest-regression, satisfies AC#2 + #3):**
1. **Help text (Option B)** on the 5 missing Quote-side driver fields (`BillToContactId`, `StartDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId`) using the strings in §2 — this directly closes AC#2, zero behavior change.
2. **Do NOT** mark additional fields Required-on-layout (Option A) — it blocks save and is too aggressive for conditionally-required fields; keep only the existing `Name` / `Amendment_Reason__c` asterisks.
3. **Group the driver fields** into a clearly-labeled "Required for Order Submission" fieldSection on `Quote_Record_Page` (Option C) so the asterisk-substitute is the *section context*, not a save-blocking dot.
4. **Build the Flow guidance modal (Option D)** for the live "what's still missing" checklist — the only thing that can also reflect the downstream Account/Contact/Workday gaps the rep cannot see on the Quote. This is the real answer to "is anything blocking submission?" and pairs with the existing Order-side `OrderSubmissionValidator` / `Fortra_Order_Submission_Check` (v13) blocker.

So the literal answer to "even an asterisk?": **an asterisk via Required-on-layout is the wrong tool here** (it blocks save and won't render on the dynamic page); the right visual indicators are **help-text bubbles + a grouped section + a live guidance modal**, with hard-blocking left to the existing Order-side validator.

---

## 5. Lightning record pages / FlexiPages the Quote uses

Live query (FortraUAT, Tooling API): `FlexiPage WHERE EntityDefinition.QualifiedApiName='Quote'` →
- **`Quote_Record_Page`** (MasterLabel "Quote Record Page", Type `RecordPage`) — the single Quote record page. Retrieved to `Data/sc3338/retrieve/flexipage/flexipages/Quote_Record_Page.flexipage-meta.xml`.

Related Quote-area pages (not the Quote object): `Quote_Line_Item_Record_Page`, `Quote_Checklist_Item_Record_Page`.

**Structure of `Quote_Record_Page` (2,820 lines):**
- **Type:** dynamic FlexiPage — **16 `flexipage:fieldSection` components, 135 `fieldItem` field references (133 unique fields), built directly on the page** (NOT `force:recordDetail`). FieldItem syntax is `Record.<FieldName>` (e.g. `Quote_Record_Page.flexipage-meta.xml:233` `Record.Name`).
- **FieldSection labels:** Amendment Details · Financial Impact · Renewal Details · General · Deal Partner Information · Prepared For · Quote Level Discounts · Totals · Currency Information · **Place Information** · Compliance · Approval Flow Checkboxes · System Information · Document Display Options · Terms and Conditions · Tabs.
- **Tabs (`flexipage:tabset`/7 `flexipage:tab`):** Details · Quote Documents · Related Lists · Approvals · Activity · **Operations Checklist**.
- **Guidance-capable components already present:** `runtime_sales_pathassistant:pathAssistant` (linear Path), `interaction_orchestrator:workGuide` ("Work Guide", not hidden when empty), `operationsChecklistPanel` (Operations Checklist tab), `runtime_revenue_foundation:progressIndicator`, `quoteLineFlexPanel`, `runtime_revenue_foundation:transactionLineTable`/`transactionSummary` (RLM line editor), `runtime_approvals:approvalTrace`, `force:highlightsPanel`.
- **Driver fields confirmed present on the FlexiPage** (so help text WILL surface to reps): all 8 Place fields, `BillToContactId`, `ContactId`, `AccountId`, `QuoteAccountId`, `StartDate`, `ExpirationDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId`, `Billing_Partner__c`, `Amendment_Reason__c`, `Name`, and `Validation_Result__c` (textarea — surfaces the validation outcome). **Not on the FlexiPage:** `PartnerAccountId`, and (because they don't exist on Quote) `Bill_To_Account__c` / `Ship_To_Account__c`.

**Implication for AC#2:** because the page is a dynamic FlexiPage, the **place to add the help text is the field metadata** (`inlineHelpText`, which the `fieldSection`'s field component renders) — editing the classic layout's `Required` behavior would NOT change what the rep sees here. A "Required for Order" section (Option C) should be added as a new `fieldSection` on `Quote_Record_Page`, and the guidance modal (Option D) can be wired to a quick action or surfaced via the existing Path / Work Guide / Operations Checklist.

---

## 6. Conditionally-required consistency VRs already in place (context for the asterisk debate)

Live query (FortraUAT) — these matter because they already block SAVE on a few of the driver fields, demonstrating exactly why blanket Required-on-layout would over-block:

**Quote (4 active VRs):**
- `Quote_BillToContactAcct_Equal_QuoteAcct` → field "Bill To Contact": "Select a Bill To Contact that is related to this Quote's Account."
- `Quote_BillToPlacceAcct_Equal_QuoteAcct` *(note the real name has the "Placce" typo)* → field "Bill To Place": "Select a Bill To Place that is related to this Quote's Account."
- `Enforce_Amendment_Sales_Restriction` → field "Amendment Reason" (120-day renewal restriction).
- `Sales_Cannot_Create_Downsell` → field "Amendment Reason".

**Order (7 active VRs):** `Lock_Currency_At_Order_Activation`, plus six `Order_{Bill,Ship}To{Place,Contact,Address}Acct_Equal_OrderAcct` consistency rules.

These already enforce *relational correctness* (the Place/Contact must belong to the Quote/Order Account) — so the help text in §2 should reinforce "choose a Place tied to this Quote's Account" to pre-empt these VR errors.

---

## 7. Drift from GROUND_TRUTH.md (live UAT wins)

| GROUND_TRUTH statement | Live finding (2026-06-12) | Disposition |
|---|---|---|
| "Quote validation rules (5): Amendment_Requires_Contract, Enforce_Amendment_Sales_Restriction, Enforce_Discount_Cap, Require_Amendment_Reason, Sales_Cannot_Create_Downsell" (line 49) | Live UAT has **4 active Quote VRs**: `Enforce_Amendment_Sales_Restriction`, `Sales_Cannot_Create_Downsell`, `Quote_BillToContactAcct_Equal_QuoteAcct`, `Quote_BillToPlacceAcct_Equal_QuoteAcct`. The three local-only names (`Amendment_Requires_Contract`, `Enforce_Discount_Cap`, `Require_Amendment_Reason`) **do not exist live at all** (explicit name query returned NONE). The two BillTo-equality VRs are live-only (not in force-app). | **DRIFT.** Local `force-app/main/default/objects/Quote/validationRules/` (5 files) is **stale**. Live is authoritative. |
| "Order validation rules: none in force-app (verify live)" (line 50) | Live UAT has **7 active Order VRs** (`Lock_Currency_At_Order_Activation` + 6 Place/Contact/Address-Account-equality rules). | **DRIFT** (GROUND_TRUTH only claimed "none in force-app", which is true; live has 7 — now verified). |
| 128 / 127 layout items; 1 / 2 Required | **Confirmed exactly** (128/1 and 127/2). | ✔ No drift |
| 36 of 237 fields have help text; only `Name` hard-required | **Confirmed exactly** (237 fields, 36 with `inlineHelpText`; only `Name` is nillable=false & non-defaulted & user-enterable). | ✔ No drift |
| Implied: Quote shows fields via the classic layout | The user-facing surface is the **dynamic FlexiPage `Quote_Record_Page`**, not the classic layout. Layout `Required` behavior won't render there. | **Nuance/added finding** — changes how AC#2 should be implemented. |
| GROUND_TRUTH treats Bill_To/Ship_To and contacts as Quote concerns | `ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Billing_Frequency__c` **do not exist on Quote** (verified live `FieldDefinition`); only `BillToContactId` exists. Their Quote-side drivers are the **Place lookups**. | **Added finding** — corrects the field-by-field mapping. |

---

## 8. Recommendation summary (AC#2)

1. **Add inline help text to 5 Quote-side driver fields** that lack it and feed Order requirements: `BillToContactId`, `StartDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId` (strings in §2). Optionally `PartnerAccountId`, `Name`. This is the minimal, zero-regression change that satisfies AC#2.
2. **Leave the 36 existing help-text strings untouched** (§3) — they're business-approved and cover the 8 Place fields + partner/amendment/discount fields.
3. **Do not mark additional fields Required-on-layout** — it blocks SAVE (not just submit) and won't even render on the dynamic FlexiPage; keep only the existing `Name` / `Amendment_Reason__c` asterisks.
4. **Add a "Required for Order Submission" fieldSection** to `Quote_Record_Page` grouping the driver fields, and **build the Flow guidance modal** (scope #3) for the live missing-field checklist — surfaced via the page's existing Path / Work Guide / Operations Checklist.
5. **Reinforce relational guidance** in help text ("choose a Place/Contact tied to this Quote's Account") to pre-empt the 4 active Quote consistency VRs (§6).
6. **Refresh the stale local `force-app` Quote VR set** before any deploy (§7 drift) so a deploy doesn't re-introduce the 3 deleted VRs or clobber the 2 live BillTo-equality VRs.
