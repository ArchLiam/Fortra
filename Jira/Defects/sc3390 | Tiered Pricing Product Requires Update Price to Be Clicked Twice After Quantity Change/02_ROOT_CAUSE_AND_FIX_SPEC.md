# SC-3390 — Root Cause Analysis & Fix Specification

> **⚠️ SUPERSEDED by `06_FIX.md` (2026-06-11).** This doc's "PLAUSIBLE‑UNPROVEN" verdicts and "(c)→(a)‑gated /
> recommend (e) first" sequencing predate the live trace. The root cause is now **CONFIRMED** (`05_…`) and fix
> **(a) `IsPriceImpacting=true`** is **shipped & validated**. Read for the RCA detail; trust `06_FIX.md` for status/fix.

**Ticket:** SC-3390 — "Tiered Pricing Product Requires Update Price to Be Clicked Twice After Quantity Change"
**Org:** FortraUAT (sandbox). Investigation was **strictly read-only** — no DML, no deploy, no quote mutation.
**Author:** RCA synthesis for Liam (owner), Nir Kailash & Marc DeBrey (pricing).
**Date:** 2026-06-11
**Status of root cause:** **PLAUSIBLE — best-supported, not yet confirmed by a live debug trace.** The single decisive test (a 2-click boundary-cross repro with debug logs) requires authorization to mutate a quote and was **not performed** under the read-only constraint. See §7–8.

> **Ground-truth drift note (non-load-bearing but correct the record):** The task brief and several memory entries state the live pricing procedure is **V9**. It is **V12** (created 2026-06-11 by Nir Kailash; `Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V120`, Status=Active; V1–V11 Inactive). Evidence: `evidence/proc-version-status.txt`. The dispatch mechanism and prehook wiring are unchanged across versions, so the RCA holds; but any procedure-step citations below are against **live V12**, not V9. The local `force-app` copy is badly stale (only V1 Active + 1 inactive + 1 draft) — do not diff against it.

---

## 1. TL;DR

When a rep "changes the quantity" on a tiered product, they are **not** editing the standard `QuoteLineItem.Quantity` field — they are typing into a Product-Configurator attribute called **"Unit Quantity"** (internal DeveloperName `Attribute_Volume`, `AttributeDefinition 0tjWC0000000tqvYAA`), stored on a child `QuoteLineItemAttribute` record. The tiered-pricing prehook (`AttributeVolumePricingPrehook`) range-matches the tier **solely from the pricing-context snapshot** of that attribute — never from the live record. The best-supported root cause is a **one-cycle stale-context snapshot**: the freshly-typed Unit Quantity value is **not present in the context the FIRST "Update Price" click prices against**, so the prehook reads the OLD (or null) volume, applies the OLD tier — or, on null, **silently resets the line to List Price** — with no error. By the SECOND click the new value has been committed and is in the snapshot, so the prehook matches the correct tier. A strong contributing factor is that the Unit Quantity attribute is **`IsPriceImpacting = false`** on all 26 tiered products (confirmed at the `ProductAttributeDefinition` level, not just the instance), which means editing it does **not** auto-trigger a clean same-cycle reprice the way a price-impacting edit would. **Honest confidence:** the mechanism's *direction* is confirmed by code + live data; the exact **first-click-reads-old-volume** step is **unproven** because no captured debug log reaches the volume read — every log early-returns at the eligibility gate. The top next action is an authorized live repro with debug logs (§7–8).

---

## 2. Confirmed mechanism (step-by-step)

Legend: **[CONFIRMED]** = backed by code and/or live evidence in `Data/sc3390/evidence/`. **[PLAUSIBLE-UNPROVEN]** = mechanistically coherent and consistent with all evidence, but the decisive trace is missing.

