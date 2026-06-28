# SC-3447 — Power Scope & Quantity Reality (live read-only data)

Investigation date: 2026-06-27
Org: FortraUAT (00DWC000006eUFF2A2)
Method: `sf data query -o FortraUAT` (read-only). All counts re-verified live; 2026-06-26
priors compared inline. Raw query JSON cached in scratchpad.

---

## 0. TL;DR

- 2026-06-26 catalog numbers **re-verified identical**: 3,406 Power products; 2,782 active;
  3,405 "Order Line Only" + exactly **1** "Order Line and Hardware".
- The lone "Order Line and Hardware" product is a **test fixture**, not a real product:
  `UAT Power Split Test - Order Line and Hardware --do not delete!`
  (Id `01tWC00000FiKdVYAV`, ProductCode `UAT-POWER-OLH-001`).
- **Quantities are seat/user/license counts, NOT machines.** Every top-20 high-qty Power
  product is "Software" (Subscription / Perpetual / Renewal-or-New Maintenance). Names like
  "...Password Self Help for IBM i", "...Multi-Factor Authentication", "...Users" make the
  per-seat semantics explicit. Sentinels 999999/99999/9999 = "unlimited" markers.
- The `for(i=1;i<qty;i++)` per-unit clone model is therefore **categorically wrong** for Power:
  it tries to mint one OrderItem per *seat*, up to **999,999** rows on a single line.
- **The convert backlog is live and real**: ~**167 distinct non-terminal quotes** carry a Power
  line ≥100 qty (79 quotes ≥457, the repro-proven blow size; 43 quotes ≥1000). These are
  almost entirely **NULL-status renewal quotes** (445 of 446 lines) — i.e. renewals waiting to
  be converted, every one of which will hit the CPU limit on convert.
- **Repro quote `0Q0WC000003AuQb0AK` (Q-00781200) NO LONGER EXISTS** as of 2026-06-27
  (count=0). Churn ate it. Repro *product* "Abstract" still valid.
- **Hard evidence the split only ever worked tiny**: 63 split-produced clone OrderItems exist
  org-wide; the **largest successful clone group is 9 clones**. Nothing large has ever
  converted — the feature is effectively broken for any realistic Power quantity.

---

## 1. Product2 Power catalog scope

Query:
```sql
SELECT COUNT(Id) total FROM Product2 WHERE Solution_Group__c='Power'
-- => 3406  (2026-06-26 prior: 3406  MATCH)

SELECT IsActive, COUNT(Id) cnt FROM Product2 WHERE Solution_Group__c='Power' GROUP BY IsActive
-- => IsActive=true 2782 ; IsActive=false 624  (prior: 2782 active  MATCH)

SELECT Power_Split_Type__c, COUNT(Id) cnt FROM Product2
WHERE Solution_Group__c='Power' GROUP BY Power_Split_Type__c
-- => "Order Line Only" 3405 ; "Order Line and Hardware" 1  (prior MATCH)
```

| Metric | Count |
|---|---|
| Total Power products | 3,406 |
| Active | 2,782 |
| Inactive | 624 |
| Power_Split_Type = "Order Line Only" | 3,405 |
| Power_Split_Type = "Order Line and Hardware" | **1** |

The single "Order Line and Hardware" record:
```sql
SELECT Id, Name, ProductCode, Family, IsActive, Power_Split_Type__c
FROM Product2 WHERE Solution_Group__c='Power' AND Power_Split_Type__c='Order Line and Hardware'
```
| Id | Name | ProductCode | Family | IsActive |
|---|---|---|---|---|
| 01tWC00000FiKdVYAV | UAT Power Split Test - Order Line and Hardware --do not delete! | UAT-POWER-OLH-001 | (null) | true |

=> It is a **manual test fixture**, not a sellable product. So in practice **100% of real
Power demand is "Order Line Only"**, the split path that mints one OrderItem per qty unit.

---

## 2. OrderItem (Power, Quantity>1) distribution

```sql
SELECT COUNT(Id) total, MAX(Quantity) maxq FROM OrderItem
WHERE Product2.Solution_Group__c='Power' AND Quantity>1
-- => total 3816 ; max 999999
```

Sentinel / threshold counts (each its own COUNT query, qty>1 base):

| Condition | OrderItem count |
|---|---|
| = 999999 | 134 |
| = 99999 | 4 |
| = 9999 | 8 |
| = 9990 | 0 |
| > 50 | 553 |
| > 300 | 279 |
| > 1000 | 182 |
| > 10000 | 138 |

