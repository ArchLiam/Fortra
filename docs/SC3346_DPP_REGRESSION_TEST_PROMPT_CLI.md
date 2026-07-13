# SC-3346 DPP (Derived Maintenance Pricing) Regression Prompt — FortraUAT · **CLI / Claude Code** (real-data)

> **Paste everything below the line into a fresh Claude Code session.** It drives an end-to-end regression of the
> **DPP — Derived Maintenance Pricing (SC-3346)** feature on **real FortraUAT records**, using the Salesforce CLI
> (`sf`) + SOQL as a read-only oracle plus the authorized pricing writes below, and delivers a color-coded
> **PASS / FAIL / BLOCKED** self-contained **HTML** report. It is the **CLI half** of a pair — the manual UI
> companion is [`docs/SC3346_DPP_UI_MANUAL_TEST_PROMPT.md`](SC3346_DPP_UI_MANUAL_TEST_PROMPT.md) (Claude-in-Chrome,
> same scenarios/acceptance).

> **Scope:** the whole **derived-maintenance pricing procedure (DPP)** — BOTH branches:
> **(1) New-business maintenance** = source license base × maintenance-tier %, then the line's own partner/
> discretionary discounts; and **(2) Renewal maintenance** = the prior maintenance carried forward and COLA-uplifted.
> It does **not** re-test the whole engine (use [`RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`](RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md))
> or the COLA-override hierarchy in isolation (use [`COLA_REGRESSION_TEST_PROMPT_CLI.md`](COLA_REGRESSION_TEST_PROMPT_CLI.md)).

> **⚠️ DO NOT DELETE OR CLEAN UP any test data you find or generate — it will be shared with the team.** Leave every
> quote/line/fixture in place; record every Id you touch in the report's "Artifacts" section.

> **PRIORITY — DPP/SC-3346 status board (2026-07-12).** Legend: ✅ FIXED (regression guard — must not re-break) ·
> 🟢 guard · 🟡 verify · 🔴 OPEN/DATA. `(org✓/git✗)` = live in FortraUAT but git-uncommitted.

| ID | Area | Verdict | Current state |
|---|---|---|---|
| **SC-3346-TIER** | new-biz maint tier pricing | 🟢 guard | net = source base × tier% — **Standard 0.20 / Premier 0.30 / Professional 0.20** (`Maintenance_Rate__mdt`) |
| **SC-3346-MTD** | new-biz **untagged** New-Maint (no tier attribute) | ✅ FIXED `(org✓/git✗)` | classification lacks a `Maintenance Type Defn` attribute → **posthook defaults to Standard 0.20** (only when the line has a base); constant `PartnerNetPricePosthook.UNTAGGED_MAINTENANCE_DEFAULT_TIER` |
| **SC-3346-BASELESS** | new-biz maint with no pricing base | 🟢 guard | `Base_Price__c<=0 AND Source_List_Price__c<=0` → **correctly $0** (no fabricated price); scope guard must hold |
| **SC-3346-DISC** | new-biz maint discount netting | 🟢 guard | partner + discretionary applied **after** base × tier |
| **SC-3346-RNM1** | **first-renewal** maintenance COLA (3-component) | ✅ FIXED `(org✓/git✗)` | commit-layer override in `PartnerNetPricePosthook.buildRenewalColaCommitUpdate`: for a Renew line whose `SourceAsset.Product2.Fortra_Product_Type__c='New Maintenance'`, commits `computeFirstRenewalMaintenanceNet(perUnit(SourceAsset.Price), priorPartner$, priorDisc$, Discount, COLA)` — asset-based, no %-re-discount — **overriding** the procedure's `Base_Price__c`-derived value. **Smoke-proven: DOpB 660.04→3645.33, DKNN/DKC5 58.58→65.09, DLBO→60.37; RRM 382MH 65.4 unchanged; idempotent.** **Grade SCN8–10 on committed `NetUnitPrice`.** ⚠️ `COLACalculatedPrice__c` stays the procedure's stale value — grade on `NetUnitPrice`, not COLACalc. |
| **SC-3346-RRM** | **2nd+ renewal** (RRM) maintenance | 🟢 guard | single-component **asset × COLA** — RRM (`Renewal Maintenance` product) + subscriptions are **excluded** from the discount-net; **must NOT re-net** (regression check) |
| **SC-3346-CCY** | multi-currency maintenance | 🟡 verify | interacts with SC-3398 conversion; native `ListPrice`, converted `NetUnitPrice` |
| **SC-3346-QTY** | qty>1 no inflation | 🟢 guard | per-unit via `AssetNetUnitPrice.perUnit`; qty-100 must not 100× |
| **SC-3346-ASSET** | mis-priced maintenance assets | 🔴 DATA | some RNM assets carry the **license price** (e.g. `Asset.Price=355` on a maint product, should be ~71) → renewal net computes off the bad base. **Upstream data-quality issue, NOT a formula bug** — flag, do not "fix" in the formula |

