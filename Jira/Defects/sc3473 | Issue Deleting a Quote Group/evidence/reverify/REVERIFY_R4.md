# SC-3473 R4 re-verification (2026-06-28, read-only, FortraUAT)

Target org: fortra--uat (liam.jeong.c@fortra.com.uat), API v67.0.

## Live-state re-confirmations (all VERIFIED this run)
- Quote 0Q0WC000002U2020AC: Status=Accepted, USD, **CalculationStatus=SaveFailedOrIncomplete** (UNCHANGED),
  LastModifiedDate 2026-06-26T16:25:03Z by 005a500001SfRd7AAF (German Wren), **IsSyncing=true**.
  (query: Quote by Id; file evidence/reverify/ — inline)
- Quote composition UNCHANGED, 4 lines (group NOT deleted -> op still fails):
  - Survivor SUSPIN 02122365 grp=null net=20000 list=20000 PTC=1
  - Survivor SUSPIN 02122366 grp=null net=20000 list=20000 PTC=1
  - Grouped AJS 04266918 grp=1C9WC00000097of0AA net=29060 list=2850 **PTC=0**
  - Grouped Abstract 04266919 grp=1C9WC00000097of0AA net=4356 list=46 **PTC=null**
  (file: evidence/reverify/qli_now.json) — note grouped lines carry anomalous PTC (0 / null) + ~10x net>>list.
- Context SalesTransactionContextExt_v2 (11OWC000002m21Z2AQ): active version **V23** (11pWC000002TjF7YAK). Single active. UNCHANGED.
- Sibling contexts: SalesTransactionContextExt v1 (11OWC0000012HsD2AU) V36 active; ProductDiscoveryContextExt (11OWC000001k8y52AA) V23 active.
- Pricing procedure Rev_Mgmt_Default_Pricing_Procedure (9QAWC0000003mg14AA): design version **V16 = Active** (9QBWC0000000niH4AQ);
  V17-V20 exist but Inactive; all others Inactive. UNCHANGED. (file: evidence/reverify/proc_versions.json)
- ExpressionSetDefinitions present: Rev_Mgmt_Default_Pricing_Procedure, Product_Discovery_Pricing_Procedure,
  Salesforce_Pricing_Discovery_Procedure, Salesforce_Default_Pricing_Discovery_Procedure(_v2). (file: evidence/reverify/esd_list.json)

## External corroboration (this run)
- RLM Dev Guide = Revenue Management Developer Guide **v67.0, Summer '26**.
- applikontech RLM guide remediation for the getTags() Map.get-null sibling = pure CONFIG:
  accurate Context Definition Mappings; Generate All Mappings; ensure a DEFAULT mapping; link new context
  version to BOTH Product Discovery AND Sales Transaction procedures; SYNC decision tables; mark attribute-based
  pricing for output; permissions. (WebSearch 2026-06-28)
- Salesforce help 000382175 confirms "Attempt to de-reference a null object" is the CPQ/Apex form — DISTINCT from
  this native JEP-358 java.util.Map.get form. Reinforces native-throw conclusion.

## Net verdict on prior RCA
All five prior live-state claims RE-CONFIRMED. No drift. The two NEW signals worth elevating:
1. IsSyncing=true — the quote is the synced quote of an OPEN opp; sync is active, not just historical.
2. The wedged CalculationStatus=SaveFailedOrIncomplete persists 2 days later and is itself a candidate lever
   (a prior failed calc may now block ANY save/reprice). This is testable read-only-ish via a reprice (DML).
