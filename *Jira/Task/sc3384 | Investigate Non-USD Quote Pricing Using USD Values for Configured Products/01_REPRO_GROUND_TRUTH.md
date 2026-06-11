# SC-3384 — Repro Ground Truth (live FortraUAT, 2026-06-11)

Confirmed against the live test quote. **Every configured-pricing line renders the correct EUR list
price but computes its derived amounts off the USD PricebookEntry value.**

## Quote header
- `0Q0WC0000036xy90AA` — **Q-Wren - Test Currencies-2026-06-09**, **CurrencyIsoCode = EUR**, Status Draft
- Pricebook2Id `01sWC0000022GHFYA2`, LineItemCount **4** (the 5th — auto-add maintenance — failed to add)

## The 4 saved quote lines (key fields)

| SKU | Mechanism | Qty | EUR ListPrice | UnitPrice | NetUnitPrice | NetTotalPrice | Subtotal | TotalPrice | Base_Price__c | Price_Mode__c |
|---|---|---|---|---|---|---|---|---|---|---|
| VM-BSL-RSL-BESEPB | Tier | 1 | 758.08 | 824 | 824 | 824 | 824 | 824 | – | – |
| GS-GSE-NRPS-AAMP | Server-type discount | 1 | 2898 | **3150** | 1575 | 1575 | **3150** | 1575 | – | – |
| VM-VLM-NRSU-VMA | Attribute-based | 1 | 460 | 460 | **500** | 500 | 500 | 500 | – | – |
| HRM-HRM-RSL-CLSAAS | Attribute-tier storage | 1 | 2005.6 | 1357.2 | **0** | **0** | 1357.2 | **0** | 1357.2 | Total Price |

## PricebookEntry per currency (the values being mis-pulled)

| SKU | EUR (Fortra PB) | EUR (Standard PB) | USD | Line's derived amount | Matches |
|---|---|---|---|---|---|
| VM-BSL-RSL-BESEPB | 758.08 | 0 | **824** | net 824 | **= USD** |
| GS-GSE-NRPS-AAMP | 2898 | 0 | **3150** | UnitPrice/Subtotal 3150; net 1575 (=50% of USD) | **= USD** |
| VM-VLM-NRSU-VMA | 460 | 0 | **500** | net 500 | **= USD** |
| HRM-HRM-RSL-CLSAAS | 2005.6 | 2005.6 | 2180 | net 0 (Subtotal 1357.2 = USD attr-tier stored value) | EUR lookup **misses → 0** |
| PIA-PIA-NRPS-PIAP | 326.6 | 0 | 355 (×2 dup) | — | — |
| PIA-PIA-RNM-PIAMBK (auto-add maint) | **0 (exists)** | 0 | 0 | fails to add | currency-mismatch error despite EUR PBE existing |

## Reads

1. **List price (PricebookEntry direct read) is correct in EUR** for all lines → the base PBE lookup *does*
   filter by currency. The defect is downstream in the **configured/derived** pricing steps.
2. **Tier, server-type-discount, attribute, and attribute-tier lookups return the USD value** — either
   because the supporting pricing records exist only in USD (**DATA**) and/or because the lookup query
   omits `CurrencyIsoCode` and grabs the USD row (**CONFIG/CODE**). Line 4's collapse to **0** (rather than
   a USD number) shows that at least one mechanism *misses entirely* on EUR rather than falling back to USD —
   evidence the lookup key differs per mechanism.
3. **Auto-add maintenance (PIAMBK)**: EUR PBE exists (price 0) yet the auto-add resolves a USD PBE →
   `The price book entry currency code is different than the one assigned to the Quote`. This is a
   **separate** lookup-omits-currency defect (Family B), not a missing-PBE problem.

## Pricing prehooks present in org (candidate currency-blind lookups)
`AttributeVolumePricingPrehook` (named in ticket), `HardwareAttributePricingPrehook`,
`PartnerPricingPrehook` / `PartnerPricingPrehookV2`, `RegionalServicesPricingPrehook`, `COLAUpliftPrehook`,
`SourceListPricePrehook`, `QLDescriptionGeneratorPrehook`. Source mirror: `Org Data/_src/classes/`.
Active pricing procedure: `Rev_Mgmt_Default_Pricing_Procedure`.

