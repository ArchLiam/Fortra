# SC-3473 — Re-Verification & Solution Roadmap

**Org:** FortraUAT · **Authored:** 2026-06-28 · **Method:** 100% read-only re-verification (6 agents, fresh live queries + adversarial gate). No DML performed.
**Companion:** `README.md` (the RCA) · `EVIDENCE_INDEX.md` · evidence under `evidence/reverify/`

---

## 1. Re-verification verdict — **prior RCA CONFIRMED, with refinements**

Every load-bearing fact was independently re-tested with fresh live queries on 2026-06-28. The diagnosis holds; the *trigger* is now sharper and two side-framings were overturned.

| # | Load-bearing claim | Re-verdict | Note |
|---|---|---|---|
| 1 | Throw is **native** managed-RLM Java, not custom Apex | ✅ **CONFIRMED** | 5 Quote/QLI/QLG triggers all have `UsageBeforeDelete=False` **and** `UsageAfterDelete=False`; 13 active flows have **zero** Delete record-trigger; NPE absent from the ApexLog window covering the 2026-06-26 failure. |
| 2 | Active pricing procedure = **V16** | ✅ **CONFIRMED** | `ExpressionSetVersion.IsActive=true` = V16 (single of 20); corroborated by `ExpressionSetDefinitionVersion.Status='Active'`. **⚠️ New:** V16 body was **edited 2026-06-27** (day *after* the failure) — any future repro runs against a changed procedure. |
| 3 | Active context = **SalesTransactionContextExt_v2 V23**, bound to the proc | ✅ **CONFIRMED / refined** | V23 active + bound (`ExpressionSetDefinitionContextDefinition 9QYWC0000000UcP4AU`). Refinement: a *second*, inert `SalesTransactionContextExt` (no `_v2`) V36 is also active org-wide but **not** bound — harmless. |
| 4 | Catalog clean for the 3 (Product2, PSM) pairs | ✅ **CONFIRMED** | Each pair → exactly one active USD PricebookEntry (Ids match the QLIs) + one PSMO. No missing static key. |
| 5 | Quote wedged in `SaveFailedOrIncomplete` | ✅ **CONFIRMED** | Still wedged, `IsSyncing=true`, 4 lines, group undeleted. |

**🔶 The decisive refinement (NEW, read-only-confirmed).** The most-probable *trigger* now has a name: the to-be-deleted **"Abstract" grouped line (`0QLWC000003jN8P4AU`)** is a **TermDefined / Annual** line carrying `PricingTerm=1` but **`EndDate=NULL` and `PricingTermCount=NULL`** — a malformed term state. Both surviving SUSPIN lines, by contrast, are fully termed (`EndDate=2027-03-17`, `PTC=1`). A null term/end-date is exactly the input that the V16 Proration / term logic and the native context-hydration runtime turn into a `Map.get(...) → null → .toString()` NPE. **This is the same defect family as `SC-3420` / `SC-3411` / `SC-3406`** (TermDefined lines missing `EndDate`/`PricingTermCount`).

**⛔ Two README framings OVERTURNED by this pass:**
- The AJS "configured/attribute pricing, net≫list" story is **wrong** — it's a **manual `NetUnitPrice`** (`Has_Attribute_Adjustment__c=False`, **0** `QuoteLineItemAttribute` on all 4 lines). No configuration to dangle.
- "Only HW-type group with ungrouped survivors" is **wrong** — there are **7** such quotes; **6** are `CompletedWithPricing`; only this one fails.

