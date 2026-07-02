# SC-3350 — Live/Packaging & force-app Drift (prod-promotion readiness)

**Stream:** Live/Packaging & force-app drift
**Date:** 2026-06-10 (research after Marc DeBrey's later-today re-edits)
**Org:** FortraUAT (read-only). **Branch:** uat. **force-app root:** `/Users/liamjeong/Documents/Code/Fortra/force-app`
**Grounding brief:** `Data/sc3354/SC-3354_Research_Brief.md` (08:13 UTC) — Section 6 "Packaging / prod-promotion". Treated as possibly stale; every claim below re-verified live.

## TL;DR (headline)
The COLA feature remains almost entirely **live-only**. Deploying the current `force-app` would **regress prod**: it carries the COLA fields but ships a `COLA_Source__c` restricted value set that is **missing `MyCAP Default`**, and it carries a `DocuSign_API_Access` permission set that references `OrderItem.COLA_Uplift_Percent__c` while no OrderItem object/field exists in source. None of the 16 COLA Apex classes, neither CMDT type, neither CMDT record set, the COLA_Admin perm set, the two ExplainabilityMsgTemplates, the Contract COLA fields, the OrderItem COLA fields, nor the two outyear QLI fields are in source. **No material change vs the 08:13 brief's Section 6** — Marc's 14:00Z–16:58Z re-edits touched class *bodies* only, not the packaging surface, and did NOT back-fill source control.

---

## A. Apex artifacts — force-app vs LIVE

**Result: 0 of 16 COLA Apex classes are in force-app. All 16 are LIVE-ONLY.**

`force-app/main/default/classes/` contains only 12 `.cls` files, none COLA/Uplift-related (verified: `find force-app -iname "*Uplift*.cls"` → none; `grep -rln -i COLA force-app/main/default/classes/` → no hits).

LIVE classes (Tooling `ApexClass` query, with current LastModifiedDate confirming Marc's later edits):

| Class | LIVE LastModifiedDate | LIVE LastModifiedBy | In force-app? |
|---|---|---|---|
| AssetContractQueryHelper | 2026-06-10T14:00:37Z | Marc DeBrey | NO |
| COLAUpliftHandler | 2026-06-10T16:29:57Z | Marc DeBrey | NO |
| COLAUpliftPrehook | 2026-06-10T**16:58:15**Z | Marc DeBrey | NO |
| COLAUpliftTest | 2026-06-10T**16:58:15**Z | Marc DeBrey | NO |
| QLDescriptionGeneratorPrehook | 2026-06-10T14:41:27Z | Marc DeBrey | NO |
| IUpliftRatesSelector | 2025-12-18 | Vincent Vong | NO |
| IUpliftRatesService | 2025-12-18 | Vincent Vong | NO |
| UpliftRateMatcherStrategy | 2025-12-18 | Vincent Vong | NO |
| UpliftRateMatcherStrategyTest | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesController | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesControllerTest | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesSelector | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesSelectorTest | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesService | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesServiceImpl | 2025-12-18 | Vincent Vong | NO |
| UpliftRatesServiceTest | 2025-12-18 | Vincent Vong | NO |

**DELTA vs brief:** brief listed these 16 as not-in-force-app — still true. Brief stated the prehook+test were re-edited "16:51Z"; LIVE shows **16:58:15Z** for both — even the task prompt's timestamp is slightly stale. The UpliftRates* service layer (10 classes, Vincent Vong) was NOT touched by Marc and is unrelated to the renewal defects, but is still entirely out of source.

**No `QuoteLineItemTrigger` in force-app** (`find force-app -iname QuoteLineItemTrigger*` → none). The trigger entry-point that calls COLAUpliftHandler is also live-only.

---

## B. The restricted-picklist trap — RE-VERIFIED, STILL TRUE (now precisely characterized)

**force-app `COLA_Source__c`** (`force-app/main/default/objects/QuoteLineItem/fields/COLA_Source__c.field-meta.xml`):
- `<restricted>true</restricted>` (line 11)
- Value set = exactly 3 values: `CMDT Lookup` (default), `Contract Override`, `Line Override` (lines 14–28).
- **MISSING: `MyCAP Default`.**

**LIVE `COLA_Source__c`** (Tooling `CustomField.Metadata`, EntityDefinitionId='QuoteLineItem', DeveloperName='COLA_Source'):
- `restricted: True`
- Active values = **4**: `CMDT Lookup` (default), `Contract Override`, `Line Override`, **`MyCAP Default`**.

**CURRENT live handler writes `MyCAP Default`** — re-confirmed against the body retrieved live AFTER the 16:29:57Z edit (`Data/sc3350/research/live_today/COLAUpliftHandler.cls`):
- line 200: `qli.COLA_Source__c = 'MyCAP Default';`
- line 303: `String colaSource = 'CMDT Lookup';` (default)
- plus `'Contract Override'` (310) and `'Line Override'` (102/196/364).
So the four runtime-written values exactly match the live 4-value picklist.

**Live DATA holds the missing value** (`SELECT COLA_Source__c, COUNT(Id) FROM QuoteLineItem GROUP BY COLA_Source__c`):
- `CMDT Lookup` = 1,221,983
- `Line Override` = 7
- `Contract Override` = 6
- **`MyCAP Default` = 7**

**Conclusion:** deploying force-app's `COLA_Source__c` field-meta would attempt to deactivate/remove `MyCAP Default` from a **restricted** picklist that the live handler writes and that 7 live records hold → `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` (or a value-removal-with-data error). **The trap survived all of Marc's today-edits.** Confidence: HIGH (field-meta read + live picklist metadata + live handler line cite + live data counts).

**Fix prerequisite for any source-control alignment:** add `MyCAP Default` to the force-app value set before deploying this field.

---

## C. Reverse drift — DocuSign_API_Access PS references an absent OrderItem field — RE-VERIFIED, STILL TRUE

`force-app/main/default/permissionsets/DocuSign_API_Access.permissionset-meta.xml:9`:
```xml
<field>OrderItem.COLA_Uplift_Percent__c</field>
```
- This is the ONLY permission set in force-app referencing any COLA field (`grep -rl -i COLA force-app/main/default/permissionsets/` → only DocuSign_API_Access).
- **No OrderItem object dir exists in force-app** (`ls force-app/main/default/objects/OrderItem` → absent). Therefore `OrderItem.COLA_Uplift_Percent__c` is absent from source.
- LIVE OrderItem DOES have the field (Tooling FieldDefinition): `COLA_Uplift_Percent__c Number(16,2)`.
- A standalone source-only deploy of this PS would fail (field not found). Confidence: HIGH.

---

## D. Field drift — QuoteLineItem

LIVE QLI COLA/Uplift fields = **16** (Tooling FieldDefinition). force-app QLI COLA/Uplift fields = **14**.

**LIVE-ONLY (absent from force-app) — exactly the two the task flagged:**
- `COLA_Outyear_Uplift_Percent__c` — ABSENT in force-app, PRESENT live.
- `Final_Year_COLA_Calculated_Price__c` — ABSENT in force-app, PRESENT live. (This is the inert outyear-compounding display formula, brief §3/B3/B4.)

**Present in BOTH (14):** COLACalculatedPrice__c, COLAUpliftPercent__c, COLA_Applied_Date__c, COLA_Modified_By__c, COLA_Modified_Date__c, COLA_Override_Reason__c, COLA_Solution_Category__c, COLA_Source__c, COLA_Uplift2__c, COLA_Uplift_Percent__c, Default_COLA_Uplift_Percent__c, Is_COLA_Overridden__c, Pre_COLA_Price__c, UnitPriceUplift.

Confidence: HIGH (live FieldDefinition vs `ls` of the field dir).

---

## E. Field drift — Contract object (entire object dir absent from force-app)

- `force-app/main/default/objects/Contract/` does NOT exist.
- LIVE Contract COLA fields (FieldDefinition): `COLA_Override_Percent__c`, `COLA_Override_Persist_Until__c` — both LIVE-ONLY.
- These are read by AssetContractQueryHelper / the contract-override path. Confidence: HIGH.

---

## F. Field drift — OrderItem object (entire object dir absent from force-app)

- `force-app/main/default/objects/OrderItem/` does NOT exist.
- LIVE OrderItem COLA-named fields (FieldDefinition): `COLA_Uplift_Percent__c Number(16,2)`, `COLACalculatedPrice__c Currency(14,2)` — both LIVE-ONLY.
- Broader Uplift match also returns `UnitPriceUplift`, `Uplift_Percent__c` (generic, likely non-COLA).
- **DELTA vs brief:** brief said "5 OrderItem COLA fields." Live shows only **2 COLA-named** OrderItem fields (4 if you include the two generic `*Uplift*` fields). The brief's "5" is an **overcount**; the real, packaging-relevant gap is the DocuSign PS pointing at `COLA_Uplift_Percent__c` (Section C). Confidence: HIGH.

---

## G. CMDT — types and records (all live-only)

- **Type defs** exist live (EntityDefinition): `COLA_Uplift_Rules__mdt`, `MyCAP_Rules__mdt`. **Absent from force-app** (`find force-app -path "*objects*" -iname "*COLA_Uplift_Rules*"` → none; `*MyCAP*` matches only Quote fields Mycap__c/MYCAP_Approval__c, NOT the CMDT type).
- **No `customMetadata/` records** for COLA/MyCAP in force-app (`find force-app -path "*customMetadata*"` → none).
- LIVE record counts: `COLA_Uplift_Rules__mdt` = **22**; `MyCAP_Rules__mdt` = **1**. (Matches brief's 22+1.)
- Confidence: HIGH.

---

## H. Permission set + Explainability templates (live-only)

- `COLA_Admin` permission set: LIVE (PermissionSet Name='COLA_Admin', Label 'COLA Admin'). **Absent from force-app** (`find force-app -iname "*COLA_Admin*"` → none).
- `ExplainabilityMsgTemplate`: LIVE `COLAUpliftPass` ("COLA Uplift Applied"), `COLAUpliftFail` ("COLA Uplift Not Applied"). **Absent from force-app** (`find force-app -iname "*COLAUpliftPass*"` etc → none; no explainabilityMsgTemplate dir).
- Confidence: HIGH.

---

## Deltas vs the 08:13 brief (Section 6)
1. Brief's packaging gap list is **still accurate** in substance — nothing was back-filled into force-app despite Marc's 14:00Z–16:58Z class edits. The edits were body-only; the source-control surface is unchanged.
2. Restricted-picklist trap **still present and now data-confirmed**: force-app missing `MyCAP Default`; live picklist has it as the 4th active value; 7 live QLI rows hold it; the post-16:29Z live handler still writes it (line 200).
3. Prehook+Test live LastModifiedDate is **16:58:15Z**, not "16:51Z" as the task prompt states — minor staleness even in the prompt.
4. Brief's "5 OrderItem COLA fields" is an **overcount**; live has 2 COLA-named OrderItem fields. The packaging-relevant item is the DocuSign PS reverse-drift, which is confirmed.
5. UpliftRates* (10 classes, Vincent Vong, Dec-2025) are untouched by today's work and likely out of SC-3350 scope, but remain out of source.

## Open questions (for Marc / German)
- Is force-app intended to become authoritative (back-fill all 16 classes + Contract/OrderItem object dirs + CMDT type+records + perm set + explainability templates from UAT) before any SC-3350 change ships? If so this is a large source-control reconciliation, separate from the two renewal defects.
- OK to add `MyCAP Default` to the restricted `COLA_Source__c` value set in force-app (required before that field can deploy without erroring)?
- Are `COLA_Outyear_Uplift_Percent__c` + `Final_Year_COLA_Calculated_Price__c` (the inert outyear pair) in scope for source control now, or do they wait on the multi-year wiring decision (brief §3)?
- Is the DocuSign_API_Access PS reverse-drift a pre-existing source-control bug to fix independently (add OrderItem.COLA_Uplift_Percent__c to source or remove the FLS line)?

## SOQL / commands used (evidence)
- `sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Name, LastModifiedDate, LastModifiedBy.Name, LengthWithoutComments FROM ApexClass WHERE Name IN (...16 classes...)"`
- `sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Body FROM ApexClass WHERE Name='COLAUpliftHandler'"` → saved `Data/sc3350/research/live_today/COLAUpliftHandler.cls` (25,087 chars)
- `... FROM EntityDefinition WHERE QualifiedApiName IN ('COLA_Uplift_Rules__mdt','MyCAP_Rules__mdt')`
- `SELECT COUNT() FROM COLA_Uplift_Rules__mdt` → 22; `... FROM MyCAP_Rules__mdt` → 1
- `... FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='QuoteLineItem' AND (... COLA/Uplift/Pre_COLA/Outyear/Final_Year ...)` → 16
- `... EntityDefinition.QualifiedApiName='Contract' AND QualifiedApiName LIKE '%COLA%'` → 2
- `... EntityDefinition.QualifiedApiName='OrderItem' AND QualifiedApiName LIKE '%COLA%'` → 2
- `... FROM PermissionSet WHERE Name='COLA_Admin'` → 1
- `... FROM ExplainabilityMsgTemplate WHERE DeveloperName LIKE '%COLA%'` → COLAUpliftPass, COLAUpliftFail
- `SELECT COLA_Source__c, COUNT(Id) FROM QuoteLineItem WHERE COLA_Source__c != null GROUP BY COLA_Source__c` → CMDT 1221983 / Line Override 7 / Contract Override 6 / MyCAP Default 7
- `... FROM CustomField WHERE EntityDefinitionId='QuoteLineItem' AND DeveloperName='COLA_Source'` (Metadata) → restricted:true, values [CMDT Lookup, Contract Override, Line Override, MyCAP Default]
- force-app: `find force-app -iname "*COLA*" ...`; `ls force-app/main/default/objects/QuoteLineItem/fields/`; `Read force-app/.../COLA_Source__c.field-meta.xml`; `Read force-app/.../DocuSign_API_Access.permissionset-meta.xml`
