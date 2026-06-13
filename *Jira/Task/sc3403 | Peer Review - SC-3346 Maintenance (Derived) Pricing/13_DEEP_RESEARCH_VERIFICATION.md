<!-- Provenance: deep multi-source verification of doc-12, run 2026-06-13.
Method: 25-agent Workflow (11 parallel forensic gatherers over FINEST logs / Apex / 75k-line pricing procedure / before-save flow / live FortraUAT read-only metadata+data / 2 web streams / git+memory) -> 9 adversarial per-claim skeptics + 2 diverse-lens panels (CRUX + CONTRADICTION) each with a judge -> synthesis.
Main-thread independent corroboration (direct greps on Data/sc-maint/sc3404/logs/07LWC00000OxZTl2AN.log + procedure XML) reproduced the load-bearing evidence: engine NetUnitPrice map = {dn3x4=301.75} only (dn3y4 absent); 47x "67.38" all in COLACalculatedPrice__c, 0 as a price; ListPrice={dn3y4=0.0, dn3x4=355.0}; Quantity={both=0.0} (so qty-0 is NOT the discriminator - the license is also qty-0 and prices fine); native DerivedProductsRenewals/DerivedPricingRenewals absent from the canary log; and the procedure's DerivedProductsNonRenewal gate + DerivedPricingAttribute/AttributePricingFilter gates confirmed present in the XML. Verdicts: C1/C3/C9/C11 confirmed-high; C2/C4/C7/C8/FIX partial; CONTRADICTION=Story A confirmed-high; CRUX=partial-high (fix likely insufficient as written).
READ-ONLY investigation. No UAT DML/deploy performed by this verification. -->

# SC-3404 Peer-Review Verification Report — doc-12 Renewal-Maintenance $0 NetUnitPrice Handoff

**Bottom line:** doc-12's root-cause DIRECTION is **correct** (the canary maintenance line is never a priced node, and "native override" is refuted) — but doc-12 mis-attributes the *cause*, **overstates** two of its claims, and its recommended **fix is UNPROVEN and likely insufficient as written**. The handoff is a solid diagnostic to hand to Nir, but it is **NOT build-ready**: the single decisive validation test (does a prehook seed turn the line into a persisting priced node?) has never been run, and the structural evidence predicts a bare `InputUnitPrice` seed will be ignored for a still-`ItemIsDerived` line.

---

## TL;DR

- **CONFIRMED (high):** The canary maint line `dn3y4` is genuinely absent from every engine `NetUnitPrice`/`InputUnitPrice`/`PartnerUnitPrice` *map* (0 of 16 each), while present 646× as a context node. `67.38` lives only in `COLACalculatedPrice__c`. The line nets `null` and the engine still reports `CompletedWithPricing` (silent $0). Story A's observable is real.
- **CONFIRMED (high):** Story B ("native `DerivedProductsRenewals` runs last and overwrites the formula's 67.38 to 0") is **structurally refuted** in the live V14 procedure: the native committer runs at container seq **5**, BEFORE the formula at seq **7**, AND is gated by `DerivedProductsNonRenewal` (`QuoteTypeText__c NotEquals 'Renewal'`) to exclude renewals. The discarding formula (`resultIncluded=false`) means there is no committed 67.38 to overwrite. The only direct A/B experiment (flip `resultIncluded=true`) left the line at $0 — falsifying B.
- **CONFIRMED (high):** `NetUnitPrice` on `QuoteLineItem` is `createable=False`/`updateable=False` in live UAT — so doc-12's claim that a before-save flow cannot write it is correct (the lever is dead).
- **CORRECTED:** doc-12's stated *cause* ("`ListPrice=0` + qty 0 + derived + 'No Change'") is **over-specified**. The contributing license line shares qty=0 AND 'No Change' yet prices fine at 301.75. The operative disqualifier is **`DerivedPricingAttribute` null/unhydrated** for the maint line (not the 4-attribute combo, and NOT 'No Change').
- **CORRECTED:** doc-12's claim "**no layer can persist NetUnitPrice**" and "`67.38` never bridged to a price field" are **overstated**. The v1.5 posthook (`PartnerNetPricePosthook.cls:858-866`) *does* write `attributeName 'NetUnitPrice' => 67.38` via `updateContextAttributes` and the call runs clean (`linesUpdated=1`) — it simply **does not persist** for the non-priced node. The accurate statement is "written-but-never-persisted," not "never written."
- **UNPROVEN (the crux):** That seeding `InputUnitPrice`/`ListPrice` in a prehook makes a `ListPrice=0`/derived line a persisting priced node. The standard `NetUnitPrice=InputUnitPrice` assignment explicitly **skips derived lines**, and the live `AttributePricingFilter` gate requires `DerivedPricingAttribute IsNotNull AND =false` — so a null-`DerivedPricingAttribute` line would be skipped *regardless of any seeded InputUnitPrice*. doc-12 itself flags this (§4.1) as unproven.
- **VERSION-STATE RED FLAG:** At verification time the pricing procedure had **ZERO active versions** (all 14 `ExpressionSetDefinitionVersion` rows `Status=Inactive`, stamped 18:06–18:07Z — mid-republish). doc-12's "V14/V140 active" could not be confirmed live; any reprice right now may error.
- **NET:** Diagnosis is the best-supported position to date and is reasonable to hand off, but it is "best-evidenced inference," not "proven." Require the un-run waterfall trace + throwaway prehook-seed test before any build.

