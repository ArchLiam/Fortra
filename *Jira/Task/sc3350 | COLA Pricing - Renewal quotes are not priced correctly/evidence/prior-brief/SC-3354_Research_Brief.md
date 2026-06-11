# SC-3354 — COLA Renewal Pricing: Deep Research Brief

**Owner:** Liam (rework) → hand back to Nir Kailash (peer test). Original impl: Marc DeBrey.
**Date:** 2026-06-10. **Org:** FortraUAT (read-only research). **Status:** pre-coding research complete.

This brief grounds the rework. It is the synthesis of 7 parallel research streams (renewal-line creation, prehook chain, pricing procedure, COLA Apex logic, data model/drift, docs/business intent, test coverage), every claim verified against live UAT.

---

## 0. The one-paragraph truth

COLA is implemented **twice** — a trigger (`COLAUpliftHandler`) that stamps `UnitPrice`/`Pre_COLA_Price__c`/`COLA_Source__c` on QuoteLineItem insert/update, and a pricing **prehook** (`COLAUpliftPrehook`) that writes `COLACalculatedPrice__c → InputUnitPrice` during a pricing-procedure reprice. The prehook's header says it *"replaces the trigger,"* **but the trigger was never removed — both are live.** The pivotal fact: **renewal quotes are generated headlessly and never run a full pricing reprice through the procedure.** That single fact causes **both** stated defects:

- **Defect #1 (priced at list):** the only code that runs on a headless renewal is the trigger, and `handleBeforeInsert` bails when `QuoteActionId` isn't on the row yet — which the RLM engine sets ~35s *after* insert. No reprice → the prehook never rescues it → line keeps list price.
- **Defect #2 (no description):** `QLDescriptionGeneratorPrehook` only runs *during* a pricing-procedure reprice. No reprice → it never fires → **0 of 1,222,003 renewal lines** have a generated description.

**So the unifying fix is to make renewals actually run a full reprice (which fires the whole prehook chain — COLA + description), or to move both COLA and description generation onto the renewal trigger/flow path.** That decision is the spine of the ticket.

---

## 1. Defect #1 — Renewal priced at list (COLA never applied)

**Root cause (confirmed in code + data):** `COLAUpliftHandler.handleBeforeInsert` (live `COLAUpliftHandler.cls:29-31`) returns early at `if (quoteActionIds.isEmpty()) return;` — it only reads `QuoteActionId` off the inserting rows. The standard RLM path (`Fortra_Create_Renewal_Quote` → platform `initiateRenewal`) creates the Quote, QuoteAction, and QLIs as **separately-finalized** records; `QuoteActionId` is **not reliably in `Trigger.new` at before-insert** (the prehook author even documents this: *"QuoteActionId is not available in context tags at runtime"*, `COLAUpliftPrehook.cls:208-210`).

**Live evidence:**
- Repro line `0QLWC000003bHpl4AE` (Quote `0Q0WC00000365Uj0AI`, created 2026-06-07 **after** the rework): `ListPrice=10000`, `UnitPrice=10000`, all COLA fields null. Valid Renew QuoteAction `7ocWC00000tYaFtYAK`, SourceAsset `02iWC000007DXlJYAW` Price `10000`, category `Brand Protection`, active 5% CMDT rule. Expected `10500`. The QuoteAction's `LastModifiedDate` is **35s after** the QLI insert.
- Of 34 COLA-stamped renewal lines: **13 stamped in-insert, 21 stamped on a later update** — the ~38/62 split is the fingerprint of an unreliable before-insert path rescued by the pricing-write-back UPDATE most of the time.
- `handleBeforeUpdate` can't self-heal an unstamped line: its recalc requires `Pre_COLA_Price__c != null` (`COLAUpliftHandler.cls:161`), which is null on a never-stamped line.

**Fix anchors (pick after Marc confirms architecture):**
- **A — after-insert reconcile:** re-query inserted QLIs joined to `QuoteAction` (Type='Renew') by QLI Id, update COLA fields. Reliable (FK queryable post-insert); needs a recursion guard; may race the engine write-back.
- **B — before-update self-heal:** let `handleBeforeUpdate` *derive* (not just recalc) COLA for unstamped renewal lines; drop the `Pre_COLA_Price__c != null` precondition. Smallest change; won't help lines that never receive any update unless paired with a forced reprice.
- **C — prehook-only (delete handler):** matches Marc's stated direction. Cleanest, but depends on guaranteeing a pricing pass on every renewal QLI (today not guaranteed).
- **Unifying:** **force a Reprice-All on renewal creation** → fixes #1 and #2 together.

