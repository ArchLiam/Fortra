# V21 Defect Remediation — 3-Portion Split (CRITICAL + procedure-solvable only)

Scope (per direction): **only critical defects that are solvable inside the V21 pricing procedure**
(`Rev_Mgmt_Default_Pricing_Procedure`). Apex-class, data-backfill, Flow, Mule, and org-config fixes are
**deferred** (listed at the bottom). That leaves **9 procedure-step defects**, split into 3 parallel portions
of 3 — each editing a **disjoint set of procedure steps** so three Claude Code tabs can work at once.

| Portion | Theme | Defects | Step regions it owns | Brief |
|---|---|---|---|---|
| **1** | Cancel / Amend / Proration | K-01, F-12, I-03 | Stamp Base Filter (105) + new cancel-seed step, Proration cluster (97, 121-123) | `PORTION_1_CANCEL_AMEND_PRORATION.md` |
| **2** | Partner net + Currency idempotency | E-03, F-07, G-03 | Subscription Pricing One-Time branch (110-112), Stamp Base_Price (106) + Partner Discount (87-88), Currency Conversion (33-36) | `PORTION_2_PARTNER_CURRENCY.md` |
| **3** | Derived + Category totals | K-02, J-10, K-09 | COLA Uplift Net on Renewal (26), Derived Formula / Stamp Contributor Base (107, 37-43), Category aggregates (103/104/109, 116-118) | `PORTION_3_DERIVED_CATEGORY.md` |

## ⚠ The critical coordination rule — all 3 portions edit the SAME procedure
The V21 procedure is **one `ExpressionSetDefinition` metadata file** with a single Active version and a known
co-owner **oscillation** hazard. Three tabs editing it in parallel will clobber unless you follow this:

1. **One shared baseline.** ONE person retrieves the live V21 metadata ONCE into a shared branch/dir
   (`Data/pricing-v21-validation/v21_fix_baseline/`). **All three tabs start from that identical retrieve** —
   do not each retrieve at different times (the proc drifts between retrieves).
2. **Edit only your assigned steps** (table above). The portions are chosen so step regions barely overlap.
   The only adjacency to watch: the three Stamp steps **105 (P1) / 106 (P2) / 107 (P3)** are consecutive but
   are **distinct elements** — each portion owns exactly one, so a git merge is clean; the integrator just
   re-checks all three after merge.
3. **Do NOT each deploy.** Three separate version bumps = the oscillation trap (each deploy reverts the others).
   Develop on three branches, then **integrate all step edits into ONE new draft version** and deploy **once**
   (deactivate active → deploy the single combined version → reactivate in the UI). Designate **Portion 1 as
   the integrator** (or the human merges the three branches).
4. **7-tier metadata trap (do not ship the regression):** the serialized V21 metadata may show a **3-tier**
   derived formula while the live runtime executes **7 tiers**. Diff your baseline against the live runtime and
   **preserve the 7-tier formula** before the integrated deploy, or you ship $0 on Basic/Premium/Express/Expert.
5. **After the single integrated deploy,** each tab Force-reprices ITS evidence records to verify.

## Shared rules (also in each brief)
- **Org = `FortraUAT`** (`-o FortraUAT`). The `uat` alias is a DIFFERENT org — never use it.
- These are **FIX** tasks. **Retrieve LIVE before editing** (repo drifts). **Get a fresh explicit human ack
  before ANY UAT deploy / version activation.** Keep the 2 `PricingActionParameters` context bindings; never
  hard-delete versions.
- Full diagnosis + evidence: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md` (§2 matrix, §3 write-ups).
  Step skeleton: `Data/pricing-v21-validation/V21_step_skeleton.md`. Board: `V21_Defects.html`.
- Verify recipe (Force-reprice): `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place`
  body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<id>"}}}]}}`, then query the result fields.

## Deferred (NOT in these portions — not critical-and-procedure-solvable)
- **Apex-class fixes:** F-05 (AssetContractQueryHelper), E-04 (PartnerPricing V2 wiring + PPM data),
  J-04/F-02 (derived born-net — NOTE: Portion 3's **J-10** is only the *procedure half*; the full
  derived-renewal-net fix also needs this Apex born-net work), G-02/D-09 (the currency-blind **key** lives in
  `AttributeVolumePricingPrehook`, not the procedure — Portion 2's **G-03** fixes only the FX *idempotency*).
- **Data/config:** D-03 (ABA row), J-09 (PBEDP backfill), A-07 (Maintenance Type backfill), G-08 (CurrencyType FX rates).
- **Flows:** F-04 (renewal flow), K-03 (order before-save flow CPU).
- **Mule:** K-04 (Workday extendedAmount — critical, but middleware, not procedure-solvable).
- **Low-frequency procedure:** D-01 (Calculated-mode multiplier — proc-solvable but only ~1 line org-wide; add
  to a portion later if desired).
