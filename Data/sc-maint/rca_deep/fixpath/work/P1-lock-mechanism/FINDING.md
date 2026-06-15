# P1-lock-mechanism — WHY NetUnitPrice is immutable on a settled derived QA-less node

## Verdict
The lock is **"DOES NOT RUN"**, not platform immutability. On a derived (`ItemIsDerived__std=true`)
renewal-maintenance line, the **only** RI=true element authorized to (re)write `NetUnitPrice` is the
native DerivedPricing action **`DerivedProductsRenewals`** (V14, line ~71913-72040). It is **contributor-
keyed**: it iterates a contributor list (`Contributor`/`ContributorUnitPrice`/`ContributorProduct`...)
and writes `NetUnitPrice` (output param, lines 72014-72020) only for derived lines that have a contributor
entry. A QA-less fossil has **no contributor entry**, so the action skips it, so `NetUnitPrice` is never
recomputed and the persisted fossil (60.64 / 54.58 / 0) is retained.

## Decisive evidence (canary 0QLWC000003e2Sn4AI, log `leverd_test/run/canary_finest.log`)
Across all 16 context dumps on the canary reprice:
- `InputUnitPrice = 67.38`  (writable — set by upstream RI=false formula/assignment; INPUT to derivation)
- `COLACalculatedPrice__c = 67.38`  (writable custom field — set by prehook)
- `NetUnitPrice = 60.64`  (STUCK at persisted fossil — OUTPUT of the contributor-keyed action, never recomputed)
- `ItemIsDerived__std = {0QLWC000003e2Sn4AI=true}`  (line IS derived)
- **ZERO `<lineId>cliN` contributor keys** anywhere in the canary log → contributor list is EMPTY for this line.

So the writable INPUT (InputUnitPrice) and a custom sibling field (COLACalculatedPrice__c) both move to 67.38,
but the OUTPUT NetUnitPrice does not — because the element that owns that output never fired on the line.

## The V14 pricing chain (active = ESV `9QMWC00000023eX4AQ`, versionNumber 14, sole `<status>Active</status>` @ line 69805)
1. `DerivedPricingRenewals` (RI=**false**, parentStep `ListContainer`, line 71764-71827): formula
   `IF(QuoteTypeText='Renewal', IF(COLACalc>0, COLACalc, (Base-PriorPartner-PriorDisc)*(1+COLA%/100)), NetUnitPrice)`
   → outputs NetUnitPrice **in-engine only** (RI=false ⇒ context, never committed). This is why 67.38 is
   *computed* and visible in the log but does not stick.
   - Its gate, the `DerivedPricing` AdvancedListFilter (line 71543-71611):
     `conditionLogic (1 AND 2 AND 3) OR (4 AND 5) OR (6 AND 7 AND 8)` where (6,7,8) =
     `QuoteTypeText='Renewal' AND Fortra_Product_Type='Renewal Maintenance' AND COLACalculatedPrice__c>0`.
     **No contributor / no QuoteActionId predicate** → fires for the fossils too (all 6 lines satisfy it).
2. `DerivedPricingValuesAssignment` (RI=false, line 71829-71878): copies context `NetUnitPrice → InputUnitPrice`.
3. `DerivedProductsNativePull` (ListGroup, RI=false, seq5, line 71880-71889): the native-pull container.
   - child `DerivedProductsNonRenewal` (RI=false, AdvancedListFilter, line 71891-71911): `QuoteTypeText NotEquals 'Renewal'`.
   - child **`DerivedProductsRenewals`** (actionType **DerivedPricing**, RI=**true**, seq2, line 71913-72040):
     inputs are ALL contributor params (`ContributingNetUnitPrice=ContributorUnitPrice`,
     `ContributingId=Contributor`, `ContributingProduct=ContributorProduct`, `DerivedFormula=ContributorFormulaInput`...);
     outputs `NetUnitPrice` (72014-72020) and `Subtotal=ItemNetTotalPrice` (72021-72027).
     **THIS is the only RI=true NetUnitPrice writer for derived renewal lines, and it is contributor-gated by construction.**

## Contributor sourcing (PBEDP `182WC000000HNcwYAG`)
- PricebookEntryDerivedPrice on derived PBE `01uWC000006XPPBYA4`: `ContributingProductId=01tWC00000DD1btYAD` (NRPS-PIAP
  perpetual license), `ProductId=01tWC00000DD1buYAD` (RRM), `Formula=UnitPrice`, `PricingSource=Product`, `Scope=Both`.
- In the test/regression order (`verify_finest.log`, quote 0Q0WC000002sjLZ0A) renewal derived lines ARE keyed
  in the Contributor map (e.g. `0QLWC000003NKkI4AWcli1 → 0QLWC000003NKkH4AW`, `ContributorProduct=01tWC00000DD1btYAD`)
  and one (`NKNh4AO`, contributor `NKNi4AO`) **commits a real NetUnitPrice=325.0** — proving contributor→commit works.
- The canary quote `0Q0WC0000038aXd0AI` has **only ONE line** (the RRM derived line) and **no license/contributor line**
  → empty contributor list → committer skips it.

## Why the CONTROL commits 67.38 (the born-net path) — what must change
Control line `0QLWC000003dEW24AM` (quote `0Q0WC00000382MH0AY`): QA=`7ocWC00000u7yf8YAA`, Type='Renew',
SourceAsset=`02iWC000008GKPaYAO`, **SourceAsset.Product2Id=01tWC00000DD1buYAD (RRM itself)**. The control's 67.38
is born at insert via `COLAUpliftHandler.handleBeforeInsert` (QA-gated, L29-31/L39/L280-282) → COLA_Source='CMDT Lookup',
and held through reprice. The control quote ALSO has no sibling NRPS license line — so the discriminator is **NOT a
sibling license line**; it is the **line-level Renew QuoteAction with an RRM-matched SourceAsset**, which (a) triggers
born-net Apex AND (b) provides the asset-based contributor that lets the native action keep re-deriving (or, the born
value being on the record, the engine has a settled committed value to retain that equals the correct 67.38).

## What specifically must change so the engine WRITES NetUnitPrice
Give the line a **Type='Renew' QuoteAction whose SourceAsset matches the RRM SKU** (a contributor). That is the
born-net path (Option 1 / H3). Confirmed: it is exactly "give the line a Renew QuoteAction/SourceAsset (a contributor)."
A reprice-time procedure committer that writes NetUnitPrice directly (lever-d) did NOT change the fossil in the
authorized test (and the element name never appears in the canary logs, so the test is ambiguous about whether it even
fired) — consistent with: for derived lines, `NetUnitPrice` is the OUTPUT of the contributor-keyed native action and an
ungated AssignmentElement write to the same engine-owned attribute on a contributor-less derived node does not durably commit.

## Caveat / residual
The micro-distinction between (i) the AssignmentElement write being silently discarded vs (ii) the engine reloading the
persisted NetUnitPrice for a contributor-less derived line after each element is not byte-proven; but the OUTCOME is
decisive — InputUnitPrice & COLACalculatedPrice__c reach 67.38, NetUnitPrice stays 60.64 — and the fix conclusion
(contributor at birth) is independent of that micro-distinction.
