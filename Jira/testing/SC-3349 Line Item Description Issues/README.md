# SC-3349 — Line Item Description Issues

## ✅ PEER REVIEW COMPLETE (2026-06-07, FortraUAT) — Approved, fix verified live

Peer review of Nir Kailash's fix (subtask **[SC-3352](https://helpsystems.atlassian.net/browse/SC-3352)**, reviewer: Liam Jeong).
**Outcome: approved for UAT.** The fix is correct, byte-verified against the org, renders the device
count live, and is now backed by passing unit tests. One source-control item remains before prod
promotion (see below).

### The bug
On the **beSECURE - Cloud-Based** SKU (attribute-based pricing), the auto-generated
`QuoteLineItem.Description` rendered the Unit Type **`Devices`** but dropped the **device count
`36-65`**. The full string feeds the **Workday** and **Legacy CRM** integrations, so the missing count
broke them. Root cause: the description builder read only the `Attribute_Volume` config attribute, but
this SKU carries its count in a different attribute, **`Number_of_Units`** (picklist, e.g. `36-65`).

### The fix (two parts)
1. **Apex — `QLDescriptionGeneratorPrehook.cls`** (Nir): added a `Number_of_Units` fallback via a new
   `resolveUnitQuantity()` helper. Precedence: `Attribute_Volume` wins when present, else fall back to
   `Number_of_Units`. Behavior-preserving for every existing line.
2. **Config (UI-only) — RLM pricing-prehook chain:** moved `DescriptionLinePrehook` from **before** the
   PricingProcedure to **last** in the chain, matching the class's own `@note Register LAST`.

### Live verification in FortraUAT (2026-06-07)
- **Renders correctly:** the *LineItem Description Nir Test* quote line shows
  `beSECURE - Cloud-Based | Devices: 36-65 | One Time | Cloud Based` and the value **persists** after
  the prehook reorder (confirms the post-PricingProcedure writeback is not silently dropped).
- **API name confirmed:** `AttributeDefinition.DeveloperName = 'Number_of_Units'` exactly
  (Id `0tjWC000000096dYAA`, Code `NU`) — matches the constant case-for-case.
- **Deployed bytes == reviewed source:** a fresh retrieve of the live class is byte-identical to the
  reviewed `QLDescriptionGeneratorPrehook.cls`, so the org runs exactly what was reviewed.
- **Stale lines:** pre-fix beSECURE lines still show bare `Devices`; they pick up the count on **reprice**
  (expected — no post-fix line is missing the count).

### Test class updated + run (Liam Jeong, 2026-06-07)
`QLDescriptionGeneratorPrehookTest.cls` already carried the core `Number_of_Units` cases (the
`apexguru-review/corpus` copy was stale — the *live UAT* test class was current). Added 2 edge cases to
fully close the review recommendation:
- `unitTypeSegment_BlankAttributeVolumeFallsThroughToNumberOfUnits` → `Devices: 36-65`
- `unitTypeSegment_NeitherQuantityAttrRendersBareUnitType` → bare `Devices`

**Result: 35/35 tests pass (100%), 0 failures**, deployed to UAT. (Class-level coverage 32% — the pure
fallback logic is fully covered; `execute()` + context-query methods can't be unit-tested because
`RevSignaling.TransactionRequest` has no public constructor, so they're integration-tested. Pre-existing
structural limit, not introduced here.)

### ⚠️ Before PROD promotion
- **Source control:** `QLDescriptionGeneratorPrehook.cls` + its test are **not in `force-app`** (live only
  in the org + `Data/` retrieves), and the prehook reorder is **UI-only** RLM config (not in the
  `expressionSetDefinition`). Capture both — commit the class + test to `force-app` and document the
  chain reorder as a change-controlled runbook step — so the fix is reproducible in prod and survives a
  sandbox refresh. Parts A + B are coupled (the fallback only renders correctly when the prehook runs last).
- **Confirm with integration owners (non-blocking):** (a) the `Number_of_Units` fallback is global —
  other products (e.g. *Device Profiler Ev Express* → `IP: 1-25`) now also gain a `: <count>` suffix;
  confirm that's wanted portfolio-wide. (b) The canonical spec renders a space (`Devices 36-65`) while
  the code emits colon-space (`Devices: 36-65`) — pre-existing, but confirm the Workday/Legacy CRM
  parsers accept the colon.

## Details
- **Type:** Story · **Status:** In Review · **Priority:** Critical
- **Assignee:** Nir Kailash · **Reporter:** Liam Jeong
- **Sprint:** CRM Sprint 14 · **Space:** Salesforce-Coastal
- **Peer review subtask:** [SC-3352](https://helpsystems.atlassian.net/browse/SC-3352) (Assignee: Liam Jeong · Reporter: Nir Kailash)
- **Source ticket:** [SC-3349](https://helpsystems.atlassian.net/browse/SC-3349)

## Components changed
| Component | Type | Change |
|-----------|------|--------|
| `QLDescriptionGeneratorPrehook.cls` | Apex | `Number_of_Units` fallback (`resolveUnitQuantity()`) |
| `QLDescriptionGeneratorPrehookTest.cls` | Apex test | +2 edge-case tests (peer review) |
| Rev Mgmt Default Pricing Procedure — prehook chain | RLM config (UI) | `DescriptionLinePrehook` moved to **last** |

## Test records (FortraUAT)
- **PASS (count renders):** Quote [LineItem Description Nir Test 2026-06-07 09:23](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC00000367I20AI/view) · line [0QLWC000003bKXV4A2](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC000003bKXV4A2/view) → `beSECURE - Cloud-Based | Devices: 36-65 | One Time | Cloud Based`
- **Reprice/refresh demo (bare → count):** Quote [Test Pricing](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC0000034U4D0AU/view) · line [0QLWC000003aarF4AQ](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC000003aarF4AQ/view)
- **Precedence / no-regression (Attribute_Volume):** Quote [UAT Attr Vol Pricing Test Quote --do not delete!](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC000002gBPJ0A2/view) · line [0QLWC00000311rZ4AQ](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC00000311rZ4AQ/view) → `… | Users: 50.0 | …`

## Artifacts
- Verification workspace + updated test class: [`../../../Data/sc3349/verify/`](../../../Data/sc3349/verify/)
- Reviewed class (Nir's fix): [`../../../Data/sc-nir-changes/QLDescriptionGeneratorPrehook.uat.cls`](../../../Data/sc-nir-changes/QLDescriptionGeneratorPrehook.uat.cls)
