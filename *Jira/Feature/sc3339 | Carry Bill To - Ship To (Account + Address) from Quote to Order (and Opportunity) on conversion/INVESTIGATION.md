# SC-3339 — Deep Investigation

> Multi-agent investigation (6 dimensions, adversarially verified, synthesized) run 2026-06-05 against **FortraUAT** (read-only).
> Raw result: [Data/sc3339/investigation_result.json](../../../Data/sc3339/investigation_result.json) · Schema describes: [Data/sc3339/schema/](../../../Data/sc3339/schema/)

---

## TL;DR

- **The Address half is already done.** The conversion flow element `Update_Order_Record_with_Bill_to_Ship_To_Address` already maps `Quote.Bill_To_Place__c → Order.Bill_To_Address__c` and `Quote.Ship_To_Place__c → Order.Ship_To_Address__c` at the **Order header**. The line-level mapper also sets `OrderItem.Ship_To_Address__c`. **Do not re-map these.**
- **The real gap is the ACCOUNT half.** `Order.Bill_To_Account__c` and `Order.Ship_To_Account__c` (both → Account) are **never populated** by the flow or the mapper, and the **Quote has no matching Account lookup** to copy from.
- **This is blocking, not cosmetic.** `Order_Submit_Validation__mdt` records **X00024** (`Bill_To_Account__c`) and **X00025** (`Ship_To_Account__c`) are **Active** and required for Order Complete / Workday submission. Converted Orders are missing these.
- **Resolved source:** the Account derives from the **parent Account of the Quote's Place** — `Order.Bill_To_Account__c = Quote.Bill_To_Place__r.Account__c`, `Order.Ship_To_Account__c = Quote.Ship_To_Place__r.Account__c`. Verified by live data: **152/153 (99.3%)** of UAT Orders with a Place set already have `Bill_To_Account__c == Bill_To_Place__r.Account__c`; `Places__c.Account__c` is required (`nillable=false`) so a parent Account always exists.
- **Also missing:** the Order **Place lookups** (`Bill_To_Place__c` / `Ship_To_Place__c`) themselves are not set today — only the `*_Address__c` variants are. They should be populated so the Account can be derived from them.
- **Power-split:** no conflict (line-level only; runs before the header update). **SC-3308:** already deployed to UAT, runs strictly downstream — no sequencing conflict, and populating the Accounts *before* reprice/activation actually helps SC-3308 pass validation.
- **Opportunity:** schema only has the two Place fields (no Account/Address/Contact). Account carryover to Opportunity is **impossible without new fields**. Scope it as optional Place-sync or descope.

---

## 1. Current state (verified)

### Entry point
The conversion is triggered by the **Quote Quick Action "Convert Quote to Order"** (`Quote.Convert_Quote_to_Order`, `type=Flow`, `flowDefinition=Fortra_Quote_to_Order_Conversion`). Clicking it runs that flow, which creates the Order — so all field-copy logic must live in this flow (or the invocables it calls) to run within the same click. There is no separate/secondary conversion entry point. The flow's own description notes *"Custom field mapping is handled via Context Definition configuration in Setup"* (Revenue Cloud Context Mapping Engine) — that engine can do direct `Quote field → Order field` copies but **cannot traverse `Place.Account__c`**, and the Quote has no Account field, so the Bill/Ship To **Account** derivation must remain Apex. (The two Place *lookups* could potentially be added to the Context Definition instead of Apex — a lighter alternative for those two fields only.)

### Conversion pipeline order
`createOrderFromQuote` (standard) → `SplitPowerOrderLines` / `PowerOrderSplittingService` → `Get_Created_Order` → **`Update_Order_Record_with_Bill_to_Ship_To_Address`** → `Decision_Create_Contract_Record` → … → SC-3308 reprice-before-activate → activation/Workday.

### What's mapped today