---

## The root-cause contradiction RESOLVED (no-priced-node vs native-override)

**Verdict: Story A ("NO PRICED NODE") is correct for the canary; Story B ("NATIVE OVERRIDE") is refuted.** doc-12's supersession of doc-11 is right *on the mechanism*. The kernel B preserves — that 67.38 *is* genuinely computed in-flight — is true, but B's overwrite mechanism is structurally impossible in the version that produced the logs.

### Why Story B fails — three independent structural refutations (live V14 XML, `chk_revert/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`, V14 block lines ~69795–75410)

1. **ORDER fails.** The native `DerivedProductsRenewals` (`resultIncluded=true`, outputs `NetUnitPrice→NetUnitPrice` AND `Subtotal→ItemNetTotalPrice`) sits in container `DerivedProductsNativePull` at top-level `sequenceNumber 5`. The B-4 formula `DerivedPricingRenewals` sits in container `ListContainer` at top-level `sequenceNumber 7`. **5 < 7 — the native element runs BEFORE the formula, not last.** B requires "runs last and overwrites." (XML lines ~71978–72101 for the native; ~71830–71889 for the formula.)
2. **GATING fails.** The native committer's sibling `AdvancedListFilter DerivedProductsNonRenewal` (child seq 1) = `QuoteTypeText__c NotEquals 'Renewal'` scopes the committer (child seq 2) to **non-renewal** lines. The canary is `QuoteTypeText__c='Renewal'` → the native committer **never touches it** (XML lines 71957–71976).
3. **NOTHING TO OVERWRITE.** The B-4 formula returns `IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, …COLA…), NetUnitPrice)` → computes 67.38 — but **`resultIncluded=false`** discards it. There is never a committed 67.38 in any price port for any element to zero.

> **Correction to doc-11, in B's own favor but still fatal:** doc-11 claimed the native element "writes only `ItemNetTotalPrice` (a total)." The XML disproves this — it writes **both** `NetUnitPrice` and `ItemNetTotalPrice` with `resultIncluded=true`. B's field argument was wrong *in B's favor*, yet B still fails because of order + gating.

### Why Story A holds — end-to-end log + live evidence

