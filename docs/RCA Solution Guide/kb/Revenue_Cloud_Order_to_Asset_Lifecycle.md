# Revenue Cloud: Order → Asset → Renewal/Amendment Lifecycle

**Purpose (one line):** Documents the complete end-to-end lifecycle of a Salesforce Revenue Cloud Advanced (RCA) transaction in the Fortra CPQ-to-Revenue-Cloud migration — from Quote-to-Order conversion, through Asset creation and Billing Schedule generation, to Renewal and Amendment processing.

**Source doc:** "Revenue Cloud — Order to Asset to Renewal/Amendment Lifecycle — Fortra CPQ-to-Revenue Cloud Migration", dated February 26, 2026.

---

## Executive Summary

An RCA transaction flows through five phases:

1. **Phase 1 — Quote-to-Order Conversion (Q2O):** Screen Flow `Fortra_Quote_to_Order_Conversion` converts a Quote + QuoteLineItems into an Order + OrderItems, optionally creating/linking a Contract, and splits Power products.
2. **Phase 2 — Order Activation & Asset Creation:** Record-triggered async flow `Fortra_Assetize_Order` creates Assets from subscription-type OrderItems (gated on an Application Usage Assignment record).
3. **Phase 3 — Billing Schedule Creation:** Record-triggered async flow `Fortra_Order_to_Billing_Schedule` creates Billing Schedules using the org default PaymentTerm.
4. **Phase 4 — Renewal Lifecycle:** Four sub-flows (window monitoring, renewal quote creation, COLA pricing, contract succession Gen 1 → Gen 2).
5. **Phase 5 — Amendment Lifecycle:** Child-contract modification path (via `AmendedContractId`), co-termination, and role-based validation restrictions.

Phases 2 and 3 fire **independently and concurrently** on the same Order-activation event (parallel async transactions; neither depends on the other). Both are designed to **fail silently** on missing prerequisite data so Order activation is never blocked.

---

## Business Requirements / Rules

- Quotes cannot be converted unless **all** `Quote_Checklist_Item__c.Is_Checked__c = true`.
- Order, OrderItem, and Contract **must all share the same `CurrencyIsoCode`** — a mismatch throws `FIELD_INTEGRITY_EXCEPTION`. Q2O enforces this by filtering candidate Contracts by `CurrencyIsoCode` during selection.
- Only **subscription-type** products create Assets. Non-subscription items (perpetual licenses, services) do **not** create Assets.
- Asset creation requires a prerequisite **Application Usage Assignment (AUA)** record; without it, assetization exits silently (most common cause of "missing asset" issues).
- Renewal eligibility = Contract within **120-day** renewal window (`EndDate - TODAY() <= 120 days`).
- COLA uplift on renewal lines follows a strict **3-tier precedence: Line Override > Contract Override > CMDT Lookup**.
- Renewals create a **new Contract generation** (Gen 1 → Gen 2 via `Original_Contract__c`); amendments create a **child Contract** (via `AmendedContractId`). These are fundamentally different relationship patterns (temporal succession vs. modification).
- Amendment Contracts co-terminate with their parent by default (matching `EndDate`).
- Sales users are restricted (by Validation Rules) from certain amendment reason types; **Customer Ops roles are exempt**.

---

## Data Model — Objects & Fields (with types where stated)

### Primary Objects and Roles

| Object | Role in Lifecycle | Key Relationships |
|---|---|---|
| `Quote` | Source document for pricing and terms | Parent of QuoteLineItem; links to Opportunity; feeds `Order.SourceQuoteId` |
| `QuoteLineItem` | Individual product line on Quote | Mapped 1:1 to OrderItem via RCA; carries COLA pricing for renewals |
| `Order` | Transactional record for fulfillment | Created from Quote; links to Contract; triggers Asset + Billing on activation |
| `OrderItem` | Individual product line on Order | Created from QuoteLineItem; source for Asset creation; may be split for Power products |
| `Contract` | Legal agreement governing terms | Links to Order; succession via `Original_Contract__c` (renewal) or `AmendedContractId` (amendment) |
| `Asset` | Customer entitlement to product/service | Created from OrderItem on activation; subject of Renew and Amend actions |
| `BillingSchedule` | Invoice schedule for billing periods | Created from Order on activation; uses PaymentTerm for due-date calculation |
| `AppUsageAssignment` (AUA) | Prerequisite flag for RLC processing | Must exist on Order for assetization; `AppUsageType = 'RevenueLifecycleManagement'` |

