# Sales & Marketing — Territory Routing & Inquiry Assignment

> Discovery KB · Topic 03 · Source folder: `Fortra Discovery Documentation/Sales and Marketing/Territory Routing/`
> Complements the design KB (`FORTRA_KNOWLEDGE_BASE.md`). This file captures the **raw discovery inputs**: the documented assignment process, the routing flowchart, and the actual territory definition table (`FortraTerritories2026_18_02.xlsx`) that the routing matches against.

## 1. What this is

Fortra's lead/inquiry **Territory Assignment & Notification Process**. When an inbound inquiry is created in Salesforce, an automated process must determine, **per product of interest**, the right territory and therefore the right owner (AE / BDR), Channel Account Manager (CAM), and notification user, then split/route the inquiry and email the responsible teams.

There are two artifacts describing the *logic*:

- **`Territory Assignment Process.docx`** — the written step-by-step spec (Steps 1–7). Inquiry-centric; does **not** mention D&B, PCTA, or Global HQ.
- **`Territory Assignment - Updated.pdf`** — the **current-state** flowchart (read with vision). This is the newer/authoritative diagram and adds three concepts the docx omits: an upfront **D&B account-resolution** step, a **PCTA?** decision that flips AE↔BDR precedence, and a **Global HQ owner** notification at the end.
- **`Archive/SF_TerritoryRouting.*` (jpg / vsdx / drawio)** — an older, far more granular swimlane of the same flow (matches the docx hierarchy node-for-node). Archived/superseded but useful for the exhaustive match-hierarchy order. Its node labels also reference `Domestic HQ exists in SF`, `Is PCTA?` (twice), and `Is Global HQ Owner different than Sales Inquiry Assignee` — confirming the Updated PDF additions originate here.

And one artifact providing the *data*:

- **`FortraTerritories2026_18_02.xlsx`** — the territory master/load table. The `Final UAT List` sheet (2,138 rows) is the authoritative load; the other sheets are working drafts and source lookups (see §6).

---

## 2. The territory definition table — dimensions & field map

The territory record is matched on a set of dimension columns and carries the owner/assignment columns. From the `Final UAT List` sheet header (13 columns):

| Column (xlsx) | Likely SF API name | Role | Notes |
|---|---|---|---|
| `Unit__c` | `Unit__c` | Match dimension (coarsest) | Only two values: **`Cyber`** (2,071 rows) and **`Tech`** (67 rows). |
| `Solution_Group__c` | `Solution_Group__c` | Match dimension (mid) | `Defensive Security` (1,766), `Offensive Security` (305), `RPA+` (67). |
| `Solution_Category__c` | `Solution_Category__c` | Match dimension (finest) | Blank for **2,071** rows (all Cyber). Populated only on Tech/RPA+ rows: `Robotic Process Automation` (63), `Core IGA` (1), `Network Monitoring` (1), `Powertech Identity & Access Manager (BoKS)` (1), `Capacity Management` (1). |
| `Parent Name` | (territory parent / grouping) | Hierarchy / human grouping | 48 distinct values. Names the rep "patch" (e.g. `West - NorCal`, `FinServ - South`, `Offensive Security 7`, `Public Sector - DoD`). Blank for all Tech rows. |
| `Name` | `Name` | Territory record name | Composed string — see naming convention §2.1. Unique per row. |
| `Named_Account__c` | `Named_Account__c` | Match dimension (highest priority in hierarchy) | **0 rows populated** in the Final UAT List — the named-account tier exists in logic but has no data loaded yet (see Open Questions). |
| `Industry__c` | `Industry__c` | Match dimension | Populated on 66 rows only. Values below. |
| `Account_Executive__c` | `Account_Executive__c` | **Owner (AE)** | 52 distinct AEs. |
| `BDR__c` | `BDR__c` | **Owner (BDR)** | 20 distinct BDRs. Many rows blank (international/named-industry rows). |
| `CAM` | (Channel Account Manager) | Partner-deal owner | 10 distinct CAMs **in this sheet** — but CAM is more fully driven by the geo→CAM lookup in `Sheet4b` (see §4). Present only in `Final UAT List` (12-col draft sheets drop it). |
| `State__c` | `State__c` | Match dimension (geo) | 65 distinct states/provinces. Blank on 259 rows (those matched by Country or Industry only). |
| `Country__c` | `Country__c` | Match dimension (geo) | 238 distinct countries. Populated on 247 rows (the international/non-US rows); blank on US-state and zip rows. |
| `Zip_Code__c` | `Zip_Code__c` | Match dimension (finest geo) | Populated on **1,653 rows** — almost all in two US patches (NorCal & FL-N/TX, see §3.3). 5-digit US ZIPs. |

