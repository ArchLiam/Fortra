# SC-3350 — Live COLA CMDT Rates + Go-Live Traps (verification)

**Date:** 2026-06-10 (research run, post Marc DeBrey's same-day class edits)
**Org:** FortraUAT (read-only)
**Stream:** Live/CMDT rates + go-live traps
**Grounding brief:** `/Users/liamjeong/Documents/Code/Fortra/Data/sc3354/SC-3354_Research_Brief.md` (08:13 UTC) — §6 rate table, B8 BoKS trap.

---

## 0. Headline

The live COLA/MyCAP CMDT **data records are UNCHANGED vs the 08:13 brief**. Marc's same-day
edits (14:00Z–16:51Z) touched the Apex **classes only**, not the CMDT records — proven by
`SystemModstamp`: newest COLA record = `2026-06-09T23:34:29Z` (TEMP BoKS, yesterday), every other
record `2026-04-17T00:34:39Z`; MyCAP `2026-04-15T01:43:15Z`. **Zero rate deltas.**

B8 TEMP_BoKS trap **reconfirmed against live data**: the TEMP rule covers **17** products,
the permanent `Powertech IAM BoKS` rule covers **0**.

**Field-name correction to the task prompt / brief:** the CMDT fields are
`Is_Active__c` (not `Active__c`), `Effective_Start_Date__c` / `Effective_End_Date__c`
(not `Start_Date__c` / `End_Date__c`). The task's literal SOQL fails with INVALID_FIELD; corrected SOQL used below.

---

## 1. SOQL used (corrected field names)

COLA rules (the task's `Active__c`/`Start_Date__c`/`End_Date__c` do **not** exist):
```sql
SELECT MasterLabel, DeveloperName, Solution_Category__c, Default_Uplift_Percent__c,
       Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c, Description__c, SystemModstamp
FROM COLA_Uplift_Rules__mdt ORDER BY Solution_Category__c
```
MyCAP rules:
```sql
SELECT MasterLabel, DeveloperName, Default_Out_Year_Uplift_Percent__c,
       Minimum_Out_Year_Uplift_Percent__c, Is_Active__c, SystemModstamp
FROM MyCAP_Rules__mdt
```
BoKS product counts:
```sql
SELECT COUNT(Id) FROM Product2 WHERE Solution_Category__c = 'Powertech Identity & Access Manager (BoKS)'  -- = 17 (15 active)
SELECT COUNT(Id) FROM Product2 WHERE Solution_Category__c = 'Powertech IAM BoKS'                          -- = 0
SELECT Solution_Category__c, COUNT(Id) FROM Product2 GROUP BY Solution_Category__c                         -- full distribution
```

`COLA_Uplift_Rules__mdt` field list (live describe): Id, DeveloperName, MasterLabel,
`Default_Uplift_Percent__c` (double), `Description__c`, `Effective_End_Date__c` (date),
`Effective_Start_Date__c` (date), `Is_Active__c` (boolean), `Solution_Category__c` (string).

`MyCAP_Rules__mdt` field list: `Default_Out_Year_Uplift_Percent__c` (double),
`Is_Active__c` (boolean), `Minimum_Out_Year_Uplift_Percent__c` (double).

---

## 2. CURRENT COLA_Uplift_Rules__mdt — all 22 records (all Active=true, all dates null)

| MasterLabel | DeveloperName key | Solution_Category__c | Rate % | Active | Start | End | #Products | Note |
|---|---|---|---|---|---|---|---|---|
| Brand Protection | — | Brand Protection | 5 | T | — | — | 48 | |
| Business Intelligence | — | Business Intelligence | 7.85 | T | — | — | 512 | |
| Capacity Management | — | Capacity Management | 4.7 | T | — | — | 284 | |
| Cloud Data Protection | — | Cloud Data Protection | 5 | T | — | — | 58 | |
| Core IGA | — | Core IGA | 4.7 | T | — | — | 172 | |
| Cybersecurity | — | Cybersecurity | 7.85 | T | — | — | 495 | |
| Data Protection | — | Data Protection | 4.7 | T | — | — | 828 | |
| Doc Management | — | Doc Management | 7.85 | T | — | — | 766 | |
| Email Security | — | Email Security | 5 | T | — | — | 603 | |
| File Integrity Monitoring | — | File Integrity Monitoring | 5 | T | — | — | 1199 | |
| **Fortra Platform** | — | Fortra Platform | **0** | T | — | — | **0** | **DEAD rule (0 products) AND rate 0** |
| Globalscape | — | Globalscape | 7.85 | T | — | — | 755 | |
| GoAnywhere | — | GoAnywhere | 7.85 | T | — | — | 744 | |
| Human Risk Management | — | Human Risk Management | 5 | T | — | — | 119 | |
| **IPP** | — | IPP | **0** | T | — | — | 4 | rate 0 (4 products → 0% uplift) |
| Network Monitoring | — | Network Monitoring | 7.85 | T | — | — | 106 | |
| Offensive Security | — | Offensive Security | 6.2 | T | — | — | 63 | |
| **Powertech IAM BoKS** | — | Powertech IAM BoKS | 7.85 | T | — | — | **0** | **DEAD permanent rule (0 products)** |
| **TEMP BoKS IAM ProductCat** | — | **Powertech Identity & Access Manager (BoKS)** | 7.85 | T | — | — | **17** (15 active) | **THE ONLY rule covering live BoKS** |
| Robotic Process Automation | — | Robotic Process Automation | 9.85 | T | — | — | 192 | |
| Systems Management | — | Systems Management | 7.85 | T | — | — | 1628 | |
| Vulnerability Management | — | Vulnerability Management | 6.2 | T | — | — | 166 | |

- **All 22 are Active=true.** 0 inactive.
- **All Effective_Start_Date__c / Effective_End_Date__c are null** → every rule is unconditionally
  effective per the handler/prehook date-window logic.

**MyCAP_Rules__mdt (1 record):** `Global` — Default_Out_Year_Uplift_Percent__c = **3**,
Minimum_Out_Year_Uplift_Percent__c = **3**, Active=true. (Out-year/MyCAP path is INERT for pricing
per brief B3 — not re-tested in this stream.)

---

## 3. B8 TEMP_BoKS trap — RECONFIRMED (live data)

| Rule (MasterLabel) | Solution_Category__c string | Matching Product2 | Active Product2 |
|---|---|---|---|
| `TEMP BoKS IAM ProductCat` (TEMP) | `Powertech Identity & Access Manager (BoKS)` | **17** | **15** |
| `Powertech IAM BoKS` (permanent) | `Powertech IAM BoKS` | **0** | **0** |

The two rules carry **DIFFERENT** `Solution_Category__c` strings, so there is **no map-key collision**
(the CMDT map is keyed by `Solution_Category__c`; both engines `.put()` under distinct keys). The trap
is purely that the **permanent** rule's category string matches no product while the **TEMP** rule's
does. **Deleting the TEMP rule before go-live (as instructed elsewhere) strands all 17 BoKS products
at silent 0% uplift** — the permanent rule will NOT pick them up because their `Product2.Solution_Category__c`
= `Powertech Identity & Access Manager (BoKS)`, not `Powertech IAM BoKS`.

**Matching mechanism (both engines, verified in live source):**
- Lookup key = `QuoteAction.SourceAsset.Product2.Solution_Category__c`
  (`COLAUpliftHandler.cls:272`, `COLAUpliftPrehook.cls:283`).
- CMDT map built by `getCOLARulesMap()` — identical in both classes:
  `COLAUpliftHandler.cls:349-377` and `COLAUpliftPrehook.cls:551-583`. Filter:
  `WHERE Is_Active__c = true`, then in-Apex effective-date window check (both null here → effective),
  then `rulesMap.put(rule.Solution_Category__c, rule)`. Both engines AGREE on filter + key.

**The 17 BoKS products (Id | active | ProductCode | Name):**
```
01tWC00000DD15IYAT | True  | PIA-PIA-NROR-BOKSAL          | BoKS Administration License Fee
01tWC00000FCPTHYA5 | True  | PIA-PIA-NROR-BOKSAL-TECH     | BoKS Administration License Fee (Technical)
01tWC00000DD15JYAT | True  | PIA-PIA-NROR-BOKSCE          | BoKS Certification Test
01tWC00000DD1bvYAD | True  | PIA-PIA-RSS-PIAS             | Powertech Identity & Access Manager (BoKS)
01tWC00000DCywFYAT | False | PIA-PIA-RSS-PIAS_MAINT       | Powertech Identity & Access Manager (BoKS)
01tWC00000DD2MsYAL | False | PIA-PIA-RSS-PIAS_LIC         | Powertech Identity & Access Manager (BoKS)
01tWC00000DD1btYAD | True  | PIA-PIA-NRPS-PIAP            | Powertech Identity & Access Manager (BoKS)
01tWC00000FCUfCYAX | True  | PIA-PIA-RSS-PIAS-TECH        | ...(Technical)
01tWC00000FCUfBYAX | True  | PIA-PIA-NRPS-PIAP-TECH       | ...(Technical)
01tWC00000FCUfAYAX | True  | PIA-PIA-RNM-PIAMBK-TECH      | ...(Technical)-NewMaintenance
01tWC00000FCKKbYAP | True  | PIA-PIA-RRM-PIAM-TECH        | ...(Technical)-RenewalMaintenance
01tWC00000DD1bwYAD | True  | PIA-PIA-NRST-POID            | ...Services
01tWC00000FCKKcYAP | True  | PIA-PIA-NRST-POID-TECH       | ...Services (Technical)
01tWC00000DD1bxYAD | True  | PIA-PIA-NRSE-PIAMSE          | ...Services Expense
01tWC00000FCKKdYAP | True  | PIA-PIA-NRSE-PIAMSE-TECH     | ...Services Expense (Technical)
01tWC00000DD1bsYAD | True  | PIA-PIA-RNM-PIAMBK          | ...-NewMaintenance
01tWC00000DD1buYAD | True  | PIA-PIA-RRM-PIAM            | ...-RenewalMaintenance
```
(15 active, 2 inactive: `_MAINT`/`_LIC` variants.)

---

## 4. Additional coverage findings (full CMDT × Product2 join — beyond just BoKS)

Computed by joining the live 22 CMDT categories against the live `Product2 GROUP BY Solution_Category__c`
(21 distinct values, including `None`).

**DEAD CMDT rules (0 matching Product2):**
1. `Powertech IAM BoKS` (permanent) — 0 products (the B8 trap counterpart).
2. `Fortra Platform` — 0 products **AND** rate 0. (Brief §6 also flagged this as DEAD.)

**Product2 categories with NO CMDT rule → silent 0% / no uplift:**
- `None` (null `Solution_Category__c`) — **88 products**. Renewals of these get no category match →
  no CMDT default → 0% COLA. (Brief §5/D8 referenced "88 null-category products.") **Reconfirmed: 88.**

**Zero-rate categories that DO have products (uplift applies but resolves to 0%):**
- `IPP` — rate 0, 4 products.
- (`Fortra Platform` rate 0 but 0 products → no effect.)

**Coverage table (live, product counts attached):**
```
   48  rate=5     Brand Protection
  512  rate=7.85  Business Intelligence
  284  rate=4.7   Capacity Management
   58  rate=5     Cloud Data Protection
  172  rate=4.7   Core IGA
  495  rate=7.85  Cybersecurity
  828  rate=4.7   Data Protection
  766  rate=7.85  Doc Management
  603  rate=5     Email Security
 1199  rate=5     File Integrity Monitoring
    0  rate=0     Fortra Platform          <-- DEAD
  755  rate=7.85  Globalscape
  744  rate=7.85  GoAnywhere
  119  rate=5     Human Risk Management
    4  rate=0     IPP                       <-- 0% with products
  106  rate=7.85  Network Monitoring
   63  rate=6.2   Offensive Security
    0  rate=7.85  Powertech IAM BoKS        <-- DEAD (B8)
   17  rate=7.85  Powertech Identity & Access Manager (BoKS)  <-- TEMP, the live BoKS rule
  192  rate=9.85  Robotic Process Automation
 1628  rate=7.85  Systems Management
  166  rate=6.2   Vulnerability Management
   88  (no rule)  None                      <-- UNCOVERED, silent 0%
```

---

## 5. Deltas vs the 08:13 brief (§6)

| Item | Brief §6 | Live now | Delta? |
|---|---|---|---|
| Rate table (all 22 rates) | listed | byte-identical rates | **NO CHANGE** |
| MyCAP Global out-year / min | 3 / 3 | 3 / 3 | **NO CHANGE** |
| TEMP rule covers BoKS | 17 products | **17** (15 active) | **NO CHANGE** (confirmed) |
| Permanent `Powertech IAM BoKS` | 0 products | **0** | **NO CHANGE** (confirmed) |
| Null-category products | "88 null-category" | **88** | **NO CHANGE** (confirmed exact) |
| `Fortra Platform` DEAD | noted "(DEAD — 0 products)" for BoKS; Fortra Platform 0 rate | DEAD: 0 products | **CONFIRMED** (brief implied, now quantified) |
| CMDT record count | "22 active" | 22, all active | **NO CHANGE** |
| TEMP rule MasterLabel | brief calls it "TEMP Powertech Identity & Access Manager (BoKS)" | live MasterLabel = **`TEMP BoKS IAM ProductCat`** | **LABEL MISMATCH** — the brief used the *category string* as the label; the actual MasterLabel differs (cosmetic, but matters if someone searches by label to delete it) |
| CMDT field names | task SOQL used `Active__c`/`Start_Date__c`/`End_Date__c` | real fields `Is_Active__c`/`Effective_Start_Date__c`/`Effective_End_Date__c` | **TASK-PROMPT FIELD-NAME ERROR** corrected |

**Marc's same-day edits did NOT touch the CMDT data.** SystemModstamps:
- COLA: newest `2026-06-09T23:34:29Z` (TEMP BoKS, yesterday), rest `2026-04-17T00:34:39Z`.
- MyCAP: `2026-04-15T01:43:15Z`.
- Marc's class edits today (AssetContractQueryHelper 14:00Z, QLDescriptionGeneratorPrehook 14:41Z,
  COLAUpliftHandler 16:29Z, COLAUpliftPrehook+Test 16:51Z) are **code-only**. The rate model is the
  exact one the brief described. (Class-logic deltas are a different stream's scope; this stream
  confirms the *data* is stable and the *category-match contract* in both engines is unchanged at the
  source lines cited.)

---

## 6. Go-live traps (summary for the ticket)

1. **TEMP_BoKS (B8) — MEDIUM/go-live.** Do NOT delete `TEMP BoKS IAM ProductCat` without first either
   (a) re-pointing the permanent rule's `Solution_Category__c` to `Powertech Identity & Access Manager (BoKS)`,
   or (b) re-categorizing the 17 Product2 records to `Powertech IAM BoKS`. Otherwise 17 BoKS products
   (15 active) → silent 0% renewal uplift.
2. **88 null-category products** → no rule → silent 0% on renewal. Decide intended behavior (default rule? data fix?).
3. **`Fortra Platform` permanent rule is dead** (0 products) and **`Powertech IAM BoKS` permanent rule is dead** (0 products) — neither does anything today.
4. **`IPP` rate=0 with 4 live products** — intentional 0% or an unset rate? Confirm with business.
5. **Field-name discipline:** any migration/test/deploy script must use `Is_Active__c`,
   `Effective_Start_Date__c`, `Effective_End_Date__c` — the names in the task prompt and the brief's prose are wrong.

---

## 7. Confidence

- Rate table / record counts / Active flags / dates: **HIGH** (direct live SOQL, 22+1 records).
- B8 BoKS counts (17 / 0): **HIGH** (direct COUNT, listed all 17).
- 88 null-category, dead-rule join: **HIGH** (live GROUP BY).
- "CMDT data unchanged by Marc's edits": **HIGH** (SystemModstamp predates today).
- Both engines agree on filter+key: **HIGH — verified against FRESHEST live source** via Tooling API
  `SELECT Body FROM ApexClass`. Live LastModifiedDates today: COLAUpliftPrehook + COLAUpliftTest
  **16:58:15Z**, COLAUpliftHandler **16:29:57Z**, QLDescriptionGeneratorPrehook 14:41:27Z,
  AssetContractQueryHelper 14:00:37Z (all by Marc DeBrey — Prehook is even LATER than the brief's
  stated 16:51Z). In the freshest bodies, BOTH `getCOLARulesMap` (Handler ~L378-398, Prehook ~L640-660)
  still use `WHERE Is_Active__c = true` + the same effective-date window + `rulesMap.put(rule.Solution_Category__c, rule)`;
  lookup still reads `SourceAsset.Product2.Solution_Category__c` (Handler L36). **Line numbers shifted
  vs the brief (handler map was 349-377, now ~378-398) because Marc's edits grew the class, but the
  category-match contract is byte-equivalent.** The local `Data/cola-renewal-review/live/` copies are
  slightly stale (predate 16:58Z) but the contract they show matches the freshest org source.
