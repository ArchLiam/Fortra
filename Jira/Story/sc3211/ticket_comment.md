## SC-3211 — Pre-deploy report (FortraUAT)

### Pre-fix state classification (FortraUAT, v2 Active)

**Defects confirmed in the deployed Flow XML:**

1. **Decision condition #5 references the wrong MyCap field.** Currently `$Record.MYCAP__c` (OrderItem-level Checkbox). Per Open Question #1 resolution, must be `$Record.Order.MyCap__c` (Order-level Checkbox). The org has *three* MyCap-like fields with different casing (`OrderItem.MYCAP__c`, `Order.MyCap__c`, `Quote.Mycap__c`) — recommend a separate cleanup ticket to standardise; out of scope here. Quote → Order propagation was spot-checked across 9 recent orders (4 MyCap=true, 5 MyCap=false) and matched in every case — propagation is wired and functional.

2. **`Perpetual_Set_Dates` recordUpdates writes `Start_Date_Calculated__c = $Record.ServiceDate` and `End_Date_Calculated__c = $Record.EndDate`** — i.e., the Non-Qualifying mapping. Per Requirements + AC #1–#3 + HLD pseudocode + the Notes section ("OrderItem.Start_Date_Calculated__c and OrderItem.End_Date_Calculated__c are used to keep them null as Workday expects them to be null"), both fields must be `null` on the qualifying branch.

The Non-Qualifying branch matches spec exactly and was not modified — no regression risk to AC #6.

### Spec vs. Build Instructions defect (in this ticket)

The **Build Instructions → Step 1 lines 3–4** and its accompanying XML snippet specify `$Record.ServiceDate` / `$Record.EndDate` for `Start_Date_Calculated__c` / `End_Date_Calculated__c` on the qualifying branch. **These are the Non-Qualifying values** and they contradict the Requirements, all four ACs, the HLD pseudocode, and the Notes section, which uniformly require `null` for these two fields on the qualifying branch. The Spec wins and the implementation reflects that.

**Recommendation to ticket owner:** correct Build Instructions Step 1 (lines 3 and 4) and the embedded XML snippet to write `null` for `Start_Date_Calculated__c` and `End_Date_Calculated__c` on the qualifying branch. As written, the Build Instructions reproduce the very bug the ticket exists to fix.

### Final decision element MyCap reference

Changed from `$Record.MYCAP__c` → `$Record.Order.MyCap__c` per the resolution to Open Question #1.

### Date-null technique

The qualifying branch nulls `Start_Date_Calculated__c` / `End_Date_Calculated__c` by referencing a private Flow Variable resource of type Date with no default value (`NullDate`). `$GlobalConstant.EmptyString` is not valid for Date inputs and an empty `<dateValue>` fails XSD validation — a null-initialized Date variable is the supported Flow pattern.

### Deploy status

**v3 Active in FortraUAT** as of 2026-05-29 (Deploy Id `0AfWC00000G580X0AR`). v2 demoted to Obsolete; v1 was already Obsolete. The three edits described above are now live.

### Per-AC validation outcome

The validation plan is documented in `data/sc3211/validation_results.md` and should now be executed against v3:

- AC #1: re-save 2 named fixtures (`0000370091`, `0000372424`); expect `Bill From=Bill To=Order.EffectiveDate`, `Start Calc=End Calc=null`.
- AC #2: re-save 3 named fixtures on MyCap=true Orders (`0000563869`, `0000563872`, `0000563873`); expect same shape as AC #1.
- AC #3: validated by inference via AC #1 — current catalog data has zero records that match (6 AND 7) without also matching one of conditions #1–#4. Synthesising one requires Product2/PricebookEntry mutation, which §11 forbids.
- AC #4: query non-qualifying records with non-null `ServiceDate` AND `EndDate`, touch-save, expect `Bill From=ServiceDate`, `Bill To=EndDate`, `Start Calc=ServiceDate`, `End Calc=EndDate`.
- AC #5 (BillingSchedule creation): **gap recorded**. RCA's billing-schedule generation pathway is platform-managed and not directly traceable from this Flow. Defer to a RCA-aware operator.
- AC #6: same fixtures as AC #4; compare pre-fix vs post-fix.
- AC #7: **pass by static inspection** — only one Flow XML file was edited; no new flow / trigger / process was added.

### Confirmation of scope

The change is delivered entirely within `Fortra_OrderItem_Set_Dates` (decision condition #5, two input assignments on `Perpetual_Set_Dates`, and one new private `<variables>` resource for the null-Date pattern). No new automation. Non-qualifying branch untouched.

### Follow-ups surfaced during diagnosis (not in scope for SC-3211)

1. **Quote → Order MyCap propagation** — spot-checked and consistent in sampled data. AC #2 in isolation can pass even if the upstream propagation regresses; recommend a separate parent-level AC or smoke test on the propagation logic.
2. **One-Time PSM products with non-Perpetual Family** (e.g. `Family = New Maintenance`, `PSM = One Time`, `Rev_Category = RC_42000`) currently fall through to the Non-Qualifying branch. If Workday treats *all* one-time lines as needing perpetual-branch dates, this is a separate defect — owned by Product2 tagging or the qualifying-condition design, not this Flow.
3. **Three-way casing of MyCap** across OrderItem / Order / Quote — latent footgun.
4. **Dead `Tk` formula in the Flow** — declared, never referenced. Out-of-scope cleanup candidate.

### Files (for reviewer)

Local artifacts under `data/sc3211/` in the working repo:
- `retrieve/flows/Fortra_OrderItem_Set_Dates.flow-meta.xml` — edited XML, ready to deploy
- `diagnosis.md` — full pre-fix analysis
- `change_summary.md` — exact diff and deploy plan
- `validation_results.md` — per-AC validation plan and pre-fix observed state