Full bucket distribution (3,816 lines, qty>1):

| Quantity bucket | Lines |
|---|---|
| 2–10 | 2,805 |
| 11–50 | 458 |
| 51–100 | 149 |
| 101–300 | 125 |
| 301–1,000 | 97 |
| 1,001–10,000 | 44 |
| 10,001–100,000 | 4 |
| 100,001–1,000,000 | 134 |

Clone math (loop produces `qty-1` clones per line):
- **Σ(qty-1) across all Power OrderItems = 134,705,687** clones if every existing line were
  re-split. (Dominated by the 134 lines at 999,999.)
- **Lines that ALONE exceed 10,000 clones (qty-1 > 10000) = 138.**
- Lines qty-1 > 1,000 = 182. Lines qty-1 > 456 (≥ repro size) = 256.

So 138 individual existing OrderItem lines would each, by themselves, demand >10k clone
inserts. The repro at 456 is mid-pack, not an outlier.

---

## 3. QuoteLineItem (Power, Quantity>1) — the convert candidates

```sql
SELECT COUNT(Id) total, MAX(Quantity) maxq FROM QuoteLineItem
WHERE Product2.Solution_Group__c='Power' AND Quantity>1
-- => total 18137 ; max 999999
```

Sentinel / threshold counts:

| Condition | QLI count |
|---|---|
| = 999999 | 402 |
| = 99999 | 21 |
| = 9999 | 28 |
| = 9990 | 0 |
| > 50 | 2,257 |
| > 300 | 966 |
| > 1000 | 600 |
| > 10000 | 423 |

Bucket distribution (18,137 lines, qty>1):

| Quantity bucket | Lines |
|---|---|
| 2–10 | 13,463 |
| 11–50 | 2,417 |
| 51–100 | 684 |
| 101–300 | 607 |
| 301–1,000 | 366 |
| 1,001–10,000 | 177 |
| 10,001–100,000 | 21 |
| 100,001–1,000,000 | 402 |

- QLI lines qty-1 > 10,000 = **423**.
- QLI lines qty-1 > 1,000 = 600. Lines ≥456 (repro-proven blow) = 868.

### Live blocked-convert backlog (the key business number)

Convertible = quote NOT in a terminal status (`Won`,`Canceled`,`Rejected`,`Denied`,`Ordered`)
OR status null. Distinct quotes carrying ≥1 Power line at/above threshold:

| Power line qty threshold | Convertible lines | Distinct convertible quotes |
|---|---|---|
| ≥ 100 | 446 | **167** |
| ≥ 200 | 346 | 118 |
| ≥ 457 (repro-proven blow) | 259 | **79** |
| ≥ 1,000 | 193 | 43 |

Status mix of the ≥100 convertible backlog:
```sql
SELECT Quote.Status, COUNT(Id) FROM QuoteLineItem
WHERE Product2.Solution_Group__c='Power' AND Quantity>=100
  AND (Quote.Status NOT IN ('Won','Canceled','Rejected','Denied','Ordered') OR Quote.Status=null)
GROUP BY Quote.Status
```
| Status | Lines |
|---|---|
| (blank / null) | 445 |
| Draft | 1 |

