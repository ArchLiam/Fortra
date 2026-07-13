# SC-3346 DPP (Derived Maintenance Pricing) Manual E2E Prompt — FortraUAT **UI** (Claude API + Claude-on-Chrome)

> **Paste everything below into a fresh Claude-on-Chrome session** (Claude driving your logged-in Chrome, with `sf`
> available in the same session as a read-only cross-check). This runs an **actual manual end-to-end test of the
> DPP — Derived Maintenance Pricing (SC-3346)** feature by driving the **Salesforce Lightning UI** — adding a
> license to a cart and reading the **auto-added maintenance line**, selecting the **maintenance tier**,
> **Manage Assets → Renew** for renewals, the **Transaction Line Editor**, **Reprice All** — reading the **on-screen**
> Net / Sales Price and the maintenance line's **attributes** as the oracle, capturing **screenshots** as evidence,
> and delivering a color-coded **PASS / FAIL / BLOCKED** self-contained **HTML** report.

> **Companion prompt:** the headless/CLI version is
> [`docs/SC3346_DPP_REGRESSION_TEST_PROMPT_CLI.md`](SC3346_DPP_REGRESSION_TEST_PROMPT_CLI.md) — same scenarios and
> acceptance, scored via `sf`/SOQL. **Why a UI prompt exists:** the RLM engine prices only what is in the managed
> **SalesTransaction context**, which the **cart / Transaction Line Editor** and **Manage Assets → Renew** establish.
> A maintenance line **born in the UI** (auto-added next to its license, or born on a renewal) carries real
> configurator/`QuoteAction` context that a headless reprice can read as **$0 / stale**. So the *auto-add tier
> selection* and *born-fresh renewal* lanes can only be scored here.

> **⚠️ DO NOT DELETE OR CLEAN UP any quote, line, order, or renewal you create — it will be shared with the team.**
> Record every record Id (and its URL) in the report's Artifacts section.

> **PRIORITY — DPP/SC-3346 status board (2026-07-12), UI-observable.** Legend: ✅ FIXED (guard) · 🟢 guard · 🟡
> verify · 🔴 OPEN/DATA · ⬜ needs-UI. `(org✓/git✗)` = live but git-uncommitted.

| ID | Area | Verdict | UI-observable symptom / expectation |
|---|---|---|---|
| **SC-3346-TIER** | new-biz maint tier | 🟢 guard · **needs-UI** | select **Maintenance Type Defn = Standard/Premier/Professional** on the auto-added maint line → **Net = source base × 0.20 / 0.30 / 0.20** |
| **SC-3346-MTD** | untagged New-Maint (no tier picker) | ✅ FIXED `(org✓/git✗)` · **needs-UI** | a maintenance line whose product has **no tier attribute** (no "Maintenance Type Defn" field on the line) still prices **non-zero** (Standard 0.20 default), not $0 |
| **SC-3346-BASELESS** | maint with no base | 🟢 guard | a maintenance line with no resolvable source base shows **$0** (correct) |
| **SC-3346-DISC** | discount netting | 🟢 guard | after a partner/discretionary discount, maint **Net = base×tier − discounts** |
| **SC-3346-RNM1** | first-renewal maint COLA | ✅ FIXED `(org✓/git✗)` · **needs-UI** | after Reprice All the renewal maint **Net Unit Price = (prior base − partner − disc) × (1+COLA)** — the posthook overrides the procedure's under-priced value (smoke: discretionary line 660→3645; RRM unchanged). Read the **committed Net Unit Price** (not COLACalc, which stays stale) |
| **SC-3346-RRM** | 2nd+ renewal (RRM) | 🟢 guard | a Renewal-Maintenance line's Net = **asset × COLA** (prior discount **not** re-subtracted) |
| **SC-3346-QTY** | qty>1 | 🟢 guard | a qty-N maintenance line's **unit** Net is not multiplied by N |
| **SC-3346-ASSET** | mis-priced assets | 🔴 DATA | if a renewal maint line's Net looks license-scale (e.g. ~372 not ~65), its source **asset price is bad data** — flag, not a formula FAIL |

---

