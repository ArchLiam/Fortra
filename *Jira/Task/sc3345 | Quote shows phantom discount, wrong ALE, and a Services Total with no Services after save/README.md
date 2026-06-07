# SC-3345 — Quote shows phantom discount, wrong ALE, and a Services Total with no Services after save

> Space: Salesforce-Coastal (SC) · Type: Task · [SC-3345](https://helpsystems.atlassian.net/browse/SC-3345)
>
> 🔬 **Full root-cause analysis + proposed solution: see [`sc3345.md`](sc3345.md) (authoritative: §10).**
>
> **Verified root cause:** the active pricing-procedure version **V6** mixes aggregation bases (Subtotal
> sums *list*, everything else sums *net*) and sign-flips a markup into a fake discount; the $500 Services
> is a stale aggregate (empty group + "Initialize resources" toggle OFF). **Your V7 was never activated and
> is byte-identical in totals logic → activating it does NOT fix it.** Fix = author a corrected version (V8).

## Details

| Field | Value |
|---|---|
| **Status** | To Do |
| **Reporter** | German Wren (reported via Teams) |
| **Assignee** | Liam Jeong |
| **Priority** | 🔴 Critical |
| **Sprint** | CRM Sprint 14 |
| **Components** | SF RCA |
| **Labels** | Bug, CRM, RCA |
| **Environment** | FortraUAT (`fortra--uat.sandbox.lightning.force.com`) |

---

## Summary

After saving a Quote with **no discounts applied**, the quote displays a very large (phantom)
discount, an incorrect ALE, and a Total Services value even though the quote contains **no Services
line items**. Multiple dollar-amount fields show incorrect values.

## Reported by

German Wren — Teams, 2026-06-06 (UAT):

> *"Incorrect dollar amount values in multiple fields — After saving a quote with no discounts
> applied by me, a very large discount was displayed on the quote. ALE is also incorrect, and for
> some reason there is Services Total even though there are no Services on this quote."*

## Affected record

- **Quote:** Test Pricing (`00780814`) — Status **Accepted**, Currency USD
- **Link:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000034U4D0AU/view
- **Id:** `0Q0WC0000034U4D0AU`
- Created 2026-06-03, last modified 2026-06-05

---

## Symptoms (verified via SOQL against FortraUAT — read-only)

**Quote-level:**

| Field | Value on record | Problem |
|---|---|---|
| `Discount` | **-11,271.7%** | Phantom — no discount was applied |
| `Total_Discount_Amount__c` | **-$5,185** | Phantom — no discount was applied |
| `Subtotal` | **$46** | Out of sync with `TotalPrice` |
| `TotalPrice` / `GrandTotal` | **$5,231** | (line `TotalPrice` sum) |
| `ALE__c` / `Annualized_License_Equivalent_Base__c` | **$46** | Incorrect — does not reflect subscription value |
| `Total_Services__c` | **$500** | Phantom — quote has **no** Services lines |
| `Total_Subscription__c` | **$5,231** | |

**Line items (2 lines, both `Family = Subscription` — no Services):**

| Product | Family | Qty | UnitPrice | `Subtotal` | `TotalPrice` |
|---|---|---|---|---|---|
| beSECURE - Cloud-Based | Subscription | 1 | $0 | $0 | $875 |
| Abstract | Subscription | 1 | $46 | $46 | $4,356 |
| **Sum** | | | | **$46** | **$5,231** |

---

## Analysis / suspected root cause

The line-level **`Subtotal`** rollup ($0 + $46 = **$46**) is out of sync with the line-level
**`TotalPrice`** ($875 + $4,356 = **$5,231**) after the model-based price runs. The quote-level
derived/rollup fields then cascade from the wrong base:

- **Phantom discount:** `Total_Discount_Amount__c` = `Subtotal − TotalPrice` = `$46 − $5,231` =
  **-$5,185**, and `Discount %` = `-$5,185 / $46 ≈ -11,271.7%`. Because `TotalPrice` is *higher*
  than `Subtotal`, the engine reports it as a (huge, negative) discount even though none was entered.
- **Wrong ALE:** `ALE__c` is pinned to the bad `Subtotal` base ($46) instead of the actual
  annualized subscription value.
- **Phantom Services Total:** `Total_Services__c` rolls up **$500** while no line has a Services
  family — the Services rollup is misclassifying a line or summing a stale value.

This points at the Quote pricing/rollup automation (RLM / RevenueCloud reprice + the
`Total_*` / `ALE__c` derivation), not user-entered data.

## Steps to reproduce

1. In FortraUAT, create/open a Quote with Subscription line items and **apply no discount**.
   (Repro record: Quote `00780814` / `0Q0WC0000034U4D0AU`.)
2. Save the quote.
3. Observe the Quote-level pricing summary.

**Expected:** Discount = 0 (no discount applied); `Subtotal` consistent with `TotalPrice`; ALE
reflects the real annualized subscription value; Total Services = $0 when there are no Services lines.

**Actual:** Discount ≈ -11,271.7% / -$5,185; `Subtotal` ($46) ≠ `TotalPrice` ($5,231); ALE = $46;
Total Services = $500 with no Services lines.

---

## Acceptance Criteria

- [ ] With no discount applied, the Quote shows **$0 / 0%** discount (`Discount`,
      `Total_Discount_Amount__c`).
- [ ] Quote `Subtotal` is consistent with `TotalPrice` / line totals after save and reprice.
- [ ] `ALE__c` reflects the correct annualized subscription value for the quote's lines.
- [ ] `Total_Services__c` = **$0** when the quote contains no Services line items; rolls up
      correctly when Services lines exist.
- [ ] Verified on the repro quote (`00780814`) and on a fresh quote with mixed Subscription lines.
- [ ] No regression to correctly-discounted quotes (real discounts still roll up correctly).

## Notes / next steps

- Investigate where line `Subtotal` is populated vs `TotalPrice` during reprice — they diverge here.
- Check the `Total_Services__c` rollup classification logic (what counts as "Services").
- Likely related to the RLM/RevenueCloud quote reprice automation — coordinate with whoever owns
  Quote pricing rollups.

---

## References

- Reported via Teams (German Wren), screenshot attached to the report.
- Repro quote: `0Q0WC0000034U4D0AU` (Test Pricing / 00780814), Account `001WC00000XiZP4YAN`,
  Opportunity `006WC00000OE0NKYA1`.
