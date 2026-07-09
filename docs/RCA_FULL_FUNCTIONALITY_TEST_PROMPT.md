# RCA Full-Functionality Testing Prompt — FortraUAT (real-data, end-to-end)

> **Paste everything below the line into a fresh agent/tester session.** It drives an end-to-end validation
> of the entire Fortra Revenue Cloud Advanced (RCA) pricing + quote-to-cash engine against **real FortraUAT
> records**, and delivers the outcome as a **high-visibility HTML + JSX report** (§9), color-coded
> **PASS / FAIL / BLOCKED**.

---

## ROLE & MISSION
You are an **RCA QA agent** validating the live Fortra Revenue Cloud Advanced engine on Salesforce org
**FortraUAT**. Exercise **as many scenarios as possible** across pricing and the full quote-to-cash
lifecycle, using **real UAT data only**, and produce a defect-grade report. Do not fabricate data; do not
change configuration; the only writes you perform are the **reprices / converts / activations** the steps
below tell you to run.

## GROUND RULES
1. **Org:** `FortraUAT` (all `sf` commands use `-o FortraUAT`). Read-mostly.
2. **Real data only.** Use the bound scenario quotes in §3, or the SOQL in §4 to find a real record for any
   scenario not pre-bound. If no real record exists for a scenario, mark it **BLOCKED (no data)** — never invent one.
3. **Reprice is the core action.** Repricing is idempotent by design: **run every priced scenario TWICE and
   assert first-click == second-click** (the SC-3390 idempotency guarantee).
4. **The oracle** is the per-line snapshot in §2. Capture it **before and after** each reprice and diff.
5. **After every reprice, check the D-18 exception log** (§7.4): a new `Exception_Log__c` row means a pricing
   hook silently swallowed an error — that is a FAIL to investigate, even if the price looks right.
6. **Deliver the outcome as a self-contained HTML + JSX report** (§9) — high-visibility, color-coded
   PASS/FAIL/BLOCKED, click-to-expand evidence — **not** a plain markdown table. Populate the provided
   template with real evidence (actual field values).

## §1 — THE PRICING WATERFALL (what you are validating)
A reprice runs the shared V21 procedure `Rev_Mgmt_Default_Pricing_Procedure` + Apex hooks in this order.
Each stage writes specific fields — know which stage owns which number:

| Order | Stage | Sets / does |
|---|---|---|
| 1 | **List Price** (native `ListPrice` → `Price_Book_Entry_Decision_Table_v2`) | `ListPrice`, `Base_Price__c` from the per-currency PricebookEntry |
| 2 | **HardwareAttributePricingPrehook** | Hardware price = `ListPrice × pGroup × userTier × (1 − systemType%)` |
| 3 | **RegionalServicesPricingPrehook** | country multiplier on the **LIST** channel only (`RegionalNetUnitPrice__c`) |
| 4 | **PartnerPricingPrehookV2** | partner Discount / Guaranteed-Margin on non-derived lines (`Pre_Partner_Price__c`, `PartnerDiscountPercent`) |
| 5 | **AttributeVolumePricingPrehook** | attribute/volume tier price (`Base_Price__c` via Net Bridge) |
| 6 | **COLAUpliftPrehook** | renewal COLA (`COLACalculatedPrice__c`, `COLA_Uplift_Percent__c`, `COLA_Source__c`) |
| 7 | **ESD procedure steps** | subscription/proration → derived-maint → aggregation (zero-init before aggregates) → **FX conversion LAST** |
| 8 | **PartnerNetPricePosthook** | applies partner net to `NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount`; deferred (derived-maint) partner pricing; **now deal-aware (D-11)** |
| 9 | **QLDescriptionGeneratorPrehook** | line description |
| 10 | **CancelLineCreditPosthook** | negative-qty credit lines (`CancelNetUnitPrice__c`) |

## §2 — REPRICE + SNAPSHOT MECHANICS (exact commands)
**Reprice a Quote:**
```
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" \
  --method POST --body '{"inputs":[{"QuoteId":"<QUOTE_ID>"}]}' -o FortraUAT
```
Assert the response has `"isSuccess": true` (the CLI prepends warning lines — parse from the first `[`).

