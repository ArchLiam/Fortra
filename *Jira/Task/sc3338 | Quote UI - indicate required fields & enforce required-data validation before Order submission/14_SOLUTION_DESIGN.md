# SC-3338 — Dimension E: Solution Design & Build Plan

**Scope:** the concrete, low-lift, best-practice build for Acceptance Criteria #2 (help text), #3 (Flow guidance modal), #5 (no regressions) — plus the blocking-validation confirmation (AC #4), deploy strategy, and the Wren UX review.

**Evidence base:** verified live against `FortraUAT` and `FortraProd` on 2026-06-12. Where live state differs from `Data/sc3338/GROUND_TRUTH.md`, the drift is flagged in §0. Live wins.

---

## 0. Drift discovered vs GROUND_TRUTH.md (live UAT, 2026-06-12)

| # | GROUND_TRUTH says | Live UAT actually | Impact on this design |
|---|---|---|---|
| D1 | Local `Fortra_Order_Submission_Check.flow-meta.xml` = v13 calling `OrderSubmissionValidator` | **Local force-app copy is STALE.** It is the pre-v13 design (per-field `FieldPopulatedCheck` loop; screens `BillShipTo_Validation_Screen` absent). The **LIVE v13** (retrieved fresh to `/tmp/sc3338_flow`) calls the single `OrderSubmissionValidator` Apex action and has screens `[BillShipTo_Validation_Screen, Error_Screen, Status_Selection, Validation_Error_Screen]`. | Design must target the **live v13** flow, not the local source. Any redeploy of the local flow would REGRESS UAT to the SOQL-governor bug (SC-3366). Do **not** deploy the local flow. |
| D2 | Quote VRs (5): `Amendment_Requires_Contract`, `Enforce_Amendment_Sales_Restriction`, `Enforce_Discount_Cap`, `Require_Amendment_Reason`, `Sales_Cannot_Create_Downsell` | Live **active** Quote VRs (4): `Enforce_Amendment_Sales_Restriction`, `Sales_Cannot_Create_Downsell`, **`Quote_BillToContactAcct_Equal_QuoteAcct`**, **`Quote_BillToPlacceAcct_Equal_QuoteAcct`** | Two **new** Bill-To relationship VRs already exist and already use the exact "custom error on a Quote field with non-restrictive guidance" pattern this design recommends (§3). They govern fields the conversion mapper depends on. Reuse the pattern; do not duplicate them. |
| D3 | Order submission machinery "absent from prod — CONFIRM" | **CONFIRMED ABSENT in prod.** `ApexClass OrderSubmissionValidator` = 0 rows, `EntityDefinition Order_Submit_Validation__mdt` = 0 rows, `Flow Fortra_Order_Submission_Check` = 0 rows in `FortraProd`. | Hard-locks the deploy strategy (§5): the blocking layer that depends on this machinery is UAT-only; help text + guidance modal are the only prod-safe deliverables. |
| D4 | (not stated) | Conversion is driven by **`Quote.Create_Order_from_Quote__c = TRUE`** on an after-save update-triggered flow `Quote_After_Update_Create_Order_From_Quote` (v2, Active) → `createOrderFromQuote`. Rep-facing launcher = Quote quick action **`Convert_Quote_to_Order`** (Type=Flow) + screen flow `Fortra_Quote_to_Order_Conversion` (v27, Active). | This is the **exact insertion point** for a non-bypassable Quote-time blocker (§3) and the natural sibling launch point for the guidance modal (§2). |

**Verification commands (re-runnable):**
- `sf data query --target-org FortraUAT --use-tooling-api -q "SELECT VersionNumber, Status FROM Flow WHERE Definition.DeveloperName='Fortra_Order_Submission_Check' ORDER BY VersionNumber DESC"` → v13 Active, all prior Obsolete.
- `sf data query --target-org FortraProd --use-tooling-api -q "SELECT Name FROM ApexClass WHERE Name='OrderSubmissionValidator'"` → 0 rows.

---

## 1. HELP TEXT plan (AC #2) — field-by-field on the Quote

### 1.1 Which fields get help text

The Order-submission required set spans Account/Contact/Order/OrderItem fields (`Order_Submit_Validation_LIVE.csv`). **Most are NOT user-entered on the Quote** — they are either auto-populated downstream (all `Workday_*`, `WorkdayReferenceID__c`, `Workday_Contract_ID__c`, `TotalLineTaxAmount`, `LineNumber`, OrderItem `Id`, `Billing_Frequency__c`) or live on the Account/Contact (`DB_DUNS__c`, `Phone`, `Type`, contact `FirstName`/`LastName`/`Workday_MobilePhone_*`). Help text on the **Quote** can only target the **rep-controlled Quote fields that DRIVE the required Order data through conversion.**

