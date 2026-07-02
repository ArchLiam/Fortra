# SC-3372 — "Error: Please add the contributing products to the transaction"

> 🗺️ Part of the **[Pricing-V9 incident cluster](../_CLUSTER%20pricing-v9%20%28sc3371%20sc3372%20sc3374%29/ROADMAP.md)** (SC-3371 · SC-3372 · SC-3374) — see the shared ROADMAP for sequencing, ownership, the V9-change gate, and the open decisions (D2/D3) gating this fix. It supersedes the older `Data/sc3372/TICKET_RELATIONSHIPS.md`.

| | |
|---|---|
| **Jira** | SC-3372 (Salesforce-Coastal) |
| **Priority** | Critical |
| **Status** | In Progress — deep RCA complete, no changes deployed |
| **Reporter** | Joe Romo |
| **Assignee** | Liam Jeong |
| **Org** | FortraUAT (UAT-only) |
| **Opened** | 2026-06-09 |
| **Last verified** | 2026-06-09 (multi-agent re-verification vs live FortraUAT) |
| **Labels** | CRM-Revenue-Cloud, LOB-Salesforce-1-UAT · Sprint CRM Sprint 14 |

---

## Symptom

Adding the perpetual license **EFT 8 Continuum** (`GS-GSE-NRPS-E8CP`) to a quote auto-adds a maintenance
line **EFT 8 Continuum-NewMaintenance** (`GS-GSE-RNM-EFT8`). On pricing, the quote throws:

> **We can't price when contributing products are missing. Please add the contributing products to the transaction.**

Both lines show List Price **USD 0.00**. The user *did* have the contributing license in the cart — the
error is **not** about a missing line.

**Live repro:** quote `0Q0WC0000036wHJ0AY` ("Q-Automation Test-2026-06-09", account PAGANI SPA, Draft,
GrandTotal=0, Fortra Price Book). Still stuck as of last check (maintenance line never priced).

> ⚠️ The name "Q-Automation Test-2026-06-09" is reused on **3** quotes on PAGANI SPA — only
> `0Q0WC0000036wHJ0AY` has the EFT8 lines. Filter repro queries by line content, not Name.

## Products involved

| Role | Name | ProductCode | Product2 Id |
|---|---|---|---|
| License (added) | EFT 8 Continuum (Perpetual) | `GS-GSE-NRPS-E8CP` | 01tWC00000DD1DxYAL |
| Maintenance (auto-added) | EFT 8 Continuum-NewMaintenance | `GS-GSE-RNM-EFT8` | 01tWC00000DD1DwYAL |
| (sibling) SaaS subscription | EFT 8 Continuum | `GS-GSE-RSS-E8CS` | 01tWC00000DD1DyYAL |

Repro QLIs: maintenance `0QLWC000003c8vh4AA` (Net*/TotalLineAmount = **NULL** → pricing aborted),
license `0QLWC000003c8vi4AA` (priced to **0**). Maintenance attributes: **MTD=Premier**, Server Type=Non-Production,
Deployment=On Premise, Feature Options=EFT Express ARM.

---

## Root cause (HIGH confidence — re-verified live)

The error is a **native RLM (Revenue Lifecycle Management) managed-package error** — the literal strings
"contributing products" / "We can't price" return **zero** grep hits anywhere in the repo (no Apex, labels,
validation rules, or procedure XML). It is emitted by the pricing engine, not custom code.

**Mechanism:**

1. The maintenance PBE `GS-GSE-RNM-EFT8` is **`IsDerived=True` only in the Fortra Price Book**
   (`01sWC0000022GHFYA2`); the Standard Price Book PBE is `IsDerived=False`. Both are $0. The repro quote
   runs on the Fortra Price Book, so the derived path is necessarily invoked.
