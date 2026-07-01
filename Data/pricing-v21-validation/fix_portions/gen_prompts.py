#!/usr/bin/env python3
# Generate 3 self-contained tab prompts (PORTION_1/2/3) from authored.json + fix_portions/<id>.json pins.
import json, os
BASE = os.path.dirname(__file__)
VAL = os.path.dirname(BASE)
authored = {d['id']: d for d in json.load(open(f'{VAL}/v21_run3/authored.json'))['defects']}
pin = {}
for sid in ['K-01','F-12','G-01','F-09','G-02','I-03','E-04','J-06','A-07','G-08','J-09','J-10']:
    pin[sid] = json.load(open(f'{BASE}/{sid}.json'))

PORTIONS = {
 1: {'name': 'V21 PROCEDURE', 'file': 'PORTION_1_PROCEDURE.md',
     'ids': ['K-01','F-12','G-01','F-09','G-02','I-03','E-04'],
     'surface': 'In-place edits to the active V21 ExpressionSet (pricing procedure) metadata, batched into ONE deactivate -> deploy -> reactivate cycle. PLUS E-04 also needs a small data backfill (Non_Orig_* on 30 Partner_Pricing_Model rows).',
     'owns': 'You are the ONLY work-stream permitted to edit the V21 procedure. The other two tabs touch Apex / data records only and will NOT touch the proc.'},
 2: {'name': 'APEX + INDEPENDENT CONFIG', 'file': 'PORTION_2_APEX_CONFIG.md',
     'ids': ['J-06','A-07','G-08'],
     'surface': 'One Apex class edit + two independent data/config backfills. NONE of these touch the V21 procedure metadata.',
     'owns': 'Do NOT edit the V21 procedure (Portion 1 owns it). Your three items hit three different artifacts (an Apex class, ProductAttributeDefinition records, and CurrencyType admin) and do not collide with each other.'},
 3: {'name': 'DERIVED-PBE DATA', 'file': 'PORTION_3_DERIVED_PBE_DATA.md',
     'ids': ['J-09','J-10'],
     'surface': 'Two data backfills in the derived-PriceBookEntry space (PriceBookEntryDerivedPrice rows + PricebookEntry.IsDerived flags). No procedure edits, no Apex.',
     'owns': 'Do NOT edit the V21 procedure (Portion 1 owns it). Both your items operate on the derived-PBE config for overlapping products, so you own that space exclusively.'},
}