---

## 2. Defect #2 — Renewal lines get no Line Item Description

**Root cause (confirmed):** `QLDescriptionGeneratorPrehook` (a `SignalingApexProcessor`, "Register LAST in the chain") only runs **during pricing-procedure execution**. Renewals never reprice through the procedure, so it never fires. The prehook code, registration, attribute hydration (`SalesTransactionItemAttribute`), and writeback (`SalesTrxnItemDescription`, `fieldType=inputoutput`) are all **correct** — proven by 321 non-renewal lines getting descriptions with identical attribute structure.

**Live evidence:**
- **0 of 1,222,003** renewal lines have a generated pipe-format description; **321** non-renewal lines do (0 of them renewals).
- A non-renewal line (`0QLWC000003cIGm4AM`) and a renewal line (`0QLWC000002UYeI4AW`) have **identical** 4-attribute structure; only the renewal lacks a description. The only difference is `QuoteAction.Type='Renew'`.
- 27–28/34 renewal lines DO carry the attributes the generator needs — so it's **not** missing inputs. (6/34 carry **zero** attributes — a separate upstream gap.)

**Important wrinkles:**
- The prehook chain registration/order (`DescriptionLinePrehook`) is **UI-only RLM config** — NOT in any retrievable metadata (confirmed exhaustively; documented in SC-3349 README). Must be captured as a change-controlled runbook step.
- `submitContextUpdates` **silently swallows** "not in updatable state" (`QLDescriptionGeneratorPrehook.cls:622`) — if the renewal reprice runs in a non-updatable context, writes drop invisibly. Verify during fix.
- Description format spec (SC-3349): `Product | <UnitType>: <count> | <Term> | <Config...>`, e.g. `beSECURE - Cloud-Based | Devices: 36-65 | One Time | Cloud Based`. Qty from `Attribute_Volume` else `Number_of_Units`. **If COLA adds its own prehook, it must run BEFORE `DescriptionLinePrehook`.**

**Fix anchors:** (a) add post-creation Reprice-All to the renewal flow so the existing prehook fires, or (b) port the description build onto the renewal trigger path. (a) also fixes #1.
**Scope note:** the description logic lives in `QLDescriptionGeneratorPrehook`, NOT a COLA class — confirm with Marc whether SC-3354 touches it or just asserts it end-to-end.

---

## 3. The scope fork — single-year vs the spreadsheet's multi-year model

This is the decision that determines the size of the ticket.

- **Design docs** (COLA SDD `Data/sc3347/docs_txt/Fortra-Pricing-COLA-Solution-Design-Doc.txt`, Overview, Increase Table) describe a clean **single-year** model: `UnitPrice = Asset.Price × (1 + COLA%/100)`, gross base, renewal-only, 3-tier override. The live **year-1 path implements this faithfully** (verified to the penny on audit quote `0Q0WC000003671t0AA`).
- **The ticket spreadsheet** ("Perpetual Sales Calculations") is the **real business target** and is richer: **multi-year compounding** — "Base Price + Cola" 200→206→212.18 and "Renewal Maintenance Total" 140→144.20→148.53 (×1.03/yr) — applied to **both** the license/base line **and** the maintenance line, with the **year-1 rate** (CMDT Solution-Category, 4.7–12%) **distinct** from the **out-year rate** (MyCAP 3%).
- **Live MyCAP/outyear code is Marc's half-finished attempt at the spreadsheet:** it computes the compounded value into the **display-only formula field** `Final_Year_COLA_Calculated_Price__c` but **never feeds it to price** — the field is referenced **0 times** in the pricing procedure. **The out-year compounding is computed but never billed (INERT).** And the formula itself is broken (see B4).

**→ Decision for Marc/German:** does SC-3354 = "fix the two year-1 defects" (small, well-scoped), or = "finish wiring the multi-year out-year compounding into actual pricing, for license + maintenance" (large, touches the procedure, maintenance derivation, regional)? **Everything downstream hangs on this.**

---

## 4. Live pricing-procedure wiring (active version = **V10**, not V9)

