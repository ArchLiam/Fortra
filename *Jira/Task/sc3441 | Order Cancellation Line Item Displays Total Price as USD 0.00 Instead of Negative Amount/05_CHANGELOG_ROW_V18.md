# SC-3441 — Pricing Procedure Change-Log row for V18

Row to add to the **"Pricing Procedure — Change Log"** Google Sheet (next after CL-0005). Fact-checked 2026-06-25 against the live FortraUAT org + the deployed V18 artifact + the existing CL-0004/CL-0005 style. Paste-ready TSV: `05_CHANGELOG_ROW_V18.tsv` (header + one data line; paste into cell **A8**, tab = column).

| Column | Value |
|---|---|
| Log ID | CL-0006 |
| Date | 06-25 |
| Author | Liam |
| Component Type | Pricing Procedure (ExpressionSet) |
| Component Name | Rev_Mgmt_Default_Pricing_Procedure |
| Version / Build / Deploy ID | V18 |
| Change Type | New/Create |
| Environment(s) | fortrauat (UAT) |
| What Changed | Cloned active V16 → V18 via UI (metadata clone to V17 failed on a cross-slot ExpressionSetDefinitionVersion reference; V17 left Inactive). Added ONE new top-level ListGroup `CancelNetSeedContainer` at seq 13 — ahead of the seq-14 discount-base container (gate `StampBaseFilter`) and the line-total step. It holds a null-safe gate (`CancelNetUnitPrice__c IsNotNull AND NetUnitPrice IsNull`) plus two AssignmentElements writing `CancelNetUnitPrice__c → NetUnitPrice` and `→ InputUnitPrice`. Structurally identical to the working COLA-renewal NetUnitPrice writer. No existing steps changed; zero data changes. Companion components deployed separately (not in the procedure): field `CancelNetUnitPrice__c` on OrderItem + QuoteLineItem (+FLS), context-def `SalesTransactionContextExt_v2` hydration on both SalesTransactionItem nodes, and prehook `CancelLineNetSeedPrehook` in plan `Fortra_Pricing_PreHook`. |
| Why — Business / Technical Reason | SC-3441 (reporter Joe Romo): UI cancellation lines (Order 00095539, Arcus Hosting, Qty −1, ListPrice 3000) show Total Price USD 0.00 instead of the −3000 credit. The native RLM waterfall returns no priced row for a cancel line, so the `NetUnitPrice` field stays null and the line-total `NetUnitPrice × LineItemQuantity = null × −1 = 0`. Nothing seeds NetUnitPrice on a non-COLA cancel line. Correct credit = original asset NET (`AssetActionSource.NetUnitPrice` via `OrderAction.SourceAssetId`), not catalog list — 77% (1539/1999) of asset-source rows have net≠list and 907 have list 0 with nonzero net. V18 seeds the NetUnitPrice field from asset net on cancel lines before the line-total step. Native LastTransaction carryover was rejected first (OrderItem has no PricingSource field, the order context node leaves ItemPricingSource unmapped, subject asset PricingSource null). |
| Impact / Downstream Effects | **STATUS = IN PROGRESS:** V18 is deployed and active but does NOT yet produce −3000 — reprice still stalls at `StampBaseFilter` (`NetUnitPrice>0` on a still-null value, SF-BRE-00004), so the seed isn't yet reaching runtime context. Gate is tight (cancel/neg-qty only) so positive-qty, partner, COLA, regional and derived-maintenance lines are unaffected. **DUAL-ACTIVE drift recurred:** V16 was deactivated when V18 went active, but a live query 2026-06-25 found BOTH V16 (`9QBWC0000000niH4AQ`) and V18 (`9QBWC0000000o3F4AQ`) Active again — RLM runs the highest (V18), but V16 should be re-deactivated for determinism (do NOT delete — platform-blocked). UAT-only; prod is a separate procedure object (`9QAaZ00000Bj7S1WAJ`) lacking `CancelNetUnitPrice__c` — prod cutover gated. |

## Fact-check notes (workflow `wf_9f9ccd23-cb1`, 3 verifiers)
Corrections applied vs the first draft:
- **Field precision:** dropped the disputed `Currency(18,2)` — live `FieldDefinition` reports `Currency(16,2)` (metadata `<precision>18</precision>` = 16 integer + 2 decimal). Cell now just names the field.
- **Change Type** `New/Create` (no spaces) and **Version** bare `V18` — match CL-0004/CL-0005 convention; the V18 record Id `9QBWC0000000o3F4AQ` moved to the Impact prose.
- **V18 step names:** stall is at `StampBaseFilter` (gate child of the seq-14 container `StampContributorBasePreDiscount`) — the V16 names `StampContributorBaseFilter`/`QuantityPrice64` were renumbered by the clone. The MAX-clamp `FormulaBasedPricing3` is seq **36** in V18 (was 37 in V16) — but that latent warning was moved out of the row into the dossier.
- **Dropped** the "0/430k assets carry PricingSource" claim — 430,521 is the AssetAction `Type='Generate'` total, not a PricingSource distribution. Kept the architectural rejection reasons (no OrderItem.PricingSource field; unmapped order-node ItemPricingSource; subject asset PricingSource null).
- **Dual-active:** the dossier said "V18 sole active / V16 deactivated"; the **live 2026-06-25 query proves V16 is Active again** (documented drift recurrence). Row keeps the dual-active claim and cites the live query; dossier corrected to match (see README/03/HANDOFF).
- **Tightened** What Changed & Impact to CL-0004/CL-0005 density; the FINEST/Simulate-exhausted, pivot-to-direct-write, and latent-clamp details live in `03_…`/`04_…`, not the change-log row.

Live-confirmed: V18 Id `9QBWC0000000o3F4AQ`, CreatedDate 2026-06-25T04:15:46Z; V16 `9QBWC0000000niH4AQ`; both Active; V17 `9QBWC0000000ntZ4AQ` Inactive; field present on both objects.