### 2.1 `Name` naming convention

`Name` is a delimited composite of the populated dimensions, in the form:

```
<Unit>-<Solution Group>-[<Solution Category>-]<geo-or-industry-or-list>
```

Examples observed:
- Geo (state): `Cyber-Offensive Security-Virginia`
- Geo (zip): `Cyber-Defensive Security-California-93426`
- Industry+state: `Cyber-Defensive Security-Financial - Other Services-Illinois`
- Industry+country: `Cyber-Defensive Security-Government - DoD-United States`
- Country: `Cyber-Offensive Security- Mexico`
- Tech/category: `Tech-RPA+-Robotic Process Automation-Alaska`
- Public-sector pseudo-geo: `Cyber-Offensive Security-Public Sector OffSec`

> **Data-quality flags in the source rows:** inconsistent leading spaces after the dash on international rows (`Cyber-Offensive Security- Costa Rica`); spelling errors carried into territory data — `Domincan Republic`, `Falkand Islands`, `Belguim`, `Gilbraltar`, `Krgyzstan`, `Slovkia`, `Phillipines`, `New Calendonia`, `Cote d'lvoire`, `Dijbouti`. These will become literal territory/geo values in SF unless cleansed; account/lead geo data must match these exact (mis)spellings for the match to hit.

### 2.2 `Industry__c` picklist values used

Industry is a match dimension only on Cyber rows. Distinct values + row counts:

| Industry value | Rows | Used with |
|---|---|---|
| `Financial - Other Services` | 51 | Defensive Security, state-level (the 6 `FinServ -` patches) |
| `Government - Civilian` | 3 | Off+Def Sec, country/PublicSector |
| `Government - DoD` | 3 | Off+Def Sec |
| `Government - Intelligence Community` | 3 | Off+Def Sec |
| `Energy/Utilities` | 2 | Def Sec / Public Sector |
| `Government - Defense Industrial Base` | 1 | OffSec (Josh Rhees) |
| `Government - Federal Systems Integrator` | 1 | OffSec |
| `Government - State & Local` | 1 | OffSec |
| `Public Sector - Energy / Utilities` | 1 | Def Sec Canada |

(2,072 rows have Industry blank — the geo-only rows.)

---

## 3. Territory geometry — how the patches are built

### 3.1 Offensive Security (Cyber) — 305 rows, country/state based
Organized into numbered patches `Offensive Security 1…16` (`Parent Name`), one AE each. US/Canada patches are **state-driven**; international patches are **country-driven** (a single AE owning dozens of countries). `Sheet1` (17 rows) is the human-readable summary of these patches (one row per patch listing all its states/countries in a comma string). Patch→AE→BDR examples:

| Patch | AE | BDR | Coverage |
|---|---|---|---|
| Offensive Security 1 | McKenzie Kestner | Kelton Herrick | VA, DC, WV, PR |
| Offensive Security 2 | Nick O'Hara | Kelton Herrick | IL, KS, LA, MO, OK, TX |
| Offensive Security 4 | Connor Johnson | (none) | New England + Eastern Canada |
| Offensive Security 7 | Luis Enrique Angeles Anguiano | (none) | LATAM + Caribbean (~48 countries) |
| Offensive Security 9 | Islam Saad | (none) | Middle East |
| Offensive Security 10 | James Cooper | Tom Palmer | Northern/Western Europe |
| Offensive Security 11 | Prash Rai | Harrison Riley | E. Europe / Africa (~65 countries) |
| Offensive Security 12 | Ryan Power | (none) | DACH + Baltics + Russia |
| Offensive Security 13 | Sudan Gurung | (none) | France/Iberia/W. Africa |
| Offensive Security 14 | Timothy Steele | (none) | Australia, New Zealand |
| Offensive Security 15 | Natalie Chong | (none) | APAC + Pacific Islands (~50) |
| Offensive Security 16 | Josh Rhees | (none) | **`Public Sector OffSec`** (industry-driven, US Gov verticals) |

### 3.2 Defensive Security (Cyber) — 1,766 rows, the bulk of the table
Three overlapping sub-models all under `Solution_Group__c = Defensive Security`:

