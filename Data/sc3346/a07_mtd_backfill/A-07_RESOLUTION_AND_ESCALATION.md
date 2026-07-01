# A-07 — Maintenance-Type attribute (MTD) backfill — Resolution + Escalation

**Ticket:** SC-3346 / V21 defect **A-07** (P2, ORG-CONFIG-DEFECT)
**Org:** FortraUAT (`00DWC000006eUFF2A2`) — **UAT ONLY**, not deployed to production
**Date:** 2026-06-30 (executed 2026-07-01 UTC)
**Attribute:** `Maintenance_Type_Defn` (MTD) — AttributeDefinitionId `0tjWC000000096bYAA`
**Scope of this portion:** DATA only — `ProductAttributeDefinition` (PAD). No procedure edit, no Apex.

---

## 1. Summary

The defect: active **New Maintenance** Product2 records that lack an MTD `ProductAttributeDefinition`
row don't materialize a `Maintenance Type` attribute on their quote lines, so V21 **step 39**
("Derived Pricing Formula") tier lookup returns 0 → **NetUnitPrice = $0** instead of `SLP × 0.20`
(Standard tier).

Live gap at start: **1,567** of 1,683 active New-Maintenance products lacked the MTD PAD (only 116 carried it).

The originally-specified remediation — *"Bulk-insert ~1,567 identical PAD rows with hardcoded
`ProductClassificationAttributeId=11CWC000007hls42AA` / `AttributeCategoryId=0v3WC00000005ZEYAY`"* —
is **NOT viable**. `ProductAttributeDefinition.ProductClassificationAttributeId` is **non-nillable AND
per-classification**: it must reference the MTD `ProductClassificationAttr` (PCA) whose
`ProductClassificationId` = the product's `Product2.BasedOnId`. There are only **13** MTD PCAs (one per
classification). A single hardcoded PCA mismatches every other classification, and **0 of 9,591** PADs
org-wide have a null PCA or sit on an unclassified product — proving both constraints.

**Only 91 products (the FEAT_ONLY classification) were cleanly backfillable within the DATA-only boundary.
Those 91 were backfilled and verified.** The remaining **1,476** need a product-owner decision (below).

---

## 2. What was done — 91 rows backfilled (DONE, verified)

Backfilled the **91** active New-Maintenance products in classification **FEAT_ONLY**
(`11BWC0000037mB52AI`), the only gap classification that has a matching MTD PCA
(`11CWC0000096yh32AA`).

