# Fortra RLM — Engineering Practices: Background & Improvement Suggestions

*Prepared by Liam Jeong for Hiren Shah (and Alison / John). Framed as making this delivery and future projects stronger — root-cause, not blame. Every figure below is checkable against the org/repo.*

---

## First, the credit
This has been a hard, high-complexity build on Revenue Cloud Advanced — a platform with genuinely sharp edges (governor limits, ExpressionSet pricing, RLM data locks, immature migration tooling). The team has put in real effort and shipped a large amount of working functionality under schedule pressure. The goal of this note is not to assign blame; it is to surface a small number of **structural, fixable patterns** that are quietly inflating cycle time — so the remaining UAT and the prod cutover go more smoothly, and the next engagement starts on firmer ground.

I joined late (late April), so I am deliberately sticking to things I can show with concrete evidence.

---

## Theme 1 — There is no shared, version-controlled source of truth *(highest leverage; root cause of several others)*
The code that actually runs the org is effectively not under version control:
- The deployable, git-tracked package (`force-app`) holds **12 Apex classes and 3 flows**. The live org holds **404 classes, 245 flows, 10 triggers** — so **~97% of running Apex and ~99% of flows have no version-controlled counterpart** (by basename only 10 classes / 2 flows overlap; 0 of 10 triggers tracked).
- The retrieved mirror of the live org (`Org Data/_src`) is **explicitly gitignored** — it has no history at all.
- There is **no shared team repository** (the only repo is single-author, a personal mirror), **no CI**, and **no git-backed promotion path**. Fixes are hand-carried to prod one ad-hoc retrieve at a time.

Because there is no single source of truth, collaboration happens by **editing the live org directly**, with documented consequences:
- A production **gack 572633412-308158** from an in-place pricing-procedure edit that skipped a context re-sync.
- A flow change (**V9**) that silently **re-introduced a previously-closed Workday defect** (SC-3347), fixed only by reverting to V8.
- A maintenance-rate formula that **oscillates between sessions** as it is clobbered and re-applied.

Each required a fresh investigation starting from "what is actually live right now," because nobody could diff or roll back. **This is a process gap, not a people problem** — without a shared repo and pipeline, even careful engineers end up editing live and clobbering each other.

## Theme 2 — Quality gates aren't continuous
Org-wide Apex coverage was **43%** at the authoritative peer-review run (SC-3403, run `707WC00002y0PNw`), against the **mandatory 75%** Salesforce production gate, with several in-scope pricing classes at **2–37%**. A same-day remediation pass moved the overall number only to **45%**. Whatever the business sign-off looks like, **the platform itself will reject the prod deploy until coverage clears 75%** — a hard, late-surfacing blocker that a continuous-coverage habit (write tests as you build, keep the suite green) catches early instead of at cutover.

## Theme 3 — Overlapping automation and an overgrown pricing procedure burn governor budget
- Large-order completion failed in UAT with **"Too many SOQL queries: 101"** because three OrderItem flows fan out per line on one transaction (**51 flow interviews on a 17-line order**). A redundant, deprecated line-type subflow was the **single largest contributor (~40% of the queries)** doing work an active flow already did.
- The pricing engine is **one procedure grown to 110 steps across ~14 in-place versions**, wrapped by **9 prehook/posthook classes** (two of them redundant V1/V2 pairs); **18 obsolete flows** still sit in the org.

None of this is catastrophic individually, but it is accreted, duplicate automation that consumes the shared governor budget and makes every change riskier. *(Fairness: the large-order failure is on a UAT-only validation stack and had more than one cause; the duplicate subflow has since been addressed.)*

