# SC-3346 / SC-3372 — ZERO-LIST-PBE resolution & Product-Mgmt data request

**Date:** 2026-06-14 · **Org:** FortraUAT · **Active proc:** Rev_Mgmt_Default_Pricing_Procedure **V14** · Read-only analysis (5-agent workflow + adversarial verification).

## Verdict: NOT resolvable in-org — it's a DATA gap (Product Mgmt), not a procedure/code bug.

The V14 derived-pricing **procedure architecture is already correct** and needs **no change**. Execution order (verified against live V14 XML, `Data/sc3372/proc_v14/v14_block.xml`):
`ListContainer10 (seq4 zero-reset, gated ItemIsDerived__std) → DerivedProductsNativePull (seq5 NATIVE, gated only QuoteTypeText__c≠'Renewal') → ListContainer9 (seq6 MTD FORMULA = tier×Source_List_Price__c) → ListContainer (seq7 New-Business/Renewal formula)`, last-writer-wins. Exactly **one** `actionType=DerivedPricing` element exists (`DerivedProductsRenewals`).

So the residual gap is **data**, partitioned by which mechanism each product is meant to use.

## The gap (live SOQL, independently re-confirmed)

| Bucket | Count | Notes |
|---|---|---|
| Active derived maintenance PBEs | **3,453** | all IsDerived=true, IsActive=true, **UnitPrice=0** |
| Covered by native `PriceBookEntryDerivedPrice` | 199 | 191 FIM, 4 PIA, 2 RPA, 1 GS, 1 test |
| Formula-eligible (has `MTD` attribute `0tjWC000000096bYAA` = Maintenance_Type_Defn) | 192 | 143 GS + ~2/family token |
| Served by EITHER path (overlap 7) | 384 | |
| **NEITHER — true $0 / hard-error exposure** | **3,069 (88.9%)** | `Data/sc3346/gap/neither.csv` |

Dominant uncovered families: **SM 718, DM 447, FIM 330, DP 264, GOA 262, BI 216, ES 190, CS 180, CM 176, GS 121.**

## Why no in-org fix works (three paths, all blocked/rejected)

1. **Native backfill (PBEDP)** — *blocked on Product Mgmt, two ways:*
   - **No programmatic mapping.** All 201 PBEDP rows are hand-authored; the maint→contributor suffix is bespoke (0/201 exact-suffix match, 146/201 not even a single-char swap, 26/201 cross product-line FIM↔FML). A heuristic validated against the 201 known-good rows reproduces only **28%** (wrong for 87, none for 58, ambiguous for 103). `ProductRelatedComponent` is *not* the link. → 3,069 rows must be **manually authored** by someone with product-pairing knowledge.
   - **Missing contributor term prices.** Native derives from the contributor's **Term-Based** PricebookEntry. Of 101 already-curated contributors only **68 (67%)** have a non-zero term PBE; org-wide only **78 NRPS** (perpetual-license) products carry one. These prices don't exist in-org.

2. **Formula path (MTD × Source_List_Price__c — the SC-3346 design)** — *blocked on Product-Mgmt catalog data:*
   - Needs the **MTD attribute stamped** on the 3,069 products (a catalog decision: which products are formula-priced, at which tier).
   - `Source_List_Price__c` is hydrated by the `Stamp_Source_List_Price` v8 flow which **itself reads PBEDP** → without a source price, formula = tier × null = **$0**. (Corrects the initial "formula is PBEDP-independent" claim.)
   - Only **3 hard-coded tier rates** (Premier 0.30 / Standard 0.20 / Professional 0.20, else 0) — the separate **NB-DERIVED-TIER** defect; can't represent native ratios like FIM 0.2301. Needs the authoritative per-family tier table.

3. **Gate/remove the native element** — *rejected:* regresses the ~167 FIM/RPA/PIA config-covered no-MTD products (e.g. FIM net 462 = 0.2301×2008) from a **loud hard-error** to a **silent $0** — strictly worse.

## Current exposure shape
With the native element present, an uncovered line **hard-errors** ("We can't price when contributing products are missing") — it blocks the quote loudly rather than silently mispricing (repro `0Q0WC0000036wHJ0AY`); a $0 variant exists on `0Q0WC000003735t0AA`. So the priority is *correct pricing*, which needs the data below.

## Product-Mgmt data request (what unblocks the fix)
Keyed off `Data/sc3346/gap/neither.csv` (3,069 PBEs) + `Data/sc-maint/*.csv`:
- **Per-family mechanism decision** (native-config vs formula) for each of the ~9 uncovered families (SM/DM/DP/GOA/BI/ES/CS/CM/GS…).
- **Native families:** maintenance→contributor product pairings + non-zero **Term-Based** contributor PricebookEntries.
- **Formula families:** which products get the **MTD** attribute, the **Source_List_Price** source, and the **maintenance tier-rate table** (fixes NB-DERIVED-TIER too).

## Recommended execution (when data arrives)
- Execute as a **data/config backfill in family waves** (PBEDP rows / contributor term PBEs / MTD PAD links / SLP / tier table) — **NOT** a procedure rewrite (avoids the ExpressionSetVersion delete-block + context-resync gack).
- Validate each wave on repro `0Q0WC000003735t0AA` + a known-good control per mechanism (FIM-FIM-RNM-CCMLSE native→462; a GS MTD line→tier×SLP); confirm last-writer-wins doesn't regress the control. Re-verify MTD/PAD flags after any Gearset/refresh (durability gap).
- Re-confirm the live active proc version first; fresh deploy/DML authorization required.

## Executable now (no Product-Mgmt data needed)
- This data-request handoff (done — this doc + CSVs).
- Keep loud failure (native present) — do **not** broaden the formula or stamp MTD onto config families without SLP+tier data (would silently override working native 462 with $0).
- Optionally fix **NB-DERIVED-TIER** (replace the 3-tier inline IF-chain with a CMDT lookup) — but the authoritative rate table is still a Product-Mgmt input.

**Artifacts:** `Data/sc3346/gap/{neither,all_derived,mtd_pbes,pbedp_pbes}.csv`, `Data/sc-maint/{pbedp_all_201,derived_pbe_all,contrib_all_pbe,term_nonzero_raw}.csv`, `Data/sc3372/proc_v14/`.
