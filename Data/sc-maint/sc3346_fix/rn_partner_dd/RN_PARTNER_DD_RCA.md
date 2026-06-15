# SC-3346 RN-PARTNER-DD — Live V14 Partner-Discount Mechanism RCA

READ-ONLY. Retrieved fresh from FortraUAT 2026-06-14 via tooling API
(`SELECT Metadata FROM ExpressionSetDefinition WHERE DeveloperName='Rev_Mgmt_Default_Pricing_Procedure'`).

- ExpressionSet: `9QLWC0000015cDl4AI`
- Active ExpressionSetVersion: `9QMWC00000023eX4AQ` VersionNumber **14**, IsActive=true,
  LastModified 2026-06-14T04:46:20Z by 005WC00000MgTN2YAN.
- Active version block in metadata: `label="Rev Mgmt Default Pricing V14"`, `status="Active"`, 107 steps.
- Files: `ESD_full_metadata_LIVE.json` (all 14 versions), `V14_ACTIVE_block.json` (active block; line numbers below reference this file).

## VERDICT (answer to KEY QUESTION)

The live V14 procedure **does NOT, by element ordering, transform 67.38 → 60.64 on a renewal-maintenance
derived line.** The two ×0.90 partner-discount writers are both **GATED OUT** of renewal-maintenance derived lines:

- `PartnerDiscountDerivedMaintenance20` is excluded by its filter criterion 5 `QuoteTypeText__c NotEquals 'Renewal'`.
- `PartnerDiscount30` is excluded by its filter `DerivedPricingAttribute IsNull OR =false` (a derived line has `DerivedPricingAttribute=true`).

The only element that actually **commits** NetUnitPrice on a renewal-maintenance derived line is
`DerivedProductsRenewals` (`resultIncluded=true`), the native DerivedPricing committer behind the
`DerivedProductsNonRenewal` gate (`QuoteTypeText__c NotEquals 'Renewal'`). For a Renewal line that gate is FALSE,
so the filter passes the line through to the committer. The COLA-net value travels into `NetUnitPrice` /
`InputUnitPrice` via the `resultIncluded=false` formula chain, and the committer carries it forward.

**The 60.64 is a born-stale value the procedure FAILS TO OVERWRITE on some lines — it is NOT deterministically
produced by V14.** Proof: 6 live `Renewal Maintenance` QLIs with byte-identical inputs
(COLACalculatedPrice=67.38, Base_Price=71, Prior_Partner_Discount=8.52, COLA%=7.85, ListPrice=0) committed
**four different NetUnitPrice values**: 67.38 (correct), 60.64 (=67.38×0.90, the bug), 54.58 (=60.64×0.90, double-stacked),
and 0 (MissingContributor family). A deterministic procedure cannot emit four answers from one input set.
The ×0.90 is real (arithmetic exact) but it is **persisted on the line from a prior cycle / pre-priced source**,
and on the buggy lines the committer leaves it intact rather than re-deriving 67.38 from COLACalculatedPrice.

This is the SC-3346 doc-12/13 "no-priced-node / MissingContributor" family, not an in-procedure ×0.90 step.

---

## 1. Every partner-discount element in active V14

### A. `PartnerDiscountDerivedMaintenance` (ListGroup, seq 8) — the derived-maintenance partner block

Three children (parentStep=`PartnerDiscountDerivedMaintenance`):

**(i) `PartnerDiscountDerivedMaintenance19`** — AdvancedListFilter, the GATE (V14 line 5353). resultIncluded=false.
`conditionLogic = "1 AND 2 AND 3 AND 4 AND 5"`:
1. `DerivedPricingAttribute IsNotNull`
2. `DerivedPricingAttribute Equals 'true'`
3. `Deal_Type__c NotEquals 'Fortra Originated'`
4. `ItemPricingSource NotEquals 'LastTransaction'`
5. **`QuoteTypeText__c NotEquals 'Renewal'`**  ← excludes renewals entirely

**(ii) `PartnerDiscountDerivedMaintenance20`** — ManualDiscount BKM (V14 line 5464). **resultIncluded=true** — a committer when it fires.
customElement I/O (the ×0.90 mechanism):
- IN `AdjustmentType = PercentageStringConstant` (="Percentage")
- IN `AdjustmentValue = PartnerDiscountPercent` (line 5390 — the partner margin %, ~10% → ×0.90)
- IN `Quantity = LineItemQuantity`
- IN `InputUnitPrice = InputUnitPrice`
- OUT `NetUnitPrice = NetUnitPrice` (output=true)
- OUT `Subtotal = ItemNetTotalPrice` (output=true)

