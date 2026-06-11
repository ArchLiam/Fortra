# SC-3350 — Step 2 Reprice Trace (live, 2026-06-10 18:13Z)

**Quote:** 00780886 / `0Q0WC000003671t0AA` (Nir - COLA Test Account). **Action:** Reprice All in the UI,
after fixing the Bill To Place prerequisite (created Place `a0lWC000004n5x7YAA` on the quote's account).
**Result banner:** *"The prices were refreshed and the configuration was validated."*

## After-reprice field values (stable; lines unchanged for >2 min)

| Line | Pre_COLA | COLA% | UnitPrice | Subtotal | TotalLineAmount | NetUnitPrice | NetTotalPrice | TotalPrice | Description |
|---|---|---|---|---|---|---|---|---|---|
| Abstract | 4356 | 7.85 | 4697.946 | 4697.946 | 4697.946 | **0** | **0** | **0** | `Abstract \| CU \| Primary \| Production` |
| beSECURE - Cloud-Based | 875 | 6.2 | 929.25 | 929.25 | 929.25 | **0** | **0** | **0** | `beSECURE - Cloud-Based \| Devices: 36-65 \| One Time \| Cloud Based` |

Quote totals: Subtotal **5627.196**, TotalPrice **0**, GrandTotal **0**, ALE 5627.2.

## What the trace proves

1. **Defect #2 (no description) is FIXED by forcing a reprice.** Both lines went from null → correct
   pipe-format descriptions. Confirms the unifying-fix thesis: the description prehook fires inside a pricing pass.
2. **COLA applies correctly and exactly once.** UnitPrice = Subtotal = TotalLineAmount = Pre_COLA × (1+COLA%).
   **No double-application** even though the `COLAUpliftHandler` trigger is still active. (D3 double-apply risk
   not observed on this scenario — still worth confirming on contract-override / multi-asset scenarios.)
3. **Reprice does not gack.** The SC-3308 contextDef risk did not materialize; it validated cleanly — *once
   the Bill To Place prerequisite was satisfied*.
4. **Bill To Place is a hard renewal prerequisite.** Reprice is blocked until `Bill_To_Place__c.Account__c ==
   Quote.AccountId`. The renewal flow does not set Places, and this test account had none.

## The isolated remaining defect

**The net-price side computes to $0.** List side (Subtotal / TotalLineAmount) is correct and COLA'd, but
**NetUnitPrice / NetTotalPrice / TotalPrice / GrandTotal = 0** → the quote's actual Grand Total is **$0**.
COLA Path A writes `COLACalculatedPrice__c → InputUnitPrice` (list/subtotal side); the net-price waterfall is
**not** deriving NetUnitPrice from it (and it isn't deriving from ListPrice either — Abstract ListPrice=46 but
NetUnitPrice=0). This is the deeper "renewal not priced correctly," in the **$0-net family** (SC-3345/SC-3347),
distinct from the COLA rate lookup (which is correct).

## Implication for the plan

- **D2 ("force a reprice on renewal") is VALIDATED and NECESSARY** — fixes descriptions + applies COLA — **but
  NOT SUFFICIENT.** A new must-fix is added: **renewal net-price = $0**.
- Next diagnostic: a **pricing-procedure waterfall trace** (debug log on a reprice) to find which step sets
  `NetUnitPrice` and why it resolves to 0 for non-derived renewal lines (Path A). Then fix that step so the
  COLA'd `InputUnitPrice` flows to `NetUnitPrice`.