**Snapshot the oracle fields (read-only)** — capture before AND after:
```
sf data query -o FortraUAT -q "SELECT LineNumber, Product2.Name, Fortra_Product_Type__c, Quantity, \
UnitPrice, ListPrice, Base_Price__c, NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount, \
PricingTerm, PricingTermCount, PricingTermUnit, StartDate, EndDate, \
Pre_Partner_Price__c, PrehookRSNetUnitPrice__c, PartnerDiscountPercent, Partner_Discount_Percent__c, \
COLACalculatedPrice__c, COLA_Uplift_Percent__c, CancelNetUnitPrice__c \
FROM QuoteLineItem WHERE QuoteId='<QUOTE_ID>' ORDER BY LineNumber"
```
(There's also a ready-made harness: `ORG=FortraUAT Data/pricing-refactor-scratch/harness/snapshot.sh Quote <id> out.tsv`,
then `python3 Data/pricing-refactor-scratch/harness/diff.py baseline.tsv out.tsv` → `GATE PASS — 0 delta`.)

**Order reprice:** flow `Fortra_Order_Reprice` (same shape, `OrderId`). **Convert Quote→Order:** flow
`Fortra_Quote_to_Order_Conversion`. **Order snapshot:** `snapshot.sh Order <orderId>` (Order uses
`RegionalNetUnitPrice__c` + `Workday_Contract_Line_Type__c`).

## §3 — REAL UAT SCENARIO BINDINGS (the backbone — these are live quotes)
| S# | Real Quote Id | Covers | Known reference |
|---|---|---|---|
| S1 | `0Q0WC000003IIT0` | New USD baseline, one-time (6 lines) | nullPTC×2 ok on one-time |
| S2 | `0Q0WC000003GMu5` | term subscription | has `PricingTermCount=1` |
| S3 | `0Q0WC000003IKkv` | renewal COLA | COLA applied (S3 carries a known SC-3346 qty0→$0 line — expected) |
| S4 | `0Q0WC0000028bsk` | derived / new maintenance (18 lines, 17 New-Maint) | nullPTC correct for maint |
| S5 | `0Q0WC000003IKeT` | **partner Discount** (Channel-Originated, 18%) | |
| S6 | `0Q0WC0000035dGj` | **partner Guaranteed-Margin** (Reseller+Distributor, GM 28%) | 824 → **593.28** |
| S7 | `0Q0WC0000039bwH` | **Fortra-Originated, Non_Orig POPULATED** | Non_Orig 12%: 355 → **312.40** |
| S9 | `0Q0WC000003Fr77` | regional EUR | 1 regional line |
| S10 | `0Q0WC000003ICoz` | non-USD (GBP) | |
| S11 | `0Q0WC000003GMu5` | attribute-tier (Has_Attribute_Adjustment) | idempotent (SC-3390) |
| S11b | `0Q0WC000003FcrF` | EUR multi-currency | USD-base × hardcoded 0.9346 FX |
| S12 | `0Q0WC000002RK6g` | **hardware / Power** (23 lines, maxQty 20) | |
| S13 | `0Q0WC000003FapR` | **cancel / amend-remove** credit | negQty −50000 credit line |
| S14 | `0Q0WC0000028HhT` | **governor** (73 lines, 29 nullPTC) | SC-3366 stress |
| S8 | *(no real quote)* | Fortra-Originated with Non_Orig **NULL** | **BLOCKED — needs data**; covered only at unit level |

> Verify each Id still exists + is repriceable before use:
> `sf data query -o FortraUAT -q "SELECT Id, Name, Status, CurrencyIsoCode FROM Quote WHERE Id='<id>'"`.
> If an Id is stale, use §4 to find a fresh real record of the same type.

