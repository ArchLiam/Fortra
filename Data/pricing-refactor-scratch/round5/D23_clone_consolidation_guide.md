# D-23 / INV-19 — Intra-V21 Clone-Clutter Consolidation Guide

**Round 5 · Tab 3 · Read-only ESD close-out · 2026-07-08**
**Headline: the "clone clutter" is a READABILITY/diffability problem, not a dead-code problem. ~Zero elements are safely deletable — every clone candidate writes a distinct wired field. The recommended action is label-RENAME hygiene (all provably 0-delta); recommended deletions = 0.**

---

## 1. Method

Parsed the **fresh** active V21 block (retrieved from FortraUAT 2026-07-08; preserved as `round5/active_v21_block_20260708.xml` = full-file lines **110855–117770**) into all **128 `<steps>` elements** with `name / label / stepType / parentStep / sequenceNumber / conditionLogic / field-I·O`. (Confirms INV-19's "128 steps", "16 dup-label groups", "Copy-of-Copy triad", "~28 ListContainer sprawl". My fresh block is 6,916 lines vs the Jul-6 extract's 6,895 — recent canvas edits, so this inventory supersedes the earlier one.)

## 2. The 0-delta rule used throughout

In an ExpressionSetDefinition, **runtime identity = `<name>` + field inputs/outputs + `<conditionLogic>`**. `<label>` is **display-only** and is referenced by nothing. Therefore:
- **Renaming a `<label>` is provably 0-delta** — it changes no wired reference and no `<conditionLogic>` string.
- **Deleting any of the clone candidates below is NOT 0-delta** — each writes a distinct output field (`Total_Software__c`, `Total_Subscription__c`, …) consumed downstream; deleting strands that field. → **rename-only, do not delete.**

**D-20 / INV-ESD-FILTER-POSITIONAL cross-check (binding):** `AdvancedListFilter` criteria are positional — `<conditionLogic>` wires them by `<sequenceNumber>`, so removing a criterion renumbers survivors and silently rewrites the logic. **Every recommendation in this guide is label-only and removes NO criterion**, so the positional-renumber hazard is *not* triggered by any action here. It is flagged where a future structural merge *would* hit it (§5).

---

## 3. The real "Copy of Copy" triad — KEEP ALL, RENAME ONLY (do NOT delete)

Top-level seq 35/36/37. The "Copy 1 of …" labels are clone *provenance*, but each container was re-pointed to a **different product-type filter and a different aggregate output field** — they are the **K-09 category-rollup trio** (paired with the seq 32/33/34 "Reset Total … (K-09 zero-init)" steps).

| Container `<name>` | seq | Current label | Child filter (on `Fortra_Product_Type__c`) | **Writes** | Action |
|---|---|---|---|---|---|
| `ListContainer8` | 35 | `List Container 8` | `TotalServices` | `Total_Services__c` | **Rename label** → `Aggregate Total Services (K-09)` |
| `Copy1ofListContainer8` | 36 | `Copy 1 of List Container 8` | `TotalSoftware` | `Total_Software__c` | **Rename label** → `Aggregate Total Software (K-09)` |
| `Copy1ofCopy1ofListContainer8` | 37 | `Copy 1 of Copy 1 of List Container 8` | `TotalSubscription` | `Total_Subscription__c` | **Rename label** → `Aggregate Total Subscription (K-09)` |