This is exactly the element that would compute `NetUnitPrice = InputUnitPrice × (1 − PartnerDiscountPercent/100)`.
But filter (i) criterion 5 means it **never fires on a renewal**.

**(iii) `StampPartnerUnitPriceDerivedMaintenance`** — AssignmentElement (V14 line 6553). resultIncluded=false.
Copies `NetUnitPrice → PartnerUnitPrice` (a custom stamp field). Does not commit standard output.

### B. `PartnerDiscount` block under `ListContainer3` (ListGroup, seq 11) — the general (non-derived) partner discount

**`PartnerDiscount`** — AdvancedListFilter, GATE. resultIncluded=false.
`conditionLogic = "1 AND (2 OR 3)"`:
1. `Deal_Type__c NotEquals 'Fortra Originated'`
2. `DerivedPricingAttribute IsNull`
3. `DerivedPricingAttribute Equals 'false'`
→ requires the line to be NON-derived. A derived line (`DerivedPricingAttribute=true`) FAILS this gate.

**`PartnerDiscount30`** — ManualDiscount BKM, parentStep=ListContainer3. **resultIncluded=true.**
Identical I/O contract to `PartnerDiscountDerivedMaintenance20`
(AdjustmentValue=`PartnerDiscountPercent`, InputUnitPrice→NetUnitPrice out). Also gated off derived lines.

**No other element in V14 reads `PartnerDiscountPercent` or applies a partner ×0.90.**

---

## 2. NetUnitPrice writers & execution order for a renewal-maintenance derived line

All 15 elements that write `NetUnitPrice` (output=true), with their gate filter and commit flag:

| element | resultIncluded | gate filter | fires on renewal-maint derived line? |
|---|---|---|---|
| DerivedPricingFormula | **false** | `AttributeDefinitionCode='MTD'` | yes (NB tier×SLP into NetUnitPrice, non-committing) |
| DerivedPricingNetUnitPriceValueReset | **false** | `ItemIsDerived=true` | yes (`IF Renewal then NetUnitPrice else 0`) |
| DerivedPricingRenewals | **false** | DerivedPricing filter (below) | yes (COLA net → NetUnitPrice, non-committing) |
| COLAUpliftonRenewalNet | **false** | COLA filter (ItemPricingSource='LastTransaction') | conditionally |
| **DerivedProductsRenewals** | **TRUE** | `DerivedProductsNonRenewal` (`QuoteType ≠ Renewal`) | **yes — THE committer** |
| PartnerDiscountDerivedMaintenance20 | true | `QuoteType ≠ Renewal` (crit 5) | **NO — gated out** |
| PartnerDiscount30 | true | non-derived only | **NO — gated out** |
| (AttributeBasedPrice, AttributeDiscountEntries, BundleBasedAdjustmentEntries, VolumeDiscountEntries, SubscriptionPricing, ManualQuoteLevel*, PricingSetting) | true | various non-derived/non-renewal scopes | NO |

`DerivedPricing` gate (parentStep of `DerivedPricingRenewals`, V14):
`(DerivedPricingAttribute=true AND AttributeDefinitionCode='MDT') OR (QuoteType='Renewal' AND ItemIsDerived=true) OR (QuoteType='Renewal' AND Fortra_Product_Type__c='Renewal Maintenance' AND COLACalculatedPrice__c>0)`
→ a renewal-maintenance derived line with COLA>0 PASSES (clause 3).

