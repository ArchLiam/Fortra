# V21 Validation — Per-Scenario Agent Method Brief (P1/P2 wave)

You are validating ONE scenario of the FortraUAT V21 pricing procedure. Smoke-test it on REAL UAT data,
produce a PASS / FAIL / BLOCKED verdict with a root-cause class, write evidence, and return a structured row.

## Non-negotiables
- **Org = `FortraUAT`** (always `-o FortraUAT` / `--target-org FortraUAT`). The `uat` alias is a DIFFERENT
  (5sInfusion) org — never use it.
- **Active procedure = `Rev_Mgmt_Default_Pricing_Procedure` V21** (design `9QBWC0000000oWH4AY`, context
  `SalesTransactionContextExt_v2` v23). Confirmed Active 2026-06-29.
- **VALIDATION ONLY. NO deploys, NO version activate/deactivate, NO edits to the procedure / flows / Apex /
  metadata / decision tables.** Creating *test data* via Apex fixture scripts + REST is allowed and expected.
- **Retrieve LIVE before trusting local source** — repo copies drift. Query the org for actual field values.
- Put all evidence/fixtures under `Data/pricing-v21-validation/` (logs, payloads, screenshots).

## The #1 trap: a malformed fixture looks like a procedure defect
A wrong seed value makes a CORRECT V21 look broken. **A mismatch is NOT a defect until you have proven the
input data was valid AND the procedure's branch ran on the intended inputs.** If you cannot prove the data
was correct, the verdict is **BLOCKED (data unverified)**, never FAIL.
- **Positive control first:** before trusting a fixture, price a KNOWN-GOOD existing record through V21 and
  confirm it matches. If the control passes but your fixture fails → suspect the fixture, not the procedure.
- **Prefer existing/cloned real records over hand-built inputs.** Query Quote/QuoteLineItem/Order/OrderItem/
  Asset/PricebookEntry for a record that already matches the scenario's `test_setup`. Use it if found.
- **Known harness artifact (CRITICAL):** the headless place/reprice API on **Apex-inserted** lines often does
  NOT hydrate list→NetUnitPrice the way the UI "Add Products" path does — producing spurious $0 nets. If a
  FRESH fixture line nets $0/null, SUSPECT THIS FIRST. Confirm the mechanism on a real UI-priced record; if
  the only failing evidence is a headless Apex-inserted line, the verdict is **BLOCKED**, not FAIL.

## Root-cause class (assign exactly one on any mismatch)
- `PROCEDURE-DEFECT` — inputs correct, intended branch ran, produced the wrong number → V21 step is at fault.
- `ORG-CONFIG-DEFECT` — wrong number traces to missing/incorrect config a real UI user would ALSO hit
  (e.g. a product genuinely missing a required pricing attribute / decision-table row).
- `TEST-DATA-ARTIFACT` — the fixture was malformed / the branch never ran / ran on wrong inputs. FIX the
  fixture and RE-RUN before recording a final verdict.
- `EXPECTATION-ERROR` — the catalog's expected value was wrong. FIX the expected value and RE-RUN.
- `N-A(pass)` — scenario passed.
Only `PROCEDURE-DEFECT` / `ORG-CONFIG-DEFECT` are reportable defects. Distinguish *missing-config-the-
scenario-exposes* (real) from *missing-config-the-fixture-forgot* (artifact): would a real sales rep building
this in the UI have hit the same gap? Yes → real; UI would have populated it → artifact.

## Test-data waterfall (in order)
1. **Find existing UAT data** matching `test_setup` (SOQL). Many prior P0 PASS rows point at real priced
   records you can reuse as controls — read sibling rows in `Data/pricing-v21-validation/rows/*.json`.
2. **Use the most appropriate existing fixture** in `scripts/apex/` (run with
   `sf apex run -o FortraUAT -f <path>`, then grep the debug log for the ERROR-level marker line):
   - `setupColaUatTestData.compact.apex` — partner/Discount NEW quote (COLA/DPP, partner+billing-partner).
   - `setupCancelQuoteTestData.compact.apex` — convert-ready Cancellation Quote (Qty −1, CancelNetUnitPrice__c).
   - `setupCancelOrderTestData.compact.apex` — Cancellation Order (Qty −1, asset-net stamped).
   - `setupPowerConvertQuoteTestData.compact.apex` — high-qty Power convert quote.
   - Plus the ~22 prior `setup*TestData.compact.apex` scripts (one per earlier scenario) — reuse if the cell
     matches (e.g. `setupTermDefinedConvertTestData`, `setupRegionalServicesTestData`,
     `setupCurrencyEurCatalogTestData`, `setupJ02DerivedTierTestData`, `setupH02ManualPercentDiscountTestData`).
3. **If none fits, WRITE a new fixture** `scripts/apex/setup<Scenario>TestData.compact.apex` (house style below).
4. After data exists, **run pricing** (headless reprice recipe below; else documented UI convert/reprice),
   then **query the resulting field values** to assert actual vs expected.

## Reusable standing records (reuse, do not mutate beyond required-field backfill)
- Account "Fortra, LLC - Test" `001WC00000XiZP4YAN`.
- Opportunities `006WC00000RPVp3YAH`, `006WC00000OE0NKYA1`; EUR Opp `006WC00000QnybxYAB`.
- Live pricebook = **"Fortra Price Book"** (`Pricebook2.IsActive=true`). "Standard Price Book" is INACTIVE —
  never pick a PBE whose parent book is inactive. Pick PBEs with a non-zero correct list in the right currency.
