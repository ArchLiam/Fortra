# SC-3338 — Dimension D: Validation Enforcement Gap Analysis + Prod Parity

**Scope:** Acceptance Criterion #4 (confirm/backfill blocking validation) part 2, and AC #5 (no-regressions context).
**Date:** 2026-06-12. **Org of record:** FortraUAT (`liam.jeong.c@fortra.com.uat`). Parity org: FortraProd (`liam.jeong.c@fortra.com`). All live facts verified read-only; no deploys/DML.

> **Bottom line:** Enforcement of the "required-for-Order-Complete" data set exists, but it lives entirely on the **Order**, fires only when a rep clicks a single quick-action button ("Update Status" → `Fortra_Order_Submission_Check`), and is **completely absent from production**. The **Quote** has zero presence-validation for any of those fields. A rep can flip one checkbox (`Create_Order_from_Quote__c`) to mint an Order with missing data and never hit the validator. SC-3338's Quote-side work therefore cannot lean on the Order-side machinery in prod — it must stand on its own.

---

## 1. Every validation layer that blocks bad Quote/Order data (live UAT)

### 1a. Quote validation rules — DRIFT FROM GROUND_TRUTH / force-app

GROUND_TRUTH and `force-app/main/default/objects/Quote/validationRules/` list **5** rules. **Live UAT has only 4**, and the membership differs. Live wins.

| Rule (live UAT) | Active | In force-app? | Error condition (verified) | What it blocks |
|---|---|---|---|---|
| `Enforce_Amendment_Sales_Restriction` | true | Yes | `Quote_Type__c='Amendment' AND Within_Renewal_Window__c=TRUE AND NOT(reason Upsell/Cross-sell) AND NOT Customer Ops/Operations role` | Sales creating downsell/cancel amendments inside 120-day renewal window |
| `Sales_Cannot_Create_Downsell` | true | Yes | `Quote_Type__c='Amendment' AND reason in (Downsell, Full Cancellation) AND NOT Customer Ops/Operations role` | Sales creating downsell/full-cancel amendments at all |
| `Quote_BillToContactAcct_Equal_QuoteAcct` | true | **NO (live-only)** | `NOT(ISBLANK(BillToContact.AccountId)) AND BillToContact.AccountId != QuoteAccountId` | A Bill-To Contact whose Account ≠ Quote Account (integrity, not presence) |
| `Quote_BillToPlacceAcct_Equal_QuoteAcct` | true | **NO (live-only)** | `NOT(ISBLANK(Bill_To_Place__r.Account__c)) AND Bill_To_Place__r.Account__c != QuoteAccountId` | A Bill-To Place whose Account ≠ Quote Account (integrity, not presence) |

**In force-app but NOT deployed live (stale source):** `Amendment_Requires_Contract`, `Enforce_Discount_Cap`, `Require_Amendment_Reason`. These three are NOT enforced in UAT. (Live query `SELECT ValidationName FROM ValidationRule WHERE EntityDefinition.QualifiedApiName='Quote'` returns exactly the 4 above.)

force-app sources read: `force-app/main/default/objects/Quote/validationRules/Amendment_Requires_Contract.validationRule-meta.xml`, `…/Enforce_Amendment_Sales_Restriction.…`, `…/Enforce_Discount_Cap.…`, `…/Require_Amendment_Reason.…`, `…/Sales_Cannot_Create_Downsell.…`.
Live formulas extracted to `Data/sc3338/retrieve/vr_live/unpackaged/objects/Quote.object`.

**Key point:** None of the 4 live Quote VRs require any field for Order submission. Two are amendment-policy guards; two are Bill-To account-integrity guards that only fire when the field is **already populated** (`NOT(ISBLANK(...))` short-circuits when blank). **There is no Quote VR that blocks a blank required-for-submission field.**

### 1b. Order validation rules — DRIFT: GROUND_TRUTH said "none in force-app", live has 7 active