## CHANGELOG
*Newest first. One dated line per material change.*
- **2026-07-12 (run 2 — RNM1 fix verification)** — Re-ran after the commit-layer fix (`PartnerNetPricePosthook.buildRenewalColaCommitUpdate`) deployed. **PASS 12 / WARN 1 / FAIL 0 / BLOCKED 2 / DATA 1** (report `docs/sc3346_dpp_cli_report_2026-07-12_run2.html`). **SCN10 FIXED** — the run-1 FAIL line `0Q0WC000003DOpB0AW` committed 660.04 in run 1, now commits **3645.33** and holds idempotently across reprice ×2; DLBO→60.37. **SCN8 FIXED** — DKNN 58.58→**65.09** (was WARN). All 6 renewal lines match born-formula to the cent (independently re-derived + adversarially verified, unrefuted). Confirmed **grade on `NetUnitPrice`** — `COLACalculatedPrice__c` stays the procedure's stale value (660.04/58.58); its only money consumer `MaintenanceOrderDecompositionService.cls:477` is a last-resort fallback not reached while `NetUnitPrice>0` (no order/Workday money defect), though re-stamping COLACalc is advisable. **SCN2 now PASS** — gold line `04267517` is live Premier, reprices to **106.50** = 355×0.30. Unchanged: **WARN SCN6** (new-biz netting 56.23 ≠ waterfall 54.32, out of renewal-fix scope); **BLOCKED SCN3** (no live Professional; rate=0.20=Standard), **SCN12** (0 non-USD renewal); **DATA SCN15** (18 override-license lines). 153 unit tests 100%, D-18 clean.
- **2026-07-12** — First CLI regression run (Claude Code). 16 scenarios · **PASS 9 / WARN 2 / FAIL 1 / BLOCKED 3 / DATA 1** (report `docs/sc3346_dpp_cli_report_2026-07-12.html`). **FAIL SCN10** — first-renewal maint carrying a discretionary/manual `Discount` does NOT survive Force-reprice: fresh `0Q0WC000003DOpB0AW` borns correct `UnitPrice` 3645.33 but reprices `NetUnitPrice`→**660.04** (Base collapses to `assetPx 4000 × 0.20 = 800`, new-biz tier mis-route); stale `DLBO` 60.37→58.58 (over-eroded base). **Silent — no D-18 row.** The RNM1 fix is proven on born `UnitPrice` only; reprice/`NetUnitPrice` path is unguarded for discount cases. **WARN SCN8** — named §DATA sample `DKNN` reprices to 58.58 ≠ documented 65.09 (over-eroded born Base 54.32); fresh partner-only `FRPZ` correct at 3666.9. **WARN SCN6** — netting applied (71→56.23) but 56.23 ≠ waterfall 54.32. **DATA SCN15** — 16 PIAMBK lines (11 inflated-base + 5 license-scale asset) inherit inflated base from over-priced contributor licenses (e.g. DOfV license Unit 15300/Base 20000 vs list 355). **BLOCKED SCN2/3** — no live Premier/Professional tags; Apex-fixture reprice hits `DerivedPricingFilter#1` (metadata confirms 0.30/0.20). **BLOCKED SCN12** — 0 non-USD first-renewal maint lines. Guards HELD: SCN1 (71) / SCN4 (60.75) / SCN11 (72.77 not re-netted) / SCN13 (per-unit) / SCN14 (gold idempotent) + 152 unit tests 100%.
- **2026-07-12** — Prompt created. SC-3346-MTD untagged default live (line `04267561` $0→60.75). SC-3346-RNM1 3-component renewal fix deployed (86/86 tests); smoke-proven on born-line `UnitPrice`: 65.09 / 60.37 / 58.20 / 76.57. Flagged SC-3346-ASSET data-quality issue.

---