Memory referencing "active V9" is **stale** — the org's active `Rev_Mgmt_Default_Pricing_Procedure` is **VersionNumber 10** (startDate 2026-05-31). Two COLA elements in V10:

| Path | Steps | Gating | Formula → target | Applies to |
|---|---|---|---|---|
| **A** (prehook-fed) | `COLAUpliftonRenewal` filter + assign, waterfall seq 9 | `ActionType='Renew'` AND `DerivedPricingAttribute=false` AND `COLA_Uplift_Percent__c` not null | `COLACalculatedPrice__c` → **`InputUnitPrice`** | non-derived renewal lines |
| **B** (self-derived) | `DerivedPricingRenewals` formula, seq 7 | container `DerivedPricingAttribute=true` AND `AttributeDefinitionCode='MDT'`; formula re-checks `QuoteTypeText__c='Renewal'` | `(Base_Price − Prior_Partner_Discount − Prior_Discretionary_Discount) × (1+COLA%)` → **`NetUnitPrice`** | MDT/maintenance-derived renewal lines |

- The two paths are **mutually exclusive on `DerivedPricingAttribute`** (anti-collision), but use **different bases**: A uses raw `Asset.Price` (no discounts); B nets prior discounts. **Inconsistent.**
- **Regional does NOT compound with COLA.** Design doc claims `Final = Asset.Price×(1+COLA%)×RegionalMult`. Live regional (`RegionalServicesPrice27`, seq 11; reconcile seq 33) is **Services-only** and applies as a **MIN/floor** (`NetUnitPrice = MIN(RegionalNetUnitPrice__c, NetUnitPrice)`) that can *overwrite* the COLA'd `InputUnitPrice` — not a multiplier. SDD's compounding claim is **obsolete**.
- **Double-application exposure:** trigger writes COLA'd `UnitPrice` at insert; procedure re-applies COLA into `InputUnitPrice` from the prehook. If the procedure's list base derives from the already-uplifted `UnitPrice`, that's double-uplift. **Needs a live waterfall trace to quantify.**
- Context: `SalesTransactionContextExt_v2`. `COLAUpliftPercent__c`/`COLAApplied__c`/`COLAExplainer__c` **poison** the prehook's `updateContextAttributes` batch and are deliberately excluded; `COLA_Uplift_Percent__c` is synced by the **trigger** instead (`COLAUpliftPrehook.cls:460-463`). Any rework must preserve which attrs are hydration-mapped or writes silently drop.

---

## 5. Latent bugs (beyond the two stated defects)

| # | Bug | Location | Severity | Confirmed |
|---|---|---|---|---|
| B1 | **Multi-asset contract override collapses to ONE asset** — map keyed by `contractId`; other assets fall to CMDT, `COLA_Source` mislabeled `CMDT Lookup` | `AssetContractQueryHelper.cls:47-52` | HIGH | Live: `800WC00000PCpoMYAT` @4%, 4 assets `02iWC000007RVDN/DO/DP/DQ` — 3 get wrong price. (Prehook is NOT affected — it keys per-ACR.) |
| B2 | **Prehook fail-silent** — returns SUCCESS on every exception; contract-override query failure degrades to CMDT with no signal | `COLAUpliftPrehook.cls:90-96,604-607` | HIGH | Code |
| B3 | **Out-year/MyCAP entirely inert for pricing** — `Final_Year_COLA_Calculated_Price__c` referenced 0× in procedure; spreadsheet's Y2/Y3 totals computed but never billed | repo-wide grep | HIGH (design gap) | Yes |
| B4 | **`Final_Year` formula broken** — primary branch compounds wrong base (`COLACalculatedPrice` not pre-COLA); fallback uses `PricingTermCount` (months) as a years exponent, no `PricingTermUnit` guard; branches mutually inconsistent | field formula | HIGH-if-activated | Live formula text |
| B5 | **"One-time" null-persist override never consumed** — re-applies on every renewal forever (no consumption mechanism) | `Handler.cls:409-415`, `Prehook.cls:621-625` | MEDIUM | Code |
| B6 | **Asset.Price guard mismatch** — handler skips only null; prehook skips null OR `<=0` → divergent stamped state on zero/negative price | `Handler.cls:264-267` vs `Prehook.cls:274-278` | MEDIUM | Code |
| B7 | **Duplicate COLA computation** (handler + prehook) never reconciled — split-brain on which is authoritative | `Handler.cls:299` vs `Prehook.cls:358` | MEDIUM | Established |
| B8 | **TEMP_BoKS trap** — `TEMP_BoKS_IAM_ProductCat` ('Powertech Identity & Access Manager (BoKS)') is the ONLY active rule covering **17 live BoKS products**; permanent rule 'Powertech IAM BoKS' matches **0**. Deleting TEMP before go-live (as instructed) strands BoKS renewals at silent 0% | CMDT data | MEDIUM (go-live) | Live |

