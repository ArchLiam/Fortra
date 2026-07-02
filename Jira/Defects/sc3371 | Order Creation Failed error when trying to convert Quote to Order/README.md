# SC-3371 — Order Creation Failed converting Quote to Order

> 🗺️ Part of the **[Pricing-V9 incident cluster](../_CLUSTER%20pricing-v9%20%28sc3371%20sc3372%20sc3374%29/ROADMAP.md)** (SC-3371 · SC-3372 · SC-3374) — see the shared ROADMAP for sequencing, ownership, and the V9-change gate. Lead: this chat.

**Status:** ✅ Root cause identified · service **already self-recovered** (8 clean converts since 16:28Z) · read-only investigation 2026-06-09 · UAT only.
**Severity:** Critical · **Assignee:** Liam Jeong · **Reporter:** Joe Romo · **Label:** CRM-Revenue-Cloud / LOB-Salesforce-1-UAT

## Symptom
Converting Quote **00780952** to an Order returned "Order Creation Failed — An error occurred while converting this Quote to an Order." with `System.UnexpectedException: Salesforce System Error: 1713239056-468345 (-1631597440)`. The failing convert ran 2026-06-09T13:27:16Z (08:27 CDT), leaving orphaned Draft Order **00095400** (CompletedWithoutPricing). Ticket filed 08:36 CDT, 9 min later.

## Root cause (one line)
A **transient recurrence** of the convert-time RLM pricing gack. At **08:12 CDT (13:12:06Z)** the active pricing procedure **V9** was reworked/re-activated; during the window that opened, the **Order side** of context `SalesTransactionContextExt_v2` (`OrderEntitiesMapping`) was **missing the item-level attributes V9 reads — `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c`** (the same pair fixed that morning for the reprice gack; the fix did not survive the V9 republish). The convert reprices the new Order in-transaction → engine can't fetch the Order-side item tags → `-1631597440` "Unable to fetch tags" gack → uncatchable → transaction rolls back → "Order Creation Failed."

## Decisive evidence
- **Before/after live context snapshots** of `OrderEntitiesMapping`: at 14:41Z (≈1 h after the failed convert) `Prior_*` = **absent**; by 17:36Z (after recovery) `Prior_*` = **present**. The flip tracks the recovery exactly.
- **Order timeline:** success at 13:10Z (pre-rework) → fail 13:20Z + 13:27Z (post-rework) → continuous success from 16:28Z (post-repair), including a structurally-identical single-line quote (00095403). Time-clustered, not content-driven.
- **Buffers ruled out:** `ListPriceBuffer__c` / `LineDiscountBuffer__c` are *still* absent from the Order side, yet converts succeed → header sourceless placeholders are tolerated; only item-level formula attributes (`Prior_*`) gack when unmapped. *(This corrects the first auto-generated draft, which wrongly named the buffers as root cause.)*

## What to do now
1. **Cleanup** orphan Draft Order **00095400** (`801WC00000kQoI3YAK`) — delete or reprocess.
2. **Confirm** by re-converting Quote 00780952 — it will now succeed (optionally with a TraceFlag to capture a clean "0 Unable-to-fetch-tags" log).
3. **Hardening (process):** the Order-side `Prior_*` mapping was lost across a V9 republish — 2nd time this gap hit the convert path. After ANY rework of the live active V9, re-verify OrderEntitiesMapping has every item-level attribute V9 reads, then re-sync the context. Build on a draft V9, not the live active one.
4. **Completeness (low priority):** add `ListPriceBuffer__c` + `LineDiscountBuffer__c` as sourceless header placeholders on OrderEntitiesMapping (mirror the Quote side) to remove the latent gap.

## Do NOT
- Do NOT modify/revert V9 (procedure is correct; only the bound Order context drifted).
- Do NOT map the buffers to a field (transient sourceless header tags — no such field exists).
- Do NOT deploy to prod (UAT-only pricing rework, not promoted).

## Key Ids
- V9 active: `9QBWC0000000me94AA` (LastModified 2026-06-09T13:12:06Z, Liam Jeong) · ESD `9QAWC0000003mg14AA` (Rev_Mgmt_Default_Pricing_Procedure)
- ContextDefinition: `11OWC000002m21Z2AQ` SalesTransactionContextExt_v2; active v23 `11pWC000002TjF7YAK` (stale, not re-synced after rework)
- Convert flow active: `301WC00000kONJsYAO` (V26, Fortra_Quote_to_Order_Conversion)
- Quote `0Q0WC0000036wnZ0AQ` (00780952) · Account PAGANI SPA `001WC00000gVLfxYAG` (Customer)
- Orphan Draft Order `801WC00000kQoI3YAK` (00095400)

## Full RCA
[Data/sc3371/RCA_FINDINGS.md](../../../Data/sc3371/RCA_FINDINGS.md)
