# SC-3393 — H2 (stale/unsynced runtime context) ADVERSARIAL REFUTATION

H2 claim: the active runtime ContextDefinitionVersion of SalesTransactionContextExt_v2 is
stale/unsynced after the 2026-06-09/06-10 regional rework, so RegionalNetUnitPrice__c and/or
AllowRegionalPricing__c is ABSENT from the runtime context — a missing resource (same class as the
prior project_reprice_contextdef_error gack).

VERDICT: **H2 REFUTED** (high confidence). The regional attributes are present, hydrated, and
mapped in the LIVE runtime context metadata, AND the prior (pre-gate) V9 procedure already consumed
both attributes successfully — so they cannot be absent from the runtime bag.

## A. Live runtime metadata proves the attributes EXIST on the active version (not design-time XML)
Queried tooling runtime objects (ContextAttribute / ContextAttributeMapping / ContextNodeMapping),
which are what the engine hydrates — independent of the retrieved .contextDefinition XML.

Active context versions (both IsActive=true):
- SalesTransactionContextExt_v2  v23  11pWC000002TjF7YAK  (LastMod 2026-06-04)
- SalesTransactionContextExt     v34  11pWC000001DswTYAS  (LastMod 2026-06-05)

ContextAttribute rows on the ACTIVE _v2 v23, node SalesTransactionItem (11oWC00000RnKJKYA3):
- AllowRegionalPricing__c  boolean  inputoutput  11nWC0000D8nZGcYQM
- RegionalNetUnitPrice__c  currency inputoutput  11nWC0000D8nZH0YQM
(The old v34 SalesTransactionItem node ALSO has both — so either binding has them.)

ContextAttributeMapping hydrating them on the active _v2 v23 QuoteLineItem mapping
(ContextMapping 11jWC0000064MRWYA2 "QuoteEntitiesMapping", node-mapping 11bWC00000346zPYAQ, Object=QuoteLineItem):
- AllowRegionalPricing__c  <- ContextInputAttributeName=AllowRegionalPricing__c  11RWC000003o9c62AA
- RegionalNetUnitPrice__c  <- ContextInputAttributeName=RegionalNetUnitPrice__c  11RWC000003o9bq2AA
=> attribute is DECLARED + MAPPED + hydrated from a real QLI field. Present, not absent.

QLI source fields exist and return values on a fresh US line:
  Regional_NetUnit_Price__c = null ; Allow_Regional_Pricing__c = false
=> present-but-null, the H1 shape — NOT "no slot in the bag".

## B. Behavioral precedent KILLS H2: V9 (no gate) already consumed both attributes successfully
Active pricing procedure ExpressionSetDefinitionVersion: V12 ACTIVE (9QBWC0000000n0j4AA), confirmed.
The same attributes were referenced in the PRE-GATE V9 (9QBWC0000000me94AA), under which services lines
added cleanly (last success 2026-06-09T16:28, all predating the V10 gate deploy 2026-06-10T02:18):
- V9 step `RegionalServicesPrice` (AdvancedListFilter): crit `AllowRegionalPricing__c Equals true`.
- V9 step `RegionalServicesPrice27` (BKM): reads INPUT `RegionalNetUnitPrice__c`, writes `InputUnitPrice`.
If either attribute were ABSENT from the runtime context (H2), V9 would have thrown the identical
SF-BRF-00004 for every services line. It did not. => both attributes ARE present in the runtime bag.

## C. The ONLY material change V9->V12 touching these attributes is the new GreaterThan GATE
Step diff V9->V12 adds: RegionalNetReconcile, RegionalNetReconcileGate, RegionalNetUnitPrice,
RegionalInputUnitPrice, RegionalNetTotal, RegionalListTotal.
Live V12 gate (from ExpressionSetDefinitionVersion.Metadata): AdvancedListFilter, "1 AND 2":
  crit1 AllowRegionalPricing__c Equals true ; crit2 RegionalNetUnitPrice__c GreaterThan 0 (no null-guard).
V9 consumed RegionalNetUnitPrice__c in a BKM (null passes through harmlessly -> InputUnitPrice).
V10+ consumes it in an un-guarded GreaterThan comparison fired when crit1 is true.
=> the regression is the comparison semantics on a present-NULL value, not attribute absence. Supports H1.

## D. The ContextDefinitionSync "stale" signal is a RED HERRING (the one real pro-H2 data point)
ContextDefinitionSync latest rows: SalesTransactionContextExt_v2 last success 2026-05-31; the regional
runtime ContextAttribute/Mapping rows were created 2026-06-04 (AFTER that sync). At face value this looks
like "added after last sync" = H2. BUT the runtime rows the engine reads DO contain the attributes
(section A), and V9 already evaluated them at runtime (section B). So whatever ContextDefinitionSync
gates, it is NOT the presence of these resources in the evaluation bag. The 2026-05-31 date does not
make the attributes absent. (SynchronizationInformation = {"upgradeMode":"Sync","contextDefinitionViolations":[]}.)

## Decisive evidence that would have CONFIRMED H2 (and did NOT appear)
A FINEST/pricing trace showing the resource reported as MISSING (no slot) rather than null — OR a V9 that
referenced the attributes failing identically. Instead, V9 consumed them fine and the runtime rows exist.
The remaining 100%-certainty item is a FINEST log on an authorized 1-line repro showing
"RegionalNetUnitPrice__c = null" present at gate evaluation (DML — not run here). All read-only evidence
points to present-but-null (H1), refuting H2.