### 2.1 The UI and the "Update Price" button — [CONFIRMED]
- There is **no custom "Update Price" button** anywhere in `force-app` or `Org Data/_src`. The quote line editor on FlexiPage **`Quote_Record_Page`** is the **standard managed RLM** Transaction Line Editor, built from `runtime_revenue_foundation:transactionLineTable` (props `enableQuickAdd=true`, `enableSidepanel=true`), `:transactionSummary`, and `:progressIndicator`. Evidence: `evidence/ui-flexipages/`, `evidence/ui-FINDINGS-summary.txt`.
- Clicking "Update Price"/"Reprice" fires the managed Connect REST pricing call **`POST /connect/core-pricing/price-contexts/`** → **`/connect/rev/sales-transaction/actions/place`**, confirmed by live `PricingApiExecution` audit rows (`evidence/ui-pricing-api-exec.json`, ApiType=Pricing) and the captured place ApexLogs.

### 2.2 The tier driver is `Attribute_Volume`, not `Quantity` — [CONFIRMED]
- `AttributeDefinition 0tjWC0000000tqvYAA`: `DeveloperName=Attribute_Volume`, `Name='Unit Volume'`, **`Label='Unit Quantity'`**, `DataType=Number`, description **"Volume for attribute-based tier pricing. Entered by reps in Product Configurator."** Evidence: `evidence/attribute-volume-definition.txt`, `evidence/volume-binding-attributedefinition.txt`. This is why the ticket says "quantity."
- It is stored as a `QuoteLineItemAttribute` (child of QLI), **decoupled** from `QuoteLineItem.Quantity`. Live data: across 150 "Unit Volume" rows the value equals the parent Quantity in **0/150** cases (`evidence/verify-quantity-to-volume-data-sync-lag-live-qlia.json`); typical tiered line carries `Quantity=1` with Unit Volume null or a number like 50/100.
- **No automation syncs Quantity → Attribute_Volume.** All 302 `ProductConfigurationRules` have 0 Set-Attribute actions and 0 references to `Attribute_Volume`/`Quantity` (`evidence/volume-binding-all-config-rules.json`); repo-wide grep finds `Attribute_Volume` **only** in `AttributeVolumePricingPrehook.cls` + `QLDescriptionGeneratorPrehook.cls` (and their tests). The prehook only **reads** it, never writes it.

### 2.3 How the prehook reads the volume and prices the tier — [CONFIRMED] (code)
File: `Org Data/_src/classes/AttributeVolumePricingPrehook.cls` (live class `01pWC000001wAzJYAU`, ApiV64; live body byte-identical to local mirror except a trailing newline — `evidence/live-vs-local.diff`).
- Const `ATTR_VOLUME_NAME = 'Attribute_Volume'` (**cls:33**).
- Eligibility gate: reads `Has_Attribute_Adjustment__c` from the `SalesTransactionItem` context tag (**cls:182**); skips any line where it != true; early-returns `'No eligible line items (Has_Attribute_Adjustment__c = true)'` (**cls:201**) when none qualify.
- Volume read: `getAttributeVolumeValue(lineAttributes)` (**cls:279**, impl **cls:783**) reads the value **only from the context snapshot** — `industriesContext.queryTags` over `SalesTransactionItemAttribute` tags. It **never** queries the live QLI/QLIA and **never** reads `QuoteLineItem.Quantity`.
- Debug marker on every priced line: `System.debug(..., 'Attribute_Volume: ' + volume)` (**cls:280**) — this is the line a live repro must capture.
- Tier match: `findMatchingTier` (**cls ~385–433**) range-matches `volume >= Lower_Bound__c && (Upper_Bound__c == null || volume <= Upper_Bound__c)` against `Attribute_Tier_Pricing_Storage__c`, keyed by Product | PSM | AttrName | AttrValue.
- Writes outputs back to **context** (not sObjects) via `updateContextAttributes`: `Base_Price__c` (= `Tier_Value__c`), `Attribute_Price_Mode__c`, and (Calculated mode only) `Attribute_Multiplier_Pct__c` (**cls:468/474/482**).
- **Reset paths** (the silent-stale fingerprint):
  - `volume == null` → `buildResetNodeUpdate` → writes `Base_Price__c = ListPrice`, `Attribute_Price_Mode__c = 'Unit Price'` (**cls:282–289**, builder **cls:529–548**). No exception, no warning.
  - tier match == null → same reset (**cls:294–303**).