Also: per-Solution **product-level rate exceptions** (Messenger* = 12%, SecureCare/SSO = 4.70%) can't be represented by a CMDT keyed only on `Solution_Category__c` (D8) — verify whether those products carry distinct category values on Product2.

---

## 6. Packaging / prod-promotion (the "deploy would regress" blocker)

The whole feature is **live-only**; `force-app` has almost none of it. Deploying current `force-app` would **regress prod**. NOT in `force-app`:

- **Apex (14):** COLAUpliftHandler, COLAUpliftPrehook, COLAUpliftTest, AssetContractQueryHelper, QLDescriptionGeneratorPrehook (+test), and the UpliftRates* service layer (IUpliftRatesSelector, IUpliftRatesService, UpliftRateMatcherStrategy(+Test), UpliftRatesController(+Test), UpliftRatesSelector(+Test), UpliftRatesService, UpliftRatesServiceImpl, UpliftRatesServiceTest).
- **CMDT:** `COLA_Uplift_Rules__mdt` + `MyCAP_Rules__mdt` (type defs) and all **23 records** (22 COLA + 1 MyCAP).
- **Fields:** QLI `COLA_Outyear_Uplift_Percent__c`; entire **Contract** object dir (`COLA_Override_Percent__c`, `COLA_Override_Persist_Until__c`); 5 **OrderItem** COLA fields.
- **Picklist:** `force-app` `COLA_Source__c` is **restricted** with only 3 values — **missing `MyCAP Default`** (the handler writes it, `Handler.cls:200`). Deploy throws `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`.
- **Other:** `COLA_Admin` permission set; `COLAUpliftPass`/`COLAUpliftFail` ExplainabilityMsgTemplates.
- **Reverse drift:** `DocuSign_API_Access` PS (in force-app) references `OrderItem.COLA_Uplift_Percent__c`, which is absent from force-app.

**Live CMDT rate table (22 active, all dates null):** Brand Protection 5, Business Intelligence 7.85, Capacity Management 4.7, Cloud Data Protection 5, Core IGA 4.7, Cybersecurity 7.85, Data Protection 4.7, Doc Management 7.85, Email Security 5, File Integrity Monitoring 5, Fortra Platform 0, Globalscape 7.85, GoAnywhere 7.85, Human Risk Management 5, IPP 0, Network Monitoring 7.85, Offensive Security 6.2, Powertech IAM BoKS 7.85 (DEAD — 0 products), Robotic Process Automation 9.85, Systems Management 7.85, **TEMP** Powertech Identity & Access Manager (BoKS) 7.85 (17 products), Vulnerability Management 6.2. MyCAP_Rules: Global out-year 3 / min 3.

---

## 7. Test coverage + plan

**Current (re-confirmed):** COLAUpliftHandler **42%**, COLAUpliftPrehook **3%**, AssetContractQueryHelper **0%**, org-wide **39%** (below the 75% prod gate). 31 methods, 100% pass — but **14 are pure tautologies** (re-implement the formula inline and assert against themselves), 6 smoke/negative, ~9 real (all on `handleBeforeUpdate`/`isManualLineOverride`), 2 thin entry-only.

**Zero-covered, load-bearing paths:** `populateCOLAFields` (renewal insert happy-path, L237-309, incl. the `UnitPrice`/`Pre_COLA`/`Source` writes); `getContractOverrides` + `AssetContractQueryHelper`; **all** of `COLAUpliftPrehook.execute()→processLineItems()`.

