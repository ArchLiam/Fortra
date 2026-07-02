# SC-3473 — Issue Deleting a Quote Group (RLM Quote Line Editor)

**Project:** Salesforce-Coastal · **Org:** FortraUAT · **Status:** To Do · **Reporter:** Dawn Krauss · **Assignee:** Liam Jeong · **Label:** LOB-Salesforce-2-GoLive · **Created:** 26 Jun 2026
**Dossier type:** Root-Cause Analysis (100% read-only research; no DML performed) · **Authored:** 2026-06-28

> **⚠️ Update (re-verification, 2026-06-28):** A second adversarial pass **confirmed** this RCA but **sharpened the trigger** and **overturned two framings below** — the "configured/attribute pricing" on AJS is actually a manual NetUnitPrice (0 line attributes), and the hardware-group angle is *not* the discriminator. The strongest read-only-named trigger is the **malformed TermDefined "Abstract" line (`EndDate`/`PricingTermCount` = NULL)** — same family as SC-3420/3411/3406 — though it is *necessary-not-sufficient* org-wide (≈83% of carriers price fine). **See [`02_SOLUTION_ROADMAP.md`](02_SOLUTION_ROADMAP.md) for the verified verdict and the sequenced fix plan; it supersedes "Why this quote" and "Recommended next steps" below.**

---

## TL;DR

When a user opens the group-action caret on group **"Test HW1"** (`1C9WC00000097of0AA`) on quote **0Q0WC000002U2020AC** ("Test Wren - Order Processing", 00734139, Accepted) in the RLM Quote Line Editor and clicks **Delete Group**, the save fails with a red toast:

> Your quote was not updated. Cannot invoke "Object.toString()" because the return value of "java.util.Map.get(Object)" is null

**Root cause (confidence: HIGH on locus, MEDIUM on exact key):** The throw is **inside the native, Java-implemented managed Revenue Cloud (RLM) save/reprice engine — NOT custom Apex.** The string is a JVM JEP-358 "helpful NullPointerException" that custom Apex can never emit (Apex NPEs read `System.NullPointerException: Attempt to de-reference a null object` and never name `java.util.Map`). All custom Apex and Flow are ruled out as the throw site by live source audit. Deleting the group cascades-deletes its two grouped lines and forces a server-side reprice (`pricingPref:Force`) of the surviving lines; the engine performs an un-null-guarded `map.get(key).toString()` during that reprice/context-hydration step, and `map.get(key)` returns null, so `.toString()` throws. Because the Place Sales Transaction API commits the quote header first and does not roll back a later-step failure, the group stays undeleted and the user sees "Your quote was not updated."

**What is VERIFIED vs INFERRED:**
- **VERIFIED:** The error is native (not custom). The custom hook/trigger/flow layer cannot be the throw site. The data catalog is clean for this quote (no missing PricebookEntry / PSMO / attribute-definition key). The active context version is **SalesTransactionContextExt_v2 V23** (single active) and shows **no static mapping gap** reachable for the surviving lines. The active pricing procedure is **Rev_Mgmt_Default_Pricing_Procedure V16** whose group-keyed aggregate step is `isNotNull`-guarded (so ungrouped survivors are excluded from it). The repro quote's live **`CalculationStatus = SaveFailedOrIncomplete`** — i.e., the engine's designed status taxonomy fired, yet the toast still leaked the raw JVM exception.
- **INFERRED (cannot be settled read-only):** The exact native frame and the exact missing map key. The strongest in-org analogs (two confirmed prior incidents + the one documented platform sibling) all point at the **Industries Context Service hydration / pricing-calc runtime** as the throw locus, but no read-only artifact names the specific key.

**Determination:** This is **primarily a Salesforce platform / managed-package robustness defect** (the engine surfaces a raw unhandled JEP-358 NPE instead of an actionable validation message). The actionable in-org trigger is a **config/data condition** — most credibly an incomplete/edge-case **Context Definition mapping or a configured-pricing context state on this hardware/mixed-selling-model group** — which is the customer-fixable lever and should be remediated first while a Salesforce case is opened for the unguarded NPE.

