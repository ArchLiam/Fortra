# SC-3384 — Currency Authority, Rates & Governance

**Authoritative source (confirmed by Marc DeBrey, 2026-06-11):** Confluence *"Currency Conversion for
Pricebooks"* — https://helpsystems.atlassian.net/wiki/spaces/BS/pages/1924923573/Currency+Conversion+for+Pricebooks
(local copy: `Currency+Conversion+for+Pricebooks.doc` in this folder; **"Fortra Review Complete 10.10.2025"**).
Also documented in `FORTRA_KNOWLEDGE_BASE.md` §5.1.
Upstream design: Marc's SharePoint *"Fortra Revised Multi-Currency Approach Summary.docx"* + Salesforce
`AutoFX_User_Guide_v1_3.pdf`.

---

## 1. Design intent (why the SC-3384 defect is structural)

The approved approach is **Single Currency Per Transaction with native Salesforce Multi-Currency**,
USD = corporate currency. The load-bearing rule for this ticket:

> Per-currency prices are **applied at the product/pricebook level, NOT during quoting.** Master price is
> defined in USD; **per-currency PricebookEntries are pre-generated as static stored values** via Fortra's
> conversion formulas (the "Create New Products" flow, or manually). At quote time the EUR PBE is read
> **directly — no conversion happens.** Currency is **locked after quote creation** (to change it, make a
> new Opportunity + Quote). Values flow Quote → Order → Asset → Invoice unchanged; profitability uses
> `CURRENCYRATE()` to normalize to USD.

**Implication for SC-3384:** the design assumes *every* pricing input is pre-built per currency as a static
value. The base PricebookEntry follows this (list prices are correct EUR). But the **configured-pricing
supporting data** — `AttributeBasedAdjustment` (13,072 rows) and `Attribute_Tier_Pricing_Storage__c`
(1,115 rows) — was **only built in USD**, and the lookups consuming it are **currency-blind** (see
`02_ROOT_CAUSE_AND_FIX_SPEC.md`). So the defect is the design intent applied to *list prices only* and never
extended to the configured-pricing layer.

---

## 2. Authoritative rate table vs live org

The doc says: **"Using the rates below, not current Exchange rates. Round up to the nearest $5."** Finance
does an annual review (optionally quarterly). Rates live in a **Custom Metadata Type**.

| Currency | Doc — Dec 2024 ARR Rate (authoritative) | Live `CurrencyType` (2026-06-11) | Status |
|---|---|---|---|
| USD — US Dollar | 1 | 1 | ✓ |
| EUR — Euro | 0.9346 | 0.92 | ~ok (slightly off) |
| GBP — British Pound | 0.7874 | **1.0** | ❌ reset to 1.0 |
| AUD — Australian Dollar | 1.5385 | 1.52 | ~ok |
| CAD — Canadian Dollar | 1.3889 | 1.35 | ~ok |
| ARS — Argentine Peso | 666.6667 | **1.0** | ❌ reset to 1.0 |
| CHF — Swiss Franc | 0.8850 | **1.0** | ❌ reset to 1.0 |
| ILS — Israeli New Shekel | 3.6251 | **1.0** | ❌ reset to 1.0 |
| JPY — Japanese Yen | 149.2537 | **1.0** | ❌ reset to 1.0 |
| NZD — New Zealand Dollar | 1.6667 | **1.0** | ❌ reset to 1.0 |
| **MXN — Mexican Peso** | **not in doc** | 0.056 | ⚠️ ungoverned / misconfigured |
| **SEK — Swedish Krona** | **not in doc** | 1.0 | ⚠️ ungoverned |

**Takeaway:** the rate-reload fix needs **no new finance input** — the correct values are already documented
here. 6 of the doc's currencies (GBP/ARS/CHF/ILS/JPY/NZD) are sitting at a placeholder 1.0 in the live org
(the broad assessment found GBP/JPY/ARS/SEK were reset on 2026-02-11/12/13).

---

## 3. The 5 vs 10 vs 12 governance gap (from the 2026-06-11 thread)

Ben Kozlowski flagged the currency count as "a change and a risk… Was this a change agreed to?" Marc DeBrey
agreed the extras "were simply added to the Confluence doc" with no recalled discussion (suggested checking
Notebook LM). Pinning it down:

| Tier | Count | Currencies | Governance |
|---|---|---|---|
| **Stated requirement** (Ben) | 5 | USD, EUR, GBP, AUD, CAD | Agreed |
| **Confluence doc ARR table** | 10 | + ARS, CHF, ILS, JPY, NZD | In the reviewed doc (10.10.2025), but no recalled change discussion |
| **Active in the org** | 12 | + **MXN, SEK** | **Not in the doc at all** — orphan |

- The **5 → 10** expansion (ARS, CHF, ILS, JPY, NZD) is at least *documented* (the doc was "Fortra Review
  Complete 10.10.2025"), and these line up with real Legal Entities / transactions (esp. **JPY**: 2,019
  quotes; Fortra Japan KK + several JPY legal entities).
- The **10 → 12** additions (**MXN, SEK**) appear **nowhere** in the authoritative doc, have **no ARR rate**,
  **no PricebookEntry coverage**, and **~zero transactions** → strongest candidates to **deactivate** unless
  someone owns a requirement for them.

**Recommendation:** ask leadership to ratify the supported list. Most defensible scope = **the doc's 10**
(or **core 5 + JPY** as the MVP, since JPY is the only non-core currency with real volume). MXN/SEK should be
deactivated or formally justified. This directly answers Ben's "was this agreed to?" — the +5 was in the
doc; the +2 (MXN/SEK) was not.

---

## 4. Scope impact on SC-3384 effort

"How many currencies must work" is the top effort lever for the data seed (Workstream A):

- **Core 5 + JPY** (MVP): manageable solo, ~1 week for the reported products.
- **Doc's 10:** larger per-currency data seed across the catalog (ABA + ATPS rows for each).
- **All 12:** includes building MXN/SEK from scratch with no governed rates — *new capability*, not
  remediation; should not be in scope without a decision.
