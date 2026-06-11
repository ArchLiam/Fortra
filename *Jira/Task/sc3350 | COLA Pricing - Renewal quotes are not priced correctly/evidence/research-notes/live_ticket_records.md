# SC-3350 — Live/Ticket Testing Records Re-Verification (fresh)

**Stream:** Live/Ticket testing records
**Date run:** 2026-06-10 (research session, read-only)
**Org:** FortraUAT (`00DWC000006eUFF2A2`, `https://fortra--uat.sandbox.my.salesforce.com`, API v67.0)
**User:** liam.jeong.c@fortra.com.uat
**Grounding brief:** `/Users/liamjeong/Documents/Code/Fortra/Data/sc3354/SC-3354_Research_Brief.md` (08:13 UTC) — treated as possibly stale.
**Caveat to flag up front:** Marc DeBrey re-edited every COLA class LATER today (AssetContractQueryHelper 14:00Z, QLDescriptionGeneratorPrehook 14:41Z, COLAUpliftHandler 16:29Z, COLAUpliftPrehook+COLAUpliftTest 16:51Z). **None of the six cited ticket records were re-touched after those edits** — they all carry LastModifiedDate 2026-06-07 (see §5). So this stream verifies the *frozen* state of the cited records; it is NOT a re-run against today's code.

---

## 0. TL;DR answers to the 4 stream questions

