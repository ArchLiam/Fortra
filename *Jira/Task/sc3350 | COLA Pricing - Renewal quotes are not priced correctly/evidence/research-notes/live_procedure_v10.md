# SC-3350 — Live Pricing Procedure V10 COLA Wiring (CURRENT TRUTH)

**Date:** 2026-06-10 (research run, read-only). **Org:** FortraUAT.
**Stream:** Live/Pricing procedure V10 COLA wiring.
**Verdict:** The active pricing procedure is **V10**, unchanged since its 03:22Z republish. **Both COLA paths (A and B) are present exactly as the 08:13Z brief described.** `Final_Year_COLA_Calculated_Price__c` is referenced **0 times** (out-year still inert). Marc DeBrey's later-today edits were **Apex-only** and did NOT touch the procedure — so the procedure stream of the brief is **NOT stale**.

---

## 1. Active version = V10 (confirmed)

SOQL (tooling):
```
SELECT ExpressionSetDefinition.DeveloperName, VersionNumber, Status, LastModifiedDate
FROM ExpressionSetDefinitionVersion
WHERE ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' AND Status='Active'
```
Result: `Rev_Mgmt_Default_Pricing_Procedure | 10 | Active | 2026-06-10T03:22:00.000+0000`. (1 row.)

Full version ladder (ORDER BY VersionNumber DESC):
| Ver | Status | LastModifiedDate |
|---|---|---|
| **10** | **Active** | **2026-06-10T03:22:00Z** |
| 9 | Inactive | 2026-06-10T03:08:56Z |
| 8 | Inactive | 2026-06-10T02:18:12Z |
| 7..1 | Inactive | 2026-06-10T02:18:12Z |

V9 was deactivated 03:08:56Z; V10 activated/republished 03:22:00Z. Matches the prompt's "V10 republished 2026-06-10T03:22Z."

**Provenance (new fact, not in brief):**
```
SELECT Id, VersionNumber, Status, LastModifiedDate, LastModifiedBy.Name, CreatedBy.Name, CreatedDate
FROM ExpressionSetDefinitionVersion WHERE ...DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' AND VersionNumber=10
```
→ `9QBWC0000000mnp4AA | 10 | Active | LastModifiedBy=Liam Jeong | CreatedBy=Liam Jeong | Created 2026-06-10T02:18:14Z`.
**V10 was created AND republished by Liam Jeong, NOT Marc DeBrey.** Memory's "Marc republished V9" narrative does not apply to this V10.

---

## 2. Fresh metadata retrieve — byte-identical to brief artifact

