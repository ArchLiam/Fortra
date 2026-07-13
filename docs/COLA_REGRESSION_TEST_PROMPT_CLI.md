# COLA Full Regression Testing Prompt — FortraUAT · **CLI / Claude Code** (real-data)

> **Paste everything below the line into a fresh Claude Code session.** It drives a focused, end-to-end
> regression of the **COLA (Cost-of-Living-Adjustment) uplift feature** on **real FortraUAT records**, using the
> **Salesforce CLI (`sf`) + SOQL** as a read-only oracle, and delivers a color-coded **PASS / FAIL / BLOCKED**
> HTML report. It is the **CLI half** of a pair — the manual UI companion is
> [`docs/COLA_UI_MANUAL_TEST_PROMPT.md`](COLA_UI_MANUAL_TEST_PROMPT.md) (Claude-in-Chrome, same scenarios/acceptance).

> **Scope:** everything COLA — CMDT rate lookup, the 4-tier override hierarchy, MyCAP out-year enforcement, and
> (headline) the **SC-3350 renewal net commit**. It does **not** re-test the whole pricing engine — for that use
> [`docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`](RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md).

> **PRIORITY — COLA status board (2026-07-12).** Legend: ✅ FIXED (regression guard — must not re-break) · 🟢
> not-reproduced · 🟡 PARTIAL · 🔴 OPEN. `(org✓/git✗)` = live in FortraUAT but git-uncommitted (a clean `main`
> checkout still reproduces the defect).

| ID | Area | Verdict | Current state |
|---|---|---|---|
| **SC-3350** | renewal COLA → `NetUnitPrice` commit | ✅ FIXED `(org✓/git✗)` | posthook commits `NetUnitPrice = COLACalculatedPrice__c`; GrandTotal reflects COLA. Root cause was **input-type `InputUnitPrice` poisoning the `updateContextAttributes` batch** — removed from `RenewalColaPayloadBuilder.buildCommitPayload`. **Guard: net must equal COLACalc, and the commit payload must stay output-only.** |
| **COLA-RATE** | CMDT lookup by Solution Category | 🟢 guard | `COLA_Uplift_Rules__mdt` → 5.00 / 7.85 / 9.85 by category; unmatched = **0%** |
| **COLA-HIER** | 4-tier override precedence | 🟢 guard | Line Override > MyCAP Default > Contract Override > CMDT Lookup; `COLA_Source__c` reflects the winner |
| **COLA-MYCAP** | multi-year out-year 3% floor | 🟢 guard | qualifying multi-year annual → 3% default; `<3%` → `Mycap__c`=true → `MYCAP_Approval__c` → Deal Desk; prepaid + single-year bypass |
| **COLA-BASE** | `Pre_COLA_Price__c` invariant | 🟢 guard | = original `SourceAsset.Price`; **unchanged across any number of overrides** |
| **COLA-PARTNER** | partner-Originated renewal COLA | 🟡 verify | net = partner-adjusted COLA (not raw COLAcalc); confirm no regression |
| **COLA-CCY** | non-USD renewal COLA | 🟡 verify | interacts with SC-3398 conversion; may be BLOCKED until that lands |

## CHANGELOG
*Newest first. One dated line per material change.*
- **2026-07-12** — Full CLI run on **V25** (10 quotes): **15 PASS / 1 PASS-caveat (S17 partner, stays 🟡 — every sampled channel line has 0 partner discount so the reduction path is unexercised) / 3 BLOCKED (S6 unmatched-cat, S7 inactive-rule, S14 prepaid — all data/config gaps) / 0 FAIL.** SC-3350 holds: Ibx3 162420, `Net==COLAcalc`, D-18 clean across ~15 reprices, idempotent (pass2==pass3). 4-tier hierarchy all confirmed on real data (Line/MyCAP/Contract/CMDT). ⚠️ **`buildCommitPayload` output-only fix is git-UNCOMMITTED** (working-tree M; `1a2aa2b` still has `InputUnitPrice`) → clean checkout re-breaks SC-3350; commit it. Report: `docs/COLA_REGRESSION_RESULTS_2026-07-12.html`. Prompt drift fixed: `Is_COLA_Overridden__c`/`ItemPricingSource`/`PS_Service_Type__c` don't exist; CMDT field is `Default_Uplift_Percent__c`.
- **2026-07-12** — Prompt created. SC-3350 fixed via Apex posthook (output-only commit payload); smoke-tested 8-quote sample (2-pass converge) **13/13 target COLA lines commit, 0 miss, D-18 clean**. Documented the **reprice-twice convergence** rule (§GR-4).

---

## ROLE & MISSION
You are a **COLA QA agent** validating the live COLA feature on **FortraUAT**. Exercise **every COLA scenario in
§SCN** against **real UAT data** (or minted fixtures), snapshot the oracle **before and after each reprice**, and
produce a defect-grade report. Do not fabricate data; do not change configuration. **Authorized writes** = the
**Force-reprices** the steps tell you to run, the **`scripts/apex/` fixtures** (§DATA-B, savepoint-protected),
the **renewal-generation invocable** (`Fortra_Create_Renewal_Quote` / `f04_initiateRenewal.apex`), and **line-level
field edits** the override scenarios require (`COLA_Uplift_Percent__c`, `Contract.COLA_Override_Percent__c`) — via
`sf data update` **on a fixture quote only**. Nothing else.

