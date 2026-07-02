> ⚠️ **SUPERSEDED where corrected (2026-06-08).** A deep re-investigation against the **live ACTIVE V9**
> pricing procedure replaces parts of this doc — see
> [`DEEP-INVESTIGATION-V9-2026-06-08.md`](DEEP-INVESTIGATION-V9-2026-06-08.md). Key corrections: this
> README's Issue #1 procedure analysis used the **stale local V1 XML**; the SC-3359 "the override would be
> discarded by the One-Time branch" caveat is **refuted** on V9 (Issue #1 fix is **config/data only**, no
> procedure change); Issue #2 is **deterministic by provenance**, not a timing race; Issue #3's $0-line
> independence is proven across 6 of 8 stuck orders. The root-cause headlines below stand; the mechanics/fix
> details are corrected in the V9 doc.

# SC-3360 — Perpetual Advanced Authentication SKU Issue (3 defects)

> Space: Salesforce-Coastal (SC) · Type: Task (RCA) · [SC-3360](https://helpsystems.atlassian.net/browse/SC-3360)
>
> 🔬 **Read-only RCA complete (FortraUAT, 2026-06-07)** via multi-agent investigation + live SOQL,
> each root cause adversarially verified. **The FIX is QUEUED** behind the derived-pricing work per
> Joe's intake note. Three *distinct* defects, three *distinct* root causes — only the symptoms cluster
> on the same product. Raw evidence: [`Data/sc3360-advanced-auth/`](../../../Data/sc3360-advanced-auth/).

## Details

| Field | Value |
|---|---|
| **Status** | In Progress — Investigation complete; fix queued behind derived-pricing |
| **Reporter** | Joe Romo — Teams, 2026-06-06 12:03 PM |
| **Assignee** | Liam Jeong |
| **Owner / Reviewer** | Nir Kailash |
| **Priority** | 🟠 High (Issue #1 = silent mispricing; Issue #3 blocks activation; Issue #2 lower) |
| **Components** | SF RCA |
| **Labels** | RCA, CRM, Pricing |
| **Environment** | FortraUAT (`fortra--uat.sandbox.lightning.force.com`) |
| **Suggested parent** | [SC-3143 — Integration E2E](https://helpsystems.atlassian.net/browse/SC-3143) |
| **Blocked by** | Derived-pricing work — confirm with Nir which workstream gates the start |

## Solution summary (one line each)

| # | Root cause | Solution |
|---|---|---|
| **1** | Missing attribute-pricing row for `{SFTP Server, On Premise, Non-Production}` | Add the row(s) — or, if Non-Production is a uniform discount, replace per-combo Overrides with a single Server-Type % adjustment (config, not code) |
| **2** | Non-deterministic RLM -$3,150 zeroing of duplicate AAM lines | Pin the emitting pricing step via live trace, fix in the SC-3345/SC-3347 pricing workstream |
| **3** | Re-submitting an already-decomposed order (no amendment) | Use the `initiateAmendment`/change-order path for modify-after-activate; block/guard the reopen-Draft + re-Activate path |

---

## ⚠️ SKU correction

The priced/configurable bundle is **Product2 `Advanced Authentication Modes`, code `GS-GSE-NRPS-AAMP`,
Id `01tWC00000DD11YYAT`** (Perpetual / selling model "One Time", Standard list **$3,150**). The
`GS-GSE-NRPS-AAMP-TECH` / `01tWC00000FBb5HYAT` SKU is the **non-configurable "(Technical)" fulfillment
SKU**, not the priced product. All analysis is against `…DD11YYAT`.

## The three reported defects (Joe Romo, Teams 2026-06-06)

1. **PRIMARY — Server Type doesn't drive price.** Add the AA SKU as **Production**, then a second
   instance as **Non-Production** ("update pricing" selected). Configurator correctly shows Server
   Type = Non-Production, but **Net Unit Price stays = Production price**.
2. **LOWER — $0.00 net at order level.** On a Draft order opened for modification, adding products
   **at the order level** → List Price = full cost but **Net Unit Price & Total = $0.00**
   (Order 00095353, lines 5 & 6).
3. **BLOCKER — activation fails.** Reprice All + Activate on 00095353 →
   *"'Order Submission to Revenue Orchestrator' process failed … Sales Transaction cannot be
   processed at this time. Error ID: 2059615574-352070 (95127668)."*

---

# Issue #1 — Non-Production Server Type does not lower Net Unit Price  🔴 PRIMARY

### Root cause (HIGH confidence) — a **missing attribute-pricing row** (config/data gap, not code)

The bundle is priced by an **Attribute-Based Adjustment**: the pricing procedure
`Rev_Mgmt_Default_Pricing_Procedure`'s **ungated** `AttributeBasedPrice` / `AttributeDiscountEntries`
steps look up the `Attribute_Based_Adjustment_Decision_Table` (LookUpId `0lDa50000007BEuEAM`,
schedule `84Xa50000010nWQEAY` "Standard Attribute Based Adjustment", **Active**) and write the matched
**Override** straight to `NetUnitPrice`. The match is a **3-attribute AND** on Feature × Deployment × Server Type.

The product has **exactly two** Override rows (live):

| Rule | Feature | Deployment | Server Type | → Net |
|---|---|---|---|---|
| ABARule_82 (`00000219`) | SFTP Server | On Premise | **Production** | $3,150 |
| ABARule_83 (`00000220`) | Remote Automation Agent | On Premise | **Non-Production** | $1,575 |

The user keeps the **default Feature = SFTP Server** and only flips **Server Type → Non-Production**,
producing **{SFTP Server, On Premise, Non-Production} — which has NO row**. The two existing rules
differ on *both* Feature and Server Type, so a single-attribute flip matches neither → the
AttributeDiscount step makes no change → `NetUnitPrice` passes through at list/Production = **$3,150**.

**Live confirmation (Order 00095353):** three lines carry `{SFTP Server, On Premise, Non-Production}`
(captured, `IsPriceImpacting=true`) yet price at $3,150 = list — exactly the reported symptom.

**Ruled out (adversarially):** procedure not consuming Server Type ❌ · computed-but-not-applied /
SC-3359 pattern ❌ (these are direct `Override` writes) · "update pricing" didn't re-evaluate ❌ (value
*is* persisted on the line) · family-gated for Perpetual ❌ (branch is ungated).

### ✅ Solution

**Confirm the business rule first** — is Non-Production a *uniform* discount, or per Feature/Deployment?
That decision picks the fix:

- **Option A (recommended if uniform) — replace the brittle 3-attribute Overrides with a single
  Server-Type adjustment.** One `AttributeBasedAdjustment` keyed on a **single condition**
  `Server Type = Non-Production` (percentage, e.g. −50%, or an Override), so it applies to **every**
  Feature × Deployment automatically. Eliminates the sparse-matrix maintenance burden (today only 1 of
  N feature combos has any Non-Production row).
- **Option B (minimal) — add the missing combo row.** Create `AttributeBasedAdjustment` (Override) +
  `AttributeBasedAdjRule` + 3 `AttributeAdjustmentConditions` for
  `{Feature Options=SFTP Server, Deployment Option=On Premise, Server Type=Non-Production}` on
  `01tWC00000DD11YYAT`, schedule `84Xa50000010nWQEAY`, at the business-confirmed value. Fixes the
  reported case only; the rest of the matrix stays broken.

**Gate before loading either:** the adversarial pass **never observed any live AA line pricing to an
Override value** (`Has_Attribute_Adjustment__c=false` everywhere; the existing `{RAA, Non-Production}`
row was not seen firing). Run a **pricing-waterfall trace** on a `{SFTP Server, On Premise,
Non-Production}` line to confirm the Override branch actually executes and is not globally **inert**
(decision table not built/active, or a later step overwriting net) — if it's inert, the fix is bigger
than adding a row. This is **config/data**, not a procedure code change. Prior-art analogue: SC-3359
(same symptom, different cause/fix layer — do **not** co-fix).

---

# Issue #2 — $0.00 Net when adding products at the order level  🟡 LOWER

### Root cause — non-deterministic RLM **-$3,150 full-list zeroing** (SC-3347/SC-3345 family)

On Draft Order **00095353**, lines 5 & 6 (AAM, added directly at order level) show List/Unit = $3,150
but **Net = Total = $0**, driven by `TotalAdjustmentAmount = -$3,150`. The base price *is* found
(`RoundedLineAmount=3150`) then zeroed by the RLM pricing waterfall — **no** discount/override field is
set (`Price_Overriden__c=false`). The source **Quote `0Q0WC0000035mLd0AI` is 100% clean** — the $0 is
**introduced at the order level**, not carried from the quote.

**Adversarial corrections:** the discriminator is **not** "order-level add" (the same zeroing hits
batch/conversion lines too — 00095355 zeroed one of two same-timestamp lines); it's **erratic** across
orders (00095354: 0/3 · 00095355: 1/2 · 00095353: 2/5), **survives Reprice All**, and is
**Server-Type-independent**. The two obvious decision-table steps were ruled out (their source objects
are empty/positive-only; per-line adjustment buckets are $0, so -$3,150 is the *derived* residue — net
was set to $0 directly upstream). **The exact emitting step is not yet pinned.**

### ✅ Solution

1. **Pin the emitter:** live pricing-waterfall trace on a controlled repro — add N identical AAM lines
   to a Draft order → Reprice All → capture which line gets `NetUnitPrice=0` and from which
   `Rev_Mgmt_Default_Pricing_Procedure` step / prehook (candidates: a grouping/aggregate or bundle/
   dedup step keyed on repeated-identical lines).
2. **Fix in the pricing workstream:** this is the SC-3345/SC-3347 **-$3,150 family** — coordinate the
   fix there (cause-ownership routes to SC-3345; SC-3347 owns the latent Workday downstream). **Not a
   one-line config change** and **not** a duplicate of SC-3347.
3. **Interim workaround:** avoid adding duplicate AAM lines directly on the order; build them on the
   quote (quote-origin lines priced correctly here) and convert.

---

# Issue #3 — "Order Submission to Revenue Orchestrator" fails on Activate  🟠 BLOCKER

### Root cause (HIGH confidence) — **re-submit of an already-decomposed order** (NOT SC-3308)

The error is thrown by the Active record-triggered flow **`Order_Submission_to_Revenue_Orchestrator`**
(fires on `Order.Status → Activated`), which calls standard **`submitOrder`** with
`flowTransactionModel=CurrentTransaction` → a fault rolls the whole activation back, leaving the order
**Draft** (matches observed state).

**Timeline (live):** 00095353 was Activated → submitted → **Decomposed on its first pass with lines
1-4** (`SalesTransactionFulfillReq 1FjWC000006Vegr0AC` composed 16:38:40; **4 FulfillmentOrders**
16:38:45). It was then reopened to Draft (the Issue #2 "modification" path), lines 5 & 6 appended
(16:44 / 16:51), and re-Activated. Re-activation re-fires the flow → a **second `submitOrder` against
an order whose fulfillment plan is already in-flight** (`Fulfilling` / `Decomposed` / `InProgress`).
Only **one** `OrderAction` (Type=Add) exists — **no amendment**. submitOrder can't reconcile the 6-line
order against the 4-line in-flight plan → throws synchronously → rollback. No `RevenueTransactionErrorLog`
row (consistent with a synchronous CurrentTransaction rollback; the "Error ID" is a platform SBMS
reference, not a stored message).

**Not SC-3308:** 00095353 is `CompletedWithPricing / ValidationResult=null / Decomposed` — the **inverse**
of SC-3308's `CompletedWithoutPricing` race; different error string; SC-3308's v21 reprice fix runs
*before* `Status→Activated`, so it never touches this manual re-activate path → **related-to, not
duplicate-of**. **$0 lines are not the cause:** order **00095293** threw the identical error with a
single fully-healthy line. Transient/retry ruled out (00095293's precedent is disanalogous; order is
frozen at the failed state).

### ✅ Solution

1. **Use the supported amend path:** modifying an already-**decomposed** order must go through
   **`initiateAmendment` / a change order**, not reopen-to-Draft + bare re-Activate. Implement one of:
   - **Guard:** block (or warn on) re-activation of an order whose `SalesTransactionFulfillReq` is
     already `Fulfilling/Decomposed/InProgress`, with a clear message pointing users to the amendment
     flow — instead of the silent rollback toast.
   - **Route:** have the modify-after-activate UX initiate an amendment/change order so appended lines
     decompose into the existing plan.
2. **Check the dependency before scoping separate RevOrch work:** confirm whether fixing Issue #1/#2
   (so no $0 lines exist) lets the activate succeed on its own — a live re-activate of a healthy
   already-decomposed order isolates this. The $0 lines may be coincident rather than causal.
3. **Likely resolution:** primarily a **workflow/process** fix (amendment path + guard), *not* a
   pricing fix. Confirm direction with Nir (owns the convert/activate path, per SC-3308).

---

## Relationship map (all three need NEW work)

| Issue | Shares with | Relationship | Same fix? |
|---|---|---|---|
| **#1** | SC-3359 (Partner Pricing) | symptom only | ❌ #1 = missing config row; SC-3359 = computed-not-propagated |
| **#2** | SC-3347 (Workday) · SC-3345 (rollups) | shares -$3,150 symptom; cause → SC-3345 | ❌ pricing cause still open |
| **#3** | SC-3308 (same flow gate) | related-to; distinct trigger | ❌ SC-3308 v21 fix doesn't cover this path |

> The "Issue #1 is the only new investigation" theory was **refuted** — #2's pricing cause is
> open and #3 is a distinct mechanism. Parent under **SC-3143** alongside SC-3347/SC-3308.

## Acceptance criteria

**Issue #1 — Server Type drives net price**
- [ ] Pricing-waterfall trace confirms the Override branch fires (not inert).
- [ ] Business sign-off on the Non-Production value/rule (uniform % vs per-combo).
- [ ] `{SFTP Server, On Premise, Non-Production}` reprices below $3,150; Production unchanged; no regressions.

**Issue #2 — No $0 net at order level**
- [ ] Trace pins the step emitting the -$3,150 zeroing.
- [ ] Order-added AAM lines price Net = List, deterministically (incl. duplicates).

**Issue #3 — Activation works or fails safely**
- [ ] Confirm whether fixing #1/#2 clears the Activate, or a separate RevOrch fix is needed.
- [ ] Modify-after-decompose uses an amendment/change-order path; re-activation no longer throws, or is blocked with a clear message.

**DoD:** root cause + fix documented; config as deployable metadata; linked to SC-3359/SC-3347/SC-3345/SC-3308 under SC-3143; verified in UAT.

## References

- Reported via Teams (Joe Romo), 2026-06-06 12:03 PM. Affected: Quote *Q-Test After Fix 06-06-26* (`0Q0WC0000035mLd0AI`), Order **00095353** (`801WC00000kGxGCYA0`).
- Priced bundle: `Advanced Authentication Modes` `GS-GSE-NRPS-AAMP` / `01tWC00000DD11YYAT`.
- Pricing engine: [`Rev_Mgmt_Default_Pricing_Procedure`](../../../force-app/main/default/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml). RevOrch flow: `Data/sc3308/uat_fresh_20260605/flows/Order_Submission_to_Revenue_Orchestrator.flow-meta.xml`.
- Evidence (read-only SOQL + adversarial verification, 2026-06-07): [`Data/sc3360-advanced-auth/`](../../../Data/sc3360-advanced-auth/) — 19 files.
- Related: SC-3359 (Partner Pricing), SC-3347 (Workday $0-net), SC-3345 (pricing rollups), SC-3308 (convert/RevOrch), parent SC-3143 (Integration E2E).