2. `IsDerived=True` routes the line through a native pricing-procedure element of
   **`actionType = DerivedPricing`**, present in the **Active v9** of `Rev_Mgmt_Default_Pricing_Procedure`.
   - In v9 the element is named **`DerivedProductsRenewals`** (label "Derived Products - Renewals",
     stepType BusinessKnowledgeModel, `resultIncluded=true`), at **file line 43198**, inside the Active
     block (status `Active` @ line 41165 → `<versionNumber>9` @ line 46675).
   - ⚠️ The literal name **`DerivedPricingDataRetrieval` survives only in the INACTIVE v7 block** (line 32261) —
     it was **renamed, not removed**. Any fix that greps the old name will miss the live element.
3. That element resolves the contributing license via a **`PriceBookEntryDerivedPrice`** config row
   (fields `ProductId`, `ContributingProductId`, both → Product2).
4. **No `PriceBookEntryDerivedPrice` row exists for `GS-GSE-RNM-EFT8`** (nor for any GS-family product).
   With nothing to resolve, the native element **hard-errors** and aborts the line → `NetUnitPrice` stays
   NULL.

### Competing hypotheses — all refuted by live A/B evidence

| Hypothesis | Verdict | Proof |
|---|---|---|
| **(d) Missing `PriceBookEntryDerivedPrice` config** | ✅ **CAUSE** (~90%) | `FIM-FIM-RNM-CCMLSE` (HAS config) prices to NetUnitPrice=462 even at $0 list; `GS-GSE-RNM-EFT8` (0 config) throws |
| (a) $0 list price causes it | ❌ refuted | FIM maintenance at ListPrice=0 prices fine **when config exists** |
| (b) Context-definition desync (`SalesTransactionContextExt_v2`) | ❌ refuted | Wrong error signature (that yields a "Specify the contextDefinitionName…" gack); v2 is present + wired to v9 |
| (c) Contributor missing from the transaction | ❌ refuted | The license line **is** physically on the quote; the gap is the config **metadata row** |

---

## Scope — systemic, not one product

| Metric | Value |
|---|---|
| `PriceBookEntryDerivedPrice` config rows (total) | **172** → families **FIM 168 / RPA 2 / PIA 2** only |
| Distinct products configured | 170 (2 carry 2 contributing rows) |
| `IsDerived=True` maintenance PBEs, Fortra Price Book | **1,889** → **GS = 209** (all 0 config) |
| Distinct IsDerived maintenance products | 1,887 |
| **Products lacking any config** | **1,717 = 91.0%** |

Family breakdown of the 1,889: SM 362, FIM 326, DM 226, **GS 209**, GOA 136, DP 135, BI 112, ES 98, CS 92,
CM 90, IGA 34, RPA 31, NW 24, OS 6, PIA 3, VM 2, IPP 2, HRM 1.

> Every `IsDerived=True` PBE in the Fortra Price Book is a maintenance (RNM/RRM) product (1,889 with the
> filter == 1,889 without). All-pricebook IsDerived totals are larger (3,452 = 1,561 Standard + 1,889 Fortra
> + 2 "Fortra Derived Pricing") — a **different denominator, not drift**.

This is a **regression introduced by the in-flight "Maintenance Derived Pricing" rollout** — the native
element + the `IsDerived` flags were added in the LIVE procedure without backfilling the contributing-product
config (and without removing the native element).

---

## The design already predicted this

`Fortra-Maintenance-Derived-Pricing-Solution-Design` v1.0 (2026-06-06) — first validation step:

> on a known selling-model-mismatched product (FIM-FIM-RRM-TECRM), confirm whether the native Derived Pricing
> Data Retrieval element **hard-errors** (then remove it — the formula does the full job from the stamped
> field) **or returns $0** (then retain it; the formula overwrites). The formula multiplies `Source_List_Price__c`,
> not NetUnitPrice, to avoid multiplicative shrinkage.

SC-3372 is the empirical answer: **it hard-errors.** But the verified evidence below shows the design's
"remove it, the formula does the full job" contingency is **not safe to apply globally** (see Fix options).

### New-solution components already LIVE in UAT (not in force-app source)

- Field `QuoteLineItem.Source_List_Price__c` — Currency(16,2), exists.
- Flow **Stamp Source List Price** (v8, **Active**, RecordBeforeSave) and **Stamp Maintenance Pricing Inputs**
  (v1, **Active**) — both AutoLaunched.
