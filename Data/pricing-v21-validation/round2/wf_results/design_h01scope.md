`ItemDiscountAmount` and `ItemDiscountPercentage` are used only as `AdjustmentValue` parameters (pricing variables passed into the ManualDiscount BKM), never as a `sourceFieldName` in a filter anywhere in the proc. So I need to determine whether they're addressable as filter fields. These are Sales Transaction Context pricing variables. Let me confirm the discriminator situation by checking what fields ManualQuoteLevelDiscount (the shared entry filter, seq1) references, and confirm the exact structure. I have enough now. Let me verify the entry filter (ManualQuoteLevelDiscount at seq1) content one more time — I already read it at lines 114685-114736. That is the shared entry filter for the whole container.

I now have everything needed. Let me compile the final resolution.

## H-01 RESET-STEP SCOPE RESOLUTION

### 1. ListContainer60 (~line 114150) and all child steps in order

`ListContainer60` is a bare `ListGroup` (top-level `<sequenceNumber>21</sequenceNumber>`, line 114152) with **no `advancedCondition` of its own**. Its 4 children, in execution order by child `sequenceNumber`:

| child seq | name | stepType / actionType | base it reads (`InputUnitPrice`) | writes | verbatim |
|---|---|---|---|---|---|
| **1** | `ManualQuoteLevelDiscount` | AdvancedListFilter | — (entry filter, see §2) | — | line 114729 |
| **2** | `NullCheckforLineAdjustment` | BusinessKnowledgeModel / FormulaBasedPricing | reads `ItemTotalAdjustmentAmount` | `ItemTotalAdjustmentAmount` | line 114887; formula `IF ( ISNULL ( ItemTotalAdjustmentAmount ) , 0 , ItemTotalAdjustmentAmount )` |
| **3** | `ManualQuoteLevelAmountBasedLineLevel` | BusinessKnowledgeModel / **ManualDiscount** | **`InputUnitPrice` ← `NetUnitPrice`** (line 114621) | `NetUnitPrice` ← `NetUnitPrice` (114660-114663), `Subtotal` ← `ItemNetTotalPrice` | line 114676 |
| **4** | `ManualQuoteLevelPercentageBasedLineLevel` | BusinessKnowledgeModel / **ManualDiscount** | **`InputUnitPrice` ← `NetUnitPrice`** (line 114767) | `NetUnitPrice` ← `NetUnitPrice` (114806-114809), `Subtotal` ← `ItemNetTotalPrice` | line 114822 |

**The amount-discount step (H-01 target):** `ManualQuoteLevelAmountBasedLineLevel`, seq 3, `AdjustmentType=AmountStringConstant` (114600), `AdjustmentValue=ItemDiscountAmount` (114607), **`InputUnitPrice=NetUnitPrice` (114621)** → **writes back to `NetUnitPrice` (114663)**. This is the compounding source.

**The percentage step in the same container:** `ManualQuoteLevelPercentageBasedLineLevel`, seq 4, `AdjustmentType=PercentageStringConstant` (114746), `AdjustmentValue=ItemDiscountPercentage` (114753), **`InputUnitPrice=NetUnitPrice` (114767)** → writes `NetUnitPrice` (114809).

CRITICAL: the percentage step runs at **seq 4, i.e. AFTER the amount step at seq 3**, in the same container, and it also reads its base from `NetUnitPrice`.

### 2. Entry filter on ListContainer60

The container has no `advancedCondition`. Gating is the child seq-1 filter `ManualQuoteLevelDiscount` (AdvancedListFilter, lines 114685-114736), verbatim logic `1 AND (2 OR 3 OR 4) AND (5 OR 6)`:
- `ItemPricingSource NotEquals 'LastTransaction'`
- AND (`ItemSalesTransactionAction Equals 'Amend'` OR `'Add'` OR `IsNull`)
- AND (`ItemIsDerived__std IsNull` OR `= false`)