### Supporting Objects

| Object | Role |
|---|---|
| `QuoteAction` | RCA-created record; `Type = 'Renew'` identifies renewal quotes |
| `Hardware__c` | Fortra-specific custom object; cloned during Power line splitting |
| `Partition__c` | Fortra-specific custom object; cloned per split item; **child of `Hardware__c`** |
| `Quote_Checklist_Item__c` | Pre-conversion validation items on Quote (field `Is_Checked__c`) |
| `COLA_Uplift_Rules__mdt` | Custom Metadata Type — renewal pricing tiers keyed by Solution Category |
| `PaymentTerm` / `PaymentTermItem` | Billing terms configuration (e.g., Net 30) |
| `Product2` | Carries `Power_Split_Type__c` controlling Power split behavior |

### Custom Fields Named in Source

**Quote:**
- `Quote_Type__c` — set to `"Renewal"` on renewal quotes.
- `Renewal_Contract__c` — links renewal Quote to source (Gen 1) Contract.
- `OriginalOrderId` — (standard-ish) maps to `Order.SourceOrderId` for amendments.
- 8 custom fields common-named to Order, examples given: `ALE__c`, `AWS_Marketplace_Agreement_ID__c`, `Cross_Sale_Type__c` (mapped by same API name).

**QuoteLineItem (COLA-related):**
- `Is_COLA_Overridden__c` (Boolean) — Tier-1 line override flag.
- `Pre_COLA_Price__c` — base price used in the COLA formula.
- `COLA_Source__c` — audit: which tier supplied the %.
- `COLA_Applied_Date__c` — audit: date COLA applied.
- `COLA_Solution_Category__c` — audit: solution category matched.
- 14 QuoteLineItem fields mapped 1:1 to OrderItem by same API name; examples: `Currency__c`, `GSA__c`, `Hardware__c`, `Model__c`, `Serial_Number__c`.

**Order (standard RCA source mappings):**
- `Order.SourceQuoteId` ← `Quote.Id`
- `Order.SourceOpportunityId` ← `Quote.OpportunityId`
- `Order.SourceOrderId` ← `Quote.OriginalOrderId` (amendments only)
- `Order.CurrencyIsoCode` ← `Quote.CurrencyIsoCode` (must match Contract)
- `Order.EffectiveDate` — subscription/billing start date; must be populated for both assetization and billing.

**Contract:**
- `Within_Renewal_Window__c` — **Formula field**; evaluates `EndDate - TODAY() <= 120 days` → TRUE/FALSE.
- `Renewal_Status__c` — values seen: `"Pending"`, `"Accepted"`.
- `COLA_Override_Percent__c` — Tier-2 contract-level COLA override %.
- `Original_Contract__c` — renewal succession link (Gen 2 → Gen 1).
- `AmendedContractId` — amendment link (child → parent); standard-style field.
- `Co_Term_Overridden__c` (Boolean) — audit flag; default FALSE, set TRUE if amendment EndDate manually diverges from parent.
- `Legal_Entity__c` / `LegalEntityId` — inherited by new Contract / copied to renewal Quote.
- `Status` values seen: `"Activated"`, `"Renewed"`.

**Asset (targets set by RCA):**
- `Asset.Product2Id` ← `OrderItem.Product2Id`
- `Asset.Quantity` ← `OrderItem.Quantity` (1 per split line for Power)
- `Asset.Price` ← `OrderItem.UnitPrice`
- `Asset.LifecycleStartDate` ← `Order.EffectiveDate`
- `Asset.LifecycleEndDate` — calculated from billing term/frequency (set by RCA)
- `Asset.Status` — default `'Active'` on creation

**Product2:**
- `Power_Split_Type__c` — controls Power line-split type.

---

## Business Logic — Formulas, Precedence, Defaults, Edge Cases

### COLA Uplift (Phase 4c)

**Precedence (checked in order, highest first):**