## GROUND RULES
1. **Org:** `FortraUAT` (`-o FortraUAT` on every `sf`). Read-mostly.
2. **Real data only.** Use the §DATA bindings / SOQL to find live renewal COLA lines; if none fit, **mint one**
   with a §DATA-B fixture. Only mark **BLOCKED (no data)** if neither exists.
3. **The oracle** is the per-line SOQL snapshot in §ORACLE — capture **before AND after** each reprice and diff.
4. **⚠️ Reprice TWICE, and the 2nd pass is the graded one.** This org's pricing needs a **second Force-reprice to
   converge** — a single reprice can leave a transient net (often `= PartnerUnitPrice`) that resolves on the 2nd
   pass. Also assert the 2nd and 3rd passes are **identical** (idempotency, SC-3390). A change after convergence = FAIL.
5. **After every reprice, check the D-18 exception log** (§CHECKS): a new `Exception_Log__c` row means a hook
   silently swallowed an error — a FAIL to investigate even if the price looks right.
6. **COLA applies to RENEWALS only** — `Quote.QuoteTypeText__c = 'Renewal'` and the line's `QuoteAction.Type =
   'Renew'` / context `SalesTransactionActionType = 'Renew'`. A COLA'd non-renewal line = FAIL.
7. **Report:** color-coded HTML (PASS green / FAIL red / BLOCKED grey), one row per §SCN item, click-to-expand
   before/after evidence + the SOQL you ran.

## §MECH — REPRICE + SNAPSHOT (exact commands)
**Force-reprice a Quote (run ×2):**
```bash
QID=<quoteId>
printf '{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"%s"}}}]}}' "$QID" > /tmp/rp.json
sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "@/tmp/rp.json"   # expect "isSuccess": true; run this twice
```
> **`isSuccess:false`** with `FIELD_INTEGRITY_EXCEPTION "Select an active Legal Entity"` or `SF-Pricing-00006
> DerivedPricingFilter#1` = a **pre-existing quote data/config defect, NOT COLA** → mark that record BLOCKED and
> pick another. Native "Reprice All" (UI companion) is required for cart/Manage-Assets-built lines.

## §ORACLE — the COLA fields to snapshot (before AND after)
```bash
sf data query -o FortraUAT --json --query "SELECT Id, Product2.Name, Fortra_Product_Type__c, Quantity, \
  NetUnitPrice, NetTotalPrice, UnitPrice, Subtotal, COLACalculatedPrice__c, COLA_Uplift_Percent__c, \
  Default_COLA_Uplift_Percent__c, Pre_COLA_Price__c, COLA_Source__c, Is_COLA_Overridden__c, \
  COLA_Solution_Category__c, ItemPricingSource FROM QuoteLineItem WHERE QuoteId='<QID>' ORDER BY LineNumber"
# Quote-level MyCAP: SELECT Mycap__c, MYCAP_Approval__c, GrandTotal FROM Quote WHERE Id='<QID>'
```
**The core SC-3350 assertion:** for every renewal line with `COLACalculatedPrice__c > 0`, after convergence
`NetUnitPrice == COLACalculatedPrice__c` and `NetTotalPrice == COLACalculatedPrice__c × Quantity`, and
`Quote.GrandTotal` includes the uplift.

## §DATA — real UAT COLA records + SOQL to find more
**Reference quote (SC-3350 gold):** `0Q0WC000003Ibx3` — lines `npyw` (Email Security 5%, Net **98700**), `npyx`
(Vuln Mgmt 6.2%, Net **63720**), GrandTotal **162420**. Re-verify it still commits before anything else.

**Find real renewal COLA lines, by product type (there are ~78 such quotes):**
```bash
sf data query -o FortraUAT --json --query "SELECT QuoteId, Fortra_Product_Type__c, COUNT(Id) n FROM QuoteLineItem \
  WHERE COLACalculatedPrice__c > 0 AND Quote.QuoteTypeText__c='Renewal' GROUP BY QuoteId, Fortra_Product_Type__c"
```
Cover **null(license) / Subscription / Software** (all commit net) and **Renewal/New Maintenance** (commit COLA'd
net — regression check). For **MyCAP**: filter multi-year annual (`PricingTermCount>1 AND PricingTermUnit='Annual'`
OR `ItemSubscriptionTerm>1`); for **Contract override**: lines whose `AssetContractRelationship.Contract` has
`COLA_Override_Percent__c`.

