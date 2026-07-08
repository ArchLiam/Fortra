# Exchange Rate Snapshot — Solution Design (KB)

**Purpose (one line):** Capture and persist the transaction-currency→USD exchange rate at multiple levels (QuoteLineItem, Opportunity, OrderItem) across the Salesforce Revenue Cloud quoting/ordering pipeline so Workday and other downstream integrations always have the correct, non-null rate.

> Source: `Exchange_Rate_Snapshot_Solution_Design.txt` (Solution Design Document, prepared for Fortra). This KB is written for an AI coding agent; values/types/formulas are quoted verbatim from the source. The design is described as a 3-phase implementation, all internal dependencies marked **Complete**.

---

## 1. Executive Summary

- Captures and persists the currency exchange rate (transaction currency → USD) at multiple levels within the Salesforce Revenue Cloud quoting and ordering pipeline, ensuring Workday and other downstream integrations always have access to the correct rate.
- Delivered in **three phases**:
  - **Phase 1** — captures the exchange rate on each **QuoteLineItem (QLI)** at pricing time using Salesforce **Advanced Currency Management (ACM)** dated rates.
  - **Phase 2** — propagates the QLI rate to the parent **Opportunity** (syncing Quote only).
  - **Phase 3** — closes the remaining gap by setting the **Opportunity** exchange rate at creation time and on currency changes, **before any Quote or QLI exists**.
- All three phases share a single reusable Apex utility, **`DatedConversionRateLookup`**, which queries `DatedConversionRate` with a `CurrencyType` fallback. This ensures rate consistency across all objects and entry points.

### 1.1 Key Features (verbatim list)

- Automatic exchange rate capture on `QuoteLineItem` at pricing time (before insert/update trigger)
- Rate propagation from QLI to Opportunity via **syncing Quote guard** (after insert/update trigger)
- Opportunity-level rate pre-population at creation and on currency change (before insert/update trigger)
- Single reusable `DatedConversionRateLookup` utility with **ACM + CurrencyType fallback**
- Rate flows through Quote-to-Order conversion via **Context Definition hydration** mapping to OrderItem
- Zero-DML before-trigger pattern for Opportunity rate setting (no additional governor limit usage)
- Bulkified design handles data loads and mass updates efficiently

---

## 2. Business Requirements / Rules

- The exchange rate stored is **transaction currency → USD** (corporate currency is USD — Assumption A-003).
- `Exchange_Rate_To_USD__c` must be **never null** on Opportunity for downstream consumption. Phase layering guarantees this: Phase 3 sets an initial value at creation; Phase 2 overwrites it once QLIs are priced on the syncing Quote (§6.1 Phase Layering).
- **Rate precedence:** the QLI-derived rate takes precedence over the Phase 3 initial Opportunity rate, because it reflects the actual priced transaction currency (§6.3 Rate Precedence, A-007).
- **Syncing-Quote-only propagation:** only the syncing Quote's QLI rates propagate to the parent Opportunity. Non-synced Quote rates are intentionally ignored to prevent stale/conflicting values (A-006, §6.1 Syncing Quote Guard).
- Rate capture is **independent of the Revenue Cloud pricing pipeline** — set even for manually-priced or zero-dollar line items (§6.4).
- `Opportunity.Exchange_Rate_To_USD__c` is **read-only for downstream consumption**; users do not manually edit it (A-004).

---

## 3. Data Model

Every field named below is type **`Number(18,10)`** (verbatim). There are **three custom fields**, one on each of QLI / OrderItem / Opportunity, all named `Exchange_Rate_To_USD__c`.

