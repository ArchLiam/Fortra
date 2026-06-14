# SC-3338 — Phase 4 Verification & Phase 5 Prod Manifest

## Phase 4 — No-regression verification (AC5) ✅

**Change set (UAT, 2026-06-12):** only additive / non-functional metadata.
| Type | Component | Nature |
|---|---|---|
| CustomField ×6 | Quote.BillToContactId, ContactId, StartDate, Status, Bill_To_Place__c, Ship_To_Place__c | `inlineHelpText` only (non-functional) |
| Flow (NEW) | `Fortra_Quote_Required_Fields_Check` | Screen flow, read-only, **no DML / no triggers** — runs only when invoked from the action |
| QuickAction (NEW) | `Quote.Review_Required_Fields` | Launches the flow |
| FlexiPage | `Quote_Record_Page` | One entry added to highlights `actionNames` |
| Layout ×2 | `Quote-Quote Layout`, `Quote-Amendment Quote Layout` | One `platformActionListItems` added (inert/fallback — dynamic actions override) |

**No Apex, triggers, validation rules, or core flows were modified** (git-confirmed). Therefore nothing can regress existing Apex/test/integration/flow automation.

**Apex test guard (unchanged classes, run as evidence):**
```
OrderSubmissionValidatorTest  — 6/6 Pass
QuoteToOrderFieldMapperTest   — 8/8 Pass
Tests Ran 14 · Pass Rate 100% · Fail Rate 0%   (run 707WC00002yI2NU, 2026-06-12)
```

**Remaining human check (cannot run headlessly):** open a Quote → **Required Fields Check** action → confirm the modal renders the grouped ✅/❌ list + header. Data layer already validated on live Quotes (`03_PHASE2…`).

## Phase 5 — Prod deploy manifest

Because AC4 added **no** UAT-only blocking automation, the **entire SC-3338 build is prod-safe**. No piece is held back for the SC-3291 machinery promotion.

**Deploy to FortraProd (after Wren UX sign-off + explicit deploy ack):**
1. `CustomField` ×6 (Quote help text) — `force-app/main/default/objects/Quote/fields/{BillToContactId,ContactId,StartDate,Status,Bill_To_Place__c,Ship_To_Place__c}.field-meta.xml`
2. `Flow:Fortra_Quote_Required_Fields_Check` — `force-app/main/default/flows/…`
3. `QuickAction:Quote.Review_Required_Fields` — `force-app/main/default/quickActions/…`
4. `FlexiPage:Quote_Record_Page` — deployable copy at `Data/sc3338/phase2/flexi/unpackaged/` (verify the highlights `actionNames` merge cleanly against prod's current list; prod may differ)
5. (Optional) `Layout:Quote-Quote Layout` + `Quote-Amendment Quote Layout` action adds — `Data/sc3338/phase2/layout/unpackaged/` (only if prod ever disables dynamic actions; otherwise skip)

**Pre-prod checks:**
- Confirm the 6 Quote fields exist in prod (they should — standard + carried customs). Retrieve-merge help text rather than overwriting if prod help text differs.
- Confirm the `Quote_Record_Page` FlexiPage exists in prod and re-merge the action into prod's actual `actionNames` (don't blind-deploy the UAT copy).
- The flow references Account/Contact/Places__c/Quote fields — all exist in prod (the modal has **no** dependency on the UAT-only `Order_Submit_Validation__mdt`/`OrderSubmissionValidator`).
- Deploy by `--source-dir` / `--metadata` (avoid the pre-existing stray `classes/rca_diagnostic.cls-meta.xml` that breaks full-project scans).

**Do NOT deploy:** the stale local `force-app/.../Fortra_Order_Submission_Check.flow-meta.xml` (SC-3366 regression); any `Order_Submit_Validation__mdt` / `OrderSubmissionValidator` (UAT-only, prohibited in prod).

## Status summary
| AC | Status |
|---|---|
| AC1 inventory | ✅ Done (dossier `10_`–`15_` + CSV) |
| AC2 help text | ✅ Deployed UAT · prod-ready |
| AC3 guidance modal | ✅ Deployed UAT · prod-ready |
| AC4 blocking | ✅ Met via existing v27 conversion gates + modal (visibility) + Order-Complete validator (backstop); no new block per decision `04_` |
| AC5 no regressions | ✅ Verified (no Apex/flow edits; tests 14/14 green) |
| UX review w/ Wren | ⏳ Pending (Phase 0 — copy + grouping + Start Sync overflow + prod timing) |

**Net open items:** (1) Wren UX sign-off on help-text copy + modal grouping; (2) manual modal click-test; (3) decide Start Sync overflow (bump visible actions 7→8?); (4) prod deploy on go.
