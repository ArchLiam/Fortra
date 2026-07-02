# SC-3393 — Evidence Index

Investigation 2026-06-11, READ-ONLY (SOQL + metadata retrieve only). Org: FortraUAT.

**Layout:** the lightweight analysis files, both research notes, and the active **V12** procedure XML are mirrored
**inside this dossier** under `evidence/` (so the README's `evidence/...` links resolve and the dossier is
self-contained). The full multi-version raw retrieves (all 11 ExpressionSetDefinitionVersions, fresh context def,
Apex/flows, raw Apex logs — ~21 MB) remain under `/Users/liamjeong/Documents/Code/Fortra/Data/sc3393/evidence/`
to avoid duplicating large binaries. Paths in the tables below are relative to `Data/sc3393/` unless the file also
exists in the dossier `evidence/` (the analysis `.md` files, `regionalnetreconcile_group_v12.xml`,
`research-notes/error_semantics{,_web}.md`, and `retrieve/Rev_Mgmt_Default_Pricing_V120.expressionSetVersion`).

---

## Key record IDs

| Entity | Id | Notes |
|--------|-----|-------|
| Failing quote | `0Q0WC0000037tXV0AY` | "Q-Wren - Test Services" #00781060, Draft, **0 lines**; OhioHealth, US, USD |
| Account | OhioHealth Corporation | BillingCountry/ShippingCountry = United States ⇒ prehook no-op |
| Pricebook | `01sWC0000022GHFYA2` | "Fortra Price Book" |
| Product — 24 X 7 X 365 Monitoring | `01tWC00000DD115YAD` | VM-DDL-NRSU-2X7X3M, Services, Allow_Regional_Pricing=true |
| Product — CSCO I & II Course | `01tWC00000DD17hYAD` | OS-COS-NRST-CIICS, Services, true (added OK pre-V10) |
| Product — Administering Automated Password Mgmt | `01tWC00000DD11VYAT` | IGA-AAS-NRST-ADMIAP, Training, true |
| Product — AIC Expert Services | `01tWC00000DD11xYAD` | RPA-AUT-RSP-AICEXP, Services, true |
| Product — Automate Expert Services | `01tWC00000DD148YAD` | RPA-AUT-RSP-AUEX, Services, true (added OK pre-V10) |
| Control product | `01tWC00000FBWonYAH` | "24 X 7 X 365 Monitoring (Technical)", Allow_Regional_Pricing=**false**, adds fine |
| Context definition | `11OWC000002m21Z2AQ` | `SalesTransactionContextExt_v2` (parent) |
| Active context version | `11pWC000002TjF7YAK` | `_v2` **V23**, IsActive=true, LastMod 2026-06-04 |
| ContextAttribute AllowRegionalPricing__c | `11nWC0000D8nZGcYQM` | SalesTransactionItem node, boolean, inputoutput |
| ContextAttribute RegionalNetUnitPrice__c | `11nWC0000D8nZH0YQM` | SalesTransactionItem node, currency, inputoutput |
| Active procedure version | `9QBWC0000000n0j4AA` | `Rev_Mgmt_Default_Pricing_Procedure` ESDV **V12**, ACTIVE |
| Pre-gate procedure version | `9QBWC0000000me94AA` | ESDV **V9** (last version without the gate) |
| Procedure versions definition | `9QAWC0000003mg14AA` | V9 active→2026-06-10T02:18; V10 created 02:18:14 (gate added); V12 active |

---

## Synthesis / analysis files (`evidence/`)

