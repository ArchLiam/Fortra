# SC-3345 — Leadership Briefing Script

> **Topic:** Critical quote-pricing defect — incorrect discount / ALE / totals on quotes
> **Audience:** CRM / Sales Cloud leadership + RevOps / pricing owner + Eng lead
> **Duration:** ~6–8 minutes + Q&A · **Status:** found in UAT, root cause confirmed, fix scoped
> **Ask of leadership:** 2 business decisions (Slide 7) + go-ahead to build & test the fix

Use the **Talk track** as your spoken narrative; the **On screen** lines are the slide bullets.
Numbers are from the real UAT repro quote and are rounded for clarity.

---

## Slide 1 — Title

**On screen**
- SC-3345 — Quote Pricing Defect: What broke, why, and the fix
- Critical · Sales Cloud / Revenue Cloud (RLM) · UAT

**Talk track**
> "This is a quick walkthrough of a critical pricing issue Wren reported on quotes. The good news up
> front: we've found the exact root cause, it's a configuration problem in our pricing engine — not a
> data-entry mistake and not an Apex/code defect — and we have a clear, low-risk fix. I need two
> business decisions from this group to finish it. I'll keep this to about five minutes and leave the
> deep technical detail in the appendix for Q&A."

---

## Slide 2 — What the user saw

**On screen**
- Saved a quote with **no discount applied** →
  - A **huge phantom discount** appeared (≈ **−11,000%**)
  - **ALE** was wrong (showed **$46** instead of the real subscription value)
  - A **"Total Services" of $500** — on a quote with **no services on it**
- One real test quote, multiple money fields wrong at once

**Talk track**
> "Wren saved a normal quote, applied no discount, and the quote came back with a giant fake discount,
> an annualized-license value that was clearly too low, and a Services total of five hundred dollars
> even though there are no services on the quote. So several dollar figures that we put in front of
> customers were simultaneously wrong. That's why it's flagged Critical — these are customer-facing
> numbers."

---

## Slide 3 — Why it matters / exposure

**On screen**
- These are **customer-facing** figures (quote PDF, approvals, ALE/ARR reporting)
- Triggers on **attribute/derived-priced products** (priced by configuration, not a flat list price)
- Found in **UAT** on a test quote — **no confirmed customer impact yet**
- **Action item:** confirm whether Production runs the same pricing version

**Talk track**
> "Two things to calibrate the risk. First, this isn't cosmetic — these fields drive the quote
> customers see, the approval thresholds, and our annualized-revenue reporting. Second, on scope:
> we caught this in UAT on a test quote, so there's no confirmed customer impact today. But the defect
> lives in the pricing engine configuration, which means *any* quote using our configuration-priced
> products would show these wrong numbers. The one open item on exposure is to confirm whether
> Production is running this same pricing version — that's on my list and I'll report back."

---

## Slide 4 — Root cause, in plain English

**On screen**
- Our configuration-priced products price **above** their stored "list" price
- The engine measures **"discount" and "Subtotal" against list**, but the **real total against net**
- Result: it reports the *uplift* as a giant negative discount, and ALE inherits the wrong base
- The phantom **$500 Services** is a separate, simpler bug: a **leftover value never reset to zero**

**Talk track**
> "Here's the whole thing in one picture. Our configuration-priced products — think security products
> priced by number of assets — end up priced *above* their stored list price. The pricing engine
> calculates 'Subtotal' and 'discount' from the list price, but calculates the actual total from the
> real configured price. Those two bases don't match, so the gap between them gets reported as a
> massive negative discount, and the ALE field just mirrors that wrong subtotal. The Services-$500 is a
> separate, simpler bug: when a quote has no services, the engine never resets that field to zero, so
> an old leftover value from a previous calculation just sticks around. Both are configuration issues
> we control."

---

## Slide 5 — The key insight: we've iterated, but never at the right layer

**On screen**
- Our pricing procedure has **7 versions**; only **V6 is live**
- The latest, **V7, was built but never activated** — and its totals logic is **identical to V6**
- → **Activating V7 would not fix this**
- Past iterations improved **line-level pricing**; the **header-total math was never the target**
- We now know **exactly** which 3 settings to change

**Talk track**
> "This is the most important slide. We have seven versions of this pricing procedure. Only version six
> is live. The newest one, version seven, was built but never turned on — and critically, its
> total-and-discount logic is identical to the live version. So switching to version seven would not
> fix this; it'd just move the same bug forward. The earlier iterations were real improvements, but
> they targeted line-level pricing, not the header totals where this bug lives. The payoff of this
> investigation is that we've now pinpointed the three exact settings that are wrong — so the next
> change lands in the right place."

---

## Slide 6 — The fix