## ROLE & MISSION
You are a **DPP/maintenance-pricing QA agent** validating the live derived-maintenance feature on **FortraUAT**.
Exercise **every scenario in §SCN** against **real UAT data** (or minted fixtures), snapshot the oracle **before and
after each reprice**, and produce a defect-grade HTML report. Do not fabricate values; do not change configuration
or the pricing procedure. **Authorized writes** = the **Force-reprices** the steps say to run; the **`scripts/apex/`
fixtures** (§DATA-B, savepoint-protected); the **renewal-generation invocable** (`f04_initiateRenewal.apex`); the
**`RenewalMaintenanceProvisionService.provision(quoteIds)`** conversion (via `sf apex run`, on a fixture/test
renewal quote only); and **REST-adding a `Maintenance Type Defn` QLIA** for the untagged-tier scenario (Apex DML is
blocked on the managed QLIA — use `sf data create record`). **Nothing else. Delete nothing.**

## GROUND RULES
1. **Org:** `FortraUAT` (`-o FortraUAT` on every `sf`). **Active procedure = `Rev_Mgmt_Default_Pricing_Procedure`
   V25** — re-verify it is sole-active before you start (see §REPORT header query). **If it returns 0 active rows
   → every reprice fails with `ScaleCacheServiceException: Ensure that this procedure has at least one active
   version` → mark the run BLOCKED, note it, and retry when V25 is Active again.** (This org's V25 is being
   toggled by a concurrent workstream; it is infra, not a DPP defect.)
2. **Real data only.** Use the §DATA bindings/SOQL to find live derived-maintenance lines; if none fit a scenario,
   **mint one** with a §DATA-B fixture. Only mark **BLOCKED (no data)** if neither exists.
3. **The oracle** is the per-line SOQL snapshot in §ORACLE — capture **before AND after** each reprice and diff.
4. **⚠️ Reprice TWICE; the 2nd pass is graded.** A single Force-reprice can leave a transient net; a 2nd pass
   converges. Then assert pass 2 == pass 3 (idempotency, SC-3390). A change after convergence = FAIL.
5. **First-renewal maintenance only commits after conversion.** A first-renewal `New Maintenance` **OneTime**
   carryover is `NetUnitPrice = null` until `provision` swaps it to a **TermDefined `Renew`** born line. Run
   `provision` (§MECH) then reprice ×2. On a **fresh** platform renewal (`f04_initiateRenewal.apex`) provision
   auto-fires via the QLI-trigger queueable — still reprice ×2 and confirm the born line committed.
6. **After every reprice, check the D-18 exception log** (§CHECKS): a new `Exception_Log__c` row = a hook swallowed
   an error → FAIL to investigate even if the price looks right.
7. **Report:** color-coded HTML (PASS green / FAIL red / BLOCKED grey), one row per §SCN item, click-to-expand
   before/after evidence + the exact SOQL/commands you ran. **Do not delete any data** — list all Ids in Artifacts.

## §MECH — the exact writes
**Force-reprice a Quote (run ×2):**
```bash
QID=<quoteId>
printf '{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"%s"}}}]}}' "$QID" > /tmp/rp.json
sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "@/tmp/rp.json"   # expect "isSuccess": true; run twice
```
> `isSuccess:false` with `INVALID_PRICE_REVISION_FORMULA`, `SF-Pricing-00006 DerivedPricingFilter#1`,
> `INVALID_API_INPUT (Attribute Picklist Value ...)`, or `Ensure that this procedure has at least one active
> version` = a **pre-existing quote/config/infra defect, NOT DPP** → mark that record **BLOCKED** and pick another.

**Convert a first-renewal maintenance carryover to a priced node (then reprice ×2):**
```bash
echo "RenewalMaintenanceProvisionService.provision(new Set<Id>{'<QID>'});" | sf apex run -o FortraUAT
```
This deletes the OneTime carryover and borns a `TermDefined`/`Renew` line whose `UnitPrice` is set by the fixed
`COLAUpliftHandler` at insert (the value under test). It is idempotent (a re-run is a no-op).

**REST-add a `Maintenance Type Defn=Standard` QLIA (untagged-tier scenario):**
```bash
sf data create record -o FortraUAT --sobject QuoteLineItemAttribute \
  --values "QuoteLineItemId=<lineId> AttributeName='Maintenance Type Defn' AttributeDefinitionId=0tjWC000000096bYAA AttributeValue=Standard AttributePicklistValueId=0v6WC0000000A5WYAU"
```