PREAMBLE = '''## Mission

You are fixing a specific portion of the defects found in the **2026-06-30 validation of FortraUAT Pricing Procedure V21** (`Rev_Mgmt_Default_Pricing_Procedure`). Implement the fixes for the defects listed below, verify each on real data, and stop. This is one of **three parallel work-streams**; stay strictly within your portion's artifacts so the three tabs never collide.

## Environment (do not deviate)

- **Org = `FortraUAT`** only — every command uses `-o FortraUAT` / `--target-org FortraUAT`. The `uat` alias is a DIFFERENT (5sInfusion) org; never use it.
- **Active procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **Version 21**, ACTIVE.
  - design `ExpressionSetDefinition` `9QAWC0000003mg14AA`
  - active version `ExpressionSetDefinitionVersion` **`9QBWC0000000oWH4AY`** (VersionNumber 21)
  - runtime `ExpressionSetVersion` `9QMWC00000025LN4AY`
  - pricing context `SalesTransactionContextExt_v2` (v23) / `OrderEntitiesMapping`
- **REST reprice API version = v67.0.**
- Standing test records: Account "Fortra, LLC - Test" `001WC00000XiZP4YAN`; live price book = **"Fortra Price Book"** (`01sWC0000022GHFYA2`, IsActive=true). "Standard Price Book" is INACTIVE — never use it.

## Hard rules (these have bitten us before)

1. **Validation context only became fix context just now — confirm before you change anything.** Retrieve LIVE before trusting local source; repo copies drift. Re-measure the defect on the live org first so you have a before/after.
2. **In-place V21 ONLY — never create a new version (no V22).** All procedure changes go into the existing ESDV `9QBWC0000000oWH4AY`.
3. **RLM canvas re-save CLOBBERS metadata deploys.** After any proc metadata deploy: FULLY CLOSE every open Pricing-Procedure canvas tab, open a FRESH tab, and **Activate from Setup -> Pricing Procedures -> Versions list** (a status flip), NEVER from inside a pre-deploy canvas editor. Re-retrieve the metadata IMMEDIATELY after activation to confirm it did not revert, before repricing.
4. **AdvancedListFilter criteria are referenced by POSITION 1..N, not sequenceNumber.** If you add/remove a criterion, renumber survivors contiguously and update `conditionLogic` to match (e.g. `1 AND 2 AND 3 AND 4 AND 5`). A dangling reference => runtime "Invalid criteria reference".
5. **Proc deploy mechanics:** retrieve/deploy with **api version 67** and `--metadata-dir` (MDAPI source format); the orphan `rca_diagnostic.cls-meta.xml` blocks source-format ops, so use MDAPI. Sequence: **deactivate V21 -> deploy -> reactivate from Versions list -> re-retrieve to confirm -> reprice to verify.**
6. **Order reprice BEFORE Activate** (never activate an order before its order-level reprice).
7. **This is a UAT fix exercise. Do NOT deploy anything to production.** Each fix is UAT-only until separately authorized.
8. **`ValidationResult` string fields are not usable in pricing formulas** ("unsupported field type") — if a fix needs a flag, use a numeric/boolean field or an AssignmentElement, not a formula on a string.

## What the validation found (so you trust the targets)

104 catalog scenarios were smoke-tested on real FortraUAT data via a 4-stage adversarial pipeline (executor -> verifier -> skeptical data-artifact audit -> tie-breaker). Outcome: **69 PASS / 13 FAIL / 22 BLOCKED**. Each defect below is a *confirmed* FAIL whose seed data passed preflight and whose intended V21 branch provably ran on valid inputs. Full evidence + per-scenario rows:
- Report: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.{html,md}` (exec-summary-first; defect cards).
- Per-defect rows: `Data/pricing-v21-validation/rows_run3/<id>.json` (live numbers + record IDs). Audit/tie-break detail: `audit_run3/`, `tiebreak_run3/`. Artifact pin for your defects: `fix_portions/<id>.json`.

**Already-excluded false positives — do NOT re-chase these:** D-09 (stale frozen FX field, not a live miscalc), I-02 (malformed off-by-one EndDate), J-05 (line on an Amend QuoteAction by design), K-02 & K-10 (catalog expected-value errors). **Out of scope for Fortra:** evergreen-catalog and contracted-pricing scenarios (no evergreen catalog, contracted pricing unsupported) — ignore any "blocked" items in those areas.

## Headless reprice + verify recipe (use for every verification)

```bash
# 1) body file (Quote example; use "Order" for orders). Force-reprice the record through live V21:
cat > /tmp/body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"Quote","method":"PATCH","id":"<RECORD_ID>"}}}]}}
JSON
# 2) place action (success = isSuccess:true, errorResponse:[]):
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" \
  --method POST -o FortraUAT --body "$(cat /tmp/body.json)"
# 3) read the result fields:
sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,Source_List_Price__c,Pre_Partner_Price__c,Base_Price__c,COLACalculatedPrice__c FROM QuoteLineItem WHERE QuoteId='<q>'"
```
A calc ERROR after your change is a regression to fix, not a pass. After fixing, also re-reprice **one or two known-good PASS controls** in the same area to confirm you did not regress them.
'''

def defect_block(sid):
    a = authored[sid]; p = pin[sid]
    arts = '\n'.join(f'  - **{x.get("type")}** — {x.get("identifier")}' for x in p.get('artifacts', []))
    lines = []
    lines.append(f'### {sid} — {a["title"]}  ·  {a["pri"]} · {a["type"]}-DEFECT' + (f' · ticket {a["ticket"]}' if a.get('ticket') and a['ticket'] != "—" else '') + (' · ⚠ NEW REGRESSION (from the 2026-06-30 05:56Z in-place edit)' if a.get('regression') else ''))
    lines.append('')
    lines.append(f'**Exact artifact(s) to edit:**\n{arts}')
    lines.append(f'\n**Deploy mechanism:** {p.get("deployMechanism")}')
    lines.append(f'\n**Expected behavior:** {a["expected"]}')
    lines.append(f'\n**Observed (live, this validation):** {a["observed"]}')
    lines.append(f'\n**Responsible step / root cause:** {a["step"]}')
    lines.append(f'\n**Fix to implement (NOT yet applied):** {a["fix"]}')
    if p.get('fixBrief') and not p['fixBrief'].startswith('BLOCKED'):
        lines.append(f'\n**Implementation detail (from artifact pin):** {p["fixBrief"]}')
    lines.append(f'\n**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.')
    lines.append(f'**Evidence record:** {a["url"]}')
    return '\n'.join(lines)