Retrieved active procedure to:
`/Users/liamjeong/Documents/Code/Fortra/Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
(2,346,321 bytes, 52,499 lines.)

`diff` vs the brief's artifact (`Data/cola-renewal-review/live/expressionSetDefinition/...`, retrieved 07:49 local today) → **IDENTICAL** (byte-for-byte). The procedure has not changed since the 03:22Z republish.

Note: SF CLI warns the ExpressionSetDefinition metadata is **v66**; the org/SOAP API is v67. Retrieve succeeded; no truncation (line/byte counts match the prior good retrieve).

---

## 3. Path A — prehook-fed COLA on InputUnitPrice (PRESENT, unchanged)

Canonical block at lines 1408–1506 (repeated 10× across container variants).

**Filter element `COLAUpliftonRenewal`** (stepType `AdvancedListFilter`, label "COLA Uplift on Renewal", parentStep `ListContainer2`), conditionLogic `1 AND 2 AND 3 AND 4 AND 5 AND 6` (lines 1408–1445):
1. `ItemPricingSource` Equals `'LastTransaction'`  ← **NOT mentioned in the brief's gating summary**
2. `DerivedPricingAttribute` IsNotNull
3. `DerivedPricingAttribute` Equals `false`
4. `SalesTransactionActionType` IsNotNull
5. `SalesTransactionActionType` Equals `'Renew'`
6. `COLA_Uplift_Percent__c` IsNotNull

**Assignment element `COLAUpliftonRenewal10`** (stepType `BusinessKnowledgeModel`, actionType `AssignmentElement`, lines 1457–1507):
- input `section-0-input1` = Parameter `COLACalculatedPrice__c`
- output `section-0-output` = Parameter `InputUnitPrice`
- whereCondition maps `COLACalculatedPrice__c (Currency) → InputUnitPrice (Currency)`.

→ **Path A writes `COLACalculatedPrice__c → InputUnitPrice` for non-derived (`DerivedPricingAttribute=false`) renewal (`ActionType='Renew'`) lines that have a COLA % and pricing source `LastTransaction`.** Exactly the brief's Path A, **plus** the `ItemPricingSource='LastTransaction'` criterion the brief omitted.

Distinct Path-A element occurrences (grep `<name>COLAUpliftonRenewal*</name>`): filter `COLAUpliftonRenewal` ×10; assignments `COLAUpliftonRenewal10` ×4, `13` ×1, `16` ×2, `19` ×1, `21` ×2 = 10 assignment copies, each with `<value>COLACalculatedPrice__c</value>` → `InputUnitPrice` (10 `<value>COLACalculatedPrice__c</value>` total). The numbered suffixes are container-variant duplicates (the ExpressionSet compiles the same logic into multiple ListGroup contexts), not distinct logic.

---

## 4. Path B — self-derived net COLA formula on NetUnitPrice (PRESENT, unchanged)

Element `DerivedPricingRenewals` (stepType `BusinessKnowledgeModel`, actionType **`FormulaBasedPricing`**, label "Derived Pricing - Renewals", parentStep `ListContainer`), at lines 48603–48667 (and a second copy at 43137). Formula (line 48611 / 43089):

```
IF ( QuoteTypeText__c = 'Renewal' ,
     ( Base_Price__c - Prior_Partner_Discount__c - Prior_Discretionary_Discount__c ) * ( 1 + ( COLA_Uplift_Percent__c / 100 ) ) ,
     NetUnitPrice )
