# COLA Manual E2E Testing Prompt — FortraUAT Salesforce **UI** (Claude CLI + Chrome)

> **Paste everything below into a fresh `claude --chrome` session** (Claude CLI driving your logged-in Chrome).
> This runs an **actual manual end-to-end test of the COLA (Cost-of-Living-Adjustment) feature by driving the
> Salesforce Lightning UI** — **Manage Assets → Renew**, the **Transaction Line Editor**, **Reprice All**, editing
> the **COLA Uplift %** on a line, and reading the **on-screen** Net / Sales Price and the **COLA Information**
> section as the oracle — capturing **screenshots** as evidence and delivering a color-coded **PASS / FAIL /
> BLOCKED** HTML report. You may **also run `sf` SOQL** in the same session to cross-check the on-screen values
> against the record (`claude --chrome` gives you both browser and CLI).

> **Companion prompt:** the headless/CLI version is
> [`docs/COLA_REGRESSION_TEST_PROMPT_CLI.md`](COLA_REGRESSION_TEST_PROMPT_CLI.md) — same COLA scenarios and
> acceptance, scored via `sf`/SOQL. **Why a UI prompt exists:** the RLM engine prices only what is in the managed
> **SalesTransaction context**, which **Manage Assets → Renew** and the **Transaction Line Editor** establish. A
> renewal COLA line **born in the UI** carries real `QuoteAction`/source-asset context; a headless Force-reprice on
> such a line can read **$0 / stale**. So the *born-fresh renewal* and *line-level override* lanes can only be
> scored here.

> **PRIORITY — COLA status board (2026-07-12), UI-observable.** Legend: ✅ FIXED (guard) · 🟢 not-reproduced · 🟡
> PARTIAL · 🔴 OPEN · ⬜ needs-UI. `(org✓/git✗)` = live but git-uncommitted.

| ID | Area | Verdict | UI-observable symptom / expectation |
|---|---|---|---|
| **SC-3350** | renewal COLA → Net commit | ✅ FIXED `(org✓/git✗)` | after Reprice All, the renewal line's **Net Unit Price = COLA Calculated Price** (not the prior/base asset price); **Grand Total** reflects the uplift |
| **COLA-RATE** | CMDT rate by category | 🟢 guard | **COLA Uplift %** = the product category's rate (5 / 7.85 / 9.85); **COLA Source = "CMDT Lookup"** |
| **COLA-OVERRIDE** | line-level override | 🟢 guard · **needs-UI** | edit **COLA Uplift %** in the COLA Information section → Sales/Net recompute off **Pre-COLA Price**; **Is COLA Overridden = ✓**, **COLA Source = "Line Override"** |
| **COLA-MYCAP** | multi-year 3% floor | 🟢 guard · **needs-UI** | multi-year annual defaults **3%**; override `<3%` → Quote **MyCAP = ✓** → **MyCAP Approval** → Deal Desk |
| **COLA-BASE** | Pre-COLA invariant | 🟢 guard | **Pre-COLA Price** stays = original asset price across repeated overrides |
| **COLA-SALESPRICE** | Sales Price populated | ✅ FIXED (SC-3544) | **Sales Price** column not blank on the renewal line |

---

## ROLE & MISSION
You are a **COLA QA agent** testing the live COLA feature through the **FortraUAT Lightning UI**. You click the
buttons a salesperson clicks (Manage Assets → Renew, Transaction Line Editor, Reprice All), you are your own
**read-only oracle** (read the on-screen prices + the COLA Information section and **screenshot** them), and you
grade against each scenario's **Acceptance**. Use **real UAT data**; do not fabricate. **Authorized UI actions** =
Manage Assets → **Renew**, configuring lines in the Transaction Line Editor, **Reprice All**, editing a line's
**COLA Uplift %** / **Override Reason**, and (optional) **Convert Quote to Order** to confirm carry-over. No config
/ metadata changes; no Workday publish unless a step says so. If a screen won't load or an action errors, capture
the error + screenshot and mark **BLOCKED** with the reason.

## GROUND RULES
1. **Org / session:** you are signed into **FortraUAT** as an **RLM-permissioned** user (Revenue Cloud Admin / has
   the Transaction Line Editor). All record links are `https://fortra--uat.sandbox.my.salesforce.com/<id>`.
2. **Real data only.** Renew a real Contract's assets, or open a real renewal Quote. If none fits, ask the CLI
   companion to mint one (`f04_initiateRenewal.apex`), then open it here.
3. **Reprice TWICE — and it must converge and then be idempotent.** Click **Reprice All**, wait for the green
   toast, screenshot; click it **again**. The **2nd click is the graded state** (this org converges on the 2nd
   pass). Then click a **3rd** time — columns must be **identical** to the 2nd (SC-3390). A change after
   convergence = FAIL. A yellow "prices aren't up to date — Refresh" banner → click **Refresh** first.
4. **The oracle is what the screen shows** — the price columns in the Transaction Line Editor and the **COLA
   Information** section on the QuoteLineItem. **Screenshot before and after** each Reprice All and each edit.
   Optionally confirm with SOQL (`sf data query -o FortraUAT ...`) — but the **screen is the source of truth** for a UI FAIL.
5. **COLA is renewals only.** You must be on a **Renewal** quote (`Quote Type = Renewal`, lines from **Renew**).
6. **Report:** color-coded HTML (PASS/FAIL/BLOCKED) with **screenshots embedded** as evidence, one row per §SCN-UI item.

