# Maintenance (Derived) Pricing — New Business & Renewals — Solution Design

> **Source doc**: `Fortra-Maintenance-Derived-Pricing-Solution-Design_(1).txt` · Client: Fortra · Consultant: Coastal · Version 1.0 · Date: June 9, 2026
> **Purpose (one line)**: Price auto-added maintenance/support lines on Fortra Revenue Cloud (RCA) quotes that otherwise price at ~$0, using RCA configuration + a single before-save record-triggered Flow (NO Apex pricing prehook).

---

## Executive Summary

- Problem: auto-added maintenance and support lines price at **approximately $0** on Fortra's Revenue Cloud quotes.
- Solution: prices these **derived** lines using Revenue Cloud configuration plus **a single record-triggered Flow with NO Apex pricing prehook**.
- Status at hand-off (June 2026):
  - **NEW-BUSINESS branch: BUILT and VALIDATED end-to-end on the `fortrauat` org.**
  - **RENEWAL branch: BUILT but NOT yet validated**, and carries **one open business question (BR-005 / E-001)** that must be resolved before completion.
- The doc reflects state at hand-off of the renewal build to a follow-on engineer.

### Key Features (verbatim specifics)
- New-business maintenance prices from the source license's **pre-discount Base Price × user-selected maintenance tier** (**Premier 30%, Standard 20%, Professional 20%**). Validated live: **base $468 × 20% = $93.60**. Proven **immune to discounts applied to the source license**.
- The maintenance line's **own** partner and discretionary discounts apply **AFTER** the base-times-tier, via existing discount logic. Validated: **a 10% discount produced $84.24**.
- A single **before-save** record-triggered Flow stamps pricing inputs onto the maintenance line; a **quote-type-gated procedure formula** computes the price. **No Apex pricing prehook.**
- Hand-off note: renewal branch is built (a second gated formula element + the Flow's renewal branch) but **UNVALIDATED**, and depends on resolving whether real renewals even produce a separate derived maintenance line.
- Product-data prerequisite: **each maintenance product must carry its tier on the correct line attribute with a valid Premier/Standard/Professional value, or the line prices $0.**

---

## Business Process Flow (sales-user perspective)
- User adds a license product to a new-business quote, OR initiates a renewal; Revenue Cloud **auto-adds** the matching maintenance/support line where applicable.
- New business: the maintenance line prices to **license's pre-discount Base Price × maintenance tier**, then the maintenance line's own partner and discretionary discounts reduce it.
- **Discounting the license itself does NOT pull the maintenance base down** — maintenance always prices from the license's pre-discount Base.
- Renewal (INTENDED behavior): prior maintenance components carry forward, each grown by COLA, then netted — **pending confirmation that a separate maintenance line exists on real renewals**.
- The correct calculation is chosen automatically from the **quote type**.

## Technical Process Flow (sequence)
1. The pricing procedure reads the **quote-type field** and routes the derived maintenance line to one of **two gated formula elements** in the derived container.
2. **New business**: a before-save Flow stamps the source license line's **Unit Price (the pre-discount Base)** onto the maintenance line; the new-business formula multiplies it by the tier and **writes NetUnitPrice, overriding the native derived value**.
3. The maintenance line's own partner and discretionary discounts are applied afterward by the existing discount logic.
4. **Renewal**: the Flow stamps the prior maintenance order line's **Base, partner, and discretionary dollar amounts plus the resolved COLA rate**; the renewal formula grows each by COLA and nets them.
5. The **decision tables are refreshed** so the engine adopts the new configuration.

---

## Solution Components

| Component | Type | Description |
|---|---|---|
| **Stamp Maintenance Pricing Inputs Flow** | Record-Triggered Flow (on **QuoteLineItem**) | The ONLY added automation. New branch (**active**) stamps the source line's Unit Price onto the maintenance line. Renewal branch (**draft**) stamps the prior order line's Base/partner/discretionary plus the resolved COLA rate. |
| **Derived Pricing - New Business** | Pricing Procedure (Formula) | Gated to **New/Net-New**; computes `Base_Price__c × tier` (tier read via **AttributeValue**) and writes **NetUnitPrice**, overriding the native derived value. **VALIDATED.** |
| **Derived Pricing - Renewal** | Pricing Procedure (Formula) | Gated to **Renewal**; **self-gating passthrough on non-renewal**; grows the prior Base/partner/discretionary by COLA and nets them. **BUILT, NOT VALIDATED.** |
| **Derived-Pricing Decision Tables** | Decision Tables (×2) | Refreshed in Setup after derived-pricing data or formula changes. |

> NOTE: The Flow appears under two names in the source: **"Stamp Maintenance Pricing Inputs"** (component table) and API name **`Stamp_Maintenance_Pricing_Inputs`** (dependency D-002). Treat these as the same Flow.

---

## Requirements

### Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| **BR-001** | New-business maintenance prices at the source license's **pre-discount Base Price × user-selected tier** (Premier 30%, Standard 20%, Professional 20%). **VALIDATED.** | High |
| **BR-002** | Base Price includes **attribute, tier, and regional adjustments** but **EXCLUDES partner and discretionary discounts**. Discounting the source license must NOT reduce the maintenance base. **VALIDATED (discount-immune).** | High |
| **BR-003** | The maintenance line's **own** partner and discretionary discounts apply **AFTER** the base is set. **VALIDATED.** | High |
| **BR-004** | Renewal maintenance carries the prior period's **Base, partner, and discretionary discount** forward, each **grown by COLA, then netted**. **BUILT, NOT VALIDATED; depends on BR-005.** | High |
| **BR-005** | **OPEN BUSINESS DECISION**: confirm whether a real renewal produces a **separate derived maintenance line at all**, OR whether maintenance is part of the renewed subscription line (already COLA-uplifted by existing logic). **This determines whether the renewal formula is needed.** | High |

### Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| **TR-001** | **NO Apex pricing prehook** on the maintenance line; the engine owns **NetUnitPrice** on derived lines. The only added automation is **one before-save record-triggered Flow**. | High |
| **TR-002** | New-business base = the source line's **Unit Price (pre-discount, attribute-adjusted)**, Flow-stamped onto **`Base_Price__c`**. The native derived pull returns the source's **post-discount net**, so it is **overridden** by the procedure formula. | High |
| **TR-003** | The tier is read in the formula via **AttributeValue** (the line's **QuoteLineItemAttribute** value); each maintenance product must carry the tier on the correct attribute with a valid **Premier/Standard/Professional** value or the line **prices $0**. | High |
| **TR-004** | Gate signal is **`Quote_Type__c = 'Renewal'`** (**`QuoteTypeText__c`** is its text form). **Confirmed against 124,652 renewal-type quotes.** | Medium |
| **TR-005** | Renewal carry-forward depends on a **new-business order-creation step** that persists the maintenance dollar decomposition onto the order line; **that step is NOT yet built.** | Medium |
| **TR-006** | **Open new-business loose end**: a maintenance line can show **$0 on its first reprice** because the before-save stamp lands **after** the pricing pass; the durable fix is to **stamp the base BEFORE pricing**. | Medium |

---

## Assumptions
| ID | Assumption |
|---|---|
| **A-001** | Each maintenance product is configured with its tier on the attribute the formula's **AttributeValue** resolves to, with a valid Premier/Standard/Professional value. **Mis-tagged products (wrong attribute, or retired values such as `Enterprise Support`) price $0.** |
| **A-002** | The existing **Partner Pricing and discretionary-discount logic** applies the maintenance line's own discounts on **new-business** derived lines and is **EXCLUDED from renewal** derived lines. |
| **A-003** | Real renewal behavior for maintenance must be confirmed: whether renewals generate a **separate derived maintenance line** (like new business) or **fold maintenance into the renewed subscription line**. |
| **A-004** | Renewal validation requires a **real platform renewal**; the renewal branch has NOT been exercised end-to-end. |

## Dependencies

### Internal
| ID | Dependency | Status |
|---|---|---|
| **D-001** | **4 custom currency fields** (`Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c` on **QuoteLineItem** AND **OrderItem**) plus their **context Input mappings**. | **Deployed** |
| **D-002** | Before-save Flow **`Stamp_Maintenance_Pricing_Inputs`** (**v1 active** for new business; **v2 draft** for the renewal branch). | v1 Active / v2 Draft |
| **D-003** | Two procedure formula elements (**Derived Pricing - New Business**; **Derived Pricing - Renewal**) in the derived container. | Deployed; renewal element **not validated** |
| **D-004** | Product-data: maintenance tier tagged correctly per product (Premier/Standard/Professional on the correct attribute). | **Open, Fortra-owned** |
| **D-005** | New-business order-creation step that persists the maintenance dollar decomposition for renewals to carry forward. | **Not built** |

### External
| ID | Dependency | Owner |
|---|---|---|
| **E-001** | A business decision on whether real renewals generate a separate derived maintenance line, which determines whether the renewal formula is needed. | **Fortra** |

---

## Technical Design

### Architecture Overview
- Both branches share **one quote-type-gated formula slot** in the **active pricing procedure**, inside the **derived-line container**, positioned **between** the existing **`Derived Pricing`** filter and the **`Derived Pricing Values Assignment`** (which propagates the formula's NetUnitPrice into the input price downstream).
- The procedure routes the maintenance line to **one of two formula elements**, each **overriding the native derived value**.
- A single **before-save** record-triggered Flow supplies the inputs:
  - New business: stamps the source license line's **Unit Price** onto **`Base_Price__c`**.
  - Renewal: stamps the **prior maintenance order line's Base, partner, and discretionary dollar amounts and the resolved COLA rate**.
- The native derived pull is **overridden because it delivers the source's post-discount net rather than the pre-discount Base.**

### Data Model
- Maintenance and license lines are **standard QuoteLineItem records**; the maintenance line is **derived** and the engine owns its **NetUnitPrice**.
- The source license for a maintenance product is identified by **`PriceBookEntryDerivedPrice.ContributingProductId`**.
- New-business pricing reads the **source line's Unit Price**; renewal pricing reads the **prior maintenance OrderItem**.
- Line-level fields are **context-mapped into the version-2 Sales Transaction context**: `Base_Price__c`, `COLA_Uplift_Percent__c`, and the two new prior-discount fields.
- The maintenance **tier** lives on a **QuoteLineItemAttribute** record (**AttributeName / AttributeValue**) and is read in the formula via **AttributeValue**.
- On **real renewals** the QuoteLineItem also carries **`Replaced_Asset__c`** (the source asset) and **`Source_List_Price__c`**.

#### Custom / referenced fields (name — type/role — notes)
| Field | Object(s) | Type / Role | Notes |
|---|---|---|---|
| `Base_Price__c` | QuoteLineItem (renewal line reuses it) | Currency (pricing input) | Flow-stamped from source `QuoteLineItem.UnitPrice` (pre-discount Base). Context-mapped into v2 Sales Transaction context. |
| `Prior_Partner_Discount__c` | **QuoteLineItem AND OrderItem** | **Currency** (custom, D-001) | Prior period partner discount $; subtracted in renewal formula. |
| `Prior_Discretionary_Discount__c` | **QuoteLineItem AND OrderItem** | **Currency** (custom, D-001) | Prior period discretionary discount $; subtracted in renewal formula. |
| `COLA_Uplift_Percent__c` | QuoteLineItem | Percent/Number (pricing input) | Resolved COLA rate; context-mapped into v2 context. Sourced from COLA hierarchy (line / contract / category). |
| `Quote_Type__c` | Quote | Picklist/gate signal | Gate value `'Renewal'` routes to renewal formula. Confirmed against **124,652** renewal-type quotes. |
| `QuoteTypeText__c` | Quote | Text | Text form of `Quote_Type__c`. |
| `Replaced_Asset__c` | QuoteLineItem (renewals only) | Lookup (source asset) | Present on real renewals. |
| `Source_List_Price__c` | QuoteLineItem (renewals only) | Currency | Present on real renewals. |
| `NetUnitPrice` | QuoteLineItem (derived line) | Standard (engine-owned) | Written/overridden by the procedure formula. |
| `UnitPrice` | Source QuoteLineItem | Standard | Read as the pre-discount Base for new business. |
| `PriceBookEntryDerivedPrice.ContributingProductId` | PriceBookEntryDerivedPrice | Standard lookup | Identifies the source license for a maintenance product. |
| `AttributeName` / `AttributeValue` | QuoteLineItemAttribute | Standard | `AttributeValue` holds the tier (Premier/Standard/Professional); read in formula. |

> The exact SF field data types for `Prior_Partner_Discount__c` and `Prior_Discretionary_Discount__c` are stated as **currency** (D-001: "4 custom currency fields"). `Base_Price__c` and `COLA_Uplift_Percent__c` types are not given a precise SF type keyword beyond their currency/percent roles — do not invent.

#### Field Mappings (source → target, verbatim)
| Source Field | Target Field |
|---|---|
| Source `QuoteLineItem.UnitPrice` (pre-discount Base) | Maintenance `QuoteLineItem.Base_Price__c` (Flow-stamped) |
| Line `QuoteLineItemAttribute.AttributeValue` (tier) | Formula `AttributeValue` (Premier/Standard/Professional) |
| Prior `OrderItem` Base / partner $ / discretionary $ | Renewal line `Base_Price__c` / `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` (Flow-stamped) |
| COLA hierarchy (line / contract / category) | `QuoteLineItem.COLA_Uplift_Percent__c` |

### Business Logic (exact formulas)

**New business** (gated **New/Net-New**):
```
NetUnitPrice = Base_Price__c × tierRate
```
where `tierRate` is read via **AttributeValue** and mapped:
```
Premier      → 0.30
Standard     → 0.20
Professional → 0.20
else         → 0        (the "$0 tier")
```
- The line's own partner and discretionary discounts are then applied by the **existing discount logic** (AFTER base×tier).
- **Validated**: `$468 base × Standard (0.20) = $93.60`; **immune to a 20% discount on the source**; a **10% maintenance-line discount yields $84.24**.
- A maintenance product whose tier is on the **wrong attribute** or holds a **retired value (such as `Enterprise Support`)** falls to the **$0 tier**.

**Renewal** (gated **Renewal**):
```
NetUnitPrice = (Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA / 100)
```
- **Self-gating**: on **non-renewal** quotes it returns **NetUnitPrice unchanged** (passthrough).
- **BUILT but NOT validated.** Its premise (that a separate derived maintenance line exists on renewals) is **unconfirmed**: real platform renewals observed to date **renew the license/subscription line directly with COLA already applied**, and **do NOT produce a separate derived maintenance line**.

> Note: The `× (1 + COLA/100)` form implies `COLA_Uplift_Percent__c` is expressed as a **whole-number percent** (e.g. 3 = 3%), not a fraction. Rounding mode is **not specified** in the source — do not assume one.

### Integration Points & Sequence
- **No external integrations.**
- The solution **composes with**:
  - the native **Derived Pricing Data Retrieval** element (**overridden**),
  - the existing **Partner Pricing and discretionary-discount logic** (reused for new business),
  - the existing **COLA rate hierarchy** (reused by the Flow),
  - the existing **license-renewal COLA logic** (which already uplifts renewed subscription lines),
  - the two **derived-pricing decision tables** (refreshed after changes).
- **Verified platform behavior**: derived-pricing data/formula changes **do NOT take effect on a reprice until the relevant decision table is refreshed.**

---

## Open Issues / Risks
- **BR-005 / E-001 (BLOCKER for renewal branch)**: Unconfirmed whether real renewals emit a separate derived maintenance line. Observed platform behavior contradicts the renewal premise (renews subscription line directly with COLA already applied). If confirmed folded-in, the **renewal formula is not needed**.
- **TR-006 (new-business loose end)**: First-reprice **$0** because the before-save stamp lands **after** the pricing pass. Durable fix = **stamp the base before pricing**.
- **TR-005 / D-005 (renewal prerequisite, NOT built)**: The new-business order-creation step that persists the maintenance dollar decomposition onto the order line does not exist yet; renewal carry-forward cannot work without it.
- **D-004 (Fortra-owned, open)**: Product tier data hygiene; mis-tagged products silently price $0.

---

## CODE-GOVERNING RULES (an engineer refactoring this MUST NOT violate)

1. **NO Apex pricing prehook on the maintenance/derived line.** (TR-001) The engine owns `NetUnitPrice` on derived lines. The ONLY added automation is one **before-save record-triggered Flow** on QuoteLineItem plus procedure formula elements. Do not introduce a prehook to compute maintenance price.

2. **New-business base = source `QuoteLineItem.UnitPrice` (pre-discount, attribute-adjusted), stamped onto `Base_Price__c` by the Flow.** (TR-002, BR-002) Do NOT source the base from the native derived pull — that returns the source's **post-discount net**, which is why the formula overrides it. The base MUST remain **immune to discounts applied to the source license** (`$468 × 0.20 = $93.60` even with a 20% source discount).

3. **New-business formula = `Base_Price__c × tierRate`, then existing discount logic applies AFTER.** (BR-001, BR-003) Order is non-negotiable: base×tier FIRST, then the maintenance line's OWN partner/discretionary discounts (validated `10% → $84.24`). Do not apply the maintenance line's discounts before the tier multiply, and do not let the source line's discounts enter the base.

4. **Tier rates are exactly: Premier 0.30, Standard 0.20, Professional 0.20, else 0.** (BR-001, Business Logic) Any value not in {Premier, Standard, Professional} (including wrong attribute or retired values like `Enterprise Support`) MUST fall to the **$0 tier**. Do not add silent defaults that mask mis-tagged product data.

5. **Tier is read via `AttributeValue` from the line's `QuoteLineItemAttribute`.** (TR-003) Keep the tier read on the QuoteLineItemAttribute; each maintenance product must carry a valid Premier/Standard/Professional value on the correct attribute or it prices $0.

6. **Quote-type gate signal is `Quote_Type__c = 'Renewal'` (`QuoteTypeText__c` is the text form).** (TR-004) Routing between the two formula elements MUST use this signal. Do not change the gate field/value.

7. **Renewal formula = `(Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA/100)`, and MUST self-gate: return `NetUnitPrice` UNCHANGED on non-renewal quotes.** (BR-004, Business Logic) The passthrough behavior on non-renewal is load-bearing (both formulas live in one shared slot). Renewal discounts are NOT re-applied by the existing discount logic (A-002 — existing discount logic is EXCLUDED from renewal derived lines); the prior discounts are already subtracted in the formula.

8. **Both formula elements live in the derived-line container BETWEEN the existing `Derived Pricing` filter and `Derived Pricing Values Assignment`, and each OVERRIDES the native derived value.** (Architecture) Do not move them outside this ordering; `Derived Pricing Values Assignment` propagates the formula's `NetUnitPrice` downstream.

9. **After any derived-pricing data or formula change, the two derived-pricing decision tables MUST be refreshed** — changes do NOT take effect on a reprice until refresh. (Integration Points, Component table) Include this in any deploy/runbook.

10. **The 4 custom currency fields (`Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c` on BOTH QuoteLineItem AND OrderItem) plus their context Input mappings into the v2 Sales Transaction context are required infrastructure.** (D-001) Also context-mapped: `Base_Price__c`, `COLA_Uplift_Percent__c`. Do not drop these fields or their context mappings.

11. **Source license identity = `PriceBookEntryDerivedPrice.ContributingProductId`.** (Data Model) Use this to identify the source license for a maintenance product; do not substitute another linkage.

12. **Renewal carry-forward requires a new-business order-creation step that persists the maintenance dollar decomposition onto the OrderItem — this is NOT built (D-005/TR-005).** Any renewal work MUST first build this persistence step; the renewal branch cannot function without it.

13. **Do not "complete" the renewal branch until BR-005/E-001 is resolved.** (Exec summary, A-003) Observed real renewals renew the subscription line directly with COLA already applied and produce NO separate derived maintenance line. If that holds, the renewal formula is unnecessary — do not ship it as-is.

14. **New-business first-reprice $0 (TR-006) must be fixed by stamping the base BEFORE the pricing pass, not by post-hoc reprice hacks.** The stamp currently lands after pricing; the durable fix is ordering, not a second reprice trigger.
