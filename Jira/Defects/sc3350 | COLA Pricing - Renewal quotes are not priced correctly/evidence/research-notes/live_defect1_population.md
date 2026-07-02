# SC-3350 — Defect #1 (renewal priced at list): live repro + population health

**Date:** 2026-06-10 (research run, post Marc-DeBrey same-day edits). **Org:** FortraUAT. **Mode:** read-only.
**Prior brief under verification:** `/Users/liamjeong/Documents/Code/Fortra/Data/sc3354/SC-3354_Research_Brief.md` (written 08:13 UTC).

> All COLA classes were re-edited by **Marc DeBrey** today AFTER the brief was written, confirmed via Tooling API:
> AssetContractQueryHelper 14:00:37Z, QLDescriptionGeneratorPrehook 14:41:27Z, COLAUpliftHandler 16:29:57Z,
> COLAUpliftPrehook 16:51:20Z, COLAUpliftTest 16:51:20Z. (LastModifiedBy=Marc DeBrey for all five.)
> SOQL (tooling): `SELECT Name, LastModifiedDate, LastModifiedBy.Name, ApiVersion FROM ApexClass WHERE Name IN (...)`

---

## 1. Repro line 0QLWC000003bHpl4AE — STILL BROKEN (unchanged since insert)

SOQL:
```
SELECT Id, ListPrice, UnitPrice, COLA_Uplift_Percent__c, Pre_COLA_Price__c, COLA_Source__c,
       COLACalculatedPrice__c, Product2Id, QuoteId, CreatedDate, LastModifiedDate
FROM QuoteLineItem WHERE Id='0QLWC000003bHpl4AE'
```
Result (live now):
| field | value |
|---|---|
| ListPrice | 10000 |
| UnitPrice | **10000** (== ListPrice; expected 10500) |
| COLA_Uplift_Percent__c | **null** |
| Pre_COLA_Price__c | null |
| COLA_Source__c | null |
| COLACalculatedPrice__c | null |
| CreatedDate | 2026-06-07T13:31:24Z |
| LastModifiedDate | **2026-06-07T13:31:24Z** (identical to CreatedDate — never re-touched) |

- Quote `0Q0WC00000365Uj0AI`. Product2 `01tWC00000DD11SYAT` ("Additional Threat Assessments", `Solution_Category__c='Brand Protection'`).
- QuoteAction `7ocWC00000tYaFtYAK`: **Type='Renew'**, CreatedDate 13:31:23Z, **LastModifiedDate 13:31:58Z** → finalized ~34s AFTER the QLI insert (13:31:24Z).
- Source Asset `02iWC000007DXlJYAW`: Price=10000 (NON-null), Product2 `01tWC00000DD11SYAT`.
- Active CMDT rule: `COLA_Uplift_Rules__mdt` Brand Protection → `Default_Uplift_Percent__c=5`, `Is_Active__c=true`, no date gating. So expected = 10000 × 1.05 = **10500**.

**Verdict: NOT fixed.** Marc's same-day class edits did NOT retroactively repair this line (expected — Apex edits don't re-run on old records without a reprice/DML). LastModifiedDate proves zero post-insert touches.

**Confirmed failure mode = QuoteActionId before-insert race.** `COLAUpliftHandler.handleBeforeInsert` (live, 16:29Z body):
- L23-27 collects `qli.QuoteActionId` off `Trigger.new`;
- L29-31 `if (quoteActionIds.isEmpty()) return;` — bails when the FK isn't on the row yet.
The QuoteAction was last-modified 34s after the QLI insert → `QuoteActionId` was not in `Trigger.new` at before-insert → handler bailed → line kept list price. The FK is queryable NOW (`7ocWC00000tYaFtYAK`) but nothing re-ran to stamp it. `handleBeforeUpdate` cannot self-heal: its recalc path requires `Pre_COLA_Price__c != null` (L161), which is null on a never-stamped line.

(Local copy `/Data/sc3350/research/live_today/COLAUpliftHandler.cls` verified BYTE-IDENTICAL to current org body — diff of fresh tooling `Body` pull = 0 lines. Safe to cite line numbers from it.)

---

## 2. Population health — DEFENSIBLE COUNTS (corrects the brief)

