# SC-3393 — Active Procedure & Gate Inventory (LIVE FortraUAT, 2026-06-11)

## ACTIVE VERSION (verified by metadata retrieve, NOT memory)
Retrieved ALL ExpressionSetDefinitionVersion members via wildcard manifest into
`Data/sc3393/evidence/proc_live/unpackaged/expressionSetVersion/`.
Only ONE version of Rev_Mgmt_Default_Pricing_Procedure has `<status>Active</status>`:
- **V12 (versionNumber 12) = ACTIVE.** All others (V1, V2, V3-V11) = Inactive.
- Memory ("active V12") is CORRECT. File: `..._Rev_Mgmt_Default_Pricing_V120.expressionSetVersion`.

## RegionalNetReconcile ListGroup — top-level sequenceNumber 33, stepType=ListGroup
ListGroup itself has NO advancedCondition. RegionalNetReconcileGate is its entry filter.
5 children (live V12 — note evidence/00_ground_truth.md OMITTED RegionalInputUnitPrice):

| seq | name | stepType | READS | WRITES | condition |
|-----|------|----------|-------|--------|-----------|
| 1 | RegionalNetReconcileGate | AdvancedListFilter | AllowRegionalPricing__c, **RegionalNetUnitPrice__c** | (filter, no write) | `1 AND 2`: c1 AllowRegionalPricing__c **Equals true**; c2 **RegionalNetUnitPrice__c GreaterThan 0** |
| 2 | RegionalNetUnitPrice | BKM (FormulaBasedPricing) | RegionalNetUnitPrice__c, NetUnitPrice | NetUnitPrice | `IF(RegionalNetUnitPrice__c < NetUnitPrice, RegionalNetUnitPrice__c, NetUnitPrice)` |
| 3 | RegionalInputUnitPrice | BKM (FormulaBasedPricing) | NetUnitPrice | InputUnitPrice | NetUnitPrice (Get) |
| 4 | RegionalNetTotal | BKM (FormulaBasedPricing) `resultIncluded=true` | NetUnitPrice, LineItemQuantity | ItemNetTotalPrice | NetUnitPrice * LineItemQuantity |
| 5 | RegionalListTotal | BKM (FormulaBasedPricing) | NetUnitPrice, LineItemQuantity | TotalLineAmount | NetUnitPrice * LineItemQuantity |

Group children run only when the gate passes (AllowRegionalPricing__c=true AND RegionalNetUnitPrice__c>0).

## Gate condition UNCHANGED V10 = V11 = V12
Identical `1 AND 2` / Equals true / GreaterThan 0. NOT modified today (refutes "gate edited today").

## "Recently introduced" CLAIM — VALIDATED
RegionalNetReconcile group is ABSENT from V1-V9, FIRST appears in **V10** (2026-06-10), persists V11/V12.
Step counts: V9=103 steps, V10=112 (+9 = the new group), V12=118.
V9 was the last regional version WITHOUT the reconcile gate.

## Every reference to the three regional resources in ACTIVE V12
- `RegionalNetUnitPrice__c` — 4 refs, ALL inside RegionalNetReconcile group:
  - gate crit2 (READ, comparison)  — line 4481
  - RegionalNetUnitPrice formula (READ) — line 4570
  - RegionalServicesPrice27 assignment **writes RegionalNetUnitPrice__c -> InputUnitPrice** (line 4657/4678) — this is in the OLDER ListContainer4 group (top-level **seq 12**), gated by `AllowRegionalPricing__c=true` ONLY (conditionLogic `1`). PRE-DATES V10 (present in V9).
- `AllowRegionalPricing__c` — 2 refs: gate crit1 (line 4474) and RegionalServicesPrice filter (line 4633, seq12 group).
- `PrehookRSNetUnitPrice__c` — **ZERO refs.** The procedure never reads it.

## Does the gate REQUIRE RegionalNetUnitPrice__c to have a value when AllowRegionalPricing__c=true? — YES
- Gate is `1 AND 2`. When crit1 (AllowRegionalPricing__c=true) is satisfied, the BRF engine MUST simulate
  crit2 (RegionalNetUnitPrice__c GreaterThan 0). A value comparison requires the resource to have a value.
- On a US line: prehook is a NO-OP (US multiplier 1.0, writes nothing), QLI Regional_NetUnit_Price__c has NO
  default => NULL => context attr RegionalNetUnitPrice__c has no corresponding value => engine cannot simulate
  the GreaterThan => **SF-BRF-00004 / SF-Pricing-00006 "RegionalNetReconcileGate#1"**. Matches the reported error.
- Non-services lines (AllowRegionalPricing__c=false) fail crit1 => never reach crit2 => no error. Explains why
  only the 5 Services products fail.

## Convention violation — the gate is the ONLY value-comparison on a nullable resource without a null guard
Every OTHER gate in V12 that touches a nullable field guards it with IsNull/IsNotNull
(e.g. COLA_Uplift_Percent__c IsNotNull, DerivedPricingAttribute IsNotNull, IsContracted IsNull,
PricingDate IsNull, itemTransientEndDate IsNull/IsNotNull, InputUnitPrice IsNull, ItemSalesTransactionAction IsNull).
RegionalNetReconcileGate is the SOLE gate doing a `GreaterThan` value comparison on a nullable `__c` resource
with NO preceding IsNotNull guard. There is NO IsNull/IsNotNull anywhere inside the RegionalNetReconcile group.
=> Structurally defective by the procedure's own established convention; consistent with H1.

Files: proc_live retrieve at Data/sc3393/evidence/proc_live/ ; all 11 prior versions also retrieved there.