- The prehook's **own** output is consumed same-cycle by the downstream V12 steps (`AttributeValuePricingCalculatedMode33` / `TotalPriceMode36` / `UnitPriceMode30` → `InputUnitPrice` → `AttributeBasedPrice` → `NetUnitPrice`). There is **no downstream lag** (see §3, refuted candidate `total-price-mode-net-channel`). Therefore the only way to get "old-then-new" across two clicks is a **stale INPUT volume on click 1**.

### 2.4 The lag itself — [PLAUSIBLE-UNPROVEN]
The load-bearing claim: **on the first click the context snapshot does not yet carry the rep's new Unit Quantity**, so the prehook prices the old/null volume; on the second click it does. Supporting structure:
- The prehook reads volume **only from the context snapshot** taken at dispatch start (§2.3) — [CONFIRMED]. So if the new value isn't in that snapshot, the wrong tier is deterministic.
- The Unit Quantity attribute is **`IsPriceImpacting=false`** on all 26 tiered `ProductAttributeDefinition`s incl. CLSAAS (`PAD 0v7WC0000000TvBYAU`), `DefaultValue=null` — confirmed at the **definition** level, not just the instance (`evidence/verify-nonpriceimpacting-attr-write-after-reprice-PAD.txt`). A non-price-impacting attribute edit does not auto-enlist a clean reprice the way a price-impacting one does — [CONFIRMED that the flag is false; PLAUSIBLE that this is what opens the window].
- The codebase has a **documented identical disease**: `quoteLineFlexPanel.js` does `updateRecord` → `sleep(2000)` "to let any platform processes settle" → reprice; SC-3308 is the activate-before-reprice variant; `COLAUpliftPrehook.cls:1144–1150` documents a TLE timing gap "flag only set by trigger AFTER pricing write-back." This is the same one-cycle-stale-then-converge family — [CONFIRMED such bugs exist here].

**What is NOT yet proven:** no captured ApexLog reaches `cls:280` ("Attribute_Volume: …"). Every captured reprice/place log (`log-place-04-34-13.txt`, `log-aura-12-45-03.txt`, and the four large `07LWC…` logs) early-returns at `cls:201` `'No eligible line items'` because the captured contexts contained no eligible tiered line. So the precise first-click-reads-old-volume step is **inferred, not observed**. (§7)

### 2.5 The live "frozen" lines are consistent with the reset path — [CONFIRMED as data-explained, NOT as proof of the timing bug]
On the actively-edited symptom-class quote `0Q0WC0000037swP0AQ` (`evidence/quote-37swP-lines.txt` + `evidence/verify-…-clsaas-attrs.txt`): 13 CLSAAS lines are frozen at `Base_Price__c=2180`, mode `'Unit Price'` (= the verified CLSAAS USD List Price, PBE `01uWC000004dScBYAU`). This is **fully explained by static data**, not by snapshot lag: 12/13 have `Feature Options='Managed Service'` with **Unit Volume = null** → reset on null (cls:282); the 13th has `Feature Options='Console'` with Unit Volume=100.0, but the CLSAAS tier table carries **only** Self Managed / Managed / Managed Service rows (0 'Console' rows org-wide) → reset on no-match (cls:294). These lines are in their **terminal-correct state for their current data** — repricing again would not change them. **Do not cite these as direct proof of the click-twice timing bug** (see §3, this was the originally-claimed "corroboration" that was refuted).

---

## 3. Candidate table — verdicts and decisive evidence