### 2a. The true renewal-line universe is TINY (brief's "1.22M renewal lines" is wrong)
- Org-wide `QuoteLineItem` total: **1,223,243** (`SELECT COUNT() FROM QuoteLineItem`). → This is the number the brief mislabeled "1,222,003 renewal lines." It is the WHOLE table, not renewals.
- QLIs with a non-null `QuoteActionId` org-wide: **115** (`WHERE QuoteActionId != null`).
- **QLIs whose own QuoteAction is Type='Renew' org-wide: 43** (`WHERE QuoteAction.Type='Renew'`). ← the real renewal-line population.
- Renew QuoteActions: **45**; distinct renewal Quotes: **32** (`SELECT COUNT_DISTINCT(QuoteId) FROM QuoteAction WHERE Type='Renew'`).

### 2b. Denominator definition
Two defensible denominators; I report both because they diverge:

**(A) Lines on a renewal quote** = QLIs where `QuoteId IN (the 32 quotes that have ANY Renew QuoteAction)`. Count = **52**.
  - Breakdown by the LINE's OWN `QuoteAction.Type`: **Renew=43, No Change=2, null/no-QuoteAction=7**.
  - The 2 No-Change and 7 null-QA lines are NOT renewal lines and are correctly not COLA'd. Including them inflates the defect count.

**(B) True renewal lines** = QLIs where the LINE's own `QuoteAction.Type='Renew'`. Count = **43**. ← use this as the defect-#1 denominator.

SOQL for (A): get the 32 quote Ids from `QuoteAction WHERE Type='Renew'`, then
`SELECT ... FROM QuoteLineItem WHERE QuoteId IN (<32 ids>)`. (Field-to-field `UnitPrice = ListPrice` is NOT allowed in SOQL — confirmed it errors at the comparison column — so "at-list" is computed client-side.)

