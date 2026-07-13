# RCA Hybrid E2E Prompt — Claude Code CLI (SOQL oracle) **+** Claude Chrome (UI driver) · FortraUAT

> **Paste everything below into a fresh Claude Code CLI session that also has browser control (the Claude Chrome
> extension, or a Playwright / Chrome-DevTools MCP) with a logged-in FortraUAT tab.** You will run the RCA
> quote-to-cash E2E by **driving the Salesforce Lightning UI through the browser** for every managed action, and
> **grading with `sf` / SOQL as the authoritative oracle** — then publish the color-coded PASS / FAIL / BLOCKED report.

> **This is the CLI-orchestrated version of the manual UI test.** The scenarios, bindings, and acceptance are the
> UI Manual E2E prompt [`docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md`](RCA_UI_MANUAL_E2E_TEST_PROMPT.md) — read it as the
> **test-case spec**. This wrapper changes only *who does what*: **the browser performs the managed UI actions**
> (they establish the pricing context a headless reprice can't reach), and **the CLI grades via SOQL to the cent**
> (not by reading pixels off the grid). Deeper root-cause detail per ticket is in
> [`docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`](RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md) §T.

## WHY HYBRID (the division of labor)
- **Browser drives the managed place-actions** — **Manage Assets → Renew / Amend / Cancel**, **Add Product +
  configure** in the Transaction Line Editor, **native Reprice All**, **Convert Quote to Order**, **Activate**.
  Only these enter the managed **SalesTransaction context**; a headless `Fortra_Quote_Reprice` reads **$0 / stale**
  on cart- or Manage-Assets-built lines. This is what unblocks the lanes the pure-CLI run marked BLOCKED.
- **CLI grades with SOQL** — after each UI action, query the real fields (`NetUnitPrice`, `Subtotal`, `UnitPrice`,
  `COLACalculatedPrice__c`, …) and compare to the case's Acceptance **to the cent**. SOQL is exact; the on-screen
  grid rounds and hides fields. The CLI also runs the **D-18** check and generates the report.
- **Screenshots are corroborating evidence**, not the oracle. Capture one per UI action; the graded number is the SOQL value.

## TOOLS & ASSUMPTIONS
- **Browser** (Claude Chrome / browser MCP): a tab already **logged into FortraUAT** at
  `https://fortra--uat.sandbox.lightning.force.com`. If you cannot drive the browser directly, **issue the exact UI
  step to the operator and wait for confirmation**, then grade via SOQL — never fabricate a UI result.
- **`sf` CLI**, org alias **`FortraUAT`** (all `sf` commands use `-o FortraUAT`). Read-mostly; the only writes are
  the **UI actions above** (performed in the browser) plus the **authorized reprices** those steps call for.
- Open any record: `…/lightning/r/<Object>/<Id>/view` (Quote / Order / Contract / Asset / Opportunity).

## PREFLIGHT (CLI — do this first, every run)
1. **Active procedure = V25.** `sf data query -o FortraUAT -t -q "SELECT VersionNumber, Status FROM
   ExpressionSetDefinitionVersion WHERE ExpressionSetDefinitionId='9QAWC0000003mg14AA' AND Status='Active'"`.
   **⚠️ If it returns 0 rows, a canvas edit (the SC-3350 Price-Revision work) is mid-flight — STOP and ask the user
   to reactivate V25.** Do not reprice against no active version (invalid results + corrupts quote state).
2. **D-18 baseline:** `SELECT COUNT(Id) FROM Exception_Log__c WHERE CreatedDate = TODAY` → record it; any *new* row
   after a UI action is a swallowed-error **FAIL** (wait ~20–40s for delivery).
3. **Verify bindings exist / status** with the §3 SOQL before use — statuses drift.

## THE HYBRID LOOP (run per test case)
For each scenario in the UI doc's **§A / §B / §LIFECYCLE / §T-UI / §RECIPE**:
1. **(Browser)** Navigate to the record/contract → perform the managed UI action for the case (Manage Assets
   Renew/Amend/Cancel · Add Product + configure attributes · **native Reprice All ×2** · Convert quick action ·
   Activate). **Screenshot** each step. Wait for the green *"prices were refreshed and the configuration was
   validated"* toast (or capture a red/yellow banner as evidence).
2. **(CLI/SOQL)** Snapshot the affected lines with the oracle query below → compare to the case's **Acceptance**
   **to the cent**. Reprice ×2 must be **idempotent** (2nd SOQL snapshot == 1st).
3. **(CLI/SOQL)** Run the **D-18** query → any new row = FAIL (attach it).
4. **Record** the row: `verdict` (PASS/FAIL/BLOCKED), `actual` = the SOQL numbers, `screenshot` = the UI evidence,
   `exceptionLog` = D-18 result.

### Oracle SOQL
**Quote lines:**
```
sf data query -o FortraUAT -q "SELECT LineNumber, Product2.Name, Product2.ProductCode, Quantity, ListPrice, \
UnitPrice, NetUnitPrice, NetTotalPrice, Subtotal, TotalPrice, Base_Price__c, Source_List_Price__c, \
COLACalculatedPrice__c, COLA_Uplift_Percent__c, PartnerDiscountPercent, PricingTermCount, CancelNetUnitPrice__c, \
CurrencyIsoCode, Fortra_Product_Type__c FROM QuoteLineItem WHERE QuoteId='<QUOTE_ID>' ORDER BY LineNumber"
```
**Order lines (convert parity / lifecycle):**
```
sf data query -o FortraUAT -q "SELECT OrderItem.Product2.Name, Quantity, ListPrice, UnitPrice, NetUnitPrice, \
NetTotalPrice, Subtotal, TotalPrice, Workday_Contract_Line_Type__c, RegionalNetUnitPrice__c FROM OrderItem \
WHERE OrderId='<ORDER_ID>' ORDER BY OrderItemNumber"
```
**D-18:** `SELECT Source__c, Hook_Phase__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC`

## SCOPE THIS RUN (the UI-doc lanes — grade every one)
Run them in this order; each is a `RESULTS` row. **Bindings are in the UI doc; key ones repeated here:**

| Lane | UI action (browser) | SOQL oracle (grade to the cent) |
|---|---|---|
| **§A-1 Renew** | Contract **00069410** (BoKS) → Manage Assets → Renew → Automatic Renewal → Reprice All ×2 | renewal net = prior asset net ×(1+COLA); perpetual = No Change/$0; **derived maint > $0** (Path B). ⚠️ renewal *subscription* net may read **null** (active SC-3350 work) — grade derived-maint separately |
| **§A-2 Amend / SC-3501** | Cypress contract **00069475** → Manage Assets → Amend **EFT 7 Enterprise** (asset 273,540 / qty10) → change qty → Reprice All ×2 | `NetUnitPrice` = **27,354** (=273540÷10, per-unit, NOT 273,540); `UnitPrice`==Net; totals = 27,354×qty |
| **§A-3 Cancel / SC-3503** | *(a contract you activated in this run — §LIFECYCLE)* → Manage Assets → Cancel | completes + creates negative credit (`TotalPrice`<0), OR errors on **"Stamp Base Filter 1"** = FAIL. **Ask before running on a shared contract.** |
| **§B Convert parity** | a priced quote → **Convert Quote to Order** → open Order → Reprice All ×2 | each OrderItem's List/Sales/Net/Subtotal/Total **== the Quote line to the cent**; Power splits 1 OrderItem/unit |
| **§LIFECYCLE 6.1–6.10** | Configure → Reprice → Convert → Order Reprice → **Activate** → Contract → Assets → (Workday observe) → Amend → Renew | each phase's oracle (Order==Quote; Status=Activated; Asset count==line count; `Workday_Contract_Line_Type__c` varied) |
| **§T-UI tickets** | per the UI doc's §T-UI cases (SC-3346-ABP / MTD / QTYFOLD / DEDUPE / renewal · SC-3384/3398 · SC-3384-CTX · SC-3501 · SC-3502 · SC-3544 · SC-3503 · SC-3513 · Hardware/Power) | each case's PASS/FAIL oracle (SOQL), e.g. ABP perpetual 15,300 / maint 3,168; SC-3544 UnitPrice 4573.80/918.75; SC-3384 EUR net = USD×0.9346 |
| **§RECIPE deep/edge** | build the §5X line-sets in the TLE (open the CLI §5X / `scripts/apex` fixture for SKU+attrs+EXPECT) → Reprice All ×2 | the fixture's printed EXPECT (e.g. ABA L3 1575; 7-tier Basic 53.25; cancel derived-maint −71) |

## AUTHORIZATION & SAFETY
- **Authorized writes** = the browser UI actions above + the reprices they call for. **Do NOT** change org config /
  metadata (no Setup edits), and **do NOT** publish a Workday event unless a step explicitly says so.
- **§A-3 Cancel is destructive-adjacent** — a partial completion can strand credit records. Run it only on a contract
  **you activated in this run** (§LIFECYCLE), and **confirm with the user** before cancelling on any shared/named contract.
- If the browser action fails or a screen won't load, capture the error + screenshot and mark the row **BLOCKED
  (UI not available)** — never invent a result.

## OUTPUT — §REPORT (mandatory)
Produce the **§REPORT** exactly as the UI doc specifies: a self-contained **HTML + JSX** report (or publish as a
**Claude Artifact** — inline React, no external scripts). Each `RESULTS` row carries `verdict`, `expected`, `actual`
(**the SOQL numbers**), the UI action, the **screenshot** evidence, and `exceptionLog` (D-18). Cluster §T-UI at the
top, most-severe-first; a dedicated **Defects** section (every FAIL + ticket + screenshot) and a **Blocked** section.
Lead with a one-line executive summary (e.g. *"N PASS · N FAIL · N BLOCKED · D-18 clean — <headline>"*).

---
*Hybrid of the two RCA prompts: it executes the **UI Manual E2E** test-case spec
([`docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md`](RCA_UI_MANUAL_E2E_TEST_PROMPT.md)) but with **Claude Code CLI driving the
browser + grading via SOQL**. Active procedure `Rev_Mgmt_Default_Pricing_Procedure` **V25** (confirm at preflight —
the SC-3350 Price-Revision canvas edit may be mid-flight). Re-verify each record/URL before use.*
