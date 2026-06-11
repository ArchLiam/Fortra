# SC-3384 — Investigate Non-USD Quote Pricing Using USD Values for Configured Products

**Jira:** https://helpsystems.atlassian.net/browse/SC-3384
**Type:** Task
**Org:** FortraUAT (multi-currency enabled; 12 active currencies)
**Status:** Investigation (RCA in progress)
**Owner:** Liam Jeong — collaborate with **Nir** and **Marc** (per Jomil Bell, 2026-06-11)
**Created in repo:** 2026-06-11

---

## 1. Problem Statement

During **EUR** quote testing, several **configured products** have correct EUR price book entries,
but the **quote line pricing is calculated using USD values while displaying the EUR currency symbol**.

The list price renders correctly in EUR, but the *derived* amounts (Net Unit, Net Total, Subtotal, Total)
fall back to USD figures dressed in a EUR symbol. The defect is specific to **configured / rules-driven
pricing** (tier, server-type discount, attribute-based, attribute-tier), plus an **auto-add maintenance**
currency-mismatch hard error.

---

## 2. Test Quote

| Field | Value |
|---|---|
| Quote Name | **Q-Wren - Test Currencies-2026-06-09** |
| Quote Id | **0Q0WC0000036xy90AA** |
| Currency | EUR |
| URL | https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000036xy90AA/view |

---

## 3. Products / Configurations Tested

| Line | Pricing Mechanism | Product | SKU |
|---|---|---|---|
| 1 | **Tier-based pricing (attribute-based)** | BeSECURE - Premise-Based | `VM-BSL-RSL-BESEPB` |
| 2 | **Server Type Discount pricing** | Advanced Authentication Modes | `GS-GSE-NRPS-AAMP` |
| 3 | **Attribute-based pricing** | VM Analyst | `VM-VLM-NRSU-VMA` |
| 4 | **Attribute tier pricing storage** | Click and Launch Security Awareness Training - All Star | `HRM-HRM-RSL-CLSAAS` |
| 5 | **Auto-add maintenance** | Powertech Identity & Access Manager (BoKS) | `PIA-PIA-NRPS-PIAP` |
| 5b | (auto-added child) | Powertech Identity & Access Manager (BoKS)-NewMaintenance | `PIA-PIA-RNM-PIAMBK` |

---

## 4. Observed Issues (per line)

- **Line 1 (Tier-based / `VM-BSL-RSL-BESEPB`)** — Correct EUR **List Price**, but **Net Unit, Net Total,
  Subtotal, and Total** appear to use the **USD tiered price** with a EUR symbol.
- **Line 2 (Server Type Discount / `GS-GSE-NRPS-AAMP`)** — Correct EUR **List Price**, but **Subtotal**
  appears to use the **USD price**, and **Net Unit, Net Total, and Total** appear to be calculated as
  **50% of the USD price** rather than the EUR price.
- **Line 3 (Attribute-based / `VM-VLM-NRSU-VMA`)** — Correct EUR **List Price for the base product**, but
  the **attribute-based Net Unit, Net Total, Subtotal, and Total** appear to use **USD pricing for the
  configured attributes**.
- **Line 4 (Attribute tier pricing / `HRM-HRM-RSL-CLSAAS`)** — Correct EUR **List Price**, but **Subtotal**
  appears to use the **USD price** for the configured quantity of **50**. **Net Unit, Net Total, and Total
  show 0.**
- **Line 5 (Auto-add maintenance / `PIA-PIA-NRPS-PIAP` → `PIA-PIA-RNM-PIAMBK`)** — Auto-added maintenance
  product **fails to add** with:
  > `The price book entry currency code is different than the one assigned to the Quote.: Price Book Entry ID`

---

## 5. Reporter Hypotheses

1. **Attribute Tier Pricing Storage records appear to be USD-only**, and **`AttributeVolumePricingPrehook`**
   may not be including **currency** in the pricing-tier lookup.
