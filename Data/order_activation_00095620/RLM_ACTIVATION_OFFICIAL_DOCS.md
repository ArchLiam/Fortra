# Order Activation, Status, and Pricing-Validation Reference — Revenue Lifecycle Management (RLM / Revenue Cloud Advanced)

> Synthesized from a 15-agent doc-research workflow (8 finders → 6 adversarial verifiers → synthesis), grounded in the **Revenue Management Developer Guide v67.0 (Summer '26)** and **SOAP API Developer Guide v67.0**. JS-rendered help pages corroborated by title/snippet where verbatim quotes weren't fetchable.

## Headline corrections / confirmations

- **Gate 1 (contract-must-be-Activated) is NOT documented Salesforce platform behavior.** `FAILED_ACTIVATION` is the generic SOAP code "The activation of a Contract failed." No official page gates *Order* activation on its related Contract's status; docs describe contracts generated *from* orders, and KB 000387771 says orders can activate *without* a contract. The literal string `This order's contract is inactive` appears in **no** official source → **most likely org/managed-package validation, not native platform.** Action: identify what emits it in-org.
- **Gate 2 (ValidationResult) is officially CONFIRMED.** `Order.ValidationResult` is a real RCA-licensed field: *"Specifies whether the order was configured and priced. Orders can be activated only after they're configured and priced."* Values: `MissingContributor`, `TransactionIncomplete`. Blank/null = activatable. It is **createable/updateable** (so clearing it via DML is a documented-capable operation).
- **`CalculationStatus` ≠ `ValidationResult`** (confirmed distinct). `CalculationStatus` is **read-only**; `Saving` is the rep-facing *label* for `ReconciliationInProgress` (not an API value); `CompletedWithoutPricing` shows to reps as "Unknown".
- **"Update Status" updates `Order.Status` only; it does not activate the Contract** (confirmed). Activation = setting Status to an Activated-category value; Status is the only field updatable at activation.

---

## 1. Object model — quote→order→contract→asset

RLM/RCA reuses **standard** sales objects (not CPQ `SBQQ__`).

```
Quote ──(Create Order From Quote)──▶ Order ──(Status→Activated)──▶ Asset (Assetize)
  │                                    │
QuoteLineItem ────────────────────▶ OrderItem ──▶ AssetAction / AssetStatePeriod / AssetActionSource
  │                                    │
  └──(Create Contract)──────────────▶ Contract ──▶ Sales Contract Line
                                        │
                                 AssetContractRelationship
```

Key relationship fields: `Order.QuoteId`, `OrderItem.QuoteLineItemId`, `Order.ContractId` (updatable only while StatusCode=Draft), `AssetContractRelationship`.

## 2. Field reference (official)

### Order.Status / Order.StatusCode (Status Category)
- Status: org-defined picklist; each value maps to a StatusCode category. *"the Status field is the only field you can update when activating the order."*
- StatusCode categories: `Draft`, `Activated`, `Superseded` (RCA-only, API 64.0+).

### Order.ValidationResult — the activation gate ✅ confirmed
- *"Specifies whether the order was configured and priced. Orders can be activated only after they're configured and priced. Available in API version 61.0 and later."* RCA-licensed. Properties: **Create, Filter, Group, Nillable, Restricted picklist, Sort, Update**.

| Value | Meaning |
|---|---|
| (blank/null) | Configured & priced — activatable (documented explicitly for Quote; `"ValidationResult": null` in completed-order REST examples). |
| `TransactionIncomplete` | "the order wasn't configured and priced." Set when a line is changed outside the standard pricing flow; cleared by repricing. |
| `MissingContributor` | "the order contains a derived product but not its pricing source." Config/data problem — repricing alone won't clear it (cf. SC-3372). |

> No `Success`/`ValidationSuccessful` value exists. Passing = blank.

### OrderItem.ValidationResult
- *"An order can be activated only after all its order items are configured and priced."* Single value: `Warning` ("the order item isn't configured and priced"). **OrderItem has no CalculationStatus.**

### Order.CalculationStatus — read-only, separate concern ✅ confirmed
- *"The status of the price and tax calculations for the order. … read-only … API version 61.0 and later."*

| Value | Meaning | Rep label |
|---|---|---|
| CompletedWithPricing | pricing complete, tax next | |
| CompletedWithTax | pricing + tax complete (terminal success) | |
| CompletedWithoutPricing | pricing/tax skipped | **Unknown** |
| ReconciliationInProgress | data arrangement in progress | **Saving** |
| SaveFailedOrIncomplete | recent changes not saved | Some Records Weren't Saved |
| PriceCalculationFailed / TaxCalculationFailed / TaxCalculationWaiting | pricing/tax failures/waits | |
| ConfigurationFailed / ConfigurationInProgress / OrderRequestFailed / OrderRequestPartiallySaved / ReconciliationFailed / GroupRampConfigurationFailed | config/save/reconcile states (v62/65) | |

> `NotStarted`/`InProgress`/`Saving`/`Failed`/`Completed` are **not** API values. "Saving" we saw in logs = `ReconciliationInProgress`.

### Contract.Status
- *"Client applications must initially create a Contract in a non-Activated state … set Status to Activated; the Status field is the only field you can update when activating the Contract."* Categories: Draft, InApproval, Activated (+Terminated/Expired, not API-available; +Salesforce Contracts states when enabled).

### SOAP ExceptionCodes
- `FAILED_ACTIVATION` = "The activation of a Contract failed." · `INVALID_INPUT` = generic invalid input. The detail sentences are **application-layer**, not documented.

### Pricing inputs
- `TransactionProcessingType.PricingPreference`: **Force** (reprice all lines = "Reprice All"), **System** (delta — only unprocessed lines, when Delta Pricing on), **Skip**.
- `RevenueManagementSettings.enableDeltaPricing` (default false); `hidePriceRefreshNtfcn`.

## 3. "Update Status" & status lifecycle
Activation has no separate verb — it's a Status update to an Activated-category value (stamps ActivatedDate/ById, triggers assetization). The Lightning **Path** is standard on Order; its finalize button is standardly "Mark Status as Complete" (classic Order button = "Activate"). "Update Status" is an org label/quick-action over the same standard mechanism. **Updating Status does not activate the Contract.**

## 4. Activation gates
- **(a) Contract Activated** — empirical only; **not documented** (verdict: unverified/leaning-refuted). Likely org/managed-package validation. **Verify in-org what emits `This order's contract is inactive`.**
- **(b) Configured & priced (ValidationResult blank)** — **documented & confirmed.** Non-blank blocks activation; reprice (Force) clears `TransactionIncomplete`; `MissingContributor` needs the source product. CalculationStatus must reach a Completed* state.

## 5. Pricing/Reprice vs activation
- Reprice All = `PricingPreference=Force` (full recalculation, clears VR). Delta save = `System` (only unprocessed lines → can leave `TransactionIncomplete`). TLE banners aren't the gate; `ValidationResult` is.
- Engine: Run Salesforce Pricing → pricing procedure over a context instance (`contextInstanceId`+`pricingProcedureName`+`effectiveDate`); context/version mismatch leaves `TransactionIncomplete`.

## 6. Reconciliation — our org vs docs
| # | Empirical (FortraUAT) | Doc status |
|---|---|---|
| 1 | `FAILED_ACTIVATION: contract is inactive` on Draft contract | **Not documented — inferred org/managed-package.** Direction contradicts documented order→contract flow. |
| 2 | `…prices aren't updated`; `ValidationResult=TransactionIncomplete` | **Confirmed (field+gate); exact string not documented.** |
| 3 | Activated orders have `ValidationResult=null` | Inferred (documented-by-implication). |
| 4 | Reprice log shows VR=null/CompletedWithPricing; flip to TransactionIncomplete not in any flow/Apex | **Mechanism inferred** (managed-package-internal at save); staleness semantics documented. |
| 5 | `PowerOrderSplittingService` restores VR=null; manual reprice doesn't | **Org custom code.** Field's `Update` property is the documented enabler. |
| 6 | Apex `update VR=null` → activatable | Consistent (field is updateable). **Workaround** — bypasses the configured-and-priced guarantee; would mask `MissingContributor`. |

## 7. Known issue & open items
- Salesforce **Known Issue a028c00000qQ59ZAAS**: "Price Calculation Status requirement prevents activation of orders created outside CPQ" — corroborates a pricing-completion activation gate.
- Open: confirm in-org source of the contract gate (validation rule / flow / Apex / managed pkg); confirm org picklist membership via Tooling describe; verify whether Place Sales Transaction reprice auto-clears VR vs only explicit Reprice All.

**Sources:** RLM Dev Guide v67.0 PDF · [Transaction Mgmt Fields on Order](https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/quote_and_order_capture_fields_on_order.htm) · [Object Reference: Order](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_order.htm) · [Object Reference: Contract](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_contract.htm) · [SOAP ExceptionCode](https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_concepts_errorhandling.htm)
