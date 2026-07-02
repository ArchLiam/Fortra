# SC-3441 — Salesforce Support Case

**Subject:** Negative-quantity (cancellation) line is excluded from the pricing waterfall at runtime — Pricing Procedure steps never execute against it, though the Simulator prices it correctly (Revenue Cloud Advanced / RLM)

**Environment:** Sandbox `FortraUAT` (Org Id `00DWC000006eUFF2A2`). Revenue Lifecycle Management — native pricing (ExpressionSet pricing procedure + SalesTransaction context).

---

## Summary

A user-initiated cancellation creates a line with **negative quantity** (Qty −1) and a List Price, but it prices **Total Price = $0.00** instead of a negative credit. To produce the credit we created a custom field to **capture the cancelled line's unit price** and added pricing-procedure steps to apply it (unit price × negative quantity). The **Pricing Procedure Simulator returns the correct result (−15,000)**, but a **live "Reprice All" returns 0**.

Our investigation indicates the **negative-quantity line is excluded from the pricing waterfall at runtime**: it has no `price_water_fall` row, and **no list-group/step in the procedure executes against it** — only top-level (non-list-group) elements such as the List Price step run. We need to understand why the cancel line is excluded and the supported way to price a negative-quantity line natively.

---

## Root cause we observe

- The native pricing waterfall produces **no priced row** for a negative-quantity line → `NetUnitPrice` stays null → any line-total step computes `null × −1 = 0` → Total Price = 0.
- More fundamentally: at runtime, **every list-group step (our cancellation seed/credit steps AND the standard discount/total groups) is skipped for this line.** The only step that runs is the top-level List Price step. The line is effectively not iterated by the waterfall.
- The **Simulator executes every step unconditionally** on the supplied line, so it returns the correct −15,000 — i.e., the Simulator is not a faithful oracle for runtime waterfall membership.

---

## Approaches we attempted (and outcome)

All of these were implemented in the sandbox while trying to get the cancellation line to price to a negative credit:

1. **Custom field + pricing-procedure steps** — created `CancelNetUnitPrice__c` (Currency) on `QuoteLineItem`/`OrderItem` to capture the cancelled line's unit price, added it to the `SalesTransactionContextExt_v2` context, and added pricing-procedure steps (a seed group copying it to `NetUnitPrice`/`InputUnitPrice`, and a group computing `CancelNetUnitPrice__c × LineItemQuantity → ItemNetTotalPrice`/`TotalLineAmount`).
   *Outcome:* Correct in the Simulator (−15,000); **0 at runtime** — the steps never execute against the negative-qty line.

2. **Apex before-save trigger** — a trigger on `QuoteLineItem`/`OrderItem` to populate `CancelNetUnitPrice__c` (and, on the Order side, to stamp `NetUnitPrice` directly) from the source asset's net unit price.
   *Outcome:* Field populates reliably (confirmed on the record and in the context dump at 15,000). On the **Order** side a direct `NetUnitPrice` write persists; on the **Quote** side `QuoteLineItem.NetUnitPrice` is **read-only** (not directly writable). Either way, the **procedure still does not price the line** at runtime.

