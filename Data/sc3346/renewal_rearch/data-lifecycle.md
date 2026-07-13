I have a complete, evidence-backed picture. All COLA math cross-verified against the live CMDT (BoKS 7.85%, Vulnerability Mgmt 6.2%, Email Security 5%). Compiling the report.

---

# RENEWAL LIFECYCLE — END-TO-END, AS ACTUALLY RUN IN FortraUAT (read-only trace, 2026-07-09)

## 0. Scale / reality check (the single most important framing fact)

| Metric | Count | Meaning |
|---|---|---|
| `Quote.Quote_Type__c='Renewal'` | **124,718** | Overwhelmingly **migrated legacy** renewal quotes — no RCA action model |
| `QuoteAction` total (all types) | **~305** | The *entire* RCA-native renewal/amend history in this org |
| `QuoteAction.Type='Renew'` | **102** | RCA-native renewals ever run |
| `No Change` / `Amend` / `Cancel` / `Add` | 85 / 71 / 40 / 7 | |
| `Contract` Status=Activated / **Renewed** | 29,452 / **0** | **No contract has EVER reached Status=Renewed** |
| `Contract.Renewal_Status__c` Pending / Accepted / In Progress / Quoted / Declined | 1,173 / 7 / **0 / 0 / 0** | Only two of five SDD statuses are ever set |
| `Contract.Within_Renewal_Window__c=true` | 5,877 | vs only 1,173 marked Pending |
| `ContractLineItem` | **1** | The CLI-based renewal path is dead |

The RCA renewal engine has been exercised ~100 times total (all recent test accounts). Everything below is traced on those real records.

---

## 1. The ACTUAL state machine (with the real component names)

The SDD describes a native-"Renew"-action design. The live org has **replaced the front half with custom flows** and **rebuilt the maintenance-pricing half** entirely. Active, verified pipeline:

**Stage A — Window detection.** `Fortra_Contract_Renewal_Window_Monitor` (Scheduled, daily 02:00). Sets `Renewal_Status__c='Pending'` on Activated + in-window + null-status contracts. Live: 1,173 Pending. **This is advisory only — it does NOT gate renewal creation** (traced clean renewal below was created on a contract with `Within_Renewal_Window__c=false`).

**Stage B — Renewal Quote creation.** `Fortra_Create_Renewal_Quote` (Active, AutoLaunched) — its own description: *"Override for `quotingAI__createRenewalQuote`. Resolves Asset origin chain, creates Opportunity, calls `initiateRenewal` with pre-resolved OpportunityId and ContractId."* The native createRenewalQuote is overridden. `initiateRenewal` (platform) then generates the **Quote + one `QuoteAction` per selected Asset**, plus one **QuoteLineItem per QuoteAction** (`QLI.QuoteActionId` FK links them; QuoteAction itself only carries `QuoteId`, `Type`, `SourceAssetId`, `Subtype`). A parallel dormant path `Fortra_Renewal_Quote_Creation` (screen flow, builds QLIs from ContractLineItems) is effectively dead — `ContractLineItem`=1 org-wide.

**Stage C — Quote enrichment (TWO competing active flows, both after-save on Quote-create, both 0-min scheduled path):**
- `Fortra_RCA_Renewal_Enhancement` — entry `Quote_Type__c IsNull=true`; traces origin via `AssetAction(Initial Sale)→AssetActionSource→OrderItem`.
- `Fortra_Renewal_Quote_Enhancement` — entry `OriginalActionType='Renew'`; its description: *"Enhances renewal Quotes that the **broken createRenewalQuote override leaves bare**. Reads the Contract and its standing Renewal Opportunity directly (no asset-to-order lineage)."*
A fresh renewal quote satisfies **both** entry criteria → both queue. The second is the current working one; the first is superseded but still active. Both create a Renewal Opportunity and stamp `Quote_Type__c='Renewal'`, `Renewal_Contract__c`, `OpportunityId`.