force-app has **no** `Order/validationRules/` directory. Live UAT has **7 active** Order VRs (none are presence requirements; all are integrity/lock guards). Formulas in `Data/sc3338/retrieve/vr_live/unpackaged/objects/Order.object`:

| Order VR (live) | Active | Condition (verified) | Blocks |
|---|---|---|---|
| `Lock_Currency_At_Order_Activation` | true | `ISCHANGED(CurrencyIsoCode) AND Status in (Activated/In Fulfillment/Fulfilled/Completed/Closed)` | Currency change after activation |
| `Order_BillToAddressAcct_Equal_OrderAcct` | true | `NOT(ISBLANK(Bill_To_Address__r.Account__c)) AND != AccountId` | Bill-To Address Account ≠ Order Account |
| `Order_BillToContactAcct_Equal_OrderAcct` | true | `NOT(ISBLANK(BillToContact.AccountId)) AND != AccountId` | Bill-To Contact Account ≠ Order Account |
| `Order_BillToPlaceAcct_Equal_OrderAcct` | true | `NOT(ISBLANK(Bill_To_Place__r.Account__c)) AND != AccountId` | Bill-To Place Account ≠ Order Account |
| `Order_ShipToAddressAcct_Equal_OrderAcct` | true | (Ship analog) | Ship-To Address Account ≠ Order Account |
| `Order_ShipToContactAcct_Equal_OrderAcct` | true | (Ship analog) | Ship-To Contact Account ≠ Order Account |
| `Order_ShipToPlaceAcct_Equal_OrderAcct` | true | (Ship analog) | Ship-To Place Account ≠ Order Account |

All seven are **integrity guards**, not presence guards. They fire only on a populated value (`NOT(ISBLANK)`). They never block a missing required field. They are the Order-side mirror of the 2 live Quote Bill-To VRs.

### 1c. OrderItem validation rules
**Zero** — neither in force-app (`force-app/main/default/objects/OrderItem/validationRules/` does not exist) nor live (`SELECT ... WHERE EntityDefinition.QualifiedApiName='OrderItem'` → COUNT 0). No OrderItem field is VR-enforced; the line-level requirements (`Billing_Frequency__c`, `Workday_Contract_Line_Type__c`, `TotalLineTaxAmount`, `LineNumber`) are enforced ONLY by the mdt/validator (see 1e).

### 1d. The screen-flow validation (the real "blocker") — and its bypass
- **`Fortra_Order_Submission_Check`** = screen flow, `processType=Flow`, `triggerType=None`, object=Order, 4 screens / 4 action calls (one is `OrderSubmissionValidator`). Source: `Data/sc3338/retrieve/flows_live/unpackaged/flows/Fortra_Order_Submission_Check.flow`. Active live (label "Fortra | Order | Submission Check").
- **Invocation:** it is launched **only** by the Order quick action `Order_Complete` (label "Update Status", `type=Flow`, `flowDefinition=Fortra_Order_Submission_Check`). Source: `Data/sc3338/retrieve/qa_live/unpackaged/quickActions/Order.Order_Complete.quickAction`.
- **Bypass:** Nothing forces a rep to click "Update Status." The validator runs only inside that button's flow. An Order can be created and left in any pre-Complete status indefinitely without the validator ever executing. There is **no record-triggered / before-save enforcement** of the required set on the Order — the only before-save Order flow is `Order_Before_Insert_Update_Sync_Status` (`RecordBeforeSave`, CreateAndUpdate, no customErrors; it syncs status, it does not validate presence). Source: `Data/sc3338/retrieve/flows_live/unpackaged/flows/Order_Before_Insert_Update_Sync_Status.flow`.