- **Map-absence (base log `07LWC00000OxZTl2AN.log`):** `grep -E '^NetUnitPrice={' | grep -c dn3y4` = **0**; same for `^InputUnitPrice={` (0) and `^PartnerUnitPrice={` (0). All 16 maps of each type carry **only** the license `dn3x4=301.75`. The line is present 646× as `ListPrice={dn3y4=0.0}`, `LineItemQuantity={dn3y4=0.0}`, `ItemIsDerived__std={dn3y4=true}`, `COLACalculatedPrice__c={dn3y4=67.38}` — heavily *contextualized*, never a *priced node*.
- **67.38 location:** appears 48× in the base log, **all** in `COLACalculatedPrice__c`/`Final_Year_COLA_Calculated_Price__c`; **0** as a value inside any engine net/input/partner map.
- **Posthook no-op (v1.5 log `07LWC00000Oxacj2AB.log`):** the posthook fires (`13345: RENEWAL MAINT COLA: Line 0QLWC000003dn3y4AA -> Net=67.38`), builds the 8-attr payload (13358), and `updateContextAttributes` runs clean (`13720→13721`, `linesUpdated=1`, no exception, `persistContext`=0 occurrences). Despite a subsequent `RLM_PRICING_BEGIN` at 13809, `dn3y4` still has 0 entries in all 16 `NetUnitPrice` maps and the committed `$Record.NetUnitPrice=null` (lines 17349/17508/17531). **A layer wrote NetUnitPrice and the engine silently dropped it** — the precise signature of "no priced node," not "overwrite."
- **The hard discriminator (doc-11 Attempt 1):** flipping `DerivedPricingRenewals.resultIncluded=true` (which under B should commit 67.38) **left the line at $0**. Under A (no slot to fill), it shouldn't fix it — and it didn't.

### Where the two stories converge — and the practical consequence for the fix

A and B describe the **same wall** from two angles: the **committed `NetUnitPrice` is owned by the native RLM engine**, not by any custom formula/prehook/posthook. The surviving kernel of B (the engine, not custom Apex, governs the value for a derived line) is exactly why **doc-12's prehook seed is not guaranteed to work.** The sibling line `ck6X4` (single-line quote `00781043`) is the warning shot: it IS a `NetUnitPrice` map key (qty=1) but pinned at **0.0** across all 16 snapshots even though prehook AND posthook wrote 67.38 — so for a derived line, even *being in the map* does not let an external write of 67.38 land. (`ck6X4` is a *different* failure mode — `ValidationResult=MissingContributor` ×169, a lone maint line with no contributor on its quote — but it proves the engine governs the derived net regardless of hook writes.)

**Practical consequence:** Story A correctly diagnoses the **defect** (no priced node). Its **remedy** must do more than seed `InputUnitPrice` — it must either also neutralize `ItemIsDerived`/hydrate `DerivedPricingAttribute=false` so the line routes through the standard assignment, OR fix the native derived-pricing config so the derived element itself emits 67.38. A bare `InputUnitPrice` seed on a still-derived line is predicted to be skipped.

---

## Claim-by-claim verdict table

