# Maintenance (Derived) Pricing — Ticket spec + owner's hand-off (transcribed from ticket screenshots, 2026-06-11)

## A. Client requirement (ticket body — "Auto-Add First Year Maintenance and Additional Year Renewal Pricing")
- **New business (Year 1):** maintenance list = source perpetual license **Base Price × tier %** (Standard 20%, Premier 30%, Professional 20%). Base Price = price incl. attribute/tier/regional adjustments but **NOT** partner/discretionary discounts. Final = base×tier − partner − discretionary (the maintenance line's OWN discounts, applied after the base).
- **Renewal (Year 2,3…):** carry the prior contract's maintenance line forward as **three dollar components** (Base, Partner$, Discretionary$), grow each by COLA, then net: `(PriorBase − PriorPartner − PriorDiscretionary) each ×(1+COLA)`.
- Worked example (Leah Guenther image, 3% COLA): license base 1000 −100 partner −200 sw = 700 net; New Maint 200 (=1000×20%) −20 −40 = **140**; Renewal Yr2 206 −20.60 −41.20 = **144.20**; Yr3 = **148.53**. KEY: maintenance base is 20% of the license's **pre-discount** 1000, not its 700 net.
- Both branches share ONE quote-type-gated formula slot (List Container 9, after Volume Discounts, before Quantity×Price), gated on `Quote.QuoteTypeText__c`, both read Flow-stamped inputs and write **NetUnitPrice**. **No Apex pricing prehook on the maintenance line** (the design's stated principle).

## B. Design's own "Build Instructions" self-reported status (from ticket body)
- Step 1 Gating validation (selling-model backfill) — ✅ DONE / validated 2026-06-08 (PIA-PIA-NRPS-PIAP → PIA-PIA-RNM-PIAMBK priced $71.00).
- Step 2 New-business stamp branch of Flow — ✅ DONE.
- Step 3 New-business formula in Container 9 (Base_Price__c × tier, MaintenanceType__c) — ✅ DONE (validated 468×0.20=$93.60).
- Step 4 Verify maintenance line's own partner/discretionary discounts apply on derived line — ✅ DONE (claimed).
- Step 5 Persist maintenance dollar decomposition at order creation — ✅ DONE (claimed).
- Step 6 Renewal stamp branch of Flow (3 components + COLA) — ✅ DONE (claimed).
- Step 7 Renewal formula in Container 9 — ✅ DONE (claimed).
- Step 8 Selling-model backfill (~85 products) — ✅ LOADED 2026-06-08.
- Step 9 Source-config / tier cleanup (Unit Volume attr, straggler tiers, restore test formulas) — ⬜ **OPEN (product-data, Fortra-owned)**.
- Step 10 Decision-table refresh ×2 — 🔁 as needed.
- Step 11 E2E verification — 🟡 **PARTIAL — new business validated; renewal PENDING.**

## C. Owner hand-off — Nir Kailash "Quick Update" (2026-06-10 08:38)
- **Done:** New-business maintenance pricing working in UAT. Quotes derive maintenance from license, apply 15% software / 12% maintenance partner rates, convert to order with renewal carry-forward fields (base, prior partner $, prior discretionary $) persisting. Quote-to-order E2E validated.
- **In progress:** Renewal maintenance. Core automation built (quote-type stamping, line cleanup handler, prior-$ stamp flow, config rules Yr1+Yr2), have an activated contract w/ assets to test.
- **Two blockers during renewal testing:**
  - **(B1)** Renewing **both assets at once fails in the pricing procedure before a quote is created**.
  - **(B2)** The maintenance-only **workaround copies the Year-1 product onto the renewal quote instead of swapping to Renewal Maintenance** — the Year-2 config rule only runs in TLE when a license is on the cart.
- **Open:** Full renewal E2E (TLE configure → RRM → reprice → Q2O); auto-populating renewal quote headers from contract; a **context-definition mismatch that blocks programmatic reprice** in some paths.
- **Bottom line:** "New business is essentially done. Renewal is the active focus, design and code are in place, but the platform renew path needs one more pass."

## D. Implementation Summary — "Derived Maintenance / Source List Price" (Nir, 2026-06-08)
- New quote Yr1 — PASS. Quote→Order→Contract/Assets — PASS (note `Unable to fetch tags: [Source_List_Price__c]` on order reprice). **Asset Renew → Renewal Quote generation — FAIL** ("Renew from Contract 00069201 fails during inline pricing").
- Renewal failure detail: pricing aborts in **Rev Mgmt Default Pricing V9** at header step `TotalLineDiscountAmount`: **`Null Value cannot be aggregated value[0E-16, null]`** — renewal quote rolled back, no draft persists.
- Disabled in code: `SourceListPricePrehook`, `SourceListPriceResolver`, renewal handlers (`QuoteRenewalTypeHandler`, `RenewalQuoteLineHandler`), Q2O `Source_List_Price__c` mapping in `QuoteToOrderFieldMapper` (commented out per latest request). [NOTE: now superseded by today's rework — verify live.]
- Test products: BoKS PIA-PIA-NRPS-PIAP (perpetual license), PIA-PIA-RNM-PIAMBK (New Maint Yr1), PIA-PIA-RRM-PIAM (Renewal Maint Yr2+). Contract 00069201 (800WC00000RzLBFYA3). Config rule Year2 = 14OWC0000022Eyb2AE (AutoAdds RRM when perpetual + QuoteTypeText__c=Renewal).

## E. Marc DeBrey blocker (2026-06-09 07:56, Slack)
- "Still getting the error when repricing an Order: **Pricing Calculation Error: Specify the contextDefinitionName that's used in the expression set and provide a value for the context definition and try again.**"
- Marc's theory: "two pricing discovery procedures activated, and there should only be one … SF needs to delete the wrong one … some kind of corruption issue."
- Cross-ref prior RCA `project_reprice_contextdef_error`: error attributed to an in-place edit of LIVE active pricing procedure without re-syncing context `SalesTransactionContextExt_v2`; SC-3308 convert path is the victim/surfacing channel. LIVE-CAPTURE confirms FOUR discovery procedures are active.

## F. Cross-ticket entanglement (this build shares code/fields with)
- **SC-3350 COLA renewal pricing** — shares COLAUpliftHandler/Prehook, COLA_Uplift_Percent__c, the renewal 3-component formula `DerivedPricingRenewals`, and the $0-NetUnitPrice family. SC-3350's own RCA proved an in-procedure renewal-net seed is a DEAD END (engine owns NetUnitPrice on the waterfall) and the only working lever was the COLA PREHOOK seeding NetUnitPrice — which CONTRADICTS this ticket's stated principle "No Apex pricing prehook on the maintenance line." Reconcile.
- **SC-3359** Partner Pricing net not applied — shares PartnerNetPricePosthook (the partner-discount step). SC-3359 found active V9 SubscriptionPricing74 writes InputUnitPrice not net.
- **SC-3372** "add contributing products" — same IsDerived maintenance PBE / DerivedPricingDataRetrieval native element this design proposes to remove.
- **SC-3308** convert-to-order activation failure — the order-reprice path this ticket's Q2O + OrderRepriceInvocable depend on.