1. **`FinServ -` patches (6)** — *industry-overlay* territories: `Industry__c = Financial - Other Services` + `State__c`. Each patch = one AE + one BDR covering a band of states (Mid-Atlantic / North / North Central / South / South Central / West). These take priority over the plain geo territory when the inquiry's account is FinServ.
2. **`Public Sector -` patches (4)** — *industry+country* territories (no state/zip): Civilian, DoD, Intelligence, Energy/Utilities — each = one AE (Dan Jamison / Garrett Wiesner / David Nelson / Travis Emerson), no BDR, country = US and Canada rows.
3. **Plain geo patches (`North -`, `South -`, `West -`, `LATAM 1`, `North - Canada (non French)`)** — the general defensive-security field, state-driven (and zip-driven for two patches, see §3.3).

### 3.3 The two ZIP-level patches (1,653 of the 1,653 zip rows)
Two AEs are split down to **individual US ZIP codes** rather than whole states:

| Parent Name | AE | BDR | State | Zip rows |
|---|---|---|---|---|
| `West - NorCal` | Linh Mings | James Landers | California | **892** |
| `South - FL-N, WI, IA` | Luke Lorah | Tevin Robertson | FL/WI/IA | **496** |
| `South - LA, TX-N` | Chris Scarcella | Kyle Cleaver | LA/TX | **265** |

This is why the table is 2,138 rows instead of a few hundred: California and the FL/TX/WI corridor are carved at ZIP granularity (the `Zip_Code__c` match tier exists specifically to support these split metros). `Sheet2` (891 ZIPs) is the raw NorCal ZIP list used to build these rows.

### 3.4 Tech unit — 67 rows, category+state
All `Tech`/`RPA+`. The bulk (63) are `Robotic Process Automation` by US state, single AE **Marjie Sarphati**, no BDR. The other 4 are one-off `Solution_Category__c` rows (Core IGA, Network Monitoring, BoKS, Capacity Management). Tech rows have **no `Parent Name`** and are the catch-all "Tech queue" target referenced in the default-assignment step.

---

## 4. CAM (Channel Account Manager) geo lookup — `Sheet4` / `Sheet4b`

CAM assignment for partner deals is driven by a **geography→CAM table**, separate from the AE/BDR territory rows:

- **`Sheet4b`** (308 rows, header `State/Province | Country/Region | Channel Account Manager`) is the usable lookup: country (or state) → CAM. Distinct CAMs and their coverage counts:

| CAM | Geos covered |
|---|---|
| Moe Bux | 59 |
| KoK Chan | 53 |
| Nils Hansen | 47 |
| Jenko Gaviglia | 33 |
| John Murdock | 30 |
| Jean-Philippe Fourche | 24 |
| Don Smith | 23 |
| Melissa O'Leary | 16 |
| Larry Meeusen | 15 |
| Michael Leitner | 4 |
| Sean Donnelly | 2 |
| `N/A` | 1 |

- **`Sheet4`** (308 rows) is the same data with columns mis-ordered (`Country/Region | Channel Account Manager | State/Province`) and the CAM column actually holding the geo name in many rows — a **broken/draft transpose**; use `Sheet4b`.
- Note: international territory rows in `Final UAT List` already carry a per-row CAM (e.g. OffSec 7 → `Nils Hansen`, OffSec 9 → `Moe Bux`), so CAM is partly denormalized into the territory rows and partly resolved via the geo lookup. The two should agree; reconcile before load.
- `Sheet3` (69 rows: `Territory | BDR | Robot/Powertech | BI/RPG Toolbox/Surveyor | DocM`) is a **separate, product-line-specific BDR routing** (legacy Tripwire/Globalscape-style per-state BDR by product family: Robot/Powertech, BI/RPG Toolbox/Surveyor, DocM). Owners here (Joe Hurle, Cooper Yeary, Danny Anderson, Lauren Vecere, Mike Long, etc.) do **not** overlap with the Cyber AE/BDR pool — this is the Tech-side per-product BDR map and looks like an input that fed the `Tech`/`RPA+` rows. Likely needs its own territory rows or a product-family routing rule.

---

## 5. The assignment & notification process (logic)

### 5.1 Trigger & inputs (Step 1, docx)
- Inquiry record created in SF, pre-populated: contact info, **Products of Interest** (multi-select picklist, *must* be completed), Account & Contact matching done **externally before** SF entry.
- Record auto-flagged **`assignment ready`** on creation → triggers the process. Flag can be re-set to **manually re-run** the whole process.