| Claim | doc-12 says | Verdict | Conf. | Key evidence |
|---|---|---|---|---|
| **C1** | Maint line never a key in any engine `NetUnitPrice`/`InputUnitPrice`/`PartnerUnitPrice` map (grep=0) though present 646× | **confirmed** (scope: engine `^Map={` entries) | high | `07LWC00000OxZTl2AN.log`: `grep -c dn3y4`=646; `^NetUnitPrice={`→0, `^InputUnitPrice={`→0; 16/16 maps carry only `dn3x4=301.75` |
| **C2** | Exclusion caused by `ListPrice=0`+qty0+`ItemIsDerived=true`+`No Change` *combination* | **partial** (attributes present; causal claim over-specified) | high | License `dn3x4` shares qty=0 + 'No Change' yet prices 301.75. Only `ItemIsDerived` (true vs false) and `ListPrice` (0 vs 355) differ; true driver is `DerivedPricingAttribute` null |
| **C3** | `COLAUpliftPrehook` logs "Found 0 renewal QLIs"; 'No Change' line not seeded | **confirmed** | high | Live SOQL: `dn3y4` `QuoteAction.Type='No Change'`; prehook SOQL gate `QuoteAction.Type='Renew'` (live `COLAUpliftPrehook` ~line 310-317); log 11176 `Rows:0` → 11216 "Found 0 renewal QLIs from 2 total" |
| **C4** | `67.38` never bridged to any price field; lives only in `COLACalculatedPrice__c` | **partial** (persistence true; "never bridged" false) | high | `PartnerNetPricePosthook.cls:858-865` assigns `colaNet→'NetUnitPrice'/'InputUnitPrice'/'UnitPrice'/'PartnerUnitPrice'`; log 13345 fires it, submitted clean — but never persists |
| **C7** | seq41/seq33 procedure attempts failed because line is not a node / post-line-pricing zone | **partial** (outcome confirmed; mechanism inferred, not traced) | high | Elements landed in `postdeploy`/`postdeploy5` metadata; no captured reprice log post-dates the v3/v5 deploys; element internals are opaque in FINEST |
| **C8** | `NetUnitPrice` read-only to record-triggered flows → "Invalid target field for field update" | **partial** (read-only confirmed; exact string/“broke reprice” uncorroborated) | medium | Live describe: `QuoteLineItem.NetUnitPrice` `createable=False`/`updateable=False`/`calculated=False`. Exact error string only in doc-12 prose + a *different-field* (LegalEntityId) test comment |
| **C9** | v1.5 posthook fires, computes 67.38, `updateContextAttributes` clean, but committed `NetUnitPrice` stays null (no-op for unpriced node) | **confirmed** | high | Log 13345/13358/13720-13729 (`linesUpdated=1`, 0 FATAL/EXCEPTION); maps post-write (13772/13833) still `{dn3x4=301.75}`; final `$Record` null |
| **C11** | v1.4 posthook filter excludes 'New Maintenance'; design "never actually effective" (stale 60.64/0 on RRM) | **confirmed** | high | Live posthook `@version 1.4`, line 806 `= 'Renewal Maintenance'`; broadened v1.5 matched + wrote 67.38 yet didn't persist; live RRM lines: Draft 00781043 net=0, Accepted 00781068 net=60.64 |
| **FIX** (prehook seed) | Sound, and the **only** fix that can work | **partial** (right direction; unproven mechanism; "only fix" refuted) | medium | `ck6X4` clean write→still 0.0; standard assignment skips derived lines; native PBE-derived-config (PBEDP row exists, `182WC000000FN26YAG`) is a viable alternative doc-12 excludes |

---

## The recommended fix — soundness, completeness, and the unproven crux

doc-12 (§4) recommends: in `COLAUpliftPrehook`, for renewal-maintenance lines, read the persisted `COLACalculatedPrice__c=67.38` and seed the context line's `InputUnitPrice`/`ListPrice` **before** the procedure runs, so "the engine carries the line ... `NetUnitPrice = InputUnitPrice = 67.38` → persists."

### What's sound
- The **direction** (move the lever upstream into a prehook so the value is an *input* to the procedure, not a post-hoc override) is the most defensible approach and is consistent with the team's already-deployed `RenewalMaintenancePricingService`/NetUnitPrice-seed work in the live `COLAUpliftPrehook` (`buildNetUnitPriceUpdate`).
- doc-12 correctly identifies that the posthook and before-save-flow levers are dead (C8, C9 confirmed).

### The unproven crux — and the evidence against it
doc-12 §4.1 itself flags the load-bearing assumption as unproven: *"a prehook-set InputUnitPrice/ListPrice actually makes a ListPrice=0, derived, 'No Change' line get carried + priced ... This is the crux and is UNPROVEN."* The evidence **leans against** a bare seed working:

1. **The standard `NetUnitPrice=InputUnitPrice` assignment is gated to NON-derived lines.** The live `AttributePricingFilter` (parentStep `ListContainer49`/`ListContainer46`) requires `DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute Equals false`. The canary's `DerivedPricingAttribute` is **null/unhydrated** (it appears 0× in that map across all logs; only license `dn3x4=false` appears). A null-`DerivedPricingAttribute` line **fails `IsNotNull` and is skipped regardless of any seeded `InputUnitPrice`**.
2. **`ck6X4` proves a clean COLA write does not land on a derived line** even when the line is a map key (held at 0.0 through both prehook and posthook writes).
3. **The native derived path has a `NetUnitPrice`-resetting element** (`DerivedPricingNetUnitPriceValueReset`, FormulaBasedPricing outputting `NetUnitPrice`) in the derived branch.