## ROLE & MISSION
You are a **DPP/maintenance-pricing QA agent** testing the live derived-maintenance feature through the **FortraUAT
Lightning UI**. You click the buttons a salesperson clicks (add a license to a cart, pick the maintenance tier,
Manage Assets → Renew, Transaction Line Editor, Reprice All), you are your own **read-only oracle** (read the
on-screen prices + the maintenance line's attributes and **screenshot** them), and you grade against each scenario's
**Acceptance**. Use **real UAT data**; do not fabricate. **Authorized UI actions** = building a quote/cart and adding
products, selecting a line's **Maintenance Type Defn** tier, **Manage Assets → Renew**, **Reprice All**, applying a
partner/discretionary **discount** on a line, and (optional) **Convert Quote to Order** to confirm carry-over. **No
config / metadata / pricing-procedure changes.** If a screen won't load or an action errors, screenshot it and mark
**BLOCKED** with the reason. **Delete nothing.**

## GROUND RULES
1. **Org / session:** signed into **FortraUAT** as an **RLM-permissioned** user (Revenue Cloud Admin / has the
   Transaction Line Editor). Record links are `https://fortra--uat.sandbox.my.salesforce.com/<id>`.
2. **Real data only.** Renew a real Contract's assets, or open/build a real quote. If none fits, ask the CLI
   companion to mint one (`f04_initiateRenewal.apex` / `scripts/apex/setupJ02DerivedTierTestData.compact.apex`),
   then open it here.
3. **Reprice TWICE — converge, then be idempotent.** Click **Reprice All**, wait for the green toast, screenshot;
   click it **again** — the **2nd click is the graded state**. Then a **3rd** — columns must be **identical**
   (SC-3390). A yellow "prices aren't up to date — Refresh" banner → click **Refresh** first.
4. **The oracle is what the screen shows** — the price columns in the Transaction Line Editor and the maintenance
   line's attribute + pricing fields. **Screenshot before and after** each Reprice All and each edit. Optionally
   confirm with SOQL in the same session — but the **screen is the source of truth** for a UI FAIL.
5. **If Reprice All red-toasts** `Ensure that this procedure has at least one active version`, `INVALID_PRICE_REVISION_FORMULA`,
   or "Something went wrong hydrating the context" → screenshot + mark **BLOCKED** (pre-existing infra/quote issue,
   not DPP) and move on; retry the procedure-inactive ones later.
6. **Report:** color-coded HTML (PASS/FAIL/BLOCKED) with **screenshots embedded**, one row per §SCN-UI item.
   **Delete nothing** — list all record Ids/URLs in Artifacts.

## §0 — THE ON-SCREEN ORACLE (how to read DPP in the UI)
- **Transaction Line Editor / line grid** (Quote → **Lines** tab): graded columns are **Net Unit Price**, **Net
  Total**, **Sales Price** (UnitPrice), **Subtotal**, and the maintenance line sits **next to its license**.
- **Maintenance tier attribute:** on the auto-added maintenance line, open its **configure/attributes** panel →
  **Maintenance Type Defn** (Standard / Premier / Professional). A product whose classification does **not** model a
  tier shows **no such attribute** — that is the SC-3346-MTD case (it must still price via the Standard default).
- **QLI fields** (open the maintenance QuoteLineItem record): `Fortra_Product_Type__c` (New Maintenance / Renewal
  Maintenance), `Base_Price__c`, `Source_List_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c`,
  `COLA_Uplift_Percent__c`, `NetUnitPrice`.
- **Quote header:** **Grand Total**, **Quote Type** (New / Renewal).

## §1 — CORE UI MECHANICS (buttons you will click)
- **New-biz maintenance:** New/Draft Quote → **Add Products** → add a **license** (e.g. BoKS `PIA-PIA-NRPS-PIAP`) →
  RCA **auto-adds the matching maintenance line** next to it → open the maintenance line's attributes → set
  **Maintenance Type Defn** → **Reprice All ×2** → read the maintenance line's Net.
- **Renewal maintenance:** open an activated **Contract** with installed maintenance assets → **Manage Assets** →
  select → **Renew** → this creates a **Renewal Quote** with the maintenance carried forward → **Lines** →
  **Reprice All ×2** → read the renewal maintenance line's Net.
- **Discount:** apply a partner/discretionary discount on the maintenance line → **Reprice All ×2**.
- **Convert Quote → Order** (optional): confirm the maintenance Net carries over.

## §A — BUILD A NEW-BIZ MAINTENANCE QUOTE (backbone lane 1)
1. New Quote on the standing test Account/Opp → **Add Products** → add a license whose maintenance is **tier-modelled**
   (BoKS `PIA-PIA-NRPS-PIAP`). Screenshot the auto-added maintenance line.
2. Set **Maintenance Type Defn = Standard** on the maintenance line → **Reprice All ×2** → screenshot.
3. Grade #1–#6. Keep the Quote Id.

## §B — BORN-FRESH RENEWAL MAINTENANCE (backbone lane 2)
1. Open a real **activated Contract** with an installed **maintenance** asset (or ask the CLI companion for one).
2. **Manage Assets → select → Renew.** Screenshot the Renewal Quote.
3. **Lines → Reprice All ×2** → screenshot. If the maintenance line shows **$0/null**, it may need conversion — ask
   the CLI companion to run `RenewalMaintenanceProvisionService.provision('<QID>')`, then Reprice All ×2 again.
4. Grade #7–#11. Keep the Quote Id.

## §SCN-UI — DPP scenarios to score in the UI (each = a report row)
| # | Scenario | Acceptance (on screen) |
|---|---|---|
| **1** | new-biz maint — **Standard** | maint **Net = source base × 0.20** (BoKS 355 → **71**); tier attribute shows Standard |
| **2** | new-biz maint — **Premier** | change tier to Premier → **Net = base × 0.30** (**106.50**) after Reprice ×2 |
| **3** | new-biz maint — **Professional** | **Net = base × 0.20** |
| **4** | **untagged** New-Maint (no tier picker) | **SC-3346-MTD:** a maintenance line with **no "Maintenance Type Defn" attribute** still shows a **non-zero Net** (Standard 0.20 default), not $0 |
| **5** | **base-less** maint | a maintenance line with no resolvable source base shows **$0** (correct — not an error) |
| **6** | **discount netting** | apply a partner discount → maint **Net = base×tier − discount** (screenshot before/after) |
| **7** | **first-renewal maint** — with discount | §B renewal line **Net = (prior base − partner − disc) × (1+COLA)** (e.g. **65.09**), not asset×COLA (76.57) and not $0 |
| **8** | **first-renewal maint** — no discount | **Net = asset × (1+COLA)** (**76.57**) |
| **9** | **RRM (2nd+ renewal)** non-regression | a Renewal-Maintenance line's **Net = asset × COLA**; prior discount **not** re-subtracted |
| **10** | **qty>1** | a qty-N maintenance line's **unit** Net equals the qty-1 value (no ×N inflation) |
| **11** | **convergence + idempotency** | Reprice All 2nd and 3rd → columns **identical** |
| **12** | **SC-3346-ASSET data check** | if a renewal maint Net is license-scale (≈372 not ≈65), flag the source **asset price** as bad data (screenshot + asset Id) — **DATA finding**, not a math FAIL |
| **13** | **Convert carry-over** (optional) | Convert Quote → Order → Order line maintenance **Net** survives |

## §CHECKS
- After each Reprice All, if a **red toast** / **"Something went wrong hydrating the context"** / any pricing error
  appears → screenshot + BLOCKED (note: context-hydration and procedure-inactive errors are separate open/infra
  items, not DPP math).
- Optional SOQL cross-check (same session): `sf data query -o FortraUAT --query "SELECT Fortra_Product_Type__c,
  Base_Price__c, Prior_Partner_Discount__c, COLA_Uplift_Percent__c, NetUnitPrice, QuoteAction.SourceAsset.Price
  FROM QuoteLineItem WHERE QuoteId='<QID>'"` — the SOQL must match the screen; a mismatch is itself a finding.
- **D-18:** `sf data query -o FortraUAT --query "SELECT Source__c, Message__c FROM Exception_Log__c WHERE CreatedDate = TODAY"` — a new Posthook/COLA/RenewalMaintenance row = FAIL.

## §REPORT
Produce a **single self-contained HTML file** (inline CSS/JS, no external assets), high-visibility and readable:
color-coded **PASS / FAIL / BLOCKED** badges, one row per §SCN-UI item, with the **before/after screenshots embedded**
(base64 data-URIs) and the on-screen values called out next to the expected value. Header: org, **procedure version**,
the §A and §B Quote Ids used, tester = Claude-on-Chrome, run timestamp. **Artifacts section: list every Quote /
Order / renewal / line / asset Id and URL used or created — nothing is deleted.** End with a **CHANGELOG** line to
append to both prompts. Save the HTML next to this prompt (e.g. `docs/sc3346_dpp_ui_report_<date>.html`).