### 5.2 Account resolution via D&B (Updated PDF only — not in docx)
The current-state flow starts with account hygiene *before* matching:
1. **Send Info to D&B** — send all available info (email, country, state, etc.) to **Dun & Bradstreet** to find a matching account and its **domestic ultimate (Domestic HQ)** account.
2. **Domestic HQ exists in SF?**
   - **Yes →** proceed to territory matching.
   - **No → Create Account Structure** — create/link any needed accounts so SF holds the complete, correct account hierarchy, then proceed.

> This is the integration touch-point: territory routing depends on a clean **Domestic HQ / global parent** account hierarchy, sourced from D&B. Connects to the broader Fortra account-hierarchy / D&B enrichment design.

### 5.3 Per-product territory match (Step 2) — the match hierarchy
**Loop over every product in Products of Interest.** For each: find the corresponding **Marketing Product** in SF (assumed **1:1** mapping between picklist value and Marketing Product), then run the match hierarchy.

The hierarchy runs in three nested "levels" using the Marketing Product's classification, **most specific level first**:
1. **Solution Category level** — only if `Marketing Product Solution Category` is **not blank**.
2. **Solution Group level** — repeat the entire sub-hierarchy using Solution Group.
3. **Unit level** — repeat the entire sub-hierarchy using Unit.

Within **each** level, try these dimension combinations **in priority order** and stop at the first match:

| Priority | Match attempt | Updated-PDF diamond label |
|---|---|---|
| 1 | **Named Account** | `Name Account Territory Found` |
| 2 | Industry + Country | `Industry Territory Found` |
| 3 | Industry + State + Zip | (collapsed into Industry tier on the Updated PDF) |
| 4 | Industry + State | — |
| 5 | Industry alone | — |
| 6 | Country | `Country only Territory Found` |
| 7 | State + Zip | `State & Zip Code Territory Found` |
| 8 | State | `State Only Territory Found` |

- **Default (no match at any level):** assign to the **Cyber or Tech queue** based on the Marketing Product's `Unit` (docx) — the Updated PDF labels this **"Assign Default Territory (Sales Ops Queue)"**.
- Store the matched territory + Marketing Product, continue to next product.

> The Archive drawio enumerates this exhaustively (Industry+Country+Solution Category → Industry+State+Zip+SC → Industry+State+SC → Industry+SC → Country+SC → State+Zip+SC → State+SC, then "Repeat all steps with Solution Group", then "Repeat all steps with Unit"). The text-PDF flowchart (`Territory Assignment - Updated.pdf.txt`) confirms the same ladder.

### 5.4 Owner determination (Step 3) + PCTA branch
For each territory/product combination, pick the owner:
- If territory **`Assigned to AE`** checkbox is checked → use the territory's **AE**.
- Else (BDR-led):
  - If inquiry **has a partner** → use **Partner BDR** field if populated, otherwise the regular **BDR** field.
  - If **no partner** → use the regular **BDR** field.

The **Updated PDF** frames the AE-vs-BDR choice as a single decision **`Is PCTA?`**:
- **Yes →** *Assign to AE* (or BDR if AE not defined).
- **No →** *Assign to BDR* (or AE if BDR not defined).

> **PCTA** (Partner-Centric Territory Assignment, per the archive node "Is PCTA?") is the modeled switch between AE-owned and BDR-owned routing. The docx "Assigned to AE checkbox" and the PDF "Is PCTA?" are the same gate expressed differently. **Open question:** exact definition/source field of PCTA — reconcile with the territory `Assigned to AE` checkbox.

**Record splitting:** compare owners across all processed products:
- Same owner for all → assign that owner to the original inquiry.
- Multiple owners → **split** the inquiry into separate records, one per unique owner, assign each. (Updated PDF: *Combine products assigned to the same owner into one Sales Inquiry Object* → *Collect Unique Assignments*.)

### 5.5 Product of Interest records (Step 4)
Create **one Product of Interest record per Marketing Product/Territory combination**, linked to the appropriate (original or split) inquiry, carrying the specific Marketing Product + Territory. (Updated PDF "Evaluate each unique assignment" lane: Create SF Sales Inquiry Record → Add all Products of Interest → Associate with Domestic HQ Account → Assign to correct user → Create Sales Inquiry.)

