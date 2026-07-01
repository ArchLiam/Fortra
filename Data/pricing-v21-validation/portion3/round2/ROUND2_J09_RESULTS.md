# V21 Fix — ROUND 2, Portion 2 (PBEDP DATA) · J-09 — Results

**Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`) · **Date:** 2026-06-30 · Active proc **V21** (ESDV `9QBWC0000000oWH4AY`, ctx v23).
**Status:** LIVE re-validation complete. **No DML performed.** J-09 payload re-confirmed & sharpened; **held** at the SC-3372 gate (Marc DeBrey mapping confirmation + fresh DML auth).

---

## What round-2 did (all read-only)
Re-measured every one of the **476** HICONF PBEs against the *current* live org (round-1 preflight was ~12:00–17:46; this is the after-22:01Z re-check per hard-rule #1), then re-derived the actionable subset, validated contributor pricing, scored mapping confidence, and diffed vs the round-1 staged 253.

## Result: zero drift, and a sharper split

| bucket | rows | disposition |
|---|---|---|
| **Actionable** (active Fortra Price Book `01sWC0000022GHFYA2` + IsDerived + active PBE + 0 PBEDP + priced-USD contributor) | **253** | ✅ would flip null→priced |
| Wrong pricebook (Standard `Standard Price Book` / inactive "Fortra Derived Pricing") | **223** | ❌ excluded — do NOT insert (hard-rule #forbids; doesn't price live quotes) |
| now-covered / PBE-inactive / not-derived / contributor-unpriced / missing | **0** | — |

**Drift vs round-1's staged 253: NONE.** stable 253 · newly-blocked 0 · newly-actionable 0. The org has not moved; the round-1 `j09_import_253.csv` payload is still exactly correct.

### Contributor-mapping confidence (the crux risk)
- **Name-stem match: 253/253 EXACT** (`maint_name` minus `-New/RenewalMaintenance` == `contrib_name`). The heuristic's known ~8.5% miss rate lived in the *ambiguous* cases, which are already excluded from the 253.
- **No contributor is itself a maintenance/renewal SKU** (0 bad-kind).
- **All 137 contributors carry an active priced USD FPB PBE** ($5.73 – $52,500; none ≤ $0).

### Two tiers within the 253
| tier | rows | names | what it is | confidence |
|---|---|---|---|---|
| **A — unambiguous** | **171** | 96 | contributor name resolves to exactly ONE active product | highest |
| **B — name-collision, forced pick** | **82** | 41 | contributor name matches 2 active products — a **$0-priced NRPS (perpetual)** + a **priced RSS (subscription)**; mapping took the **only priced candidate** | operationally forced; **business-semantics needs Marc** |

Tier B is *not* a data-selection risk: the alternative candidate is $0 (would re-create the defect), so the priced pick is the only viable one. The open question is purely business-semantic — **should perpetual `-NewMaintenance` derive from the subscription (RSS) list price when the perpetual (NRPS) license is $0-priced in the Fortra Price Book?** That is a zero-list-contributor question ([[project_sc3372_contributing_products_error]] "870 zero-list-contributor") and belongs to Marc.

## The named DoD evidence record is NOT fixable by this backfill
- **QLI `0QLWC000003KEbO4AW`** (Quote `0Q0WC0000029Agw0AE`) = **EFT 8 Express-NewMaintenance**, PBE `01uWC000005wsZpYAI` — live now: IsDerived=true, active, USD, **0 PBEDP**, Net=null/List=0/SLP=null. **STILL FAILING.**
- This PBE is **not in the 476 HICONF payload at all** — it's an ambiguous-contributor case ("EFT 8 Express" → 4 products; active: `GS-GSE-NRPS-EFEP` perpetual + `GS-GSE-RSS-EFES` subscription). Round-1 recommends **RSS `GS-GSE-RSS-EFES`** (the license line on the evidence quote), **pending Marc**.
- ⇒ Inserting the 253 will **not** flip the spec's named evidence line. Use the in-set proof target instead (below).

## Recommended in-set decisive proof (single reversible row, once authorized)
- Insert **1** PBEDP: PBE **`01uWC000005wsZGYAY`** (Advanced Authentication Modes-NewMaintenance, Tier A) ← contributor **`01tWC00000DD11YYAT`**, marker `M5-PBEDP-20260630`.
- Force-reprice DRAFT QLI **`0QLWC000003DAHl4AO`** (Quote `0Q0WC00000297R80AI`) — live now Net=null/List=0/SLP=null → expect SLP + NetUnitPrice to resolve.
- Regression control (covered, untouched): BoKS USD PBE `01uWC000005wsbVYAQ`.
- Reversible: delete `Legacy_Rule_Id__c='M5-PBEDP-20260630'`.

## Blast radius
**47,039 QLIs** currently sit on the 253 PBEs (20,385 Approved · 9,237 Draft · 16,982 no-status · 434 In Review). New PBEDP rows change pricing on next reprice — this is why the bulk write is gated on Marc's confirmation, not a casual insert.

## GATE (held)
SC-3372 standing rule + [[feedback_uat_deploy_authorization]]: **fresh explicit DML auth + Marc DeBrey contributor-mapping confirmation** required before any write. Nothing inserted. UAT only; nothing to prod.

## Artifacts (`Data/pricing-v21-validation/portion3/round2/`)
- `revalidate.py` / `revalidate.json` — reproducible live re-measurement of all 476
- `live_actionable.csv` (253) · `live_blocked_for_marc.csv` (223)
- `j09_import_TIER_A_unambiguous_171.csv` · `j09_import_TIER_B_needs_marc_82.csv` — insert-ready split
- `marc_ambiguous_picks.csv` — the 41 name-collisions with both candidates + FPB-USD prices
- (round-1) `../j09_import_253.csv` — full 253-row payload, marker `M5-PBEDP-20260630`

---

# STAGE 1 PROOF EXECUTED — 2026-06-30 (owner-authorized live DML)

**Inserted 1 reversible PBEDP row** (marker `M5-PBEDP-20260630`, id `182WC000000I1NRYA0`): PBE `01uWC000005wsZGYAY` (Advanced Authentication Modes-NewMaintenance) ← contributor `01tWC00000DD11YYAT`, Formula=UnitPrice, USD. Verified on OPEN-opp Draft line QLI `0QLWC000003DAub4AG` (Quote `0Q0WC0000028bsk0AA`, opp "Evaluating").

| field | BEFORE | AFTER Force-reprice |
|---|---|---|
| `Source_List_Price__c` | **null** | **3150** ✅ (= contributor's FPB-USD list) |
| `NetUnitPrice` | null | null ⚠️ |
| `ListPrice` | 0 | 0 |

**✅ PBEDP fix PROVEN.** The native DerivedProducts pull now resolves the contributor and stamps `Source_List_Price__c` (null→3150). The J-09 silent-null-from-missing-contributor defect is eliminated. Causally attributable: the only change between BEFORE/AFTER was the single PBEDP row; reprice returned `isSuccess:true`, no "contributing products are missing" error.

**⚠️ NetUnitPrice residual = the MTD-tier value (Portion 3, NOT this portion).** `Net = tier% × Source_List_Price__c`. The proof line carries **0 `QuoteLineItemAttribute` rows** → no Maintenance_Type_Defn (MTD) value → the tier IF-chain has no branch → Net stays null. This is the documented round-1 result (PBEDP is necessary + stamps SLP; MTD tier is a separate input). Confirmed org-wide:
- The MTD product-attribute IS defined on the proof product (and 58/171 Tier-A products).
- `QuoteLineItemAttribute`: 740,611 rows; 102,199 carry the MTD def; **all MTD selections live in `AttributePicklistValueId`** (`AttributeValue` is null on every row).
- The intersection **(uncovered-253 PBE) ∩ (line has an MTD value) ∩ (repriceable Draft/open/USD)** is empty in the scannable population → a full Net→non-zero flip cannot be shown by a PBEDP insert alone; it requires **Portion 3 (MTD DATA)** to stamp MTD values on these lines. QLIA is a big-object-like entity (subqueries cap at 1,000), so it can't be semi-joined.

**Net:** Portion 2 (PBEDP) is verified DONE for the proof case (SLP flip). Full maintenance-price resolution (`Net` non-zero) requires Portion 2 **and** Portion 3 (MTD) together — the round-2 cross-portion dependency. The proof row remains in place (reversible via the marker) pending the decision to proceed to Tier A / roll back.

---

# STAGE 2 — TIER A (171) APPLIED — 2026-06-30 (owner-authorized live DML)

**Inserted 170 PBEDP rows** (bulk job `750WC00000RZ3Q5YAL`, 170/170 success, 0 fail) + the pre-existing Stage-1 proof row = **171 total** under marker `M5-PBEDP-20260630`. File: `j09_import_TIER_A_minus_proof_170.csv` (proof PBE excluded to avoid a duplicate).

**Coverage verified:** all **171 Tier-A PBEs covered exactly once** — 0 duplicates, 0 missing.

**Functional spot-check (SLP flip generalizes across distinct products):**
| product | PBE | Source_List_Price__c before → after |
|---|---|---|
| Advanced Authentication Modes-NewMaintenance | `01uWC000005wsZGYAY` | null → **3150** |
| Advanced Authentication Modes-Yearly (…-Ye…) | `01uWC000005wsZHYAY` | null → **124** |
| Workspaces-NewMaintenance | `01uWC000005wsjiYAA` | null → **2400** |

All three flip null→contributor-list; `NetUnitPrice` remains null on all (MTD-tier gap = Portion 3, expected). Reprices returned `isSuccess:true`, no "contributing products are missing" error.

**Regression control:** covered BoKS PBE `01uWC000005wsbVYAQ` carries **0** M5-marker rows — untouched (inserts only ever target uncovered PBEs).

**Reversible:** `sf data delete bulk` on `Legacy_Rule_Id__c='M5-PBEDP-20260630'` (171 rows) fully reverts.

## Remaining J-09 work (NOT applied)
- **Tier B (82 rows / 41 names):** held for the perpetual-vs-subscription semantics call → `MARC_DEBREY_HANDOFF.md`.
- **EFT 8 Express evidence PBE:** held for Marc's contributor pick (recommend `GS-GSE-RSS-EFES`).
- **Full `NetUnitPrice` resolution** on all these lines: requires **Portion 3 (MTD DATA)** to stamp Maintenance_Type_Defn values — PBEDP alone stamps SLP only.
