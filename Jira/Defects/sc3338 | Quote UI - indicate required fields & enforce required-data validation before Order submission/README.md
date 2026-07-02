# SC-3338 — Quote UI: Indicate Required Fields & Enforce Required-Data Validation Before Order Submission

**Status:** Research + Design complete (build pending Wren UX sign-off)
**Sprint:** CRM 14 · **Components:** SF Sales Cloud · **Labels:** CRM, CRM-Sales-Cloud, LOB-Salesforce-1-UAT, ui, ux
**Reporter:** Jomil Bell · **Assignee:** Liam Jeong · **Callouts:** Ashley Gabbert ("even an asterisk?") + Wren ("no validation stopping submission")
**Verified:** live FortraUAT + FortraProd, 2026-06-12 (read-only). All claims below cite repo `file_path:line` or a live query.

---

## 1. Executive summary

A rep can build a Quote, convert it to an Order, and only discover missing required data **much later** — at Order-Complete submission (when the bulk of the missing data is owned by other teams) or, in bypass cases, at Workday rejection. The Quote itself gives almost no signal: **only `Name` is hard-required** (`nillable=false`, verified in `Quote_describe.json`) and only **36 of 237** Quote fields carry inline help text — none systematically covering the Order-submission required set.

The single most important insight from this research: **most "required for Order submission" fields are NOT user-entered on the Quote — they are auto-populated downstream or are system fields.** Only a small Account/Contact/Place/date set is genuinely rep-controlled. So the fix is **not** to hard-require fields (the ticket explicitly forbids this — scope rule #2), but to (a) surface the genuinely rep-owned drivers via help text, (b) add a Flow guidance modal that shows the full ✔/✘ readiness picture (including Account/Contact fields that can't carry Quote help text), and (c) add a non-restrictive, un-bypassable Quote-time blocking validation on the conversion boundary.

The full Order-side blocking machinery (`Order_Submit_Validation__mdt` + `OrderSubmissionValidator` + `Fortra_Order_Submission_Check` flow) is **UAT-only** and must **not** be deployed to prod (SC-3291, user directive 2026-06-01). The SC-3338 prod-safe deliverables are the UX (help text + modal); the Quote blocker is held UAT-only until the broader machinery is promoted.

---

## 2. The gap (why this ticket exists)

Today a rep learns of missing data in **two late waves**:

1. **At conversion** — the conversion screen flow blocks a *subset* (Bill To Contact, Bill To Place, Billing Street, Ship To Place, Quote Status=Accepted, pricing/CalculationStatus complete, IsSyncing, no existing Order, contract start date, Operations Checklist). It does **not** cover Account DUNS/Phone/Type, Contact Workday mobile-phone attributes, or any Order/OrderItem Workday field. (`12_CONVERSION_AND_ENFORCEMENT_PATH.md`)
2. **At Order-Complete** — the *full* required set is first enforced only when a rep clicks the **"Update Status" → Order Complete** quick action, which launches `Fortra_Order_Submission_Check` v13 → `OrderSubmissionValidator`. This is very late, and most blocked fields are owned by other teams. (`12_`, `13_VALIDATION_GAP_ANALYSIS.md`)

And there is a **true silent bypass**: there is **no record-triggered flow or Validation Rule** that gates the required-field set on `Status='Order Complete'`. The only enforcement is inside a screen-flow quick action a rep may never click. Any inline edit / Data Loader / API write / the `Create_Order_from_Quote__c` checkbox-flow that sets `Status='Order Complete'` skips both screen flows entirely and is never caught — until Workday rejects it. (`13_`)

The Quote gives **no** visual cue and runs **no** Quote-time presence validation. That is the "un-noticeable blocker" Wren flagged.

---

## 3. Verified required-field inventory — the user-entered vs auto-populated split (KEY INSIGHT)

`Order_Submit_Validation__mdt` holds the canonical "required for Order Complete" rules: **48 records (25 Active / 23 Inactive)** — verified live (`COUNT()=48`; `WHERE Active__c=true` → 25). The local export `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` byte-matches the org. Each rule is `{Object_API_Name__c, Field_API_Name__c, Relationship_Field_API_Name__c, Active__c, Error_Message__c, Link_Message__c, …}`, where `Relationship_Field_API_Name__c` = `Id` (the Order itself), `OrderId` (per-line OrderItem), or a FK on the Order resolving a related Account/Contact/Place.

The table below is the **heart of the ticket** — it classifies each *active* rule by **provenance** (who/what populates it), which drives whether it needs rep-facing UX or is simply not a rep concern.

| Category | Field (mdt rule) | Active | Provenance | Rep concern? | Evidence |
|---|---|:--:|---|:--:|---|
| **Account** (`AccountId`) | `Name` | ✅ | USER-entered | yes | CSV X00003 |
| Account | `Phone` | ✅ | USER-entered | yes | CSV X00001 |
| Account | `DB_DUNS__c` | ✅ | USER-entered (data owner) | yes | CSV X00002 |
| Account | `Type` | ✅ | USER-entered | yes | CSV X00004 |
| **Contact** BillTo (`BillToContactId`) + ShipTo (`ShipToContactId`) | `FirstName`, `LastName` | ✅ | USER-entered | yes | CSV X00013/36, X00014/37 |
| Contact (Bill+Ship) | `Workday_MobilePhone_Device_Type__c`, `Workday_MobilePhone_Usage_Type__c` | ✅ | USER/data-owner entered | yes | CSV X00018/42, X00020/44 |
| Contact (Bill+Ship) | `Workday_MobilePhone_Primary__c` | ✅ | Boolean — **never blocks** | no (no-op) | CSV X00019/43; validator `OrderSubmissionValidator.cls:258-259` |
| **Order** (`Id`) | `Bill_To_Account__c` | ✅ | AUTO at conversion (`QuoteToOrderFieldMapper`) | no | CSV X00024; `QuoteToOrderFieldMapper.cls:19-27,130-141` |
| Order | `Ship_To_Account__c` | ✅ | AUTO (Ship_To_Place's Account; **null when no Ship_To_Place**) | no (data hole) | CSV X00025; `QuoteToOrderFieldMapper.cls:22-23` |
| Order | `EffectiveDate` | ✅ | AUTO from Quote.StartDate (rep-owned at Quote) | indirect | CSV X00028 (blank Error_Message → generic text) |
| Order | `Status` | ✅ | SYSTEM | no | CSV X00022 |
| Order | `Workday_Contract_ID__c` | ✅ | AUTO = Order Id (flow `Fortra_Order_Workday_Contract_ID` v3) | no | CSV X00021; live IsCalculated=false |
| Order | `WorkdayReferenceID__c` | ✅ | AUTO — **formula** (IsCalculated=true) | no | CSV X00023; live FieldDefinition IsCalculated=true |
| **OrderItem** (`OrderId`) | `LineNumber`, `Id`, `TotalLineTaxAmount` | ✅ | SYSTEM | no | CSV X00029/32/33 |
| OrderItem | `Billing_Frequency__c` | ✅ | AUTO — **formula** (IsCalculated=true) | no | CSV X00031; live FieldDefinition IsCalculated=true |
| OrderItem | `Workday_Contract_Line_Type__c` | ✅ | AUTO (flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type` v11) | no | CSV X00030 |

**Net rep-owned set:** Account `Name`/`Phone`/`DB_DUNS__c`/`Type`; Contact (Bill+Ship) `FirstName`/`LastName`/Workday device-type + usage-type; and (at Quote) the StartDate→EffectiveDate driver plus the Bill/Ship Place lookups that hydrate Ship_To_Account at conversion. **Everything else is auto-populated or system** — surfacing it as a "required field the rep must fill" would be noise.

**Inactive rules (23)** are present but not enforced and must NOT be activated for SC-3338: all 10 **Places** rules (`Location_Type__c`/`Primary__c`/`Public__c`/`Street_Address_Line_2/3__c` on Bill/Ship_To_Address) are inactive *by design* — SC-3298/BUG-MTC-388 was resolved documented-only (Place attributes optional in Workday). The Contact `Workday_Customer_Id__c` (X00011/X00041) and OrderItem `ProductCode` (X00034) rules reference fields that **do not exist on the SObject describe**, so the validator's `fieldExists()` guard (`OrderSubmissionValidator.cls:297-303`) skips them even if reactivated. *(Caveat for future readers: `OrderItem.ProductCode` DOES return one row from the `FieldDefinition` metadata catalog, but it is absent from the SObject `describe().fields` map the runtime validator reads via `SObject.get(fieldName)` — so the inactive rule is inert regardless.)*

**Two no-op/non-specific behaviors to know:** (a) the validator treats **Boolean** as always-populated (`OrderSubmissionValidator.cls:258-259`), so `Workday_MobilePhone_Primary__c` and any reactivated Places `Primary__c`/`Public__c` rule can never block; (b) the `EffectiveDate` rule (X00028) has a **blank** `Error_Message__c`, but the validator substitutes a generic `'Required field is missing.'` (`OrderSubmissionValidator.cls:230`) — not silent, just non-specific. `Workday_Contract_ID__c == Order.Id` was confirmed across a 30-order sample (auto-defaulted), so it is never a rep concern.

**Fill-rate evidence (directional).** On submitted Orders the **auto-populated** Order/OrderItem required fields are essentially always filled — a 30-order sample showed `Bill_To_Account__c`/`Ship_To_Account__c`/`Workday_Contract_ID__c`/`EffectiveDate`/`BillToContactId` = 100%, `WorkdayReferenceID__c` = 90%, `ShipToContactId` = 93%; OrderItem `Billing_Frequency__c`/`LineNumber`/`TotalLineTaxAmount`/`Workday_Contract_Line_Type__c` = 100% (95 lines). By contrast the **Account-level user-maintained fields** (`DB_DUNS__c`, `Phone`, `Type`) are occasionally blank and are the real rep-guidance surface. *(The earlier precise figures — DUNS 67% / Type 56% — did NOT reproduce on a larger sample: a 63-account pull from 200 recent submitted orders gave DUNS 89% / Type 90% / Phone 78%, and a 10-account sample gave 60/60/80. Treat the 67%/56% as a single-snapshot artifact; the **qualitative** point — Account fields are user-maintained and can be blank, vs ~90-100% auto-fill — is what holds.)*

See `10_REQUIRED_FIELD_INVENTORY.md` for the per-rule walk-through.

---

## 4. Quote-side UI / help-text audit (where AC#2 must land)

- **Layouts (verified by parsing `.layout`):** `Quote-Quote Layout` = 128 placed items, **1 Required-on-layout (`Name`)**; `Quote-Amendment Quote Layout` = 127 items, **2 Required (`Name`, `Amendment_Reason__c`)`. (`11_QUOTE_UI_HELPTEXT_AUDIT.md`)
- **CRITICAL — classic Required dots do NOT render:** the live Quote Lightning page (`Quote_Record_Page`) is a **dynamic FlexiPage** built from 16 `fieldSection` components with 135 explicit `fieldItems` — it does **not** embed the classic layout via `force:recordDetail`. So classic-layout Required behavior never reaches reps; **`inlineHelpText` DOES render.** Therefore AC#2 must be satisfied via **field metadata help text + a grouped guidance section**, not via the layout's Required flag. (`11_`)
- **Help text coverage:** **36 of 237** Quote fields have `inlineHelpText` (verified in `Quote_describe.json`). Existing help clusters on the 8 Place fields, partner fields, amendment/financial/discount fields — it does **not** cover the Order-submission set.
- **The genuine Quote-side drivers** reduce to ~8 Place lookups + `StartDate` + `Status` + `CurrencyIsoCode` + `LegalEntityId` + a small partner set. Live describe confirms: `Bill_To_Place__c`, `Ship_To_Place__c`, `ContactId`, `Billing_Partner__c` **already have** help text; **`BillToContactId`, `StartDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId` have NONE** → these 5 need new help text.
- **Fields that DON'T exist on Quote** (verified live — they are Order-only): `ShipToContactId`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Billing_Frequency__c`. Only `BillToContactId` exists on Quote. Their Quote-side drivers are the **Place lookups** that carry account+contact+address into the Order at conversion.
- **`Quote_Record_Page` already has guidance-capable surfaces** (no new component build needed): `runtime_sales_pathassistant:pathAssistant` (Path), `interaction_orchestrator:workGuide` (Work Guide), an Operations Checklist tab, and a `Validation_Result__c` field. Recommend adding a new **"Required for Order Submission" fieldSection** here rather than touching the classic layout's Required behavior. (`11_`)

**Ashley's "asterisk" question, answered:** marking fields Required-on-layout blocks **SAVE** (not just submit), is too aggressive for conditionally-required fields, contradicts scope rule #2, **and won't even render** on the dynamic FlexiPage. The correct indicators are inline help text + a grouped "Required for Order" section + a Flow guidance modal, with hard-blocking left to the conversion/Order-side enforcement. (`11_`)

---

## 5. Conversion & enforcement path (verified live)

| Stage | Trigger | What runs | Validates required set? | Evidence |
|---|---|---|:--:|---|
| **Convert** (UI) | Quote QA "Convert Quote to Order" | screen flow `Fortra_Quote_to_Order_Conversion` **v27 Active** → standard RLM `createOrderFromQuote` | **partial** (per-field error screens for a subset; see §2) | `12_`; live FlowDefinitionView |
| **Convert** (headless) | `Quote.Create_Order_from_Quote__c=true` | record-after-save `Quote_After_Update_Create_Order_From_Quote` → `createOrderFromQuote` | **NO validation** | `12_`,`13_`; live |
| Field mapping | (during conversion) | `QuoteToOrderFieldMapper.cls` maps Quote→Order required data | n/a (mapping) | `QuoteToOrderFieldMapper.cls:19-27,130-141` |
| **Order-Complete gate** | Order QA "Update Status" (`Order.Order_Complete`) | screen flow `Fortra_Order_Submission_Check` **v13 Active** → `OrderSubmissionValidator.validate()` (`OrderSubmissionValidator.cls:69`) | **YES — full mdt set**, with per-field error screen + record links | `12_`; live; CSV |
| Status flip | inside v13, only when `errorCount=0` | sets `Status='Order Complete'` + `Workday_Sync_Status__c='Pending'` (one DML) | n/a | `12_` |
| Downstream | Status='Order Complete' | `Fortra_Order_After_Update_Platform_Event_Workday` → `Order_Completed_WD__e` → MuleSoft → Workday | n/a | `12_` |

**The crux (bypassable):** the only real blocker (`OrderSubmissionValidator`) runs **only** inside the Order "Update Status" quick action. There is **no** record-triggered backstop and **no** VR keyed to `Status='Order Complete'`. Live Order has **7 active VRs** (`Lock_Currency_At_Order_Activation` + 6 Bill/Ship account-equality consistency rules) — none enforces the required-field presence set — and the only Order trigger, `OrderValidationTrigger`, is **before-insert only** (`./conv_retrieve2/unpackaged/triggers/OrderValidationTrigger.trigger`; also `./Org Data/_src/triggers/`). So the required-field set is genuinely bypassable. (`12_`,`13_`)

**Drift note on the local flow:** the force-app copy `force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml` is **STALE** — it still calls the deprecated per-field `FieldPopulatedCheck` (4 references; 0 to `OrderSubmissionValidator`), which is the SC-3366 SOQL-governor bug. **Do not deploy the local flow.** Live v13 calls the single `OrderSubmissionValidator`. force-app holds only 2 flows total — it is a sparse working set, not a mirror. (`12_`,`14_SOLUTION_DESIGN.md`)

---

## 6. Prod-vs-UAT parity constraint (binding)

**The entire Order-submission validation machinery is UAT-only** — verified live against FortraProd (all 0 rows / absent):

| Artifact | FortraUAT | FortraProd | Method (read-only) |
|---|---|---|---|
| `Order_Submit_Validation__mdt` | 48 records (25 active) | **ABSENT** | `EntityDefinition WHERE QualifiedApiName='Order_Submit_Validation__mdt'` → 0 |
| `Fortra_Order_Submission_Check` flow | v13 Active | **ABSENT** | tooling `Flow WHERE Definition.DeveloperName=…` → 0 |
| `OrderSubmissionValidator` class | EXISTS | **ABSENT** | `ApexClass WHERE Name=…` → 0 |
| `FieldPopulatedCheck` class | EXISTS (deprecated) | **ABSENT** | same → 0 |

Implication: the **UX deliverables (help text + Flow modal) are prod-safe** and may ship to both orgs. The **Quote-time blocking validation is UAT-only for now** and must wait to promote to prod until the broader Order-submission/SC-3291 machinery is itself promoted — so Quote-time and Order-time enforcement stay consistent. Re-deploying the Order machinery to prod is **prohibited** (user 2026-06-01). (`13_`, `14_`, `Data/sc3338/PROD_PARITY_EVIDENCE.md`)

---

## 7. Recommended solution & low-lift build plan

Three deliverables, none of which hard-requires a field (no `nillable=false`, no layout Required).

### 7a. Help text (AC#2) — prod-safe
Add/append `inlineHelpText` on the **5 Quote driver fields with none today**: `BillToContactId`, `StartDate`, `Status`, `CurrencyIsoCode`, `LegalEntityId` (verified NONE live). Do **not** disturb the 36 fields that already have help text (`Bill_To_Place__c`, `Ship_To_Place__c`, `ContactId`, `Billing_Partner__c` already covered). Add a new **"Required for Order Submission" fieldSection** to `Quote_Record_Page` (dynamic FlexiPage) grouping these drivers — this is where help text actually renders to reps. (`11_`,`14_`)

### 7b. Flow guidance modal (AC#3) — prod-safe
A **Quote-side screen Flow** (per ticket: Flow over LWC for maintainability/consistency with the existing `Order_Complete` and `Convert_Quote_to_Order` Flow quick actions), launched from a new Quote quick action **`Review_Required_Fields`** (input `recordId`). It reads the live Quote + Account + Contacts + Places and renders declarative ✔/✘ readiness rows mirroring `OrderSubmissionValidator.isValuePopulated` (`OrderSubmissionValidator.cls:254-265`). **Do NOT reuse `OrderSubmissionValidator`** — it is Order-Id-keyed and there is no Order pre-conversion. The modal is the **only** surface that can show Account/Contact-resident requirements (DUNS, Phone, Type, contact names, Workday device/usage type) that cannot carry Quote help text — which is precisely why the ticket needs both. (`14_`)

### 7c. Non-restrictive blocking validation (AC#4) — UAT-only for now
**Option A:** a **before-save record-triggered Quote flow** firing when `Create_Order_from_Quote__c` changes to `true` (the exact, un-bypassable conversion insertion point — it intercepts the UI flow, the headless checkbox path, and Data Loader alike), raising a **friendly Custom Error**. Validate **ONLY the rep-entered fields** (`BillToContactId`, `ContactId`, `Bill_To_Place__c`, `Ship_To_Place__c`, and the Account `DB_DUNS__c`/`Phone`/`Type` prerequisites) — **never** the downstream auto fields (`Workday_*`, `Status`, `LineNumber`, tax). Keep all fields nillable. This mirrors the proven live pattern **`Fortra_Quote_Validate_Partner_Pricing_Model` v2 Active** (RecordBeforeSave with `customError`s) and the two new live VRs `Quote_BillToContactAcct_Equal_QuoteAcct` / `Quote_BillToPlacceAcct_Equal_QuoteAcct` (note the real `Placce` typo), which already implement the "custom error on a Quote relationship field, non-restrictive guidance" pattern. Keep the Order-side v13 flow as the downstream backstop for fields that don't exist until after conversion. (`13_`,`14_`)

> Regression guard for 7c: hard-requiring `BillToContactId`/`ContactId`/Place fields at SAVE time would break Quote-insert paths and the amendment/renewal auto-create flows — that is why the trigger is gated on the **conversion boundary** (`ISCHANGED(Create_Order_from_Quote__c) && =TRUE`), not on every Quote save. `QuoteToOrderFieldMapper.cls` (271 lines, bulk SOQL/DML) is the most field-sensitive surface; candidate Quote fields are referenced across `QuoteToOrderFieldMapper(.cls/Test)`, `OrderSubmissionValidator(.cls/Test)`, `FortraDemoDataFactory`. (`13_`)

---

## 8. Acceptance-criteria coverage

| # | Acceptance criterion | Deliverable | Prod-safe? | Status |
|---|---|---|:--:|---|
| AC1 | Documented inventory of every Quote→Order required field + the metadata enforcing each | §3 table + `10_`/CSV | n/a | **Done (this dossier)** |
| AC2 | Each required field has descriptive help text on the Quote | help text on 6 driver fields (`02_PHASE1…`) | ✅ | **✅ Deployed to UAT** |
| AC3 | Flow-based guidance modal lists all required fields, reachable from the Quote | `Review_Required_Fields` QA + `Fortra_Quote_Required_Fields_Check` screen flow, ✅/❌ rows incl. Account/Contact, on the Quote highlights panel (`03_PHASE2…`) | ✅ | **✅ Deployed to UAT** |
| AC4 | Converting/submitting a Quote with missing data is blocked with a clear, user-friendly message (no silent blockers) | **No new hard block** (decision 2026-06-12, `04_PHASE3…`). Satisfied by: existing v27 conversion flow's 10 validation gates (rep-controlled Quote fields) + the new modal (visibility incl. Account/Contact) + existing Order-Complete validator (UAT backstop). | existing conversion gate ✅ prod / Order-Complete backstop UAT-only | **✅ Met via existing layers + modal** |
| AC5 | No regressions in Apex/test/integration/flow | zero hard-requires; only `inlineHelpText` + a NEW read-only flow + action-list adds; do NOT deploy stale local flow; rerun `OrderSubmissionValidatorTest` + `QuoteToOrderFieldMapperTest` | ✅ | Phase 4 |

> **Note (2026-06-12 build update):** AC2/AC3 are built & deployed to **UAT**. AC4 was **descoped from a new blocking flow** — see `04_PHASE3_BLOCKING_DECISION.md`: the rep convert path calls `createOrderFromQuote` directly (not via `Create_Order_from_Quote__c`), the v27 conversion flow already blocks rep-controlled fields with clear screens, and forcing a hard block on Account/Contact fields would be over-restrictive. Phase logs: `02_`, `03_`, `04_`.

---

## 9. Risks & mitigations

- **Deploying the stale local flow regresses UAT** to the SC-3366 SOQL-governor bug. Mitigation: never deploy `force-app/.../Fortra_Order_Submission_Check.flow-meta.xml`; treat live v13 as source of truth.
- **Over-blocking from a blanket required-on-layout or unconditioned validation** — explicitly avoided by gating 7c on the conversion boundary and keeping fields nillable.
- **Account/Contact data ownership** — DUNS/Phone/Type/contact-name/Workday-device fields are often owned by other teams; the modal surfaces them early so reps can chase them before conversion rather than at Order-Complete.
- **`Ship_To_Account__c` silent hole** — `QuoteToOrderFieldMapper.cls:22-23` leaves it null when no `Ship_To_Place`; the conversion-boundary validation should require `Ship_To_Place__c` so the Order field hydrates.
- **Known unrelated mapper caveat** — `QuoteToOrderFieldMapper.cls:130-141` maps `Bill_To_Account__c ← Quote.AccountId` (SC-3339 rule), noted as wrong for ~36% partner-billing cases (SC-3339 scope, NOT SC-3338); left as-is here.
- **Source drift** — force-app is a sparse working set (2 flows; stale VR membership). Always verify against live before any deploy.

---

## 10. Open questions for Wren / team (UX review)

1. **AC4 prod scope:** ship the Quote blocker UAT-only now (matching the Order machinery) and promote later, or hold all of AC4 until SC-3291 machinery is promoted? (Recommended: UAT-only now; promote together.)
2. **Modal scope:** show the full readiness picture incl. all-team-owned Account/Contact fields, or only rep-actionable items? (Recommended: full, grouped by owner.)
3. **Help-text wording** for the 5 new fields — Wren to approve copy.
4. **Conversion-gate extension:** also extend the v27 conversion flow's per-field screens to cover Account/Contact prerequisites, or rely on the new before-save Quote flow? (Recommended: before-save flow, since it also catches the headless/Data-Loader paths.)

---

## 11. Drift discovered vs GROUND_TRUTH.md (live UAT wins)

| ID | GROUND_TRUTH said | Live UAT (2026-06-12) | Resolution |
|---|---|---|---|
| D1 | "Order VRs: none in force-app (verify live)" | **7 active Order VRs** (`Lock_Currency_At_Order_Activation` + 6 Bill/Ship account-equality) — *none* enforces required-field presence | Note is true for force-app (no Order VR dir) but live has 7; updated GT to say "7 live" so it doesn't imply zero enforcement |
| D2 | Quote VRs = 5 (Amendment_Requires_Contract, Enforce_Amendment_Sales_Restriction, Enforce_Discount_Cap, Require_Amendment_Reason, Sales_Cannot_Create_Downsell) | **4 active**: `Enforce_Amendment_Sales_Restriction`, `Sales_Cannot_Create_Downsell`, `Quote_BillToContactAcct_Equal_QuoteAcct`, `Quote_BillToPlacceAcct_Equal_QuoteAcct`. The 3 in GT (Amendment_Requires_Contract, Enforce_Discount_Cap, Require_Amendment_Reason) exist only in **stale force-app**, not live | GT line 49 corrected to the live 4-VR set |
| D3 | Contact `Workday_Customer_Id__c` (X00011/X00041) and OrderItem `ProductCode` (X00034) are valid rule fields | Both inactive AND absent from the SObject describe → validator's `fieldExists()` (`OrderSubmissionValidator.cls:297-303`) skips them. (`ProductCode` returns 1 `FieldDefinition` row but not in `describe().fields`.) | Inert regardless |
| D4 | local force-app submission flow = the active logic | local XML is STALE (calls `FieldPopulatedCheck`); live v13 calls `OrderSubmissionValidator` | Live wins; never deploy local flow |
| — | Claim-7 Account fill rates DUNS 67% / Type 56% | Not robust: larger 63-acct sample = DUNS 89% / Type 90% / Phone 78% | Restated qualitatively (§3) |

**Active flow versions recorded for durability (live UAT 2026-06-12):** `Fortra_Order_Submission_Check` **v13**, `Fortra_Quote_to_Order_Conversion` **v27**, `Fortra_Order_Workday_Contract_ID` **v3**, `Fortra_OrderItem_Set_Workday_Contract_Line_Type` **v11**.

---

## 12. Companion document index

| Doc | Contents |
|---|---|
| `10_REQUIRED_FIELD_INVENTORY.md` | Per-rule mdt walk-through, provenance split, fill-rate evidence, inactive-rule rationale |
| `11_QUOTE_UI_HELPTEXT_AUDIT.md` | Layout/FlexiPage analysis, help-text coverage, asterisk answer, guidance-capable surfaces |
| `12_CONVERSION_AND_ENFORCEMENT_PATH.md` | Convert→Order-Complete path, conversion-gate subset, bypass crux, downstream Workday |
| `13_VALIDATION_GAP_ANALYSIS.md` | Prod parity, no Quote-time validation, VR drift, regression surface, recommended backfill |
| `14_SOLUTION_DESIGN.md` | Help-text/modal/blocker design, deploy sequencing, no-regression plan |
| `Data/sc3338/GROUND_TRUTH.md` | Original verified facts (corrected per §11) |
| `Data/sc3338/PROD_PARITY_EVIDENCE.md` | Independent prod-vs-UAT parity check |
| `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` | Live 48-record mdt export (byte-matches org) |