| Target | Object | Source | Where | Status |
|---|---|---|---|---|
| `Bill_To_Address__c` | Order (header) | `Quote.Bill_To_Place__c` | flow `Update_Order_Record_with_Bill_to_Ship_To_Address` (`...flow-meta.xml:1431-1436`) | ✅ done |
| `Ship_To_Address__c` | Order (header) | `Quote.Ship_To_Place__c` | same flow element (`:1437-1443`) | ✅ done |
| `Ship_To_Address__c` | **OrderItem (line)** | `Quote.Ship_To_Place__c` | `QuoteToOrderFieldMapper.cls:115-118` | ✅ done (complementary, different object) |
| `Hardware__c`, `Hardware_ID__c` | OrderItem | QLI same fields | `QuoteToOrderFieldMapper.cls` | ✅ done |
| `Partition_Record__c` | OrderItem | `QLI.Partition_Reference__c` | `QuoteToOrderFieldMapper.cls` | ✅ done |
| `Bill_To_Place__c` | Order (header) | `Quote.Bill_To_Place__c` | createOrderFromQuote / Context Mapping | ✅ **already populated** (see §2a) |
| `Ship_To_Place__c` | Order (header) | `Quote.Ship_To_Place__c` | createOrderFromQuote / Context Mapping | ✅ **already populated** (see §2a) |
| `Bill_To_Account__c` | Order (header) | *(derive)* `Order.Bill_To_Place__r.Account__c` | — | ❌ **gap (blocking)** |
| `Ship_To_Account__c` | Order (header) | *(derive)* `Order.Ship_To_Place__r.Account__c` | — | ❌ **gap (blocking)** |

> **§2a — Q4 data (FortraUAT, 2026-06-05, n=28,949 Orders):** `Bill_To_Place__c`=21,353 / `Ship_To_Place__c`=15,390 populated, but `Bill_To_Address__c`/`Ship_To_Address__c`=154 each and `Bill_To_Account__c`=157 / `Ship_To_Account__c`=153. The flow element only assigns the two `*_Address__c` fields — yet **0** converted Orders have Address-without-Place, proving the Place lookups are populated upstream by `createOrderFromQuote`/Context Mapping. Place and Address are the **same Places record** ~98% of the time (Bill 97.9%, Ship 98.9%; mismatches = manual overrides `00095328`, `00095256`). **Conclusion:** do not map Place lookups; derive the Account from the Order's own (already-populated) Place. Data: [Data/sc3339/schema/order_place_addr_sample.json](../../../Data/sc3339/schema/order_place_addr_sample.json).

### The mapper is line-level only
`QuoteToOrderFieldMapper` (invocable, input = `orderId` only) queries `OrderItem WHERE OrderId = :orderId AND QuoteLineItemId != null` and patches OrderItem fields. **It never touches Order header fields.** No local test class exists → **0% coverage** (a 4-method line-level test exists in UAT and in `Data/apexguru-review/corpus/`, but covers no header logic and not the line `Ship_To_Address` mapping).

---

## 2. The central gap: where does Bill/Ship To *Account* come from?

The Quote has **no** `Bill_To_Account__c` / `Ship_To_Account__c`. Its only Account-typed fields are `AccountId` (read-only), `PartnerAccountId`, `Billing_Partner__c`, and `Account_Billing_Account__c` (→ **AccountBillingAccount**, a *different* object — type mismatch against an Account lookup).

**Resolved derivation — the Place's parent Account:**

```
Order.Bill_To_Account__c  =  Quote.Bill_To_Place__r.Account__c
Order.Ship_To_Account__c  =  Quote.Ship_To_Place__r.Account__c
```