| Candidate | Verdict | Decisive evidence (why it was settled) |
|---|---|---|
| **`nonpriceimpacting-attr-write-after-reprice`** — Unit Volume is `IsPriceImpacting=false`; first reprice snapshots OLD volume, second the new value | **PLAUSIBLE — best-supported, UNPROVEN** | `IsPriceImpacting=false` confirmed at PAD-definition level on all 26 tiered products incl. CLSAAS `0v7WC0000000TvBYAU` (`verify-…-PAD.txt`); prehook reads volume only from context snapshot (cls:121/279/783); output consumed same-cycle → only a stale **input** explains old-then-new. **BUT** all three pieces of originally-cited "corroboration" were **refuted** (timestamp inversion = unrelated line CREATE; frozen-2180 = static data; zero log reaches the volume read). Decisive proof (paired 2-click debug log) requires authorized DML and was not run. |
| **`configurator-commit-async-relative-to-reprice`** — configurator QLIA save and reprice are separate async txns; reprice context built before QLIA commit | **REFUTED** | In the place txn (`log-place-04-34-13.txt`, `07LWC00000OqoxN2AR`) the prehook reads volume from a **transient** runtime context (`ctxInstanceId='0000000s272q18g00251…'`, an ephemeral id, not a persisted `0Q0/0QL` id) — **0** persisted-QLIA SOQL for Unit Volume in the whole txn. Txn ordering is **PRICE-then-PERSIST**: prehooks + `updateContextAttributes` (L23370) run **before** the QLI persist (L23505–26206). So there is no "context-build precedes the QLIA commit" window inside the place txn. *(Surviving narrow variant: the side-panel UI not putting the just-typed value into the FIRST request payload — but that collapses into the `IsPriceImpacting=false` snapshot story, not this candidate's commit-race.)* |
| **`async-pricing-mode-first-click-returns-before-settle`** — RLM async/deferred pricing returns before the background recompute settles | **REFUTED** | Org settings: `IndustriesPricing.enableLargeTransactionPricing=false`, `enablePricingProcParallelization=false`, `enableHighAvailability=false`; `RevenueManagement.enableDeltaPricing=false`, `enableTransactionProcessor=true` (synchronous). The place txn returns a `RevSignaling.TransactionResponse` **inline** ("executed 1 time in 367 ms") and writes priced QLI in-txn. The only post-place async job is the COLA `MyCAPFlagApplier` (writes `Quote.Mycap__c` only). `progressIndicator` is a UI affordance, not proof of async pricing. |
| **`has-attribute-adjustment-eligibility-flag-lag`** — `Has_Attribute_Adjustment__c` stamped one cycle late; first reprice sees line ineligible | **REFUTED** | The flag has **no setter anywhere**: grep `'Has_Attribute_Adjustment__c ='` across all Apex returns only a test-assert, a comment, and the early-return literal (cls:201); the 4 live active QLI RecordBeforeSave flows don't write it; no trigger writes it; the procedure only reads it as a gate. A one-cycle lag logically requires a setter. (Contrast: COLA's `Is_COLA_Overridden__c` IS set by `COLAUpliftHandler.cls` — that's why it can lag.) Live: symptom quote's tiered lines already carry the flag `=true` **before** click 1 (`quote-37swP-lines.txt`), so for the change-quantity case there is nothing to flip. *(Could still matter for first-add-then-change flows, but not the literal SC-3390 scenario.)* |
| **`total-price-mode-net-channel-downstream-lag`** — prehook writes correct `Base_Price__c` but V12 consumer steps propagate to Net only on the 2nd pass | **REFUTED** | Byte-normalized **V11-vs-V12 step diff**: every consumer step (`AttributeValuePricingCalculatedMode33`, `TotalPriceMode36`, `UnitPriceMode30`, `AttributeBasedPrice`, `QuantityPrice57`, `SubscriptionPricing/73`, ListContainer5/6/7) is **UNCHANGED**; the entire V11→V12 delta is confined to Derived/Renewal/Partner/COLA. The chain is a **single synchronous DAG pass** (V12 L1073–1302 → InputUnitPrice; L700–797 → NetUnitPrice in the same pass); identical context in ⇒ identical Net out. The sc3384 "Total-Price Net=0" surface is **persistent/does-not-converge** — the opposite of SC-3390's convergence. Convergence ⇒ the INPUT differs between clicks ⇒ points **upstream**, not downstream. |
| **`static-recursion-guard-skips-effective-pass`** — `isUpdating` static guard skips the effective pass on a nested dispatch | **REFUTED** | The prehook's only write-back is `updateContextAttributes` — a synchronous in-place context write that does **not** re-trigger the ExpressionSet (the procedure calls the prehook, not vice-versa). Across **7** FINEST logs: `AttributeVolume` START=1, END=1, `'Skipping recursive execution'`=0 — zero nested re-entry. Apex statics reset per transaction and each click is its own txn, so `isUpdating` cannot carry state across the two clicks (candidate concedes this). Single live class id (no double-registration). |
| **`async-queueable-tail-requote`** — post-place `MyCAPFlagApplier` queueable does QLI DML that re-prices over a stale context | **REFUTED** | Verified against the **LIVE** class (`01pWC000001wNGbYAM`, modified today by Nir; local mirror is 546 diff-lines stale): `MyCAPFlagApplier.execute()` (L1157–1192) does `Database.update` on `List<Quote>` for `Quote.Mycap__c` **only** — no QLI DML, no reprice. It is **renewal-gated** (`if (stActionType != 'Renew') continue;`, early `return 0` when no renewal lines) and never enqueues on the non-renewal tiered path. Captured queueable runs show `toUpdate=[]`, 0 DML_BEGIN, 0 place callout. *(Latent regression risk only — guarded by a code comment.)* |
| **`quantity-to-volume-data-sync-lag`** *(intuitive reading of "quantity")* | **REFUTED (DEAD)** | No writer of `Attribute_Volume` exists: prehook only reads it; 302 PCRs have 0 Set-Attribute actions and 0 references; no flow/trigger references it. Live: value == parent Quantity in **0/150** rows — fully decoupled, inconsistent with any sync (lagging or not). The "quantity" in the ticket = the rep-typed `Label='Unit Quantity'` configurator attribute, not `QuoteLineItem.Quantity`. **Reviewers should not re-chase a Quantity→Volume sync.** |

**Explicitly refuted — do not re-investigate:** async-pricing-mode, configurator-commit-async-race (as a *persisted-QLIA* commit race), Has_Attribute_Adjustment eligibility lag (for the change-quantity case), downstream net-channel lag, static recursion guard, queueable tail re-quote, and any Quantity→Volume data sync.

---

## 4. Why no error is shown (the silent stale-price risk)

The prehook is **designed to never error** on a missing/non-matching volume — it **falls back to List Price** instead:
- On `volume == null` (cls:282–289) and on no-tier-match (cls:294–303) it calls `buildResetNodeUpdate`, which writes `Base_Price__c = ListPrice` and `Attribute_Price_Mode__c = 'Unit Price'` (cls:529–548) and returns a normal SUCCESS response — **no exception, no warning, no validation message.**
- The managed `transactionLineTable` therefore reports the pricing run as **Success** and refreshes the grid with whatever the (stale) snapshot produced. There is no loading/disabled state tying the displayed price to "is this reprice based on the value I just typed?"
- Net effect for the rep: after click 1 they see a **plausible, non-zero, no-error price** (either the old tier or the clean List Price). Nothing signals it is stale. They only discover the correct tier price if they happen to click "Update Price" again. **This is the core reps-quote-stale-prices risk.**

The same reset logic also explains the field-observed "frozen at List Price 2180" cluster (§2.5) — those lines are at List because their current Unit Volume data is null or non-matching, and the engine silently reset them rather than flagging a problem.

---

## 5. Scope / blast radius

- **Affected:** any quote line on a **tiered / Attribute-Volume product** where the rep edits the **"Unit Quantity"** configurator attribute and crosses (or sets) a tier boundary, then clicks "Update Price." The 26 tiered products carrying `Attribute_Volume` (all `IsPriceImpacting=false`) — top ones by tier-row count: Security Awareness (`HRM-HRM-RSL-SEAW`, 159 rows), Security Awareness Program (`HRM-HRM-RSL-SAPS`, 134), Fortra VM Standard (`VM-VLM-RSL-FVSS`, 100), Fortra Pen Test External (`VM-DDL-RSL-FPTES`, 76), Tripwire ExpertOps (`FIM-FIM-RSP-*`, 50 each), Click and Launch SAT (`HRM-HRM-RSL-CLSAAS`, 37). Full PAD list: `evidence/verify-…-PAD.txt`.
- **Eligibility:** only lines with `Has_Attribute_Adjustment__c = true` are priced by the prehook at all; only 51 of 12,295 sampled tiered lines (77 org-wide) carry the flag true. So the at-risk population is the **subset of tiered lines that are tier-eligible AND get a Unit Quantity edit** — not every tiered line.
- **Immune:** **non-tiered lines are immune** — the prehook skips any line where `Has_Attribute_Adjustment__c != true` (early return cls:201), and non-tiered products have no `Attribute_Volume` attribute and no tier rows. Editing standard `QuoteLineItem.Quantity` on a non-tiered product follows the ordinary synchronous reprice and does not exhibit this lag.
- **Severity:** correctness/financial — reps can save and send a quote at a **stale tier price** (e.g., still on the 1–49 tier after entering 50) with **no warning**. Whether it manifests every time depends on the exact UI commit timing of the side-panel attribute save relative to the reprice (the unproven window).

---

## 6. Fix options (ordered)

> **Platform constraints (from memory — must respect):** `Rev_Mgmt_Default_Pricing_Procedure` version **hard-delete is blocked** (UI+API+REST). Any procedure change = **new ExpressionSetVersion → republish → context re-sync** (`SalesTransactionContextExt_v2`). **Do NOT remove** the two `PricingActionParameters` bindings (Order `17gWC…AvYAK`, Quote `17gWC…AwYAK`). Leave inactive versions in place. **Any UAT deploy/DML (even validate-only) needs a fresh explicit authorization.**

### (a) ROOT-CAUSE FIX — make the Unit Quantity edit participate in the same-cycle reprice
**Change type:** config (`ProductAttributeDefinition.IsPriceImpacting`) on the 26 tiered products, then validate behavior.
**What it does:** Flips `Attribute_Volume`'s `IsPriceImpacting` from `false` → `true` so the platform treats a Unit Quantity edit as a price-affecting change and folds it into the same pricing cycle / re-snapshots the context before pricing — closing the one-cycle window so the first click already carries the new value.
**Risk:** Medium. (1) The causal claim "`IsPriceImpacting=false` is what opens the window" is **plausible-unproven** — if the real window is the **side-panel save timing** rather than the flag, this alone may not fully fix it (validate with the §8 repro before declaring done). (2) Setting it true may trigger additional auto-reprices on every Unit Quantity edit (more pricing calls / latency). (3) Must be applied to all 26 PADs consistently. **No procedure version change required**, so the ExpressionSet republish/context-resync constraint does not apply to this option.
**Validation:** the §8 repro (49→50 CLSAAS boundary cross) must price correctly on the **first** click; debug log shows prehook cls:280 reading the **new** volume on click 1; regression-check a sample of tiered + non-tiered lines for unintended reprice churn.

### (b) ROOT-CAUSE-ADJACENT — guarantee the typed value is committed before the reprice (UI/flow sequencing)
**Change type:** depends on whether a custom wrapper sits behind the per-line button (current evidence: it is the **managed** `transactionLineTable`, so there may be **no** code seam to change — in which case this is a Salesforce platform case, not a local fix).
**What it does:** Ensures the side-panel `QuoteLineItemAttribute` save **flushes and is reflected in the context** before the price-contexts call snapshots it — the explicit, mechanism-targeted version of (a). If a custom LWC wrapper exists (the header-discount panel proves wrappers exist in this org), apply the documented `updateRecord → settle → reprice` ordering (as `quoteLineFlexPanel.js` already does for the discount path).
**Risk:** Medium-High. If the button is purely managed, there is **no local seam** — escalate to Salesforce/RLM. A `sleep`/settle band-aid is the codebase's known anti-pattern and should be a last resort, not a fix.
**Validation:** same as (a); additionally confirm the place-request payload carries the new Unit Quantity on click 1.

### (c) DEFENSIVE MITIGATION — make stale state visible / unreadable (no silent stale price)
**Change type:** UI (managed-component config if available) + optionally a small validation.
**What it does:** Removes the *silent* part of the risk so reps cannot read/quote a stale price unknowingly. Options:
  - Show a loading/disabled state on the line until the reprice settles (if `progressIndicator`/`transactionLineTable` config allows binding the grid to reprice completion), so the displayed price is never a pre-edit value.
  - A submit/convert-time **validation/warning** when a tier-eligible line's stored `Base_Price__c == ListPrice` while a non-null Unit Quantity should match a tier (i.e., detect a likely silent reset) — surface "reprice required" before the quote can be sent.
**Risk:** Low-Medium; does not fix the root cause (reps still need an accurate second reprice) but eliminates the **silent** failure mode (the actual money risk). Must be careful not to false-positive on legitimately List-priced lines (e.g., 'Console'/no-tier-match, which is correctly List).
**Validation:** confirm a deliberately-stale line raises the warning; confirm legitimately List-priced lines do not.

### (d) PRODUCT/DATA HARDENING (parallel, not a fix for the timing bug)
- Several CLSAAS lines reset to List because `Feature Options='Console'` has **no tier rows** and many have **null Unit Volume**. Decide whether 'Console' should have tier rows or whether a null/unsupported volume should hard-warn instead of silently resetting. (Overlaps the §4 silent-reset behavior; coordinate with the prehook owners.)

**Recommended sequence:** ship **(c)** first as a fast, low-risk guard against silent stale prices; pursue **(a)** as the root-cause fix **gated on the §8 live repro confirming the flag is the window**; hold **(b)** for the case where the repro shows the lag survives flag changes (then it is a managed-platform/Salesforce escalation).

---

## 7. Open questions / not-verified / how to get decisive proof

1. **[TOP NEXT ACTION] No captured log reaches the volume read.** Every captured reprice/place log early-returns at `cls:201` `'No eligible line items'` because the contexts had no eligible tiered line. We have **never observed** click-1 reading the old volume and click-2 reading the new one. The single decisive proof is a **paired debug log from an authorized live repro** (see §8). Until then the root cause is **plausible-unproven**.
2. **Is `IsPriceImpacting=false` actually the window, or is it the side-panel save timing?** These are different fixes (config flag vs. UI/managed sequencing). The semantics of `IsPriceImpacting` (auto-reprice-on-change vs. write-commit enlistment) are debatable; the repro must show whether flipping the flag (or just slowing the click) makes click-1 correct.
3. **What persists `Attribute_Volume` and is it synchronous-before or async-during the price call?** No repo flow/trigger does it — it is the managed RLM configurator. Whether the side-panel save commits before the first price-contexts snapshot is the load-bearing unknown.
4. **Is the per-line "Update Price" button purely managed, or wrapped by a custom LWC/flow?** Determines whether fix (b) has a local seam at all.
5. **Latent regression watch (not SC-3390 cause):** the `MyCAPFlagApplier` QLI-DML removal is enforced only by a code comment; re-adding QLI DML to any post-place queueable would reintroduce a DML→reprice→DML loop for renewal quotes. Add a guard/test.

---

## 8. Reproduction & verification plan

**Read-only-safe steps (do now, no authorization needed):**
1. Confirm the at-risk attribute and flag: `AttributeDefinition 0tjWC0000000tqvYAA` (`Label='Unit Quantity'`) and `IsPriceImpacting=false` on all 26 tiered PADs — already captured (`evidence/verify-…-PAD.txt`). Re-run if org may have changed.
2. Confirm async pricing is OFF: `IndustriesPricing.enableLargeTransactionPricing=false`, `RevenueManagement.enableTransactionProcessor=true` — already captured (`evidence/settings-pricing/`, `evidence/settings-retrieve/`).
3. Inspect a tiered quote's current state to read the reset fingerprint: e.g. `0Q0WC0000037swP0AQ` CLSAAS lines frozen at `Base_Price__c=2180` / `Unit Price` with Unit Volume null/Console (`evidence/quote-37swP-lines.txt`, `evidence/verify-…-clsaas-attrs.txt`).

**The ONE step that needs authorization (mutates a quote — DML):**
4. **Live boundary-cross repro with debug logs.** On a scratch/test quote, add a CLSAAS (or any tiered) line, set `Has_Attribute_Adjustment__c=true`, set `Feature Options='Managed Service'`, and set **Unit Quantity = 49** (tier 1–49). Enable a FINEST trace flag on the running user. Change **Unit Quantity to 50** (crosses into the 50–99 tier), click **"Update Price" ONCE**, capture the ApexLog. Then click **"Update Price" a SECOND time** and capture that log.
   - **CONFIRMS the root cause** if: click-1 log shows `cls:280 'Attribute_Volume: 49'` (old) and an old-tier MATCH or a RESET, while click-2 log shows `cls:280 'Attribute_Volume: 50'` and the correct 50–99 tier MATCH.
   - **REFUTES it** if: click-1 already shows `'Attribute_Volume: 50'` (then the lag is downstream/elsewhere — but §3 already refuted the downstream candidates, so this outcome would force a fresh look at managed-component grid-refresh timing).
5. **Fix validation (after authorized config change (a)):** with `IsPriceImpacting=true` on the tiered PADs, repeat step 4. Pass = correct tier price and `cls:280` new volume on the **first** click; also spot-check non-tiered and other tiered lines for unintended reprice churn.

---

## Appendix — key evidence file index (all under `Data/sc3390/evidence/`)
- `live-AttributeVolumePricingPrehook.cls`, `live-vs-local.diff` — live prehook == local mirror (trailing newline only).
- `verify-nonpriceimpacting-attr-write-after-reprice-PAD.txt` — `IsPriceImpacting=false` on all 26 tiered PADs.
- `quote-37swP-lines.txt`, `verify-nonpriceimpacting-attr-write-after-reprice-clsaas-attrs.txt`, `unit-volume-recent.txt` — live frozen-2180 cluster explained by null/Console data; the "timestamp inversion" line is an unrelated non-tiered CREATE.
- `settings-pricing/`, `settings-retrieve/` — async pricing disabled; synchronous transaction processor.
- `proc-version-status.txt`, `proc-v12-prehook-output-consumers.txt`, `retrieve-v11/` — live V12 active; V11↔V12 consumer steps unchanged.
- `volume-binding-all-config-rules.json`, `verify-quantity-to-volume-data-sync-lag-live-qlia.json` — no Quantity→Volume sync; fields decoupled.
- `verify-async-queueable-tail-requote-*` — live COLA prehook writes only `Quote.Mycap__c`, renewal-gated.
- `log-place-04-34-13.txt`, `log-aura-12-45-03.txt`, `log-07LWC*.txt` — all early-return at the eligibility gate; none reaches the volume read (the proof gap).