**Prehook is untestable as written** (needs a `Context.IndustriesContext` that can't be fabricated). **Refactor prerequisite:** extract the pure pricing/override math into `@TestVisible static` methods (mirror the proven `QLDescriptionGeneratorPrehookTest` pattern) — ~75% of the prehook is otherwise unreachable in a unit test. Then add behavioral tests: defect-#1 insert path, contract-override insert path, multi-asset, MyCAP/outyear, and the pure-math methods. Full plan in the test-research stream.

---

## 8. Consolidated open questions for Marc DeBrey / German Wren

**Architecture (blocking):**
1. Is the before-insert/trigger COLA path **still load-bearing**, or vestigial? The prehook header says it "replaces" the handler, but the trigger still runs. Consolidate to one engine, or keep both? Which wins when they disagree?
2. By design, **does renewal generation ever run a full pricing reprice** through the procedure? (Data says no — that's why both defects exist.) Should the fix be "force a Reprice-All on renewal creation" (fixes both) or "move COLA + description onto the trigger path"?

**Scope (blocking):**
3. Is SC-3354 just the **two year-1 defects**, or does it include **wiring the multi-year out-year compounding into actual pricing** (the spreadsheet's Y2/Y3 — currently inert)? For license lines only, or **maintenance lines** too (B3/B4/D4/D5)?
4. **COLA base:** gross `Asset.Price` (docs + live) or the **prior net** (post-discount) renewal price? Path A and Path B already disagree.

**Behavior:**
5. **Regional × COLA:** MIN-floor (live) or compounding-multiplier (SDD)? (D6)
6. **Override stickiness:** set-once (Increase Table) or re-sync-every-reprice with override detection (live)? (D7)
7. **Multi-asset contract override (B1):** re-key `AssetContractQueryHelper` per-ACR (like the prehook), or is one-asset-per-active-contract a real invariant the data violates?
8. **Out-year (B3/B4):** wire `Final_Year_COLA_Calculated_Price__c` into price? If so, fix the base/exponent first. Confirm year-1=CMDT, out-year=MyCAP 3% flat.
9. **"One-time" override (B5):** null persist = apply-once-then-stop, or apply-forever (live)? If once, what consumes it?
10. **Per-product rate exceptions (D8):** Messenger* 12% / SecureCare/SSO 4.70% — do those products carry distinct `Solution_Category__c`, or do we need a product-level override?
11. **Fail-silent prehook (B2):** should COLA failure surface to Deal Desk, or is silent-SUCCESS acceptable?
12. **Asset.Price ≤ 0 (B6):** skip (prehook) or stamp $0 (handler)? They must agree.

**Packaging:**
13. Is **force-app authoritative** (back-fill from UAT) before any change? OK to add `MyCAP Default` to the restricted `COLA_Source__c` value set? Is the Contract object + OrderItem COLA fields + the UpliftRates* service layer **in scope** for source-control here?
14. **TEMP_BoKS go-live (B8):** re-categorize the 17 Product2 records to 'Powertech IAM BoKS', or re-point the permanent rule to the live string? (Also the DEAD 'Fortra Platform' rule + 88 null-category products.)

**Description (#2):**
15. Where exactly is the `DescriptionLinePrehook` chain order stored in Setup (UI-only)? Is it still LAST after the V10 republish? Does the renewal reprice run in an **updatable** context (else writes silently drop)?

---

## 9. Key artifacts (retrieved/verified)

- Live classes: `Data/cola-renewal-review/live/classes/{COLAUpliftHandler,COLAUpliftPrehook,COLAUpliftTest,QLDescriptionGeneratorPrehook,AssetContractQueryHelper}.cls`
- Live trigger: `Data/cola-renewal-review/live/triggers/QuoteLineItemTrigger.trigger`
- Live V10 procedure: `Data/cola-renewal-review/live/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
- Live context: `Data/cola-renewal-review/context/` (`SalesTransactionContextExt_v2`)
- Outyear field: `Data/cola-renewal-review/live/objects/QuoteLineItem/fields/Final_Year_COLA_Calculated_Price__c.field-meta.xml`
- Design docs: `Data/sc3347/docs_txt/Fortra-Pricing-COLA-Solution-Design-Doc.txt`, `Confluence/Cola+Increase+Table.doc`, `FORTRA_KNOWLEDGE_BASE.md:240-266`
- Description spec/history: `*Jira/testing/SC-3349 Line Item Description Issues/README.md`
- Repro line: `0QLWC000003bHpl4AE` / Quote `0Q0WC00000365Uj0AI`. Audit (correct) quote: `0Q0WC000003671t0AA`. Multi-asset contract: `800WC00000PCpoMYAT`.