- Active v9 `DerivedPricingFormula` (FormulaBasedPricing, gated `AttributeDefinitionCode='MTD'`):
  `IF(AttributeValue='Premier',0.30, IF('Standard',0.20, IF('Professional',0.20, 0))) * Source_List_Price__c`
  → output `NetUnitPrice` (file line 42894).
- MTD attribute (`Maintenance_Type_Defn`, code MTD) on **184** products; 179 overlap the IsDerived-maintenance
  set, so **1,708 of 1,887 (90.5%) lack MTD** and would price `$0` under the formula path.

---

## Fix options (reordered after deep verification)

### 1. ✅ PREFERRED — backfill `PriceBookEntryDerivedPrice` config (+ fix the $0 list price)
Add one config row: `GS-GSE-RNM-EFT8` → contributing **`GS-GSE-NRPS-E8CP`**, mirroring the working FIM
pattern (`FIM-FIM-RNM-CCMLSE` → `FIM-FIM-NRPS-CCMLIE`). A single config row fixes **both** symptoms at once:
it stops the native element hard-error **and** lets the `Stamp Source List Price` flow resolve the contributor
and populate `Source_List_Price__c` so the formula path can compute. Lowest regression — the 170 currently-working
config-covered products are untouched.
- **Required co-fix:** `GS-GSE-NRPS-E8CP` has **$0 list price in all 10 PBEs** (Fortra+Standard × USD/AUD/CAD/EUR/GBP).
  Without a non-zero license list price, the derived maintenance price computes to `$0` even after config is added.

### 2. Flip `IsDerived=False` on the affected maintenance PBE
Narrowest blast radius — the native element skips the line and the formula path prices it. But it is
**off-design** (bypasses the maintenance-derived-pricing model) and inconsistent with the 1,889-PBE rollout.

### 3. ❌ DEPRIORITIZED — remove the native `DerivedProductsRenewals` element globally
This was the *original* RCA's lead recommendation. Deep verification shows it is **unsafe**:
- **Regression (high):** of the 170 config-covered products, only **3** carry MTD; **167 (FIM/RPA/PIA) have no
  MTD and price ONLY via the native path**. Live proof: `FIM-FIM-RNM-CCMLSE` = `462 = 0.2301 × 2008`
  (`Source_List_Price__c=2008`) — a ratio that matches **no** MTD tier, so it is native-config-derived, not
  formula-derived. Removing the native element would zero these out.
- **Double dependency:** the `Stamp Source List Price` flow queries the *same* `PriceBookEntryDerivedPrice`
  table. With 0 config rows, `Source_List_Price__c` stays NULL → removing the native element converts the
  hard-error into a **silent $0** (`0.30 × null`), not a correct price.

### ⚠️ Do NOT deploy force-app's procedure
`force-app/.../Rev_Mgmt_Default_Pricing_Procedure...xml` is a **stale _V1** (context `SalesTransactionContextExt`,
3 versions, no `Source_List_Price__c`, no new formula elements). Live active is **_V9** (`SalesTransactionContextExt_v2`,
9 versions). Deploying force-app would **revert V9 → V1** and wipe the in-flight formula path. Re-baseline
force-app from live v9 before any source-controlled change.

---

## Auto-add mechanism (corrected)

The maintenance line is **NOT** added by a `ProductRelatedComponent` on the EFT8 license (0 PRCs where it is
parent) nor by a custom flow/Apex. It is **RLM-native configurator co-creation** — both QLIs were created at
the same instant (`2026-06-09T13:02:47`, by Joe Romo) when the perpetual license was added. (The EFT8 license
is itself a bundle *child* of 5 other products via "Bundle to Bundle Component Relationship"; the maintenance
product is a PRC child of unrelated `GS-GSE-RNM-SFTPBN` — neither is the maintenance trigger.)

---

## Open questions (gate the fix)