| Object | Field | Type | How populated / description |
|---|---|---|---|
| `QuoteLineItem` | `Exchange_Rate_To_USD__c` | `Number(18,10)` | Exchange rate from transaction currency to USD. Set by **Phase 1 before-trigger** at insert/update (pricing time). |
| `OrderItem` | `Exchange_Rate_To_USD__c` | `Number(18,10)` | Exchange rate from transaction currency to USD. Populated via **Context Definition hydration** during Quote-to-Order (Q2O) conversion. |
| `Opportunity` | `Exchange_Rate_To_USD__c` | `Number(18,10)` | Exchange rate from transaction currency to USD. **Phase 3** sets at creation; **Phase 2** overwrites when QLI is priced. |
| `DatedConversionRate` (standard, ACM) | `ConversionRate` | (standard) | Standard Salesforce ACM object. **Primary** source for dated exchange rates. Queried by ISO code and date range. |
| `CurrencyType` (standard) | `ConversionRate` | (standard) | Standard Salesforce object. **Fallback** source when no `DatedConversionRate` exists for a given ISO code. |

### 3.1 Field Mappings (§6.2.1, verbatim source→target)

| Source Field | Target Field |
|---|---|
| `QuoteLineItem.CurrencyIsoCode` | `DatedConversionRateLookup.Request.currencyIsoCode` |
| `DatedConversionRateLookup.Result.exchangeRate` | `QuoteLineItem.Exchange_Rate_To_USD__c` |
| `QuoteLineItem.Exchange_Rate_To_USD__c` | `Opportunity.Exchange_Rate_To_USD__c` (via Phase 2 after-trigger) |
| `QuoteLineItem.Exchange_Rate_To_USD__c` | `OrderItem.Exchange_Rate_To_USD__c` (via Context Definition hydration) |
| `Opportunity.CurrencyIsoCode` | `DatedConversionRateLookup.Request.currencyIsoCode` (Phase 3) |
| `DatedConversionRateLookup.Result.exchangeRate` | `Opportunity.Exchange_Rate_To_USD__c` (Phase 3) |

**Request/Result shape (inferred from mappings):** `DatedConversionRateLookup.Request` has field `currencyIsoCode`; `DatedConversionRateLookup.Result` has field `exchangeRate`.

---

## 4. Business Logic (§6.3, exact rules)

### Rate Lookup Logic (`DatedConversionRateLookup`)
1. First queries **`DatedConversionRate` (ACM)** for the given ISO code and date range.
2. If **no dated rate exists**, falls back to the **active `CurrencyType`** record.
3. **`USD` and blank codes return `1.0`.**
4. **Unknown codes return `null`.**

Mechanics (§6.1 Rate Lookup Pattern): it is an `@InvocableMethod` class callable from both triggers and Flows. It **collects unique ISO codes**, performs a **single SOQL** against `DatedConversionRate`, **falls back to `CurrencyType`** for any missing codes, and distributes results back to callers so all consumers get identical values.

### Phase 1 — QLI Before-Trigger
- On **every** `QuoteLineItem` insert or update, build a `DatedConversionRateLookup.Request` for each record's `CurrencyIsoCode` (**skipping blanks**).
- Call `getExchangeRates()` **once** with all requests (bulkified).
- Set `Exchange_Rate_To_USD__c` from the corresponding `Result`, **directly on the trigger record in memory (no DML needed)** — Salesforce commits it as part of the original DML.
- **USD returns `1.0`; unknown currencies return `null`.**

### Phase 2 — QLI After-Trigger (Opportunity propagation)
- Collect `QuoteId`-to-rate mappings from trigger records **where `Exchange_Rate_To_USD__c` is not null**.
- Query `Quote` records with their parent Opportunity's `SyncedQuoteId` (single SOQL — the Syncing Quote Guard).
- For each `Quote` where **`Quote.Id == Opportunity.SyncedQuoteId`**, update `Opportunity.Exchange_Rate_To_USD__c`.
- Uses **`Database.update` with `allOrNone = false`** so Opportunity validation-rule failures do **not** block the QLI save.
- **Non-synced Quotes are ignored** (guard prevents stale rates).

### Phase 3 — Opportunity Before-Insert
- On **every** Opportunity insert, call `DatedConversionRateLookup.getExchangeRates()` for each record's `CurrencyIsoCode`.
- Set `Exchange_Rate_To_USD__c` **in-place on the trigger record (zero DML)**.

