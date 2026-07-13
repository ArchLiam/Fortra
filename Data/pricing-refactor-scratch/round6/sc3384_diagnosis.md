# SC-3384 — Multi-Currency Configured-Pricing: Diagnosis + Fix Plan

**Round 6 · Tab 3 · 2026-07-09 · read-only diagnosis** (workflow `w5qytw6ob`, 5-agent per-path + synthesis).
Test quote: `0Q0WC0000036xy90AA` (Q-Wren - Test Currencies, EUR).

## The one root cause
EUR/GBP **configured-pricing** lines (tier, attribute, server-discount, and the maintenance derived from them) are priced by
**currency-BLIND lookups over USD-ONLY configured data**, whose USD result is stamped into **`QuoteLineItem.Base_Price__c` —
a `Number(16,2)`, currency-blind (NOT a Currency field)**. Everything downstream (net, derived maintenance) inherits that USD
base. **Standard list pricing is unaffected** (per-currency PBEs exist and resolve). The defect lives entirely in the
CONFIGURED family. `Base_Price__c` being a plain Number (vs `NetUnitPrice`/`ListPrice`/`Pre_Partner_Price__c` = Currency) is
the structural conduit for the USD leak.

## Per-path
| Path | Gap | Root cause | Fix |
|---|---|---|---|
| **Tier / attribute-volume** (CLSAAS) | **code + data** | `AttributeVolumePricingPrehook` bulk SOQL + composite key **omit currency** → EUR line matches a USD tier row. Data: USD 1117 / EUR 37 / GBP 0. | CODE: thread the **item** currency (`STICurrencyIsoCode` tag) into the SOQL WHERE + `buildCompositeKey`. DATA: backfill non-USD tier rows. **(my domain — AttributeVolumePricingPrehook/AttributeVolumeCalculator)** |
| **Server-type discount / ABA** (Adv Auth Modes) | **code + config/data** | Absolute-value USD **Override** rows, resolved by a currency-blind decision-table lookup (no currency key). | **PREFERRED: remodel Override→PERCENTAGE** (currency-neutral, one row, also closes SC-3360). Fallback: seed EUR/GBP absolute Override rows. |
| **Derived maintenance** (BoKS) | **transitive** | maint net = `rate × contributor.Base_Price__c`. When the contributor is configured (USD-blind base), maint inherits USD. Priced by the **custom `PartnerNetPricePosthook` fallback** (0 currency refs in 87K chars), NOT the native PBEDP engine (which is USD-only + `IsDerived` not-updateable). | **No discrete fix** — fixed *transitively* once the contributor base is EUR-correct. Optional: a currency assertion guard in `ContributorPricingCalculator`. **A PBEDP/IsDerived backfill is the WRONG fix.** |
| **Auto-add maintenance PBE mismatch** | **none — already resolved** | Premise doesn't hold: EUR/GBP maint PBEs exist (6/currency) + the handler is currency-keyed. | No fix. Optional defense-in-depth: add `CurrencyIsoCode` filter to the flow `Get_Maint_PBE`. |

## ⚠️ My FX-removal must be RECONSIDERED for sequencing
The 4 FX steps were correct to remove for **standard** lines (0-delta — they never flowed through the multiply). **BUT
SC-3384 is entirely about CONFIGURED lines, and `CurrencyConversionNetUnitPrice` was the *only* currency adjustment those
lines had.** Removing it means configured EUR/GBP lines may now sit at **raw USD** (instead of the prior crude `USD×0.9346`)
in the interim before the real fix lands. This is "wrong → differently-wrong," not a regression of working pricing, but it
**must be reconciled**: ship the FX removal + the configured-base fix in the **same release**, or hold. **VERIFY FIRST** with
a UI reprice of a configured EUR line (my flow-reprice showed 0-delta but likely didn't recompute the configured lines).

## Prior work reconciliation
- **M5-PBEDP (SC-3372):** backfilled the *USD* PBEDP/IsDerived config — feeds the native engine, does nothing for non-USD, and doesn't touch the posthook that actually prices non-USD maintenance. Not the SC-3384 fix.
- **J-10:** established SC-3384 EUR-derived-$0 was the Portion-1 StampBaseFilter null-abort (fixed); flagged the FX-compound residual (now removed).
- **Wave-2 refactor:** decomposed `PartnerNetPricePosthook` into pure calculators — behavior-preserving, still currency-blind.

## Fix plan (DATA-first, per peer-review rule B6 — key-scoping without data drops EUR lines to no-match/reset)
0. **Do not ship a currency-key CODE change before its DATA is loaded + verified.**
1. **Reload org FX rates** + get **Marc DeBrey** sign-off on seed values.
2. **DATA:** seed `Attribute_Tier_Pricing_Storage__c` (GBP all products, EUR non-CLSAAS, re-seed CLSAAS EUR at authoritative rate); ABA data only if the percentage remodel is rejected.
3. **CODE (mine):** deploy `AttributeVolumePricingPrehook` + `AttributeVolumeCalculator` currency-key change + updated tests — after step 2 verifies.
4. **CONFIG:** prefer the ABA **percentage remodel** (skips the ABA data seed, closes SC-3360).
5. **Derived (BoKS):** no step — re-verify on the EUR quote after 2–4 land.
6. **Reconcile the V22 FX-step removal with the configured-base fix in the SAME release.**
7. **Auto-maint:** no action (optional flow currency filter).
8. **Regression-verify** the full EUR quote (all 5 line types) AND a **GBP** quote (GBP has ZERO attribute-tier + ZERO non-USD ABA data — the harder case).

## Open questions for the owner
- **ABA:** percentage remodel (cleaner, closes SC-3360) vs per-currency absolute Override seed?
- **FX contract:** after V22 removed `CurrencyConversionNetUnitPrice`, what applies FX to configured lines *today*? (If nothing → configured EUR/GBP at raw USD now.)
- **`Base_Price__c` type:** leave `Number(16,2)` + rely on per-currency data + one FX, or promote to a Currency/per-currency store?
- **GBP scope:** in SC-3384's shipping scope, or EUR-first? (GBP has zero non-USD configured data.)
- **Authoritative non-USD values:** static-rate catalog (`CEILING(USD×mult/5)×5`) as source of truth, or independently-authored EUR/GBP prices?
- **Owner gate:** is Marc DeBrey the sign-off for the tier + ABA seeds (per J-09)?