| Priority | Source | Condition |
|---|---|---|
| 1 (Highest) | Line Override | `QuoteLineItem.Is_COLA_Overridden__c = true` |
| 2 | Contract Override | `Contract.COLA_Override_Percent__c` is set on parent Contract |
| 3 (Default) | CMDT Lookup | `COLA_Uplift_Rules__mdt` matched by Product **Solution Category** |

**Formula (verbatim):**
```
New UnitPrice = Pre_COLA_Price__c × (1 + COLA% / 100)
```
Audit fields populated on apply: `COLA_Source__c`, `COLA_Applied_Date__c`, `COLA_Solution_Category__c`.

### Renewal Window (Phase 4a)

Formula field `Within_Renewal_Window__c` = TRUE when `EndDate - TODAY() <= 120 days`. Scheduled flow updates matching Contracts to `Renewal_Status__c = "Pending"`.

### PaymentTerm Due-Date Config (Phase 3)

Default PaymentTerm must be: `IsDefault = true` AND `Status = 'Active'`, with at least one `PaymentTermItem` child having:
- `Type = "Period-Based"`
- `PaymentTimeframe = "Standard"`
- `Period = 30`
- `PeriodUnit = "Days"`

### Power Line Splitting (Phase 1, Step 5)

Splits OrderItems where the Product is a **Power solution group** AND `Quantity > 1`. Split type controlled by `Product2.Power_Split_Type__c`. Clones `Hardware__c` and (per split item) `Partition__c`. Each resulting split line has `Quantity = 1`.

### Edge Cases / Silent-Failure Design

- **Assetize AUA check:** if no `AppUsageAssignment` with `RecordId = Order.Id` and `AppUsageType = 'RevenueLifecycleManagement'`, flow **exits silently** — no error, no Assets. Order stays Activated.
- **Assetize errors:** `$Flow.FaultMessage` captured/logged but **non-blocking**; Order remains Activated regardless.
- **Billing EffectiveDate check:** if `Order.EffectiveDate` missing in async re-query, flow exits — **no billing schedule created** (no error).
- **Currency mismatch:** across Order/OrderItem/Contract → `FIELD_INTEGRITY_EXCEPTION`.

---

## Components

### Flows

| Flow | Type / Trigger | Responsibility |
|---|---|---|
| `Fortra_Quote_to_Order_Conversion` | Screen Flow, user-initiated | Q2O orchestration: validation, activation mode, contract selection, order creation, power split, contract linking, activation decision |
| `Fortra_Assetize_Order` | Record-Triggered, async on `Order.Status = "Activated"` | Create Assets from subscription-type OrderItems (AUA-gated) |
| `Fortra_Order_to_Billing_Schedule` | Record-Triggered, async on `Order.Status = "Activated"` | Create Billing Schedules per billable OrderItem using default PaymentTerm |
| `Fortra_Contract_Renewal_Window_Monitor` | Scheduled (daily) | Set `Renewal_Status__c = "Pending"` on Contracts where `Status = "Activated"` AND `Within_Renewal_Window__c = TRUE` |
| `Fortra_RCA_Renewal_Enhancement` | Record-Triggered on Quote | On Renew action: set `Quote_Type__c = "Renewal"`, link `Renewal_Contract__c`, copy `LegalEntityId` from Contract |
| `Fortra_Renewal_Contract_Succession` | Record-Triggered on Order activation | Gen 1 → `Status = "Renewed"`, `Renewal_Status__c = "Accepted"`; create Gen 2 with `Original_Contract__c` = Gen 1 |
| `Contract_Amendment_CoTermination` | Record-Triggered on Contract create where `AmendedContractId IS NOT NULL` | Set amendment `EndDate` = parent `EndDate`; set `Co_Term_Overridden__c = FALSE` |
| `Contract_Amendment_CoTerm_Override_Detection` | Companion flow (on later manual EndDate change) | Set `Co_Term_Overridden__c = TRUE` audit flag when amendment EndDate diverges from parent |

### Apex Classes

| Class | Responsibility |
|---|---|
| `ChecklistValidationService` | Q2O Step 1 — ensure all `Quote_Checklist_Item__c.Is_Checked__c = true`; error screen if not |
| `PowerOrderSplittingService` | Q2O Step 5 — split OrderItems for Power products with `Quantity > 1`, per `Product2.Power_Split_Type__c` |
| `COLAUpliftHandler` | Trigger on QuoteLineItem — applies COLA 3-tier uplift + audit fields during renewal |