**The single thing that would close this:** an **authorized live Delete-Group reproduction on 0Q0WC000002U2020AC with FINEST / RLM-pricing debug logging** (this is DML and out of scope for this read-only research) to capture the actual native stack frame and the null key.

---

## The Error

```
Your quote was not updated.
Cannot invoke "Object.toString()" because the return value of "java.util.Map.get(Object)" is null
```

This is a **JVM JEP-358 "helpful NullPointerException"** (openjdk.org/jeps/358): a detail message computed lazily from bytecode that names the JDK call (`java.util.Map.get` / `Object.toString`). It is a developer stack-trace artifact, never an application-authored end-user message.

**Why this proves the throw is native, not Apex (VERIFIED, unanimous):**
- Apex null-dereference errors read `System.NullPointerException: Attempt to de-reference a null object` and never mention `java.util.Map`.
- Mission B retrieved all 10 custom pricing hooks live (api 67): every `execute()` swallows internal exceptions and returns `RevSignaling.TransactionStatus.SUCCESS` (explicit "Return SUCCESS even on error" comments); the only FAILED path is a blank `ctxInstanceId`, unreachable in a live reprice; and even a FAILED message carries an Apex `e.getMessage()`, never raw Java.
- Mission C verified **no** custom Apex trigger and **no** active Flow has a delete context on Quote / QuoteLineItem / QuoteLineGroup, so when the two grouped lines are deleted no custom automation runs at all.
- Mission F verified the native error **does not log to Apex**: the ApexLog retention window (2026-06-23 → 2026-06-28) covers the repro, yet reporter Dawn Krauss has zero ApexLogs and the only non-Success logs org-wide are unrelated.

**The one documented platform sibling** of this exact error class (Applikontech RLM troubleshooting guide) is:
> "...hydrating additional context fields: Cannot invoke `industries.context.api.service.model.runtime.schema.impl.defaultimpl.DefaultContextRuntimeEntityAttribute.getTags()` because the return value of `java.util.Map.get(Object)` is null"

— same `java.util.Map.get(Object)==null` JEP-358 pattern, attributed to the **native Industries Context Service runtime during context hydration**, remedied by correcting **Context Definition Mappings**. SC-3473 calls `.toString()` on a different missing-key value in the same engine family.

---

## Reproduction Context (ground truth, live-verified)

| Item | Value |
|---|---|
| Quote | `0Q0WC000002U2020AC` "Test Wren - Order Processing", 00734139, Status **Accepted**, USD, 4 lines, **CalculationStatus = SaveFailedOrIncomplete** |
| Account / Opp | "Fortra, LLC - Test"; quote is **SyncedQuoteId** of OPEN opp `006WC00000NMOODYA5` (StageName Pre-Qualified, IsClosed=false) |
| Group deleted | QuoteLineGroup `1C9WC00000097of0AA` "Test HW1" — the **only** group; **Hardware_Group_Type__c=True**, Hardware__c `a0nWC000001wdV3YAI` (HW-0717957) |
| Grouped line 1 (deleted) | Advanced Job Scheduler, Product2 `01tWC00000DD11cYAD` (SM-AJS-NRPS-AJSP), PSM `0jPWC00000005yz2AA` **OneTime**, net 29060 / list 2850 |
| Grouped line 2 (deleted) | Abstract, Product2 `01tWC00000DD11GYAT` (BI-ABS-RSS-ABSTSU — **not** the ...11EYAT in the brief), PSM `0jPWC000000060b2AA` **TermDefined/Annual**, net 4356 / list 46 |
| Survivor 1 (repriced) | Suspicious Email Intelligence, Product2 `01tWC00000DD1mNYAT` (ES-ETM-RMS-SUSPIN), PSM `0jPWC000000060b2AA` TermDefined, net 20000, QuoteLineGroupId=null |
| Survivor 2 (repriced) | same SUSPIN product/PSM, net 20000, QuoteLineGroupId=null |

