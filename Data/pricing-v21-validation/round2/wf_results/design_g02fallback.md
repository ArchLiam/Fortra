Confirmed: the current live V21 does NOT contain the `CurrencyIsoCode='USD'` gate (it was reverted in Round 1). The G-02 fix must ADD the gate AND the fallback. I now have everything needed. Here is the complete design.

---

# G-02 PBE Fallback — Canvas Step Design (V21, active pricing procedure)

## Part 1 — The ABA containers and what they write (verbatim, V21)

**`ListContainer` (seq4, line 114015-114025)** and **`ListContainer7` (seq5, line 114158-114168)** are both bare `ListGroup` wrappers:
```
<name>ListContainer</name>  … <sequenceNumber>4</sequenceNumber> … <stepType>ListGroup</stepType>
<name>ListContainer7</name> … <sequenceNumber>5</sequenceNumber> … <stepType>ListGroup</stepType>
```

Inside each is a filter + a `BusinessKnowledgeModel` ABA discount step:

- **`ListContainer` → `AttributePricingFilter` (seq1, 112004)** gates entry: `ItemContractAttributePasId IsNotNull AND ItemPricingSource != 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute = false`.
- **`ListContainer` → `AttributeBasedPrice` (seq2, 111795)** — `actionType=AttributeDiscount`; **output is `NetUnitPrice`** (and `Subtotal → ItemNetTotalPrice`). It writes the attribute-adjusted net directly into `NetUnitPrice`, not a separate override field.
- **`ListContainer7` → `AttributeDiscountEntries` (seq2, 111965)** — same `AttributeDiscount` action; verbatim output params:
```
<name>NetUnitPrice</name> <output>true</output> <value>NetUnitPrice</value>
<name>Subtotal</name>      <output>true</output> <value>ItemNetTotalPrice</value>
```

So both ABA steps **assign `NetUnitPrice` in place** from the Attribute Discount decision table. When G-02 gates the two container filters to `CurrencyIsoCode='USD'`, a non-USD ABA line is filtered OUT and its `NetUnitPrice` is never seeded here — it stays 0.

## Part 2 — The list-price step (currency-matched PBE)

**`PriceBookEntries` (seq2, TOP-LEVEL, line 115580)** — `actionType=ListPrice`, runs at top-level **sequenceNumber 2** (before the ABA containers at 4/5). It passes the line's currency into the lookup and writes `ListPrice`:
```
<name>CurrencyIsoCode</name> … <value>CurrencyIsoCode</value>   (input, line 115466-115469)
<name>ListPrice</name>       <output>true</output> <value>ListPrice</value>  (115564-115567)
<name>IsDerived</name>       <output>true</output> <value>DerivedPricingAttribute</value>
```
Because it filters PBE by `CurrencyIsoCode`, on a EUR line `ListPrice` is loaded with the **EUR PBE UnitPrice (2943.99)**, NOT the USD 1575. This is exactly the currency-matched value the fallback must seed from. It runs at seq2 — well before the ABA containers (seq4/5) and the FX step (seq39), so `ListPrice` is already correct and available when the fallback fires.

## Part 3 — Why a normal EUR line nets correctly but an ABA EUR line ends at $0

There are two independent net-seed paths, and the attribute line skips both:

1. **`OneTimeNetSeed`** (label "OneTime Net Seed", line 115024, parent `SeedOneTimeNetBeforePartner` seq19), formula:
   `IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )`.
   Its gate **`OneTimeNetSeedFilter`** (115072) requires `SellingModelType != 'Evergreen' AND != 'TermDefined' AND ItemPricingSource != 'LastTransaction' AND (DerivedPricingAttribute IsNull OR = false)`. A normal non-ABA EUR line passes here and gets its net. The attribute line's problem is upstream: even if it reached this seed, `InputUnitPrice` is already 0 — see #2.

2. **`SyncInputUnitPricefromNet`** (parent `SyncInputUnitPriceforDiscountBase`, seq13) does `InputUnitPrice = NetUnitPrice`. Because the gated-out ABA line has `NetUnitPrice = 0` at seq13, this **copies 0 into `InputUnitPrice`**. So the `OneTimeNetSeed` fallback `IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice)` degenerates to `IF(0>0, 0, 0) = 0`. Net stays 0, then the FX step multiplies 0 → 0.

The closest analogs (verbatim), which the fallback should mirror in shape:
- **`OneTimeNetSeed`** (115024): `IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )` — FormulaBasedPricing, output `NetUnitPrice`.
- **`ResetNettoPrePartnerBase`** (label "Reset Net to Pre-Partner Base", line 116086): `IF ( PartnerDiscountPercent > 0 , IF ( Has_Attribute_Adjustment__c = true , NetUnitPrice , ListPrice ) , NetUnitPrice )` — FormulaBasedPricing, output `NetUnitPrice`. **This is the exact sibling to mirror**: it already reads `Has_Attribute_Adjustment__c`, already falls back to `ListPrice`, is a top-level-ish FBM writing `NetUnitPrice`, and lives in the correct region (parent `StampContributorBasePreDiscount`, seq14).