## §4 — SOQL TO FIND REAL RECORDS (for any scenario not pre-bound)
Run these against FortraUAT to pull a **real** record; pick one in a workable (Draft/editable) status:
```
-- Partner Discount quote:            SELECT Id,Name FROM Quote WHERE Partner_Pricing_Model__c='Discount' AND Billing_Partner__c!=null ORDER BY LastModifiedDate DESC LIMIT 5
-- Partner Guaranteed-Margin quote:   SELECT Id,Name FROM Quote WHERE Partner_Pricing_Model__c='Guaranteed Margin' AND Billing_Partner__c!=null ORDER BY LastModifiedDate DESC LIMIT 5
-- Fortra-Originated deal:            SELECT Id,Name,Deal_Type__c FROM Quote WHERE Deal_Type__c='Fortra Originated' ORDER BY LastModifiedDate DESC LIMIT 5
-- EUR / GBP quote:                   SELECT Id,Name,CurrencyIsoCode FROM Quote WHERE CurrencyIsoCode IN ('EUR','GBP','CHF','JPY','AUD') ORDER BY LastModifiedDate DESC LIMIT 10
-- Renewal quote:                     SELECT Id,Name FROM Quote WHERE Type__c LIKE '%Renewal%' OR RecordType.Name LIKE '%Renewal%' ORDER BY LastModifiedDate DESC LIMIT 5
-- Hardware/Power lines:              SELECT QuoteId FROM QuoteLineItem WHERE Fortra_Product_Type__c IN ('Hardware') OR Product2.Family='Hardware' GROUP BY QuoteId LIMIT 5
-- Cancel/amend (negative qty):       SELECT QuoteId FROM QuoteLineItem WHERE Quantity<0 GROUP BY QuoteId LIMIT 5
-- Activated Order w/ Assets:         SELECT Id,OrderNumber,Status FROM Order WHERE Status='Activated' ORDER BY ActivatedDate DESC LIMIT 5
-- Multi-line (governor):             SELECT QuoteId, COUNT(Id) c FROM QuoteLineItem GROUP BY QuoteId HAVING COUNT(Id)>=15 LIMIT 5
```

## §5 — PRICING SCENARIO MATRIX (run each; reprice TWICE)
For every scenario: pick the real record (§3/§4) → snapshot BEFORE → reprice → reprice AGAIN → snapshot AFTER
→ verify the **Expected** against the **oracle fields** → check the D-18 log → record PASS/FAIL/BLOCKED.

**A. List price / One-Time / Perpetual** — *S1.* `NetUnitPrice`/`UnitPrice` = catalog `ListPrice` (no discount);
one-time & perpetual lines legitimately have `PricingTermCount = null`; `TotalPrice = NetUnitPrice × Quantity`.

**B. Subscription (term + evergreen) / Proration / PricingTermCount** — *S2, S14.* Term lines carry a non-null
`PricingTermCount` (engine-only writeable — a null on a TermDefined line is the SC-3420/3411 defect);
proration reflects `StartDate`/`EndDate`; `PricingTermUnit` correct.

**C. Renewal + COLA (Line > Contract > CMDT > MyCAP)** — *S3.* `COLACalculatedPrice__c` = prior net × (1+uplift);
`COLA_Uplift_Percent__c` and `COLA_Source__c` reflect the winning tier; a manual line override wins over
Contract wins over CMDT; MyCAP = out-year floor (year-1 keeps the CMDT rate). Renewal maintenance lines are
owned by the SC-3346 derived path, not COLA.

**D. Derived / New maintenance** — *S4.* New-Maintenance lines derive net from the contributor base × tier rate
(not from list); band via `Partner_Pricing_Model__c`; middle lines must NOT price to $0 (SC-3346/3412).

**E. Partner Discount** — *S5.* `NetUnitPrice = Pre_Partner_Price__c × (1 − billingPartner Discount%)`;
`PartnerDiscountPercent` stamped; **re-reprice must NOT compound** the discount (DEF-1: base off
`Pre_Partner_Price__c`, not the already-discounted `NetUnitPrice`).

**F. Partner Guaranteed-Margin (additive, multi-partner)** — *S6.* `NetUnitPrice = ListPrice × (1 − Σ all partner
margins%)`; verify S6's 824 → **593.28** (28% total); a 0-margin partner is excluded from the sum.

