# SC-3473 — UAT Validation Test Records

**Org:** FortraUAT (`https://fortra--uat.sandbox.my.salesforce.com`)
**Fix:** TermDefined Proration writer re-added to pricing procedure **V16** (restores `PricingTermCount` derivation dropped in Nir's V12). Build: `Data/sc3473/build/`. Rollback: `Data/sc3473/backup/V160_PRISTINE.expressionSetVersion`.
**Run validation AFTER V16 is reactivated** (Quote Line Editor → Reprice All on each).

| # | Purpose | Quote | Line (QLI) | Config | Expected after reprice |
|---|---|---|---|---|---|
| 1 | **Ticket repro** (SC-3473) | [0Q0WC000002U2020AC](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC000002U2020AC/view) "Test Wren - Order Processing" | [0QLWC000003jN8P4AU](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC000003jN8P4AU/view) Abstract | TermDefined, PB=Anniversary, term=1, EndDate/PTC **null** | PTC null→**1**, EndDate derives → retry **Delete Group** = no NPE |
| 2 | **Positive control** (PTC derives) | [0Q0WC000003DLBP0A4](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC000003DLBP0A4/view) "Renewal Quote" (Draft) | [0QLWC000003iXUo4AM](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC000003iXUo4AM/view) beSECURE | TermDefined, PB=DayOfPeriod, term=1, EndDate set, PTC **null** | PTC = **1** |
| 3 | **Regression control** (must stay clean) | [0Q0WC000003A8qb0AC](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/Quote/0Q0WC000003A8qb0AC/view) "Test LJ 2026-06-16" (Draft) | [0QLWC000003fLGT4A2](https://fortra--uat.sandbox.my.salesforce.com/lightning/r/QuoteLineItem/0QLWC000003fLGT4A2/view) SECURE Exchange Gateway | TermDefined, PeriodBoundary **null** | **No** `INVALID_PERIOD_BOUNDARY`; PTC stays null (guard skips it) |

## Pass criteria
- #2 PTC = 1 → writer works.
- #3 reprices clean → guard prevents the PB-null regression.
- #1 PTC=1 + Delete Group succeeds → SC-3473 resolved.

If #3 errors → **roll back** (redeploy `Data/sc3473/backup/V160_PRISTINE.expressionSetVersion`, reactivate clean V16).