- Positive controls: BoKS derived demo Quote `0Q0WC000003FKRJ0A4` (license 355 / new-maint 71 = 0.20×355);
  USD partner E-02 quote `0Q0WC000003FO1u0AG` (Net=List×0.85); EUR catalog G-01 quote `0Q0WC000003AaoT0AS`.

## Headless reprice recipe (Force-reprice through V21)
Write a body file (per-scenario unique) then POST it:
```
# body (Quote example; use "Order" for orders):
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"Quote","method":"PATCH","id":"<RECORD_ID>"}}}]}}

# discover API version:  sf org display -o FortraUAT --json | jq -r .result.apiVersion   (use v60+; v64/v67 work)
sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" \
  --method POST -o FortraUAT --body "$(cat <bodyfile>)"
# success = isSuccess:true, errorResponse:[]. A calc ERROR is a SETUP problem to resolve, not a FAIL of V21.
```
Then query outputs, e.g.:
`sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,EndDate,Source_List_Price__c,Pre_Partner_Price__c,Base_Price__c,Partner_Pricing_Source__c,COLACalculatedPrice__c FROM QuoteLineItem WHERE QuoteId='<q>'"`
(For orders use OrderItem; reprice BEFORE Activate; for converts honor StartDate/BillToContact/Bill+Ship Place
+ address text/Account Type/DB_DUNS__c preconditions.)

## Explainability / preflight gate (MANDATORY before asserting outputs)
Preflight — prove the fixture is valid AND matches `test_setup`. Do not assert until all pass:
- Product has expected `Fortra_Product_Type__c`, ProductSellingModel/SellingModelType, and any pricing
  attributes the branch needs (derived/maintenance attr, Attribute_Price_Mode__c, etc.).
- PBE active, parent book active, matching CurrencyIsoCode, non-zero correct list ($0 PBE → silent $0).
- Renewal/cancel/derived: the source Asset/AssetActionSource has the expected positive NET.
- Scenario-required fields set: partner (PartnerAccountId / Partner_Pricing_Model__c / PartnerDiscountPercent),
  currency, Deal_Type__c / GSW__c, term/proration fields, QuoteAction/OrderAction Type for renew/cancel/amend.
- Record is priceable: synced where required; CalculationStatus reaches CompletedWithPricing, not error.
Explainability — confirm WHICH branch fired by inspecting the gating fields on the QLI/OI after reprice
(ItemPricingSource, SellingModelType, IsContracted, QuoteTypeText__c, Fortra_Product_Type__c, Deal_Type__c,
Attribute_Price_Mode__c, ItemIsDerived__std, AllowRegionalPricing__c, COLA_Uplift_Percent__c, GSW__c) and the
intermediate stamps (Source_List_Price__c, Pre_Partner_Price__c, Base_Price__c, COLACalculatedPrice__c).
If the trace shows the branch never ran / ran on wrong inputs → data/route wrong, NOT V21.

## Config / parity scenarios (no fixture needed)
Some scenarios are about org-wide config or quote↔order parity, not a single priced line — validate by
querying existing records + the proc/context metadata; do NOT build a DML fixture. Examples: context-version
parity, inactive-version delete block, stale category totals, derived-family inconsistency, multi-year COLA
inertness, non-derived exclusion from derived filters. Read the relevant prior P0 row + memory ticket first.

## Apex fixture house style (copy the four reference scripts)
- Target FortraUAT; first-line comment = what it builds + scenario id(s).
- `Savepoint sp = Database.setSavepoint();` ... on exception `Database.rollback(sp); throw e;` (no orphans).
- `Database.DMLOptions dml; dml.DuplicateRuleHeader.AllowSave=true; dml.DuplicateRuleHeader.RunAsCurrentUser=true;`
  on every insert.
- Uniquify with `TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + random` so parallel agents don't
  collide; only write unique fields (DB_DUNS__c) when blank.
- Reuse the standing records above; clone known-good Contact/Place templates for required+custom fields.
- Emit ONE ERROR-level marker line with the scenario id + clickable record URL(s).
- Hoist local var declarations above loops (team treats per-iteration decls as a heap concern).
- QuoteLineItemAttribute / OrderItemAttribute are managed/virtual: insert via REST
  (`/sobjects/QuoteLineItemAttribute`), NOT Apex DML (Apex errors "use insertImmediate").

## Output (do BOTH)
1. Write your row to `Data/pricing-v21-validation/rows/<id>.json` with fields: id, category, name, priority,
   verdict (PASS|FAIL|BLOCKED), rootCause (PROCEDURE-DEFECT|ORG-CONFIG-DEFECT|TEST-DATA-ARTIFACT|
   EXPECTATION-ERROR|N-A(pass)), dataSource (existing|named-script|new-script|config-query), preflight
   (pass|fail|na), expected, actual (REAL numbers), evidence (record URL / query output / log marker),
   defectStep (responsible V21 step if defect), proposedFix (described, NOT applied), regression (ticket if
   provenance match), notes, verdict_reason.
2. Return the SAME object as your structured result.

Never fabricate a PASS or downgrade to a static check. A scenario that genuinely cannot be smoke-tested
(no data, no buildable fixture) is BLOCKED with the exact blocker. When in doubt, suspect the fixture before
the procedure → BLOCKED, not FAIL.
