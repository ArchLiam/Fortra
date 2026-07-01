You are fixing **3 critical pricing defects in the V21 procedure** in the **Fortra FortraUAT** org —
the Derived-net + Category-totals cluster. Two sibling tabs are concurrently editing **other steps of the same
procedure**; follow the shared-procedure merge discipline below so you don't clobber them.

## Environment & rules
- **Org = `FortraUAT` only** (`-o FortraUAT`). The `uat` alias is a DIFFERENT (5sInfusion) org — never use it.
- **Active procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **V21** — design `9QBWC0000000oWH4AY`, runtime ESV
  `9QMWC00000025LN4AY`, context `SalesTransactionContextExt_v2` v23. Confirm Active first (tooling query on
  `ExpressionSetDefinitionVersion`).
- This is a **FIX** task. **Get a fresh explicit human ack before any UAT deploy / version activation.**
- Diagnosis + evidence: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md` (§3 → K-02, J-10, K-09).
  Step skeleton: `Data/pricing-v21-validation/V21_step_skeleton.md`.

## ⚠ Shared-procedure merge discipline (all 3 tabs edit ONE metadata file)
1. **Start from the shared baseline** at `Data/pricing-v21-validation/v21_fix_baseline/` (a single live retrieve
   all tabs share — do NOT re-retrieve at a different time; the proc drifts/oscillates). If absent, ask the
   integrator (Portion 1) to create it, then branch from it.
2. **Edit ONLY your steps:** **COLA Uplift Net on Renewal** (skeleton step 26), **Derived Pricing Formula /
   Stamp Contributor Base (Pre-Discount)** (steps 37-43 + 107), and the **category aggregates/totals**
   (`Services/Software/Subscription Aggregate Price` 103/104/109 and `Total Services/Software/Subscription`
   116-118). Do not touch cancel/proration/partner/currency steps (other tabs own those).
3. **Do NOT deploy on your own.** Commit your step edits to a branch; the integrator (Portion 1) merges all
   three portions into **one new draft version** for a single deactivate→deploy→reactivate.
4. **7-tier trap (this is YOUR cluster's land-mine):** the live runtime derived formula is **7-tier**
   (Basic/Standard/Professional/Premium/Express/Premier/Expert) but the serialized metadata may show only
   **3 tiers**. **Diff the baseline against the live runtime and preserve all 7 tiers** in anything you touch —
   shipping a 3-tier formula = $0 on Basic/Premium/Express/Expert maintenance (1,031+ historical rows exposed).
   Keep the 2 `PricingActionParameters` context bindings; never hard-delete versions.
- **Verify (after the integrated deploy)** with a Force-reprice on each record, then re-query:
  `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place`
  body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<id>"}}}]}}`

## Your 3 defects

**K-02 — Missing-contributor derived line silently nets $0.** (SC-3346/3372, CRITICAL — silent mispricing)
- Cause: a derived line that resolves no priced contributor (no license on the cart) leaves `NetUnitPrice=null`,
  `ValidationResult=null`, and the header rolls up $0 with no error.
- Fix: add a **MissingContributor surfacing branch** near `Stamp Contributor Base (Pre-Discount)` / Derived
  Pricing Formula — when `Base_Price__c` / `Pre_Partner_Price__c` / `InputUnitPrice` are all null/0 on a derived
  line, set `ValidationResult=MissingContributor` (or emit a place-level error) instead of committing $0.
- Verify: Quote `0Q0WC000003FZ5N0AW` (maint-only, no license) → surfaces the error, not a silent $0;
  control J-02 (license present) still prices 71/124.25.

**J-10 — EUR + COLA + partner derived-renewal cell → $0.** (SC-3346, CRITICAL for that interaction cell)
- Cause: `COLA Uplift Net on Renewal` (step 26) is gated `DerivedPricingAttribute=false`, so derived renewal
  lines never receive the COLA net; the Derived Formula renewal branch passes `NetUnitPrice` through as 0, and
  FX then 0×0.9346=0.
- Fix: drop the `DerivedPricingAttribute=false` gate on step 26 (or set the Derived Pricing Formula **renewal**
  branch to `COLACalculatedPrice__c` when `COLA_Uplift_Percent__c IsNotNull`) so derived renewal lines commit
  `NetUnitPrice = COLACalculatedPrice__c`.
- Verify: Quote `0Q0WC000003FZN70AO` → derived EUR renewal net ≈ **3427** (not 0).
- **Coordination:** this is only the *procedure half* of the derived-renewal-net fix. The companion **born-net /
  QuoteAction** work (J-04/F-02) is an Apex task that is **deferred** — flag to the owner that J-10 alone may not
  fully populate every renewal-maint line until that Apex work lands; verify on the EUR cell above regardless.

**K-09 — Empty category groups keep stale `Total_Services__c` / `Total_Subscription__c`.** (SC-3345)
- Cause: a SUM over an empty filtered group writes nothing, so the category total keeps its stale prior value;
  there is no zero-init before the aggregates.
- Fix: add an unconditional **zero-init** for each category total (`Total_Services__c`, `Total_Software__c`,
  `Total_Subscription__c`, and `Total_Discount_Amount__c`) **before** its `…Aggregate Price` step — clone the
  SC-3345 Fix1 category-reset pattern from `DiscountPercent`; OR enable the procedure-header
  "Initialize resources with default values" toggle.
- Verify: Quote `0Q0WC000003FbGr0AK` (Software present; Services/Subscription empty) → after reprice the empty
  Services/Subscription totals = **0**, not the stale 555/999.

## Done criteria
Your 3 step edits are on a branch from the shared baseline; the 7-tier formula is preserved (diff-checked);
after the integrated deploy the 3 records reprice to expected; you confirmed **Stamp Contributor Base (107)** is
the only stamp step you touched (Portion 1 owns 105, Portion 2 owns 106). Then join the **final joint reprice**
on the shared records (BoKS demo `0Q0WC000003FKRJ0A4`, an EUR quote, a maint-only quote) with the other tabs.