**0-delta rationale:** each output field appears exactly twice in V21 (its K-09 reset + this aggregate write) → each is wired and load-bearing → **rename only — do not delete** (this is exactly the task's "clone that DOES carry a wired reference" bucket). Renaming the display label touches no `<name>`, no field I/O, no `<conditionLogic>`. The child filters (`TotalSoftware`, `TotalSubscription`) may optionally be relabeled to match, but their `conditionLogic` (`1`) and single criterion are **not** to be edited.

> Canvas how-to (label-based): open V21 → in the element tree find the group labeled **"Copy 1 of List Container 8"** (it is the one whose aggregate output is `Total_Software__c`) → open it → edit **Label** only → Save. Repeat for "Copy 1 of Copy 1 of List Container 8" (`Total_Subscription__c`). **Do not** use "Delete Group" on any of the three.

---

## 4. Duplicate-label groups — classification (why almost none are deletable)

The 16 duplicate-label groups fall into three buckets. Only the *labels* are duplicated; the *elements* are functionally distinct.

### 4a. RLM default-label sprawl — RENAME for diffability, KEEP all (no deletion)
| Duplicate label | Count | What they actually are | Action |
|---|---|---|---|
| `List Container` | **12** ListGroups (seq 4,5,9,10,20,24,25,26,28,29,30,31) | 12 **distinct** pricing groups left on the RLM default label (attribute pricing, contacted, qty×price, list-ops, etc.) | Rename each to its function (child filter labels already describe them). **Not copies of each other — do not delete.** |
| `List Operation` | **8** AdvancedListFilters | Entry filters of 8 different groups, each a **different `conditionLogic`** (`1` · `1 AND 2` · `(1 AND (2 OR 3)) OR (4 AND 3)` · …) | Rename to match parent group. **Distinct gates — do not delete.** |
| `Assignment` | 4 | RLM default label on `section-0-input1` AssignmentElements in 4 different parents | Optional rename; cosmetic. Do not delete. |
| `Subscription Pricing` | 3 | `Quantity` BKM (qty×price) in 3 different containers | Optional rename; cosmetic. Do not delete. |

**0-delta rationale:** these share a *label* only; each has a unique `<name>` and lives under a different `parentStep`, computing a different result. Deleting any would drop a live pricing group. Renaming is 0-delta and is the entire benefit (makes the §7 waterfall diff-by-label mandate actually work).

### 4b. Filter+Action pairs inside ONE container — NOT clones (each "x2" is one functional unit)
`Attribute Value Pricing – Calculated/Total-Price/Unit-Price Mode`, `COLA Uplift on Renewal`, `Contacted Pricing`, `GSA Pricing`, `Partner Discount`, `Quantity * Price`, `Regional Services Price`, `Partner Discount – Derived Maintenance` (×3). Each "duplicate label" is simply the group's **[filter, action(-BKM)]** members sharing the group label. **These are single functional units, not clones.** Action: **none required** (optionally the child action can be relabeled `… – calc`/`… – filter`, purely cosmetic). No deletion.

### 4c. The two `Attribute Pricing Filter` groups — investigate, do NOT merge blindly
`AttributePricingFilter` (parent `ListContainer`, `1 AND 2 AND 3 AND 4`) vs `AttributePricingFilter8` (parent `ListContainer7`, `(1 OR 2) AND 3`). **Different criteria sets → different match populations**; likely two intentional attribute-pricing paths. **Do not delete/merge without a full-matrix parallel-run proof** that their match sets are truly disjoint-or-redundant. Default action: rename the two parent groups (`List Container` / `List Container`) to distinguish them; keep both.

---

## 5. The two `Aggregate Price` elements (seq 45, 46) — KEEP BOTH, RENAME (not clones)

Both are top-level `section-count` / `GroupingAndAggregatePricing` BKM steps sharing the label "Aggregate Price", but they compute **different aggregations**:
- **seq 45:** `section-0-group-count = 0` → **ungrouped** SUM (across all lines).
- **seq 46:** `section-0-group-count = 1`, `section-0-group-0 = SalesTransactionItemGroup` → **grouped** SUM (per item group).

**Not a clone.** Action: rename → `Aggregate Price (ungrouped)` and `Aggregate Price (per item group)`. **Do not delete either** — different outputs feed different rollups. 0-delta (label only).

---

## 6. Oversized ListContainers (INV-19 "sprawl")

The sprawl is a *count* problem (≈28 ListContainer-named groups), not a single fat container: the largest holds **5** children (`ListContainer57`); most hold 2–4. There is **no single 28-member container** to split. The remediation is the §4a rename pass (make the 28 groups self-describing), **not** structural surgery. No deletion.

---

## 7. Owner action summary (all 0-delta)

1. **Rename** the Copy triad (§3): 3 labels. Highest value (kills the misleading "Copy of Copy" provenance that implies dead code).
2. **Rename** the 12 `List Container` + 8 `List Operation` default labels (§4a) to their functions. Enables label-based waterfall diffing (§7 mandate / D-5).
3. **Rename** the 2 `Aggregate Price` elements (§5) to `ungrouped` / `per item group`.
4. **Investigate** (do not act) the two `Attribute Pricing Filter` paths (§4c) under a parallel-run gate before any merge.
5. **Deletions recommended: 0.** Every candidate carries a wired field/output; deleting is not 0-delta. **Remove no `AdvancedListFilter` criterion** (D-20 positional hazard).

> Net: D-23 is real as *label debt* but the plan's "consolidation" framing should be read as **label-rename hygiene**, not element removal. This closes D-23 as a low-risk, in-place, 0-delta canvas rename pass — and explicitly refutes any read that treats the Copy triad or the ListContainer sprawl as deletable dead code.
