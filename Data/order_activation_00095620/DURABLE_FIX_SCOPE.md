# Durable fix — Order activation strands on two gates (contract + ValidationResult)

**Source incident:** Order 00095620 (`801WC00000lhDYyYAM`), PAGANI SPA, Q-Automation test convert. Could not activate. RCA below. Resolved live 2026-06-27 (contract activated by user; `ValidationResult` nulled by Apex).

## Problem (two independent gates that block `Update Status → Activated`)

### Gate 1 — Draft contract
`FAILED_ACTIVATION: This order's contract is inactive.` Salesforce blocks Order activation whenever `Order.ContractId` → a non-`Activated` Contract.
- Contract is born **Draft** at quote→order convert via standard RCA *ContractsContextDefinition* (`Fortra_Order_to_Contract_Field_Mapping` only stamps custom fields).
- The convert wizard `Fortra_Quote_to_Order_Conversion` activates the contract (`Activate_Contract` recordUpdate → `Status='Automatic'` branch only) **only when the user picks Automatic** activation. Manual-mode converts (and interrupted ones) leave Draft order + Draft contract.
- The standalone Order **"Update Status"** path only flips `Order.Status`; it never activates the contract. → always fails on a Draft-contract order.
- Scope: 8 orders stranded Draft-order+Draft-contract as of 2026-06-27.

### Gate 2 — `Order.ValidationResult = TransactionIncomplete`
After the contract is Activated, activation can still fail: `INVALID_INPUT: We couldn't activate the order because the prices aren't updated. Click Reprice All and try again.` — a standard RLM gate on `Order.ValidationResult` (must be null/blank).
- ANY OrderItem DML flips a clean `null → TransactionIncomplete` (platform behavior; documented in `PowerOrderSplittingService.cls:100-102`).
- On Power-split-eligible products (`Power_Split_Type__c` set — includes `'Order Line Only'`), a **manual reprice re-flips it every time**; only the convert wizard's `PowerOrderSplittingService` restores `null`. **Repricing does not fix it — it causes it.**
- When `CalculationStatus=CompletedWithPricing` and totals are correct, the flag is merely stale.

## Recommended durable fixes (pick per appetite)

1. **Auto-activate the linked Draft contract on Order activation** (preferred). A before-/around-activation automation (or extend the Update Status flow) that, when `Order.Status` is moving to Activated and `Order.Contract.Status='Draft'`, activates the contract first (mirroring `Activate_Contract`). Removes Gate 1 for every path, not just the convert wizard's Automatic branch.

2. **Restore `ValidationResult=null` after a manual reprice** on Power-split-eligible orders that priced cleanly (`CalculationStatus=CompletedWithPricing`), mirroring what `PowerOrderSplittingService` already does post-split. Removes Gate 2's "reprice strands the order" trap. Alternatively, surface a clear "Clear pricing flag & activate" action.

3. **Guard the Update Status action**: when the contract is Draft or `ValidationResult=TransactionIncomplete`, show an actionable message (and offer to fix) instead of the raw platform error.

## Manual remediation runbook (until durable fix ships)
1. Activate the Contract (UI: Contract → Activated; or `update Contract SET Status='Activated'`). Note: fires renewal-opp / co-term automation — intended.
2. If `ValidationResult=TransactionIncomplete` and pricing is complete: `update Order SET ValidationResult=null` (Apex). Do NOT reprice.
3. Order → **Update Status → Activated** (no reprice in between).

## Stranded inventory (2026-06-27) — do NOT batch-activate blindly
| Order | VR | Calc | Contract | Created | Owner | Action |
|---|---|---|---|---|---|---|
| 00095620 | nulled ✅ | CompletedWithPricing | Activated | 6/26 | Joe Romo | FIXED — ready to activate |
| 00095621 | TransactionIncomplete | CompletedWithoutPricing | Draft | 6/26 | Jordan Pollard | needs contract; owner-confirm |
| 00095607 | null | CompletedWithPricing | Draft | 6/26 | Joe Romo | needs contract; owner-confirm |
| 00095575 | TransactionIncomplete | CompletedWithoutPricing | Draft | 6/24 | Joe Romo | needs contract; owner-confirm |
| 00095501 | TransactionIncomplete | CompletedWithoutPricing | Draft | 6/14 | Victoria Mullady | needs contract; owner-confirm |
| 00004763 | null | CompletedWithoutPricing | Draft | 4/09 | Aaron Broom | STALE — leave |
| 00000270 | null | CompletedWithoutPricing | Draft | 2/20 | Joe Eginger | STALE — leave |
| 00000102 | null | (none) | Draft | 1/05 | Service Data Migration | MIGRATION ARTIFACT — leave |