### RCA Actions (invocable / platform)

- `createOrderFromQuote` — maps Quote → Order and QuoteLineItems → OrderItems; returns new Order ID; fault-handles if pricing not calculated.
- `createOrUpdateAssetFromOrder` — creates one Asset per subscription-type OrderItem; on amendments, **updates existing** Assets instead of creating new ones.
- `createBillingSchedulesFromBillingTransaction` — inputs: `billingTransactionId = Order.Id`, `billingStartMonth = Order.EffectiveDate`, `paymentTermID`.

### Validation Rules (Phase 5)

| Validation Rule | Sales Users Blocked From | Exception |
|---|---|---|
| `Sales_Cannot_Amend_Downsell` | Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change | Customer Ops roles |
| `Sales_Renewal_Window_Restriction` | Everything except Upsell or Cross-sell (within 120-day renewal window) | Customer Ops roles |

---

## Phase-by-Phase Processing Steps

### Phase 1 — Q2O (`Fortra_Quote_to_Order_Conversion`)
1. **Validate** — `ChecklistValidationService`; all `Quote_Checklist_Item__c.Is_Checked__c = true` or error screen.
2. **Activation Mode** — user picks Automatic (activate immediately) or Manual (stays Draft for review).
3. **Contract Selection** — Select existing (currency-matched) / Create New / Skip Contract.
4. **Order Creation** — `createOrderFromQuote`; returns new Order ID; fault handling if pricing not calculated.
5. **Power Line Splitting** — `PowerOrderSplittingService`.
6. **Contract Linking** — new Contract inherits `AccountId`, `CurrencyIsoCode`, `Legal_Entity__c` from Quote; links Order to Contract.
7. **Activation Decision** — if Automatic → `Order.Status = Activated` → triggers Phase 2 + Phase 3 async flows; if Manual → stays Draft.

### Phase 2 — Assetization (`Fortra_Assetize_Order`)
1. **Check AUA** — query `AppUsageAssignment` where `RecordId = Order.Id` and `AppUsageType = 'RevenueLifecycleManagement'`; if missing → exit silently.
2. **Create Assets** — `createOrUpdateAssetFromOrder`; one Asset per subscription-type OrderItem; non-subscription items do NOT create Assets.
3. **Error Handling** — capture `$Flow.FaultMessage`; failures logged, non-blocking; Order remains Activated.

### Phase 3 — Billing (`Fortra_Order_to_Billing_Schedule`)
1. **Query Order** — re-query in async context; verify `Order.EffectiveDate` populated; if missing → exit (no schedule).
2. **Lookup PaymentTerm** — `IsDefault = true` AND `Status = 'Active'`; must have `PaymentTermItem` child.
3. **Create Schedules** — `createBillingSchedulesFromBillingTransaction` (inputs listed above).

### Phase 4 — Renewal
- **4a Window Monitoring** (`Fortra_Contract_Renewal_Window_Monitor`, daily): Contracts `Status="Activated"` + `Within_Renewal_Window__c=TRUE` → `Renewal_Status__c="Pending"`.
- **4b Renewal Quote Creation** (`Fortra_RCA_Renewal_Enhancement`): platform auto-creates Quote + `QuoteAction (Type="Renew")` on Renew action; flow sets `Quote_Type__c="Renewal"`, links `Renewal_Contract__c`, copies `LegalEntityId`.
- **4c COLA Pricing** (`COLAUpliftHandler`): 3-tier uplift + audit fields.
- **4d Q2O + Contract Succession** (`Fortra_Renewal_Contract_Succession`): renewal Quote runs same Phase 1 Q2O; on activation Gen 1 → Renewed/Accepted, Gen 2 created with `Original_Contract__c` = Gen 1, inheriting Account, Legal Entity, Solution Group, Partner, Currency.

**Contract Succession Model:**

| Object | Before Renewal | After Renewal |
|---|---|---|
| Original Contract (Gen 1) | `Status: Activated`, `Renewal_Status__c: Pending`, `Within_Renewal_Window__c: TRUE` | `Status: Renewed`, `Renewal_Status__c: Accepted` |
| Renewal Quote | `Quote_Type__c: Renewal`, `Renewal_Contract__c: Gen 1 Id`, QLIs with COLA-enhanced pricing | Converted to Order via Q2O |
| New Contract (Gen 2) | (Does not exist yet) | `Status: Activated`, `Original_Contract__c: Gen 1 Id`; inherits Account, Legal Entity, Solution Group, Partner, Currency |