- **Method:** Bulk API v2 insert — job `750WC00000RYYRAYA5`, **91 success / 0 fail**.
- **Row shape** (copied from the working BoKS gold control + the FEAT_ONLY PCA):
  - `AttributeDefinitionId` = `0tjWC000000096bYAA`
  - `Name` = `Maintenance Type`
  - `DefaultValue` = `Standard`
  - `IsPriceImpacting` = **true**
  - `IsRequired`/`IsHidden`/`IsReadOnly` = false, `Status` = `Active`
  - `ProductClassificationAttributeId` = **`11CWC0000096yh32AA`** (the FEAT_ONLY PCA — **NOT** the
    spec's `11CWC000007hls42AA`, which belongs to MTYPE_STYPE and would have mismatched)
  - `AttributeCategoryId` = **null** (the FEAT_ONLY PCA carries no category — **NOT** the spec's
    `0v3WC00000005ZEYAY`)
- **Result:** MTD PADs 186 → **277** (+91); on active New-Maint 116 → **207**; FEAT_ONLY gap 91 → **0**.
- Input files: [ids.txt](ids.txt), [mtd_insert.csv](mtd_insert.csv).

### Verification (DoD met — non-zero derived tier)

Repriced on the Draft test quote **0Q0WC000003FJ2D0AW** ("Q-Train the Trainer - Derived Pricing").
A **freshly-added** FEAT_ONLY New-Maintenance line materialized `Maintenance Type = Standard` from the
new PAD and priced correctly. Clean A/B on the **same product** (Tripwire Enterprise Console-NewMaintenance,
`01tWC00000DD1hUYAT`, FEAT_ONLY, SLP = 6995):

| Line | Created | MTD attr on line | NetUnitPrice |
|---|---|---|---|
| `0QLWC000003kTje4AE` (pre-backfill) | 2026-06-29 | absent | **$0** ❌ |
| `0QLWC000003lEaU4AU` (post-backfill, fresh) | 2026-07-01 | **Standard** | **$1,399** ✅ (= 6995 × 0.20) |

> Note on existing lines: a reprice (even `configurationMethod=Force`) does **not** retrofit a newly-added
> product attribute onto a line that was already configured/decomposed *before* the PAD existed — RCA locks
> the line's attribute set at creation. **New** lines materialize MTD automatically. So the 91 products are
> fixed going forward; any already-open quote/line predating this backfill must be re-added/re-quoted to pick
> up MTD. (The temporary test lines added during verification were removed; the quote was restored to its
> original 5 lines.)

---

## 3. Escalation — 1,476 products BLOCKED for the product owner

These cannot be fixed by a PAD insert alone (the DATA-only boundary of this portion). They split into two buckets.

### BLOCKED-A — classified, but the classification has NO MTD PCA — **541 products**

A PAD can't be inserted because there is no MTD `ProductClassificationAttr` for the product's classification
(and `ProductClassificationAttributeId` is required). File: [blocked_A_classified_no_pca.csv](blocked_A_classified_no_pca.csv).

| Classification | BasedOnId | Products | Includes |
|---|---|---:|---|
| STYPE_ONLY | 11BWC0000037mBF2AY | 333 | |
| PL_STYPE | 11BWC0000037mBH2AY | 127 | |
| DTYPE_STYPE | 11BWC0000037mBO2AY | 18 | |
| FEAT_STYPE | 11BWC0000037mBN2AY | 17 | |
| **FEAT_UTYPE** | 11BWC0000037mB92AI | 15 | **FIM CCM — CCM Management Server** (`01tWC00000DD16LYAT`) |
| **FEAT_UTYPE_NUMUNITS** | 11BWC0000037mB42AI | 6 | **FIM CCM — CCM Limited Scan Engine** (`01tWC00000DD16HYAT`) |
| FEAT_PL_STYPE_GNUM | 11BWC0000037mBr2AI | 5 | |
| FEAT_PTIER | 11BWC0000037mCZ2AY | 5 | |
| FEAT_UTYPE_STYPE | 11BWC0000037mBR2AY | 4 | |
| UTYPE_ONLY | 11BWC0000037mBE2AY | 2 | |
| PL_STYPE_OS | 11BWC0000037mCe2AI | 2 | |
| UTYPE_PL_STYPE | 11BWC0000037mBc2AI | 2 | |
| FEAT_PTIER_UTYPE_NUMUNITS | 11BWC0000037mCL2AY | 1 | |
| UTYPE_NUMUNITS_DTYPE_STYPE | 11BWC0000037mBp2AI | 1 | |
| UTYPE_NUMUNITS | 11BWC0000037mB62AI | 1 | |
| UTYPE_NUMUNITS_STYPE_OS | 11BWC0000037mC62AI | 1 | |
| FEAT_STYPE_CL | 11BWC0000037mCB2AY | 1 | |
| **Total** | | **541** | |

> **The headline FIM CCM evidence (CCMMSN / CCMLSE) is here** — both are in FEAT_UTYPE / FEAT_UTYPE_NUMUNITS,
> neither of which has an MTD PCA. **A-07's original DoD ("reprice FIM CCM → non-zero") is unreachable via a PAD
> backfill.** FIM CCM specifically requires one of the remediation options below.

### BLOCKED-B — no classification at all (`BasedOnId = null`) — **935 products**

No classification → no PCA to reference → cannot carry any product-level PAD. File:
[blocked_B_null_basedonid.csv](blocked_B_null_basedonid.csv). These need a classification assigned first.

**Reconciliation:** 91 backfilled + 541 (BLOCKED-A) + 935 (BLOCKED-B) = **1,567** original gap. ✓

---

## 4. Recommended remediation for the 1,476 (product-owner / architecture decision)

Pick per option — **all are outside the DATA-only PAD boundary of this portion**:

1. **Add MTD `ProductClassificationAttr` to the affected classifications** (esp. FEAT_UTYPE +
   FEAT_UTYPE_NUMUNITS for FIM CCM). Then a PAD backfill like the 91 becomes possible for BLOCKED-A. This is a
   schema/config change on `ProductClassificationAttr` (not just PAD).
2. **Add a documented `Standard`/0.20 default directly in V21 step 39** so the tier resolves when the MTD
   attribute is absent. This is a **procedure change owned by Portion 1** — it fixes all 1,476 at once (and the
   91) without any per-product data, and is the lowest-effort path if a flat 0.20 New-Maint default is
   acceptable to the business.
3. **Assign classifications to the 935 null-`BasedOnId` products** (BLOCKED-B), then option 1/backfill. Largest
   data effort; likely only worth it for products actually sold as New Maintenance.

**Recommendation:** Option 2 (step-39 default) is the most robust single fix for the residual 1,476 — it
removes the dependency on per-classification PCAs entirely. The 91 FEAT_ONLY backfill done here is complementary
and correct regardless.

---

## Artifacts
- [ids.txt](ids.txt) — 91 backfilled Product2 Ids
- [mtd_insert.csv](mtd_insert.csv) — the exact Bulk insert payload (job `750WC00000RYYRAYA5`)
- [blocked_A_classified_no_pca.csv](blocked_A_classified_no_pca.csv) — 541 (incl. FIM CCM)
- [blocked_B_null_basedonid.csv](blocked_B_null_basedonid.csv) — 935