**G. Fortra-Originated — Non_Orig populated AND null** — *S7 (populated 12% → 312.40).* When `Deal_Type__c =
'Fortra Originated'` the Non_Orig_* schedule applies; when a `Non_Orig_*_Pct__c` is **blank**, the engine falls
back to the standard band (owner decision — never silent 0%). **Both the prehook and (post D-11) the posthook
deferred path** must behave identically here. *(Non_Orig-NULL end-to-end = S8, BLOCKED no-data.)*

**H. Regional** — *S9.* Country multiplier applies to the **LIST** channel only → `UnitPrice`/`RegionalNetUnitPrice__c`
scaled; **NET stays catalog** (structural `TotalLineAmount ≠ NetTotalPrice` is expected); an Active regional row
with a null `Multiplier__c` must be skipped, not applied.

**I. Multi-currency (EUR/GBP/…)** — *S10 (GBP), S11b (EUR).* Non-USD lines price in the transaction currency;
today the engine prices USD then applies FX (`0.9346` for EUR) — verify the final `NetUnitPrice` equals the
expected converted value; flag any **double-FX** (corporate rate × hardcoded FX ≈ 8% under = F-09).

**J. Attribute / Volume / Tiered** — *S11.* The configured attribute volume selects a tier price; a **tier change
must reprice cleanly on the FIRST click** (SC-3390: no stale price, no reset-to-list); reprice twice → identical.

**K. Hardware / Power** — *S12.* `Hardware_Price = ListPrice × pGroup × userTier × (1 − systemType%)`; user
override > `Hardware__c` > default; on a high-qty Power line, convert must not blow CPU (SC-3447).

**L. Cancel / Amend-remove credit** — *S13.* A negative-quantity line yields a **credit** (negative
`TotalPrice`), not $0; `CancelNetUnitPrice__c` seeds the credit; a null `NetUnitPrice` on a cancel line must not
abort the whole reprice (K-01/SC-3441 null-safety).

## §6 — QUOTE-TO-CASH LIFECYCLE (beyond pricing)
Pick a clean real quote (ideally S1 or S4) and walk the full lifecycle:
1. **Configure** — add products/bundles/attributes; confirm the config saves.
2. **Reprice (Quote)** — §2; snapshot.
3. **Convert → Order** — run `Fortra_Quote_to_Order_Conversion`. Verify: an Order is created; **Power lines
   qty-split into 1 OrderItem/unit** (PowerOrderSplittingService); `Order_Line_ARR__c` apportioned per-unit (not
   N×); no CPU limit (SC-3447).
4. **Reprice (Order)** — `Fortra_Order_Reprice`; confirm Order-side prices match the Quote (dual-object parity;
   Order uses `RegionalNetUnitPrice__c`).
5. **Activate the Order** — verify Status→Activated; `EndDate`/`PricingTermCount` present on TermDefined lines
   (their absence blocks activation — SC-3411/3406).
6. **Contract** — a Contract is created/activated; not left Draft (manual-convert strands it — activate first).
7. **Workday sync** — publish/observe `Order_Completed_WD__e`; verify each line's `Workday_Contract_Line_Type__c`
   is correct (not every line FIXED AMOUNT — SC-3210/3368), `extendedAmount` = NetTotalPrice (SC-3374), and an
   **amendment** carries the original contract ID (SC-3505).
8. **Assets** — after activation, **Assets are created** (`SELECT COUNT() FROM Asset WHERE ...`); a subscription
   order completing with **0 Assets** is the SC-3415/3419 swallow defect; `Asset.ARR__c` = the apportioned line
   ARR (not N×); `AssetAction`/`AssetActionSource` present.
9. **Cancel / Amend** — amend the order to remove/reduce a line → credit line (§5-L); re-activate.
10. **Renew** — a renewal quote/opp: `Amount` non-zero where recurring; `RenewalForecastAmount` = Σ MRR×12×COLA
    (SC-3500); auto-added maintenance lines priced (not $0).

## §7 — CROSS-CUTTING CHECKS (run on EVERY scenario)
1. **Idempotency** — reprice twice; the two snapshots must be byte-identical (SC-3390). A second-click delta = FAIL.
2. **Governor** — on the 15+ line quote (S14) the reprice must complete with **no `SOQL:101` / no CPU limit**
   (SC-3366). Capture limits from the debug log if available.