### Phase 5 — Amendment
- Amendment Contract linked via `AmendedContractId` to parent (child relationship, NOT Gen chain).
- Co-termination flow sets amendment `EndDate` = parent `EndDate`, `Co_Term_Overridden__c = FALSE`; override-detection flow sets TRUE on manual divergence.
- Role-based VRs restrict Sales amendment reasons (Customer Ops exempt).
- Amendment orders go through same Q2O / Assetization / Billing pipeline. Key differences: `Order.SourceOrderId` links to original Order; `createOrUpdateAssetFromOrder` **updates existing** Assets rather than creating new.

---

## Integration Points & Sequence

1. User initiates Q2O Screen Flow → `createOrderFromQuote` (RCA) creates Order/OrderItems.
2. `PowerOrderSplittingService` (Apex) splits + clones `Hardware__c`/`Partition__c`.
3. Order activation event → **two parallel async flows fire concurrently**: `Fortra_Assetize_Order` (Phase 2) and `Fortra_Order_to_Billing_Schedule` (Phase 3). They do not depend on each other.
4. Assetize calls `createOrUpdateAssetFromOrder` (RCA); Billing calls `createBillingSchedulesFromBillingTransaction` (RCA).
5. Field flow (Quote→Order, Order→Contract) managed by **Revenue Cloud Context Service**; standard RCA provides core mappings; **Context Definition `SalesTransactionContextExt`** adds Fortra custom-field hydration mappings. Any custom field flowing Quote→Order must have a corresponding hydration mapping in the Context Definition.
6. Renewal: daily scheduled monitor → Renew action (platform creates Quote + QuoteAction) → COLA trigger → Q2O → succession flow.

---

## Key Control Points

| Flow / Phase | Control | Purpose |
|---|---|---|
| Q2O | Checklist validation | Prevent conversion of incomplete quotes |
| Q2O | Currency matching | Prevent Order-Contract currency mismatch |
| Q2O | Power splitting | Handle bulk Power products with quantity > 1 |
| Assetize | AUA lookup | Prerequisite for RLC asset creation |
| Assetize | EffectiveDate check | Verify billing start date exists |
| Billing | PaymentTerm lookup | Default payment terms must exist |
| Renewal | 120-day window formula | Determine renewal eligibility |
| Renewal | COLA hierarchy | Apply correct pricing tier (Line > Contract > CMDT) |
| Amendment | Role-based validation | Restrict Sales from certain amendment types |
| Amendment | Co-termination | Default end date alignment with parent Contract |

---

## Assumptions / Dependencies / Open Issues

- **Dependency — AUA record:** assetization silently no-ops without it (most common missing-asset root cause). Requires monitoring since no error surfaces.
- **Dependency — default PaymentTerm + PaymentTermItem:** billing silently no-ops if absent/misconfigured.
- **Dependency — Context Definition `SalesTransactionContextExt`:** custom fields fail to flow Quote→Order if hydration mapping is missing (declarative layer is critical).
- **Assumption — Order.EffectiveDate populated** before async phases run; otherwise Asset lifecycle dates and billing schedules cannot be derived.
- **Design trade-off — Silent-failure by design:** AUA check and PaymentTerm lookup exit gracefully rather than throwing, so Order activation is never blocked by downstream failures; requires external monitoring to catch missed Assets/Billing Schedules.
- **Multi-currency:** Order/OrderItem/Contract must all match `CurrencyIsoCode` or `FIELD_INTEGRITY_EXCEPTION`.

### Business Logic Distribution (technology responsibilities)

| Technology | Responsibility |
|---|---|
| Salesforce Flows | Orchestration, field mapping, user interaction, validation sequencing |
| Apex Classes | Complex logic: Power line splitting, field cloning, COLA pricing, checklist validation |
| Validation Rules | Role-based restrictions on amendments and renewal-window enforcement |
| Formula Fields | Calculated fields: renewal window (`Within_Renewal_Window__c`), days until expiry |

---

## CODE-GOVERNING RULES (an engineer refactoring this MUST NOT violate)