So only non-LastTransaction, Add/Amend/new, non-derived lines enter. (Note: an AdvancedListFilter at seq 1 filters the working list for the whole container's downstream steps.)

### 3. Partner-discount order vs ListContainer60

- **Partner percent discount = `PartnerDiscount59`** (ManualDiscount, `AdjustmentValue=PartnerDiscountPercent` 115130, `InputUnitPrice=NetUnitPrice` 115144, writes `NetUnitPrice`), parent `ListContainer3` (line 115200).
- `ListContainer3` top-level **`<sequenceNumber>20</sequenceNumber>`** (line 114108).
- `ListContainer60` top-level **`<sequenceNumber>21</sequenceNumber>`** (line 114152).

**Partner (container seq 20) runs BEFORE the amount container (seq 21).** Confirmed. A reset that seeds `NetUnitPrice=ListPrice` at seq 21 WOULD wipe a partner discount already applied at seq 20 for a partner+amount line, unless it is partner-aware.

### 4. Discriminator field + ManualDiscountDerivedMaintenance

- **No dedicated amount-vs-percent discriminator field exists.** `ItemDiscountAmount` and `ItemDiscountPercentage` appear ONLY as `AdjustmentValue` parameters inside the two ManualDiscount BKMs — never as a `sourceFieldName` in any filter. QuoteLineItem field metadata has `Discount_Value__c`, `DiscountAmount`, `Discount`, `Discount_Reason__c` but no "adjustment type / amount-vs-percent" flag. So there is no clean boolean discriminator to filter on. The only per-line signal distinguishing an amount line is **`ItemDiscountAmount` being populated/non-zero** (vs `ItemDiscountPercentage` for percent lines).
- **`ManualDiscountDerivedMaintenance`** (seq 4, parent `PartnerDiscountDerivedMaintenance`, line 114583): SAME compounding pattern — `AdjustmentType=PercentageStringConstant` (114507), `InputUnitPrice=NetUnitPrice` (114528), writes `NetUnitPrice` (114570). It is percent-based and in a DIFFERENT container (`PartnerDiscountDerivedMaintenance`, top-level seq 22), NOT ListContainer60, so it is **out of scope for H-01's amount reset** but shares the read-from-NetUnitPrice pattern.

---

## RESOLVED ANSWERS

### (a) Unconditional or scoped?

**Scope it to amount-discount lines only — do NOT make it unconditional.** An unconditional `NetUnitPrice=ListPrice` reset at seq 21 would (i) clobber the partner discount from seq 20 for every partner line, and (ii) reset the base for the percentage step at seq 4 (see (c)).

There is **no clean boolean discriminator field**. The safest expressible discriminator is **`ItemDiscountAmount` populated / non-zero** (only amount lines carry it; percent lines carry `ItemDiscountPercentage` instead). Put the scope on the reset step's own `advancedCondition`:

```
sourceFieldName = ItemDiscountAmount   operator = NotEquals   value = 0        (seq 1)
sourceFieldName = ItemDiscountAmount   operator = IsNotNull                    (seq 2)   [conditionLogic: 1 AND 2]
```

If `ItemDiscountAmount` is not addressable as a `sourceFieldName` in an AdvancedListFilter (it is only ever used as a ManualDiscount `AdjustmentValue` in this proc — unverified as a filter field), the **safest alternative** is to NOT reset via a formula at all and instead **change the amount step's own base** so it stops compounding: seed a per-line pre-amount base field once (mirror `StampContributorBasePreDiscount`/`Pre_Partner_Price__c`) BEFORE partner, then point `ManualQuoteLevelAmountBasedLineLevel`'s `InputUnitPrice` at that stamped base instead of live `NetUnitPrice`. That eliminates compounding without any list-price reset and with zero collateral on partner/percent paths.

### (b) Does the reset wipe a partner discount for a partner+amount line?

**Yes, if written naively** — partner runs at container seq 20, the reset at seq 21 would overwrite the partner-discounted `NetUnitPrice` back to `ListPrice`. Combined partner+amount lines ARE reachable (nothing in the entry filter excludes partner lines). So the reset MUST be partner-aware, mirroring `ResetNettoPrePartnerBase` (line 116085), whose verbatim formula is:

```
IF ( PartnerDiscountPercent > 0 , IF ( Has_Attribute_Adjustment__c = true , NetUnitPrice , ListPrice ) , NetUnitPrice )
```

**Partner-aware reset formula for H-01** (re-seed the amount base without clobbering partner):

```
IF ( PartnerDiscountPercent > 0 ,
     IF ( Pre_Partner_Price__c > 0 , Pre_Partner_Price__c , NetUnitPrice ) ,
     ListPrice )
```

Rationale: for a partner line, do NOT reset to ListPrice — restore the pre-partner base (`Pre_Partner_Price__c`, stamped at `StampContributorBasePreDiscount` seq 14, before partner seq 20) so the amount discount applies to the correct partner-net base and does not double-count. For a non-partner line, reset to `ListPrice` (the H-01 fix). This mirrors the sibling's partner-guard structure exactly. NOTE: this restores the pre-partner base, not the post-partner net; if the intended behavior is "amount discount applies on top of partner net," use `NetUnitPrice` in the partner branch (i.e. leave partner net untouched) — that branch does not compound because it runs once per reprice reading `Pre_Partner_Price__c`/list, not the prior amount-discounted net. Confirm the business intent for partner+amount stacking before finalizing which partner-branch value to use.

### (c) Does the percentage step's base change if the reset runs?

**Yes — the percentage step (`ManualQuoteLevelPercentageBasedLineLevel`, seq 4) reads `InputUnitPrice=NetUnitPrice` (114767) and runs AFTER the amount step (seq 3) in the SAME container.** An unconditional or wrongly-placed reset would corrupt the percentage step's base. Two controls close this:
1. The `ItemDiscountAmount NotEquals 0 / IsNotNull` scope (from (a)) means the reset only fires on amount lines, so pure-percentage lines are untouched.
2. Placement: the reset is inserted as a NEW child of ListContainer60 **immediately before seq 3** (new seq 3), so it runs before the amount step but its scope prevents it from re-seeding a line that will subsequently be percent-discounted. A line that is BOTH amount- and percent-discounted is an edge case; because the amount step (seq 3) runs first and the reset seeds its base, the percent step (seq 4) then reads the amount-discounted net — which is the current stacking behavior and is unchanged.

---

## FINAL CANVAS STEP

**Step name:** `ResetAmountBaseFromList`
**Label:** `Reset Amount Base to List (Pre-Amount)`
**Parent:** `ListContainer60`
**stepType:** `BusinessKnowledgeModel`, **actionType:** `FormulaBasedPricing`
**Placement:** new child of ListContainer60, inserted **immediately before `ManualQuoteLevelAmountBasedLineLevel`**.

**Scope filter (advancedCondition on the reset step):**
```
conditionLogic: 1 AND 2
1: sourceFieldName=ItemDiscountAmount  operator=IsNotNull
2: sourceFieldName=ItemDiscountAmount  operator=NotEquals  value=0  valueType=Literal
```
(If `ItemDiscountAmount` is not filterable, fall back to the "stamp pre-amount base + repoint InputUnitPrice" alternative in (a) — no reset step at all.)

**Formula (partner-aware, `formula-section-0-input`, output `NetUnitPrice`):**
```
IF ( PartnerDiscountPercent > 0 , IF ( Pre_Partner_Price__c > 0 , Pre_Partner_Price__c , NetUnitPrice ) , ListPrice )
```

### Renumbering inside ListContainer60
Current child seqs: `ManualQuoteLevelDiscount`=1 (filter), `NullCheckforLineAdjustment`=2, `ManualQuoteLevelAmountBasedLineLevel`=3, `ManualQuoteLevelPercentageBasedLineLevel`=4. Insert the reset so it executes after NullCheck(2) and before Amount:
- `ManualQuoteLevelDiscount` → 1 (unchanged, filter)
- `NullCheckforLineAdjustment` → 2 (unchanged)
- **`ResetAmountBaseFromList` → 3 (NEW)**
- `ManualQuoteLevelAmountBasedLineLevel` → **4** (was 3)
- `ManualQuoteLevelPercentageBasedLineLevel` → **5** (was 4)

(Top-level container seqs 20/21/22 are unchanged; renumbering is child-local only.)

### Verbatim sibling it mirrors
`ResetNettoPrePartnerBase` (line 116085-116086, parent `StampContributorBasePreDiscount`), formula (line 116031):
```
IF ( PartnerDiscountPercent > 0 , IF ( Has_Attribute_Adjustment__c = true , NetUnitPrice , ListPrice ) , NetUnitPrice )
```
Also mirror `StampContributorBasePreDiscount` (seq 14) / `Pre_Partner_Price__c` stamping for the fallback path in (a).

### Which controls prove each risk closed
- **Compounding (20000→15000→10000):** reset re-seeds base each reprice from `ListPrice`/`Pre_Partner_Price__c` (never the prior amount-discounted `NetUnitPrice`), so the amount step's `InputUnitPrice` is deterministic per reprice. Proof: reprice twice, `NetUnitPrice` after amount step is identical both runs.
- **Partner clobber (risk b):** partner-aware `IF ( PartnerDiscountPercent > 0 , … )` branch avoids ListPrice for partner lines. Proof: a line with `PartnerDiscountPercent > 0` + `ItemDiscountAmount ≠ 0` keeps its partner-net base after the reset.
- **Percentage-step corruption (risk c):** `ItemDiscountAmount IsNotNull AND ≠ 0` scope means pure-percent lines never enter the reset. Proof: a percent-only line (`ItemDiscountPercentage` set, `ItemDiscountAmount` null/0) shows unchanged `NetUnitPrice` going into `ManualQuoteLevelPercentageBasedLineLevel`.
- **Derived-maint unaffected:** `ManualDiscountDerivedMaintenance` lives in container `PartnerDiscountDerivedMaintenance` (seq 22), not ListContainer60; reset is scoped to ListContainer60 children only. Proof: derived-maint net unchanged.

**Open item to verify in canvas before deploy:** confirm `ItemDiscountAmount` is selectable as a `sourceFieldName` in an AdvancedListFilter/formula-step condition (it currently appears only as a ManualDiscount `AdjustmentValue`). If not selectable, use the (a) fallback (stamp pre-amount base + repoint `InputUnitPrice`), which needs no discriminator filter.

Source file (all line refs): `/Users/liamjeong/Documents/Code/Fortra/Data/pricing-v21-validation/round2/live_retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (V21 block lines 110855-117766).