# SC-3292 — v11 Defect Audit (Territory-Assignment Path)

Scope: only the SC-3292 change scope — POI Sales Territory → Opportunity.Territory__c. Not a full flow audit.

## Path traced
1. `Loop_Inquiries_to_Convert.noMoreValuesConnector` → `Get_Products_of_Interest` (SOQL: `Product_of_Interest__c WHERE Sales_Inquiry__c IN InquiriesToConvertIdsText`)
2. → `Iterate_Products_of_Interest` (loop)
3. → `Product_of_Interest_VAR_is_Blank` (decision) → `Assign_Territory_to_Opportunity` (sets `productOfInterestTerritory` = current POI's `Sales_Territory__c`) → back into the loop
4. Loop exits (either default branch when variable becomes non-blank, or noMoreValues) → `Review_Products_of_Interest_Screen` → ... → `Opportunity_Form_Screen` → `Assign_Opportunity_Fields_Default` (writes `productOfInterestTerritory` into `NewOpportunityRecord.Territory__c`) → `Assign_Opportunity_Fields_Form` → `Summary_Screen` → `Create_Opportunity`

## Defects / risks

### D1 — `Get_Products_of_Interest` has no ORDER BY (LIKELY DEFECT)
The recordLookup at [line 1063](Inquiry_Conversion_Screen_Flow.flow-meta.xml#L1063) has no `<sortField>` / `<sortOrder>`. Without it, "first value" is whatever order Salesforce returns rows in — typically Id-ascending, but **not contractually guaranteed** and not tied to any business notion of "first" (creation date, primary flag, etc.).
- Impact: Same Lead converted twice could in principle pick different POIs.
- Bigger impact: when converting **multiple inquiries together** (the flow's multi-Lead path), POIs from different inquiries mix in one collection — the "first" territory becomes arbitrary across inquiries.
- Fix: add `<sortField>CreatedDate</sortField><sortOrder>Asc</sortOrder>` on `Get_Products_of_Interest`, or whatever ordering Adam Haas actually means by "first value."

### D2 — Null POI Sales Territory ⇒ later POI wins (SPEC AMBIGUITY)
`Assign_Territory_to_Opportunity` runs unconditionally as long as `productOfInterestTerritory` is blank. If POI #1 has `Sales_Territory__c = null`, the variable is assigned null (still blank), the loop continues, and POI #2 sets it. So the effective rule is **"first POI with a non-null Sales Territory wins,"** not strict "first POI."
- Spec says "Sales Territory from related Inquiry POI (first value)." Both readings are defensible.
- Risk: if Adam meant strict "first POI" (and that POI's territory is blank → leave Opp Territory blank), this is wrong.
- Fix (if strict): re-scope the decision so the loop exits on the first iteration regardless of value, or set a separate "processed" boolean.

### D3 — Multi-inquiry convergence has no precedence rule (LIKELY DEFECT)
When the flow converts >1 Inquiry in one run, the POI collection is the **union** across all selected inquiries. The "first" POI is whichever the SOQL returns first. There is no rule like "POI from the triggering inquiry wins" or "POI from the earliest-created inquiry wins."
- Real-world impact: rare for the screen-flow path (most conversions are one Lead at a time), but the flow explicitly supports multi-inquiry batch via the `Get_same_Contact_Unit_Inquiries` branch.
- Fix: add inquiry-ordering rule or restrict the territory pick to the triggering inquiry's POIs.

### D4 — Back-button rewind doesn't reset `productOfInterestTerritory` (LATENT)
Variable is never explicitly set back to null. Screens after the loop (`Review_Products_of_Interest_Screen`, `Opportunity_Form_Screen`, `Summary_Screen`) all have `<allowBack>true</allowBack>`. If a user navigates back across the loop and the upstream selection changes (e.g., picks different inquiries via the "same Contact/Unit" merge step), the loop re-runs but the variable already holds the prior value, so the decision short-circuits and the territory **doesn't update** to reflect the new POI set.
- Hard to hit in practice but reachable. Fix: add an assignment that nulls `productOfInterestTerritory` on each re-entry to `Get_Products_of_Interest`, OR move the assignment immediately before the loop.

### D5 — Existing-Opportunity path is unchanged (SCOPE QUESTION, not a defect)
If `Is_there_any_Exisiting_Open_Opportunity` → YES branch fires and the user picks an existing Opp via `Existing_Opportunities_Screen`, the flow updates that existing Opp's relationships but **does not touch `Territory__c`**. The ticket's Assignment Component spec only mentions `NewOpportunityRecord > Territory`, so this is presumably out of scope, but worth confirming with Adam — same business reason ("populate Territory on Opportunity") arguably applies to existing-Opp re-parenting too.

### D6 — Precedence vs `Sales_Inquiry_Territory_Assignment` is undocumented (REAL)
Already noted in `README.md`. There is a second active flow on Lead (`Sales_Inquiry_Territory_Assignment` v11, id `301WC00000jiwg2YAA`) that was the original Territory source visible in the pre-fix data. Need to confirm with Adam Haas whether POI-derived (this flow) or Lead-derived (the other flow) should win when they disagree.

### D7 — Fix is unverified under v11 (PROCESS GAP)
Zero opportunities have been created under v11. Andy's four test opps from today were all created on v8/v9/v10. **Cannot call this "defect-free" without at least one v11 datapoint.**

## Verdict
Not fully defect-free. **D1 and D7 should be addressed before close**; D2/D3/D6 need a one-line clarification from Adam to know whether they're defects or by-design; D4 is latent and low-priority; D5 is a scope question.