**On screen**
- Build a **new, corrected version (V8)** from V7 (keeps the recent pricing improvements)
- Three targeted changes:
  1. Measure **Subtotal on the same basis as the total** (fixes the fake discount **and** ALE)
  2. **Reset category totals to zero** each run (kills the phantom Services $500)
  3. Treat a price **uplift as $0 discount**, not a negative discount
- Turn on the engine's **"initialize values" safety setting**
- **Configuration only — no code.** Test on the repro quote, then activate

**Talk track**
> "The fix is config, not code. We build one new corrected version from version seven so we keep the
> recent improvements, and make three targeted changes: measure the subtotal on the same basis as the
> total — that single change fixes both the fake discount and the ALE; reset the category totals to
> zero on every calculation so leftovers can't linger; and stop treating a price uplift as a negative
> discount. We also flip on a built-in 'initialize values' safety setting as a backstop. Then we re-test
> on the exact quote Wren reported and confirm every field reads correctly before we activate."

---

## Slide 7 — Decisions we need from you

**On screen**
- **Decision 1 — Subtotal & ALE basis:** should they show the **net/real price** customers pay, or the
  stored **list** price? *(Recommend: net — it matches every other total.)*
- **Decision 2 — "Discount" on uplift:** when the configured price is **above** list, should the
  discount show **$0** *(recommend)*, or do we want the uplift shown in a separate field?

**Talk track**
> "Two decisions are genuinely yours, because they're about what the numbers should *mean*, not how to
> build them. One: should Subtotal and ALE reflect the net price the customer actually pays, or the
> stored list price? My recommendation is net, because every other total on the quote is already net.
> Two: when a configured product prices *above* list, should the discount simply show zero — my
> recommendation — or do you want that uplift surfaced somewhere explicitly? Give me those two answers
> and the fix is fully specified."

---

## Slide 8 — Plan, risk, and the ask

**On screen**
- **Risk:** Low–Medium. UAT first; config is reversible (revert to V6); no code, no data migration
- **Watch-outs:** the safety setting is org-wide → broader regression test; check Orders use the same engine
- **Sequence:** decisions → build V8 → test on repro quote + regression → activate in UAT → confirm prod exposure
- **Ask today:** approve the 2 decisions + go-ahead to build and test (activation is a separate sign-off)

**Talk track**
> "On risk: low to medium. We do everything in UAT first, it's fully reversible — we can revert to the
> current live version instantly — and there's no code or data migration involved. Two things we'll be
> careful about: the safety setting is org-wide, so we'll run a broader regression, not just the one
> quote; and we'll confirm whether Orders use this same engine so the fix covers them too. The sequence
> is: get the two decisions today, build the corrected version, test it on Wren's quote plus regression
> cases, activate in UAT, and confirm production exposure. What I'm asking for today is approval on the
> two decisions and the go-ahead to build and test — turning it on live will come back to you as a
> separate, quick sign-off once it's proven."

---

## Closing line
> "To summarize: customer-facing pricing numbers are wrong because of a configuration mismatch in our
> pricing engine, we know the exact three settings to change, the fix is reversible and code-free, and
> I need two business decisions to finish it. Questions?"

---

## Appendix — Technical Q&A backup (only if asked)

**"What exactly is the mismatch?"**
Subtotal aggregates the **list base** (`TotalLineAmount` = $46) while TotalPrice/category totals
aggregate **net** (`NetTotalPrice` = $5,231). The standard Discount % = `(1 − TotalPrice/Subtotal)` then
evaluates to −11,271%. `ALE__c` is a **formula field = Subtotal**, so it inherits the $46.

**"Why does the $500 Services value appear?"**
Category totals are conditional aggregates with no reset step, and the procedure's *"Initialize
resources with default values"* toggle is OFF. With no Services lines, the aggregate writes nothing and
the prior $500 persists. (`Total_Software__c` shows null because it was simply never written.)

**"Why won't activating V7 fix it?"**
V7's totals/discount/Subtotal logic is byte-identical to the live V6. Its only real changes are
line-level derived-pricing (a `DerivedPricingFilter` on `AttributeDefinitionCode='MTD'`, a tiered
formula, and a `ResetNetUnitPrice` line step). All 7 versions share the same three header-total defects.

**"How confident are we in the root cause?"**
Every one of the eight wrong/again-correct values on the repro quote reconciles exactly to the live
configuration's arithmetic (e.g. −$5,185 = −1 × the $5,185 uplift; −11,271.739% = 1 − 5231/46). Verified
against the live UAT metadata.

**"Is there a quick workaround?"**
For an individual stuck quote, a Reprice can refresh values, but it won't correct the discount/ALE basis
or the stale Services total — those require the version fix. No reliable manual workaround.

**Repro:** UAT Quote `0Q0WC0000034U4D0AU` ("Test Pricing" / 00780814). Full RCA: `sc3345.md` §10.
