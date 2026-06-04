# SC-3171 — Update Inquiry Close Reason value "Customer - Non-Sales Inquiry" → "Non-Sales Inquiry"

## Details
- **Type:** Sub-task
- **Status:** In Progress
- **Assignee:** Liam Jeong · **Reporter:** Adam Haas
- **Parent:** [SC-3115 — Sales Cloud Hardening - Training](https://helpsystems.atlassian.net/browse/SC-3115)
- **Due date:** None · **Priority:** Undefined
- **Sprint:** CRM Sprint 14 · **Component:** SF Experience Cloud (Partner)
- **Labels:** CRM-Experience-Cloud, CRM-Sales-Cloud, LOB-Salesforce-1-UAT
- **Source ticket:** [SC-3171](https://helpsystems.atlassian.net/browse/SC-3171)

## TL;DR
On the **Inquiry** record (implemented on the **`Lead`** object), the **Close Reason**
picklist value **"Customer - Non-Sales Inquiry"** should be renamed to **"Non-Sales Inquiry"**.

- **Metadata target:** `Lead.Close_Reason__c` (picklist value label)
- The picklist value was **already changed manually** in **dp2, uat, and fulltemp** by Joe Martinez
  (2026-05-19) — *"No associated automation concerns."*
- **Not in repo source:** no `Close_Reason__c` field definition or the picklist value appears under
  `force-app/` — this was a direct in-org picklist edit, nothing to deploy from source.

## ⚠️ Testing blocker (Adam Haas, 2026-06-04 9:24 AM)
> *"I tested this morning and this is not working. I can not move the inquiry status to 'closed'
> without setting a close reason but close reason can not be updated until the [inquiry] is closed.
> Consequently there is no way to update the status to closed or to update the closed reason.
> Perhaps try a default closed reason of 'Not Closed'."*

The rename itself landed, but testing surfaced a **chicken-and-egg dependency** independent of the
label change:
- Status → **Closed** requires a Close Reason to be set, **but**
- Close Reason can't be edited until the inquiry is **Closed**.

→ Neither the status nor the close reason can be updated. **Suggested fix:** introduce a default
Close Reason value of **"Not Closed"** so the record can transition out of the deadlock.

This is the open item for SC-3171 — the picklist relabel is done. The close/reason interlock has now
been **root-caused** (see the Deep research section, §4 below): it is a **logic bug in the
`Prevent_Close_Reason_When_Not_Closed` validation rule** (an `OR` that should be an `AND`, making the
condition always true) — **not** the rename, and **not** the dependent-picklist alone. Adam's
suggested *"Not Closed"* default does **not** fix it; the fix is to correct that one validation rule.

## Change requested
| Field | From | To |
|---|---|---|
| `Lead.Close_Reason__c` (Inquiry Close Reason) | `Customer - Non-Sales Inquiry` | `Non-Sales Inquiry` |

## Comments
| When | Who | Note |
|---|---|---|
| 2026-05-19 10:55 AM | Joe Martinez | Manually changed in **dp2, uat, and fulltemp**. No associated automation concerns. |
| 2026-06-04 9:24 AM | Adam Haas | Tested — relabel done, but the **status⇄close-reason interlock** blocks closing an inquiry. Suggests a default of **"Not Closed"**. (see blocker above) |

## Deep research — what SC-3171 is really accomplishing

### 1. What the ticket accomplishes (in one paragraph)

SC-3171 is a **picklist-value label rename** on the standard Lead object — which in this Fortra Sales Cloud org is **labeled "Inquiry" / "Inquiries"** — changing the `Lead.Close_Reason__c` value **"Customer - Non-Sales Inquiry" → "Non-Sales Inquiry"**. It is pure **data-hygiene / label cleanup**: a clearer close-disposition for BSI reps classifying inquiries that are not sales opportunities, dropping the redundant `Customer - ` prefix. It is one sub-task in epic **SC-3115 "Sales Cloud Hardening - Training Follow-up Items"** (the post-training Inquiry-management cleanup backlog, Critical, overdue 2026-05-18). The rename itself is small and complete; the ticket's open risk comes from a *separate* status↔close-reason deadlock Adam Haas surfaced, which is independent of the rename but lives in the same Inquiry close-lifecycle.

### 2. The Inquiry (Lead) close model

**`Close_Reason__c`** (label "Close Reason") — type Picklist, `restrictedPicklist=false`, **`dependentPicklist=true`, `controllerName=Status`**, **no default value** (`defaultValue=null`, no value flagged default), uses an inline `valueSetDefinition` (not a GlobalValueSet). All 7 values carry `validFor='BAAA'`, which decodes (bytes `[0x04,0x00,0x00]`, bit index 5) to **valid only when `Status = Closed`** — so no Close Reason value is even selectable until the Inquiry is Closed.

| `Close_Reason__c` value (all active) | Note |
|---|---|
| Bad Contact Info | |
| **Non-Sales Inquiry** | **← the SC-3171 renamed value** (was "Customer - Non-Sales Inquiry") |
| No Response | |
| Not in Target Market/Buyer | |
| Not Interested | |
| Not Right Timing | |
| Working Existing Inquiry | |

There is **no "Not Closed" value** and **no default**.

**`Status`** (label "Inquiry Status") — type Picklist, `restrictedPicklist=false`, **`dependentPicklist=false`, `controllerName=null`** (it is the *controller*, not closed-restricted), `nillable=false`, **default `New`**.

| `Status` API value | Note |
|---|---|
| New | default |
| Pending_Resolution | underscore API name |
| Assigned | |
| Working | |
| Qualified | `converted=true` |
| Closed | controlling value that unlocks all Close Reason values |

### 3. Status of the rename — complete and automation-safe

- **Complete in UAT.** Joe Martinez (2026-05-19) manually applied it in **dp2, uat, and fulltemp**; live describe confirms exactly **7 active values**, with **"Non-Sales Inquiry" present** and **"Customer - Non-Sales Inquiry" absent**.
- **Zero residual.** Metadata API field XML (which *does* surface inactive values via `<isActive>false</isActive>`) shows **no inactive entries** and the string "Customer" nowhere. Not backed by any GlobalValueSet (all 25 enumerated; none backs this field), so the 7 inline values are authoritative and complete.
- **Not referenced by name in automation.** Independent verification scanned all 382 unmanaged Apex classes + 9 triggers (client-side text scan), all 10 Lead validation-rule formulas/messages, and retrieved org flows — **zero hits** for the old string, the new string, or even the `Close_Reason` field. The two close-reason validation rules reference the *field* (`ISBLANK(TEXT())`, `ISCHANGED()`), never a value literal, so the rename cannot break them. Joe Martinez's "No associated automation concerns" is **confirmed for the value rename**.
- **Not in `force-app/` source** — it was an in-org picklist edit; nothing to deploy for the rename itself.
- *Data nuance:* the new value "Non-Sales Inquiry" currently has **zero stored records** (the old value also has zero) — valid but not yet exercised in data.

### 4. The real blocker (Adam Haas) — root cause

Adam's 2026-06-04 report — *"cannot move the inquiry status to Closed without a close reason, but close reason cannot be updated until it is closed"* — is a **genuine, independently-confirmed hard deadlock** caused by **two active Lead validation rules** (not a layout/FLS read-only gate, not the rename). Both formulas below were re-pulled directly from FortraUAT at write time.

**Half 1 — cannot Close without a Close Reason.**
Rule **`Require_Closed_Reason`** (Id `03dWC000000rFLtYAM`, Active), `errorConditionFormula`:
```
ISPICKVAL(Status, "Closed") && ISBLANK(TEXT(Close_Reason__c))
```
Message: *"Please select a Closed Reason before setting the status to Closed."* — **correct / intended.**

**Half 2 — cannot edit Close Reason (at any status).**
Rule **`Prevent_Close_Reason_When_Not_Closed`** (Id `03dWC000001nHtZYAU`, Active), `errorConditionFormula`:
```
AND( ISCHANGED(Close_Reason__c), OR((TEXT(Status) != 'Closed'),(TEXT(Status) != 'Working')) )
```
Message: *"A Close Reason can not be updated when the inquiry status is not closed."*

**Root cause — OR-vs-AND tautology bug.** `OR(Status != 'Closed', Status != 'Working')` is **always TRUE** for every Status value (no single value can equal both 'Closed' and 'Working', so at least one inequality always holds — verified by truth table over all 6 values). The OR collapses to TRUE, reducing the rule to just `ISCHANGED(Close_Reason__c)` — it **fires on ANY Close Reason change at ANY status**, including the same save that sets Status=Closed. Intended logic was almost certainly **`AND(Status != 'Closed', Status != 'Working')`** (block edits only when Status is *neither* Closed *nor* Working) — a classic De Morgan inversion.

**The deadlock:** to close you must set a Close Reason (Rule A); setting any Close Reason trips Rule B. The two cannot be satisfied together. **Neither rule references `$Permission.Bypass_Validation_Rules`, so there is no admin bypass — the block applies to everyone.** A compounding (but not sole) factor: the dependent picklist exposes no Close Reason value in the UI unless Status=Closed.

> *Verification scope:* under the read-only mandate **no live DML save was executed** — the deadlock is proven by formula + dependency logic; Adam's report is the empirical confirmation. Profile-level FLS on `Close_Reason__c` for non-admin users was not separately audited (`updateable=true` reflects only the inspecting user).

**Adam's "default Close Reason = 'Not Closed'" suggestion does NOT resolve the deadlock.** (1) There is **no 'Not Closed' value**, and as a dependent picklist its values are valid only when Status=Closed, so a default could not legally apply at New/Working. (2) Even if a default existed, **any later edit of `Close_Reason__c` still trips the tautological `ISCHANGED` in Rule B**, and changing Status to Closed alongside a default still requires a Close Reason change that Rule B rejects. The real fix is **correcting Rule B's `OR` to `AND`** (or deactivating Rule B), not adding a default value.

### 5. Where SC-3171 sits in SC-3115

| Sub-task | Scope | Status |
|---|---|---|
| SC-3122 | Inquiry UI/UX — child inquiries + POI | DONE |
| SC-3124 | Account/contact matching SOP | TO DO |
| SC-3125 | Confirm no automation changes status on activity logged | DONE |
| SC-3126 | Document notification territory | DONE |
| SC-3127 | POI multi-select viewable-not-editable | DONE |
| SC-3169 | Fortra feedback on issues found | DONE |
| **SC-3171** | **`Close_Reason__c` value rename (this ticket)** | **In Progress** |

SC-3171 is the **label-cleanup lane** among UI/UX, SOP-documentation, and automation-confirmation siblings (epic ~55% done). Adam's blocker touches the **same Inquiry Status lifecycle** (New → Pending Resolution → Assigned → Working → Qualified → Closed) that SC-3115 item #1 (territory-mismatch → Pending Resolution) also operates on — connecting SC-3171 to the epic's broader status-lifecycle theme even though the deadlock is independent of the rename. Note: the only automation writing `Status` is the flow **`Sales_Inquiry_Territory_Assignment`** (sets `Pending_Resolution` on no-match, `Assigned` on match); **no flow or Apex reads/writes `Close_Reason__c`**.

### 6. Recommended path to "done"

1. **Acceptance criterion split** — confirm with Adam/Joe that SC-3171's *original* deliverable (the value rename) is **already met** and that the close deadlock is a **distinct defect**. Consider tracking the deadlock as its own bug under SC-3115 rather than overloading SC-3171. *(No org change.)*
2. **Fix `Prevent_Close_Reason_When_Not_Closed`** — change the `OR` to `AND`:
   `AND( ISCHANGED(Close_Reason__c), AND(TEXT(Status) != 'Closed', TEXT(Status) != 'Working') )`, or deactivate the rule if its intent is unclear. **This is a metadata/config change to UAT and requires a fresh explicit deploy/DML acknowledgement per UAT policy** ("Focus on UAT" ≠ deploy authorization).
3. **Do NOT add a 'Not Closed' default** — it does not resolve the deadlock and adds a meaningless disposition value (see §4). *(Recommend against.)*
4. **Re-test the close path live** after the Rule B fix: set Status→Closed with a Close Reason in one save, and confirm editing Close Reason on a non-Closed record still behaves as intended. **Needs a deploy-ack'd UAT change first; the test itself is DML.**
5. **Propagate the validation-rule fix** to dp2 / fulltemp / prod once validated in UAT, mirroring how the rename was propagated. **Each environment change needs its own deploy ack.**
6. **Capture Rule B in source** — Lead metadata is currently not in `force-app/`; consider retrieving the corrected rule into source control for traceability. *(Read-only retrieve is fine; committing is a repo change.)*

### 7. Open questions / needs-live-recheck

- **Regression dating:** when/by whom was `Prevent_Close_Reason_When_Not_Closed` (Id `03dWC000001nHtZYAU`) created/last-modified? Pull `CreatedDate/CreatedBy/LastModifiedDate` to confirm whether the OR-tautology predates or post-dates the rename. *(Not yet queried.)*
- **Live deadlock reproduction:** not executed under the read-only mandate; a DML save attempt (needs deploy/DML ack) would empirically confirm before-and-after-fix behavior.
- **Profile FLS on `Close_Reason__c`:** `updateable=true` reflects only the inspecting user; non-admin profile FLS was not audited and could add a separate gate for BSI reps.
- **Cross-env parity:** whether dp2 / fulltemp carry the same two validation rules (and the same OR bug) as UAT was not checked — this research targeted FortraUAT only. Joe's manual rename hit all three, but the VR state in dp2/fulltemp/prod is unverified.
- **Managed trigger `salesintelio.SalesIntel_LeadUpdate_Trigger`:** body is hidden (managed package, after-insert/after-update); cannot confirm by source that it never writes Status/Close_Reason, though nothing observed indicates it does.
- **Process Builder / Workflow Field Updates** on Lead were not separately enumerated (only Flow + ApexTrigger + ValidationRule). None surfaced, but legacy Process Builder/workflow rules were not explicitly queried.
- **'Not Closed' decision:** the ticket records only Adam's *suggestion*; the agreed resolution (fix Rule B vs. relax the requirement) is not yet decided on the ticket.
- **Component tag mismatch:** SC-3171 README lists Component "SF Experience Cloud (Partner)" while parent SC-3115 is "SF Sales Cloud" — unreconciled, though functionally the work is on the Lead/Inquiry object regardless.

> *Evidence artifacts:* [`../../../Data/sc3171/research/`](../../../Data/sc3171/research/) — incl. `lead_describe_full.json`, `vr_require_closed_reason.json`, `vr_prevent_close_reason_when_not_closed.json`, `lead_validation_rules_list.json`, `verify-1.json`, `verify-2.json`, `verify-3.json`, and `retrieve/`, `layouts/`, `flows/` subfolders.

---
_Written 2026-06-04 from the SC-3171 ticket (description + Release Comments metadata + comments).
Picklist value confirmed not present in `force-app/` — in-org manual edit per Joe Martinez.
**Deep research** added 2026-06-04 from the `sc3171-inquiry-close-reason-research` multi-agent
workflow (5 introspection + 3 adversarial-verify agents, all verdicts **confirmed**) against live
**FortraUAT** (read-only); the two validation-rule formulas in §4 were independently re-verified at
write time. Org-derived facts are point-in-time — re-check against FortraUAT before changing anything._