=> The backlog is **almost entirely NULL-status renewal quotes** (e.g. "Renewal Quote for
Account: Zurich Life Assurance plc …" at qty 999999). These are renewals queued to convert;
**every one will hit the CPU limit when someone clicks Convert.** Estimate: **~80–170 live
quotes** are currently un-convertible due to this defect, growing as renewals are generated.

Note on "Won": 609 of the 868 ≥457 QLI lines sit on `Won` quotes (already-closed historical
deals). Those are not part of the active convert backlog but show the long-standing pattern.

---

## 4. Top 20 Power products by max line quantity — seats vs machines

### By OrderItem max quantity
```sql
SELECT Product2.Name, Product2.Family, Product2.Rev_Category_Name__c, Product2.Power_Split_Type__c,
       MAX(Quantity), COUNT(Id)
FROM OrderItem WHERE Product2.Solution_Group__c='Power' AND Quantity>1
GROUP BY ... ORDER BY MAX(Quantity) DESC LIMIT 20
```
| maxQ | lines | Family | Rev Category | Product |
|---|---|---|---|---|
| 999999 | 256 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Password Self Help for IBM i |
| 99999 | 161 | Perpetual | Non-Recurring Perpetual Sales - Software | Insite Analytics |
| 9999 | 31 | Perpetual | Non-Recurring Perpetual Sales - Software | Sequel Repository Designer |
| 9999 | 4 | Subscription | Recurring Sales - Software Subscriptions | Sequel Repository |
| 9999 | 25 | Perpetual | Non-Recurring Perpetual Sales - Software | Sequel Repository |
| 9900 | 77 | Subscription | Recurring Sales - Software Subscriptions | Powertech Multi-Factor Authentication for IBM i |
| 7500 | 105 | Subscription | Recurring Sales - Software Subscriptions | Powertech Password Self Help for IBM i |
| 5080 | 6 | Perpetual | Non-Recurring Perpetual Sales - Software | Safestone Password Self Help Users |
| 2000 | 5 | Perpetual | Non-Recurring Perpetual Sales - Software | Productivity Enablement |
| 1620 | 8 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus - x86 Linux |
| 999 | 2 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus for IBM i |
| 988 | 734 | Perpetual | Non-Recurring Perpetual Sales - Software | Query & Report Writer |
| 931 | 57 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus - Linux / AIX |
| 750 | 3 | Subscription | Recurring Sales - Software Subscriptions | Safestone Password Self Help Users |
| 507 | 169 | Subscription | Recurring Sales - Software Subscriptions | Robot Schedule Enterprise |
| 500 | 352 | Perpetual | Non-Recurring Perpetual Sales - Software | Robot Schedule Enterprise Agent |
| 475 | 107 | Subscription | Recurring Sales - Software Subscriptions | Powertech Antivirus - Linux / AIX |
| 417 | 13 | Subscription | Recurring Sales - Software Subscriptions | Powertech Antivirus - x86 Linux |
| 400 | 24 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Multi-Factor Authentication for IBM i |
| 209 | 2 | Perpetual | Non-Recurring Perpetual Sales - Software | Alignia - Business Application |

### By QuoteLineItem max quantity
| maxQ | lines | Family | Rev Category | Product |
|---|---|---|---|---|
| 999999 | 267 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Password Self Help for IBM i |
| 999999 | 1267 | Renewal Maintenance | Recurring Renew Maintenance | Cybersecurity-RenewalMaintenance |
| 99999 | 198 | Perpetual | Non-Recurring Perpetual Sales - Software | Insite Analytics |
| 99999 | 5005 | Renewal Maintenance | Recurring Renew Maintenance | Business Intelligence-RenewalMaintenance |
| 9999 | 16 | Subscription | Recurring Sales - Software Subscriptions | Sequel Repository |
| 9999 | 33 | Perpetual | Non-Recurring Perpetual Sales - Software | Sequel Repository Designer |
| 9999 | 27 | Perpetual | Non-Recurring Perpetual Sales - Software | Sequel Repository |
| 9900 | 258 | Subscription | Recurring Sales - Software Subscriptions | Powertech Multi-Factor Authentication for IBM i |
| 7500 | 233 | Subscription | Recurring Sales - Software Subscriptions | Powertech Password Self Help for IBM i |
| 5080 | 6 | Perpetual | Non-Recurring Perpetual Sales - Software | Safestone Password Self Help Users |
| 2000 | 5 | Perpetual | Non-Recurring Perpetual Sales - Software | Productivity Enablement |
| 1800 | 122 | New Maintenance | Recurring New Maintenance | Cybersecurity-NewMaintenance |
| 1700 | 1898 | Renewal Maintenance | Recurring Renew Maintenance | Systems Management-RenewalMaintenance |
| 1620 | 9 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus - x86 Linux |
| 999 | 16 | New Maintenance | Recurring New Maintenance | Business Intelligence - New Maintenance-NewMaintenance |
| 999 | 21 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus for IBM i |
| 988 | 745 | Perpetual | Non-Recurring Perpetual Sales - Software | Query & Report Writer |
| 931 | 65 | Perpetual | Non-Recurring Perpetual Sales - Software | Powertech Antivirus - Linux / AIX |
| 900 | 161 | Services | Non-Recurring Services Sales - Training | Tango Services |
| 750 | 13 | Subscription | Recurring Sales - Software Subscriptions | Safestone Password Self Help Users |

**Interpretation:** 100% of the high-qty products are software/maintenance/services revenue
categories. Top quantities are on **per-seat security software** (Password Self Help,
Multi-Factor Authentication) and **maintenance bundles** (per-seat renewal/new maintenance).
The 999999/99999/9999 plateaus are clearly **"unlimited"/site-license sentinels**, not
literal device counts. **None are hardware.** This is decisive evidence that Power quantity =
seat/user/license count, so splitting one OrderItem per unit is semantically wrong and the
root cause of the CPU blow-up — there is no business reason to materialize 999,999 line rows.

---

## 5. Repro line product sanity (Abstract)

```sql
SELECT Id, Name, ProductCode, Solution_Group__c, Power_Split_Type__c, Family, IsActive
FROM Product2 WHERE Id='01tWC00000DD11GYAT'
```
| Field | Value |
|---|---|
| Id | 01tWC00000DD11GYAT |
| Name | Abstract |
| ProductCode | BI-ABS-RSS-ABSTSU |
| Solution_Group__c | Power |
| Power_Split_Type__c | Order Line Only |
| Family | Subscription |
| IsActive | true |

Matches the 2026-06-26 prior (Power / Order Line Only / Active; Family=Subscription, new).

**Repro QUOTE re-check:** `0Q0WC000003AuQb0AK` (Q-00781200) — **COUNT=0, no longer exists**
in FortraUAT as of 2026-06-27. It was converted/deleted/refreshed away in the daily churn. A
fresh repro quote will be needed for any future re-test; use the Abstract product + qty ≥ ~50
(see §6) on a fresh quote.

---

## 6. CPU-cliff bound from existing successful splits

```sql
SELECT COUNT(Id) FROM OrderItem
WHERE Product2.Solution_Group__c='Power' AND Original_Order_Item__c!=null   -- => 63
SELECT Original_Order_Item__c, COUNT(Id) FROM OrderItem
WHERE Product2.Solution_Group__c='Power' AND Original_Order_Item__c!=null
GROUP BY Original_Order_Item__c ORDER BY COUNT(Id) DESC                      -- max group = 9
```
- Only **63** split-produced clone OrderItems exist org-wide.
- **Largest successful clone group = 9 clones** (parent 802WC00000MrnPLYAZ).
- => In practice the split has only ever completed for tiny quantities (≤~10). Combined with
  the dead-txn snapshot (CPU >10,000ms at only ~480 DML rows), the practical CPU cliff sits
  **well below 100**, far below the repro's 456 and astronomically below the 999,999 sentinels.
  Effectively the feature works only for trivial Power lines and fails for any real seat count.

---

## 7. Re-verification vs 2026-06-26 priors

| Prior claim | Today | Status |
|---|---|---|
| Power total 3,406 | 3,406 | MATCH |
| Active 2,782 | 2,782 | MATCH |
| 3,405 "Order Line Only" + 1 "Order Line and Hardware" | same | MATCH |
| The 1 OLH product | = UAT test fixture `01tWC00000FiKdVYAV` | NEW DETAIL (it's a fixture) |
| Repro product Abstract = Power/OLO/Active | confirmed (Family=Subscription) | MATCH |
| Repro quote 0Q0WC000003AuQb0AK | **GONE (count=0)** | CHANGED — churn |
| Quantity is seat/sentinel not machine | confirmed across top-20 (all software) | STRENGTHENED |
| Sentinels 9999/99999/999999 | present (8/4/134 OI; 28/21/402 QLI); 9990 = 0 | CONFIRMED; 9990 not used |

---

## 8. Implications for the fix (data-driven)

- The defect impacts a **live, growing backlog of ~80–170 non-terminal quotes** (mostly NULL-
  status renewals), each un-convertible today. This is a true Blocker, not a one-off.
- A row-per-seat model can never scale: a single legitimate line legally reaches 999,999.
  Any fix that still materializes N OrderItems (sync OR async OR chunked) is a stopgap — async
  merely moves the wall (DML rows, storage, downstream flow re-fires per clone). The data
  argues for the **redesign** option (do not explode seat-count Power lines into one row per
  seat at all; keep qty on the single OrderItem, or split only by a real machine/HW dimension,
  which for "Order Line Only" is none).
- Because 100% of real Power demand is "Order Line Only" and the only "…and Hardware" record
  is a test fixture, the hardware-split branch is currently exercising zero real volume — the
  per-unit explosion is pure liability with no offsetting business need.