### Phase 3 — Opportunity Before-Update
- **Filter to only Opportunities where `CurrencyIsoCode` changed** (comparing `Trigger.newMap` vs `Trigger.oldMap`).
- If any changed, call `DatedConversionRateLookup` and set `Exchange_Rate_To_USD__c`.
- **Non-currency edits skip this logic entirely.**

### Rate Precedence (§6.3)
- Phase 3 sets the **initial** value.
- Phase 2 **overwrites** when QLIs exist on a syncing Quote.
- The QLI-derived rate takes precedence because it reflects the **actual priced transaction currency**.

### Edge cases / defaults (consolidated)
- USD ISO code → `1.0`.
- Blank / empty ISO code → `1.0` (treated like USD in lookup) AND blanks are skipped when building QLI requests in Phase 1.
- Unknown ISO code (no DatedConversionRate and no CurrencyType) → `null`.
- Phase 2 tolerates Opportunity save failures via `allOrNone=false` (partial success).
- No explicit rounding mode is stated in the source; field precision is `Number(18,10)` (10 decimal places).

---

## 5. Components (§2.2)

| Component | Type | Responsibility |
|---|---|---|
| `DatedConversionRateLookup` | Apex Class (`@InvocableMethod`) | Reusable utility. Queries `DatedConversionRate` (ACM) with `CurrencyType` fallback. Returns exchange rate for a given ISO code and date. **Used by both triggers** (and callable from Flows). Single source of truth for rates. |
| `QuoteLineItemExchangeRateTrigger` | Apex Trigger (before/after insert, before/after update) | **Phase 1** (before context): sets `Exchange_Rate_To_USD__c` on QLI. **Phase 2** (after context): propagates rate to parent Opportunity (syncing Quote only). |
| `OpportunityTrigger` | Apex Trigger (before insert, before update, after update) | **Phase 3** (before context): pre-populates `Exchange_Rate_To_USD__c` on new Opportunities and refreshes on currency change. **after update** handles existing Hardware lifecycle logic (pre-existing). |
| `OpportunityTriggerHandler` | Apex Class (Handler) | Routes trigger events to handler methods. Phase 3 adds `handleBeforeInsert`, `handleBeforeUpdate`, and a private `setExchangeRates` helper. |
| `Exchange_Rate_To_USD__c` (QuoteLineItem) | Custom Field — `Number(18,10)` | Set by Phase 1 trigger at pricing time. |
| `Exchange_Rate_To_USD__c` (OrderItem) | Custom Field — `Number(18,10)` | Populated via Context Definition hydration during Q2O. |
| `Exchange_Rate_To_USD__c` (Opportunity) | Custom Field — `Number(18,10)` | Phase 3 sets at creation; Phase 2 overwrites when QLI is priced. |
| `SalesTransactionContextExt` | Context Definition (Manual Config) | Hydration mapping that copies `Exchange_Rate_To_USD__c` from QLI → `SalesTransactionItem`, and from OrderItem → `SalesTransactionItem`. |
| `OrderItem_Field_Access` | Permission Set | Grants **Read** access to `Exchange_Rate_To_USD__c` on **both** `QuoteLineItem` and `OrderItem`. |

### Trigger architecture notes (§6.1)
- Follows Salesforce **one-trigger-per-object** best practice.
- `QuoteLineItemExchangeRateTrigger` handles both Phase 1 (before: rate capture) and Phase 2 (after: Opportunity propagation).
- `OpportunityTrigger` handles Phase 3 (before: creation rate) alongside the existing after-update Hardware lifecycle logic.
- Both Phase 1 (QLI) and Phase 3 (Opportunity) use **before-trigger field assignment** → set rate directly on the in-memory record → **zero additional DML**, minimal governor impact (**1–2 SOQLs** for the rate lookup).

---

## 6. Integration Points & Sequence