```
Output `formula-section-0-output` = Parameter **`NetUnitPrice`** (line 48653).

**Container gating** (`Copy1ofListContainer8` group seq 31 → AdvancedListFilter at lines 48352–48374), conditionLogic `1 AND 2 AND 3`:
1. `DerivedPricingAttribute` IsNotNull
2. `DerivedPricingAttribute` Equals `true`
3. `AttributeDefinitionCode` Equals `'MDT'`

→ **Path B applies `(Base_Price − Prior_Partner_Discount − Prior_Discretionary_Discount) × (1 + COLA%/100) → NetUnitPrice` for MDT-derived (`DerivedPricingAttribute=true`, `AttributeDefinitionCode='MDT'`) lines, with the formula self-re-checking `QuoteTypeText__c='Renewal'`.** Exactly the brief's Path B. Formula value appears **2×** (two container variants), no other formula variants.

---

## 5. Mutual exclusivity (unchanged)

Path A requires `DerivedPricingAttribute=false`; Path B requires `DerivedPricingAttribute=true`. They remain **mutually exclusive on `DerivedPricingAttribute`**, as the brief stated. Bases still differ: A uses `COLACalculatedPrice__c` (computed by the prehook/handler off raw `Asset.Price`, no discounts); B nets prior discounts. Inconsistency the brief flagged persists.

---

## 6. Out-year / Final-Year wiring (still INERT — 0 refs, confirmed)

`grep -c` against the live V10 XML:
| Token | Count | Meaning |
|---|---|---|
| `Final_Year_COLA_Calculated_Price__c` | **0** | out-year compounded price never fed to pricing (inert) — matches brief |
| `COLA_Outyear_Uplift_Percent__c` | 0 | out-year rate field not referenced |
| `MyCAP` | 0 | MyCAP out-year rate path not in procedure |
| `Pre_COLA_Price__c` | 0 | handler-only field, not in procedure |
| `COLA_Source__c` | 0 | handler-only field, not in procedure |

→ **B3 (out-year inert) re-confirmed against current V10.** The only COLA inputs the procedure consumes are `COLACalculatedPrice__c` (Path A), `Base_Price__c`/`Prior_Partner_Discount__c`/`Prior_Discretionary_Discount__c`/`COLA_Uplift_Percent__c`/`QuoteTypeText__c` (Path B), and the gating attrs `DerivedPricingAttribute`/`AttributeDefinitionCode`/`SalesTransactionActionType`/`ItemPricingSource`.

Incidental: `Source_List_Price__c` appears 2× (the Maintenance Derived Pricing element from the contextDef-gack memory) — unrelated to COLA.

---

## 7. Marc's later-today edits did NOT touch the procedure

```
SELECT Name, LastModifiedDate, LastModifiedBy.Name FROM ApexClass
WHERE Name IN ('COLAUpliftHandler','COLAUpliftPrehook','COLAUpliftTest','AssetContractQueryHelper','QLDescriptionGeneratorPrehook')
ORDER BY LastModifiedDate DESC
```
| Class | LastModifiedDate | By |
|---|---|---|
| COLAUpliftPrehook | 2026-06-10T16:58:15Z | Marc DeBrey |
| COLAUpliftTest | 2026-06-10T16:58:15Z | Marc DeBrey |
| COLAUpliftHandler | 2026-06-10T16:29:57Z | Marc DeBrey |
| QLDescriptionGeneratorPrehook | 2026-06-10T14:41:27Z | Marc DeBrey |
| AssetContractQueryHelper | 2026-06-10T14:00:37Z | Marc DeBrey |

All five edits are **Apex classes**, all by Marc, 14:00Z–16:58Z. The procedure (`ExpressionSetDefinitionVersion` V10) was last modified **03:22Z by Liam Jeong** and is byte-identical to the 07:49 artifact. **Therefore the procedure has NOT changed since the brief; Marc's churn is entirely in the Apex layer.** Any behavioral delta vs the brief lives in COLAUpliftPrehook/Handler/Test/AssetContractQueryHelper/QLDescriptionGeneratorPrehook — out of scope for this stream, flagged for the Apex stream.

**Caveat:** Path A only fires if the prehook/handler still populate `COLACalculatedPrice__c` and the trigger still syncs `COLA_Uplift_Percent__c` to the context. Those are Apex (Marc-edited today). The procedure WIRING is intact, but its INPUTS depend on Apex that changed 14:00Z–16:58Z. Confirm input population in the Apex stream before asserting end-to-end Path-A behavior.

---

## 8. Deltas vs the 08:13Z brief (this stream)

1. **No procedure change.** V10 retrieve is byte-identical to the brief's artifact; both COLA paths and the 0 Final_Year refs hold. The brief's section 4 ("Live pricing-procedure wiring") is **current, not stale**.
2. **Path A filter has an extra criterion the brief omitted:** `ItemPricingSource = 'LastTransaction'` (criterion #1 of 6). Brief summarized gating as "ActionType='Renew' AND DerivedPricingAttribute=false [AND COLA% not null]"; the live filter is stricter. Behaviorally narrows when Path A fires (line must be priced from last transaction).
3. **Waterfall position:** brief said "Path A waterfall seq 9 / Path B seq 7." Live: Path A's parent ListGroup `ListContainer2` has `sequenceNumber=6`; Path B's parent `Copy1ofListContainer8` has `sequenceNumber=31`. The brief's seq numbers don't match the ListGroup sequenceNumbers (likely a different intra-container counting). **Low-impact; structural gating is what governs, and that is confirmed identical.** Flag as a number to re-derive if exact waterfall order matters.
4. **V10 provenance correction:** V10 was created+republished by **Liam Jeong** (02:18Z create / 03:22Z modify), not Marc. Memory's "Marc republishes V9" pattern does not apply here.

---

## 9. Evidence index (file + line cites)

- Active version SOQL: section 1 above.
- Fresh retrieve: `/Users/liamjeong/Documents/Code/Fortra/Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
- Path A filter criteria: lines 1408–1445. Path A assignment: lines 1457–1507 (`COLACalculatedPrice__c`→`InputUnitPrice` at 1465/1493).
- Path B formula: lines 48604–48667 (formula 48611; output `NetUnitPrice` 48653). Second copy: 43089/43137.
- Path B container gating (MDT): lines 48352–48374.
- 0-ref greps: section 6.
- Apex edit timestamps: section 7 SOQL.