1. **Checklist gate is mandatory:** Q2O MUST NOT proceed unless every `Quote_Checklist_Item__c.Is_Checked__c = true`. On failure, show error screen — do not convert.
2. **Currency invariant:** Order, OrderItem, and Contract MUST share identical `CurrencyIsoCode`. Q2O MUST filter candidate Contracts by `CurrencyIsoCode` during selection. Violation → `FIELD_INTEGRITY_EXCEPTION`.
3. **Subscription-only assetization:** `createOrUpdateAssetFromOrder` MUST create Assets ONLY for subscription-type OrderItems. Perpetual licenses and services MUST NOT create Assets.
4. **AUA prerequisite, silent exit:** Assetization MUST query `AppUsageAssignment` where `RecordId = Order.Id` and `AppUsageType = 'RevenueLifecycleManagement'` and MUST exit silently (no thrown error) when absent. Order MUST remain `Activated`.
5. **Non-blocking downstream:** Neither assetization errors (`$Flow.FaultMessage`) nor a missing/misconfigured PaymentTerm may block or roll back Order activation. Failures are logged/exit gracefully only.
6. **Billing EffectiveDate guard:** Billing flow MUST verify `Order.EffectiveDate` is populated (re-query in async context) and exit with no schedule if missing.
7. **Parallel independence:** Assetization (Phase 2) and Billing (Phase 3) MUST remain independent async transactions triggered by the same activation event; neither may depend on the other's completion.
8. **COLA precedence exact order:** COLA % MUST be resolved as Line Override (`Is_COLA_Overridden__c = true`) > Contract Override (`Contract.COLA_Override_Percent__c` set) > CMDT (`COLA_Uplift_Rules__mdt` by Solution Category). Do not reorder.
9. **COLA formula exact:** `New UnitPrice = Pre_COLA_Price__c × (1 + COLA% / 100)`. Must also populate `COLA_Source__c`, `COLA_Applied_Date__c`, `COLA_Solution_Category__c`.
10. **Renewal window threshold:** `Within_Renewal_Window__c` MUST evaluate `EndDate - TODAY() <= 120 days`. Same 120-day threshold governs `Sales_Renewal_Window_Restriction`.
11. **Renewal succession pattern:** Renewals MUST update Gen 1 to `Status="Renewed"`, `Renewal_Status__c="Accepted"` and create Gen 2 with `Original_Contract__c = Gen 1 Id`. Renewals MUST NOT use `AmendedContractId`.
12. **Amendment pattern:** Amendments MUST link child Contract to parent via `AmendedContractId` (NOT `Original_Contract__c`). `createOrUpdateAssetFromOrder` MUST update existing Assets (not create) when processing amendments; `Order.SourceOrderId` MUST link to the original Order.
13. **Co-termination default:** On amendment Contract create (`AmendedContractId IS NOT NULL`), amendment `EndDate` MUST default to parent `EndDate` with `Co_Term_Overridden__c = FALSE`; manual EndDate divergence MUST set `Co_Term_Overridden__c = TRUE`.
14. **Amendment role restrictions:** VRs `Sales_Cannot_Amend_Downsell` and `Sales_Renewal_Window_Restriction` MUST block Sales from the listed amendment reasons while exempting Customer Ops roles.
15. **Power split rule:** `PowerOrderSplittingService` MUST split only when Product is a Power solution group AND `Quantity > 1`, using `Product2.Power_Split_Type__c`; each split line MUST have `Quantity = 1`, and `Hardware__c` / `Partition__c` MUST be cloned per split.
16. **PaymentTerm config invariant:** Billing MUST select the PaymentTerm with `IsDefault = true` AND `Status = 'Active'`, which MUST have a `PaymentTermItem` child (`Type="Period-Based"`, `PaymentTimeframe="Standard"`, `Period=30`, `PeriodUnit="Days"`).
17. **Context Definition mapping:** Any custom field required to flow Quote→Order MUST have a corresponding hydration mapping in Context Definition `SalesTransactionContextExt`; do not rely on standard RCA mappings alone for Fortra custom fields.
18. **RCA action contract:** `createBillingSchedulesFromBillingTransaction` MUST be called with `billingTransactionId = Order.Id`, `billingStartMonth = Order.EffectiveDate`, and a valid `paymentTermID`.
