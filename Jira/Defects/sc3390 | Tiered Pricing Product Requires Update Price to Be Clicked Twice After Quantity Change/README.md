# SC-3390 — Tiered Pricing Product Requires Update Price to Be Clicked Twice After Quantity Change

> ## ✅ FIXED & VALIDATED IN UAT (2026-06-11) — see **`06_FIX.md`**
> Root cause **proven** by live FINEST trace (`05_…`); fix **shipped & validated on 2 products**.
> **Fix = `ProductAttributeDefinition.IsPriceImpacting false→true` on all 26 tiered Unit‑Quantity PADs + Sync Pricing Data** (option **a**).
> CLSAAS 49→50 and SEAW 499→500 now price correctly on the **first** "Update Prices" click.
> **Sections below 2–8 are the original RCA and are SUPERSEDED by `06_FIX.md`** (they still read "plausible‑unproven / recommend (e) first").
> Open items: **prod promotion is BLOCKED** (prod has none of the RLM stack) and a **durability gap** (the flag is PAD data a refresh/Gearset migration can silently revert) — both detailed in `06_FIX.md §6/§6a`.

**Jira:** SC-3390 (Salesforce-Coastal) · **Type:** Task · **Status:** Fixed in UAT (root cause proven, fix validated; prod blocked on RLM cutover)
**Assignee:** Liam Jeong · **Reporter:** German Wren · **Labels:** CRM-RevenueCloud, LOB-Salesforce-1-UAT
**Org:** FortraUAT (sandbox) · **Investigation:** strictly **read-only** (no DML, no deploy, no quote mutation)
**Created in repo:** 2026-06-11

---

## 1. Problem statement (verbatim)

When quoting a **Tiered Pricing** product, changing the quantity does **not** update the price the first
time the user clicks **Update Price**. The user must click **Update Price** a **second** time before the
quote-line pricing updates correctly. **No** error/warning/loading indicator is shown after the first click.
**Risk:** sales reps may believe pricing updated after the first click and quote stale prices to customers.

**Success criteria:** tiered quote-line prices update correctly on the **first** Update Price click; no
double-click required; if pricing can't update on click 1 the user gets a clear error/status; the line never
silently stays at an incorrect price.

---

## 2. Root cause — TL;DR ✅ **CONFIRMED by live FINEST trace (2026-06-11) — see `05_LIVE_REPRO_RESULTS.md`**

**PROVEN:** on a live repro, after changing Unit Quantity 49→50, the **first** "Update Prices" click logged
`Attribute_Volume: 49` (old) → priced the 1–49 tier (1231.2); the **second** click logged `Attribute_Volume: 50`
→ priced the 50–99 tier (1357.2). The volume commits to the pricing context **one reprice cycle late**, and every
mismatch is a **silent** `RESET … resetting to list price` (no error). The engine prices its input correctly
every time → the defect is the **stale input**, not the engine. Fix focus: **(e) Instant Pricing** (validate
next), then (a) `IsPriceImpacting`. Original (now-historical) hypothesis writeup follows.

---

### (historical) Root cause hypothesis as written before the trace

The rep's "quantity" is **not** `QuoteLineItem.Quantity`. It is a Product-Configurator attribute named
**"Unit Quantity"** (internal `Attribute_Volume`, `AttributeDefinition 0tjWC0000000tqvYAA`, Number), stored on
a child `QuoteLineItemAttribute`. The tiered-pricing prehook **`AttributeVolumePricingPrehook`** range-matches
the tier **only from the pricing-context snapshot** of that attribute — never from the live record.

Best-supported mechanism = **one-cycle stale-context snapshot**: the freshly-typed Unit Quantity is **not in
the context the FIRST "Update Price" prices against**, so the prehook reads the OLD (or null) volume, applies
the OLD tier — or, on null, **silently resets the line to List Price** with no error. The SECOND click prices
the now-committed value → correct tier. Contributing factor: the Unit Quantity attribute is
**`IsPriceImpacting = false`** on **all 26** tiered products (confirmed at the `ProductAttributeDefinition`
definition level), the plausible reason the edit doesn't auto-trigger a clean same-cycle reprice.