The conversion mapping is the authority (`force-app/main/default/classes/QuoteToOrderFieldMapper.cls:13-31`):

```
Order.Bill_To_Account__c  ← Quote.AccountId
Order.Ship_To_Account__c  ← Quote.Ship_To_Place__r.Account__c
Order.Bill_To_Address__c  ← Quote.Bill_To_Place__c
Order.Ship_To_Address__c  ← Quote.Ship_To_Place__c
Order.BillToContactId     ← Quote.BillToContactId
Order.ShipToContactId     ← Quote.ContactId
```

So the **Quote user-entered driver fields** are: `AccountId`, `BillToContactId`, `ContactId`, `Bill_To_Place__c`, `Ship_To_Place__c`, plus `StartDate` (→ Order `EffectiveDate`, platform default) and `Status`.

### 1.2 Field-by-field help-text table

`help=Y` rows already have text (verified from `Data/sc3338/retrieve/Quote_describe.json`) — **do not disturb** them. `help=–` rows are the gap to fill.

| Quote field | Drives (Order/related) | Has help today? | Action | Proposed `inlineHelpText` |
|---|---|---|---|---|
| `AccountId` (Account Name) | `Order.Bill_To_Account__c`; Account `Name`/`Phone`/`Type`/`DB_DUNS__c` resolve from here | – (`createable=false`) | **Display only** — not directly editable on Quote (set at create). Add no field help; cover in the modal instead. | n/a |
| `BillToContactId` (Bill To Contact) | `Order.BillToContactId`; that Contact's `FirstName`/`LastName`/`Workday_MobilePhone_*` | – | **ADD** | `Select the Bill To contact. Required to complete the Order — this contact's First/Last Name and Workday mobile-phone details must be filled in before the Order can be submitted to Workday. Pick a contact related to this Quote's Account.` |
| `ContactId` (Quote Contact) | `Order.ShipToContactId` (per mapper) | Y ("This is the Fortra Quote Contact.") | **REPLACE** — current text doesn't convey it becomes the Ship-To contact and is required. | `This is the Fortra Quote Contact and becomes the Order's Ship To contact. Required for Order submission — its First/Last Name and Workday mobile-phone details must be populated.` |
| `Bill_To_Place__c` (Bill To Place) | `Order.Bill_To_Address__c` | Y ("Select the place where invoices should be sent for this quote") | **KEEP, light append** | `Select the place where invoices should be sent for this quote. Becomes the Order's Bill To Address and is required to submit the Order.` |
| `Ship_To_Place__c` (Ship To Place) | `Order.Ship_To_Address__c` and `Order.Ship_To_Account__c` (via its Account) | Y ("Select the place where products should be delivered") | **KEEP, light append** | `Select the place where products should be delivered. Becomes the Order's Ship To Address, and its Account becomes the Ship To Account — both required to submit the Order.` |
| `StartDate` | `Order.EffectiveDate` (required) | – | **ADD** | `Quote start date. Carries to the Order's Start Date (Effective Date), which is required to submit the Order.` |
| `Status` | gates conversion | – | **ADD** | `Quote status. The Order is created automatically once the Quote is converted; check the Required Fields guidance before converting.` |

> Account- and Contact-resident fields (`DB_DUNS__c`, `Phone`, `Type`, contact `FirstName`/`LastName`/`Workday_MobilePhone_Device_Type__c`/`_Primary__c`/`_Usage_Type__c`) cannot get **Quote** help text — they are not Quote fields. They are surfaced to the rep through the **guidance modal** (§2), which is exactly why the ticket asks for the modal in addition to help text. (Optionally, a parallel help-text pass on the **Account/Contact** layouts is a stretch deliverable, not in SC-3338 scope.)

### 1.3 Mechanism + deploy

- Help text lives on the field, not the layout: `CustomField.inlineHelpText` in `force-app/main/default/objects/Quote/fields/<Field>__c.field-meta.xml` (and the standard-field overrides for `BillToContactId`, `ContactId`, `StartDate`, `Status`).
- Deploy with a targeted source deploy of only those `CustomField` components, e.g. `sf project deploy start --target-org <org> --metadata "CustomField:Quote.BillToContactId" "CustomField:Quote.ContactId" ...`.
- Help text renders on both the read view and edit modal automatically once the field is on the page layout / Dynamic Form (all listed fields already are, per the 128-item Quote layout in GROUND_TRUTH). No layout change required.
- **Prod-safe** (see §5): pure UX metadata, no dependency on the UAT-only machinery. The two standard-field overrides and the `__c` field help texts deploy cleanly to prod since those Quote fields exist there.