3. **Currency display** — non-USD line `NetUnitPrice` and the displayed converted value are consistent (no
   double-FX; G-01/F-09).
4. **D-18 exception log** — after each reprice:
   `sf data query -o FortraUAT -q "SELECT Source__c, Hook_Phase__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC"`.
   **Any new row = a pricing hook swallowed an error** (partner/COLA/regional/hardware/attr/etc.) → FAIL and
   attach the row, even if the price looks correct. (Real-context delivery latency is ~20–40s — wait then query.)

## §8 — REGRESSION MUST-NOT-BREAK (historically fragile — always include)
| Ticket | Test | Must NOT | Check |
|---|---|---|---|
| SC-3390 | tiered attr reprice twice | reset-to-list / need 2 clicks | 1st==2nd snapshot |
| DEF-1 | partner Discount re-reprice | compound (×0.82 each pass) | NetUnitPrice stable on 2nd reprice |
| SC-3441 / K-01 | cancel line, null NetUnitPrice | $0 instead of credit / abort reprice | negative TotalPrice; reprice succeeds |
| SC-3366 | 15+ line reprice (S14) | SOQL:101 / CPU | reprice isSuccess, limits under cap |
| SC-3384 / F-09 | non-USD (+partner) reprice | USD-blind / double-FX ~8% under | converted NetUnitPrice correct |
| SC-3415/3419 | activate subscription order | 0 Assets | Asset count > 0 |
| SC-3347/3374 | Workday sync | Contract Amt ≠ Line Amt / all FIXED | extendedAmount=NetTotalPrice; line-types varied |
| SC-3420/3411 | TermDefined line | null PricingTermCount | PTC non-null; activation succeeds |
| SC-3346/3412 | derived maint middle line | $0 | net > 0 from contributor base |

## §9 — OUTCOME: HTML + JSX REPORT (mandatory output format)
Deliver the results as a **single self-contained HTML file with embedded React/JSX** — high visibility,
color-coded, scannable. **Use the ready template** [`docs/rca_test_report_template.html`](rca_test_report_template.html):
copy it, fill the `META` object and the `RESULTS` array (one object per scenario), save as
`rca_test_report_<date>.html`, and open it in a browser. Do **not** hand back only a markdown table.

**Each `RESULTS` entry (the row schema):**
```
{ id, category, scenario, record,   // id (A–L / S#), category, one-line scenario, real UAT record Id
  stage,                            // the waterfall stage it exercises (§1)
  ticket,                           // regression ref if any (e.g. "SC-3390"), else ""
  verdict,                          // 'PASS' | 'FAIL' | 'BLOCKED'
  expected, actual,                 // expected vs actual oracle values (real numbers)
  evidence,                         // proof (e.g. "reprice ×2 identical", "824→593.28")
  exceptionLog }                    // any Exception_Log__c row (§7.4), else "none" / "—"
```

**The report renders out of the box:** an overall PASS/FAIL banner + pass-rate %, big **PASS / FAIL /
BLOCKED** stat cards, a stacked pass-rate bar, status-filter chips, a most-severe-first scenario table with
color-coded status pills and **click-to-expand evidence**, a dedicated **Defects** section, and a **Blocked**
section listing each missing precondition. It is responsive and light/dark aware.

**Coverage the report must reflect:** every §5 pricing scenario (A–L), each §6 lifecycle phase, and each §8
regression must-not-break — one `RESULTS` row apiece (aim for the full ~40+ rows). Populate `exceptionLog`
from the §7.4 D-18 query per scenario — **a populated value on an otherwise PASS-looking row is still a FAIL.**

> To publish it as a shareable **Claude Artifact** instead of a local file, inline React/ReactDOM rather than
> the CDN `<script>` tags (the Artifact CSP blocks external scripts) — the JSX and structure are identical.

---
*Grounded in the live V21 waterfall + the S1–S14 golden harness (`Data/pricing-refactor-scratch/harness/`);
the harness `baselines/` hold frozen 0-delta oracles you can diff against directly. Report template:
[`docs/rca_test_report_template.html`](rca_test_report_template.html).*
