# SC-3338 — Phase 3 Decision: Blocking validation (AC4)

**Decision (Liam, 2026-06-12):** *"Do not force it. Just quick action and screen flow is fine for now."*
→ **No new hard-blocking automation is built.** AC4 is satisfied by the existing enforcement layers + the new Phase 2 guidance modal. Phase 3 (the before-save blocking flow from 14_§3) is **descoped**.

## Why — what the investigation found (corrects 14_SOLUTION_DESIGN.md §3 / GROUND_TRUTH D4)

### 1. The originally-designed trigger was invalid for the rep path
14_§3 Option A proposed a before-save Quote flow gated on `Create_Order_from_Quote__c → true`. But live inspection of the conversion flows shows:
- **Rep UI path:** `Convert_Quote_to_Order` quick action → screen flow **`Fortra_Quote_to_Order_Conversion` v27** calls the RLM `createOrderFromQuote` action **directly** — it has **0 references** to `Create_Order_from_Quote__c`.
- **Headless path:** the after-save flow `Quote_After_Update_Create_Order_From_Quote` v2 fires on `Create_Order_from_Quote__c = true` → `createOrderFromQuote`.
So the flag drives ONLY the headless/data-load path; a before-save flow on the flag would NOT intercept the rep's actual conversion. The design's "conversion is driven by the flag" assumption was incomplete.

### 2. The conversion flow ALREADY blocks the rep-controlled fields (AC4 largely pre-satisfied)
`Fortra_Quote_to_Order_Conversion` v27 runs **10 validation gates before `createOrderFromQuote`**, each with a dedicated clear error screen:

| Gate (Decision) | Checks | Error screen |
|---|---|---|
| Validate_BillToContact | `BillToContactId IsNull` | Screen_Error_Missing_BillToContact |
| Validate_BillingAddress | `Bill_To_Place__c IsNull` | Screen_Error_Missing_BillingAddress |
| Validate_BillingStreet | `BillingStreet IsNull` | Screen_Error_Missing_BillingStreet |
| Validate_ShippingAddress | `Ship_To_Place__c IsNull` | Screen_Error_Missing_ShippingAddress |
| Validate_QuoteStatus | `Status = Accepted` | Screen_Error_Quote_Not_Accepted |
| Validate_PricingStatus | `CalculationStatus` complete | Screen_Error_Pricing_Required |
| Validate_IsSyncing | `IsSyncing` | Screen_Error_Not_Syncing |
| Validate_No_Existing_Order | no existing Order | Screen_Error_Order_Already_Exists |
| Validate_Contract_StartDate | `StartDate >=` (valid) | Screen_Error_Contract_StartDate |
| Validate_ChecklistComplete | `ChecklistValidationService` over `Quote_Checklist_Item__c` (Operations Checklist) | Screen_Error_Checklist_Incomplete |

So the rep is **already blocked with a clear, friendly message** at conversion for every field they directly control on the Quote. This is NOT the "un-noticeable blocker" — that complaint was about the *late Order-Complete* validation.

### 3. The true remaining gap = Account/Contact-resident fields
Not checked by the conversion gate: Account `Name`/`Phone`/`Type`/`DB_DUNS__c`; Contact `FirstName`/`LastName`/`Workday_MobilePhone_Device_Type__c`/`_Usage_Type__c` (both Bill-To and Ship-To); the Quote/Ship-To Contact presence (`ContactId`); Ship-To Place's Account. These are the **other-team-owned, frequently-blank** fields (per the fill-rate research).

Forcing a hard block on these at conversion would:
- edit the **core conversion flow** (highest-risk change — a bug blocks ALL conversions), and
- be the **most restrictive** option — blocking sales reps on Account data they often don't own — exactly the over-restriction the ticket's scope rule #2 warns against.

## Resulting AC4 coverage (no new automation)
The three layers together satisfy "blocked with a clear, user-friendly message — no silent blockers":
1. **Visibility (NEW, Phase 2):** the `Review_Required_Fields` modal shows the full ✅/❌ readiness incl. the Account/Contact fields, so nothing is a surprise.
2. **Conversion-time block (EXISTING):** v27's 10 gates block the rep-controlled Quote fields with clear screens.
3. **Submission-time backstop (EXISTING, UAT):** the Order-Complete validator (`OrderSubmissionValidator` + 25 active mdt rules) enforces the Account/Contact/Workday fields — and is no longer "silent" because the modal forewarns the rep.

## If revisited later (not now)
- Add a single gate to v27 for **Quote/Ship-To Contact presence** (`ContactId IsNull`) — the one clearly rep-controlled item the existing gate misses. Low scope, mirrors the existing pattern.
- Or represent the Account/Contact prerequisites as **Operations Checklist items** so the existing `Validate_ChecklistComplete` gate enforces them declaratively, no core-flow edit.
- Headless-path guard (before-save on the flag) only if data-load conversions become a concern.
