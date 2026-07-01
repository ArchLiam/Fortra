# J-09 / SC-3372 — PBEDP contributor backfill: confirmation request for Marc DeBrey

**Context:** IsDerived maintenance PBEs with **0** `PriceBookEntryDerivedPrice` (contributor-config) rows price **silently null** under the live V21 pricing procedure. Fix = backfill one PBEDP row per uncovered derived PBE pointing at the correct contributing license. We have a live-validated, ready-to-insert set for the **active Fortra Price Book** (`01sWC0000022GHFYA2`). **We need your sign-off on the contributor mappings before we write** (UAT only). Nothing has been inserted.

Each row: `PricebookEntryId` (the derived maint PBE) + `ContributingProductId` (the license) + `Formula=UnitPrice`, `PricingSource=Product`, `DerivedPricingScope=Both`, `EffectiveFrom=2026-04-01`, `EffectiveTo=2099-12-31`, marker `Legacy_Rule_Id__c=M5-PBEDP-20260630` (reversible).

---

## 1. Tier A — 171 rows, unambiguous (please confirm / no objection)
Contributor name-stem = maintenance name minus `-New/RenewalMaintenance`, and that name resolves to **exactly one** active product with a real Fortra-Price-Book USD price. Highest confidence; no selection judgment involved.
→ file `j09_import_TIER_A_unambiguous_171.csv`.

## 2. Tier B — 82 rows / 41 license names, **needs your semantic call**
For these 41 license names, **two active products share the name**: an **NRPS (perpetual)** priced **$0** in the Fortra Price Book, and an **RSS (subscription)** with a real price. The maintenance line is a *perpetual* `-NewMaintenance`/`-RenewalMaintenance`, so the "natural" contributor is the perpetual — **but the perpetual is $0-priced**, which would re-create the null/$0 defect. We therefore mapped each to the **only priced candidate (the RSS/subscription product)**.

**Question:** is it correct for perpetual maintenance to derive its list price from the **subscription** SKU when the perpetual SKU is $0 in the Fortra Price Book? Or is the perpetual's $0 the real gap to fix (in which case these stay blocked until the perpetual is priced)?

→ full table with both candidates + prices in `marc_ambiguous_picks.csv`. Representative rows:

| license name | chosen (priced) | $ | alternative (perpetual) | $ |
|---|---|---|---|---|
| Alert Intelligence | SM-AI-RSS-ALERSU | 6000 | SM-AI-NRPS-ALERPE | 0 |
| Alignia Core | SM-VIT-RSS-ALCS | 8250 | SM-VIT-NRPS-ALCP | 0 |
| Vityl Capacity Management | CM-VCM-RSS-VCMS | 19800 | CM-VCM-NRPS-VCMP | 0 |
| VMC - Windows Operations Agent | SM-VMC-RSS-VWOS | 11780 | SM-VMC-NRPS-VWOP | 0 |
| DLP | DP-DLP-NRPS-DLPPER | 360 | DP-DLP-RSS-DLPSUB | 0 |
| Policy Manager for Network Devices | FIM-FIM-NRPS-PMNDP | 199 | FIM-FIM-RSS-PMNDS | 0 |

*(A few — DLP, Flow Exporters, Policy Manager family, QRemote, RPG Toolbox, Threat Aware — invert: the perpetual is the priced one and the subscription is $0. Same question, mirror image.)*

## 3. The J-09 evidence PBE — needs an explicit contributor pick
- PBE `01uWC000005wsZpYAI` = **EFT 8 Express-NewMaintenance** (`GS-GSE-RNM-EF8`), 0 PBEDP, prices null. **Not** in the 253 (name "EFT 8 Express" → 4 products).
- Active candidates: **`GS-GSE-RSS-EFES`** (subscription, on the evidence quote as the license line, List 958.8) vs `GS-GSE-NRPS-EFEP` (perpetual). **We recommend `GS-GSE-RSS-EFES`** — please confirm.

## 4. Excluded / NOT requested — 223 rows (FYI)
The staged 2026-06-14 CSV was ~47% mis-scoped: **223 rows point at the (forbidden) `Standard Price Book` or the inactive "Fortra Derived Pricing" book** and are excluded — they wouldn't price live quotes. → `live_blocked_for_marc.csv`. No action needed unless the intent was actually to configure a different book.

---

**After your confirmation** we insert (UAT only) via REST/Bulk with the reversible marker, then reprice a previously-null derived line to prove null→priced. Reversible any time by deleting the marker.
