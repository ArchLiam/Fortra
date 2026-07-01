# SC-3473 — Evidence Index

All artifacts produced by the read-only deep-research workflow (26 agents). Organized by mission. No DML was performed against FortraUAT.


## `evidence/research-web/`  (3 files)

_Mission A — native RLM 'Delete Group' mechanism + web/KI research (RLM Dev Guide v67 PDF+text, Applikontech sibling-error notes)_

- `research-web/MISSION_A_NOTES.md` (4,699 B)
- `research-web/rlm_dev_guide.txt` (4,143,921 B)
- … plus 1 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/mission_B/`  (50 files)

_Mission B — custom Apex pricing-hook audit (live-retrieved hooks; active procedure V16 steps; RTEL/describe queries)_

- … plus 50 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/missionC/`  (27 files)

_Mission C — trigger + flow audit on QLI/QLG/Quote delete & reprice path (live triggers/handlers, flows, AUTOMATION_MAP.md)_

- `missionC/AUTOMATION_MAP.md` (5,382 B)
- … plus 26 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/missionD/`  (45 files)

_Mission D — failing-quote forensics (PBE/PSMO/attribute catalog completeness; retrieved metadata)_

- … plus 45 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/missionE/`  (26 files)

_Mission E — differentiator vs other grouped quotes (hardware-group / SM-mix / survivor-reprice comparison sets)_

- `missionE/differentiator_summary.json` (939 B)
- … plus 25 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/prior-art/`  (4 files)

_Mission F — prior-art + ApexLog forensics (reporter has 0 ApexLogs in retention window; error not logged to Apex)_

- … plus 4 raw query/metadata artifacts (`.json`, retrieved source)

## `evidence/verify/`  (169 files)

_Adversarial verification — 3 lenses (data-forensics / native-semantics / differential) per hypothesis H1–H6, with raw SOQL JSON_

- `verify/H1_differential_findings.md` (2,452 B)
- `verify/H1_native_semantics_findings.md` (3,744 B)
- `verify/H2_differential_summary.txt` (3,741 B)
- `verify/H2_findings_summary.json` (2,193 B)
- `verify/H2_native_semantics_findings.md` (2,114 B)
- `verify/H3_REFUTED_summary.json` (1,403 B)
- `verify/H3_findings.md` (2,553 B)
- `verify/H4/DIFFERENTIAL_LENS_summary.md` (2,720 B)
- `verify/H4/H4_REFUTED_summary.md` (3,965 B)
- `verify/H4/av_err.txt` (74 B)
- `verify/H4/err.txt` (282 B)
- `verify/H4/err2.txt` (74 B)
- `verify/H4/err3.txt` (74 B)
- `verify/H4/one_group_quote_ids.txt` (879 B)
- `verify/H5-differential/FINDINGS.json` (1,985 B)
- `verify/H5/H5_REFUTED_summary.json` (2,345 B)
- `verify/H5_REFUTATION.md` (4,056 B)
- `verify/H6/H6_native_robustness_findings.md` (6,160 B)
- `verify/H6_differential_findings.md` (5,215 B)
- `verify/REFUTATION_SUMMARY.md` (1,762 B)
- `verify/context_tags.txt` (1,442 B)
- `verify/nodes_custom.txt` (51 B)
- `verify/oli_all_fields.txt` (1,888 B)
- `verify/other_node_integrity.txt` (159 B)
- `verify/per_user_attr_population.txt` (1,428 B)
- … plus 137 raw query/metadata artifacts (`.json`, retrieved source)

## Key artifacts (quick reference)

- `evidence/research-web/rlm_dev_guide.txt` — RLM Dev Guide v67 extracted text — Place Sales Transaction 'Delete Group' sample, pricingPref:Force, commit-header-first/no-rollback
- `evidence/research-web/MISSION_A_NOTES.md` — Web research notes incl. the documented native sibling `DefaultContextRuntimeEntityAttribute.getTags()` NPE
- `evidence/prior-art/apexlog_reporter_dawn_krauss.json` — Proof the native error does not log to Apex (0 logs for reporter in window)
- `evidence/verify/H1_native_semantics_findings.md` — Active procedure = V16; only group-keyed aggregate step is isNotNull-guarded
- `evidence/verify/H2_findings_summary.json` — Active context = SalesTransactionContextExt_v2 V23; no static mapping gap for survivors
- `evidence/verify/H6` — Live CalculationStatus=SaveFailedOrIncomplete — robustness-gap signature
- `evidence/missionE/differentiator_summary.json` — Confounded discriminator cluster: HW-type + net≫list markup + OneTime/TermDefined mix + survivor-reprice