## §DATA-B — mint COLA fixtures when no real record fits
Run a fixture, then grep the ERROR-level log for its `✅ FIXTURE CREATED` marker (prints Quote Id + expected oracle):
```bash
sf apex run -o FortraUAT -f scripts/apex/<script>.apex
```
- `setupColaUatTestData.compact.apex` — COLA/DPP base quote fixture (Contact→Place→Quote on the standing test Account/Opp).
- `setupJ03DerivedRenewalResetTestData.compact.apex` / `setupCarryForwardLastTxnTestData.compact.apex` — renewal/last-transaction fixtures.
- **Generate a platform renewal** (real source assets + `QuoteAction.Type='Renew'`): `f04_initiateRenewal.apex`
  or the `Fortra_Create_Renewal_Quote` invocable. This is the only way to get a *born-fresh* renewal COLA line.
- New fixtures follow the `scripts/apex/setup*TestData.compact.apex` shape (savepoint-protected — real records, not fakes).

## §SCN — COLA scenarios to run (each is a report row)
Grade each after §MECH ×2. Bind a real record from §DATA (or mint one).

| # | Scenario | Acceptance |
|---|---|---|
| **1** | **SC-3350 net commit** (license) | `NetUnitPrice == COLACalculatedPrice__c`; `NetTotalPrice = COLAcalc × qty`; GrandTotal reflects it. (Ibx3: 98700/63720, GT 162420.) |
| **2** | net commit — **Subscription** | same; verify no double-count vs term (`NetTotalPrice = COLAcalc × qty`, not × term again) |
| **3** | net commit — **Software** | same as #1 |
| **4** | **Maintenance** renewal COLA | maintenance line with `COLAcalc>0` → `NetUnitPrice == COLAcalc` (no SC-3346 regression; net not $0/stale) |
| **5** | **CMDT rate by category** | `COLA_Uplift_Percent__c` = the category's rule (5/7.85/9.85); `COLA_Source__c='CMDT Lookup'`; `COLA_Solution_Category__c` set |
| **6** | **Unmatched category → 0%** | product with no matching `COLA_Uplift_Rules__mdt` → 0% COLA, no uplift, no error |
| **7** | **Inactive rule excluded** | `Is_Active__c=false` rule → that category excluded (falls to 0% or next tier) |
| **8** | **Line override** | edit `COLA_Uplift_Percent__c` on a fixture line → `UnitPrice/Net = Pre_COLA × (1+new%)`; `Is_COLA_Overridden__c=true`; `COLA_Source__c='Line Override'` |
| **9** | **Pre-COLA invariant** | override the line 2–3× → `Pre_COLA_Price__c` unchanged (= original `SourceAsset.Price`); each recompute off Pre-COLA, never off a prior uplifted value |
| **10** | **Contract override** | valid `Contract.COLA_Override_Percent__c` (+ persist date ≥ today or null) → that % wins over CMDT; `COLA_Source__c='Contract Override'` |
| **11** | **Non-renewal = no COLA** | a New/Amend line → **no** `COLACalculatedPrice__c`, no uplift |
| **12** | **MyCAP default (multi-yr annual, no override)** | `COLA_Uplift_Percent__c=3.00`, `COLA_Source__c='MyCAP Default'`, `Quote.Mycap__c=false` (3% meets floor) |
| **13** | **MyCAP approval trigger** | override qualifying line to `<3%` → `Quote.Mycap__c=true` → `MYCAP_Approval__c=true` (flow); Deal Desk routing |
| **14** | **MyCAP prepaid bypass** | `PS_Service_Type='Prepaid'` multi-year → MyCAP skips; COLA stays CMDT default; no flag |
| **15** | **MyCAP single-year bypass** | single-year annual → MyCAP bypassed; COLA = CMDT default |
| **16** | **MyCAP mixed lines** | one qualifying line `<3%` → `Mycap__c=true`; only the qualifying line defaulted to 3% |
| **17** | **Partner-Originated renewal COLA** | `Deal_Type__c='Channel Originated'` renewal → net = partner-adjusted COLA (not raw COLAcalc); no error/regression |
| **18** | **Idempotency + convergence** | reprice ×3 → converges by pass 2, identical pass 2 vs 3 |
| **19** | **D-18 clean** | zero new `Exception_Log__c` across the whole run |

## §CHECKS
- **D-18 exception log:** `SELECT Source__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC` — any `COLA*`/`Partner*`/`RenewalCola*` row after a reprice = FAIL.
- **SC-3350 payload guard (static):** confirm `RenewalColaPayloadBuilder.buildCommitPayload` writes **output-only**
  fields and does **NOT** include `InputUnitPrice` (or `UnitPrice`) — re-adding an input-type attribute re-poisons
  the batch and silently drops the net. `RenewalColaPayloadBuilderTest` + `PartnerNetPricePosthookTest` must be green.

## §REPORT
Produce a single self-contained HTML file (color-coded PASS/FAIL/BLOCKED, click-to-expand before/after tables +
the SOQL used). Header: org, procedure version (re-verify sole-active: `SELECT VersionNumber,Status FROM
ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure'
AND Status='Active'`), run timestamp, and a one-line verdict per §SCN row. End with a **CHANGELOG** line to append here.
