# SC-3441 — Status comment (draft for the ticket)

**Root cause (confirmed):** On a cancellation/negative-quantity line the native RLM price waterfall returns no priced row, so the line's `NetUnitPrice` field is never populated. The active line-total formula computes `NetUnitPrice × Quantity = null × −1 = 0`, which is why Total Price shows $0.00 instead of the credit. No declarative pricing step seeds `NetUnitPrice` on a (non-COLA) cancel line. This is systemic — every cancellation that actually runs the pricing procedure is affected (6/6); the negative lines that *do* price correctly are bulk-migrated records that bypassed the procedure.

**Correct value:** the credit must use the **original asset NET** (`AssetActionSource.NetUnitPrice`), not catalog list price — 77% of asset rows have net ≠ list, and some have list 0 with a nonzero net paid. For order 00095539 the original sale was undiscounted, so the expected −3000.00 happens to equal list.

**Fix in progress:** a tightly-gated seed that populates `NetUnitPrice` on cancel lines from the originating asset net, ahead of the line-total step. Components (field, pricing context, prehook to resolve the asset net, and the procedure step) are built and deployed to UAT on a dedicated procedure version, but the value is **not yet flowing through at runtime** — repricing still stalls because `NetUnitPrice` arrives null at a downstream guard.

**Why it's taking another pass:** RLM pricing executes inside an opaque managed code unit, so neither the FINEST debug log nor the procedure Simulator can show the per-step values for a custom field (Simulate rejects custom `__c` fields as input). To get past the blind spot I'm reworking the prehook to write the net price **directly** and to emit a queryable diagnostic record on every run, so we can see exactly where the value is lost and close it out.

**Separately tracked (not part of this fix):** (1) a second cancel line with both net and list at zero — a data issue; (2) a latent total-amount clamp that zeroes legitimately-negative subtotals — will be guarded as part of validation.

Next update after the reworked prehook is deployed and repriced.