1. **Does the audit renewal price correctly now?** The stored audit quote `0Q0WC000003671t0AA` STILL shows correct per-line COLA `UnitPrice` (Abstract 4697.946, beSECURE 929.25) and correct audit fields (Pre_COLA, %, Source, SolutionCat). **BUT this is the same frozen 2026-06-07 record — it was NOT regenerated after Marc's today-edits.** A true "now" answer needs a *new* renewal (a DML op, out of read-only scope). Also note: the audit quote's price rollups are WRONG (Subtotal=46/0=list, GrandTotal=0) — only `UnitPrice` is COLA'd; see §2/§3. Confidence: HIGH that the stored values are unchanged; the "prices correctly under today's code" claim is UNKNOWN/needs a fresh renewal trace.
2. **Is Description STILL null (defect #2)?** YES — `Description` is null on **all 6 QLIs** across all three quotes. Defect #2 reproduces. Confidence: HIGH.
3. **What does the Subtotal renewal look like?** The record the task labels "Renewal-Subtotal" = `0Q0WC00000366tp0AA` (00780885), header Subtotal **5627.196**. Its two lines have correct COLA `UnitPrice` AND their line-level `Subtotal` rolled to the COLA price (4697.946 + 929.25) — but the *audit* fields (Pre_COLA, Source, SolutionCat) are **NULL** on those lines. So 366tp and 3671t are mirror-image partial failures (see §3). Confidence: HIGH.
4. **Confirm the asset prices.** Abstract `02iWC000008BTEzYAO` Price=**4356** ✓; beSECURE `02iWC000008BTF0YAO` Price=**875** ✓. Both Installed, both on Account `001WC00000kJGcuYAG`. Confidence: HIGH.

**Nir's expected math — verified to the penny on the audit quote:**
- Abstract 4356 × 1.0785 = **4697.946** = audit line `0QLWC000003bJOY4A2`.UnitPrice ✓
- beSECURE 875 × 1.062 = **929.25** = audit line `0QLWC000003bJOX4A2`.UnitPrice ✓
- Sum 5627.196 = header Subtotal of `0Q0WC00000366tp0AA` ✓ (and = sum of audit-quote line UnitPrices)

---

## 1. Record map (task labels vs. reality)

The task's labels and the live data are partly crossed. Authoritative mapping:

| Task label | Quote Id | QuoteNumber | Name | Status | Header Subtotal | Header GrandTotal |
|---|---|---|---|---|---|---|
| Original Quote | `0Q0WC00000366Yr0AI` | 00780884 | "Nir COLA Test Quote 2026-06-07 07:43" | Accepted | 5231 | 5231 |
| **Renewal-Subtotal** | `0Q0WC00000366tp0AA` | 00780885 | "Renewal Quote" | Draft | **5627.196** | 0 |
| **Renewal-COLA-audit** | `0Q0WC000003671t0AA` | 00780886 | "Renewal Quote" | Draft | **46** | 0 |

Note the header-Subtotal swap vs. intuition: the quote the task calls the "audit" quote (3671t) has header Subtotal **46** (list), and the quote called "Subtotal" (366tp) has Subtotal **5627.196** (COLA'd). Both have **GrandTotal 0** (no completed pricing pass). SOQL:
`SELECT Id,Name,QuoteNumber,Status,Subtotal,GrandTotal,TotalPrice,CreatedDate,LastModifiedDate FROM Quote WHERE Id IN (...)`

---

## 2. The two Assets (defect-#1 base prices) — CONFIRMED

SOQL: `SELECT Id,Name,Product2.Name,Product2Id,Price,Quantity,Status,AccountId,CreatedDate FROM Asset WHERE Id IN ('02iWC000008BTEzYAO','02iWC000008BTF0YAO')`

| Asset Id | Name | Product2Id | Price | Qty | Status | Account |
|---|---|---|---|---|---|---|
| `02iWC000008BTEzYAO` | Abstract | `01tWC00000DD11GYAT` | **4356** | 1 | Installed | 001WC00000kJGcuYAG |
| `02iWC000008BTF0YAO` | beSECURE - Cloud-Based | `01tWC00000DD10zYAD` | **875** | 1 | Installed | 001WC00000kJGcuYAG |

- (Asset object has **no** `ContractId` field; the Contract `800WC00000RyqPBYAZ` is referenced via the COLA contract-override path, not a direct Asset FK. Contract has no override set — see §4 — so CMDT lookup is the correct/expected source.)
- These two Asset prices (4356/875) ARE the `Pre_COLA_Price__c` base used by the audit quote (matches exactly). They are NOT the Product2 catalog `ListPrice` (46/0) — see §6.

---

## 3. The six QuoteLineItems — full COLA field dump

SOQL (core):
```
SELECT Id, QuoteId, Product2.Name, Product2Id, ListPrice, UnitPrice, Quantity,
       Pre_COLA_Price__c, COLA_Uplift_Percent__c, COLA_Source__c, COLACalculatedPrice__c,
       COLA_Solution_Category__c, Default_COLA_Uplift_Percent__c, Is_COLA_Overridden__c,
       COLA_Applied_Date__c, COLA_Modified_Date__c, Description, CreatedDate, LastModifiedDate
FROM QuoteLineItem WHERE QuoteId IN ('0Q0WC00000366Yr0AI','0Q0WC000003671t0AA','0Q0WC00000366tp0AA')
```
Plus a second pass for line-total fields: `ListPrice, UnitPrice, Quantity, TotalPrice, NetUnitPrice, NetTotalPrice, Subtotal`.

### 3a. Original quote `0Q0WC00000366Yr0AI` (baseline, pre-renewal)
| QLI Id | Product | List | Unit | line Subtotal | COLA% | Source | Desc |
|---|---|---|---|---|---|---|---|
| `0QLWC000003bIyj4AE` | Abstract | 46 | 46 | **4356** | null | null | null |
| `0QLWC000003bIvV4AU` | beSECURE | 0 | 0 | **875** | null | null | null |

No COLA fields (correct — it's the source quote, not a renewal). Crucially the **line Subtotal = the negotiated price (4356/875)** that became Asset.Price, even though Unit/List = 46/0. This is the provenance of the "prior price" the renewal must uplift.

### 3b. "Renewal-Subtotal" `0Q0WC00000366tp0AA` (header Subtotal 5627.196)
| QLI Id | Product | List | Unit | line Subtotal | NetUnit | NetTotal | TotalPrice | COLA% | Pre_COLA | Source | SolnCat | COLA_Applied |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `0QLWC000003bJGT4A2` | Abstract | 46 | **4697.946** | **4697.946** | 0 | 0 | 0 | 7.85 | **null** | **null** | **null** | null |
| `0QLWC000003bJGU4A2` | beSECURE | 0 | **929.25** | **929.25** | 0 | 0 | 0 | 6.2 | **null** | **null** | **null** | null |

UnitPrice + COLA% correct; **line Subtotal rolled to the COLA price** → header 5627.196. BUT the audit-trail COLA fields (`Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `Default_COLA_Uplift_Percent__c`, `COLA_Applied_Date__c`) are all **NULL**. So COLA% + Unit landed but the provenance fields did not. `Description` null.

### 3c. "Renewal-COLA-audit" `0Q0WC000003671t0AA` (header Subtotal 46)
| QLI Id | Product | List | Unit | line Subtotal | NetUnit | NetTotal | TotalPrice | COLA% | Pre_COLA | Source | SolnCat | Default% | COLA_Applied |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `0QLWC000003bJOY4A2` | Abstract | 46 | **4697.946** | **46** | 0 | 0 | 0 | 7.85 | **4356** | **CMDT Lookup** | **Business Intelligence** | 7.85 | 2026-06-07T15:12:46Z |
| `0QLWC000003bJOX4A2` | beSECURE | 0 | **929.25** | **0** | 0 | 0 | 0 | 6.2 | **875** | **CMDT Lookup** | **Vulnerability Management** | 6.2 | 2026-06-07T15:12:46Z |

UnitPrice + ALL audit fields correct (Pre_COLA=Asset.Price; CMDT Lookup source; per-solution % matches CMDT rate table: Business Intelligence 7.85, Vulnerability Management 6.2). **BUT the price rollups are WRONG**: line `Subtotal` = ListPrice (46/0, not the COLA'd UnitPrice), `NetUnitPrice`=`NetTotalPrice`=`TotalPrice`=0 → header Subtotal 46, GrandTotal 0.

### 3d. The mirror-image failure (key insight)
Same two Assets, same expected math, two renewal quotes generated minutes apart, **two DIFFERENT partial-failure shapes**:
- **3671t (audit):** audit fields ✅, price rollup ❌ (Subtotal=list, Net/Total=0).
- **366tp (subtotal):** price rollup ✅ (Subtotal=COLA), audit fields ❌ (Pre_COLA/Source/SolnCat null).

Neither is fully correct. Both share `NetUnitPrice=NetTotalPrice=TotalPrice=0` and header `GrandTotal=0`. That zero-Net/zero-Total + GrandTotal 0 is the live fingerprint of **"no full pricing-procedure reprice ran on the renewal"** — exactly the brief's central thesis (§0/§1 of the brief). The trigger stamped `UnitPrice` (and, race-dependent, some audit fields); the procedure's Net/Total/description writes never fired.

---

## 4. Contract `800WC00000RyqPBYAZ` — CONFIRMED, no override

SOQL: `SELECT Id,ContractNumber,Status,AccountId,StartDate,EndDate,COLA_Override_Percent__c,COLA_Override_Persist_Until__c,CreatedDate FROM Contract WHERE Id='800WC00000RyqPBYAZ'`

| Field | Value |
|---|---|
| ContractNumber | 00069191 |
| Status | Activated |
| Account | 001WC00000kJGcuYAG |
| StartDate / EndDate | 2026-06-07 / 2027-06-06 |
| COLA_Override_Percent__c | **null** |
| COLA_Override_Persist_Until__c | **null** |

→ No contract-level COLA override, so the expected `COLA_Source__c` is **CMDT Lookup** (which is exactly what the audit quote shows). The AssetContractQueryHelper multi-asset bug (brief B1) is NOT exercised here (no override).

---

## 5. STALENESS / timing — critical delta flag

| Record | CreatedDate | LastModifiedDate |
|---|---|---|
| Quote 366Yr (orig) | 2026-06-07T14:43:31Z | 2026-06-07T15:01:14Z |
| Quote 366tp (subtotal) | 2026-06-07T15:04:45Z | 2026-06-07T15:10:43Z |
| Quote 3671t (audit) | 2026-06-07T15:12:44Z | 2026-06-07T15:12:48Z |
| All 6 QLIs | 2026-06-07 | 2026-06-07 |

- **All cited records last modified 2026-06-07** — three days before today, and well before Marc's today-edits (14:00–16:51Z). They reflect the **2026-06-07 code**, NOT today's reworked classes. The brief's 08:13 reading of these same records is therefore identical to mine (nothing changed the records between 08:13 and now).
- **No new test quotes** exist on Account `001WC00000kJGcuYAG` since 2026-06-08 (SOQL: `... WHERE AccountId='001WC00000kJGcuYAG' AND CreatedDate>=2026-06-08T00:00:00Z` → 0 rows). So Marc's today-edits have **not been validated against a fresh renewal** for these assets. Any "does it work now" assertion requires generating a new renewal = DML, out of scope.

**QuoteActions** (provenance of the renewal + timing race):
SOQL: `SELECT Id,QuoteId,Type,Subtype,SourceAssetId,CreatedDate,LastModifiedDate FROM QuoteAction WHERE QuoteId IN (...)`
| Quote | QuoteAction | Type | SourceAsset | Created |
|---|---|---|---|---|
| 366tp | `7ocWC00000tYaKjYAK` | Renew | `02iWC000008BTEzYAO` (Abstract) | 2026-06-07T15:04:46Z |
| 366tp | `7ocWC00000tYaKkYAK` | Renew | `02iWC000008BTF0YAO` (beSECURE) | 2026-06-07T15:04:46Z |
| 3671t | `7ocWC00000tYaMLYA0` | Renew | `02iWC000008BTEzYAO` (Abstract) | 2026-06-07T15:12:46Z |
| 3671t | `7ocWC00000tYaMMYA0` | Renew | `02iWC000008BTF0YAO` (beSECURE) | 2026-06-07T15:12:46Z |

For the **audit** quote (3671t), the Renew QuoteActions were created **15:12:46 — the same second as the QLIs and the `COLA_Applied_Date__c`**. That co-timing is *why* `handleBeforeInsert` succeeded in stamping the full audit-field set on 3671t (QuoteActionId was in-context). This is consistent with the brief's race mechanism (brief §1: the repro line's QuoteAction landed ~35s late and stamping failed). Here the race fell the *other* way for the audit fields, yet the Net/Total rollups still didn't populate on either quote.

---

## 6. ListPrice mystery resolved (don't trip on it)
`ListPrice` on these QLIs (Abstract 46, beSECURE 0) is the **Product2 catalog price**, which is essentially placeholder/near-zero for these SKUs. The real prior/negotiated price is the **Asset.Price (4356 / 875)**, captured as line `Subtotal` on the original quote and as `Pre_COLA_Price__c` on the audit renewal. So "renewal priced at plain list price" (defect #1's headline) more precisely means "priced at the meaningless catalog ListPrice / rolled-up to it," not at the prior transacted price. The audit quote proves the *trigger* correctly bases COLA on Asset.Price; the failure is that the **Net/Total/Subtotal rollups** don't pick up the COLA'd UnitPrice (no reprice).

---

## 7. Out-year / Final-Year fields — DELTA vs brief

- `COLA_Outyear_Uplift_Percent__c` (Number(16,2)): **null on all 4 renewal QLIs** → out-year still inert (consistent with brief B3).
- `Final_Year_COLA_Calculated_Price__c`: appears in tooling `FieldDefinition` for QuoteLineItem as **`Formula (Currency)`, IsCalculated=true**, BUT **`SELECT`-ing it throws `INVALID_FIELD` ("No such column")** on the data API.
  - **Interpretation (MEDIUM confidence):** a valid, active formula field is always SOQL-selectable; a formula in a *compile-error* state still lists in FieldDefinition but throws on query. So the out-year formula field appears to be **currently broken/un-queryable in UAT**, which is a sharper finding than the brief's B4 ("formula logic is wrong but computes a value"). Right now it can't even be selected. Needs a metadata/Setup confirm to be certain it's an error state vs. a permissions quirk (I queried as an admin-level integration user, so FLS is unlikely).

---

## 8. Confidence + what's still unknown
- HIGH: asset prices (4356/875), contract no-override, audit-quote per-line UnitPrice + audit fields correct to the penny, Description null on all 6, the mirror-image partial-failure pattern, all records frozen at 2026-06-07.
- MEDIUM: Final_Year formula field is in a broken/un-queryable state (inferred from INVALID_FIELD on a calculated field).
- UNKNOWN / needs-DML-trace (out of read-only scope): whether a renewal generated *today*, under Marc's reworked classes, prices correctly end-to-end (Net/Total/GrandTotal populated, Description generated). The cited records cannot answer this — they predate the edits.

## 9. Exact SOQL used (for reproduction)
1. `SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='QuoteLineItem' AND QualifiedApiName LIKE '%COLA%'` (--use-tooling-api) → field inventory.
2. Quote headers (Id list).
3. QLI core COLA dump (Id list of 3 quotes).
4. QLI total fields (ListPrice/UnitPrice/Qty/TotalPrice/NetUnitPrice/NetTotalPrice/Subtotal).
5. Asset query (2 Ids).
6. Contract query (1 Id).
7. QuoteAction query (3 quote Ids).
8. `... QuoteLineItem ... GROUP BY QuoteId` line counts.
9. `Quote WHERE AccountId='001WC00000kJGcuYAG' AND CreatedDate>=2026-06-08` → 0 new quotes.
10. FieldDefinition DataType/IsCalculated for the Final_Year + outyear fields (--use-tooling-api).