## Theme 4 — Volume & edge-case scope wasn't pinned down in discovery
- The design documentation contains **essentially no non-functional / volume requirements** — no order-size ceiling, no line-count expectations, no governor budget (a grep across both design KBs for volume/NFR terms returns one self-asserted note). The realistic order-line ceiling is **still an open question to the PO**.
- Two Critical/Blocker governor defects were discovered **reactively in UAT**: **SC-3366** (SOQL-101) and **SC-3447** (a high-quantity convert produced **401 line clones, 1,293 flow interviews, and breached the Apex CPU limit**).
- The discovery KB still lists **core pricing rules as open** (multi-currency, guaranteed-margin-vs-discount math, NEW vs RENEW maintenance SKU handling), and **~24 distinct pricing/Workday tickets** were worked in a roughly 3-week UAT-prep window.
- On migration: multiple Revenue Cloud Advanced entities had **no supported migration path** (ProductConfigurationRule — 302 rows blocked across every standard tool; ProductAttributeDefinition blocking 4,572 of 5,421 Product2 deletes; ProductComponentGroup; and others), discovered one-by-one **during the SC-3137 cutover** rather than validated in planning.

Common thread: requirements that should have been elicited up front — **peak volumes, pricing math, per-object migration feasibility** — were instead discovered during build/UAT, where each discovery becomes its own RCA → fix → retest loop.

---

## What I'd suggest going forward
1. **Stand up one shared team repository** as the single source of truth; commit the full org metadata; stop editing the live org directly. *(structural)*
2. **Add CI + branch/PR review + a repeatable deploy pipeline** so changes are diffable, reviewable, reversible. *(medium)*
3. **Make coverage + a green suite a per-ticket, continuous expectation**, not end-of-build remediation. *(medium)*
4. **Consolidation pass on order/pricing automation**: retire the 18 obsolete + duplicate flows, one automation per object/purpose, bulkify SOQL out of loops. *(medium)*
5. **Plan to refactor the pricing procedure** toward a smaller, source-controlled definition instead of appending steps and republishing live. *(structural)*
6. **Capture non-functional requirements** (peak order/line volumes, governor budgets), **pricing math, and per-object migration feasibility during discovery** — with the business signing off on the numbers before build. *(medium)*
7. **Quick win:** commit the current live org state and tag it as the cutover baseline so the team has one agreed "what is live" reference today. *(quick-win)*

---

## Risks if unaddressed
- **Cutover blocked at the platform tier**: 43–45% coverage → Salesforce rejects the prod deploy until a multi-day hardening pass, regardless of business sign-off.
- **Continued silent regressions / lost work**: no diff or rollback on ~97% of running code → in-place edits keep clobbering each other and re-introducing closed defects.
- **Live outages with no recovery path**: in-place edits to the single active pricing procedure (inactive versions can't even be hard-deleted) keep producing gacks, each a fresh same-day RCA.
- **Recurring governor failures on the highest-value orders**: without captured volume requirements and bulkified automation, large/high-quantity orders keep hitting SOQL/CPU limits; the realistic ceiling remains unknown.
- **Unbounded UAT slippage / budget overrun**: each reactively-discovered gap becomes its own RCA-fix-retest loop.
- **Bus-factor risk**: the only repo is single-author; other developers' work exists solely in the live org, so there's no attributable history if a contributor rolls off.

---

## Credibility guardrails — what NOT to overclaim (in case of pushback)
- The repo is **not** "local-only" — it has a remote, but it's a **personal GitHub account**, not an org/team account. Say *"single-author personal mirror, not shared team version control."*
- Call the SC-3366 SOQL failure a **UAT completion blocker on the highest-value orders**, *not* a production blocker — the validation stack is UAT-only.
- The duplicate subflow was the **largest single contributor (~40%)**, *not* the sole cause — the failure was multi-cause.
- **Don't** present 3,425 / 750,000 as business-confirmed order volumes — they're test/hypothetical figures. The defensible point: the realistic order-line ceiling **was never captured and remains an open PO question**.
- Treat the 43% figure as the durable point (**43–45% vs 75%**); the specific red-suite per-class numbers were a point-in-time snapshot (a same-day run turned the suite green).
- Frame in-place pricing-procedure editing as a **recurring anti-pattern to replace**, not an endorsed standard; reference specific RLM-admin edits, not blanket blame.
- Refer to **"multiple named editors"** qualitatively rather than per-developer counts.
- The "this is THE primary driver of the overrun" framing is **reasonable inference, not measured fact** — the evidence strongly supports the *pattern* but doesn't quantify the share of overrun. Lead with the pattern.