3. **Record-triggered flow** — a flow to set `CancelNetUnitPrice__c` on the cancellation line as an alternative populator to the Apex trigger.
   *Outcome:* Field populates; **no change to the pricing result** (the value is present but the procedure steps that consume it don't run for the line).

4. **RevSignaling pricing prehook** — an Apex prehook to seed `CancelNetUnitPrice__c` into the pricing **context** at runtime (before the procedure executes).
   *Outcome:* Seeds the value into context (confirmed in `RLM_PRICING_BEGIN`), but the procedure steps still **do not execute** against the negative-qty line → **0**.

5. **Forced fresh runtime compile** — created a new procedure version with the cancel logic and **activated it as the sole active runtime** (fresh `ExpressionSetVersion`), to rule out a stale compile.
   *Outcome:* Confirmed the new version with the cancel logic was the sole active runtime during the test; live reprice **still 0**.

**Common result across 1–5:** the value is available on the line and in the context, the design + Simulator are correct, the context is correctly configured — yet at runtime **no list-group/step in the procedure executes against the negative-quantity line** (no `price_water_fall` row; only top-level elements run). This is what led us to conclude the line is excluded from the pricing waterfall, and to open this case.

---

## Steps to reproduce

1. Procedure contains the seed/credit groups above (visible in the active design version).
2. **Simulator** (Advanced input / Auto-fill from the live quote; context mapping `QuoteEntitiesMapping`) → **Net Amount = −15,000** (all steps fire).
3. Live **Reprice All** on the quote.

- **Expected:** matches the Simulator → line total **−15,000**.
- **Actual:** **0**. In the FINEST pricing log, `CancelNetUnitPrice__c = 15000.0` and `LineItemQuantity = -1.0` are present in every `RLM_PRICING_BEGIN/END` dump, yet `ItemNetTotalPrice`/`TotalLineAmount` stay 0 across all passes; the saved line has `NetUnitPrice = null`. The line has **no `price_water_fall` row**, and nothing produced by any list-group step (`NetUnitPrice`, discounts, `ItemNetTotalPrice`) ever lands.

---

## Diagnostics already performed — ruled out

| Suspect | Verdict | Evidence |
|---|---|---|
| Procedure design wrong | Ruled out | Simulator returns −15,000; retrieved metadata confirms steps present & correctly ordered, structurally identical to a working native group |
| Stale runtime compile | Ruled out | Created a new procedure version (fresh `ExpressionSetVersion`, brand-new CreatedDate) and **activated it as the sole active runtime**; live reprice still 0 |
| Wrong/stale active version | Ruled out | Confirmed the version **with** the cancel logic was the **sole active runtime** at the captured failing reprice |
| Field-level security | Ruled out | Reprice runs as a System Administrator with full Read/Edit on the field |
| Competing pricing procedure | Ruled out | Only one active DefaultPricing ExpressionSet; the others are Discovery procedures |
| Field not hydrated | Ruled out | `CancelNetUnitPrice__c = 15000.0` present in every `RLM_PRICING_BEGIN/END` dump, from the first pass |
| Context misconfigured / stale | Ruled out | The field is a `ContextAttribute` (currency, inputoutput) on the SalesTransactionItem node with a ContextTag, mapped via `ContextAttributeMapping` to `QuoteLineItem.CancelNetUnitPrice__c` under `QuoteEntitiesMapping` — structurally identical to other working custom attributes, under the active context version |
| Steps execute at runtime | They do NOT for this line | No `price_water_fall` row; all step-written fields null; `ItemNetTotalPrice = 0` in every pass — only the top-level List Price step runs |

---

## Questions

1. **Why is a negative-quantity (cancellation) line excluded from the pricing waterfall at runtime** — such that no list-group/step in the pricing procedure executes against it (only top-level elements run) — while the **Pricing Procedure Simulator executes all steps and prices it correctly**?
2. What is the **supported native way to price a negative-quantity / cancellation line** in RLM pricing so it yields a negative credit (e.g., `NetUnitPrice × negative quantity`)? Is there a setting, a required field (e.g., a pricing source), or a pattern that makes the line participate in the waterfall?
3. Is the **Simulator-vs-runtime divergence expected** (Simulator executes steps unconditionally; runtime gates on waterfall membership)? If so, what is the correct way to validate cancellation pricing before activation?
4. If native pricing cannot price negative-quantity lines, is a **post-pricing hook** (writing the line total after the procedure) the recommended approach, or is there a platform-supported alternative?

---

## Reference Ids

- Pricing procedure: `Rev_Mgmt_Default_Pricing_Procedure` — ExpressionSetDefinition `9QAWC0000003mg14AA`; runtime ExpressionSet `9QLWC0000015cDl4AI`. (Version with cancel logic compiled & activated for the failing-reprice test: ExpressionSetVersion `9QMWC00000024tx4AA`.)
- Context: `SalesTransactionContextExt_v2` — ContextDefinition `11OWC000002m21Z2AQ`, active ContextDefinitionVersion `11pWC000002TjF7YAK`; ContextAttribute `11nWC0000D9vxSXYQY`; mapping `QuoteEntitiesMapping` `11jWC0000064MRWYA2`.
- Custom attribute: `QuoteLineItem.CancelNetUnitPrice__c` (Currency 16,2).
- Repro record: Quote `0Q0WC000002VENJ0A4` (`00734145`), line `0QLWC000002q2Sn4AI` (Qty −1, List 15,000, `CancelNetUnitPrice__c = 15,000`).

---

## Business impact

All user-initiated cancellation lines price to $0.00 instead of a credit; the resulting Cancellation Quotes fail price calculation and cannot convert to Order.

---

## Parallel workaround under evaluation (for our reference)

A RevSignaling **post-hook** that writes `NetUnitPrice` / `ItemTotalPrice` / `TotalLineAmount = CancelNetUnitPrice__c × quantity` directly onto the line *after* the procedure — it operates on the result line-set rather than the waterfall iteration, so it sidesteps the exclusion. Being pursued in parallel with this case.