**⚖️ Honest limit (the adversarial gate's main catch).** The malformed-term condition is **necessary here but NOT sufficient org-wide**: **128 of 154** priced quotes carrying the *same* malformed condition are `CompletedWithPricing` (≈83% price fine). So the malformed line is a strong **contributing** trigger, not a proven sole cause — there is an unidentified co-factor (most likely the *combination* on this quote, or the already-wedged calc state). **The literal native frame and key remain INFERRED** until an authorized FINEST-logged repro.

**Mechanism reconciliation (a real gap the gate flagged).** The malformed line is *deleted*, yet the failure is a *reprice* — how does a deleted line throw? Two readings, both pointing to the same first action:
- **(a) Full-graph reconcile:** the native Place "delete + reprice" reconcile **hydrates/processes the entire transaction graph — including the to-be-deleted malformed line — before committing the cascade delete**; the malformed term passes through hydration/proration regardless of the delete flag. (The one documented sibling of this exact NPE, `DefaultContextRuntimeEntityAttribute.getTags()==null`, is in **context hydration**.)
- **(b) Pre-wedged quote:** timeline shows the Abstract line was created **16:05** and the quote was wedged by **16:25** — *before* any delete. The quote may have failed on the line's **original add-save**, so the Delete-Group save merely re-runs the procedure over the still-present malformed line and re-throws. Under (b), **a plain re-save would throw too** — which is precisely what the P1 probe tests.

**H6 (platform robustness defect) survives unchanged:** the engine's designed status taxonomy fired (`SaveFailedOrIncomplete`) yet it **leaked a raw JVM NPE to the toast** instead of an actionable message. That is a Salesforce-side defect regardless of the data fix.

---

## 2. Roadmap at a glance

| Phase | Goal | Action | Auth needed | Risk |
|---|---|---|---|---|
| **A — now** | Escalate the platform defect | File the Salesforce RLM case (H6 raw-NPE leak) | None (read-only) | None |
| **B — diagnose** | Name the native frame/key | **ONE** FINEST-logged probe on a **clone** — plain **re-save FIRST**, then Delete Group | **DML** | Low (clone) |
| **C — unblock** | Remove the group | Ranked levers, each *validate-under-logging*: ① term-field data-fix ② Place API `pricingPref:Skip` ③ Ungroup / delete-lines-individually / clone-and-rebuild | **DML** | Low–Med |
| **D — durable fix** | Stop recurrence | Backfill TermDefined `EndDate`/`PTC` + extend the existing SC-3411 backstop; **(last resort)** context republish | **DML / deploy** | Med (data) / **High** (republish) |
| **E — prevent** | Detect early | Guardrail on malformed TermDefined lines; monitor wedged `CalculationStatus` (67 quotes today) | Deploy | Low |

> **Sequencing correction (from the gate):** the FINEST **diagnostic comes before betting on any unblock lever**, and the first logged transaction should be a **plain re-save, not a delete** — because if a plain save also throws, the entire "Delete-Group / forced-reprice / no-rollback" framing is incidental and the unblock levers are aimed at the wrong variable.

---

## 3. Phases in detail

### Phase A — File the Salesforce platform case (do now, read-only, no org change)
The raw JEP-358 leak is a managed-package robustness defect only Salesforce can fix.
- **Severity:** High — GoLive blocker (`LOB-Salesforce-2-GoLive`). **Product:** Revenue Lifecycle Management → Pricing / Place Sales Transaction. **Org:** `fortra--uat` (`00DWC000006eUFF2A2`), RLM Dev Guide v67 / API v67.
- **Title:** *"RLM Quote Line Editor 'Delete Group' surfaces a raw JEP-358 NullPointerException (`Cannot invoke Object.toString() because java.util.Map.get(Object) is null`) instead of a guarded message; quote header commits but group is not deleted."*
- **Include:** the exact toast; repro = Delete Group on group `1C9WC00000097of0AA` of quote `0Q0WC000002U2020AC`; the live `CalculationStatus=SaveFailedOrIncomplete` datum (designed status fired, raw exception still leaked); the documented `DefaultContextRuntimeEntityAttribute.getTags()` sibling; active V16 / context V23; group composition (OneTime AJS + **malformed TermDefined** Abstract under `Hardware_Group_Type__c=True`, leaving 2 termed SUSPIN survivors).
- **Ask SF to:** (1) run a native pricing/context trace to name the exact frame + null **key**; (2) **null-guard** `map.get(key).toString()` so a config/data error surfaces as `PlaceQuoteErrorResponse`, not a raw NPE; (3) confirm whether a context republish corrects the in-org trigger.
- **Supplement** with the `referenceId` captured in Phase B.

### Phase B — One FINEST-logged diagnostic on a CLONE *(requires DML authorization)*
The single action that converts the inferred key into a verified frame. **Do it on a clone** to preserve the canonical repro for the case.
1. Trace flag on the executing user: FINEST on Apex Code; DEBUG/FINE on Database, System, Validation, Callout, Workflow, and the RLM/Industries-pricing categories where exposed.
2. **First, a plain Reprice-All / re-save** (NOT a delete) on the clone → does it throw the *same* NPE? **Same error ⇒** every-save/data-trigger (delete path is incidental); **clean ⇒** the delete path is the structural trigger. *This one observation reorders everything below.*
3. Then Delete Group once. Immediately capture the **POST `/connect/rev/sales-transaction/actions/place` response body** (the raw NPE + any Salesforce `referenceId`/Gack id) from the network tab, the browser console, and any pricing trace. Save under `evidence/reverify/repro/`.

### Phase C — Unblock the user *(requires DML authorization; each lever is plausible-but-UNPROVEN — validate under logging)*
Ranked; pick the one the Phase-B frame supports. **None is "high confidence"** — the gate showed each rests on the same unproven frame.
1. **Term-field data-fix (most-probable + durable):** set the malformed Abstract line `EndDate = StartDate + 1 Annual term` and `PricingTermCount = 1`, reprice, then Delete Group. Directly targets the named trigger and is the same remedy as the SC-3411/3420 family. *Caveat: necessary-not-sufficient (83% of carriers price fine), so it may not fully clear it.*
2. **`pricingPref:Skip` delete via Place API:** POST the QuoteLineGroup `DELETE/DeleteGroup` with `pricingPref:Skip` instead of `Force` to skip the survivor reprice. *⚠️ Verified valid as an input, but NOT verified to bypass the throwing frame — if the throw is in **context hydration** (the documented sibling), Skip won't help. Test under logging.*
3. **Ungroup** (keeps lines, null-groups them) / **delete the 2 grouped lines individually** then drop the empty group / **clone-and-rebuild without the group** and re-point `Opportunity.SyncedQuoteId`. Each changes the post-op reprice population; test in order until one succeeds.
- **Pre-req check:** confirm whether `Accepted` status gates QLE edits in this org (may require revert to Draft first).

### Phase D — Durable fix
- **Data hygiene (preferred):** backfill `EndDate`/`PricingTermCount` on malformed TermDefined lines and **extend the existing SC-3411 backstop** (`Set_Dates` V6 / `Submission_Check` per memory) to populate them at save so no TermDefined line reaches pricing with a null term. Low risk, addresses the whole `SC-3420/3411/3406` family.
- **Context republish — LAST RESORT only, change-window, snapshot-first:** Setup → Context Definitions → `SalesTransactionExt_v2` V23 → Generate All Mappings on `SalesTransactionItem` for **both** Quote and Order nodes → Deactivate dependencies → Save → Sync → Reactivate → sync V16 decision tables. **⚠️ V23 is the live org-wide pricing context for ALL quotes+orders — a bad republish hard-fails all repricing.** Note the prior "twice-proven remedy" precedents were **Order-side static-mapping gaps**, and this ticket's H2 **refuted** a static gap for the surviving quote-side nodes — so this is an *experiment*, not a clean transplant. Verify via Reprice-All on a comparison quote *before* trusting it.

### Phase E — Prevent
- Validation/guardrail flagging any TermDefined QLI with null `EndDate`/`PricingTermCount` before save (ties to SC-3411/3420/3406).
- Monitor wedged calc states: **20 quotes** in `SaveFailedOrIncomplete` + **47** in `PriceCalculationFailed` today — a recurring-fault dashboard, not one-offs.

---

## 4. Open decisions for you

1. **Authorize the Phase-B FINEST diagnostic on a clone?** (Recommended **YES, on a clone** — it's the only path that names the key and strengthens the SF case. Any DML needs your explicit go-ahead.)
2. **File the Salesforce case now** (read-only, no org change), supplementing with the `referenceId` later? (Recommended **yes, now**.)
3. **Authorize the Phase-C unblock** (term-field fix / Skip / Ungroup) on the live quote, or only after Phase B? (Recommended **after B**, on the clone first.)
4. **Context republish (Phase D):** hold as last resort, change-window only? (Recommended **yes — do not run it speculatively**; the static-gap premise is refuted here.)
5. **Confirm `0Q0WC000002U2020AC` + its synced OPEN opp `006WC00000NMOODYA5` are test data** before any DML (`IsSyncing=true` means a save can push to the opp).
6. **Preflight gate:** re-confirm active **V16 / V23** at the moment of any repro (V16 body changed 2026-06-27).

---

## 5. Confidence

**HIGH** that the throw is native (not Apex) and on the locus, and that the re-verification is sound (every live fact re-confirmed this pass). **MEDIUM** on the named key: the malformed-TermDefined line is the strongest read-only candidate and is confirmed on this quote, but it is necessary-not-sufficient org-wide, so the literal native frame/key stays **inferred** pending the authorized FINEST repro. **VERIFIED:** the H6 platform robustness defect. **Do not** pursue a custom-Apex fix — custom code is conclusively neither the cause nor a remediation point.

---

## 6. Resolution thread (2026-06-28): **SC‑3473's data trigger IS SC‑3420**

Step-1 resolution diagnosis tied the malformed term state to a known, still-open defect:

- On the failing quote, the grouped **Abstract** line is TermDefined/Annual with `StartDate` + `SubscriptionTerm=1` set but **`EndDate=NULL` and `PricingTermCount=NULL`**. No Fortra flow writes `QLI.EndDate`; `PricingTermCount` is **platform read-only** (engine-derived) — so these are pricing-engine outputs that never got written.
- **Live confirmation on active V16:** **123/128 (96%)** TermDefined quote lines created since 2026‑06‑15 have null `PricingTermCount`. The V16 `Proration` action consumes **`EffectiveTo = itemTransientEndDate`**, which is **null** for TermDefined lines because the **TermDefined term-derivation/Proration writer was deleted in the V11→V12 rebuild** (SC‑3420 proven root cause) and is still absent in V16.
- **Therefore:** SC‑3473's most-probable in-org trigger (a null term key during the forced reprice) is produced by **SC‑3420**. Fixing SC‑3420 is the durable remedy for the whole TermDefined family — **SC‑3420 / SC‑3411 / SC‑3406 / SC‑3415 / SC‑3473**.

**Fix = procedure-only (no shortcut):** re-add the guarded TermDefined Proration writer (output `Proration Multiplier → PricingTermCount`; computes `itemTransientEndDate`). Guard from the June‑16 E2E: `SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND SubscriptionTerm IsNotNull` (the naïve `TermDefined`-only filter regressed 124,912 PB‑null lines with `INVALID_PERIOD_BOUNDARY`).

**Blockers to shipping (do not solo-deploy):**
1. The ready build (`Data/sc3420/e2e_deploy/`) is **empty** — must be **re-retrieved and rebuilt on current V16** (procedure churns; Marc co-owns).
2. **Owner-gated:** coordinate with **Marc** before any deploy to the live pricing procedure.
3. **Not 100% proven to clear the NPE** (necessary-not-sufficient: ~83% of malformed lines still price) — after deploy, verify with the SC‑3473 group-delete repro.
4. UAT deploy needs explicit authorization; the auto-mode classifier will gate it.

**Recommended resolution sequence:** (A) file the SF case for the raw-NPE leak now [read-only, ready]; (B) escalate/confirm SC‑3420 as the upstream fix and coordinate with Marc to rebuild the guarded writer on V16; (C) deploy SC‑3420 fix (authorized + Marc) → reprice the failing quote → retry Delete Group to confirm SC‑3473 clears.