### 5.6 CAM assignment (Step 5)
Triggered by Product of Interest creation. **Only if the inquiry has a partner** (else skip entirely). Uses the **identical match hierarchy** as Step 2 (Category→Group→Unit). The territory used for CAM lookup **may differ** from the AE/BDR territory. Match → assign CAM from matched territory; no match → leave CAM **blank** (no default).

### 5.7 Notification user assignment (Step 6)
Triggered by Product of Interest creation, **for all inquiries regardless of partner**. Runs the identical match hierarchy **but against the inquiry's associated ACCOUNT record** (not the inquiry's own geo). Stores the matched territory ID as **Notification Territory**, and the matched territory's **AE** as **Notification User**, on the Product of Interest record.

### 5.8 Email notification (Step 7)
Runs once at the very end, after all Product of Interest records exist:
- Query all Product of Interest records → compile Notification Users + their inquiries.
- **Group by Notification User** to prevent duplicate emails.
- Send **one email per Notification User** with their assigned inquiry/inquiries + product details.
- Set the **notification flag** on records (team-notified).

### 5.9 Global HQ notification (Updated PDF only)
After "Notify Sales Inquiry Assignee", the current-state flow adds a final branch:
- **Is PCTA?** → **Yes →** **Is Global HQ Owner different than the Sales Inquiry Assignee?** → **Yes →** **Notify Global HQ Owner** → END.

> So on partner/PCTA deals where the account's **Global HQ** is owned by a *different* rep than the inquiry assignee, that global-HQ owner is also notified. This reuses the D&B-built account hierarchy from §5.2.

---

## 6. Workbook sheet inventory (`FortraTerritories2026_18_02.xlsx`)

| Sheet | Rows × Cols | Role |
|---|---|---|
| **`Final UAT List`** | 2,139 × 13 | **Authoritative territory load** (the only sheet with the `CAM` column). 2,138 data rows. |
| `Table1_3` | 3,090 × 12 | Earlier full draft (3,089 rows; Def Sec 2,783) — superseded by Final UAT List. |
| `Table1_2` | 417 × 12 | Intermediate draft (OffSec 299 + DefSec 117). |
| `Table1_1` | 381 × 12 | Intermediate draft (OffSec 299 + DefSec 81). |
| `OffSec` | 306 × 12 | Offensive Security working set (299 OffSec + 6 DefSec). |
| `Sheet1` | 17 × 12 | Human-readable OffSec patch summary (one row per `Offensive Security N`, states/countries in a comma string). |
| `Sheet4b` | 308 × 3 | **Geo → CAM lookup** (usable). |
| `Sheet4` | 308 × 3 | Same data, broken column order — ignore, use `Sheet4b`. |
| `Sheet2` | 1,017 × 1 | Raw US ZIP list (891 values) feeding the NorCal ZIP-level rows. |
| `Sheet3` | 69 × 5 | Tech/legacy **per-product BDR map** (`Territory \| BDR \| Robot/Powertech \| BI/RPG Toolbox/Surveyor \| DocM`). |

The progression `Table1_1 → Table1_2 → Table1_3 → Final UAT List` shows the table being built up (Offensive Security first, Defensive Security expanded incrementally, then ZIP-level NorCal/FL-TX added) and CAM added only at the end.

---

## 7. How this maps to Salesforce RCA / Workday / MuleSoft

- **Salesforce object model:** The dimension columns use `__c` API-name conventions (`Unit__c`, `Solution_Group__c`, `Solution_Category__c`, `Named_Account__c`, `Industry__c`, `Account_Executive__c`, `BDR__c`, `State__c`, `Country__c`, `Zip_Code__c`) — implying a **custom `Territory`-style object** (likely `Territory__c` or similar) loaded from this sheet, *not* native Salesforce Enterprise Territory Management (ETM). The match logic (priority ladder, PCTA gate, splitting) is custom **Apex/Flow**, not ETM assignment rules. The `Parent Name` column suggests a self-referencing parent/child territory hierarchy.
- **Custom inquiry model:** "Sales Inquiry" + "Product of Interest" are custom objects (the PDF says "Create SF Sales Inquiry Record"). Note the parent's memory: in this org **Leads are labeled "Inquiry"** — confirm whether "Sales Inquiry" = the renamed `Lead` or a distinct custom object before building.
- **D&B integration:** the upfront account-resolution step ("Send Info to D&B", "Domestic HQ exists in SF?", "Create Account Structure") is an external enrichment call — candidate **MuleSoft** integration, and a hard dependency: territory matching for Named Account / Industry / Global-HQ notification all rely on the D&B-built account hierarchy.
- **No Workday touch-point** in this flow — territory routing is pre-sales (lead→inquiry assignment), upstream of quote/order; Workday only enters after order conversion.
- **Marketing Product 1:1 assumption** is load-bearing: every Products-of-Interest picklist value must map to exactly one Marketing Product carrying Unit/Solution Group/Solution Category, or the match hierarchy can't start. Verify this mapping exists.