### 2c. Defect-#1 count on denominator (B) = true renewal lines (43)
| bucket | count | note |
|---|---|---|
| COLA stamped (`COLA_Uplift_Percent__c != null`) | **40** | priced (mostly correctly, see 2e) |
| COLA null | **3** | |
| └ COLA-null AND `UnitPrice==ListPrice` (**clean defect-#1 repro**) | **2** | `0QLWC000003bHpl4AE`, `0QLWC0000031Lgb4AE` |
| └ COLA-null AND `UnitPrice != ListPrice` | **1** | `0QLWC000002Y57N4AS` (Unit=0, List=6875 — zero-price anomaly, separate) |

→ **Population defect rate on true renewal lines: 2 clean at-list / 43 = ~4.7%** (3/43 = 7% if you count the zero-price line). NOT a majority — the trigger stamps most renewal lines; the defect is the minority race/edge case.

### 2d. Two DISTINCT defect-#1 failure modes (not one)
1. **QuoteActionId before-insert race** — `0QLWC000003bHpl4AE`. QA present & valid now, Price non-null, active rule exists; handler bailed because FK was null at before-insert. (Canonical repro.)
2. **Source Asset Price = null** — `0QLWC0000031Lgb4AE`. QuoteAction.Type='Renew', but `QuoteAction.SourceAsset.Price = null` (SolCat='Email Security'). Handler bails at L291-293 `if (assetPrice == null) continue;`. List=Unit=560.88. This is a SEPARATE bug the brief did not isolate.

### 2e. Stamped-line correctness spot-check (of the 40 stamped)
Computed `UnitPrice == Pre_COLA_Price__c × (1 + pct/100)` client-side over all 41 COLA-stamped renewal-quote lines:
- matches: **30**, mismatches: **4**, no `Pre_COLA_Price__c`: 7.
- 4 mismatches (`0QLWC000002YTxh4AG`, `0QLWC0000032Grl4AE`, `0QLWC0000032Grn4AE`, `0QLWC0000034WxG4AU`) — UnitPrice diverges from the COLA formula; several show actual=2400 flat (looks like a later reprice/regional/manual override clobbering the COLA'd price). Worth a waterfall trace but OUT of scope for the at-list defect. (`COLA_Source__c` on these = Contract Override / CMDT Lookup / MyCAP Default.)

---

## 3. The 13-in-insert / 21-on-update split — RE-DERIVED

Method: for every COLA-stamped renewal-quote line, compute `LastModifiedDate − CreatedDate`. A line stamped IN the before-insert pass has delta ≈ 0s; a line stamped later (write-back/update) has delta > 0s.

Result over **41 stamped lines** (denominator A, all COLA-stamped on the 32 quotes):
- **in-insert (delta ≤ 1s … ≤ 10s, stable): 13**
- **on-update (delta > 1s): 28**

→ The brief's **"13 in-insert" is EXACTLY reproduced and stable** across thresholds 1/2/5/10s. The on-update side moved **21 → 28** because **7 more renewal lines were created since 08:13Z** (denominator grew 34 → 41). So the split is now **13 / 28 of 41**, vs the brief's 13 / 21 of 34. The 13-in-insert core is the durable fingerprint of the unreliable before-insert path; most lines are rescued by a later UPDATE write-back.

Caveat: `LastModifiedDate` reflects ANY later field change, so large deltas (days) just mean unrelated later edits; only the **delta≈0** bucket (=13) is a clean "stamped at insert" signal. The complement (28) is "not stamped at insert" — a superset of "stamped on update."

Per-line deltas captured in `/tmp/renewal_qlis.json` analysis; 13 lines at delta=0s:
`0QLWC000002Ryuz4AC, 0QLWC000002UYeD/E/F/G/H/I4AW (6), 0QLWC000003aHv34AE, 0QLWC000003bGgp4AE, 0QLWC000003bGgr4AE, 0QLWC000003bIAj4AM, 0QLWC000003bJOX4A2, 0QLWC000003bJOY4A2`.

---

## 4. KEY NEW FINDING — within-transaction partial stamp is product/category-driven, not pure timing

Quote `0Q0WC00000364Lm0AI` (all 4 QLIs created 2026-06-07T13:46:42, same second):
| QLI | Product2 | SolCat | own QA.Type | COLA | result |
|---|---|---|---|---|---|
| 0QLWC000003bGgp4AE | 01tWC00000DD14lYAD (Automate Professional) | Robotic Process Automation | **Renew** | 9.85% CMDT, delta 0s | correctly COLA'd → 2674.85 |
| 0QLWC000003bGgr4AE | 01tWC00000DD14lYAD | Robotic Process Automation | **Renew** | 9.85% CMDT, delta 0s | correctly COLA'd |
| 0QLWC000003bGgo4AE | 01tWC00000DD11SYAT (Additional Threat Assessments) | Brand Protection | **No Change** | null | NOT COLA'd — **CORRECT** (No Change action) |
| 0QLWC000003bGgq4AE | 01tWC00000DD11SYAT | Brand Protection | **No Change** | null | NOT COLA'd — **CORRECT** (No Change action) |

→ The two unstamped lines on this quote are linked to `QuoteAction.Type='No Change'`, which the handler correctly excludes (L39 `AND Type='Renew'`). They are **false positives** if you count "renewal-quote lines at list" naively. This is exactly why denominator (B) (line's own QA.Type='Renew') is the correct defect basis. It also shows the canonical repro (`0QLWC000003bHpl4AE`, same asset `02iWC000007DXlJYAW`, but on a genuine **Renew** QuoteAction in quote 365Uj) IS a real defect, while its No-Change twin is not.

---

## 5. The 7 null-QuoteActionId lines (separate sub-population)
`0QLWC0000031OY24AM, 0QLWC0000034MJa4AM, 0QLWC0000035KIv4AM, 0QLWC0000035JbO4AU, 0QLWC0000035KNl4AM, 0QLWC000003cMDt4AM, 0QLWC000003cMDu4AM`
- All have `QuoteActionId = null` (no QuoteAction at all). Sit on renewal quotes but are not tied to a Renew action / source asset → handler's before-insert path can never reach them (bails L29).
- `0QLWC000003cMDu4AM` DID get pct=7.85 stamped (on a later update, delta 22s) despite null QAId — proves the update write-back path can stamp lines the insert path can't.
- Likely manually-added lines, not renewal-generated; probably NOT in scope for defect-#1, but flag for Marc.

---

## 6. Deltas vs the 08:13Z brief
1. **"0 of 1,222,003 renewal lines"** → that 1.22M is the WHOLE QLI table (now 1,223,243), NOT renewals. True renewal-line universe (QuoteAction.Type='Renew') = **43 org-wide**. The brief's renewal-line denominator is off by ~5 orders of magnitude.
2. **Defect-#1 at-list count** is **2 clean repros / 43 true renewal lines (~4.7%)**, not a wholesale failure. A naive quote-level join overcounts to 8 because it sweeps in No-Change (2) and null-QA (7) lines.
3. **13-in-insert reproduced exactly; on-update 21→28** (denominator 34→41) because 7 renewal lines were created after the brief.
4. **NEW: a second, distinct defect-#1 failure mode** = `SourceAsset.Price = null` (`0QLWC0000031Lgb4AE`, handler L291 bail), separate from the QuoteActionId race.
5. **NEW: within-transaction partial stamp is governed by `QuoteAction.Type` (Renew vs No Change), not timing** — the unstamped twins on quote 364Lm are correct No-Change behavior.
6. **Repro line is genuinely unchanged** (LastModifiedDate==CreatedDate); Marc's same-day edits did not touch existing data.
7. **SOQL field-to-field comparison (`UnitPrice = ListPrice`) is rejected** by the platform — must compute at-list client-side. (Affects how anyone re-runs this query.)

## 6b. Null SourceAsset.Price prevalence (failure mode #2)
`SELECT Id, QuoteAction.SourceAsset.Price, COLA_Uplift_Percent__c, UnitPrice, ListPrice FROM QuoteLineItem WHERE QuoteAction.Type='Renew'` → of **43** renew lines, **3** have null `SourceAsset.Price`:
- `0QLWC000002Y57N4AS` — Unit=0, List=6875, COLA null (zero-price anomaly).
- `0QLWC0000031Lgb4AE` — Unit=List=560.88, COLA null (**at-list repro, mode #2**).
- `0QLWC000002wtxR4AQ` — pct=3, Unit=15450 (got COLA'd anyway via a later override/update despite null asset price).
→ Null source price correlates with the bail but is not deterministic (1 of 3 was rescued by an update-path override). Both at-list clean repros (`...bHpl4AE` mode #1, `...1Lgb4AE` mode #2) are accounted for.

## 7. Open / needs-trace
- Why do 4 stamped lines have UnitPrice ≠ COLA formula (several flat 2400)? Later reprice / regional / manual clobber — needs waterfall trace.
- Are the 7 null-QuoteActionId lines in scope for SC-3350, or out-of-band manual adds?
- `SourceAsset.Price = null` (mode #2): is that a data-quality issue upstream or a renewal-generation gap? Confirm how many of the 43 renew lines have null source-asset price (here only 1 surfaced).
- Confirm against Marc whether the 16:29Z handler edit changed before-insert behavior at all (it still bails on null QuoteActionId — the race is NOT fixed in code).

## Queries used (key ones)
- Tooling class timestamps: `SELECT Name, LastModifiedDate, LastModifiedBy.Name, ApiVersion FROM ApexClass WHERE Name IN ('COLAUpliftHandler','COLAUpliftPrehook','COLAUpliftTest','AssetContractQueryHelper','QLDescriptionGeneratorPrehook')`
- Repro line: see §1.
- `SELECT COUNT() FROM QuoteAction WHERE Type='Renew'` → 45
- `SELECT COUNT_DISTINCT(QuoteId) FROM QuoteAction WHERE Type='Renew'` → 32
- `SELECT QuoteId FROM QuoteAction WHERE Type='Renew'` → 32 distinct ids → IN-list
- `SELECT Id,QuoteId,QuoteActionId,QuoteAction.Type,ListPrice,UnitPrice,COLA_Uplift_Percent__c,COLA_Source__c,Pre_COLA_Price__c,COLACalculatedPrice__c,CreatedDate,LastModifiedDate,Product2Id FROM QuoteLineItem WHERE QuoteId IN (<32>)` → 52 rows (analyzed client-side)
- `SELECT COUNT() FROM QuoteLineItem` → 1,223,243
- `SELECT COUNT() FROM QuoteLineItem WHERE QuoteAction.Type='Renew'` → 43
- `SELECT ... FROM Product2 WHERE Id IN ('01tWC00000DD11SYAT','01tWC00000DD14lYAD')` → SolCats Brand Protection / Robotic Process Automation
- `SELECT MasterLabel, Solution_Category__c, Default_Uplift_Percent__c, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c FROM COLA_Uplift_Rules__mdt WHERE Solution_Category__c IN ('Brand Protection','Robotic Process Automation')` → 5% active / 9.85% active