---

## 2. FLOW GUIDANCE MODAL design (AC #3) — chosen over LWC

### 2.1 Decision: Flow, and a **Quote-side analog reading the live Quote**, not the Order validator

- **Flow over LWC** — per the ticket, for maintainability/consistency. It matches the house style already in play: the Order side uses screen flows surfaced as quick actions (`Order_Complete`, `Send_to_Workday` — both Type=Flow), and the Quote already has screen-flow quick actions (`Convert_Quote_to_Order`, `Import_Quote_Line`, `Submit_Approval`). A flow is declarative, admin-maintainable, and needs no Apex/Jest test debt.
- **Build a Quote-side analog; do NOT reuse `OrderSubmissionValidator` here.** The Apex validator (`OrderSubmissionValidator.cls`) is keyed entirely on an **Order Id** — it queries `Order`, `OrderItem`, and Order-FK-resolved related records. At Quote time **there is no Order yet** (it is created by `createOrderFromQuote` only after `Create_Order_from_Quote__c=true`). Reusing it post-conversion would defeat the ticket's intent of pre-conversion visibility. The modal therefore reads the **live Quote + its related Account/Contacts/Places** and shows ✔/✘ per requirement. It deliberately **mirrors the validator's "is populated" semantics** (text non-blank, references non-null) so the Quote checklist and the Order blocker agree.

### 2.2 Launch point

- **Quote record page quick action**, Type=Flow, named **`Review_Required_Fields`** (label: "Required Fields Check"), added to the Quote highlights-panel actions next to the existing `Convert_Quote_to_Order` action. Reachable from the Quote, one click, no navigation away.
- Alternative/secondary surface: a **Flow component on the Quote Lightning record page (FlexiPage)** in a collapsed accordion section "Order Readiness." Either is acceptable; the quick action is the lighter lift and matches the requested "reachable from the Quote."
- Input: `recordId` (the Quote Id; auto-bound for record-page actions / FlexiPage flow component).

### 2.3 Screen content (grouped by what the rep controls)

A single read-only screen, three groups, each a checklist line with a ✔ (green) / ✘ (red) status and a short "where to fix" hint. The rep-control grouping comes straight from the required-field inventory:

- **Group A — On this Quote (you set these directly):** Bill To Contact, Ship To Contact (Quote Contact), Bill To Place, Ship To Place, Start Date.
- **Group B — On the Customer Account (open the Account to fix):** Account Name, Phone, Type, D&B DUNS.
- **Group C — On the Bill To / Ship To Contacts (open the Contact to fix):** First Name, Last Name, Workday MobilePhone Device Type, Workday MobilePhone Primary, Workday MobilePhone Usage Type.
- A footer note: "Fields like Tax, Line Numbers and Workday IDs are filled in automatically when the Order is created — you don't need to enter them."

### 2.4 Can it show live ✔/✘? Yes — here is how

The flow reads live records and computes status with **declarative formulas** (no Apex), keeping it admin-maintainable:

- `Get Records` the Quote with the driver fields and the relationship fields needed: `AccountId`, `Account.Name`, `Account.Phone`, `Account.Type`, `Account.DB_DUNS__c`, `BillToContactId`, `BillToContact.FirstName/.LastName/.Workday_MobilePhone_Device_Type__c/.Workday_MobilePhone_Primary__c/.Workday_MobilePhone_Usage_Type__c`, `ContactId` (+ same Contact subfields), `Bill_To_Place__c`, `Ship_To_Place__c`, `Ship_To_Place__r.Account__c`, `StartDate`. (Cross-object refs are reachable in one `Get Records` because they are lookups on the Quote.)
- One **Text formula per requirement** returns `✔` or `✘`, e.g. `IF(NOT(ISBLANK({!Get_Quote.BillToContact.FirstName})), "✔", "✘")`. Boolean/blank semantics mirror `OrderSubmissionValidator.isValuePopulated` (`OrderSubmissionValidator.cls:253-265`) for consistency.
- A roll-up `All_Ready` formula = AND of the individual checks, used to color the header ("Ready to convert" vs "Action needed").