2. Some issues may be **missing non-USD currency configuration** — missing EUR records for attribute pricing,
   tier pricing, or discount-pricing configuration (a **data** gap).
3. Other issues may require **deeper investigation into the pricing logic** to confirm whether currency is
   being included consistently when looking up configured pricing, discount pricing, and attribute-tier
   pricing records (a **config/code** gap).
4. The **auto-added maintenance** product appears to have the **correct price book entries** but still fails
   the currency-mismatch error → **investigate separately** from missing price-book setup.

> A Word document (`NonUSDCurrencyTesting.docx`) is in this folder; its 8 screenshots are extracted to
> `evidence/docx_screenshots/` (image1–8.png). Key additions captured in `01_REPRO_GROUND_TRUTH.md`:
> Line 1 is **attribute-based tier** pricing (PSM "Term Based - Annual"); Line 4 uses the
> **`Attribute_Tier_Pricing_Storage__c`** object — **confirmed live as 1,115 records, 100% USD, zero
> non-USD**; auto-add error verbatim is *"The price book entry currency code is different than the one
> assigned to the Quote.: Price Book Entry ID"* (`image8.png`). Quote # is **00780956**.

---

## 6. Acceptance Criteria

- [ ] Non-USD quote lines use **pricing records that match the quote currency**.
- [ ] EUR quote lines calculate **Net Unit, Net Total, Subtotal, and Total from EUR pricing, not USD pricing**.
- [ ] **Attribute-based**, **tier-based**, **server-type discount**, and **attribute-tier** pricing all
      **respect quote currency**.
- [ ] **Auto-added maintenance** products use a price book entry with the **same currency as the quote**.
- [ ] The quote can be **configured and saved without currency-mismatch errors**.

---

## 7. Working Notes — Likely Two Defect Families

This ticket bundles what is probably **two distinct root-cause families** (confirm during RCA):

- **(A) Configured-pricing currency-blindness** — tier / server-type-discount / attribute / attribute-tier
  pricing lookups (and the OmniStudio pricing **prehooks**, e.g. `AttributeVolumePricingPrehook`) do not
  filter the supporting pricing records by `CurrencyIsoCode`, so they grab the **USD** row even on a EUR
  quote. Could be **data** (missing EUR supporting rows → engine falls back to USD) and/or **config/code**
  (lookup key omits currency). The Line-4 "Net = 0" and Line-2 "50% of USD" symptoms suggest the lookups
  return *no matching EUR row* and then mis-handle the miss.
- **(B) Auto-add maintenance currency-mismatch** — the auto-add automation selects a PBE whose currency ≠
  quote currency even when a same-currency PBE exists → hard error on save. Reporter says PBEs look correct,
  so this is likely a **lookup that omits currency** when resolving the maintenance PBE. **Separate fix.**

### ✅ CONFIRMED ROOT CAUSE (deep RCA 2026-06-11 — see `02_ROOT_CAUSE_AND_FIX_SPEC.md`)

Unifying cause: **currency-blind lookups over USD-only supporting data.** The base PBE read filters by
currency (`Price_Book_Entry_Decision_Table_v2` has a `CurrencyIsoCode` Equals/Required key) → list prices
are right. Every *configured* pricing surface does not:

| Line | SKU | Engine | Lookup has currency key? | Supporting data | Defect type |
|---|---|---|---|---|---|
| 1 | VM-BSL-RSL-BESEPB | `AttributeBasedAdjustment` Override via `Attribute_Based_Adjustment_Decision_Table` (`0lDa50000007BEuEAM`) | **No** | 13,072 ABA rows **100% USD** | **DATA + CONFIG** |
| 2 | GS-GSE-NRPS-AAMP | same ABA decision table (AttributeDiscount BKM step, V9) | **No** (schedule hardcoded USD `84Xa…WQEAY`) | USD Override rows (3150/1575) | **DATA + CONFIG** |
| 3 | VM-VLM-NRSU-VMA | native ABA engine (carries `CurrencyIsoCode`) | n/a — engine is currency-aware | matched USD Override 500 | **DATA only** |
| 4 | HRM-HRM-RSL-CLSAAS | Apex `AttributeVolumePricingPrehook` | **No** (SOQL + composite key omit currency) | `Attribute_Tier_Pricing_Storage__c` 1,115 rows **100% USD** | **DATA + CODE** (+ separate Net=0 downstream) |
| 5 | PIA-PIA-RNM-PIAMBK | managed auto-add resolver (likely `ProductConfigurationRule`) | **No** | EUR PBE **exists** (`01uWC000005wzX8YAI`) | **CONFIG only** (wrong-PBE pick, not missing data) |