1. The native-derived ratio `462 = 0.2301 × 2008` for FIM matches **no** MTD formula tier → the **native path
   (not the formula) appears to price config-covered lines**. This puts the design's "formula does the full
   job once `Source_List_Price__c` is stamped" assumption in doubt and is **unverified for the 167 no-MTD
   products** — the load-bearing assumption behind any native-element-removal fix.
2. What exact percentage / contributor mapping should the `GS-GSE-RNM-EFT8` config row carry, and is
   `GS-GSE-NRPS-E8CP` definitely the single intended contributor (vs the sibling `GS-GSE-RSS-E8CS`)? The Stamp
   flow leaves multi-contributor lines NULL for manual review.
3. Has the native hard-error-vs-$0 behavior been validated per the design's first-validation-step product
   (`FIM-FIM-RRM-TECRM`)?
4. Tier coverage hole: the live formula handles only Premier/Standard/Professional. `Maintenance_Rate__mdt`
   defines 7 tiers (Basic 0.15, Expert 0.35, Express 0.30, Premier 0.30, Premium 0.24, Professional 0.20,
   Standard 0.20) and the MTD picklist has 8 values incl. "platinum"/"Express" → any line on an unhandled tier
   hits the trailing `IF(…,0)` and prices **$0 even with MTD + a populated `Source_List_Price__c`**.

---

## Recommended next step

Backfill **one** `PriceBookEntryDerivedPrice` row (`GS-GSE-RNM-EFT8` → `GS-GSE-NRPS-E8CP`, mirroring the FIM
pattern) **and** set a non-zero list price on `GS-GSE-NRPS-E8CP`, then reprice quote `0Q0WC0000036wHJ0AY`.

⚠️ This is **live DML in Marc DeBrey's in-flight pricing area**, and the contributor mapping/percentage is
unconfirmed (open question #1/#2). Per standing rule, get **fresh explicit DML/deploy authorization** and
**confirm the mapping with Marc** before any write.

---

## Related tickets / notes

- **SC-3374** — same June-9 QA sweep, same unstable v9 procedure; a service line prices with a phantom
  net-vs-line inconsistency that Workday then rejects. (See `TICKET_RELATIONSHIPS.md`.)
- **Reprice contextDef gack** — other live-edit symptom from the same procedure work (different error).
- **SC-3360 / SC-3345** — the $0-net family that the secondary `GS-GSE-NRPS-E8CP` $0 list price feeds into.

## Evidence / artifacts

- `Data/sc3372/RCA_v2.md` — full verified deep-RCA (this README is the ticket-folder copy).
- `Data/sc3372/RCA.md` — original (morning) RCA.
- `Data/sc3372/TICKET_RELATIONSHIPS.md` — SC-3372 / SC-3374 cluster.
- `Data/sc3372/live_recheck/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
  — fresh live-v9 retrieve (byte-identical to the morning `live_0609` snapshot, md5 `d1a71491b36203ed9dfb6aee0707c086`).

Key queries (all against FortraUAT, default org):
```bash
# Maintenance PBE: IsDerived only in Fortra PB, $0
sf data query --target-org FortraUAT -q "SELECT Pricebook2.Name,CurrencyIsoCode,UnitPrice,IsDerived FROM PricebookEntry WHERE Product2Id='01tWC00000DD1DwYAL'"
# Zero config rows for the product / any GS
sf data query --target-org FortraUAT -q "SELECT COUNT() FROM PriceBookEntryDerivedPrice WHERE PricebookEntry.Product2.ProductCode LIKE 'GS-%'"   # 0
sf data query --target-org FortraUAT -q "SELECT COUNT() FROM PriceBookEntryDerivedPrice"   # 172
# Active procedure version
sf data query --use-tooling-api --target-org FortraUAT -q "SELECT VersionNumber,Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure'"   # v9 Active
# Repro quote still stuck
sf data query --target-org FortraUAT -q "SELECT Id,Product2.ProductCode,ListPrice,UnitPrice,NetUnitPrice,Source_List_Price__c FROM QuoteLineItem WHERE QuoteId='0Q0WC0000036wHJ0AY'"
```