| File | Description |
|------|-------------|
| `00_ground_truth.md` | Inline scouting baseline: error, failing quote, 5 products + control, V12 gate logic, prehook behavior, context mappings, field defaults, primary hypothesis. |
| `active_proc_and_gate_inventory.md` | Confirms V12 active by metadata; full `RegionalNetReconcile` 5-child inventory (reads/writes/conditions); gate condition identical V10=V11=V12; "recently introduced" validated (V9=103→V10=112→V12=118 steps); convention-violation finding (sole un-null-guarded value comparison). |
| `RUNTIME_THREAD_FINDINGS.md` | Runtime/data thread: 0 Apex logs of the error (managed-engine), failing quote 0 lines, field defaults, existing-regional-line analysis, temporal smoking gun (last flag-true add 2026-06-09 18:55Z, zero after V10). |
| `H2_refutation_runtime_context.md` | Adversarial H2 refutation: live `ContextAttribute`/`ContextAttributeMapping`/`ContextNodeMapping` prove both attrs present+hydrated on active v23; V9 behavioral precedent (consumed both attrs successfully) kills H2; the 2026-05-31 sync-date red herring. |
| `regionalnetreconcile_group_v12.xml` | Extracted V12 XML for the `RegionalNetReconcile` group + the older `RegionalServicesPrice`/`RegionalServicesPrice27` steps. **The gate logic (lines 13–28) and the V9-precedent assignment (lines 171–243) live here.** |
| `research-notes/error_semantics.md` | Web/platform-docs research on SF-Pricing-00006 / SF-BRF-00004 semantics; argues null is a handled state and the error implies structural absence; the present-null-vs-absent fork; basis for refining H1 into the H1→H2 hybrid. Codes not publicly documented (medium confidence). |
| `research-notes/error_semantics_web.md` | Independent second web-research thread (Q1–Q6 + bottom line): leans "mapped-but-null/unvalued operand at the GreaterThan is the cause," do not rely on BRE short-circuit; converges with the other note on the same fix family. Includes the reconciliation paragraph. |

## Retrieved metadata (`evidence/`)

| Path | Description |
|------|-------------|
| `proc_live/` | Wildcard retrieve of **all** ExpressionSetDefinitionVersion members of the procedure; only `..._Rev_Mgmt_Default_Pricing_V120.expressionSetVersion` has `<status>Active</status>`. All 11 prior versions also present for diffing. |
| `proc_live/unpackaged/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V120.expressionSetVersion` | The **active V12** procedure XML. |
| `esdv_v12/v12_full.json` | Full V12 ExpressionSetDefinitionVersion (JSON) — step inventory for V12. |
| `esdv_v12/v9_full.json` | Full V9 (pre-gate) — diff baseline proving the group is new in V10. |
| `fresh_ctx/unpackaged/contextDefinitions/SalesTransactionContextExt_v2.contextDefinition` | **Fresh** live retrieve of the context def — confirms active version 23 and both regional attrs present (no source drift). |
| `apex/`, `apex2/` | Apex/class retrieves (prehook + related) supporting the US-no-op finding. |
| `flows/` | Flow retrieves checked for any writer of `Allow_Regional_Pricing__c`/`Regional_NetUnit_Price__c` (none found; flag set via Product2 mirror). |
| `logs/raw_07LWC*.log` | Today's downloaded Apex logs (Nir Kailash, succeeding "Renewal Quote" 0Q0WC0000037v1R0AQ). Confirm prehooks fire but contain **zero** occurrences of the SF-Pricing/SF-BRF error (managed-engine error, not Apex-logged). |

## Related source (outside `Data/sc3393/`)

| Path | Description |
|------|-------------|
| `Org Data/_src/classes/RegionalServicesPricingPrehook.cls` | Prehook v13.3 — lines 58–59 establish the **US no-op**; never writes `AllowRegionalPricing__c`; writes `RegionalNetUnitPrice__c` only for non-default-multiplier countries. |
| `Data/sc3393/retrieve/unpackaged/contextDefinitions/SalesTransactionContextExt_v2.contextDefinition` | Earlier full context-def retrieve (design-time mappings: lines ~6665–6672, 6789–6796 input mappings; node attr defs ~24450–24774). |
| `Data/sc3390/retrieve/unpackaged/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V120.expressionSetVersion` | Cross-ticket copy of the active V12 procedure (shared SC-3390 ground truth). |