# special override notes per defect
NOTES = {
 'I-03': '> NOTE: an earlier verifier mis-flagged I-03 as BLOCKED ("the proration leg already exists"). The tie-breaker DISPROVED that on live data: a CLEAN list-priced TermDefined line `0QLWC000002LCwH4AW` (PTC=0.7397) comes out FULL 750 on BOTH NetTotalPrice and TotalLineAmount, while only the discounted/adjustment line `0QLWC0000034VY94AM` prorates (3170.71). So the proration multiply (SubscriptionPricing95 / ListContainer93) exists but only fires on the adjustment path. **First reproduce this with a fresh UI-built mid-term TermDefined line, confirm via the explainability trace which leg drops the multiply on the plain list-priced path, THEN gate the proration multiply on SellingModelType=TermDefined regardless of whether an adjustment is present.**',
 'E-04': '> NOTE: E-04 has TWO parts that MUST land together (V2 prehook falls back to 0% on null Non_Orig data, which would BREAK partner pricing): (a) re-point the V21 plan Apex hook from `PartnerPricingPrehook` to `PartnerPricingPrehookV2` (already deployed in the org) — this is the only Apex/plan part of your proc edit; (b) populate `Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c / Non_Orig_New_Maint_Pct__c / Non_Orig_Ren_Maint_Pct__c / Non_Orig_Services_Pct__c` on all 30 `Partner_Pricing_Model__c` rows from the Fortra partner tier schedule (currently all null). Verify with a Deal_Type=`Fortra Originated` partner quote: the Non_Orig band must apply, distinct from the Channel band.',
 'K-01': '> K-01 and F-12 are the SAME fix (null-safe the StampBaseFilter). Patch ALL 6 StampBaseFilter instances in one pass: 3 are already patched (lines ~85548/97288/103199), 3 are not (lines ~109595/116513/123420 for the amend/convert path; the cancellation-path instances ~109632/116550/123457). Change `conditionLogic` `(1 OR 2) AND 3 AND 4 AND 5` -> `(1 OR 2) AND 3 AND 4 AND (5 OR 6)` and add criterion 6 = `NetUnitPrice IsNull` to each unpatched instance.',
 'F-12': '> Fixed together with K-01 (same StampBaseFilter null-safety). After null-safing the filter, also confirm the amend(qty<0) line produces a prorated negative delta (route through TermDefined proration so PTC multiplies the negative net); if it still nets full/zero, that proration routing is a follow-on within the same step family.',
 'G-02': '> Decision table `Attribute_Based_Adjustment_Decision_Table` (0lDa50000007BEuEAM) has NO CurrencyIsoCode input column and is treated as READ-ONLY for this fix — implement via the two AttributePricingFilter container gates (add `CurrencyIsoCode Equals USD`) so the ABA step only fires on USD lines (non-USD lines then fall through to the currency-matched PBE list). Remember criteria-by-position renumbering.',
}

def build(pn):
    P = PORTIONS[pn]
    ids = P['ids']
    eff = {sid: pin[sid].get('effort','M') for sid in ids}
    head = []
    head.append(f'# V21 Fix — PORTION {pn} of 3: {P["name"]}')
    head.append('')
    head.append(f'**Your defects ({len(ids)}):** ' + ', '.join(f'{i} [{authored[i]["pri"]}]' for i in ids))
    head.append(f'\n**Your surface:** {P["surface"]}')
    head.append(f'\n**Boundary:** {P["owns"]}')
    head.append('\n' + PREAMBLE)
    head.append('\n---\n\n## Your defects — fix specs\n')
    for sid in ids:
        if sid in NOTES:
            head.append(NOTES[sid] + '\n')
        head.append(defect_block(sid))
        head.append('\n---\n')
    # coordination
    head.append('## Cross-portion coordination (read before you start)\n')
    head.append(COORD[pn])
    head.append('\n## Definition of done\n')
    head.append(DOD[pn])
    return '\n'.join(head)