### 2.5 Build-ready element outline

```
START (screen flow, input: recordId)
  └─ Get_Quote  (Get Records, Quote where Id = recordId, first only,
                 with the cross-object fields in §2.4)
       └─ [Formulas, no element] cBillToContact, cShipToContact, cBillToPlace,
            cShipToPlace, cStartDate,
            cAcctName, cAcctPhone, cAcctType, cAcctDuns,
            cBTFirst, cBTLast, cBTDevType, cBTPrimary, cBTUsage,
            cSTFirst, cSTLast, cSTDevType, cSTPrimary, cSTUsage,
            fAllReady (AND of all)
       └─ Screen: Required_Fields_Checklist
            • DisplayText header  (rich text, green/red driven by {!fAllReady})
            • Section "On this Quote"      → lines using {!cBillToContact} … {!cStartDate}
            • Section "On the Account"     → {!cAcctName} … {!cAcctDuns}, w/ link to Account
            • Section "On the Contacts"    → {!cBTFirst} … {!cSTUsage}, w/ links to each Contact
            • DisplayText footer (auto-populated fields note)
            • Finish button "Close"
  (No record writes. Read-only, idempotent, safe to run any number of times.)
```

- Optional convenience: a second screen branch that, when `fAllReady = true`, offers a "Convert now" button that sets `Create_Order_from_Quote__c = true` (one `Update Records`). Keep this **out of v1** to preserve strict read-only/no-side-effect simplicity unless Wren wants it.

### 2.6 Reuse of the OrderSubmissionValidator pattern, post-conversion

- **Pre-conversion (Quote):** the Quote-side analog above (declarative, no Order needed).
- **Post-conversion (Order):** the existing live v13 `Fortra_Order_Submission_Check` + `OrderSubmissionValidator` already covers it. No change. The two checklists intentionally agree on the same required set so the rep never hits a surprise at the Order.

---

## 3. BLOCKING VALIDATION recommendation (AC #4)

### 3.1 Options compared

| Option | Where it fires | Blocks conversion? | Non-restrictive msg? | Hard-requires fields? | Verdict |
|---|---|---|---|---|---|
| **A. Quote before-save record-triggered flow with custom error**, entry = `Create_Order_from_Quote__c` changed to `true` | Quote save, the instant the rep triggers conversion | **Yes** — `addError` rolls back the save before the after-save `Quote_After_Update_Create_Order_From_Quote` can fire `createOrderFromQuote` | Yes — custom error string, field-level | **No** — fields stay nillable; only the conversion attempt is gated | **RECOMMENDED** |
| B. Validation Rule on Quote, condition `ISCHANGED(Create_Order_from_Quote__c) && Create_Order_from_Quote__c && (<any driver blank>)` | Quote save | Yes | Yes (VR error) | No | Viable, but one giant boolean formula is harder to maintain and gives one lumped message vs per-field. Use **only** if flows are discouraged. |
| C. Check inside the `Convert_Quote_to_Order` screen flow (decision → error screen) | Convert action only | Only if the rep uses that action | Yes | No | **Bypassable** — `Create_Order_from_Quote__c` can be set by other automation/data load, skipping the screen flow. Rejected as the sole guard. |
| D. Keep relying on the Order-side `Fortra_Order_Submission_Check` and make it un-bypassable | Order, at status→Order Complete | Yes (already) | Yes (already) | No | Already in place; it's the *late* "un-noticeable blocker" the ticket is reacting to. Keep as the safety net, but it does not satisfy "blocked at the Quote with a clear message." |

### 3.2 Recommendation — Option A (with D retained as backstop)

Build a **before-save record-triggered flow on Quote**, `Fortra_Quote_Block_Conversion_When_Incomplete`:

- **Entry conditions:** `recordTriggerType=Update`, before-save, fires only when `Create_Order_from_Quote__c` **changed to true** (`ISCHANGED` + `=true`). This is the same field/flag the live `Quote_After_Update_Create_Order_From_Quote` keys on (D4), so it intercepts every conversion path, including data-load/API — un-bypassable, satisfying the ticket's "no silent blockers."
- **Logic:** evaluate the same Group-A/B/C requirements as the modal (driver fields + related Account/Contact). Because before-save flows can't traverse to *new* related queries cheaply, do the cross-object reads with formula references on the triggering record's lookups (Quote→Account, Quote→Contacts are direct lookups, available in `$Record`).
- **Block:** a single `Custom Error` (Core action `addRecordError` / "Custom Error" element) with a friendly, itemized message, e.g.:

  > *"Almost there — a few fields are needed before this Quote can become an Order. Please complete: Bill To Contact name & Workday mobile details, Ship To Contact name & Workday mobile details, Account Phone/Type/DUNS. Open the **Required Fields Check** action for the full list and quick links."*

  Note it points the rep at the §2 modal — help text, modal, and blocker reinforce each other.