## Part 4 — The fallback step to create

### Placement
Create a new top-level `ListGroup` container immediately **after the ABA containers and before every net-consuming step**. The safest slot is **top-level sequenceNumber 6-ish, right after `ListContainer7` (seq5) and before `ListContainer5` (seq6)** — i.e. renumber nothing structurally, just insert the container so it evaluates after ABA (4,5) and long before the FX step `CurrencyConversionNetUnitPrice` (seq39, line 113246) and before `SyncInputUnitPriceforDiscountBase` (seq13) so the corrected net also propagates into `InputUnitPrice`. In the canvas: drag the new group to sit directly under "List Container 7" (the seq-5 ABA group), above "List Container 5".

> If canvas resequencing of seq6 is fiddly, the acceptable alternative is to place it as a new step **inside `StampContributorBasePreDiscount` (seq14), at sequenceNumber 2 (immediately before `ResetNettoPrePartnerBase`)** — still after ABA(5), before SyncInput is NOT satisfied there (Sync is seq13 < 14), so prefer the seq6 placement to also fix InputUnitPrice. Seq6 is the recommendation.

### Step type / action
- **Container:** `stepType = ListGroup` (new), name `ABACurrencyNetFallback`, top-level, sequenceNumber 6 (push existing 6+ down by one via canvas).
- **Guard child:** `stepType = AdvancedListFilter`, name `ABACurrencyNetFallbackFilter`, seq1.
- **Seed child:** `stepType = BusinessKnowledgeModel`, `actionType = FormulaBasedPricing`, name `ABACurrencyNetFallbackSeed`, seq2 — mirroring `ResetNettoPrePartnerBase` / `OneTimeNetSeed` exactly.

### Guard (AdvancedListFilter — `ABACurrencyNetFallbackFilter`)
Fire ONLY for the gated-out attribute population that has no net. Condition logic: `1 AND 2 AND 3 AND (4 OR 5)`:
1. `Has_Attribute_Adjustment__c` `Equals` `true`  — attribute line only (matches the ABA population; same field `ResetNettoPrePartnerBase` keys on).
2. `CurrencyIsoCode` `NotEquals` `'USD'`  — only the currency the USD gate excludes; USD ABA lines are untouched.
3. `ItemPricingSource` `NotEquals` `'LastTransaction'`  — mirror every sibling filter (renewals/last-txn priced elsewhere).
4. `NetUnitPrice` `Equals` `0`
5. `NetUnitPrice` `IsNull`