### Process Flow Sequence (§2.1)
1. **Phase 1 — QLI Rate Capture:** QLI insert/update → `QuoteLineItemExchangeRateTrigger` (before) → `DatedConversionRateLookup.getExchangeRates()` with QLI `CurrencyIsoCode` → set `Exchange_Rate_To_USD__c` on trigger record (no DML).
2. **Phase 2 — Opportunity Rate Propagation:** same trigger's after context → QLI `Exchange_Rate_To_USD__c` propagated to parent Opportunity **only when the QLI's Quote is the Opportunity's syncing Quote** (`Opportunity.SyncedQuoteId` check). Non-synced Quotes ignored.
3. **Phase 3 — Opportunity Creation Rate:** `OpportunityTrigger` (before insert, before update) → `DatedConversionRateLookup.getExchangeRates()` → pre-populate `Exchange_Rate_To_USD__c` on every new Opportunity. On update, only Opportunities where `CurrencyIsoCode` actually changed are processed. Later Phase 2 QLI pricing overwrites this initial rate.
4. **Rate Lookup Logic:** `DatedConversionRateLookup` → query `DatedConversionRate` (ACM) for ISO code + date range → fall back to active `CurrencyType` if none → USD/blank return `1.0`, unknown return `null`.
5. **Quote-to-Order Flow:** `Exchange_Rate_To_USD__c` propagates QLI → OrderItem via Revenue Cloud **Context Definition hydration** mapping (`SalesTransactionContextExt`). No additional automation for order conversion.

### Integration Points (§6.4)
- **Workday Integration:** reads `Exchange_Rate_To_USD__c` from **Opportunity** (deal-level rate) and **OrderItem** (line-level rate). Field is always populated — never null.
- **Context Definition Hydration:** `SalesTransactionContextExt` maps `Exchange_Rate_To_USD__c` as an attribute on `SalesTransactionItem`. Hydration mappings exist under **both `QuoteEntitiesMapping` and `OrderEntitiesMapping`**, ensuring the rate flows through Q2O conversion automatically.
- **Revenue Cloud Pricing Pipeline:** exchange rate captured **independently** of the pricing pipeline; `DatedConversionRateLookup` queries ACM rates directly — does **not** depend on the pricing procedure or price waterfall. Rate is set even for manually-priced or zero-dollar line items.

---

## 7. Assumptions (§4, verbatim)

- **A-001:** ACM is enabled in the org, providing `DatedConversionRate` records for historical rate lookups.
- **A-002:** All active currencies used in Opportunities and Quotes have corresponding `DatedConversionRate` or `CurrencyType` records in the org.
- **A-003:** The corporate currency is **USD**. All `Exchange_Rate_To_USD__c` values represent transaction currency → USD.
- **A-004:** `Opportunity.Exchange_Rate_To_USD__c` is read-only for downstream consumption; users do not manually edit.
- **A-005:** `SalesTransactionContextExt` is manually configured with hydration mappings for `Exchange_Rate_To_USD__c` after deployment.
- **A-006:** Only the syncing Quote's QLI rates should propagate to the parent Opportunity. Non-synced Quote rates are intentionally ignored.
- **A-007:** The Phase 3 initial rate will be overwritten by Phase 2 when QLIs are priced — intended behavior; QLI-derived rates take precedence.

## 8. Dependencies (§5)

**Internal (all status = Complete):**
- **D-001:** `DatedConversionRateLookup` Apex class deployed to target org.
- **D-002:** `Exchange_Rate_To_USD__c` custom field on `QuoteLineItem`.
- **D-003:** `Exchange_Rate_To_USD__c` custom field on `OrderItem`.
- **D-004:** `Exchange_Rate_To_USD__c` custom field on `Opportunity`.
- **D-005:** `QuoteLineItemExchangeRateTrigger` deployed (Phase 1 + Phase 2).
- **D-006:** `OpportunityTrigger` and `OpportunityTriggerHandler` updated (Phase 3).
- **D-007:** `OrderItem_Field_Access` permission set updated with field access.

**External:**
- **E-001:** Context Definition hydration mapping for `Exchange_Rate_To_USD__c` on `SalesTransactionItem` (manual UI configuration) — Owner: **Salesforce Admin**.
- **E-002:** FLS configuration for `Opportunity.Exchange_Rate_To_USD__c` on relevant permission sets — Owner: **Salesforce Admin**.
- **E-003:** Workday integration configured to read `Exchange_Rate_To_USD__c` from Opportunity and OrderItem — Owner: **Workday Integration Team**.