**Server mechanism (VERIFIED, RLM Dev Guide v67.0):** QLE "Delete Group" posts an sObject graph to the Place Quote / Place Sales Transaction ConnectApi with the QuoteLineGroup carrying `method:DELETE` + `action:DeleteGroup` (distinct from `action:Ungroup`, which keeps lines) and `pricingPref:Force`. QuoteLineGroup is master-detail to Quote, so the delete cascades to its grouped QLIs; `pricingPref:Force` then forces a full server-side reprice of the surviving lines. The API "saves and commits the quote header first... If a later step fails, the header isn't rolled back" — which exactly produces the symptom (group not deleted; "Your quote was not updated").

---

## Mechanism — step-by-step causal chain

1. User clicks **Delete Group** on "Test HW1" in the QLE LWC.
2. The LWC calls the native **Place Quote / Place Sales Transaction** ConnectApi with the group `method:DELETE action:DeleteGroup` and `pricingPref:Force`. *(VERIFIED — RLM Dev Guide)*
3. The engine **commits the quote header**, then cascade-deletes the group's two grouped lines (AJS OneTime + Abstract TermDefined). *(VERIFIED — master-detail + dev-guide considerations)*
4. `pricingPref:Force` triggers a **full reprice of the two surviving ungrouped SUSPIN lines** through active procedure **V16** with context **V23 (SalesTransactionContextExt_v2)**. No custom Apex/Flow runs on the delete itself; the reprice is the managed `buildContext → runSalesforcePricing → persistContextData` engine. *(VERIFIED — Missions B/C, live)*
5. During context hydration / pricing-calc, the native engine performs an **un-null-guarded `map.get(key).toString()`**; `map.get(key)` returns **null** for some key tied to this transaction's state, so `.toString()` throws the JEP-358 NPE. *(INFERRED locus; the exact map/key is not read-only-observable)*
6. The later-step failure is **not rolled back** at the header; the engine sets `CalculationStatus = SaveFailedOrIncomplete` (its designed status), but the **raw JVM exception leaks to the toast** instead of the designed "Some Records Weren't Saved" message. *(VERIFIED — live CalculationStatus + JEP-358 message quality)*
7. The group is **not** deleted; the user sees "Your quote was not updated." *(VERIFIED — quote unchanged, 4 lines, last modified by repro)*

---

## Why this quote / selectivity

The original lead hypothesis (a selling-model-mix-keyed native map) was **substantially refined/refuted** by adversarial verification, and the true discriminator is narrower than first claimed. The honest state of the selectivity evidence:

- **The OneTime+TermDefined selling-model mix is NOT unique at the quote level.** ≥812 quotes org-wide mix OneTime and TermDefined lines and reprice without this NPE; **five** groups org-wide mix OneTime+TermDefined *inside one group* (not one). So SM-mix alone cannot be the cause.
- **The OneTime null-proration / null-term "asymmetry" is org-wide**, not group-specific: 3,939/3,939 OneTime PSMOs have `ProrationPolicyId=null`. It is an inherent property of the OneTime selling-model type, present on every counter-example.
- **No static config key is missing for THIS quote's lines:** every (Product2, PSM) pair has exactly one active USD PricebookEntry in the active price book; every pair has a PSMO; all attribute-definition / picklist / PAD rows are Active; the surviving lines are fully priced (net=list=20000, PTC=1, dates set). The classic "missing PBE/PSMO" native NPE is **ruled out** for these lines.
- **No reachable context-mapping gap:** active context V23 has 0 empty `contextInputAttributeName` mappings on the quote-side nodes; the only QLI-asymmetric attribute the procedure references (`RegionalNetUnitPrice__c`, OrderItem-only) sits behind an `AllowRegionalPricing__c=true` gate that is **FALSE** on all three products, so it never executes for the survivors.
- **What remains distinctive about the failing case** (a confounded cluster, none individually sufficient): the deleted group is the **only** one that is simultaneously (a) `Hardware_Group_Type__c=True` with Hardware__c stamped onto software lines, (b) carries a ~10× net≫list configured-pricing markup, (c) holds a OneTime+TermDefined mix, **and** (d) leaves non-empty ungrouped survivors that force a post-delete reprice. Among 25 hardware-type groups, only this quote has ungrouped survivors to reprice. The most parsimonious read is that **the configured-pricing/hardware-group context state on this group, combined with the forced survivor reprice, drives the engine onto an un-anticipated code path** where the null key is dereferenced.