**Verdict on "only a data issue": No — BOTH, and interdependent.** Only **1 of 5** (VMA) is pure data;
PIAMBK is pure config; BESEPB/AAMP/CLSAAS need data **and** code/config. **Sequencing rule:** add the
currency filter and EUR data *together* — a currency filter without EUR rows regresses lines to list/0;
EUR rows without a currency key match USD+EUR non-deterministically (proven by AAMP's same-hash rows).

---

## Dossier files
- `HANDOFF.md` — **START HERE if picking this up** (Marc handoff: fix-by-defect, ID cheat-sheet, decisions needed, gotchas)
- `README.md` — this file (ticket + confirmed root cause + index)
- `01_REPRO_GROUND_TRUTH.md` — live repro evidence, PBE-per-currency, storage finding, screenshot index
- `02_ROOT_CAUSE_AND_FIX_SPEC.md` — **per-defect RCA + ordered fix spec + effort/load-share + open questions** (primary engineering deliverable)
- `03_CURRENCY_AUTHORITY_AND_RATES.md` — **authoritative currency list + ARR rate table + the 5/10/12 governance gap** (Ben's "was this agreed to?")
- `10_ORG_WIDE_REACH_IMPACT_ASSESSMENT.md` — broader multi-currency reach (rates@1.0, 129 reports, DocGen, Workday) for Jomil's "other configs / total effort" question
- `Currency+Conversion+for+Pricebooks.doc` — **authoritative source** (Confluence, "Fortra Review Complete 10.10.2025"; Marc confirmed 2026-06-11)
- `evidence/docx_screenshots/` — 8 screenshots from `NonUSDCurrencyTesting.docx`
- `NonUSDCurrencyTesting.docx` — repro source attachment

---

## 8. Investigation Plan

1. Pull the live quote `0Q0WC0000036xy90AA` + all `QuoteLineItem`s (currency, list/net/subtotal/total, product, PBE).
2. For each of the 5 SKUs, dump the supporting pricing records **per currency**: PricebookEntry, tier tables
   (`PriceAdjustmentTier`/volume tiers), attribute-based adjustments, server-type discount config, and the
   attribute-tier-pricing storage object — confirm whether EUR rows exist.
3. Read the OmniStudio pricing **prehooks** (`AttributeVolumePricingPrehook` + siblings) and the active
   pricing procedure steps; check whether each lookup includes `CurrencyIsoCode`.
4. Reproduce the auto-add maintenance currency-mismatch and trace which PBE the automation resolves.
5. Separate **DATA fixes** (seed missing EUR pricing rows) from **CONFIG/CODE fixes** (add currency to lookups),
   and size the effort. Coordinate with **Nir** and **Marc**.

---

## 9. Related Context

- Sits under the broader **Multi-Currency reach/impact** investigation Jomil requested (reach across configs
  + total effort incl. **Doc Gen**). See the org-wide impact assessment produced alongside this ticket.
- Related pricing-mechanism RCAs in this repo: `sc3360` (Advanced Authentication / `GS-GSE-NRPS-AAMP` — same
  SKU as Line 2!), `sc3359` (partner net price not applied), `sc3350` (COLA renewal pricing), `sc3372`
  (contributing products / derived PBE).
- **Multi-language is explicitly OUT OF SCOPE** for this ticket (Jomil, 2026-06-11) — currency only.
