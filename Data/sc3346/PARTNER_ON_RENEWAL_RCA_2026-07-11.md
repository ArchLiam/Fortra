# Partner-on-Renewal — RCA & Coordination (2026-07-11)

**Author:** Liam Jeong (owns RCA + partner pricing) · **For:** the SC-3346 renewal work stream (both tabs)
**Trigger:** flagged as a gap in the other tab's dossier — the renewal formula `Asset.Price × (1+COLA)` is partner-blind.

---

## TL;DR
**Partner-on-renewal is NOT a standalone active defect.** It is **sound by design** (carry-forward of the prior partner net), the double-discount was already fixed (posthook v1.5), and the one theoretical gap (**partner *change* at renewal**) **does not occur** in the data. Partner-on-renewal correctness is **downstream of the other tab's renewal-net-commit fix** — it can only be *validated* once renewals stop committing $0. This memo delivers the **acceptance criteria** + the **two risks** to verify when their fix lands.

## Findings (live FortraUAT)
1. **Partner is the norm on renewals:** 119,379 / 124,727 renewal quotes (**96%**) carry a partner.
2. **Partner *change* at renewal does not happen:** `Contract.Partner__c` populated on **0** contracts; `Amendment_Reason__c='Partner Change'` on **0**. Partner is tracked on the **Quote** (`PartnerAccountId`), stable across generations. → my flagged "partner-change-at-renewal" is **theoretical**, not a live defect.
3. **The 3-component and single-component renewal formulas are equivalent for partner economics.** SDD (Maintenance-Derived-Pricing D-001) defines `(Base − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1+COLA)`; the dossier's `Asset.Price × (1+COLA)` is the same value because `Asset.Price = Base − partner − disc = prior net`. **Retiring the 3-component graft (the other tab's plan) does NOT lose partner handling** — both carry the original partner economics forward. ✅
4. **Double-discount already fixed** (`PartnerNetPricePosthook` v1.5): on a renewal quote the deferred partner-discount path is not reached (`if (quoteId != null && !isRenewalQuote)` guard), so the current-period partner % is **not re-applied**. The renewal net = prior partner net × COLA, no re-discount.
5. **Carry-forward is SDD-intended, not accidental:** the renewal formula uses the **prior** partner discount (`Prior_Partner_Discount__c`), not the current-quote partner %. Renewals renew at prior net + uplift by design.

## The real question (and why it's blocked)
The only substantive partner-on-renewal correctness question is: **does the renewal actually carry the partner-discounted net?** That depends entirely on the source value (`Asset.Price` / prior net) **being** the partner net. But **renewals commit $0 today** (99.97%, the other tab's core defect), so this cannot be validated empirically until their **Stage 1-2 (make the net commit)** lands. Partner-on-renewal is therefore **downstream of, not parallel to, their fix.**

## Acceptance criteria — partner renewal (verify when the net-commit fix lands)
For a partner renewal line, once it commits a non-$0 net:
- **AC-P1:** committed net = **prior partner net × (1+COLA)** — i.e. the partner discount from the original sale is preserved, not re-applied and not dropped.
- **AC-P2:** no double-discount — the current-quote `PartnerDiscountPercent` is **not** applied on top (v1.5 already enforces via `isRenewalQuote`).
- **AC-P3:** the renewal maint line carries `Fortra_Product_Type__c='New Maintenance'` (per H3) — confirm the partner posthook does **not** pick a wrong *New-Maintenance partner band* for it (the v1.5 `isRenewalQuote` skip should cover this; verify empirically).

## Two risks to flag to the other tab (their fix must satisfy these)
- **RISK-1 — `Asset.Price` must be the partner net, not pre-partner/list.** Precedent: **SC-3359** ("partner net = list", fixed V9). If the source value is a pre-partner value, `Asset.Price × (1+COLA)` **over-prices** every partner renewal (drops the discount). This is the single highest-impact partner risk in their `Asset.Price × (1+COLA)` plan.
- **RISK-2 — the born-Renew flip (Stage 4) makes the line a priced node while it's still `New Maintenance` type.** Confirm partner banding on that node resolves to the *carried* net, not a fresh New-Maintenance partner computation.

## Verdict / recommendation
- **No standalone partner-on-renewal fix to build now.** Building one would (a) duplicate the other tab's net-commit work and (b) risk conflict in `PartnerNetPricePosthook` / the renewal net, which they are actively restructuring.
- **Do:** hand the other tab AC-P1..3 + RISK-1/2 as the partner axis of their Stage-2 acceptance gate; I run the partner validation once a renewal commits a non-$0 net.
