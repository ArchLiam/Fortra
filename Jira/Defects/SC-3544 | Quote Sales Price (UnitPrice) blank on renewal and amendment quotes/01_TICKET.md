# Sales Price (UnitPrice) blank / $0 on renewal & amendment quotes

- **Type:** Bug / Defect
- **Priority:** High (blocked a live training session; Marc paused training until fixed)
- **Environment:** FortraUAT
- **Reported by:** Marc DeBrey — training session, 2026-07-08
- **Owner (fix):** Liam Jeong
- **Component:** Revenue Cloud (RLM) pricing — Quote/Order line "Sales Price"

## Summary
On **renewal** and **amendment** quotes, the standard **Sales Price** field
(`QuoteLineItem.UnitPrice`) displays **blank or $0** in the Transaction Line Editor, even though the
line prices correctly (`NetUnitPrice` is populated). **New-business** quotes are unaffected — Sales
Price shows correctly there.

## Steps to reproduce
1. Open (or create) a **renewal** or **amendment** quote with at least one priced line.
2. Reprice the quote (Reprice All / save).
3. Observe the **Sales Price** column (`UnitPrice`): it is **blank / $0**, while `NetUnitPrice`
   shows the correct sold price.
4. Compare against a **new-business** quote for the same product — Sales Price populates correctly.

## Expected vs Actual
- **Expected:** Sales Price (`UnitPrice`) populated on every quote line, all quote types.
- **Actual:** Populated on new-business lines only; blank/$0 on renewal & amendment lines.

## Evidence (FortraUAT, captured 2026-07-08, lines last repriced 2026-07-07)
| Quote | Type | Base_Price__c | Pre_Partner_Price__c | UnitPrice (Sales Price) | NetUnitPrice |
|---|---|---|---|---|---|
| `0Q0WC000003Ifvp0AC` "Renewal Quote" (Marc) | renewal | blank | blank | **blank ❌** | 4573.80 ✅ |
| `0Q0WC000003F55h0AC` "Amendment Quote" (Marc) | amendment | blank | blank | **0 ❌** | 0 |
| `0Q0WC000003Ih3B0AS` (new biz, same product 5250 Integrator) | new | 2021.25 | 2021.25 | **2021.25 ✅** | 2021.25 |

## Root cause
The Sales Price field is not written by the V21 pricing engine (V21 does not read/write
`UnitPrice`). It was being populated by a **temporary before-save flow `Stamp_Sales_Price`**
(created 2026-07-06 as a display-layer stopgap). That flow stamped:

```
UnitPrice = IF( ISBLANK(Base_Price__c), Pre_Partner_Price__c, Base_Price__c )
```
and its entry criteria **skipped any line where both `Base_Price__c` and `Pre_Partner_Price__c`
were null.** Renewal/amendment lines are priced through the COLA / derived-maintenance path, which
populates `NetUnitPrice` but **not** `Base_Price__c` (an attribute-tier field) or
`Pre_Partner_Price__c` (a partner-path field) — so the flow's guard skipped them and Sales Price
was never stamped. New-business lines populate `Base_Price__c`, so they stamped fine.

## Current status / interim state
- The temporary `Stamp_Sales_Price` flow was **removed from UAT on 2026-07-08** (deactivated, then
  both versions deleted). Backup retained.
- ⚠️ With the temp flow gone, Sales Price is now blank on **all** quote types until the permanent
  fix lands. Training is paused, so no live session is affected in the interim.

## Proposed permanent fix
Populate Sales Price in the **pricing engine layer (prehook/posthook)** so `UnitPrice` is stamped
for **all quote types** from the final sold price — eliminating the source-field dependency that
broke renewals/amendments. `RegionalServicesPricingPosthook` is already the documented "last writer"
in the waterfall and is a natural home for a Sales-Price stamp step.

**Open question to confirm with business (Marc) before implementing:** what is the Sales Price
semantic on a renewal/amendment line — the **sold price** (`NetUnitPrice`) or a **pre-discount
base**? This determines the source field.

## Related / to verify
- The amendment example (`0Q0WC000003F55h0AC`) shows the line **fully zeroed** (`NetUnitPrice = 0`,
  not just `UnitPrice`). This may be a **separate** "amendment did not price at all" issue on top of
  the Sales Price gap — verify by repricing; split into its own ticket if confirmed.
- Not caused by the pricing-engine refactor (hook-thinning / SDD-compliance) — this is the
  display-layer flow specifically.
