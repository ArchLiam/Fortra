# Multi-Currency FX-Removal — Execution Runbook (SC-3384)

**Round 6 · Tab 3 · 2026-07-09 · owner-executable.** Native V21 **canvas** change — the canvas edits + UI-reprice
gate are owner actions (Claude cannot touch the pricing canvas). Diagnosis, design, and preconditions below are
verified from live data + a V21 wiring analysis (workflow `w8twjkmnw`). **Not committed / not applied.**

## TL;DR
The 4 hardcoded-FX "Currency Conversion" steps (V21 seq 38–41) **double-convert** the net waterfall: `seq 2`
already resolves the per-currency PBE (currency-aware), then seq 38–41 multiply those already-converted values by a
hardcoded FX ladder again. It's **0-delta today** only because every non-USD PBE was defined as `USD × the same
constant` (e.g. EUR 3434.655 = 3675 × 0.9346). Fix = **neutralize the ladders to 1.0 (reversible) → prove 0-delta →
delete the 4 steps.** Non-urgent (no live mispricing), but a real latent-correctness fix.

## What's wrong (precise)
`seq 2` PriceBookEntries (`actionType=ListPrice`, DT `Price_Book_Entry_Decision_Table_v2`, `CurrencyIsoCode` as a
match key) seeds `ListPrice` **and** `NetUnitPrice`/`ItemNetTotalPrice` from the per-currency PBE. Then:

| seq | element | reads | writes | formula |
|---|---|---|---|---|
| 38 | CurrencyConversionNetUnitPrice | NetUnitPrice | **NetUnitPrice** | NetUnitPrice × FX-ladder |
| 39 | CurrencyConversionUnitPriceDisplay | Base_Price__c | **InputUnitPrice** | Base_Price__c × FX-ladder |
| 40 | CurrencyConversionNetTotalSubtotal | ItemNetTotalPrice | **ItemNetTotalPrice** (→ NetTotalPrice) | ItemNetTotalPrice × FX-ladder |
| 41 | CurrencyConversionTotalLineAmount | TotalLineAmount | **TotalLineAmount** (→ ItemSubtotal) | TotalLineAmount × FX-ladder |

FX-ladder (identical in all 4): `IF(EUR 0.9346, GBP 0.7874, CAD 1.3889, AUD 1.5385, CHF 0.8850, ILS 3.6251,
JPY 149.2537, NZD 1.6667, ARS 666.6667, else 1.0)`. All 4 are **unconditional** top-level FormulaBasedPricing steps.
Currency-incorrect fields: **NetUnitPrice, InputUnitPrice, ItemNetTotalPrice(→NetTotalPrice), TotalLineAmount(→ItemSubtotal)**.

## Already correct — DO NOT TOUCH
- `ListPrice` — seq 2, currency-aware from the per-currency PBE; never touched by the FX steps.
- The per-currency **PricebookEntries** themselves (authoritative RLM pattern).
- `Base_Price__c` — seq 14 (copied from the EUR NetUnitPrice); seq 39 *reads* it but writes InputUnitPrice.
- Net-seed chain (seq 1/2/14/25/26). The DT match keys. The seq-2 resolver.

## Preconditions
1. ✅ **Per-currency PBE coverage COMPLETE** (verified 2026-07-09): every selling currency (USD/EUR/GBP/CAD/AUD/CHF/JPY/ILS/NZD/ARS)
   covers **7445 distinct products** (AUD 7446) — uniform. No line will strand at raw USD from a missing PBE.
2. ⚠️ **DT staleness — FIX BEFORE REMOVAL.** Confirmed via metadata retrieve (2026-07-09):
   `decisionTables/Price_Book_Entry_Decision_Table_v2.decisionTable` line 76 = `<isIncrementalSyncEnabled>false</isIncrementalSyncEnabled>`
   (source `PricebookEntry`, `SingleSobject`, keys `Product2Id + Pricebook2Id + ProductSellingModelId + CurrencyIsoCode`,
   status Active). It does NOT auto-refresh on PBE inserts/updates. Once the FX ladder is gone, PBE→DT→ListPrice is the SOLE
   currency source, so a stale DT directly corrupts net/total.
   - **It IS a deployable one-line flag** (false→true). **BUT do NOT flip it standalone/blindly:** flipping/re-publishing a
     LIVE pricing DT can re-materialize its snapshot and shift what `ListPrice` resolves; and like the ESD, it likely needs a
     UI **re-publish** to take effect at runtime (MDAPI≠runtime). Do it **inside the same gated window** as the FX removal,
     with an immediate A/B/C reprice-verify that `ListPrice` is unchanged.
   - Reassurance: the current snapshot is NOT dangerously stale today — live `ListPrice` = the live EUR PBE (3434.655), so
     the snapshot is tracking current PBEs. The gap is purely FUTURE PBE changes not auto-flowing.
   - **Must be live before the Scenario-D divergence gate** (else D passes for the wrong reason — the new independent PBE
     wouldn't resolve, and D would fall back to the stale value and mask the remediation gap).

## Execution
### Step 1 — Neutralize (reversible proof)
In the ACTIVE V21 canvas, edit each of seq 38/39/40/41: replace the FX `IF(...)` ladder with the constant **`1.0`**
(pass-through). Reprice the convergent scenarios → they MUST be **0-delta** (proves the downstream already carries the
currency-aware value, sourced transitively from the seq-2 EUR PBE). Fully reversible on the canvas.

### Step 2 — Remove
Once Step 1 is 0-delta: **delete all four steps in ONE atomic canvas edit**, reprice once.
- If incremental instead: seq **39** first (InputUnitPrice, terminal/display — lowest blast radius) → seq **38**
  (NetUnitPrice, already consumed by seq 25/26) → then seq **40 + 41 as a PAIR**.
- ⚠️ **Never leave seq 40 live and 41 removed (or vice-versa):** seq 44 does `TotalLineAmount = MAX(ItemNetTotalPrice,
  TotalLineAmount)`. A mixed state (one un-doubled EUR value, one still ×FX) lets the MAX silently pick the wrong basis
  and corrupt the seq 45/46 rollups + seq 48 ItemSubtotal/ItemTotalPrice mapping.

## Gate — UI reprice (must prove BOTH non-regression AND correctness)
Diff fields on every scenario: `ListPrice, UnitPrice, NetUnitPrice, Base_Price__c, InputUnitPrice, NetTotalPrice
(ItemNetTotalPrice), TotalLineAmount/ItemSubtotal, group Subtotal/ItemGroupSummarySubtotal`.
- **A — USD control:** reprice a USD 5250 Integrator line → all = 3675, EXACTLY 0-delta (FX=1.0 → removal is definitionally no-op).
- **B — EUR convergent:** reprice a EUR line → ListPrice 3434.655 AND all net/total = 3434.655, 0-delta before vs after.
- **C — GBP convergent:** reprice a GBP line → all net/total = 2893.695, 0-delta.
- **D — DIVERGENCE (decisive):** set a EUR PBE independently ≠ USD×0.9346 (e.g. 3500 vs USD 3675), **re-publish the DT**,
  reprice. *Before fix:* ListPrice=3500 but NetTotal tracks the constant (≈double-converted) → same-line disagreement =
  the latent bug made visible. *After fix:* every field = 3500 (PBE-sourced, zero dependence on 0.9346). **Revert the test PBE.**
- **Branch coverage:** also reprice one **derived-maintenance**, one **renewal/COLA**, one **subscription/proration**
  EUR line — they write ItemNetTotalPrice/TotalLineAmount via seq 16/23/25/26/27, not the plain path. Each must be 0-delta.

## Downstream-consumer audit (workflow `wn0x3qsro`, 2026-07-09)
**Key insight:** under the 0-delta guarantee (non-USD PBE = USD × the same constant → removal yields byte-identical
persisted values), any consumer that merely READS one of the four FX-written fields and reuses it is **SAFE** — it sees
the same number. This deflates most flags. **The entire safety case therefore rests on Step-1 actually repricing 0-delta**
— which the reversible neutralize-to-1.0 step EMPIRICALLY confirms. If Step-1 is NOT 0-delta, every consumer below becomes live.

- 🔴 **HIGH (genuinely, can't verify from repo): Order→Workday Mule `extendedAmount` / `currentContractAmount` mapping.**
  Sources an FX-affected field (`OrderItem.NetTotalPrice` or `TotalLineAmount` — memory `project_workday_extendedamount_mapping`
  says it was moved `TotalLineAmount→NetTotalPrice` for SC-3347, but that's external and may have drifted). Lives in Mule
  (0 hits in force-app). Workday hard-fails "Contract Amount must equal Contract Line Amount" (SC-3347/SC-3374 recurrence).
  **MUST validate the live Mule DataWeave source field before rollout** — even under 0-delta, because it's external + a hard-fail.
- 🟠 **CONDITIONAL (only bites once 0-delta is broken by an independently-set PBE / stale DT): persisted stores that survive
  the cutover.** `Asset.Price` (PopulateAssetLegacyFieldsAction), renewal carry-forward $ (MaintenanceOrderDecompositionService
  → RenewalMaintenancePricingService COLA next cycle). Assets/decompositions written before the fix carry the old basis; the
  fix doesn't retroactively re-price them. Inherent to any currency-correctness fix — note for renewal cohorts.
- 🟢 **DE-RANKED / safe under 0-delta:** `OrderRepriceInvocable` Quote-vs-Order total-match gate; absolute-$ approval routers
  (Quote approvals −100k/−250k, Subtotal/GrandTotal 15k/25k/100k); `PartnerNetPricePosthook` lower-of gate; header-discount
  distribution (ratio-based, FX cancels); renewal-ARR discount routing (ratio). All read the same values → no shift under 0-delta.
- **ARR chain to check:** flows compute `QLI_NARR__c = TotalLineAmount / term` and `ARR = NetUnitPrice × Qty × 12 / term`
  from the FX fields → 0-delta safe, BUT **is `OrderItem.Order_Line_ARR__c` a formula on these fields?** (not in local source —
  org check). If so, `Asset.ARR__c` + the SC-3500 renewal-forecast inherit any shift.

## Open questions (chase before wide rollout)
1. **Live Mule DataWeave source** for `extendedAmount` + `currentContractAmount` (external — the #1 verify).
2. Are `NetUnitPrice`/`InputUnitPrice` actually **persisted**? (writeback wall — observed BLANK on the EUR line).
3. Is `OrderItem.Order_Line_ARR__c` a **formula** on the FX-affected fields? (source drift — org describe).
4. Any **external BI/analytics** (CRM Analytics, warehouse, Workday reports) that DIVIDES by an FX rate assuming the value
   was FX-scaled? Such a consumer would double-correct after removal.

## Other residual notes
- **Writeback wall:** if the SalesTransaction OutputMap is later changed to map NetUnitPrice/Base_Price__c, re-validate end-to-end.
- **Coordinate the V21 change window with Tab 1** (D-19 canvas edits) — both touch live V21; edit in-place on V21, activate from Versions.

## Consequent decisions (resolve after removal)
- **OQ-2 / D-10b (currency-change handler):** implement as a Force-reprice through the engine (never FX-multiply / rebuild
  lines) — now sits cleanly on top of the corrected engine.
- **OQ-6 (Currency_Conversion_Formula__mdt):** NOT dead — it's **live** for the admin bulk-PBE price tool
  (`Fortra_CurrencyConversionService`), which is how the per-currency PBEs get their `USD × rate` values. So it stays; the
  only open question is the executable-string fields (`Conversion_Formula__c`/`Formula_Text__c`) vs the decimal
  `Conversion_Rate__c` — a separate config-hygiene call, no longer a "retire it" item.