**Honest confidence:** the mechanism's *direction* is confirmed by code + live data; the exact
**first-click-reads-old-volume** step is **unproven** — every captured ApexLog early-returns at the
eligibility gate (`cls:201`) and none reaches the volume read (`cls:280`). The single decisive test (a 2-click
boundary-cross repro with debug logs) **requires authorization to mutate a quote** and was not run. See
`02_…§7–8`. **This is an RCA + fix-spec deliverable, not a fix.**

---

## 3. What "Update Price" actually is (confirmed)

Standard **managed RLM** Transaction Line Editor on FlexiPage `Quote_Record_Page`
(`runtime_revenue_foundation:transactionLineTable`). **No custom "Update Price" button exists** in `force-app`
or `Org Data/_src`. Clicking it fires the managed Connect REST pricing call
`POST /connect/core-pricing/price-contexts/` → `/connect/rev/sales-transaction/actions/place`, which builds the
pricing context, runs the procedure (incl. the custom prehook), and prices **inline/synchronously**
(price-then-persist in one transaction). Fortra owns the **prehook**, not the button or its orchestration.

---

## 4. Candidate verdicts (8 hypotheses, adversarially verified)

| Candidate | Verdict |
|---|---|
| **Unit Volume → first reprice snapshots OLD volume (one-cycle stale context)** | ✅ **CONFIRMED** (live trace: click-1 read `49`, click-2 read `50`; `05_…`) |
| Configurator QLIA-save vs reprice commit race (persisted-QLIA) | REFUTED (place txn is price-then-persist; context from request payload, transient ctx id) |
| Async/deferred pricing returns before settle | REFUTED (async pricing OFF; place returns inline `367 ms`) |
| `Has_Attribute_Adjustment__c` eligibility flag lags | REFUTED (flag has **no setter**; symptom lines already true) |
| Downstream Total-Price net-channel lag | REFUTED (V11↔V12 consumer steps byte-identical; single synchronous pass; converges vs sc3384's persistent Net=0) |
| `isUpdating` static recursion guard skips effective pass | REFUTED (no re-entry vector; guard never trips in 7 logs) |
| Async queueable tail (`MyCAPFlagApplier`) re-quote | REFUTED (writes only `Quote.Mycap__c`, renewal-gated, no QLI DML) |
| Quantity→Volume data sync lag *(intuitive reading)* | **REFUTED — DEAD** (no writer; value==Quantity in **0/150** rows) |

> **Do not re-chase** the refuted seven — each was killed with cited live/code evidence (see `02_…§3`).

---

## 5. Fix options (see `02_…§6` and `03_…§4` for detail, risk, validation)

- **(e) Enable Instant Pricing on the TLE *(NEW — trial first; declarative, reversible):*** the quote line editor
  has Instant Pricing **off** (no property on the `transactionLineTable` in `Quote_Record_Page`), so per Salesforce
  docs *"inline edits … such as updating the quantity … are priced when you save the changes"* — i.e. the manual
  reprice dependency the symptom rides on. Turning it on (App Builder property) reprices on every edit. See `03_…§2,§4e`.
- **(a) Root-cause config:** set `IsPriceImpacting = true` on the 26 tiered PADs (no procedure version change). **Gate on the §8 repro** confirming the flag is the window.
- **(f) Commit-before-hydrate ordering *(NEW framing):*** the volume hydrates from the **persisted** `QuoteLineItemAttribute.AttributeValue` column (context node is already bidirectional — Direction is **not** the bug; `03_…§1.3`). Ensure the side-panel save commits before the first price-contexts hydration (UI/flow sequencing; may be managed → SF escalation).
- **(b) Root-cause-adjacent:** guarantee the typed value is committed/flushed into the context before the reprice (UI/flow sequencing). May have **no local seam** (managed component) → Salesforce escalation. *(Now subsumed by (f).)*
- **(c) Defensive mitigation (ship first):** loading/disabled state + submit-time "reprice required" warning so reps can't read a **silent** stale price.
- **(d) Data hardening:** CLSAAS `Feature Options='Console'` has no tier rows; many lines have null Unit Volume → silent List-Price reset. Decide whether to seed tiers or hard-warn.

**Recommended trial order (updated):** **(e)** Instant Pricing (declarative, reversible) → **(c)** silent-price guard in parallel → **(a)** `IsPriceImpacting` gated on the repro → **(f)** only if the lag survives.

**Recommended sequence:** (c) now → (a) gated on the live repro → (b) only if the lag survives the flag change.

---

## 6. Independently re-verified facts (2026-06-11, read-only)

- Active pricing procedure = **V12** (V1–V11 Inactive). *Corrects the brief/memory which said V9; non-load-bearing.*
- `IsPriceImpacting = false` on **all 26** Unit-Volume PADs, `DefaultValue=null` (incl. CLSAAS `0v7WC0000000TvBYAU`).
- Live `AttributeVolumePricingPrehook` (`01pWC000001wAzJYAU`) == local mirror (trailing-newline diff only).
- `Attribute_Volume` value == parent `Quantity` in **0/150** live QLIA rows (fully decoupled).

---

## 7. Top next action — ✅ decisive repro DONE; next = fix (e) validation

The decisive boundary-cross repro was **performed and confirmed** the root cause (`05_LIVE_REPRO_RESULTS.md`):
click-1 logged `Attribute_Volume: 49` (old), click-2 logged `Attribute_Volume: 50` (new). **Next action:** the
**fix-(e) validation** — same quote/line, flip the configurator's **Instant Pricing** toggle **ON**, redo 49→50,
and confirm the FINEST log shows `Attribute_Volume: 50` + 1357.2 on the **first** action (no second click). If it
does, Instant Pricing is the recommended ship-first fix. Then evaluate (a) `IsPriceImpacting` and the (c)
defensive guard.

---

## 8. Dossier index

| File | What it is |
|---|---|
| `README.md` | this file — ticket + root-cause TL;DR + verdicts + index |
| `02_ROOT_CAUSE_AND_FIX_SPEC.md` | **primary deliverable** — per-candidate RCA, refutation evidence, fix options, repro plan |
| `03_PLATFORM_RESEARCH_AND_INSTANT_PRICING.md` | **web-research addendum** — Salesforce RLM platform docs/community; the **Instant Pricing OFF** finding; the confirmed **DB-hydration path** for the volume attribute; two new lower-risk fix levers (e),(f); sources |
| `04_LIVE_REPRO_RUNBOOK.md` | **authorized live-repro runbook** — pre-armed FINEST trace + safe test fixture (`0Q0WC0000037rFZ0AY` line `0QLWC000003d2QJ4AY`) + exact 49→50 click steps + log-capture/diff harness; why it's UI-decisive only |
| `05_LIVE_REPRO_RESULTS.md` | ✅ **the proof** — live FINEST trace: click-1 read volume `49` (old)→1231.2, click-2 read `50`→1357.2; root cause CONFIRMED; engine refuted; fix-(e) validation is next |
| `evidence/` | small high-signal proofs (PAD/`IsPriceImpacting`, version status, prehook code, verdict notes, UI findings, tier data, **context-mapping hydration**) |

**Heavy artifacts** (multi-MB ApexLogs, full QLI dumps, 958 KB config-rule JSON, V11/V12 retrieves, settings
retrieves) are kept under **`Data/sc3390/evidence/`** and `Data/sc3390/retrieve/` (not duplicated here).

**Method:** read-only RCA via a 15-agent workflow (5 recon → 8 candidate synthesis → 8 adversarial verifiers →
writeup) plus independent inline cross-checks. Workflow run `wf_5431f33d-772`. **2026-06-11 follow-up pass**
(`03_…`): external Salesforce RLM/Revenue Cloud platform-doc & community web research + a read-only
ContextDefinition retrieve — added the Instant Pricing finding, the confirmed DB-hydration path, and fix levers
(e)/(f).

**Related dossiers (same engine):** `sc3384` (non-USD configured pricing — documents the same prehook + tier
storage), `sc3360` (AAMP server-type discount), `sc3349` (`QLDescriptionGeneratorPrehook` uses the same
`Attribute_Volume` as Unit Quantity).