## §ORACLE — the maintenance fields to snapshot (before AND after)
```bash
sf data query -o FortraUAT --json --query "SELECT Id, LineNumber, Product2.ProductCode, Product2.Fortra_Product_Type__c, \
  Fortra_Product_Type__c, PricebookEntry.ProductSellingModel.SellingModelType, PricebookEntry.IsDerived, Quantity, CurrencyIsoCode, \
  ListPrice, UnitPrice, NetUnitPrice, NetTotalPrice, Subtotal, TotalPrice, TotalLineAmount, \
  Base_Price__c, Source_List_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, \
  PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, COLACalculatedPrice__c, \
  QuoteAction.Type, QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c \
  FROM QuoteLineItem WHERE QuoteId='<QID>' ORDER BY LineNumber"
```
**The tier attribute (new-biz)** — RLM's managed QLIA does **not** support semi-join; pass explicit line Ids:
```bash
sf data query -o FortraUAT --query "SELECT QuoteLineItemId, AttributeName, AttributeValue FROM QuoteLineItemAttribute WHERE QuoteLineItemId IN ('<id1>','<id2>') AND AttributeName='Maintenance Type Defn'"
```
**Core assertions**
- **New-biz maint:** `NetUnitPrice == round(sourceBase × tierRate, 2)` before its own discounts, where `sourceBase`
  is the source license's base and `tierRate` ∈ {0.20, 0.30, 0.20}. Untagged (no MTD QLIA) but base>0 → `= base × 0.20`.
  Base-less → `NetUnitPrice = 0`.
- **First-renewal maint (post-provision, TermDefined/Renew):** `UnitPrice (== NetUnitPrice after reprice) ==
  round((SourceAsset.Price − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA_Uplift_Percent__c/100), 2)`.
  No-discount line → `= SourceAsset.Price × (1+COLA)` (the fix is a no-op there).
- **RRM (2nd+ renewal):** `NetUnitPrice == round(SourceAsset.Price × (1+COLA), 2)` — the prior discount is **NOT**
  re-subtracted. If an RRM line's net drops by ≈ its partner discount, the scope leaked = **FAIL**.

## §DATA — real UAT DPP records + SOQL to find more
**New-biz gold (SC-3346-MTD repro quote):** `0Q0WC000003JXMj` — line `04267561` (`FIM-FIM-RNM-DPEENM`, untagged) nets
**60.75** (= source subscription net 303.745 × 0.20) via the posthook default; BoKS lines `04267516/17` net **71**
(= 355 × 0.20). Re-verify these before anything else.

**First-renewal maintenance carryovers (unconverted OneTime — run `provision` then reprice ×2):**
```bash
sf data query -o FortraUAT --json --query "SELECT Id, QuoteId, Product2.ProductCode, Base_Price__c, Prior_Partner_Discount__c, \
  Prior_Discretionary_Discount__c, QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c, COLA_Uplift_Percent__c \
  FROM QuoteLineItem WHERE Fortra_Product_Type__c='New Maintenance' AND PricebookEntry.ProductSellingModel.SellingModelType='OneTime' \
  AND Quote.Quote_Type__c='Renewal' AND QuoteActionId!=null AND QuoteAction.SourceAssetId!=null AND Base_Price__c>0 ORDER BY CreatedDate DESC"
```
Known-good samples (asset price = maintenance base): quote `0Q0WC000003DKNN0A4` → **65.09**; `0Q0WC000003DLBO0A4` →
**60.37**; `0Q0WC00000379sr0AA` → **58.20**; `0Q0WC000003DGgL0AW` → **76.57** (no discount, no-op).
**Known mis-priced asset (SC-3346-ASSET):** quote `0Q0WC000003IKcr0AG` line `04267364` — source asset priced **355**
(license) → nets 372.76; **grade this row as a DATA finding, not a formula FAIL.**

**RRM (2nd+ renewal, non-regression):** find `Fortra_Product_Type__c='Renewal Maintenance'` lines with a `Renew` QA
and a prior discount; reprice and confirm the net is `SourceAsset.Price × (1+COLA)` (discount **not** re-netted).

## §DATA-B — mint DPP fixtures when no real record fits
Run a fixture (savepoint-protected — real records, not fakes), then grep the ERROR-level log for its
`✅ FIXTURE CREATED` marker (Quote Id + expected oracle). **Do not delete the fixture afterward.**
```bash
sf apex run -o FortraUAT -f scripts/apex/<script>.apex
```
- **New-biz derived-maintenance tiers:** `setupJ02DerivedTierTestData.compact.apex`; discount-on-derived-maint:
  `setupH03ManualDiscountDerivedMaintTestData.compact.apex`; base quote: `setupColaUatTestData.compact.apex`.
- **First-renewal maintenance (born-fresh, real source assets + `QuoteAction.Type='Renew'`):**
  `f04_initiateRenewal.apex`, `sc3346_confirm_rnm_renewal.apex`, or `sc3346_pathB_scaleout_owned_maintenance.apex`.