- **Keep restrictive language out:** message is guidance-toned ("Almost there… Please complete"), never "ERROR: field X is mandatory." Mirrors the tone of the live `Quote_BillToContactAcct_Equal_QuoteAcct` VR ("Select a Bill To Contact that is related to this Quote's Account.").

This blocks at the **Quote** (early, clear, with the modal as the fix-it companion) while the existing Order-side v13 flow (Option D) remains the final backstop for the downstream-populated fields (`Workday_Contract_ID__c`, `TotalLineTaxAmount`, etc.) that genuinely don't exist until after conversion.

### 3.3 Pattern precedent (don't reinvent)

The two live VRs `Quote_BillToContactAcct_Equal_QuoteAcct` and `Quote_BillToPlacceAcct_Equal_QuoteAcct` already implement exactly this "custom error on a Quote relationship field, non-restrictive guidance" pattern (D2). The new flow extends that established pattern to the conversion gate; reviewers will recognize it.

---

## 4. NO-REGRESSION plan (AC #5)

### 4.1 Explicitly avoid hard-required changes
- **No** `nillable=false`, **no** layout `behavior=Required`, **no** `required=true` on any field-meta. The Quote keeps `Name` as its only hard-required field (GROUND_TRUTH §Quote side). Visibility/guidance only.
- Help-text edits touch only `inlineHelpText` — a non-functional attribute; cannot break Apex/flow/integration.

### 4.2 Dependency scan (run before/after)
- Apex referencing the validator stack: `grep -rl "OrderSubmissionValidator\|FieldPopulatedCheck"` → only the classes themselves + the (stale) local flow. The new build adds **no** Apex, so the existing classes are untouched.
- Flow referencing the conversion flag: `Quote_After_Update_Create_Order_From_Quote` (after-save) keys on `Create_Order_from_Quote__c`. The new **before-save** flow runs in the same save transaction *before* it; confirm ordering with a UAT smoke test (set flag true on a complete vs incomplete Quote; complete should convert, incomplete should error and not create an Order).
- Confirm the new before-save flow does not collide with existing Quote before-save automation: live active Quote autolaunched flows are listed in the inventory; none are before-save guards on the conversion flag today, so there is no pre-existing flow to conflict with.

### 4.3 Tests to run (UAT)
- `sf apex run test --target-org FortraUAT --class-names OrderSubmissionValidatorTest QuoteToOrderFieldMapperTest --result-format human` — must stay green; neither class is modified, so this is a guard that the surrounding metadata changes didn't disturb compile/coverage. (`OrderSubmissionValidatorTest.cls` asserts constant-SOQL bulk safety; `QuoteToOrderFieldMapperTest.cls` asserts the carryover mapping the modal/blocker rely on.)
- Manual E2E in UAT: (a) incomplete Quote → run `Review_Required_Fields` modal → see ✘ list → attempt convert → blocked with friendly message; (b) complete the fields → modal all ✔ → convert succeeds → Order created → run `Order_Complete` action → passes the v13 submission check.
- **Do not deploy the stale local `Fortra_Order_Submission_Check.flow-meta.xml`** (D1) — it would regress UAT to the SOQL-governor defect (SC-3366). If a flow deploy is unavoidable, re-retrieve the live v13 first and deploy that.

---

## 5. DEPLOY STRATEGY (UAT vs prod)

Driven by D3 (machinery confirmed absent in prod) and the standing constraint "do NOT deploy SC-3291/Order-submission artifacts to prod" (2026-06-01, memory `project_sc3291_validation_uat_only`).