### Open issues / gaps
- No explicit rounding mode documented for the rate value (precision is `Number(18,10)`).
- `SalesTransactionContextExt` hydration mapping and Opportunity FLS are **manual** post-deploy steps (E-001, E-002); not automated by the Apex.
- Document numbering in the source is inconsistent (sections jump 2 → 6 → 4 → 5); treat section order as: Executive Summary, Solution Overview, Technical Design, Assumptions, Dependencies.

---

## CODE-GOVERNING RULES (MUST NOT violate)

1. **Field type is `Number(18,10)`** on all three `Exchange_Rate_To_USD__c` fields (QuoteLineItem, OrderItem, Opportunity). Do not change precision/scale.
2. **All rate lookups go through `DatedConversionRateLookup`** — it is the single source of truth. Do not inline `DatedConversionRate`/`CurrencyType` queries elsewhere. It is an `@InvocableMethod` callable from triggers and Flows.
3. **Lookup order is fixed:** query `DatedConversionRate` (ACM) by ISO code + date range **first**, then fall back to the **active `CurrencyType`** record only if no dated rate exists.
4. **`USD` and blank ISO codes return `1.0`. Unknown ISO codes return `null`.** Do not substitute a default for unknown codes.
5. **`DatedConversionRateLookup` must be bulkified:** collect unique ISO codes and perform a **single SOQL** against `DatedConversionRate`, then distribute results. Do not query per-record inside loops.
6. **Phase 1 and Phase 3 use before-triggers with in-memory field assignment (zero additional DML).** Rate must be set on the trigger record itself, committed by the original DML. Do not add explicit DML for QLI or Opportunity rate-setting.
7. **Phase 1 skips blank `CurrencyIsoCode`** when building requests, and calls `getExchangeRates()` once with all requests.
8. **Phase 2 propagates to Opportunity ONLY when `Quote.Id == Opportunity.SyncedQuoteId`** (syncing Quote guard). Non-synced Quotes must never overwrite the Opportunity rate. Use a single SOQL to resolve the syncing relationship.
9. **Phase 2 collects only QLIs where `Exchange_Rate_To_USD__c` is not null** for propagation.
10. **Phase 2 Opportunity update uses `Database.update` with `allOrNone = false`** so Opportunity validation-rule failures do not block the QLI save. Do not switch to all-or-none DML.
11. **Phase 3 Before-Update processes ONLY Opportunities where `CurrencyIsoCode` changed** (compare new vs old map). Non-currency edits must skip the logic entirely.
12. **Rate precedence:** QLI-derived rate (Phase 2) overwrites the Phase 3 initial Opportunity rate. Phase layering must keep `Opportunity.Exchange_Rate_To_USD__c` **never null** (Phase 3 always seeds at creation).
13. **One trigger per object:** keep Phase 1 + Phase 2 in `QuoteLineItemExchangeRateTrigger`; keep Phase 3 in `OpportunityTrigger` alongside its existing after-update Hardware lifecycle logic. Do not add second triggers on these objects.
14. **Rate capture must remain independent of the Revenue Cloud pricing pipeline** — set even for manually-priced or zero-dollar lines. Do not gate rate lookup on the pricing procedure / price waterfall.
15. **QLI→OrderItem propagation is via Context Definition hydration (`SalesTransactionContextExt`), not Apex.** Hydration mappings must exist under both `QuoteEntitiesMapping` and `OrderEntitiesMapping`. Do not replace with custom Apex on Q2O conversion.
16. **`OrderItem_Field_Access` permission set must grant Read to `Exchange_Rate_To_USD__c` on both QuoteLineItem and OrderItem.** Workday and downstream consumers depend on this access.
17. **Corporate currency assumption is USD** — all `Exchange_Rate_To_USD__c` values are transaction-currency→USD. Logic must not assume any other corporate currency.
18. **`Opportunity.Exchange_Rate_To_USD__c` is read-only for downstream consumption** — do not add user-editable UI writes that conflict with the automated precedence rules.