**Bottom line on selectivity:** read-only evidence establishes the failure is real, native, and correlated with the hardware/configured-mixed group + survivor-reprice cluster, but **cannot isolate a single necessary key**. That isolation needs a debug-logged repro.

---

## Evidence Table (fact → source)

| # | Fact | Verified / Inferred | Source |
|---|---|---|---|
| 1 | Error string is a JVM JEP-358 helpful-NPE from native Java; impossible from Apex (Apex reads "Attempt to de-reference a null object") | Verified | Mission A web research; openjdk.org/jeps/358 (H6 native findings) |
| 2 | Exact string is NOT a documented Salesforce Known Issue; only documented sibling is `DefaultContextRuntimeEntityAttribute.getTags()` in native Industries Context Service, fixed via Context Definition Mappings | Verified | Mission A WebSearch; Applikontech RLM guide (`evidence/research-web/MISSION_A_NOTES.md`) |
| 3 | QLE Delete Group = Place Quote/Place Sales Transaction ConnectApi, `method:DELETE action:DeleteGroup`, `pricingPref:Force`; cascades grouped lines; header commits first, later-step failure not rolled back | Verified | RLM Dev Guide v67.0 (`evidence/research-web/rlm_dev_guide.txt` ~L128050, L128270) |
| 4 | All 10 custom pricing hooks swallow exceptions → return SUCCESS; only FAILED path is blank ctxInstanceId (unreachable); none keys a map on the group node | Verified | Mission B live retrieve `evidence/mission_B/live_source/.../classes/` |
| 5 | No custom Apex trigger and no active Flow has a delete context on Quote/QLI/QLG; QuoteLineGroupTrigger is after-update only | Verified | Mission C `evidence/missionC/*.trigger.live`; Tooling ApexTrigger query |
| 6 | Native error does not log to Apex; reporter Dawn Krauss has 0 ApexLogs in the retention window covering the repro | Verified | Mission F `evidence/prior-art/apexlog_reporter_dawn_krauss.json`, `apexlog_retention_window.json` |
| 7 | Every (Product2,PSM) on the quote has exactly one active USD PricebookEntry; PSMO exists for each pair; attribute defs/picklists/PADs all Active — no missing static catalog key | Verified | Mission D `evidence/missionD/raw_queries/10_pbe.json,11_psmo.json,13-15`; H6 `H6_attached_pbe.json,H6_psmo.json` |
| 8 | Active pricing procedure = **Rev_Mgmt_Default_Pricing_Procedure V16** (single Active version); local mirror showing V15 is stale | Verified | Tooling ExpressionSetDefinitionVersion (`evidence/verify/H1_native_semantics_findings.md`, `H4/active_version.json`) |
| 9 | Active V16 has only **6** GroupingAndAggregatePricing steps (the "129" is a grep across all 20 versions); the lone group-keyed step (AggregatePrice106) keys on SalesTransactionItemGroup with condition `isNotNull`, excluding null-group survivors | Verified | `evidence/verify/H1_native_semantics_findings.md`; `evidence/verify/H4/H4_REFUTED_summary.md` |
| 10 | Active context = **SalesTransactionContextExt_v2 V23** (single active, since 2026-05-29); 0 empty `contextInputAttributeName` on quote-side nodes; the one QLI-asymmetric attr (`RegionalNetUnitPrice__c`) is gated off (`Allow_Regional_Pricing__c=FALSE` on all 3 products) | Verified | `evidence/verify/ctxdef_v2_versions.json`, `H2_findings_summary.json`, `products.json` |
| 11 | OneTime null-proration is org-wide: 3,939/3,939 OneTime PSMOs have ProrationPolicyId=null — not a failing-quote discriminator | Verified | `evidence/verify/all_onetime_psmo.json` |
| 12 | SM-mix is non-unique: ≥812 quotes mix OneTime+TermDefined at quote level; 5 groups mix OneTime+TermDefined in one group | Verified | `evidence/verify/all_grouped_qli_sm.json`, `H1_native_semantics_findings.md` |
| 13 | Failing group is the ONLY mixed-SM group that is also Hardware_Group_Type__c=True + net≫list markup + has ungrouped survivors to reprice (confounded cluster) | Verified | `evidence/verify/mixed_groups_hwtype.json`, `H1_differential_findings.md`, `hwtype_quote_linecomp.json` |
| 14 | OLI.Product_Selling_Model__c is null on 121,180/121,180 OLIs org-wide (custom field, never mapped by sync); 10,943 open synced opps share it → opp-sync PSM-null is benign, not the trigger | Verified | `evidence/verify/q1_oli_*.json`, `q4_synced_*.json` |
| 15 | Repro quote live **CalculationStatus = SaveFailedOrIncomplete** — designed status set, yet raw JEP-358 toast leaked (robustness-gap signature) | Verified | `evidence/verify/H6/quote_calcstatus.json`; RLM Dev Guide L123243-45 |
| 16 | Two confirmed prior in-org incidents of native Map/tag-fetch failures on reprice, both fixed purely by context-node mappings (reprice_contextdef_error; v16_order_pricing_contextfetch_incident) — establishes the org's dominant failure mode for this NPE family | Verified | memory `project_reprice_contextdef_error.md`, `project_v16_order_pricing_contextfetch_incident.md` (Mission F) |
| 17 | Place Quote API has a designed guarded error channel (PlaceQuoteErrorResponse {errorCode,message,referenceId}) for many conditions → engine is NOT uniformly unguarded; the raw-NPE leak is path-specific | Verified | RLM Dev Guide v67.0 (`rlm_dev_guide.txt` L135468-135593) |
| 18 | Exact native frame and missing key | **Inferred — unresolvable read-only** | Requires live repro + FINEST debug log (DML, out of scope) |