| Deliverable | Depends on UAT-only machinery? | Prod-safe? | Sequence |
|---|---|---|---|
| Quote field help text (§1) | No | **Yes** | Deploy to UAT first, then prod after Wren sign-off. Pure `CustomField.inlineHelpText`. |
| Flow guidance modal `Review_Required_Fields` + quick action (§2) | No — reads only Quote/Account/Contact/Place, all of which exist in prod | **Yes** | Deploy to UAT; prod-eligible. It references no `Order_Submit_Validation__mdt`, no `OrderSubmissionValidator`. (Confirm the Place fields it reads exist in prod before promoting.) |
| Quote before-save blocking flow `Fortra_Quote_Block_Conversion_When_Incomplete` (§3) | Partially — it gates `Create_Order_from_Quote__c`, which exists in prod, but the **downstream Order submission flow it complements is UAT-only** | **UAT-only for now** | Deploy + validate in UAT only. Promote to prod **only as part of the broader SC-3291/Order-submission prod rollout**, so Quote-time and Order-time enforcement land together and stay consistent. Do not ship the Quote blocker to prod ahead of the Order machinery. |
| (Do NOT touch) local stale `Fortra_Order_Submission_Check.flow` | n/a | n/a | Leave alone; never deploy. Re-retrieve live v13 if the file is ever needed. |

**Net:** ship help text + modal as prod-safe UX now (after Wren review). Hold the blocking flow in UAT until the Order-side machinery is itself promoted to prod.

---

## 6. UX review with Wren — talking points

1. **Two-layer model:** *visibility* (help text + Required Fields Check modal) vs *enforcement* (Quote-time block + Order-time backstop). Confirm Wren wants the asterisk-equivalent delivered as the modal checklist rather than red asterisks (we are deliberately NOT hard-requiring fields — that's the regression Jomil/the ticket warns against).
2. **Grouping by rep control** (On this Quote / On the Account / On the Contacts) — does this match how reps think? Validate the wording of the three section headers and the "auto-populated, no action needed" footer.
3. **Where the modal lives:** quick action on the Quote highlights panel next to "Convert Quote to Order" vs an accordion on the record page. Get Wren's pick.
4. **Message tone:** review the blocker copy ("Almost there — a few fields are needed…") for non-restrictive, guidance-first voice; confirm it points to the modal.
5. **Scope boundary:** Account/Contact-resident fields can't get Quote help text — confirm the modal (with quick links to the Account/Contact) is an acceptable substitute, or whether a stretch help-text pass on Account/Contact layouts is wanted.
6. **Prod timing:** help text + modal can ship to prod soon; the Quote blocker waits for the Order machinery's prod rollout. Confirm that staging is acceptable to Wren/Jomil.

### Acceptance-criteria coverage checklist

| AC | Deliverable in this design | Section |
|---|---|---|
| Documented inventory of required fields + enforcing metadata | Dimensions A–D (inventory) consumed here; conversion mapping + live mdt cited | §1.1, §0 |
| Each required (user-entered) field has descriptive help text on the Quote | Field-by-field help-text table; KEEP existing, ADD/REPLACE the gaps | §1.2–1.3 |
| Flow-based guidance modal lists all required fields, reachable from the Quote | `Review_Required_Fields` screen flow + Quote quick action, live ✔/✘ | §2 |
| Converting a Quote with missing data is blocked with a clear, friendly message | `Fortra_Quote_Block_Conversion_When_Incomplete` before-save flow, custom error on the `Create_Order_from_Quote__c` gate; Order-side v13 retained as backstop | §3 |
| No regressions in Apex/test/integration/flow | No hard-required changes; dependency scan; run `OrderSubmissionValidatorTest` + `QuoteToOrderFieldMapperTest`; do-not-deploy stale flow | §4 |
| UX review with Wren before build | Talking points 1–6 | §6 |

---

## Appendix — key file/line citations

- Conversion field mapping (authority for "which Quote fields drive the required Order data"): `force-app/main/default/classes/QuoteToOrderFieldMapper.cls:13-31`.
- "Is populated" semantics the modal must mirror: `force-app/main/default/classes/OrderSubmissionValidator.cls:253-265`.
- Live v13 submission flow structure (Apex action + screens), retrieved fresh: `/tmp/sc3338_flow/extracted/unpackaged/flows/Fortra_Order_Submission_Check.flow:90-109` (`OrderSubmissionValidator` action), `:405-526` (the four screens).
- Conversion trigger flag `Create_Order_from_Quote__c = true`: live flow `Quote_After_Update_Create_Order_From_Quote` v2 (after-save, Update), start filter `Create_Order_from_Quote__c EqualTo true`.
- Existing Quote help text (36/237) and driver-field existence: `Data/sc3338/retrieve/Quote_describe.json`.
- Required Order field set: `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` (25 active rules).
- Prod-parity nulls: `sf data query --target-org FortraProd` for `OrderSubmissionValidator` / `Order_Submit_Validation__mdt` / `Fortra_Order_Submission_Check` → all 0 rows.