### Order on a renewal-maintenance derived line
1. `DerivedPricingFormula` → writes NB-tier×SLP into NetUnitPrice (resInc=false, doesn't commit)
2. `DerivedPricingRenewals` → `IF Renewal: IF(COLA>0, COLA, ...)` → writes **67.38** into NetUnitPrice (resInc=false) — V14 line 2696
3. `DerivedPricingValuesAssignment` → copies NetUnitPrice → InputUnitPrice
4. `COLAUpliftonRenewalNet` (if ItemPricingSource='LastTransaction') → COLACalculatedPrice → NetUnitPrice (resInc=false) — line 2177
5. **`DerivedProductsRenewals`** (resInc=TRUE) → the native committer; reads contributor inputs + carries the
   derived/COLA net → commits NetUnitPrice + ItemNetTotalPrice — V14 line 3054
6. Partner steps `PartnerDiscount30` / `PartnerDiscountDerivedMaintenance20` — **both skipped** (gates fail)

There is NO partner ×0.90 step downstream of the COLA/committer that runs on a renewal line.

---

## 3. COLA elements & resultIncluded — what commits

- `DerivedPricingRenewals` (formula, line 2696): `resultIncluded=false`. Writes the COLA net to NetUnitPrice but
  is **non-committing** — it stages the value into the working node for downstream elements.
- `COLAUpliftonRenewal27` (assignment, line 2106): COLACalculatedPrice → InputUnitPrice. resInc=false.
- `COLAUpliftonRenewalNet` (assignment, line 2177): COLACalculatedPrice → NetUnitPrice. resInc=false.
- `DerivedPricingNetUnitPriceValueReset` (line 2609): `IF Renewal then NetUnitPrice else 0`. resInc=false.

All COLA/derived-formula NetUnitPrice writers are **resultIncluded=false**, confirming the docs. They do NOT
themselves commit to the output node; the COLA net only persists if a `resultIncluded=true` committer
(`DerivedProductsRenewals`) carries it forward. When the committer cannot resolve a contributor (the
MissingContributor / $0 family), it does NOT overwrite the line's born NetUnitPrice — so whatever value was already
persisted on the line (67.38, 60.64, or 0 from a prior cycle/source) survives.

---

## 4. Gating summary for the renewal-maintenance derived line

| question | answer |
|---|---|
| Does a partner ×0.90 element apply to the renewal-maint derived line? | **No** — both partner writers gated out |
| Gated by what? | DerivedMaint partner: `QuoteType ≠ Renewal`; General partner: non-derived-only |
| Distinguishes QuoteAction-linked vs null? | The committer is gated on `QuoteType`/`ItemPricingSource`, not QuoteAction directly; the COLA filter keys on `ItemPricingSource='LastTransaction'` |
| Distinguishes ItemIsDerived / ListPrice=0? | Yes — DerivedPricing & DerivedPricingFilter key on `ItemIsDerived=true`; these are the IsDerived/$0-list lines |

---

## 5. Live evidence (read-only QLI query, 2026-06-14)

6 `Renewal Maintenance` QLIs, identical inputs (COLA=67.38 except one, Base=71, PriorPartner=8.52, COLA%=7.85, ListPrice=0):

| QLI | COLACalculatedPrice | committed NetUnitPrice | interpretation |
|---|---|---|---|
| 0QLWC000003dEW24AM | 67.38 | **67.38** | correct (COLA net, no ×0.90) |
| 0QLWC000003e2Sn4AI | 67.38 | **60.64** | bug = 67.38 × 0.90 |
| 0QLWC000003dAaT4AU | 67.38 | **60.64** | bug = 67.38 × 0.90 |
| 0QLWC000003cy334AA | 60.64 | **54.58** | double-stacked = 60.64 × 0.90 |
| 0QLWC000003cN584AE | 67.38 | **0** | MissingContributor / $0 family |
| 0QLWC000003ck6X4AQ | 67.38 | **0** | MissingContributor / $0 family |

Arithmetic exact: 67.38×0.90=60.64; 60.64×0.90=54.58. Same procedure, same inputs, four outputs ⇒ the committed
value is provenance-dependent (carried from line state), not procedure-deterministic. The ×0.90 is applied
**upstream of / outside** the live V14 procedure (seed/prior-cycle/initiateRenewal carry-forward), and V14's
`DerivedProductsRenewals` committer fails to re-derive and overwrite it to 67.38 on the affected lines.

## Conclusion

In live V14 the partner ×0.90 cannot stack on the COLA net **within the procedure** for a renewal-maintenance
derived line — both partner writers are filter-gated out (renewal / non-derived). The 60.64 is a born-stale value
the procedure does not overwrite, in the same MissingContributor/no-priced-node failure mode that also produces the
$0 lines. Fix direction is the COLA/derived committer not reliably overwriting (the doc-12/13 prehook-seed /
contributor-resolution path), NOT removing or re-gating a partner step.