Evidence:
1. `Places__c.Account__c` is a **required** (`nillable=false`) lookup to Account → every Place always carries a derivable Account. ([Data/sc3339/schema/Places__c.describe.json](../../../Data/sc3339/schema/Places__c.describe.json))
2. **Live correlation (FortraUAT):** `SELECT Id, Bill_To_Account__c, Bill_To_Place__r.Account__c FROM Order WHERE Bill_To_Place__c != null AND Bill_To_Account__c != null LIMIT 200` → 153 rows, **152 match** (99.3%); Ship side 14/14 in the first sample.
3. It is **not** `Quote.AccountId` (null on some Quotes where the Place's Account is populated) and **not** `Account_Billing_Account__c` (wrong type).

> ⚠️ **Nuance flagged by the adversarial pass:** the 99.3% is an *observed correlation*, not a proven mechanism — it strongly indicates the Place's Account is the intended source, but the single mismatch (Order `00095328`: account `001WC00000dsGKgYAM` vs Place account `001WC00000QBhaXYAT`) proves the Account can legitimately diverge (manual / partner-billing override). **Therefore: derive from `Place.Account__c`, but only when the Order field is currently null — never overwrite a deliberately-set value.** Final confirmation of the override/null rules is an open question (§7).

> ❌ **Reject** the `OrderMigrationBatch.cls:613` pattern `ord.Bill_To_Account__c = quote.Account_Billing_Account__c` — it's a legacy/migration artifact with a type mismatch (AccountBillingAccount ≠ Account) and doesn't handle Ship side at all.

---

## 3. Recommended implementation

**Why Apex (not pure flow):** the Account derivation needs a relationship traversal (`Place → Account__c`) that a flow `recordUpdate` can't do in one hop — the flow only holds the Place *Id*, not the Place's Account.

1. **Extend `QuoteToOrderFieldMapper.cls`** with a header method. Given the Order(s), resolve `Order.QuoteId`, then:
   ```sql
   SELECT Id, Bill_To_Place__c, Bill_To_Place__r.Account__c,
              Ship_To_Place__c, Ship_To_Place__r.Account__c
   FROM Quote WHERE Id IN :quoteIds
   ```
   Set **only when the Order field is null** (idempotent, preserves overrides):
   `Bill_To_Place__c`, `Ship_To_Place__c`, `Bill_To_Account__c` (= bill Place's Account), `Ship_To_Account__c` (= ship Place's Account). **Do not** touch `*_Address__c` (the flow owns those). Bulkify across `List<MapRequest>` (collect orderIds → one OrderItem query, one Quote query, one Order DML). Keep `with sharing`; verify FLS on the two Account fields.

2. **Wire into the flow** *(retrieve the current UAT flow as the edit base — see §5)*. Place the new invocable call **after** `Get_Created_Order` / the address update and **before** `Decision_Create_Contract_Record` (`locationY ~2249`), so it runs after power-split and before SC-3308's reprice (`locationY 2780/3272`) and before Workday-submission validation. Optionally add the two Place-lookup assignments to the existing `Update_Order_Record_with_Bill_to_Ship_To_Address` element — or do all four fields in the one Apex call to avoid two write points on the same Order in one transaction.

3. **Create `QuoteToOrderFieldMapperTest.cls`** (seed from the corpus, add header coverage) — see §6.

4. **Confirm `Order_Submit_Validation__mdt` X00024/X00025** — no mdt change needed; add an end-to-end assertion that a converted Order passes `FieldPopulatedCheck` for both Account fields.

5. **(Optional, gated)** Opportunity Place sync — see §4.

---

## 4. Opportunity scope

Opportunity has **only** `Bill_To_Place__c` / `Ship_To_Place__c` (→ Places__c, updateable) — **no** Account, Address, or Contact Bill/Ship fields. The conversion flow performs **zero Opportunity DML** today. So "confirm Opportunity" can only mean syncing those two Place lookups (`Quote.*_Place__c → Opportunity.*_Place__c`), via one `recordUpdate` on `OpportunityId`, placed post-order-creation so it never blocks conversion. **Account carryover to Opportunity is schema-impossible.** Recommend: build only if stakeholders confirm; otherwise descope (the primary value — Order Account/Place for Workday — is entirely Order-side).

---

## 5. Coordination & non-conflicts

- **SC-3308** is **already deployed to FortraUAT** (`OrderRepriceInvocable` + test exist; flow has `Reprice_Order_Before_Activate` gated on `CompletedWithPricing` & `validationResult IsNull`). It runs **downstream** of the header update → **no field overlap, no sequencing conflict.** Populating the Accounts *before* reprice/activation **helps** SC-3308 pass pre-activation validation.
  - ⚠️ **Edit-base risk:** SC-3308's flow + `OrderRepriceInvocable` are **not in local `force-app`**. **Retrieve the current UAT flow as the edit base** and diff-verify the reprice elements survive — editing a pre-3308 local/`Data` copy would silently drop deployed reprice logic on deploy.
- **Power-split:** `PowerOrderSplittingService` is line-level only (its sole Order-header DML is `Order.ValidationResult = null` at `:286`); runs before the header update. **No regression risk.**
- **Existing automation:** no automation writes `Bill_To_Account__c`/`Ship_To_Account__c` in the conversion path. `Fortra_Order_Submission_Check` and the X00024/X00025 mdt only **read** them (for Workday validation) → populating them satisfies, not conflicts. No field defaults/formulas on any of the six target fields.

---

## 6. Test strategy (target ≥75%, meaningful assertions)

Seed `QuoteToOrderFieldMapperTest.cls` from `Data/apexguru-review/corpus/` (4 existing line-level methods), then add:
- `testDerivesBillShipAccountFromPlaceParent` — Account + two Places (Bill/Ship, `Account__c` set) + Quote → assert `Order.Bill_To_Account__c`/`Ship_To_Account__c` equal the Places' parent Accounts and `Bill_To_Place__c`/`Ship_To_Place__c` populated.
- `testDoesNotOverwriteExistingAccount` — pre-set a *different* Account → assert unchanged (locks in the `00095328` override rule).
- `testNullPlaceLeavesAccountNull` — null `Bill_To_Place__c` → Account stays null (+ fallback if implemented).
- `testBulkTwoOrdersOneInvocation` — ≥2 `MapRequest`s → correct per-order mapping; assert `Limits.getQueries()` well under 100.
- `testLineShipToAddressStillMapped` — covers the currently-untested `QuoteToOrderFieldMapper.cls:115-118`.

Every assertion checks an actual field **value** (`Assert.areEqual` with messages), not just record existence. Add an integration-style assertion that a converted Order would pass `FieldPopulatedCheck` for X00024/X00025.

---

## 7. Open questions for stakeholders

1. **Override rule:** For the ~0.7% where Bill To Account should differ from the Place's Account (partner/distributor billing, manual override per `00095328`) — is "derive from `Place.Account__c`, never overwrite a pre-set value" correct, or should `Billing_Partner__c` / `PartnerAccountId` win for Bill To specifically?
2. **Null-Place fallback:** When `Quote.Bill_To_Place__c` (or Ship) is null, should the Order Account stay null (and fail X00024/X00025, forcing manual completion), or fall back to `Quote.AccountId`/another default?
3. **Independence:** Can `Bill_To_Account__c` and `Ship_To_Account__c` be *different* Accounts on one Order, or always the same? (Determines per-Place vs shared derivation.)
4. **Opportunity:** In scope? If yes, confirm it's limited to the two Place fields, direction, and timing (post-creation, non-blocking).
5. **Place vs Address pair:** Should the Order `*_Place__c` lookups be populated (currently only `*_Address__c` are), or are `Bill_To_Place__c` and `Bill_To_Address__c` meant to be the same Place such that only one is needed?
6. **Downstream:** Are `Bill_To_Account__c`/`Ship_To_Account__c` consumed by Workday/downstream beyond X00024/X00025 in a way that constrains acceptable values?

---

## 8. Risks

- Derivation is 99.3% not 100% → guard with null-only write (idempotent).
- Bulkification: the header method must batch the `Place→Account` traversal across the invocable list or risk SOQL-101 on mass conversion.
- Editing the wrong flow base (drops deployed SC-3308 reprice) → retrieve fresh + diff-verify.
- Null-Place Quotes → converted Orders fail X00024/X00025 (correct, but may spike submission failures; confirm frequency).
- FLS/CRUD on the two Account fields for the conversion-running context.
- No CI coverage gate today (mapper at 0% local) → ship the test class with the change or risk dropping org coverage below the deploy gate.
