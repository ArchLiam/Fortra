# SC-3473 — Net-zero UI fix (TermDefined PricingTermCount) — apply in the Pricing Procedure canvas
Org: FortraUAT · Procedure: `Rev_Mgmt_Default_Pricing_Procedure` · Version: **V21 (Active)** · Net element change: **0**

## What you're changing (one filter, one added criterion)
You will broaden ONE existing filter so TermDefined lines get `PricingTermCount = 1` from the assignment that already
exists for Evergreen. No new steps/elements — you only add a criterion and edit the condition logic.

- Container (seq 29): label **"List Container"**, internal name `ListContainer92`
- Filter step inside it: `ListOperation93` (an **Advanced List Filter / List Operation**)
- The assignment already in this container sets `PricingTermCount` = `EvergreenPricingTermCountConstant` (value **1**)

## How to find the right element (it's a generic "List Container", so match by fingerprint)
1. Open Setup → **Pricing Procedures** → `Rev_Mgmt_Default_Pricing_Procedure` → open **Version 21**.
2. In the canvas, locate the element **"Evergreen anytime proration filter (Line level)"** (seq 27 — distinctly named).
3. Just after it are two generic **"List Container"** elements (seq 28, then seq 29). You want **seq 29**.
4. Confirm you have the right one by opening its filter — it must show EXACTLY these 3 conditions:
   | # | Field | Operator | Value |
   |---|-------|----------|-------|
   | 1 | `SellingModelType` | Equals | `Evergreen` |
   | 2 | `AllowPartialProrationPeriods` | Equals | `false` |
   | 3 | `itemTransientEndDate` | Is Null | — |
   Current **Condition Logic**: `1 AND (2 OR 3)`
   (Also: this container's action is an Assignment that outputs to `PricingTermCount`. That's the confirming fingerprint —
   NOT the seq-28 one, whose filter is `SellingModelType NotEquals Evergreen` / `NotEquals TermDefined`.)

## The edit
1. In that filter (`ListOperation93`), **add a 4th condition**:
   | # | Field | Operator | Value |
   |---|-------|----------|-------|
   | 4 | `SellingModelType` | Equals | `TermDefined` |
   (Type the value exactly `TermDefined` — same style as `Evergreen` in row 1.)
2. Set **Condition Logic** (custom/advanced logic) to:
   ```
   (1 AND (2 OR 3)) OR (4 AND 3)
   ```
   This keeps the Evergreen branch identical and adds "TermDefined AND itemTransientEndDate Is Null" (reusing condition 3).
3. **(Optional, cosmetic only)** In this container's assignment step, you may repoint the input constant from
   `EvergreenPricingTermCountConstant` to `PricingTermCountValueOneConstant` (both = 1) so the intent reads clearly for
   TermDefined. Skip this if it adds friction — it's not required for correctness.

## Save + activate (hygiene — avoids the known canvas clobber)
4. **Save in place** (NOT "Save As" — stay on V21; do not create V22/V23).
5. **Activate** V21 from **Setup → Pricing Procedures → Versions list** (the status flip), not from stale canvas state.
   If you had other canvas tabs open, close them first.
6. Refresh and re-open the seq-29 filter to confirm criterion 4 and the new condition logic persisted.

## Verify it works
7. Reprice a known-broken line and confirm `PricingTermCount` flips null → 1. Good test lines (currently null PTC,
   fully configured):
   - `0QLWC000003lizx4AA` (Cobalt Strike, created 2026-07-02)
   - `0QLWC000003kjjZ4AQ` (Fortra PCI Scanning)
   Open its quote in QLE → Reprice (or Reprice All on that quote) → the line's PricingTermCount should now be **1**.
8. Regression check — Evergreen lines are unchanged: an Evergreen line should still get PricingTermCount = 1 as before,
   and no line should error on reprice.
9. (I can run a SOQL sweep afterward: count of fully-configured TermDefined lines with null PTC created after the change
   should trend to 0.)

## Also patch the V22 draft
10. Apply the same single-criterion edit to the **V22 draft** so that if V22 is ever activated it won't reintroduce the bug.

## Rollback (if needed)
- Remove criterion 4 and set Condition Logic back to `1 AND (2 OR 3)`, Save in place, re-Activate. (No elements were added,
  so rollback is just this one filter revert.)

## Why this is correct / safe
- TermDefined lines are currently filtered OUT of the only PTC writer they could hit (seq 27 requires
  `itemTransientEndDate Is Not Null`, which is null for TermDefined in the reprice path) → PTC stays null → feeds the
  Delete-Group native NPE (SC-3473).
- Seq 29 already stamps PTC = 1 via a constant assignment for the analogous Evergreen "no live end-date" case. Adding the
  `(4 AND 3)` branch routes the exact broken TermDefined cohort there. Every healed TermDefined line observed = PTC 1.
- It does not touch Evergreen (branch 1) or any TermDefined line that does prorate in seq 27 (those have a non-null
  transient and are excluded by condition 3). Net element count stays 128 — under the ~129 ceiling.
- Caveat: constant PTC=1 matches all current TermDefined data (single full-term). If a *computed* PTC is ever needed for
  multi-term/partial TermDefined, that requires the 3-element proration writer (`V20_writer_subtree_template.xml`) + budget.
