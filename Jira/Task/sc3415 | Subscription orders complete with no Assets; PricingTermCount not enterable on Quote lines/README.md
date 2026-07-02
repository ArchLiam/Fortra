# SC-3415 — Subscription orders complete with no Assets; PricingTermCount not enterable on Quote lines

| | |
|---|---|
| **Ticket** | SC-3415 (Salesforce-Coastal) — Priority **Critical** — CRM Sprint 14 |
| **Reporter** | German Wren |
| **Assignee** | Liam Jeong |
| **Org** | FortraUAT — **UAT ONLY** (no prod work; org is read-only for this task) |
| **Repro** | Order **00095470** (`801WC00000kYmw8YAC`) — 32 lines, account `001WC00000XiZP4YAN`, quote "Q-Wren - Test GS Quotes w Hardware"; PTC-null draft quote lines on `00095507`/`00095497` |
| **Status** | ✅ **Visibility fix DEPLOYED to UAT 2026-06-15** (Defect A) — `Fortra_Assetize_Order` **V14**, **no new fields** (reuses existing `Order_Integration_Error_Messages__c`); see §9. Defect B (quote-tier PTC) owner-gated, open. |
| **Reconcile** | **Distinct from SC-3411** (which only fixed the null-term *activation blocker*); see §5 |

---

## 1. Summary

Two distinct symptoms are bundled in this ticket, and the lead symptom — **subscription orders activating ("Order Complete") yet generating zero Assets** — is a **NEW failure that SC-3411 does not fix and does not own.**

- **Crux (no Assets):** Order **00095470** activated cleanly (`StatusCode=Activated`, `ActivatedDate=2026-06-11T13:27:30Z`, Contract 00069266 Activated) but produced **0 AssetActionSource / 0 AssetAction / 0 Asset** — all-time, not a window artifact. Critically, **all 12 of its TermDefined lines were fully dated at activation** (`EndDate=2027-06-10`, `PricingTermCount=1`), so the SC-3411 null-term mechanism is **excluded**. The asset failure happens in a **separate async transaction** off activation, and it failed **silently** because that transaction swallows its own fault.
- **Secondary (PricingTermCount not enterable on Quote lines):** On live draft quote lines, **`EndDate` IS populated**; the **only** standard gap is **`PricingTermCount` = null**. `QuoteLineItem.PricingTermCount` is **platform read-only** — only the native RLM pricing engine can write it — and it **stopped deriving for newly-priced lines on 2026-06-11 inside the V12→V13 pricing-procedure churn window.** This is the **true root** of the SC-3411 family at the quote tier (SC-3411 only patched the *order* tier downstream).

Both are real, both block German's renewal/COLA testing, and both are **UAT-scoped**.

---

## 2. Root cause — no Assets on activation (the crux)

### 2.1 Asset generation is a SEPARATE async transaction that fails silently

Asset creation on Order activation runs through the custom flow **`Fortra_Assetize_Order` V12** (`301WC00000geVjHYAU`, Active, AutoLaunched) which **overrides the native RLM flow** (`overriddenFlow=revenue_o2aflows__o2aFlow`). Its `<start>` is `RecordAfterSave` on `Order` (Status=Activated), and the **only** connector is nested under `<scheduledPaths><pathType>AsyncAfterCommit</pathType>`. There is **no synchronous connector**.

> **This is the load-bearing fact.** Asset generation does **NOT** run in the synchronous activation / order-completion transaction. It runs in its **own AsyncAfterCommit transaction with a fresh governor budget**, calling the native `createOrUpdateAssetFromOrder` action and the `PopulateAssetLegacyFieldsAction` Apex. That action's `faultConnector` routes to a "Capture Error (Graceful End)" assignment — so **any failure is swallowed and the order stays `Activated` with zero assets and no surfaced error.** That precisely explains the "Order Complete, no Assets" symptom.

