# Derived Pricing — Demo Quote (BoKS)

Built 2026-06-29 for Marc DeBrey's "Train the Trainer – Derived Pricing" session.

## Demo record
- **Quote:** `0Q0WC000003FKRJ0A4` — "Q-DERIVED PRICING DEMO (BoKS) - 2026-06-29"
- URL: https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view
- Opportunity: `006WC00000RZUTVYA5` (Train the Trainer - Derived Pricing) · Account: Fortra, LLC - Test · Fortra Price Book / USD

## Final priced state (correct)
| Line | Product | List | Net |
|---|---|---|---|
| Powertech Identity & Access Manager (BoKS) | PIA-PIA-NRPS-PIAP | 355 | **355** |
| ...-NewMaintenance | PIA-PIA-RNM-PIAMBK | 0 | **71** (= 0.20 × 355) |
Subtotal/Total/Grand = 426.

## Why BoKS works and Marc's Tripwire quote (00781365) did not
- Active proc = **Rev Mgmt Default Pricing V16** — it **does** contain the Derived Pricing build (List Container 9 → "Derived Maintenance Net Filter" `ItemIsDerived__std = true` → "Derived Pricing Formula"). Per Nir 2026-06-29, everything per SC-3346 is in V16; the only design bug (Net Unit Price) was fixed last week.
- V16 derived formula = `tier × IF(Base_Price__c>0, Base_Price__c, IF(Pre_Partner_Price__c>0, Pre_Partner_Price__c, IF(InputUnitPrice>0, InputUnitPrice, 0)))`, where tier is keyed on the **Maintenance Type** `AttributeValue` (Expert .35 / Premier .30 / Express .30 / Premium .24 / Standard .20 / Professional .20 / Basic .15, else 0).
- Tripwire (FIM) lines net $0 because, per Nir, they are **BUNDLE ITEMS that Fortra delivered in the WRONG BUNDLE FORMAT** (Fortra to clean) — never rectified. Concretely they (a) carry **no Maintenance Type attribute** → tier = 0, and (b) Tripwire Enterprise (TEP) has **$0 catalog list** in all 20 PBEs → nothing to derive from. Not a code bug.

## Build recipe (reproducible)
1. Insert Quote + license QLI (PIAP) + maintenance QLI (PIAMBK) via **Apex** (Quote/QLI DML allowed in UAT).
2. Add attributes via **REST** (`/sobjects/QuoteLineItemAttribute`) — Apex DML on this managed/virtual object errors "use insertImmediate".
   - License needs **Feature Options = Standard** (`0tjWC000000096ZYAQ` / `0v6WC0000000A2UYAU`) — without it the license nets **$0**.
   - Maintenance needs **Maintenance Type Defn = Standard** (`0tjWC000000096bYAA` / `0v6WC0000000A5WYAU`) → 0.20 tier.
3. Force-reprice: `POST /connect/rev/sales-transaction/actions/place` with `pricingPref=Force`, `configurationMethod=Skip`, graph = Quote PATCH by id. (`reprice_body.json`)
4. Result: license 355, maintenance 71. (SLP is auto-stamped to 355 by the before-save flow; the maintenance derives via the InputUnitPrice fallback = 355.)

Note: the authentic rep flow is to add ONLY the perpetual license and let the **Config Rule auto-add** the maintenance (Nir's USE CASE). This demo was assembled line-by-line to produce a clean, correct finished example; the end state is identical.