### 1e. The Apex validator + mdt (what the screen flow actually checks)
- **`OrderSubmissionValidator.cls`** (active) — `@InvocableMethod`, constant-SOQL, reads active `Order_Submit_Validation__mdt` rules and returns blank-field errors with record links. Boolean fields are treated as always-populated (`isValuePopulated` returns true for BOOLEAN: `force-app/main/default/classes/OrderSubmissionValidator.cls:258-259`). Blank `Error_Message__c` falls back to `'Required field is missing.'` (`OrderSubmissionValidator.cls:230`).
- **`Order_Submit_Validation__mdt`** — **48 records live, 25 Active** (verified `SELECT COUNT()`=48; CSV `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` parses to 25 active). Active set per GROUND_TRUTH §31 is correct.
- **`FieldPopulatedCheck.cls`** — still **Active** in UAT (live query returns it) but deprecated/uncalled by the active flow per SC-3366.

### 1f. Quote-side before-save / record-triggered flows
| Flow | Trigger | Validates presence? |
|---|---|---|
| `Fortra_Quote_Validate_Partner_Pricing_Model` | RecordBeforeSave (CreateAndUpdate), object Partner_Pricing_Model__c | Yes — has 2 `customErrors` (`Error_Billing_Partner_Required`, `Error_Invalid_PPM`). **This is the codebase's proven pattern for Quote-time blocking** (the build to copy). Source: `Data/sc3338/retrieve/flows_live/unpackaged/flows/Fortra_Quote_Validate_Partner_Pricing_Model.flow`. NB: triggers on Partner_Pricing_Model__c, not Quote. |
| `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` | RecordBeforeSave (CreateAndUpdate), object Quote | No customErrors / no presence validation (approval-criteria stamping only). |
| `Quote_After_Update_Create_Order_From_Quote` | **RecordAfterSave (Update), object Quote** | **No.** Entry filter = `Create_Order_from_Quote__c = true`. Sole action = standard RLM `createOrderFromQuote`. **No validation gate** — flipping the checkbox creates the Order regardless of data completeness. Source: `Data/sc3338/retrieve/flows_live/unpackaged/flows/Quote_After_Update_Create_Order_From_Quote.flow`. |

No before-save Quote flow blocks any of the Order-required fields.

---

## Coverage matrix: requirement → blocked? where? noticeable?

Provenance of each active Order-required field traced to its Quote source via `force-app/main/default/classes/QuoteToOrderFieldMapper.cls:19-27` (the SC-3339 mapper).

| Required field (active mdt) | Object | Quote-side source | Blocked at Quote-time? | Blocked at Order-time? | Where | Noticeable? |
|---|---|---|---|---|---|---|
| `Bill_To_Account__c` | Order | `Quote.AccountId` (mapper:19) | No | Yes (mdt X00024) | Submission-check flow only | Only on "Update Status" click |
| `Ship_To_Account__c` | Order | `Quote.Ship_To_Place__r.Account__c` (mapper:22, **left null when no Ship_To_Place**) | No | Yes (X00025) | Submission-check flow | Only on click; **silent null if Ship_To_Place blank** |
| `EffectiveDate` | Order | `Quote` start date / platform | No | Yes (X00028, **blank msg → generic fallback**) | Submission-check flow | Only on click; generic message |
| `Status` | Order | set by flow | n/a (system) | Yes (X00022) | Submission-check flow | system-set |
| `Workday_Contract_ID__c` | Order | auto (`Fortra_Order_Workday_Contract_ID` flow) | No (not a rep field) | Yes (X00021) | Submission-check flow | downstream auto |
| `WorkdayReferenceID__c` | Order | auto (legal-entity derived) | No | Yes (X00023) | Submission-check flow | downstream auto |
| `DB_DUNS__c`, `Name`, `Phone`, `Type` | Account | Quote.Account | No | Yes (X00002/3/1/4) | Submission-check flow | Only on click |
| `FirstName`,`LastName`,`Workday_MobilePhone_Device_Type__c`,`_Primary__c`,`_Usage_Type__c` (BillTo) | Contact | `Quote.BillToContactId` (mapper:26) | No | Yes (X00013/14/18/19/20) | Submission-check flow | Only on click |
| same 5 (ShipTo) | Contact | `Quote.ContactId` → Order.ShipToContactId (mapper:27) | No | Yes (X00036/37/42/43/44) | Submission-check flow | Only on click |
| `Billing_Frequency__c`,`Id`,`LineNumber`,`TotalLineTaxAmount`,`Workday_Contract_Line_Type__c` | OrderItem | QLI / downstream | No | Yes (X00031/32/29/33/30) | Submission-check flow | Only on click; mostly auto-populated |

