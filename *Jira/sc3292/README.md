# SC-3292 — Inquiry → Opportunity Conversion: Populate Territory

**Source ticket:** [SC-3292](https://helpsystems.atlassian.net/browse/SC-3292) (parent SC-3143)
**Component:** Flow — `Fortra | Screen Flow - Inquiry Conversion` (API name `Inquiry_Conversion_Screen_Flow`)
**Reporter:** Adam Haas — **Assignee:** Liam Jeong — **Owner of latest change:** Andy Kumar
**Pulled from:** FortraUAT (`liam.jeong.c@fortra.com.uat`) on 2026-05-29

## Ticket summary
Issue: Inquiry → Opportunity conversion was not populating `Opportunity.Territory__c`.
Expected solution: in the conversion screen flow, set `NewOpportunityRecord.Territory__c` = Sales Territory from the related Inquiry Product of Interest (first value).

## Files in this folder

| File | What it is |
|---|---|
| `Inquiry_Conversion_Screen_Flow.flow-meta.xml` | Active flow metadata retrieved from UAT (v11, deployed today 14:25 UTC) |
| `flow_versions.csv` | Last 5 versions of the flow with timestamps and authors — context for which version produced which test opp |
| `field_metadata.json` | `Opportunity.Territory__c` and `Product_of_Interest__c.Sales_Territory__c` describe info, plus object-mapping notes |
| `recent_converted_leads.csv` | Leads with `Opportunity__c` populated (most recent 15) — drives the test cross-reference |
| `sample_products_of_interest.csv` | POIs linked to those leads, with `Sales_Territory__c` values |
| `sample_opportunities.csv` | Opportunities those POIs roll up to, with `Territory__c` values |
| `recent_converted_opportunities.csv` | Header-only — `Opportunity.SALES_INQUIRY_LOOKUP__c` is the only inquiry-side lookup on Opp and it is unused; the lead→opp link lives on Lead/POI |
| `uat_verification_matrix.csv` | Joined POI ↔ Opp Territory comparison with PASS/FAIL/MISMATCH per row, annotated with the flow version active at create time |

## Flow review (matches ticket spec)

In the active flow v11:

- New variable `productOfInterestTerritory` (String) — [line 2324](Inquiry_Conversion_Screen_Flow.flow-meta.xml#L2324).
- Loop `Iterate_Products_of_Interest` over `Get_Products_of_Interest` (collection filtered on `Sales_Inquiry__c IN InquiriesToConvertIdsText`).
- Decision `Product_of_Interest_VAR_is_Blank` ([line 728](Inquiry_Conversion_Screen_Flow.flow-meta.xml#L728)): if `productOfInterestTerritory` is blank/null → assign; else exit loop to `Review_Products_of_Interest_Screen`. This implements **first-value** semantics — once set, later POIs do not overwrite.
- Assignment `Assign_Territory_to_Opportunity` ([line 393](Inquiry_Conversion_Screen_Flow.flow-meta.xml#L393)): `productOfInterestTerritory = Iterate_Products_of_Interest.Sales_Territory__c`.
- Final write in `Assign_Opportunity_Fields_Default` ([line 199](Inquiry_Conversion_Screen_Flow.flow-meta.xml#L199)): `NewOpportunityRecord.Territory__c = productOfInterestTerritory`.

Wiring matches the ticket's Assignment Component spec.

## UAT data observations (see `uat_verification_matrix.csv`)

Timing on the deploy is the load-bearing detail:

| Flow version | Active from (UTC) | Author |
|---|---|---|
| v8 | 2026-05-28 19:57 | Joe Martinez (pre-fix) |
| v9 | 2026-05-29 14:04:34 | Andy Kumar (first fix attempt) |
| v10 | 2026-05-29 14:18:41 | Andy Kumar |
| **v11 (Active)** | **2026-05-29 14:25:01** | **Andy Kumar** |

All four of Andy's test opportunities today were created *before* v11 was deployed:

- `test 1 no territory` 14:03:29 → ran on v8 (pre-fix) → Territory blank (expected)
- `test 1 auto territory` 14:06:17 → v9 → Territory blank
- `test 2 auto terr` 14:11:53 → v9 → Territory blank
- `test 3 auto terr` 14:21:21 → v10 → Territory populated ✅

**No conversion-flow opportunity exists yet that was created under v11.** Andy's "ready for testing" comment was at 09:22 AM; v11 went live at 14:25 PM. Worth running a fresh conversion through v11 before sign-off.

Additional pattern in older opps (v8 era): `re test 1` and `t52` have `Territory__c` set, but to a *different* Sales Territory than their POIs reference — indicates an upstream automation (Sales_Inquiry_Territory_Assignment flow on Lead is a candidate) was populating Territory by another route before the SC-3292 fix existed. The new flow's first-value-from-POI logic will overwrite that path for newly converted opps; confirm with stakeholders this is the intended precedence.

## Suggested test before closing
1. Create a Lead with a POI whose `Sales_Territory__c` is set; convert via screen flow.
2. Repeat with multiple POIs of differing territories — confirm first-value (creation order) wins.
3. Repeat with POI(s) whose `Sales_Territory__c` is null — confirm Opp Territory stays null and no error.
4. All three must run under flow v11+.
