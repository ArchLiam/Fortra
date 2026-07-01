# J-06 — Partner derived-maintenance band fix — RESULT (FortraUAT, UAT-only)

**Status:** ✅ FIXED & VERIFIED on live FortraUAT V21 — 2026-06-30
**Ticket:** SC-3346 / SC-3359 · P0
**Artifact:** ApexClass `PartnerNetPricePosthook` (deploy `0AfWC00000GcleD0AR`, success)
**Diff:** `J06_PartnerNetPricePosthook.diff` (this folder)

## Before → After (evidence quote `0Q0WC000003FdCD0A0` / Q-J06-58422)

| Line | Product | Before | After | Expected |
|---|---|---|---|---|
| Maint | PIA-PIA-RNM-PIAMBK (New Maintenance) | NetUnitPrice **60.35** (=71×0.85, 15% Software band) | **62.48** (=71×0.88, 12% New-Maint band) | 62.48 ✅ |
| License | PIA-PIA-NRPS-PIAP (Perpetual) | 301.75 | 301.75 (unchanged) | 301.75 ✅ |

Partner: Billing_Partner__c = `001WC00000ZtazZYAR`, Quote.Partner_Pricing_Model__c = `Discount`.
Winning model = **PPM-00028** (`aGlWC000000Aa3p0AC`, Discount, active, effective 2025-01-06…2028-01-06), New_Maintenance_Percent__c = **12**, Software_Percent__c = 15.

Regression control (non-partner BoKS quote `0Q0WC000003FKRJ0A4`): maint PIA-PIA-RNM-PIAMBK still **71**, license **355** — unchanged. ✅

## Root cause (differs from the original artifact pin)

The pin pointed at `loadNewMaintenanceLines` / `resolveContributorPartnerPercent` carrying the contributor's license band. That is one input, but the **operative** source was `computeNewBusinessMaintenanceNets` (~line 2009), which set `nets.partnerPercent` from the **prehook-stamped line-item tag** `PartnerDiscountPercent` (=15, the Software band the prehook writes onto the derived-maint line) **first**, and only fell back to `maintInputs.partnerPercent` when the stamp was null/0. So correcting `maintInputs.partnerPercent` alone was inert (proven: two deploys setting it to 12 left the net at 60.35).

The context-tag approach (`quoteData.partnerPricingModel` / `billingPartnerId` from the SalesTransaction header) also did not resolve — partner fields are carried at the QLI node, not the header (consistent with the prior V16 context-fetch incident). The fix therefore resolves the band by **direct SOQL on the line's Quote/Order**, independent of context plumbing.

## Fix implemented (3 parts, all in `PartnerNetPricePosthook`)

1. **`resolveNewMaintenancePartnerBandByQuote` / `…ByOrder` (new):** for each maint line's Quote/Order, read `Billing_Partner__c` + `Partner_Pricing_Model__c`; when the model is `Discount`, resolve the active model via `PartnerPricingService.getPricingModels` and take `getMarginForProductType(model,'New Maintenance')`. Returns a band-by-transaction map.
2. **`loadNewMaintenanceLines` (QLI + OrderItem blocks):** use the resolved band as `partnerPercent` (falling back to today's contributor/stamped value if none), and set a new `NewMaintInputs.partnerBandResolved` flag = true only when a Discount band actually resolved.
3. **`computeNewBusinessMaintenanceNets`:** when `partnerBandResolved` is true, prefer `maintInputs.partnerPercent` (the authoritative New-Maint band) over the stamped license band; **otherwise byte-identical to prior behavior** (Guaranteed-Margin, non-partner, and manual-override paths unchanged → zero regression).

## Known residual (hand-off to Portion 1 / E-04)

The maint line's `PartnerDiscountPercent` **field** still displays **15** (the prehook's stamp); the pricing math correctly used 12 (net = 62.48). The displayed field will align once Portion 1's partner **prehook** re-point lands. Not a J-06 net-price defect.

## Definition of done

- [x] Derived-maintenance partner line nets the New-Maintenance band (62.48 = 71×0.88), not 60.35.
- [x] License line still 301.75.
- [x] Same-area non-partner control (BoKS) still 71 — no regression.
- [ ] (supplementary) PartnerNetPricePosthookTest run — see test log.
- UAT only — NOT deployed to production.
