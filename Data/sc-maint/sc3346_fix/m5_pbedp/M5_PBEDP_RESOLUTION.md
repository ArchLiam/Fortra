# M5-PBEDP / SC-3372 — Root Cause + Resolution

**Status:** Root cause confirmed; crosswalk built + validated; executable 476-row backfill staged. Full closure is business-crosswalk + Marc-coordination + DML-auth gated.
**Org:** FortraUAT · Date: 2026-06-14 · Active procedure V14.

## Root cause (confirmed)
The "Maintenance Derived Pricing" rollout flagged **3,453** maintenance PBEs as `IsDerived=true` and added the native `DerivedProductsRenewals` element (actionType=DerivedPricing; was `DerivedPricingDataRetrieval`) to the live procedure — but backfilled the required `PriceBookEntryDerivedPrice` contributor-config for only **199**. When a derived line with **no** PBEDP config is priced, the native element **hard-errors** ("We can't price when contributing products are missing") and aborts the line → `NetUnitPrice` NULL. **3,254 (94.2%) uncovered = live exposure** (RRM subset 1,603). Per the SC-3372 deep RCA, the fix is **backfill PBEDP** (not removing the native element — 167 config-covered FIM/PIA/RPA products price *only* via the native path; removal would zero them).

## Contributor crosswalk (built + validated)
Mapping rule: maintenance product name = `<license name> + "-NewMaintenance"/"-RenewalMaintenance"` → contributor = the license product of that name. **Validated against the 199 real PBEDP mappings: 183/200 agree (91.5%).** The 17 disagreements are business-specific (contributor carries extra qualifiers — `(Technical)`, `- EVAL`, `- FIM Only` — or is a different product, e.g. `Tripwire State Analyzer Express` → `VnE Manager Ev & Device Profiler Ev`). So name-match is a strong heuristic, **not authoritative**.

### Categorization of the 3,254 uncovered (after pricebook/currency disambiguation, excluding maintenance-product candidates)
| Bucket | Count | Meaning | Action |
|---|---|---|---|
| **Clean (name-matched, priced contributor)** | **510** | single priced contributor of the exact base name | backfill-able |
| — of which **HIGH-confidence** (NRPS/RSS license SKU) | **476** | 256 New-Maint + 220 Renewal-Maint | **executable now** (data-only REST) |
| — lower-confidence (contributor not NRPS/RSS) | 34 | other contributor SKU types | review |
| **Ambiguous** | 1,693 | base name → multiple priced products, no single resolution | **business crosswalk** |
| **Zero-list contributor** | 870 | license exists but no priced PBE | **business + license list-price fix** |
| **Missing contributor** | 181 | no product matches the base name | **business crosswalk** |

So even the best automated crosswalk cleanly resolves **510 / 3,254 (~16%)**; the other ~84% are genuinely the owner/business crosswalk the dossier flagged.

## PBEDP record model (replicate)
`PricebookEntryId` (the uncovered derived PBE) + `ContributingProductId` (the license) + `Formula=UnitPrice` + `PricingSource=Product` + `DerivedPricingScope=Both` + `EffectiveFrom=2026-04-01` + `EffectiveTo=2099-12-31`. (`ProductId`/`ProductSellingModelId` are **read-only** — auto-derived from the PBE; do NOT set them. Use a distinct `Legacy_Rule_Id__c` marker so the backfill is reversible.) **Note:** existing BoKS PBEDP rows have `EffectiveTo=null` vs FIM's `2099-12-31` — set the end date on new rows.

## What a PBEDP backfill fixes (and what it doesn't)
- ✅ Stops the native **hard-error** so the derived line can price at all (the SC-3372 symptom).
- ✅ Lets `Stamp Source List Price` resolve the contributor → populate `Source_List_Price__c` so the formula path computes (new-business: `tier × Source_List_Price`).
- ❌ Does **not** fix the renewal **commit** value on QuoteAction-less lines (that's SC-3404 — parked). And minority-tier new-business lines still price $0 until NB-DERIVED-TIER (the 7-tier formula) lands.

## Resolution path
1. **Decisive proof** (gated on DML auth): backfill ONE high-confidence New-Maintenance PBEDP whose line currently hard-errors/$0, reprice a Draft quote, confirm the error clears + it prices `tier × Source_List_Price`.
2. **Backfill the 476 high-confidence rows** (`backfill_HICONF.csv`) — data-only REST, no procedure republish, reversible (marker). Per SC-3372 standing rule: confirm with Marc + fresh DML auth before the write.
3. **Hand the 2,744 business-gated** (ambiguous/zero-list/missing) to product/Marc for the contributor crosswalk + license list-price fixes.

## Artifacts (`Data/sc-maint/sc3346_fix/m5_pbedp/`)
`derived_pbes.csv` (3,453), `covered_pbes.csv` (201), `backfill_HICONF.csv` (476 executable), `backfill_clean2.json` (510), `flagged.txt` (business-gated), `existing_map.csv` (the 199 validated mappings).
