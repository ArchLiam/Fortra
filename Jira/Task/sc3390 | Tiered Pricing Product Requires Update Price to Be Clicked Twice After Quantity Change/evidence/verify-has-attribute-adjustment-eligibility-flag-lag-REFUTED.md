# SC-3390 Adversarial Verification — CANDIDATE [has-attribute-adjustment-eligibility-flag-lag]

Verdict: **REFUTED** (as the PRIMARY click-twice driver). Real gate exists but does not LAG.

## Candidate claim
`Has_Attribute_Adjustment__c` is stamped one save-cycle behind; first reprice sees it
false → prehook skips the line (stale price stands); second reprice sees it true → tier prices.
Mechanism analogized to COLA's `Is_COLA_Overridden__c` "flag set by trigger AFTER pricing write-back."

## Decisive refutation: the flag has NO setter, so it cannot lag
The candidate's mechanism REQUIRES automation that flips the flag false→true after a save.
Exhaustive search shows no such writer exists:

1. **No Apex writes it.** `grep "Has_Attribute_Adjustment__c\s*="` across `Org Data/_src/classes` and
   `force-app` → ZERO field assignments. The only hits are a test-assert string, a doc comment,
   and the early-return message literal (`AttributeVolumePricingPrehook.cls:201`). The prehook only
   READS it (cls 182).
2. **No flow writes it.** Retrieved the 4 LIVE active QuoteLineItem RecordBeforeSave flows from
   FortraUAT (`Data/sc3390/retrieve/flows/.../flows/`): `Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values`,
   `Stamp_Maintenance_Pricing_Inputs`, `Stamp_Source_List_Price`, `Fortra_QuoteLineItem_Calculate_ARR`.
   `grep Has_Attribute_Adjustment` → 0 in all four. (Set_Services_Hourly_Rate retrieve failed, but it is
   a services-rate stamper unrelated to the flag.)
3. **No trigger writes it.** `QuoteLineItemTrigger` handlers (handleHardwareLinking, COLAUpliftHandler,
   RenewalQuoteLineHandler) — none assign it.
4. **The pricing procedure only READS it** as a gate condition (`sourceFieldName` criteria at XML lines
   972, 1066, 1146, 5834, 5928, 6008, 10708, 10802, 10882). It is never an OUTPUT of the procedure, so it
   cannot lag as a derived pricing output.
5. **Field meta:** stored Checkbox, `defaultValue=false`, no formula
   (`force-app/.../Has_Attribute_Adjustment__c.field-meta.xml`). Set once at product-config / line creation
   (RLM configurator), stable thereafter.

## The cited analogy is a DISANALOGY
- `Is_COLA_Overridden__c` IS assigned by a trigger handler: `COLAUpliftHandler.cls` lines 101, 135, 194,
  334, 362. THAT is what makes the COLA flag able to lag (trigger sets it after the in-flight context
  snapshot). `Has_Attribute_Adjustment__c` has no such setter, so the analogy does not transfer.

## Live data
- Top tiered products (CLSAAS/SEAW/SAPS/FVSS/FPTES): `Has_Attribute_Adjustment__c` = True on only 51 of
  12,295 lines; org-wide only 77 True. The flag is NOT a reliable per-product property — it is set on a
  small minority. (`sf data query` GROUP BY.)
- The symptom quote's tiered CLSAAS/SEAW lines already have the flag = **true** BEFORE any click
  (`evidence/quote-37swP-lines.txt`, `verify-...` queries). For the literal SC-3390 scenario
  (change qty on an EXISTING tiered line) the gate is already satisfied — nothing for it to "flip."

## Captured-log check (the candidate's own CONFIRM signature is ABSENT)
- The one captured place/reprice log (`log-place-04-34-13.txt`) DID hit the early-return
  `earlyReturnMessage` line 201 ("No eligible line items"), BUT its context had only 2 lines —
  `0QLWC000003bJOX4A2` (VM-BSL-RSL-BESECB) and `0QLWC000003bJOY4A2` (BI-ABS-RSS-ABSTSU) — both
  **non-tiered** products with `Has_Attribute_Adjustment__c = False` *permanently* (live query confirms).
  This is CORRECT skip behavior, not a lag. It is not the click-twice repro at all.
- No captured log shows a tiered line early-returning on click 1 then pricing on click 2 with a
  flag that became true "a cycle later." The candidate's required CONFIRM evidence does not exist in
  the corpus.

## Why this is at most a NON-FACTOR (not even contributing) for the change-qty scenario
- `Attribute_Volume` (the actual tier-match dimension) is stored as `QuoteLineItemAttribute.AttributeValue`
  ("Unit Volume"), decoupled from `Quantity` (most tiered lines have Unit Volume = null while Quantity = 1;
  `evidence/volume-binding-live-qlia-vs-quantity.txt`). Changing Quantity does not touch the eligibility
  flag and does not change Has_Attribute_Adjustment. The flag is orthogonal to the quantity change.

## Residual uncertainty
- Field history is unavailable (`trackHistory=false`), so I cannot timeline the flag with field-level
  audit. Refutation rests on the structural fact that NO setter exists (any lag needs a setter) plus the
  live-data observation that the symptom lines already carry the flag = true. For a brand-new first-add
  line the flag must come from the configurator at insert (before-save), so even the "first-add" sub-case
  the candidate reserves for itself lacks a plausible post-save setter.