Legend of "Quote-time": there is **no row** where a required field is blocked at Quote-time. Every block is Order-time, gated behind one button.

---

## 2. The HOLES (conditions NOT actually enforced, or only weakly)

| Hole | Severity | Detail / evidence |
|---|---|---|
| **H1 — No Quote-time presence validation at all** | High | None of the 4 live Quote VRs (1a) nor the 2 before-save Quote flows (1f) check any required-for-submission field for blank. A rep gets zero signal at the Quote. |
| **H2 — Conversion has no gate** | High | `Quote_After_Update_Create_Order_From_Quote` fires on `Create_Order_from_Quote__c=true` with no validation; sole action is RLM `createOrderFromQuote`. An incomplete Quote becomes an Order silently. |
| **H3 — The only real blocker is bypassable** | High | `OrderSubmissionValidator` runs ONLY inside the `Order_Complete`/"Update Status" quick-action flow. No record-triggered/before-save enforcement. An Order can persist with missing data until/unless someone clicks the button. |
| **H4 — Prod has nothing** | Critical | mdt object, submission-check flow, and both validator classes are **absent in FortraProd** (see §3). In prod there is currently **no presence enforcement anywhere** for the submission set. |
| **H5 — Ship_To_Account silently null** | Medium | `QuoteToOrderFieldMapper.cls:143-146` leaves `Order.Ship_To_Account__c` null when `Quote.Ship_To_Place__c` is blank. The mdt then flags it at Order-time (X00025), but the rep was never told on the Quote that Ship_To_Place drives it. Classic "un-noticeable blocker." |
| **H6 — Boolean rules can never block** | Low (latent) | `OrderSubmissionValidator` treats BOOLEAN as always-populated (`:258-259`). The inactive Places `Primary__c`/`Public__c` rules (X00008/46/07/47) would be **no-ops even if activated** — a checkbox is never "blank." Don't rely on them. |
| **H7 — EffectiveDate blank error message** | Low | mdt X00028 has an empty `Error_Message__c`. Not silent at runtime (validator substitutes "Required field is missing." at `:230`), but the message is non-specific — minor UX defect, not a true no-op. (Refines GROUND_TRUTH's "silent" framing.) |
| **H8 — Quote VR integrity guards short-circuit on blank** | Info | `Quote_BillToContactAcct…` / `…Place…` use `NOT(ISBLANK(...))`, so a **blank** Bill-To passes (only a *mismatched* one is blocked). They enforce correctness, never presence. |

**Enforced only by the bypassable screen flow:** every Account/Contact/Order/OrderItem field in the active mdt set (all 25 active rules). **Silent/no-op behavior:** H5 (Ship_To_Account null carry), H6 (Boolean rules), H7 (blank-message → generic).

---

## 3. PROD vs UAT parity — VERIFIED (memory confirmed)

Memory (SC-3291) said the whole Order-submission machinery is UAT-only and must not go to prod (user, 2026-06-01). **Verified live against FortraProd, all three components absent:**

| Component | FortraUAT | FortraProd | Evidence |
|---|---|---|---|
| `Order_Submit_Validation__mdt` | 48 records | **Object does not exist** | UAT `SELECT COUNT()`=48; Prod query → `sObject type 'Order_Submit_Validation__mdt' is not supported`; `sf sobject describe … --target-org FortraProd` → "The requested resource does not exist" |
| `Fortra_Order_Submission_Check` flow | Active | **0 records** | UAT Active; Prod `SELECT … FROM Flow WHERE Definition.DeveloperName='Fortra_Order_Submission_Check'` → 0 |
| `OrderSubmissionValidator.cls` | present | **0 records** | UAT present; Prod `SELECT … FROM ApexClass WHERE Name IN (...)` → 0 |
| `FieldPopulatedCheck.cls` | present (Active) | **0 records** | same query → 0 |

**Parity gap (precise):** In production there is currently **no presence-validation layer** for the Quote→Order required-data set — no mdt, no validator, no submission-check flow. The Order integrity VRs (the 7 in §1b) and the Quote VRs (§1a) *may* exist in prod independently (not separately verified here for the integrity set; they are standard non-managed VRs), but they enforce **correctness, not presence**.

**Governing consequence for SC-3338:** the Quote-side deliverables **cannot delegate blocking to the Order-side validator in prod** — it isn't there. Any "confirmed blocking validation" (AC #4) that must work in prod has to be built as Quote-native metadata (VR or before-save flow customError) that ships to prod on its own. Re-deploying the Order machinery to prod is **explicitly out of bounds** (user, 2026-06-01). So the backfill must be Quote-side and prod-deployable.

---

## 4. Regression surface for any field-level change (grep of `force-app/main/default`)

Per AC #5 (no regressions) and the ticket's explicit warning against hard-requiring fields.

| Candidate Quote field | total files | Apex | flows | Key referencing Apex/test/integration |
|---|---|---|---|---|
| `Bill_To_Place__c` | 5 | 3 | 0 | `QuoteToOrderFieldMapper.cls`, `QuoteToOrderFieldMapperTest.cls`, `OrderSubmissionValidator.cls` |
| `Ship_To_Place__c` | 5 | 3 | 0 | same trio |
| `BillToContactId` | 16 | 4 | 1 | `QuoteToOrderFieldMapper(.cls/Test)`, `OrderSubmissionValidator(.cls/Test)`, `FortraDemoDataFactory.cls` + 1 flow |
| `ShipToContactId` | 15 | 4 | 1 | same set |
| `EffectiveDate` | 5 | 3 | 0 | mapper + validator family |
| `Quote_Type__c` | 10 | 1 | 0 | amendment VRs/flows + 1 Apex |
| `Amendment_Reason__c` | 4 | 0 | 0 | amendment VRs only |
| `Renewal_Contract__c` | 3 | 0 | 0 | amendment VRs |
| `Create_Order_from_Quote__c` | 1 | 0 | 0 | field def only (flow lives in managed/UAT, not force-app) |

**Most regression-sensitive class:** `QuoteToOrderFieldMapper.cls` (271 lines) — bulk SOQL/DML mapper that reads `Quote.AccountId`, `Quote.Bill_To_Place__c`, `Quote.Ship_To_Place__c`, `Quote.BillToContactId`, `Quote.ContactId` and writes the Order Bill/Ship fields (`:115-174`). Test: `QuoteToOrderFieldMapperTest.cls`. Any change to these Quote fields' shape/requiredness must keep this mapper green.

**Assessment of the "do not hard-require" warning (AC #2):** The ticket's caution is **correct and must be honored**:
- Hard-requiring (nillable=false / Required-on-layout) `BillToContactId`/`ShipToContactId`/Place fields would break **insert/update paths in 4+ Apex classes and their tests** that create Quotes without those fields (e.g., `FortraDemoDataFactory`, mapper tests), and would block the amendment/renewal auto-creation flows (`Fortra_Create_Amendment_Quote`, `Fortra_Create_Renewal_Quote`) that insert Quotes programmatically before Bill/Ship is set.
- Many "required" fields in the active set are **auto-populated downstream, not rep-entered** (Workday_* on Order/Contact, `Status`, `LineNumber`, `TotalLineTaxAmount`, `Workday_Contract_Line_Type__c`). Hard-requiring them on the Quote is semantically wrong — they don't exist yet at Quote time.
- A field-level `required=true` on the Quote layout also can't express the **conditional** nature (e.g., Ship-To only matters for physical-ship lines), producing false blocks.

Conclusion: do **not** convert any field to hard-required. Use conditional, message-bearing validation instead (§5).

---

## 5. Recommended validation BACKFILL (recommendation only; detailed build → Dimension E)

Given the gaps, the minimal, non-restrictive, **prod-deployable, Quote-native** backfill:

1. **Primary lever — one Quote before-save record-triggered flow** (`RecordBeforeSave`, Create/Update, object Quote) that fires its `customError` **only at the conversion boundary** — i.e., gated on `ISCHANGED(Create_Order_from_Quote__c) && Create_Order_from_Quote__c = TRUE` (and/or a "Presented"/submit status). This blocks conversion with a clear, field-anchored message listing the missing rep-entered fields, mirroring the proven `Fortra_Quote_Validate_Partner_Pricing_Model` customError pattern. It fires at the **right time** (the moment the rep tries to convert), not late on the Order, and never blocks ordinary Quote saves/drafts.
   - Validate ONLY the **rep-entered** subset that maps to active Order rules: `BillToContactId`, `ContactId`(→ShipTo), `Bill_To_Place__c`, `Ship_To_Place__c`, and the Account's `DB_DUNS__c`/`Phone`/`Type` (via lookup). Do **not** validate downstream auto fields (Workday_*, Status, LineNumber, tax) — those aren't the rep's to fill at Quote time.
2. **Do not hard-require any field** (§4). No layout `required=true`, no `nillable=false`.
3. **Alternative/secondary** — equivalent conditional Quote **validation rules** keyed on the same conversion trigger, if a flow is undesirable; same field scope, same "only when converting" gating. (Flow is preferred: it can list multiple missing fields in one message and is easier to extend.)
4. **Visibility companions (AC #2/#3, separate from blocking):** add `inlineHelpText` to the rep-entered required Quote fields (force-app currently has help text on only **37 of 182** Quote field defs) and ship the Flow guidance modal — these make the requirement noticeable *before* the block fires.
5. **Prod scope:** everything in (1)/(3)/(4) is Quote-native and ships to prod independently of the prohibited Order machinery, satisfying AC #4's "blocked with a clear message" in prod without violating the 2026-06-01 do-not-deploy directive.

Hand off the exact flow elements, error text, conditional logic, and the rep-entered field list to **Dimension E**.

---

## Drift flagged vs GROUND_TRUTH.md (live UAT wins)

1. **Quote VRs:** GROUND_TRUTH/force-app list **5**; live UAT has **4**, and 2 of those (`Quote_BillToContactAcct_Equal_QuoteAcct`, `Quote_BillToPlacceAcct_Equal_QuoteAcct`) are **not in force-app**, while 3 force-app rules (`Amendment_Requires_Contract`, `Enforce_Discount_Cap`, `Require_Amendment_Reason`) are **not deployed live**. force-app is stale.
2. **Order VRs:** GROUND_TRUTH says "none in force-app (verify live)." Confirmed none in force-app, but live UAT has **7 active** Order VRs (integrity/lock guards, not presence). Documented above.
3. **EffectiveDate "silent" risk:** the blank `Error_Message__c` (X00028) is NOT silent at runtime — `OrderSubmissionValidator.cls:230` substitutes a generic message. It's a wording defect, not a no-op. Reclassified as Low (H7).
4. **`FieldPopulatedCheck.cls`:** GROUND_TRUTH calls it deprecated/uncalled; live UAT still has it **Active** (deployed but not invoked by the active flow). Both true; noted for completeness.
5. **Help-text count:** GROUND_TRUTH cites 36/237 (live describe); force-app field defs show **37/182** with inlineHelpText. Counts differ because force-app has fewer field files than the 237 live fields; both confirm sparse coverage.