---

## Hypotheses with adversarial verdicts

Adversarial review applied three lenses (data-forensics, native-semantics, differential) to each hypothesis. **The originally top-ranked H1 was largely refuted; the surviving picture is "native throw locus = context-hydration/pricing-calc, trigger = an in-org config/data edge on this group, plus a platform robustness gap."**

### H1 — Selling-model-mix keys a stale native aggregate map → **REFUTED / REFINED**
*Claim:* deleting the OneTime line leaves a per-selling-model aggregate map keyed on a now-missing OneTime entry.
*Verdict:* **REFUTED on native-semantics** (the named selling-model-keyed map does not exist in active V16; the only group-keyed step is `isNotNull`-guarded and excludes survivors); **REFINED/REFUTED on data-forensics and differential** (SM-mix is non-unique — 5 mixed groups, ≥812 mixed quotes; the OneTime null-proration is org-wide; the real differentiator is confounded HW-type + markup + survivor-reprice). SM-mix is a **correlated discriminator, not the throw mechanism**. *What survives:* the engine does fail specifically on this group's combination, but selling-model keying is the wrong named cause.

### H2 — Context-hydration mapping gap (SalesTransactionContextExt_v2) → **REFUTED as a static gap; locus survives**
*Claim:* a procedure step references a context attribute unmapped/null on the surviving-line node, so the native context runtime `Map.get(attr)` returns null.
*Verdict:* **REFUTED across all three lenses as a *static* mapping gap** — active V23 has no empty mappings on quote-side nodes, the surviving lines are fully hydrated, the one asymmetric attribute is gated off, and the prior in-org analogs were Order-side (impossible on a quote-only delete). The signature also lacks the documented `getTags()`/"hydrating additional context fields" preamble. **However**, the documented platform sibling and the live `SaveFailedOrIncomplete` status both point at the **context-hydration / pricing-calc runtime as the throw locus** — just not via a *statically* unmapped attribute. *What survives:* the **locus** (managed context/pricing runtime) and the **fix family** (config/republish of the context definition is the org's proven remedy for this NPE family), even though no static gap was found read-only. A purely runtime-value null on this configuration cannot be excluded read-only.

### H3 — Quote↔Opportunity sync reconciliation keys on null OLI ProductSellingModel → **REFUTED (all 3 lenses)**
*Verdict:* `OpportunityLineItem.Product_Selling_Model__c` is a **custom** field, null on **121,180/121,180** OLIs org-wide and never read by native sync (native sync handles standard fields only); 10,943 open synced opps share the exact condition; a structural twin synced quote (0Q0WC0000035N0f0AE) shares every named condition and is non-failing. The null is **benign baseline**, not the trigger.

### H4 — Null-group-id summary-map collision after deleting the only group → **REFUTED (all 3 lenses)**
*Verdict:* Five clean single-group quotes leave null-group-id survivors on delete and are non-failing; the active V16 group-keyed aggregate is `isNotNull`-guarded so null-group survivors never enter it; 165,208 quotes carry null-group-id lines repriced routinely. A generic `Map.get(null).toString()` over the group key would fail org-wide; it does not.

### H5 — Hardware-group-over-software teardown keys on an absent hardware key → **REFUTED (all 3 lenses)**
*Verdict:* HW-type + Hardware__c-stamped-on-software is shared by ~9+ groups (several Accepted); `Hardware.Group_Number_List__c=null` is universal across all 25 HW groups and identical on non-failing comparison hardware; the group-level hardware keys are **not even mapped into the native pricing context** (only QLI.Hardware__c/Hardware_ID__c are, as input values, not keys); the custom hardware trigger is after-update-only and cannot emit the Java NPE. Hardware-ness is **incidental**, necessary-but-not-sufficient.

### H6 — Platform robustness gap: engine leaks raw JEP-358 NPE instead of an actionable message → **SURVIVES (refined)**
*Verdict:* **SURVIVES in narrow form, REFUTED in universal form.** Live-confirmed: the repro quote's `CalculationStatus=SaveFailedOrIncomplete` shows the engine's designed status taxonomy fired, yet the toast still leaked the raw JVM exception — the precise robustness-gap signature. *Refinement:* the engine is **not** uniformly unguarded (it returns designed `PlaceQuoteErrorResponse` messages and an enumerated CalculationStatus taxonomy for anticipated failures), so the leak is **specific to an un-anticipated context-hydration/calc `Map.get().toString()` path**, not "any missing key." This is a true platform defect that **co-exists** with the in-org trigger but does not by itself name the actionable key.

**Net:** the actionable in-org trigger is most credibly a **config/data edge on this hardware/configured-mixed group's pricing context** (H2's surviving locus/fix-family), and the message itself is a **platform robustness defect** (H6). No read-only artifact isolates the exact key.