---

## 8. Open questions & gaps

1. **Named Account tier has no data.** `Named_Account__c` is the #1 priority match in the hierarchy but **0 rows** are populated in `Final UAT List`. Either named accounts are loaded separately, or this tier is currently dead. Confirm before relying on named-account routing.
2. **PCTA definition.** What field/logic sets "Is PCTA?" — is it literally the territory `Assigned to AE` checkbox, an inquiry partner flag, or a separate Partner-Centric attribute? The docx and PDF describe the same gate differently.
3. **CAM double-source.** CAM appears both denormalized on territory rows (`Final UAT List.CAM`, 10 distinct) and in the geo lookup (`Sheet4b`, 12 distinct). Which is authoritative for the Step-5 CAM assignment? They must be reconciled.
4. **`Sheet3` product-family BDR map** — is this still in use? Its owners don't appear in the main AE/BDR pool; looks like a legacy Tech routing that may need conversion into territory rows or a product-routing rule.
5. **Geo spelling errors** (`Domincan Republic`, `Falkand Islands`, `Belguim`, etc.) baked into territory data — will silently break matches unless account/lead geo is normalized to the same misspellings, or the data is cleansed on load.
6. **`Solution_Category__c` mostly blank** (all Cyber rows) — so the "Solution Category level" of the hierarchy only ever fires for Tech/RPA+ products. Confirm Cyber marketing products truly have no Solution Category, or whether category routing is intended to grow.
7. **ZIP coverage is partial** — only NorCal + FL-N/WI/IA + LA/TX-N are carved to ZIP. All other states route at state level. Confirm the State-level fallback always catches ZIPs not in the two carved metros.
8. **docx vs Updated PDF drift** — the docx (Steps 1–7) predates the D&B / PCTA / Global-HQ additions in the Updated PDF. Treat the **Updated PDF as current**; the docx is the detailed body logic, the PDF adds the front (D&B) and back (Global HQ) bookends.

---

## Sources

- [Territory Assignment Process.docx](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/Territory%20Assignment%20Process.docx) — written Step 1–7 spec (read via extracted text).
- [Territory Assignment - Updated.pdf](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/Territory%20Assignment%20-%20Updated.pdf) — current-state flowchart (read with **vision**; D&B / PCTA / Global HQ branches).
- [FortraTerritories2026_18_02.xlsx](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/FortraTerritories2026_18_02.xlsx) — territory master/load table (parsed in full via openpyxl: `Final UAT List`, `Sheet1`–`Sheet4b`, `OffSec`, `Table1_1/2/3`).
- [Archive/SF_TerritoryRouting.jpg](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/Archive/SF_TerritoryRouting.jpg) — archived granular swimlane (read with **vision**; same flow as the detailed text-PDF, too small to read individually but node text recovered from the .drawio/.pdf extracts).
- [Archive/SF_TerritoryRouting.drawio](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/Archive/SF_TerritoryRouting.drawio) — node-label source (HTML-encoded labels: Domestic HQ exists in SF, Name Account/Industry/Country/State&Zip/State Territory Found, Is PCTA? ×2, Is Global HQ Owner different than Sales Inquiry Assignee).
- [Archive/SF_TerritoryRouting.vsdx](../Fortra%20Discovery%20Documentation/Sales%20and%20Marketing/Territory%20Routing/Archive/SF_TerritoryRouting.vsdx) — Visio source of the archived diagram (extract yielded only branch Yes/No labels).
- The detailed text-PDF extract `Territory Assignment - Updated.pdf.txt` (flowchart node labels) corroborates the docx match-ladder node-for-node.

### Not extractable / partial
- `SF_TerritoryRouting.vsdx` extracted text was only the Yes/No edge labels (no node geometry/text) — geometry recovered instead from the `.drawio` labels and the `.jpg`/`.pdf` vision reads.
- `SF_TerritoryRouting.jpg` is legible only as overall layout at the provided resolution; individual box text was recovered from the companion `.drawio`/PDF extracts rather than OCR of the image.