## §0 — THE ON-SCREEN ORACLE (how to read COLA in the UI)
- **Transaction Line Editor / line grid** (Quote → **Lines** tab): the graded price columns are **Net Unit Price**,
  **Net Total**, **Sales Price** (UnitPrice), **Subtotal**. The COLA assertion: on a renewal line, **Net Unit
  Price = COLA Calculated Price** after convergence, and the Quote **Grand Total** reflects the uplift.
- **COLA Information** section (open the **QuoteLineItem** record → the "COLA Information" page-layout section):
  **COLA Uplift %** (editable), **Default COLA %**, **Pre-COLA Price** (read-only, = original asset price), **COLA
  Source** (CMDT Lookup / Contract Override / MyCAP Default / Line Override), **COLA Solution Category**, **Is COLA
  Overridden**, **COLA Calculated Price**, **COLA Override Reason** (editable).
- **Quote header:** **MyCAP** and **MyCAP Approval** checkboxes; **Grand Total**.

## §1 — CORE UI MECHANICS (buttons you will click)
- **Manage Assets → Renew:** open the activated **Contract** → **Manage Assets** → select assets → **Renew** →
  this creates a **Renewal Quote** with COLA already applied at line creation. (This is §A.)
- **Open the cart:** Quote → **Lines** tab → Transaction Line Editor. Set **Instant Pricing = OFF** (you control pricing).
- **Reprice All:** top-right **Reprice All** → wait for green toast. **Run it twice** (§GR-3).
- **Edit COLA %:** open the QLI (or edit inline in the COLA Information section) → change **COLA Uplift %** → Save →
  Reprice All ×2.
- **Convert Quote → Order** (optional carry-over check): **Convert Quote to Order** quick action → open the Order →
  **Reprice All** → confirm Net carries the COLA value.

## §A — CREATE A BORN-FRESH RENEWAL COLA QUOTE (the backbone lane)
1. Open a real **activated Contract** with installed assets (or ask the CLI companion for one:
   `SELECT Id FROM Contract WHERE Status='Activated' AND (has renewable assets)`).
2. **Manage Assets → select assets → Renew.** Screenshot the resulting **Renewal Quote**.
3. Open **Lines** → **Reprice All ×2** → screenshot the grid.
4. **Grade #1–#5 below** off this quote. Keep the Quote Id for the CLI companion to cross-verify.

## §SCN-UI — COLA scenarios to score in the UI (each = a report row)
| # | Scenario | Acceptance (on screen) |
|---|---|---|
| **1** | **SC-3350 net commit** (§A quote, license) | **Net Unit Price = COLA Calculated Price** on each renewal line; **Sales Price** populated (= Net); **Grand Total** = Σ(Net × qty). *Not* the prior/base asset price. |
| **2** | net commit — **Subscription** | same; Net Total = COLA'd unit × qty (verify no extra term multiply) |
| **3** | net commit — **Maintenance** line (if present) | derived-maintenance renewal line's Net reflects COLA (not $0 / stale) |
| **4** | **CMDT rate by category** | **COLA Uplift %** matches the category rule (5 / 7.85 / 9.85); **COLA Source = CMDT Lookup**; **COLA Solution Category** shown |
| **5** | **Sales Price populated** (SC-3544) | **Sales Price** column is **not blank** on the renewal line |
| **6** | **Line-level override** | in COLA Information, change **COLA Uplift %** (e.g. 7.85 → 5.00), Save, Reprice All ×2 → Net = **Pre-COLA Price × (1+new%)**; **Is COLA Overridden = ✓**; **COLA Source = Line Override** |
| **7** | **Pre-COLA invariant** | after 2–3 different overrides, **Pre-COLA Price** is **unchanged** (each recompute is off Pre-COLA, never a prior uplifted value) |
| **8** | **MyCAP default** (multi-year annual, no override) | **COLA Uplift % = 3.00**, **COLA Source = MyCAP Default**, Quote **MyCAP = unchecked** (3% meets floor) |
| **9** | **MyCAP approval** | override a qualifying line to **< 3%** → Quote **MyCAP = ✓** → **MyCAP Approval = ✓** (record-triggered flow) → Deal Desk approval appears |
| **10** | **MyCAP prepaid / single-year bypass** | a prepaid (`PS Service Type = Prepaid`) or single-year annual line is **not** MyCAP-defaulted; COLA stays CMDT default; no flag |
| **11** | **Convergence + idempotency** | Reprice All the 2nd and 3rd time → columns **identical**; no drift |
| **12** | **Convert carry-over** (optional) | Convert Quote → Order → Order line **Net = COLA value** (uplift survives conversion) |

## §CHECKS
- After each Reprice All, if a **red toast / "Something went wrong hydrating the context"** or any pricing error
  appears → screenshot + FAIL (note: context-hydration errors are a separate open item, not COLA math).
- Optional SOQL cross-check (same session): `sf data query -o FortraUAT --query "SELECT NetUnitPrice,
  COLACalculatedPrice__c, COLA_Source__c, Is_COLA_Overridden__c, Pre_COLA_Price__c FROM QuoteLineItem WHERE
  QuoteId='<QID>'"` — the SOQL must match the screen; a mismatch is itself a finding.
- **D-18:** `SELECT Source__c, Message__c FROM Exception_Log__c WHERE CreatedDate = TODAY` — a new COLA/Partner row = FAIL.

## §REPORT
Single self-contained HTML file: color-coded **PASS / FAIL / BLOCKED**, one row per §SCN-UI item, with the
**before/after screenshots embedded** and the on-screen values called out. Header: org, procedure version, the §A
Quote Id used, tester = Claude-in-Chrome, run timestamp. End with a **CHANGELOG** line to append to both prompts.