- **Multi-currency:** `setupCurrencyEurCatalogTestData.compact.apex`, `setupG03PartnerNonUsdTestData.compact.apex`.
- New fixtures follow the `scripts/apex/setup*TestData.compact.apex` shape (savepoint-protected).

## §SCN — DPP scenarios to run (each is a report row)
Grade each after §MECH ×2. Bind a real record from §DATA (or mint one).

| # | Scenario | Acceptance |
|---|---|---|
| **1** | new-biz maint — **Standard tier** | `NetUnitPrice = round(sourceBase × 0.20, 2)` before discounts (BoKS: 355×0.20 = **71**) |
| **2** | new-biz maint — **Premier tier** | `= sourceBase × 0.30` (BoKS: **106.50**) |
| **3** | new-biz maint — **Professional tier** | `= sourceBase × 0.20` |
| **4** | new-biz **untagged** New-Maint (no MTD attr, base>0) | **SC-3346-MTD:** `= base × 0.20` (Std default) — line has **no `Maintenance Type Defn` QLIA** yet prices non-zero (repro `04267561` → **60.75**) |
| **5** | new-biz **base-less** maint | `NetUnitPrice = 0` (correct — scope guard; no fabricated price) |
| **6** | new-biz **discount netting** | final net = `(sourceBase × tier) − partner − discretionary` (applied after base×tier) |
| **7** | new-biz **multi-currency** | non-USD maint prices; `ListPrice` native, `NetUnitPrice` converted; no $0 |
| **8** | **first-renewal maint** — with partner discount | post-`provision` TermDefined/Renew line: `Net = (assetPrice − priorPartner − priorDisc) × (1+COLA)` (e.g. **65.09**) |
| **9** | **first-renewal maint** — no discount | `Net = assetPrice × (1+COLA)` (**76.57**) — fix is a no-op |
| **10** | **first-renewal maint** — with discretionary | `(assetPrice − priorPartner − priorDisc) × (1+COLA)` (**60.37**) |
| **11** | **RRM (2nd+ renewal)** non-regression | `Net = assetPrice × (1+COLA)`; the prior partner discount is **NOT** re-subtracted |
| **12** | **renewal multi-currency** | non-USD renewal maint commits; interacts w/ SC-3398; flag if BLOCKED on that |
| **13** | **qty>1 no inflation** | born net is **per-unit** (`AssetNetUnitPrice.perUnit`); qty-N line's unit net = qty-1 value (not ×N) |
| **14** | **idempotency + convergence** | reprice ×3 → converges by pass 2, pass 2 == pass 3 |
| **15** | **SC-3346-ASSET data check** | flag any RNM line whose `SourceAsset.Price` is a license-scale value (renewal net inflated) — **DATA finding**, list the asset Ids |
| **16** | **D-18 clean** | zero new `Exception_Log__c` across the whole run |

## §CHECKS
- **D-18 exception log:** `sf data query -o FortraUAT --query "SELECT Source__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC"` — any `PartnerNetPricePosthook`/`COLAUplift*`/`RenewalMaintenance*` row after a reprice = FAIL.
- **Unit-test guard (static):** `COLAUpliftCalculatorTest`, `COLAUpliftTest` (the `...FirstRenewalMaintenanceNetsPriorDiscount` case), and `PartnerNetPricePosthookTest` (`loadNewMaintenanceLines_defaultsUntaggedLineToStandard`) must be green.
- **Scope guard (static):** `COLAUpliftHandler` discount-net must remain gated on `SourceAsset.Product2.Fortra_Product_Type__c=='New Maintenance'` (RRM/subs excluded).

## §REPORT
Produce a **single self-contained HTML file** (inline CSS/JS, no external assets), high-visibility and readable:
color-coded **PASS / FAIL / BLOCKED** badges, one row per §SCN item, **click-to-expand** before/after tables + the
exact SOQL/commands run, and a currency-aware expected-vs-actual column. Header: org, **procedure version**
(re-verify sole-active: `SELECT VersionNumber,Status FROM ExpressionSetDefinitionVersion WHERE
ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' AND Status='Active'`), run timestamp,
tester = Claude Code (CLI). **Artifacts section: list every Quote Id, line Id, born-line Id, fixture Id, and asset
Id used or generated — nothing is deleted.** End with a **CHANGELOG** line to append here. Save the HTML next to
this prompt (e.g. `docs/sc3346_dpp_cli_report_<date>.html`).