---

## What remains to confirm (read-only limits)

- The **exact native stack frame** and the **specific null map key** — not observable via any read-only SOQL/Tooling/metadata. Only a **live Delete-Group repro with FINEST / RLM-pricing debug logging** captures it (DML; out of scope).
- Whether the trigger is a **runtime-value null inside context hydration** (most-probable locus) vs a grouping/aggregate vs decomposition frame — same constraint.
- Whether **re-publishing / re-syncing SalesTransactionContextExt_v2 V23 + the V16 procedure context bindings** clears it (the org's proven remedy for the two prior analog incidents) — requires a deploy/republish + repro, both DML.

---

## Related tickets / prior art

| Ticket / memory | Relation | Strength |
|---|---|---|
| `project_reprice_contextdef_error` | Order reprice "Unable to fetch tags" from a blank context-node input mapping; native Map/tag-fetch failure on reprice; fixed by context-node mapping | **Strong** architectural analog |
| `project_v16_order_pricing_contextfetch_incident` | "couldn't fetch SalesTransactionContextExt_v2" — field mapped on Quote node but absent on Order node; fixed purely by context-node mapping; establishes "any referenced tag must be hydrated on the priced node" | **Strong** architectural analog |
| **SC-3393** (`project_sc3393_services_add_fail`) | **Only** place in the corpus quoting this exact NPE signature (via Applikontech RLM guide); classifies it as a Context Definition mapping problem; same managed-engine surface; same "not logged to Apex"; same "Your quote was not updated" toast prefix | **Strong** |
| SC-3345 (`project_quote_pricing_rollups`) | Same procedure; conditional/grouped aggregates with "Initialize defaults OFF" leave stale/null state on empty groups; delete-reprice re-runs category rollups on survivors | Medium |
| SC-3423 / SC-3468 | Hardware-Group **LWC** (`hardwareGroupManager`/`HardwareGroupController`) — different object/stack; share only the word "group" | Weak (name collision) |

---

## Recommended next steps

**1. Open a Salesforce platform case (primary path — this is a managed/platform defect).**
- Title: *"RLM Quote Line Editor 'Delete Group' surfaces raw JEP-358 NullPointerException (`Cannot invoke Object.toString() because java.util.Map.get(Object) is null`) instead of a guarded message; quote header commits but group is not deleted."*
- Attach: the repro quote/group ids; the live `CalculationStatus=SaveFailedOrIncomplete` showing the status taxonomy fired while the toast leaked the raw exception; the documented `getTags()` sibling for cross-reference.
- Ask Salesforce to (a) identify the native frame/null key on this transaction and (b) null-guard the unguarded `map.get(key).toString()` so a config error surfaces an actionable message instead of the raw NPE.

**2. In parallel, perform the authorized live diagnostic repro (DML — requires explicit go-ahead; out of scope for this read-only research).**
- Reproduce Delete Group on `0Q0WC000002U2020AC` with **FINEST + RLM/pricing** debug logging to capture the native frame and the null key. This is the single action that converts the inferred locus into a verified key.
- Highest-value out-of-scope isolation toggles (each one variable, all DML): (a) remove the OneTime AJS line first and retry delete; (b) regroup the survivors into a second non-hardware group before deleting; (c) unsync the quote from the opportunity and retry.

**3. Config/data remediation to attempt (the customer-fixable lever; H2 surviving fix-family).**
- Re-sync / re-publish **SalesTransactionContextExt_v2 V23** and re-verify its bindings to **both** the Sales Transaction (pricing) and Product Discovery procedures, run **Generate All Mappings**, confirm a default mapping exists, and **sync the decision tables** for V16 — the exact remedy that cleared the two prior in-org analog incidents. Re-verify the active procedure version (V16) and context version (V23) at preflight; the prompt's "V12/V13" is stale.
- This is the lowest-risk first remediation; pair it with the live repro to confirm it actually clears the toast before treating it as the fix.

**Do NOT** attempt a custom-Apex fix: every mission ruled custom Apex out as both the throw site and a viable remediation point. No custom-code change can produce or prevent this native NPE.

---

*Read-only research only. No DML, deploy, validate-only, reprice click, or group delete was performed against FortraUAT. Evidence artifacts are under `*Jira/Task/sc3473 | Issue Deleting a Quote Group/evidence/` (subfolders `research-web/`, `mission_B/`, `missionC/`, `missionD/`, `missionE/`, `prior-art/`, `verify/`).*