Confirmed downstream behavior:
- The pipeline materializes `OrderItem → AssetActionSource → AssetAction → Asset` ~11–13s after `ActivatedDate` (e.g. 00095471 activated 13:40:45Z → 2 AAS at 13:40:56Z).
- **Line-level gate is `Product2.IsAssetizable`** (`true` on 8,839 / `false` on 15, all Services/Training/PS). All 4 SKUs on 00095470 are `IsAssetizable=true` — config is ruled out.
- `ServiceDate`/`PricingTermCount` do **NOT** gate assetization (null is normal for perpetual/maintenance lines and still assetizes).

### 2.2 What actually failed on 00095470 (and what we proved vs. inferred)

**Proven (live FortraUAT):**
- 00095470 = exactly **32 OrderItems**, all `IsAssetizable=true` → **0 asset rows**, all-time.
- **NOT SC-3411:** all 12 TermDefined lines fully dated at activation; `OrderItemHistory` shows only a "created" row with no `EndDate` null→value transition; SC-3411's V6 backstop never touched them.
- **Pipeline globally healthy that minute:** 00095471 (2 lines) assetized 2/2 ~13 min later; org-wide 17 AAS / 16 AssetAction created on 06-11 while the decision table was already Failed.
- **Account/SKU not broken:** the same SKUs assetized on other orders; 125 lifecycle-managed Assets created in the trailing 7 days.
- **Logs are gone:** 0 ApexLogs for German Wren in the 13:00–14:00Z window on 06-11 — the abort was never captured live.

**Hypothesis (flagged — NOT confirmed):** *governor-limit abort inside the async asset transaction at 32 heavily-duplicated lines.* This is the most likely mechanism but it is **inferred, not observed**, and the original "SC-3366 SOQL-101" attribution must be **softened** for two reasons:
1. **SC-3366 targets the *synchronous* order-completion transaction** — a *different* transaction from the AsyncAfterCommit one that actually assetizes (see 2.1). So a straight SC-3366 fix would not necessarily raise the budget where the asset work runs.
2. **Live data contradicts a clean "≥15 lines fails" threshold:** 00095325 (**18** lines) → **18/18** AAS and 00095377 (**14** lines) → **14/14** AAS both assetized fully. The distinguishing variable for 00095470 is therefore **heavy line duplication** (only **4 distinct SKUs at 10/10/6/6**), making **duplicate-product asset-key collision** an alternative mechanism *at least as consistent with the data* as a governor abort.

**Net root cause (confident portion):** the order activated, but its **async asset-generation transaction failed and was silently swallowed** by `Fortra_Assetize_Order`'s graceful fault handler.

> ⚠️ **RCA CORRECTION (2026-06-15, live-tested).** Two follow-ups refine the mechanism:
> 1. A **safe rollback diagnostic** (`Invocable.Action createOrUpdateAssetFromOrder` on 00095470, rolled back, **3× identical**) returns `INVALID_API_INPUT: "the asset was updated by another process"` using **1 SOQL / 534ms CPU** → **governor-limit / SC-3366 is definitively refuted.** The fault is an **optimistic-lock collision**, deterministic.
> 2. **Plain line duplication is NOT the cause.** Synthetic throwaway orders with **2** and **12** identical same-product OneTime lines (`PIA-PIA-NRPS-PIAP`) on a fresh account **both assetized successfully** (1:1 assets, `Assetization_Status__c=Success`). So duplicate same-product lines alone do **not** collide.
> The differentiator on 00095470 is its **maintenance-decomposed lines** (`PIA-PIA-RNM-PIAMBK` ×10 → Order Product Detail records), consistent with **SC-3411 §4.1** (`OrderRepriceInvocable` fails on maintenance-decomposed orders: *"can't edit Unit Price… related Order Product Detail records"*). **Remaining open:** the exact decomposition→asset mechanism still needs a FINEST repro **on 00095470 itself** (an in-place re-fire, owner-authorized). The visibility fix (§9) surfaces the fault regardless of mechanism.

### 2.3 Two premises from the prior investigation are FALSIFIED