COORD = {
 1: '''- **You are the sole editor of the V21 procedure.** Batch ALL your proc changes (K-01/F-12 filter, G-01 formula input, F-09 assignment, G-02 filter gates, I-03 proration gate, E-04 prehook re-point) into ONE metadata change, then ONE deactivate->deploy->reactivate. Do not do six separate deploy cycles (each re-activation is a clobber risk).
- **Portions 2 & 3 reprice against the live V21 to verify their own fixes.** While V21 is deactivated or mid-deploy, their verification will fail. Announce when V21 is stable again so they can verify. Keep the deactivation window short.
- **Partner overlap with Portion 2 (J-06):** your E-04 re-points the partner *prehook* (V1->V2); Portion 2 edits the partner *posthook* (`PartnerNetPricePosthook`). Different classes, but both affect partner net — once both land, re-verify a partner quote end-to-end.
- Do NOT touch: `PartnerNetPricePosthook` (Portion 2), `ProductAttributeDefinition` / `CurrencyType` (Portion 2), `PriceBookEntry*` derived data (Portion 3).''',
 2: '''- **Do NOT edit the V21 procedure** — Portion 1 owns it. Your three items are an Apex class, ProductAttributeDefinition inserts, and CurrencyType admin; none require a proc change.
- **Verification timing:** you verify by repricing through the live V21, which Portion 1 is editing in-place. Do your edits anytime, but run your final reprice-verification when Portion 1 confirms V21 is stable (it will announce). Your J-06 Apex deploy itself does not need the proc.
- **Partner overlap with Portion 1 (E-04):** your J-06 fixes the partner *posthook* band; Portion 1 re-points the partner *prehook*. Different classes — independent edits, but re-verify a partner quote after both land.
- **Derived-maintenance overlap with Portion 3:** your A-07 backfills the Maintenance-Type *attribute*; Portion 3 backfills *PBE* derived config. Different objects/products — no collision; just be aware both touch derived-maintenance pricing.
- Do NOT touch: the V21 ExpressionSet (Portion 1), `Partner_Pricing_Model__c` Non_Orig columns (Portion 1 / E-04), `PriceBookEntry*` derived data (Portion 3).''',
 3: '''- **Do NOT edit the V21 procedure or any Apex** — Portions 1 & 2 own those. You operate only on `PriceBookEntryDerivedPrice` (J-09 inserts) and `PricebookEntry.IsDerived` (J-10 updates).
- **J-09 and J-10 share the derived-PBE space** and are both yours — sequence them so you do not double-touch the same PBE set (do J-10 IsDerived first, then J-09 PBEDP backfill on the now-correct set, or query carefully).
- **Verification timing:** you verify by repricing derived/maintenance quotes through live V21, which Portion 1 is editing. Do your data backfills anytime, but run final reprice-verification when Portion 1 confirms V21 is stable.
- **Derived-maintenance overlap with Portion 2 (A-07):** A-07 backfills the Maintenance-Type *attribute* (ProductAttributeDefinition); you backfill *PBE* config. Different objects — no collision.
- Do NOT touch: the V21 ExpressionSet (Portion 1), any Apex class (Portions 1/2), `ProductAttributeDefinition` / `CurrencyType` (Portion 2).''',
}

DOD = {
 1: '''- All 7 defects: re-reprice each evidence record through the re-activated V21 and confirm the target field now resolves to the expected value (no SF-BRE-00004 abort for K-01/F-12; UnitPrice single-FX for G-01; non-USD partner net no longer double-FX'd for F-09; EUR line no longer takes the USD ABA override for G-02; plain list-priced TermDefined net prorated by fractional PTC for I-03; Fortra-Originated partner takes the Non_Orig band for E-04).
- Re-retrieve V21 metadata post-activation to confirm no canvas-clobber revert.
- Re-reprice 3-4 known-good PASS controls (e.g. a USD direct line, a USD partner line E-02, a BoKS derived demo quote) to confirm no regression.
- Document the exact metadata diff + the Non_Orig data values applied. UAT only — do NOT deploy to prod.''',
 2: '''- J-06: re-reprice the evidence quote; derived-maintenance partner line nets the New-Maintenance band (62.48 = 71x0.88), not 60.35; license line still 301.75.
- A-07: after the MTD attribute backfill, reprice a FIM CCM New-Maintenance line and confirm it derives a non-zero tier (no longer $0/100%-copy); BoKS still 71.
- G-08: confirm the 6 CurrencyType rates + dated rows are corrected (ARS 666.6667, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667); spot-check a report/Workday-facing conversion. (Pricing proc is decoupled, so no reprice needed.)
- Document records changed (class diff, PAD insert count + Ids, CurrencyType edits). UAT only — do NOT deploy to prod.''',
 3: '''- J-10: after setting IsDerived=true on the non-USD derived PBEs, reprice an EUR derived-maintenance quote and confirm NetUnitPrice is committed (COLACalculatedPrice -> NetUnitPrice, no longer $0).
- J-09: after the PBEDP backfill, reprice a previously-uncovered IsDerived line (e.g. GS-GSE-RNM-EF8) and confirm it no longer prices silent null.
- Confirm a known-good covered derived line (BoKS) still prices correctly (no regression).
- Document the PBEDP rows inserted (count + reversible Legacy_Rule_ marker) and the PBE Ids set IsDerived=true. UAT only — do NOT deploy to prod.''',
}

idx = ['# V21 Fix — Portion index\n', 'Three self-contained tab prompts, split by deployment surface to minimize cross-tab dependency. Assign one per Claude Code tab.\n']
for pn in [1,2,3]:
    P = PORTIONS[pn]
    written = build(pn)
    open(f'{BASE}/{P["file"]}', 'w').write(written)
    idx.append(f'- **Portion {pn} — {P["name"]}** (`{P["file"]}`): {", ".join(P["ids"])}')
    print('wrote', P['file'], len(written), 'chars')
open(f'{BASE}/PORTION_INDEX.md', 'w').write('\n'.join(idx) + '\n')
print('wrote PORTION_INDEX.md')