**Implication:** the seed almost certainly must ALSO set/hydrate `DerivedPricingAttribute=false` (to route the line into the standard assignment) **or** neutralize `ItemIsDerived` — a larger, riskier change than doc-12 implies. Seeding `InputUnitPrice` alone is predicted insufficient.

### What MUST be tested before building (the ONE decisive test)
On a throwaway/clone with an **active** procedure version: extend `COLAUpliftPrehook` to (a) admit the 'New Maintenance'/'No Change' renewal line, (b) seed `InputUnitPrice` AND `ListPrice` = `COLACalculatedPrice__c`, and (c) set/hydrate `DerivedPricingAttribute=false` for it, **before** the procedure; then reprice the canary with FINEST. Decision rule:
- If `dn3y4` then appears as a key in the engine `NetUnitPrice` map with **67.38** and the committed QLI persists 67.38 (and `ValidationResult` does not flip to `TransactionIncomplete`/`MissingContributor`) → fix direction validated.
- If `dn3y4` is still absent/0/null despite the seed → bare-prehook approach is refuted; pivot to the native derived-pricing-config route (below).

---

## Risks, landmines, and corrections to doc-12

**Corrections to doc-12:**
- **"grep `NetUnitPrice=` = 0 for dn3y4"** is imprecise — a naive grep returns 5 hits, all `FLOW_VALUE_ASSIGNMENT $Record` dumps where `NetUnitPrice=null`. True only for engine `^Map={` entries. (Doesn't change the verdict; the precise claim is correct.)
- **"No layer can persist NetUnitPrice" / "67.38 never bridged to a price field"** — overstated (C4/C9). The posthook *does* write `NetUnitPrice=67.38`; it just never persists for a non-priced node. State it as "written-but-not-persisted."
- **Cause is mis-attributed** (C2). 'No Change' is NOT the disqualifier (license is also 'No Change' yet prices). The driver is `DerivedPricingAttribute` null + `ItemIsDerived` + `ListPrice=0`.
- **"V14/V140 active"** — not confirmable; at verification time **all 14 versions were Inactive** (mid-republish). Re-confirm the live active version before any conclusion.
- **§7 "procedure revert pending"** — stale by ~7 minutes; the `chk_revert` retrieve (13:08) shows the procedure is in fact pristine (`DerivedPricingRenewals.resultIncluded=false`, `DerivedProductsRenewals.resultIncluded=true`). Procedure revert is **done**.

**The native-edit alternative's blast radius (why B's "surgical" fix is dangerous, even setting aside that it's refuted):** the earlier "Option C" native flip was downgraded because it would zero **~513,622 of 513,627 renewal-maintenance QLIs** — a catastrophic blast radius. Even the "surgical filter" variant must be authored against the **live** `COLAUpliftPrehook` (Org Data/_src), which has a `buildOverrideMap(List<SObject>)` method the stale `Data/sc-maint/src` copy lacks; deploying the stale class triggers a ~28-class dependent-recompile cascade (`CommunitiesLandingController`, `SelfRegController`, etc.) per `validate_v3.json`. doc-12's landmine #8 is real.

**Accepted quote `00781068`:** carries a renewal-maintenance line at `NetUnitPrice=60.64` (COLAcalc 67.38). Two concerns: (a) any fix that re-prices it needs business sign-off; (b) **even the "working" value 60.64 ≠ the expected 67.38** — likely term/proration, but it means the "working" comparator may not validate the expected single-year math. Flag, don't disturb.

**Version churn:** the procedure moved V9→V14 in days and was mid-republish at verification. Any element-level analysis is **version-pinned to V14** and must be re-confirmed once an active version is republished.

**Uncommitted-evidence risk:** none of the SC-3404 artifacts (`Data/sc-maint/sc3404/`, docs 05–12) are committed to git. If the working tree is cleaned, the entire investigation survives only in self-contradicting memory files. Recommend committing the dossier before touching the tree.

---

## Live UAT state snapshot (observed 2026-06-13 ~18:19Z)

| Item | doc-12 claim | Live observation |
|---|---|---|
| Pricing procedure active version | V14/V140 active | **ZERO active versions** — all 14 `ExpressionSetVersion` `IsActive=false`, all 14 `ExpressionSetDefinitionVersion` `Status=Inactive`, LastModified 18:06–18:07Z (**mid-republish**). V14/V140 is highest but Inactive. |
| `PartnerNetPricePosthook` | reverted to v1.4 | **Confirmed** `@version 1.4`; `loadRenewalMaintenanceLines` line 806 `= 'Renewal Maintenance'` (single equality, no IN-list, no v1.5, no test) |
| `COLAUpliftPrehook` | renewal gate `QuoteAction.Type='Renew'`; writes only custom fields | **Confirmed** `@version 1.1`; writes only `COLACalculatedPrice__c` et al.; **no** `InputUnitPrice`/`ListPrice`/`NetUnitPrice` seed today |
| Flow `Stamp_Maintenance_Pricing_Inputs` | V13 Active | **Confirmed** ActiveVersionId `301WC00000kgtSIYAY` = V13/Active; stamps `COLACalculatedPrice__c` (not `NetUnitPrice`) |
| Canary maint line `0QLWC000003dn3y4AA` | `NetUnitPrice=null`, COLAcalc 67.38 | **Confirmed** `Fortra_Product_Type__c='New Maintenance'`, `NetUnitPrice=null`, `UnitPrice=null`, `ListPrice=0`, `Quantity=0`, `COLACalculatedPrice__c=67.38`, `Base_Price__c=71`, `Source_List_Price__c=355` |
| License line `0QLWC000003dn3x4AA` | prices 301.75 | **Confirmed** `NetUnitPrice=301.75`/`UnitPrice=301.75`/`ListPrice=355`; `Quantity=0` (NetTotal=0 only due to qty) |
| Maint PBE / derived config | (not in doc-12) | PBE `01uWC000005wsbUYAQ` `IsDerived=True`/`UnitPrice=0`; **has** `PriceBookEntryDerivedPrice` `182WC000000FN26YAG` (Formula=`UnitPrice`, contributor `PIA-PIA-NRPS-PIAP`) — NOT the SC-3372 missing-config gap |

---

## Recommended next actions for the build owner (Nir)

1. **Re-confirm the live active procedure version FIRST.** Re-poll `ExpressionSetVersion WHERE ExpressionSetId='9QLWC0000015cDl4AI' AND IsActive=true`. The procedure was mid-republish at verification; do not draw live conclusions or attempt a reprice until an active version exists. Re-verify the V14 element structure (`DerivedProductsRenewals` seq 5 / `DerivedPricingRenewals` seq 7 / `DerivedProductsNonRenewal` gate) against whatever version is then active — the analysis is version-pinned.

2. **Run the ONE decisive validation test** (do this BEFORE any build commitment). On a throwaway/clone of `COLAUpliftPrehook`, for the stamped renewal-maintenance line, seed `InputUnitPrice` AND `ListPrice` = `COLACalculatedPrice__c` (67.38) AND set/hydrate `DerivedPricingAttribute=false`, **before** the procedure; reprice canary `0Q0WC0000038aXd0AI` with FINEST + the pricing **waterfall/explainability** panel.
   - **PASS:** `dn3y4` enters the engine `NetUnitPrice` map at 67.38, persists to the QLI, `ValidationResult` stays clean → fix direction validated; proceed to build (with the `DerivedPricingAttribute` co-set, not a bare seed).
   - **FAIL:** still 0/null → pivot to action 4.

3. **Capture the waterfall trace doc-11 named but never ran.** It positively identifies *which* element owns `dn3y4`'s final `NetUnitPrice` output (or confirms no element emits one). This converts "best-supported inference" into proof and seals the refutation of B.

4. **If the prehook seed fails: pursue the native derived-pricing-config route, not the refuted native-override edit.** Investigate why the RNM 'New Maintenance' product (`01tWC00000DD1bsYAD`, canary, `NetUnitPrice=null`) behaves differently from the structurally-analogous RRM 'Renewal Maintenance' product (`01tWC00000DD1buYAD`, which prices to 0/60.64) — both are `IsDerived=True`/`UnitPrice=0` with `PriceBookEntryDerivedPrice` to the same license. The likely lever is `DerivedPricingAttribute` hydration / product-type handling, OR flipping the discarded `DerivedPricingRenewals` formula to `resultIncluded=true` **scoped narrowly** to the stamped renewal-maintenance cohort.

5. **Do NOT pursue the "surgical native filter" Option-C edit** (refuted as cause; 513K-line blast radius). Do NOT author any `COLAUpliftPrehook` change against the stale `Data/sc-maint/src` copy — use the live `Org Data/_src` source (preserve `buildOverrideMap`); deploy targeted Apex with `--test-level RunSpecifiedTests` to avoid the ~28-class recompile cascade.

6. **Confirm the data question:** is the canary maint line correctly typed `Fortra_Product_Type__c='New Maintenance'` on a Renewal quote? This typing is what makes it miss the renewal-QLI seed (C3) and trip the v1.4 posthook filter (C11). If it should be 'Renewal Maintenance', the fix may be partly a data/stamping correction (Stamp flow), not pure code.

7. **Commit the SC-3404 dossier and `Data/sc-maint/sc3404/`** before touching the working tree — the entire investigation is currently uncommitted and the memory files self-contradict.

---

## Evidence appendix

**Procedure XML (live-equivalent, post-revert pristine):** `Data/sc-maint/sc3404/chk_revert/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
- V14 block lines ~69795–75410; `<status>Active>`/`<versionNumber>14</versionNumber>` is the last block (also confirms live identity).
- `DerivedPricingRenewals` (formula): lines ~71830–71889 — output→`NetUnitPrice`, `resultIncluded=false`, parentStep `ListContainer` (top-level seq 7).
- `DerivedProductsRenewals` (native): lines ~71978–72101 — `actionType=DerivedPricing`, outputs `NetUnitPrice→NetUnitPrice` (72080-72084) + `Subtotal→ItemNetTotalPrice` (72087-72091), `resultIncluded=true`, parentStep `DerivedProductsNativePull` (top-level seq 5).
- `DerivedProductsNonRenewal` (filter): lines 71957–71976 — `QuoteTypeText__c NotEquals 'Renewal'`, child seq 1.

**FINEST logs (`Data/sc-maint/sc3404/logs/`):**
- Base canary `07LWC00000OxZTl2AN.log`: `grep -c dn3y4`=646; `^NetUnitPrice={`/`^InputUnitPrice={`/`^PartnerUnitPrice={` → 0 dn3y4 hits; 16 maps each carry only `dn3x4=301.75`. `ListPrice={dn3y4=0.0, dn3x4=355.0}` (1489); `ItemIsDerived__std={dn3y4=true, dn3x4=false}`; `SalesTransactionActionType={dn3y4=No Change, dn3x4=No Change}` (1508); `COLACalculatedPrice__c={dn3y4=67.38}`. `DerivedProductsRenewals`/`DerivedPricingRenewals`/`resultIncluded` = 0 occurrences. Prehook 11176 SOQL `Rows:0` → 11216 "Found 0 renewal QLIs from 2 total" → 11342 "submitted 0 asset-renewal context updates". Last `RLM_PRICING_END` 15457 @09:15:48; Stamp flow 17190 @09:15:53.988 (no reprice after).
- v1.5 posthook `07LWC00000Oxacj2AB.log`: SOQL [801]/20130 `Fortra_Product_Type__c IN ('Renewal Maintenance','New Maintenance')`; 13163 `colaNet|67.38`; 13345 "RENEWAL MAINT COLA: Line 0QLWC000003dn3y4AA -> Net=67.38"; 13358 8-attr payload dataPath `[0Q0WC0000038aXd0AI, 0QLWC000003dn3y4AA]`; 13720→13721 `updateContextAttributes` clean, 13729 `linesUpdated|1`; `persistContext`=0; `RLM_PRICING_BEGIN` @13809; maps post-write 13772/13833 still `{dn3x4=301.75}`; final `$Record` 17349/17508/17531 `dn3y4 NetUnitPrice=null` + `COLACalculatedPrice__c=67.38`. `CompletedWithPricing` first @18514; `MissingContributor`=0.
- Sibling `07LWC00000OxZYb2AN.log` (quote 00781043, line `ck6X4`): `ck6X4` in 16/16 `NetUnitPrice` maps at 0.0 (first @1504, pre-Apex); prehook 67.38 @9134; posthook 67.38 @10991; `RLM_PRICING_BEGIN` @11128 (after posthook); committed `NetUnitPrice=0.0`; `ValidationResult=MissingContributor` ×169; `PriceCalculationFail` ×112.

**Apex (`Data/sc-maint/sc3404/apex/` + live):**
- `PartnerNetPricePosthook.cls:806` (live v1.4) `AND Fortra_Product_Type__c = 'Renewal Maintenance'`; `:858-865` payload assigns `colaNet→'NetUnitPrice'/'UnitPrice'/'InputUnitPrice'/'PartnerUnitPrice'`; `:704` `ctx.updateContextAttributes`; `:109` only `persistContext` (Order path `applyNetPricesToOrder`).
- `:907-921` `computeRenewalMaintenanceColaNet` = `(71-8.52-0)*(1+7.85/100)` HALF_UP = **67.38** (reproduced).
- Live `COLAUpliftPrehook` (`@version 1.1`): renewal gate SOQL `QuoteAction.Type='Renew'` (~310-317); secondary branch `if (stActionType != 'Renew') continue;` (~1015); writes only custom fields; live `Org Data/_src` copy has `buildNetUnitPriceUpdate` + `buildOverrideMap` absent from stale `Data/sc-maint/src`.

**Live SOQL / describe (FortraUAT):**
- `QuoteLineItem.NetUnitPrice`: `createable=False`, `updateable=False`, `calculated=False` (confirms C8 read-only); `UnitPrice`/`COLACalculatedPrice__c` both `True/True`.
- Canary `0QLWC000003dn3y4AA`: `New Maintenance`, `NetUnitPrice=null`, `ListPrice=0`, `Quantity=0`, `COLACalculatedPrice__c=67.38`, `QuoteAction.Type='No Change'`.
- Procedure `9QLWC0000015cDl4AI`: 14 `ExpressionSetVersion` all `IsActive=false`; 14 `ExpressionSetDefinitionVersion` all `Status=Inactive` @18:06-18:07Z (mid-republish).
- Maint PBE `01uWC000005wsbUYAQ` `IsDerived=True`/`UnitPrice=0`; `PriceBookEntryDerivedPrice` `182WC000000FN26YAG` (Formula=`UnitPrice`, contributor `PIA-PIA-NRPS-PIAP`, Scope=Both).

**Revert/deploy artifacts:** `revert_apex_result.json` (Succeeded, 46/46 tests, 17:59Z); `revert_flow_result.json` (Succeeded, V13, 17:24Z); `revert_proc_result.json` (cosmetic `MetadataTransferError`, but `chk_revert` @13:08 confirms pristine); `deploy_v3/v4/v5_result.json` all `MetadataTransferError`; `deploy_apex_result.json` real compile fail (`Type is not visible: RevSignaling.SignalingApexProcessor`, `Duplicate modifier: TestVisible 796:36`).

**Web/doc references (for the crux):** Trailhead "Implement/Explore Derived Pricing" — a derived product is *designed* `ListPrice=0`/`IsDerived=true` and is priced by the native Derived Price element (`NetUnitPrice` is its output, keyed off the `DerivedPricingAttribute` context tag). revenuecloud.info "Unpacking the Revenue Cloud Pricing Procedure Part 1" — the standard `NetUnitPrice=InputUnitPrice` assignment "filters for records where we are **not** deriving our pricing from other quote line sources" (i.e. seeding `InputUnitPrice` is skipped for a still-derived line). RLM Dev Guide v67 — `QuoteLineDetail.NetUnitPrice` is Filter/Sort only (engine output); `ValidationResult=TransactionIncomplete` when a line is modified outside the standard flow; `MissingContributor` = "derived product but no pricing source."