This is a strict subset of "attribute + non-USD + net-not-yet-set", so it cannot perturb USD ABA lines (blocked by #2, stay 1575) nor normal non-ABA lines (blocked by #1).

### Seed formula (FormulaBasedPricing — `ABACurrencyNetFallbackSeed`, output `NetUnitPrice`)
```
IF ( Has_Attribute_Adjustment__c = true , IF ( NetUnitPrice > 0 , NetUnitPrice , ListPrice ) , NetUnitPrice )
```
This mirrors `ResetNettoPrePartnerBase`'s inner shape (`IF(Has_Attribute_Adjustment__c=true, NetUnitPrice, ListPrice)`) but flips to seed from the currency-matched `ListPrice` (EUR 2943.99, already loaded by `PriceBookEntries` seq2) only when the ABA step left net at/below 0. Because the guard already filters to the exact population, the formula is belt-and-suspenders and provably identity for everything else.

Output binding (verbatim mirror of `ResetNettoPrePartnerBase` / `OneTimeNetSeed`):
```
<name>formula-section-0-output</name> <output>true</output> <value>NetUnitPrice</value>
<name>Output Variable</name>          <output>true</output> <value>NetUnitPrice</value>
```

### Currency token
Use **`CurrencyIsoCode`** in the *guard* (it is a real filterable field — it is the input parameter the PBE step already reads, line 115466-115469, and `AdvancedListFilter` `sourceFieldName` operates on line fields). Do **NOT** use `STICurrencyIsoCode` in the guard.

However, if you ever branch on currency inside a *FormulaBasedPricing body* here, you must use **`STICurrencyIsoCode`** — evidence: every currency-branching formula in the V21 block (lines 113198 FX net-unit, plus 112xxx net-total/line-amount/base-price FX, relative 2280/2344/2408/2472) uses `STICurrencyIsoCode`; bare `CurrencyIsoCode` never appears inside a formula body, only as a lookup input param and a variable-name node. The recommended seed formula above deliberately avoids any currency branch (it keys on `Has_Attribute_Adjustment__c` + `ListPrice`), so it sidesteps the token ambiguity entirely — this is the safer design.

## Part 5 — Expected results on the 3 evidence QLIs (gate + fallback)

| QLI | Currency | Has_Attribute_Adjustment__c | Before (gate-only) | After gate + fallback |
|---|---|---|---|---|
| `0QLWC000003kmG14AI` | EUR | true (falls out of ABA) | Net 0 / wrong USD 1575 override | Guard fires → `NetUnitPrice = ListPrice = EUR PBE 2943.99`; then FX seq39 (×1.0 if display already in EUR, or ×0.9346 only if base was USD — see risk) |
| `0QLWC000003kmG24AI` (EUR combo) | EUR | true | Net = 0 | Guard fires → seeded from currency-matched EUR `ListPrice` (no longer $0) |
| `0QLWC000003l1tO4AQ` (USD control) | USD | true | 1575 (correct) | Guard blocked by `CurrencyIsoCode != 'USD'` → **untouched, stays 1575** |

## Verbatim analog it mirrors

`ResetNettoPrePartnerBase` (line 116086), which already reads `Has_Attribute_Adjustment__c` and falls back to `ListPrice`:
```
IF ( PartnerDiscountPercent > 0 , IF ( Has_Attribute_Adjustment__c = true , NetUnitPrice , ListPrice ) , NetUnitPrice )
```
and `OneTimeNetSeed` (line 115024) for the `IF(NetUnitPrice>0, NetUnitPrice, <fallback>)` shape:
```
IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )
```

## Residual risks

1. **FX double-application (the G-01 / J-10 family risk).** `ListPrice` from `PriceBookEntries` is the *currency-native* EUR PBE value (2943.99). The FX step `CurrencyConversionNetUnitPrice` (seq39) multiplies `NetUnitPrice × EUR-factor 0.9346`. If the intended final EUR net is 2943.99, seeding native EUR ListPrice then letting FX multiply would **double-convert to ~2751**. This is the same double-FX trap flagged in the G-01/J-10 memory. **Before deploying, trace whether the EUR PBE stores native EUR (2943.99) or a USD-base value.** If native-EUR, the fallback population must be **excluded from the seq39 FX multiply** (add `Has_Attribute_Adjustment__c=true AND CurrencyIsoCode!='USD' AND fallback-fired` to the FX step's skip condition, or seed a marker field), OR seed from a USD-base ListPrice and let FX convert. The evidence target "must land on EUR PBE 2943.99, not USD 1575" strongly implies **native-EUR PBE → exclude from FX**. Verify the seq39 filter and the PBE UnitPrice provenance before finalizing.

2. **`InputUnitPrice` propagation.** Placing the fallback at seq6 (before Sync at seq13) means the corrected net flows into `InputUnitPrice` naturally. If you instead place it inside `StampContributorBasePreDiscount` (seq14 > 13), `InputUnitPrice` stays 0 and any later `IF(NetUnitPrice>0,...,InputUnitPrice)` seed could still zero it — prefer seq6.

3. **`ListPrice` null for true derived-pricing attribute lines.** If some ABA lines are genuinely `IsDerived=true` (PBEDP-derived, no direct PBE), `ListPrice` may be null and the fallback seeds 0. Guard mitigates by only firing on non-USD attribute lines, but confirm G14/G24 resolve a non-null EUR PBE (they should, per the 2943.99 evidence).

4. **Partner interaction.** `ResetNettoPrePartnerBase` runs at seq14 and re-reads `ListPrice`/`NetUnitPrice`; because the fallback at seq6 now supplies a real EUR net, the downstream partner-discount math (`ResolvePartnerDiscountPercent` seq15, `PartnerNetPricePosthook`) will apply to the correct EUR base rather than 0 — desired, but re-verify a partner+EUR+ABA combo line in Round 2 to confirm no double-discount.

5. **Canvas resequencing.** Inserting at top-level seq6 pushes 6→7, 7→8, etc. Per the "Pricing proc V21 in-place only" / "ESD MDAPI does not reach runtime — edit in canvas" memory, do this **in the RLM canvas on V21 in place, activate from Versions**, and re-verify all three QLIs plus a USD ABA regression after activation.

Source file: `/Users/liamjeong/Documents/Code/Fortra/Data/pricing-v21-validation/round2/live_retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (V21 block lines 110855-117766; key steps: AttributeBasedPrice 111795, AttributeDiscountEntries 111965, AttributePricingFilter 112004, AttributePricingFilter8 112038, PriceBookEntries 115580, OneTimeNetSeed 115024, ResetNettoPrePartnerBase 116086, StampBaseFilter 116558, CurrencyConversionNetUnitPrice 113246).