- **Future-dating does NOT skip assetization.** 00095475's future-dated line `VM-BSL-RSL-BESECB` (ServiceDate 2027-06-11, PTC=null) **did** assetize → Asset `02iWC000008FcLaYAK` (beSECURE, Installed), booked as a `Change/Renewals` AssetAction. All 3 lines on 00095475 assetized.
- **The Failed decision table is NOT the gate.** `Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`, `RefreshStatus=Failed`, "Hash Key Group contains more than 200 rows") is a **PricingDiscovery** table (`SourceObject=AssetActionSource`) that reads **already-existing** Asset+AAS rows to return renewal/amendment pricing. It is **downstream of creation and cannot block new-order assetization** — proven by 00095471 assetizing 13 min after 00095470 under the same Failed state. (This is SC-3403 B-5, a separate latent risk.)

---

## 3. Root cause — PricingTermCount not enterable on Quote lines (secondary)

- **The quote-side gap is `PricingTermCount` ONLY.** On the repro draft lines (`ES-CEP-RSL-ACTIDB`, `VM-APS-RSL-BESTSU` on quotes 00095507/00095497) every standard term field is correctly derived — StartDate, **EndDate** (1yr−1day), SubscriptionTerm=1/Annual, PricingTerm=1/Annual — **except `PricingTermCount`, which is null.** This **corrects** the SC-3411 premise that a null `EndDate` was inherited from the quote: **937,773 of 938,052 null-PTC TermDefined lines have both StartDate AND EndDate present.**
- **`QuoteLineItem.PricingTermCount` is platform read-only.** sObject describe: `createable=false, updateable=false, calculated=false`, no formula. **Only the native RLM pricing engine can write it** during a Reprice/PlaceQuote term-derivation pass. (Contrast: `OrderItem.PricingTermCount` IS writable, which is why it can be patched on the order — but on convert it simply copies the quote's null.)
- **No custom component writes it.** The three quote-side flows (`Quote_Line_Item_On_Create`, `Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values`, `Fortra_Quote_Reprice`) contain **zero** references to `PricingTermCount`/`EndDate`/`StartDate`/`SubscriptionTerm` — there is **no Fortra quote-side equivalent of `Fortra_OrderItem_Set_Dates`.**
- **Regression timing.** EndDate-populated QLIs are 100% PTC-populated 06-05→06-10 and 100% null 06-12→06-15; last PTC-populated line created **2026-06-11T19:16:34Z**, first null **17:05:24Z**; pricing-procedure **V13 created 2026-06-11T19:07:24Z**. Derivation stopped **inside the V12→V13 churn window**, 9 minutes before the last success. This is a **pricing-engine / context-definition regression**, not a data or product-config issue (identical PSMO config on working vs. broken products).

> **Minor caveat (does not change root cause):** of the 19 post-cutover PTC-null lines, 10 also have `SubscriptionTerm` null; only 9 have PTC as the *sole* null. So "PTC alone" is imprecise as a population statement, but PTC is the universal gap.

---

## 4. Resolution

**This was a read-only RCA. No remediation was applied. All recommendations below are UAT-first and prod-gated.**

### 4.1 No-Assets (crux)
1. **Target the right transaction.** The fix surface is the **`Fortra_Assetize_Order` AsyncAfterCommit path** and the native `createOrUpdateAssetFromOrder` action — **not** the synchronous SC-3366 order-completion flow. The SC-3366 P0 subflow removal would reduce load on a *different* transaction and is **not a demonstrated fix** for the 32-line zero-asset case.
2. **Stop silent failures.** The flow's graceful `faultConnector` currently swallows the error. Add an **error-surfacing path** (platform event / error log / task) so a failed async assetization produces a visible signal instead of a silently asset-less "Order Complete."
3. **Pin the mechanism, then fix.** Run an **authorized FINEST-logged repro** on a fresh 30+ line order, capturing the **AsyncAfterCommit interview**, to determine whether the abort is a governor limit or a duplicate-product asset-key collision (the two live-consistent hypotheses). Fix accordingly; only if it is a governor limit do the SC-3366-class bulkifications become relevant — and even then **inside the async path**, not the sync one.
4. **Recover 00095470's missing assets** (owner-gated) via an RLM re-activation / asset re-trigger once the mechanism is fixed, then verify **32 AssetActionSource rows** appear with no async fault.

### 4.2 PricingTermCount (secondary)
- The durable fix is at the **pricing engine / context definition** that regressed in the V12→V13 churn — re-establish standard term-field derivation (including `PricingTermCount`) for TermDefined lines **at the Quote** so the null never reaches the order. Because the field is platform read-only with no custom writer, a flow cannot substitute; this needs the procedure/context resync (coordinate with whoever owns the V13 republish). SC-3411's V6 `Fortra_OrderItem_Set_Dates` backstop only patches the **order** tier downstream.

### 4.3 Prod safety
Do **not** deploy to prod without the standard cutover gate **and** a FINEST-log repro on a 32-line order confirming both **"no async fault"** and **"32 assets generated."** SC-3366-class flow assets are UAT-only / 0% coverage and a known prod-cutover blocker.

---

## 5. Reconcile with SC-3411 — what each ticket owns

| | **SC-3411 (RESOLVED, UAT)** | **SC-3415 (this ticket)** |
|---|---|---|
| **Symptom** | Order **cannot activate** — termed line missing `EndDate`/`PricingTermCount` | Order **activates** but generates **zero Assets**; PTC not enterable on quote lines |
| **Tier** | **Order** (downstream patch) | **Quote** (term-derivation regression) **+ async asset pipeline** |
| **Mechanism** | RLM blocks activation of a null-term line | Async asset transaction fails silently after a clean activation |
| **00095470** | Mechanism **excluded** — all 12 termed lines fully dated at activation | The actual repro |
| **Fix delivered** | `Fortra_Order_Submission_Check` V14 (surface real error) + `Fortra_OrderItem_Set_Dates` V6 (order-tier term backstop) | None yet (RCA only) — async asset path + quote-tier derivation |
| **Relationship** | Patches the *order* tier; its own README lists "P1-quote (true root)" as out of scope | **Owns** that quote-tier true root **and** the separate no-Assets failure |

**Bottom line:** SC-3411 fixed the *activation blocker* and explicitly deferred the quote-tier root cause. SC-3415 uniquely owns (a) the **no-Assets-after-activation** failure (a different transaction entirely) and (b) the **quote-side `PricingTermCount` derivation regression** that SC-3411 left open. **These are not duplicates and SC-3415 is not a subset of SC-3411.**

---

## 6. Acceptance criteria

- [ ] A 30+ line order activates **and generates a 1:1 Asset chain** (e.g. 32 lines → 32 AssetActionSource → AssetAction → Asset).
- [ ] An asset-generation failure **surfaces a visible error** instead of a silent asset-less "Order Complete."
- [ ] Order 00095470's missing assets are **recovered** (32 AAS verified) or the order is intentionally re-cycled.
- [ ] New TermDefined **quote** lines derive **`PricingTermCount`** (non-null) on reprice/PlaceQuote, so the null never converts to the order.
- [ ] German Wren can complete **renewal/COLA testing** on a freshly activated, fully-assetized order.

---

## 7. Open items

1. **Mechanism unresolved (no-Assets):** governor limit vs. duplicate-product asset-key collision — both are live-consistent; logs expired. Needs an authorized FINEST repro of the **AsyncAfterCommit** interview on a 30+ line order. The "SC-3366 SOQL-101" attribution is **downgraded to a flagged hypothesis** and, per the flow definition, would in any case be in the **wrong transaction**.
2. **Does line *duplication* drive it beyond raw count?** 18-line (all-distinct) and 14-line orders assetized fully; 00095470's 4-distinct-SKU 10/10/6/6 profile is the standout. A controlled 32-line all-distinct vs. duplicated repro would isolate the driver.
3. **00095399 (single-line, `GS-GSE-NRPS-ACSPER`, $13,860) also produced 0 AAS** — a *separate small-order edge case* (not line-count driven). Split into its own investigation (possible duplicate-of-existing-asset suppression or one-off async miss).
4. **PricingTermCount durable fix owner:** the V12→V13 procedure/context resync is owned alongside the active pricing-procedure rework — coordinate before any deploy.
5. **`Asset_Action_Source_Entries_Decision_Table_V2` RefreshStatus=Failed** (SC-3403 B-5) — a latent pricing-discovery (renewal/amendment) defect; **not** this order's gate, but track it.

---

## 8. Evidence

- **Decisive flow:** [evidence/Fortra_Assetize_Order.flow-meta.xml](evidence/Fortra_Assetize_Order.flow-meta.xml) — `<start>` AsyncAfterCommit scheduled path with **no synchronous connector**; graceful `faultConnector` on `createOrUpdateAssetFromOrder` → "Capture Error"; `overriddenFlow=revenue_o2aflows__o2aFlow`. (Full retrieve: `Data/sc3415_verify/flows/`.)
- **Decision table:** [evidence/Asset_Action_Source_Entries_Decision_Table_V2.decisionTable](evidence/Asset_Action_Source_Entries_Decision_Table_V2.decisionTable) — `UsageType=PricingDiscovery`, `RefreshStatus=Failed`. (Full retrieve: `Data/sc3415/dt/`.)
- **Verified findings + adversarial verdicts:** [evidence/deep_rca_findings.json](evidence/deep_rca_findings.json) — 5-stream deep RCA, 4 distilled claims, verify verdicts (uncertain/confirmed/confirmed/confirmed).
- **Order 00095470** `801WC00000kYmw8YAC`: Activated 2026-06-11T13:27:30Z, 32 OrderItems (PIAMBK×10, PIAP×10, SEAW×6, CLSAAS×6), Contract 00069266 Activated, **0 AAS / 0 AssetAction / 0 Asset** all-time.
- **Success contrasts:** 00095325 (18→18 AAS), 00095377 (14→14), 00095471 (2→2 at 13:40:56Z), 00095475 (3→3 incl. future-dated `BESECB` → Asset `02iWC000008FcLaYAK`).
- **Quote PTC:** draft lines `0QLWC000003elrM4AQ`/`0QLWC000003elrL4AQ`/`0QLWC000003e38j4AA` — EndDate set, `PricingTermCount=null`; describe shows the field read-only; V13 created 2026-06-11T19:07:24Z, last PTC success 19:16:34Z.
- All facts re-verified live (read-only) against FortraUAT, 2026-06-15.

---

## 9. Resolution deployed — Defect A visibility hardening (UAT, 2026-06-15)

**What shipped — `Fortra_Assetize_Order` V14, NO new fields** (reuses the existing, previously-unused `Order_Integration_Error_Messages__c`):

| Component | Change |
|---|---|
| `Fortra_Assetize_Order` **V14** | Fault path → `Stamp_Assetization_Failed` writes `Order_Integration_Error_Messages__c = "Assetization failed: <fault>"`. Success path → only **clears** that field if it currently `StartsWith "Assetization failed"` (so it never clobbers other integration errors). The `createOrUpdateAssetFromOrder` action is **unchanged**; updates write only that one field (never `Status`) so they can't re-trigger the flow. |

> **History / correction:** the first deploy (V13, Deploy ID `0AfWC00000GLZb30AH`) added two custom fields `Order.Assetization_Status__c` / `Assetization_Error__c` + a permission set — that contradicted the "no new fields" requirement and was **reverted**: V14 reworked to the existing field, then the two fields, the permission set, and the obsolete V13 version were **deleted** (verified: `No such column` on both fields). All E2E results in [E2E_TEST_REPORT.md](E2E_TEST_REPORT.md) were proven on V13's identical recordUpdate mechanism (only the target field changed in V14).

**Why this is the fix:** the collision itself is **native-platform behavior** we can't patch; the genuine Fortra-owned defect was that the failure was **silently swallowed**. V14 converts an asset-less "Order Complete" into a **visible** `Order_Integration_Error_Messages__c = "Assetization failed: …"`.

**Verification (live UAT):**
- ✅ Flow **V14 Active**; **no new fields** (both deleted); permission set deleted; obsolete V13 version deleted.
- ✅ **Success path proven (on V13 mechanism):** throwaway orders (OneTime 2-/12-line, subscription 6-line) activated → assets generated + Success outcome. (Orders `00095521`/`00095523`/`00095524`.)
- ✅ **Fault path directly verified (on V13 mechanism, owner-authorized):** re-fired 00095470 → flow stamped the failure within ~10s; Status restored. **All 4 E2E scenarios PASS** — see [E2E_TEST_REPORT.md](E2E_TEST_REPORT.md).
- ⏳ **V14 (the field-reuse target) is dry-run + deploy validated**; a runtime re-confirm on `Order_Integration_Error_Messages__c` would need one more owner-authorized 00095470 re-fire (mechanism already proven on V13).

**Residual test data (inert, marked `SC3415…`):** accounts `001WC00000kpGHxYAM` (orders 00095521/00095523) + `001WC00000kpR26YAE` (order 00095524) + lifecycle assets can't be API-deleted (RLM immutable `AssetActionSource` + lifecycle-managed Assets). Deletable children already removed. Remove the rest via Setup UI if desired.

**Not done here (open):**
- **Defect B (quote-tier PricingTermCount)** — ContextDefinition term-derivation regression; owner-gated, **not** a price-formula edit. Still open.
- **00095470 recovery** + exact maintenance-decomposition mechanism — needs an owner-authorized FINEST re-fire.
- **Prod rollout** of V14 — tracked cutover follow-up (UAT-only now).
- **Deploy artifacts:** `Data/sc3415/stage/v14/` (V14 flow) + `Data/sc3415/stage/destroy/` (field/permset removal) + `Data/sc3415/stage/helptext/` (AC6) + `Data/sc3415/diag/` (diagnostic/test/cleanup Apex). `Data/sc3415/stage/unpackaged/` is the superseded V13 (fields) package.

---

## 10. Acceptance-criteria status (2026-06-15, tested on 10 real orders)

| AC | Status | Notes |
|---|---|---|
| **1.** Activates w/o error, w/o typing PTC | ✅ **MET** | 10/10 real orders activated (SC-3411 backstop + reprice). |
| **2.** `QuoteLineItem.PricingTermCount` auto-derives | ❌ **OPEN (owner-gated)** | Universal time-based regression at **V13 activation ~06-11 19:16**. Five causes refuted (context-mapping intact, procedure-term-steps identical V12→V13, no prehook changed then, `LastPricedDate` blank for all, universal across 9+ products). Root = **runtime context↔procedure term-hydration binding the republish failed to re-sync** ([[project_reprice_contextdef_error]]); persists through V14. **Fix = owner-run clean procedure re-publish + context re-sync** (NOT a metadata edit), then verify PTC on a fresh line. |
| **3.** Assets for every subscription line (incl. future-dated) | ✅ **MET 9/10** · ❌ 00095470 | 9 orders assetize 1:1 incl. 9 future-dated lines; only 00095470 (collision) is 0. |
| **4.** Re-run 00095470 → Assets w/ correct term | ❌ **OPEN** | Deterministic collision on the **update-existing-asset** path (5 existing assets for its products). Fix = restructure duplicate lines (Quantity) **or** Salesforce platform case (native Asset DML not user-loggable); see [KEYSTONE2_FINEST_REPRO.md](KEYSTONE2_FINEST_REPRO.md). Then re-fire → 32 assets. |
| **5.** Wren completes renewal/COLA E2E + signs off | ⏳ **PENDING** | Human; unblocked once AC2 + a known-good repro path are in place. COLA/renewal pricing = SC-3346/SC-3350. |
| **6.** In-UI help text → SubscriptionTerm | ✅ **MET** | `inlineHelpText` deployed on `QuoteLineItem.PricingTermCount` + `SubscriptionTerm` (`Data/sc3415/stage/helptext/`). |