## Defect families (hypothesis to confirm in RCA)
- **(A) Configured-pricing currency-blindness** — Lines 1–4. Supporting pricing rows USD-only and/or lookup
  key omits currency.
- **(B) Auto-add maintenance currency-mismatch** — Line 5. PBE resolution omits currency.

---

## Additions from attached `NonUSDCurrencyTesting.docx` (2026-06-11)

Word doc + 8 screenshots imported to `evidence/docx_screenshots/` (image1–8.png). Reporter wording + UI evidence:

- **Quote Number 00780956** (human-readable; Id `0Q0WC0000036xy90AA`), Quote Type "New", Currency EUR.
  Screenshot `image7.png` shows the **Total Discount Amount = EUR 1,575.00 (USD 1,711.96)** — i.e. the
  header even surfaces a dual-currency value, and EUR 1,575 is exactly the AAMP "50%-of-USD" net.
- **Line 1 mechanism is "Tier based pricing (attribute based)"** — PSM "Term Based - Annual", Quantity UOM
  "1 Tier Based". So Line 1 is **attribute-based tier** pricing, not a volume tier. Ties it to the same
  attribute/tier machinery as Line 4 (and `AttributeVolumePricingPrehook`).
- **Line 4 = "Tiered pricing (Attribute_Tier_Pricing_Storage based)"**, and the reporter states verbatim:
  *"The Attribute Tier Pricing Storage records are all set to USD, but the AttributeVolumePricingPrehook does
  not appear to be including currency in the pricing tier lookup."* Configured quantity referenced as **50**
  (this is the attribute/tier quantity, not the line `Quantity`, which is 1 on the saved QLI).
- **Auto-add error (verbatim, `image8.png`):** toast *"Your quote was not updated. The price book entry
  currency code is different than the one assigned to the Quote.: Price Book Entry ID"*.

### ✅ NEW HARD FINDING — `Attribute_Tier_Pricing_Storage__c` is USD-only
Live query (FortraUAT): the object exists (`Attribute_Tier_Pricing_Storage__c`, label "Attribute Tier
Pricing Storage") and is **currency-enabled** (has `CurrencyIsoCode`), but holds **1,115 records, 100% USD —
ZERO EUR or any other currency**.

This directly confirms the reporter's Line-4 hypothesis. **Corrected interpretation (per deep RCA, see
`02_ROOT_CAUSE_AND_FIX_SPEC.md` §2.4):**
- `AttributeVolumePricingPrehook` SOQL (`cls:212-219`) filters on `Product__c`/`Product_Selling_Model__c`
  only — **no `CurrencyIsoCode`** — so on an EUR line it **HITS a USD row** and writes
  `Base_Price__c = Subtotal = 1357.2` (the USD `Tier_Value__c`). It does **not** "miss" — the earlier
  "EUR lookup misses → 0" framing was backwards.
- The **Net/Total = 0** is a **separate, currency-independent** downstream issue in how the pricing
  procedure consumes `'Total Price'` mode (treat as its own sub-fix; verify it persists after EUR data lands).
- **Remediation is BOTH:** (DATA) seed non-USD `Attribute_Tier_Pricing_Storage__c` rows, **and** (CODE) add
  `CurrencyIsoCode` to the prehook SOQL **and** thread currency into the composite key
  (`buildCompositeKey`/`buildTierLookupMap`/`lookupTierFromMap`).

### Screenshot index (`evidence/docx_screenshots/`)
- `image7.png` — Quote Lines tab (3 lines shown: BESEPB / AAMP / VM Analyst) with the mis-priced EUR amounts highlighted.
- `image8.png` — the auto-add maintenance currency-mismatch error toast.
- `image1–6.png` — EUR price book entry screenshots + per-line pricing behavior (supporting evidence).