**Stage D — QuoteAction → per-line action semantics** (driven by the source Asset's selling model, verified on data):
| QuoteAction.Type | Asset condition | QLI outcome |
|---|---|---|
| **Renew** | `Asset.LifecycleEndDate` present (TermDefined) | Priced node, COLA applied, Qty 1 |
| **No Change** | `LifecycleEndDate` null (OneTime perpetual/one-time) | Carried at **Qty 0 / $0** |
| **Amend** | OneTime needing change; `Subtype=FieldAmendment` | field-level amend |
| **Cancel** | explicit removal | credit/cancel line |

Renewability is the immutable Asset lifecycle-end-date, exactly as the established facts state (`HasLifecycleManagement=true` on ALL assets including OneTime — it is *not* the discriminator; **`LifecycleEndDate` presence is**).

**Stage E — Reprice / COLA.** `COLAUpliftHandler` (before-insert on QLI via `QuoteLineItemTrigger`) applies the 3-tier COLA; the **proven maintenance fix** `RenewalQuoteActionStamp.synthesizeRenewQuoteActions` is wired into the same before-insert to manufacture Renew actions for RNM→RRM lines the native path misses.

**Stage F — Quote→Order.** Order created with `Order.QuoteId` FK; **`Order.Type` is blank and `Order.IsRenewal__c=false` even on renewal orders** (verified across all activated renewal orders) — so downstream automation cannot key on Order.Type; it must resolve renewal-ness via `Order→Quote.Quote_Type__c`.

**Stage G — Contract succession.** `Fortra_Renewal_Contract_Succession` (after-save on **Order**, entry `Status='Activated'`). Its only DML: `Update_Original_Contract` sets **`Renewal_Status__c='Accepted'` and nothing else.** Flow description states outright: *"Contract.Status is owned and managed by Revenue Cloud."* Order activation *separately* creates a **new successor Contract** (`Order.ContractId`) via the Order→Contract mapping flows.

**Stage H — Standing renewal-forecast Opp (SC-3500, distinct concern).** `Fortra_Contract_Create_Renewal_Opportunity` (after-save Contract, +15-min path) creates a *separate* forecast Opp on `Contract.Renewal_Opportunity__c` — different record from the Stage-C quote Opportunity.

---

## 2. TRACE 1 — Clean subscription renewal (works correctly)

**Quote `0Q0WC000003Ibx30AC`** ("Renewal Quote", Draft, `Quote_Type__c=Renewal`, Acct `001WC00000XiZP4YAN`, `Renewal_Contract__c=800WC00000TGVrxYAH`, TotalPrice 162,420). Note `Original_Quote__c`/`Original_Order_Id__c`=**BLANK**.

| QLI | Product | Sell model | Action | Src Asset (`Asset.Price`→`Pre_COLA`) | COLA% (src) | UnitPrice = NetUnitPrice |
|---|---|---|---|---|---|---|
| 0QLWC…npyw4 | ES-CEP-**RSL**-ACTIDB (Active Defense) | TermDefined | **Renew** | 02iWC…kDFOYA2 (94,000→94,000) | 5% CMDT (Email Security) | 94,000×1.05 = **98,700** ✓ |
| 0QLWC…npyx4 | VM-APS-**RSL**-BESTSU (beSTORM) | TermDefined | **Renew** | 02iWC…kDFPYA2 (60,000→60,000) | 6.2% CMDT (Vuln Mgmt) | 60,000×1.062 = **63,720** ✓ |
| 0QLWC…npyv4 | BP-ETM-RMS-ADDITH (Add'l Threat Assess.) | OneTime | **No Change** | 02iWC…kDFNYA2 (`LifecycleEndDate`=null) | — | **Qty 0 / $0** |

Source contract 00069429: `Renewal_Status__c`=BLANK, `Within_Renewal_Window__c`=**false** (EndDate 2027-07-05, >120d out) → **renewal created manually, outside the window.** `Pre_COLA_Price__c` = `Asset.Price` exactly. Subscription (RSL) renewals are clean end-to-end.

---

## 3. TRACE 2 — Maintenance first-renewal: the defect and the proven fix, on ONE product, before/after

**Same maintenance product `PIA-PIA-RRM-PIAM` in two states:**

**(a) BROKEN (pre-fix, 2026-06-11)** — Quote `0Q0WC0000037yTx0AI` (Acct "Nir DPP Test 2", Renewal_Contract 00069268):
| QLI | Sell model | Action | UnitPrice | NetUnitPrice | Pre_COLA | COLA_Source |
|---|---|---|---|---|---|---|
| HRM-HRM-RSL-10L50CS | TermDefined | **(none)** | 0 | 0 | null | — |
| **PIA-PIA-RRM-PIAM** | **OneTime** | **(none)** | 0 | 60.64 | null | (blank) |
| VM-BSL-RSL-BESECB | TermDefined | Renew | 7,110.41 | **0** | 6,695.3 | CMDT |

Born OneTime with **no QuoteAction** → excluded from the priced-node path → UnitPrice=0 (only a stray partial net). This is the confirmed defect captured in live data.

**(b) FIXED (2026-07-10)** — Quote `0Q0WC000003JiBh0AK` (Acct "Nir Pricing Test 8", Renewal_Contract 00069437):
| QLI | Sell model | Action (QuoteAction Id) | **Source asset** | Pre_COLA | COLA% | Unit / Net |
|---|---|---|---|---|---|---|
| **PIA-PIA-RRM-PIAM** | **TermDefined** | **Renew** (7ocWC…yFsOvYAK, created 03:33, +1h after quote) | **02iWC…dekAYAQ = PIA-PIA-RNM-PIAMBK** (New-Maint, `LifecycleEndDate`=null, `Solution_Category`="Powertech Identity & Access Manager (BoKS)", Price 71) | 71 | 7.85% CMDT | 71×1.0785 = **76.5735 → Net 76.57** ✓ |
| VM-BSL-RSL-BESECB | TermDefined | Renew (created with quote) | 02iWC…dekCYAQ (same product) | 6,695.3 | 6.2% | 7,110.41 / Net 6,257.16 |

**The cross-product join is proven in data:** RRM line product `PIA-PIA-RRM-PIAM` and RNM source asset `PIA-PIA-RNM-PIAMBK` share `Solution_Category__c`="Powertech Identity & Access Manager (BoKS)" and the same Account `001WC00000ltm01YAA` — the `account|Solution_Category__c` key the synthesized Renew action uses. `Pre_COLA_Price__c`=71 = the RNM `Asset.Price`, even across the product swap. The synthesized action's timestamp (03:33 vs quote 02:30) shows it is injected on a *later* reprice pass, not at quote creation. (`COLACalculatedPrice__c`=382.87 on that line is stale and disagrees with the committed 76.57 — a dead audit field.)

**COLA tiers cross-verified against live `COLA_Uplift_Rules__mdt` (21 records):** BoKS 7.85, Vulnerability Management 6.2, Email Security 5.0 — every priced line above reconciles to `Pre_COLA × (1+pct/100)` with `COLA_Source__c='CMDT Lookup'` (Tier 3).

---

## 4. TRACE 3 — A completed succession (Quote→Order→successor Contract→Assets)

Original contract **00069268** (`800WC00000S9uFmYAJ`) → renewal quote `0Q0WC0000037yTx0AI` (Accepted) → **Order 00095475** (`801WC00000kaGBpYAM`, Activated 2026-06-11, `QuoteId` set, `Type`=blank, `IsRenewal__c`=false, `ContractId=800WC00000SB0FtYAL`) → **successor contract 00069271**.

Asset succession via `AssetContractRelationship`:
- **Original 00069268 (stays Status=Activated, Renewal_Status=Accepted):** PIA-PIA-NRPS-PIAP (perpetual license, end=null, $301.75) · PIA-PIA-**RNM**-PIAMBK (New-Maint, end=null, $62.48) · VM-BSL-RSL-BESECB (sub, **end=2028-06-10** — extended in place +1yr).
- **Successor 00069271 (Status=Activated, Renewal_Status=blank):** PIA-PIA-**RRM**-PIAM (Renewal-Maint, $60.64) · HRM-HRM-RSL-10L50CS (sub, end 2027-06-10, **$0**).

Findings: (1) the **RNM→RRM maintenance swap is real in succession data** (New-Maint asset on the old contract, Renewal-Maint asset on the new) but the amount *dropped* 62.48→60.64 instead of taking COLA (pre-fix). (2) **Subscriptions renew in place** (VM asset's end-date pushed to 2028 on the *original* contract) while **maintenance spawns a new asset on the successor** — inconsistent succession model. (3) **Both contracts remain Activated**, so the account now carries two overlapping active contracts covering the same estate.

---

## 5. Divergences from the Contract-Renewals SDD (`docs/RCA Solution Guide/kb/Fortra-Contract-Renewals-Solution-Design-Doc.md`)

1. **Quote creation.** SDD §7.1/§3: user clicks native "Renew" and the platform builds the Quote. **Actual:** `Fortra_Create_Renewal_Quote` overrides `quotingAI__createRenewalQuote` and calls `initiateRenewal` itself.
2. **Enrichment flow.** SDD names `Fortra_RCA_Renewal_Enhancement` (guard `Quote_Type__c IS NULL`, Product2Id+Account lineage, §12.1/§12.2). **Actual:** superseded by `Fortra_Renewal_Quote_Enhancement` (guard `OriginalActionType='Renew'`, direct-Contract read). **Both are still Active with overlapping entry criteria** → redundant double-processing / duplicate-Opp risk. The SDD's stated lineage (Product2Id+Account) matches neither running flow (one uses AssetAction→AssetActionSource→OrderItem, the other reads the Contract directly).
3. **Audit-chain fields.** SDD §7.2.f/§18: enrichment sets `Original_Quote__c` + `Original_Order_Id__c`. **Actual:** both BLANK on every real renewal quote sampled; only `Renewal_Contract__c` is populated.
4. **Contract succession status (biggest divergence).** SDD §7.2/§14.11: succession sets Contract `Status='Renewed'` AND `Renewal_Status__c='Accepted'`. **Actual:** flow sets **only** `Renewal_Status__c='Accepted'` and deliberately leaves Status alone ("owned by Revenue Cloud"). Result: **0 of 29,452 contracts are Status=Renewed**, though "Renewed" is a valid picklist value. Superseded contracts are indistinguishable from live ones by Status.
5. **Renewal-status lifecycle.** SDD §6 defines Pending→In Progress→Quoted→Accepted→Declined. **Actual:** only **Pending (1,173)** and **Accepted (7)** ever occur; In Progress/Quoted/Declined = 0.
6. **Window is not enforced.** SDD frames the 120-day window as the gate. **Actual:** renewals are created on contracts with `Within_Renewal_Window__c=false`; the monitor only advises.
7. **COLA/maintenance mechanism absent from SDD.** SDD models COLA purely as `COLAUpliftHandler` before-insert. **Actual** working renewals also depend on `RenewalQuoteActionStamp.synthesizeRenewQuoteActions` (RNM→RRM cross-product Renew synthesis) — the entire maintenance-renewal fix is undocumented in this SDD, and the pre-fix data (Trace 3, Trace 2a) shows maintenance renewals silently mispriced without it.
8. **Order.Type/IsRenewal unusable.** Renewal Orders carry blank Type and `IsRenewal__c=false`; any refactor keying succession on Order.Type will break.
9. **Two Opportunities per renewal by design** (Stage-C quote Opp vs Stage-H forecast Opp `Contract.Renewal_Opportunity__c`) — e.g. quote 0Q0WC000003Ibx30AC Opp `006WC00000Rq7ykYAB` ≠ contract's `006WC00000RnhKRYAZ`. Not described as two records in the SDD.

---

## 6. Hand-off points (where control passes — the seams a re-architecture must preserve/replace)

1. Scheduled monitor → `Contract.Renewal_Status__c='Pending'` (advisory flag only).
2. User "Renew" → `Fortra_Create_Renewal_Quote` override → platform `initiateRenewal` → **Quote + QuoteAction(per asset) + QLI(per action, `QLI.QuoteActionId`)**.
3. Quote insert (after-save, 0-min) → **two** enrichment flows → `Quote_Type__c`, `Renewal_Contract__c`, `OpportunityId`.
4. QLI **before-insert** → `QuoteLineItemTrigger` → `COLAUpliftHandler` (3-tier COLA) **and** `RenewalQuoteActionStamp` (synthesize RNM→RRM Renew, keyed `account|Solution_Category__c`).
5. Reprice pass → priced-node commit `NetUnitPrice` (COLA prehook / MyCAP `COLAUpliftPrehook`).
6. Quote→Order (`Order.QuoteId`); Order activation → **new successor Contract** (`Order.ContractId`) via Order-to-Contract mapping flows + Assetize → new/extended Assets.
7. Order Status=Activated (after-save) → `Fortra_Renewal_Contract_Succession` → original `Contract.Renewal_Status__c='Accepted'` (Status untouched).
8. Contract Activated + Auto_Renew (after-save, +15min) → `Fortra_Contract_Create_Renewal_Opportunity` → standing forecast Opp (SC-3500).

**Key source files:** SDD `docs/RCA Solution Guide/kb/Fortra-Contract-Renewals-Solution-Design-Doc.md`; flows under `force-app/main/default/flows/` (`Fortra_Create_Renewal_Quote`, `Fortra_Renewal_Quote_Enhancement`, `Fortra_RCA_Renewal_Enhancement`, `Fortra_Renewal_Contract_Succession`, `Fortra_Contract_Renewal_Window_Monitor`, `Fortra_Contract_Create_Renewal_Opportunity`). COLAUpliftHandler / RenewalQuoteActionStamp / COLAUpliftPrehook are org-only (not in force-app).