# Channel — Partner Discounts Data (D365 → Salesforce RCA Migration)

**Scope:** `Channel/Partner Discounts Data Lists/` — the partner/channel discount data lists exported from Dynamics 365 (D365) and reshaped into Salesforce Revenue Cloud Advanced (RCA) load files for both Cyber and Tech business units. This is **raw business-discovery / migration data**, complementary to the design KB (`FORTRA_KNOWLEDGE_BASE.md`).

**What this data is:** Per-partner, per-brand/solution discount schedules that govern what % off list a channel partner (Reseller / Distributor / MSP) receives. In RCA these become **Partner Discount** records that feed RLM (Revenue Lifecycle Management) partner pricing at quote time. The data carries two parallel discount tracks per row — **Channel Originated** (partner sourced the deal) and **Fortra Originated** (Fortra sourced it / "non-originating") — across five revenue categories: Software, New Maintenance, Renewal Maintenance, Subscription, Service.

---

## 1. Files in scope, at a glance

| File | Role | Key sheets (rows × cols) | Notes |
|---|---|---|---|
| `D365PartnerContractsAllBrands_2026_03_17.xlsx` | **Raw source export** from D365 — all brands, all units | `Sheet1` (2394r × 53c) | Native D365 `hs_*` schema; one row per (partner account × product brand) |
| `Archive/D365PartnerContractsAllBrands_2026_03_17_Backup.xlsx` | Backup of the above | identical | **Byte-identical** to the production export (diff confirmed) |
| `Copy of D365 Partner Discounts Data Template-WIP-Lidiane 2026.2.27.xlsx` | **WIP load template** (Lidiane Santos, 2026-02-27) | `Data to Load to UAT` (36r × 24c) + `Notes` | Cyber-only; uses *legacy* D365 solution names |
| `CyberDiscounts_UATSample_041326.xlsx` | **UAT sample** (2026-04-13) | `Data to Load to UAT` (36r × 24c) + `Notes` | Same 36 Cyber rows as WIP, but solution names *standardized* |
| `PartnerDiscount_CyberforProductionLoad.xlsx` | **Production load workbook** (Cyber) | `Cyber Data` (589r×22c), `Tech ALL Columns` (555r×62c), `Raw 2` (2394r×62c), `Cyber Edit` (37r×25c), `Lidiane Apr 4 Raw` (36r×24c) | Carries the SF field-API-name → D365-field mapping in the headers |
| `UAT Load Partner Discount Tech and Cyber.xlsx` | **Combined UAT load workbook** (Cyber + Tech) | `Data to Load C&T` (589r×22c), `Notes` (9r), `Tech ALL Columns` (555r×62c), `Raw 2` (2394r×62c), `Cyber Edit` (37r×25c), `Lidiane Apr 4 Raw` (36r×24c) | Superset; richer `Notes` with config-history annotations |

> **Extraction caveat (important):** The text extractor **caps every sheet at 400 non-empty rows**. So `Raw 2` (2394r), `Data to Load C&T` (589r), `Tech ALL Columns` (555r), and `Cyber Data` (589r) are all **truncated at row 400** in the `.txt`. Row counts and schema below are exact; row-level content beyond 400 must be read from the original `.xlsx`. The `Cyber Data` sheet in `PartnerDiscount_CyberforProductionLoad` extracted as **header-only** (the populated rows did not survive extraction) — see [§7 Open Questions].

---

## 2. The D365 source data model (`Sheet1`, 53 columns)

This is the native Dynamics 365 export. The grain is **one row per (partner account × product brand)** — a partner with discounts across 13 brands produces 13 rows. Column order as exported:

| # | D365 column | Meaning / use in migration |
|---|---|---|
| 1 | `dnb_dunsnumber` | D-U-N-S number — natural key to match the partner Account in SF |
| 2 | `exchangerate` | FX rate (mostly blank; `1` for some) |
| 3 | `hs_account` | D365 Account **GUID** (e.g. `4b848bf9-45cd-ec11-…`) — FK to partner account |
| 4 | `hs_accountname` | Partner account display name |
| 5 | `hs_contracttermenddate` | Contract end → maps to `Effective_End_Date__c` |
| 6 | `hs_contracttermstartdate` | Contract start → maps to `Effective_Start_Date__c` |
| 7 | `hs_historicalexchangerate` | (mostly blank) |
| 8 | `hs_initialmaintenancediscount` | **New Maintenance %** (Channel orig) → `New_Maintenance_Percent__c` |
| 9 | `hs_managedservicescommission` | Managed-services commission (not loaded) |
| 10 | `hs_managedservicesdiscount` | Managed-services discount |
| 11 | `hs_name` | Record name |
| 12 | `hs_newmaintenancecommission` | (commission, not loaded) |
| 13 | `hs_newsubscriptioncommission` | (commission, not loaded) |
| 14 | `hs_nonoriginatinginitialmaintenancediscount` | **New Maint % (Fortra orig)** → `Non_Orig_New_Maint_Pct__c` |
| 15 | `hs_nonoriginatingmanagedservicesdiscount` | Non-orig managed-services |
| 16 | `hs_nonoriginatingprofservicesdiscount` | **Services % (Fortra orig)** → `Non_Orig_Services_Pct__c` |
| 17 | `hs_nonoriginatingrenewmaintenancediscount` | **Renewal Maint % (Fortra orig)** → `Non_Orig_Ren_Maint_Pct__c` |
| 18 | `hs_nonoriginatingsoftwarediscount` | **Software % (Fortra orig)** → `Non_Orig_Software_Pct__c` |
| 19 | `hs_nonoriginatingsubscriptiondiscount` | **Subscription % (Fortra orig)** → `Non_Orig_Subscription_Pct__c` |
| 20 | `hs_notes` | Free-text deal terms (payment terms, volume tiers, brand lists) |
| 21 | `hs_otherreferralsdiscount` | Referral discount (0 throughout sample) |
| 22 | `hs_partnerdiscountclassification` | Classification GUID |
| 23 | `hs_partnerdiscountclassificationname` | Classification name — **empty for all rows in this export** |
| 24 | `hs_partnerdiscountid` | **Partner-discount record GUID** — the unique key carried into SF (`hs_partnerdiscountid`) for round-trip/idempotency |
| 25 | `hs_primarycertifiedcontact` | Cert contact GUID |
| 26 | `hs_primarycertifiedcontactname` | (blank) |
| 27 | `hs_productbrand` | Product brand **GUID** |
| 28 | `hs_productbrandname` | **Product brand name** (Digital Guardian, Titus, Terranova Security, …) — primary scope dimension |
| 29 | `hs_productcertification` | Cert GUID |
| 30 | `hs_productcertificationname` | (blank) |
| 31 | `hs_quotacommitment` | Annual quota commitment ($) |
| 32 | `hs_quotacommitment_base` | Quota (base currency) |
| 33 | `hs_renewalmaintenancecommission` | (commission) |
| 34 | `hs_renewalmaintenancediscount` | **Renewal Maint %** (Channel orig) → `Renewal_Maintenance_Percent__c` |
| 35 | `hs_secondarycertifiedcontact` | Cert GUID |
| 36 | `hs_secondarycertifiedcontactname` | (blank) |
| 37 | `hs_servicescommission` | (commission) |
| 38 | `hs_servicesdiscount` | **Services %** (Channel orig) → `Services_Percent__c` |
| 39 | `hs_softwarecommission` | (commission) |
| 40 | `hs_softwarediscount` | **Software %** (Channel orig) → `Software_Percent__c` |
| 41 | `hs_softwareproductmaster` | Product-master GUID (e.g. Outflank OST) |
| 42 | `hs_softwareproductmastername` | Product-master name (e.g. "Outflank Security Tooling (OST)") |
| 43–50 | `hs_special*` / `_base` pairs | Special initial-maint / services / software / subscription overrides (mostly blank) |
| 51 | `hs_subscriptiondiscount` | **Subscription %** (Channel orig) → `Subscription_Percent__c` |
| 52 | `ownerid` | Owner (partner manager) GUID |
| 53 | `owneridname` | Owner name — the channel/partner manager |

### Source volume & coverage (from the 399 rows that survived extraction of `Sheet1`)
- **399 rows extracted** (sheet declares 2394 rows — the remaining are either blank padding or truncated; the populated business set is much smaller than 2394).
- **60 unique partner account names**, **57 unique DUNS numbers**.
- **34 distinct product brands.** Top brands by row count:

| Brand | Rows | Brand | Rows |
|---|---|---|---|
| Titus | 30 | Linoma | 15 |
| Digital Defense | 30 | AutoMate | 9 |
| Vera | 29 | Fortra | 7 |
| Digital Guardian | 29 | Alert Logic | 7 |
| Core CTS | 26 | PowerTech | 6 |
| Boldon James | 25 | Robot, Cloud Data Protection | 5 each |
| Beyond Security | 24 | Halcyon, Core IGA | 4 each |
| Cobalt Strike | 23 | InterMapper | 3 |
| Clearswift | 23 | Tango04, SEQUEL, RJS, PowertechX | 2 each |
| Terranova Security | 22 | TeamQuest, ShowCase, Safestone, Fortra Security Services, Core SCS, CCSS, Bytware | 1 each |
| PhishLabs | 22 | | |
| Agari | 20 | | |
| Outflank | 16 | | |

  Brands span both **Cyber** (Digital Guardian, Titus, Vera, Boldon James, Cobalt Strike, Beyond Security, Terranova, PhishLabs, Agari, Outflank, Digital Defense, Alert Logic, Clearswift, Core CTS…) and **Tech** (AutoMate, PowerTech, Robot, InterMapper, SEQUEL, RJS, Bytware, CCSS, Halcyon, Linoma, Tango04, TeamQuest, ShowCase, Safestone, Core IGA…).

- **Discount % distribution** (`hs_softwarediscount` as exemplar of the value set used across all five categories): values observed are `0, 5, 15, 20, 25, 30, 35, 40, 45, 50`. Modal values: **0 (129 rows), 15 (125 rows), 40 (110 rows)**, 20 (22). The "0 across the board" rows were a deliberate decision to load (see [§5 Notes]).
- **`hs_partnerdiscountclassificationname` is empty for all rows** — classification is not populated in this export.
- **Partner managers (`owneridname`)** carrying the most discount records: Mandy Lopez (91), Lidiane Santos (76), Lindsay Martin (59), Toni Scott (25), Cassie Tusler (25), TJ Sundberg (19), Cindy Whalen (19), Kyrstin Goldschmidt (17), Vicki Smith (15), Katie Butwinick (11), Depa Patel (10).

---

## 3. The Salesforce RCA target model & field map (Load sheets)

The production/UAT load sheets reduce the 53-column D365 schema to a **22-column** SF-ready shape. The header text itself encodes the **D365-field → SF-API-name** mapping. The canonical target fields (Partner Discount object in RCA):

| Load column header | Salesforce API field | Sourced from D365 |
|---|---|---|
| Account Name | (lookup label) `hs_accountname` | — (blue, locate-only, **don't load**) |
| Account_c | `hs_account` (Account GUID) | `hs_account` (blue, locate-only) |
| dnb_dunsnumber | DUNS | `dnb_dunsnumber` (blue, locate-only) |
| Unit | `Unit__c` | derived (Cyber / Tech) |
| Solution Group 1.00 | `Solution_Category__c` | `Solution Group 1.00` |
| Solution Category 2.00 | `Solution_Group__c` | `Solution Category 2.00` |
| Model_Type__c | `Model_Type__c` | derived (Guaranteed Margin / Discount) |
| Is_Active__c | `Is_Active__c` | Y/N |
| Is_Default__c | `Is_Default__c` | Y/N |
| Software Percent Channel Orig. | `Software_Percent__c` | `hs_softwarediscount` |
| New Maintenance Channel Orig. | `New_Maintenance_Percent__c` | `hs_initialmaintenancediscount` |
| Renewal Maintenance Channel Orig. | `Renewal_Maintenance_Percent__c` | `hs_renewalmaintenancediscount` |
| Subscription Percent Channel Orig. | `Subscription_Percent__c` | `hs_subscriptiondiscount` |
| Service Percent Channel Orig. | `Services_Percent__c` | `hs_servicesdiscount` |
| Effective Start Date | `Effective_Start_Date__c` | `hs_contracttermstartdate` |
| Effective End Date | `Effective_End_Date__c` | `hs_contracttermenddate` |
| New Maintenance Percent Fortra Orig. | `Non_Orig_New_Maint_Pct__c` | `hs_nonoriginatinginitialmaintenancediscount` |
| Service Percent Fortra Orig. | `Non_Orig_Services_Pct__c` | `hs_nonoriginatingprofservicesdiscount` |
| Renewal Maintenance Percent Fortra Orig. | `Non_Orig_Ren_Maint_Pct__c` | `hs_nonoriginatingrenewmaintenancediscount` |
| Software Percent Fortra Orig. | `Non_Orig_Software_Pct__c` | `hs_nonoriginatingsoftwarediscount` |
| Subscription Percent Fortra Orig. | `Non_Orig_Subscription_Pct__c` | `hs_nonoriginatingsubscriptiondiscount` |
| hs_partnerdiscountid | (external/legacy id) | `hs_partnerdiscountid` (orange, Fortra-use, **don't load**) |

**Note the deliberate label cross-swap:** load header "Solution Group 1.00" maps to SF `Solution_Category__c`, and "Solution Category 2.00" maps to SF `Solution_Group__c`. The D365 "Group/Category" naming and the SF "Category/Group" naming are inverted — a known mapping trap to preserve on any re-load.

### Key structural facts of the target model
- **Two discount tracks per record:** "Channel Originated" (5 fields, the partner-sourced discount) and "Fortra Originated" / non-originating (5 fields, the lower discount when Fortra sourced the deal). Five revenue categories each: Software, New Maintenance, Renewal Maintenance, Subscription, Service.
- **Scope hierarchy:** `Unit__c` (Cyber | Tech) → `Solution_Category__c` (Solution Group 1.00) → `Solution_Group__c` (Solution Category 2.00) → optional Solution 3.00. A discount can be scoped at the unit level (blank group/category) or narrowed to a specific solution group/solution.
- **`Model_Type__c`** picklist: **`Guaranteed Margin`** vs **`Discount`**. Guaranteed-Margin partners get a margin floor; Discount partners get a straight % off. (Distributors frequently carry *both* a Guaranteed-Margin default row and additional Discount rows for specific solutions — e.g. Chillisoft, Computer Gross, Detech, Climb, Infinigate each have 1 GM row + 3 Discount rows.)
- **`Is_Default__c`** flags the partner's default/fallback discount row; **`Is_Active__c`** Y/N. In the Cyber sample, GM rows are usually `Is_Default=Y`; the supplementary Discount rows are `Is_Default=N`.

---

## 4. WIP template vs UAT sample vs Production load — the differences

### 4a. WIP template → UAT sample (the 36-row Cyber set)
`Copy of D365 Partner Discounts Data Template-WIP-Lidiane` and `CyberDiscounts_UATSample_041326` are the **same 36 Cyber rows / same accounts / same percentages / same dates**. The *only* delta is the **Solution Category 2.00 naming** — legacy D365 solution names were standardized to the new RCA solution taxonomy:

| WIP (legacy D365 name) | UAT sample (standardized RCA name) |
|---|---|
| Terranova | **Human Risk Management** |
| Fortra VM | **Vulnerability Management** |
| Phishlabs (used as a Solution Category) | **Brand Protection** |

This rename is the substantive migration transform for solution scoping. (The 36-row set also exists verbatim as the `Lidiane Apr 4 Raw` sheet inside both big load workbooks, and a reshaped/de-pivoted form as `Cyber Edit` (37r) where the Channel-orig and Fortra-orig blocks are laid out side by side per account.)

### 4b. WIP/Sample (36 Cyber rows) vs Production/UAT load (589-row combined)
- The 36-row WIP/sample is a **hand-curated Cyber pilot subset** (Lidiane's manual edits — partner type, tier, direct/indirect, DUNS lookups).
- The big load workbooks (`PartnerDiscount_CyberforProductionLoad`, `UAT Load Partner Discount Tech and Cyber`) are the **full programmatic transform of the entire D365 `Raw 2` (2394-row) export** into the 22-column SF shape, covering **both Cyber and Tech**.
- Both big workbooks carry the same supporting sheets: `Tech ALL Columns` (555r, the full Tech slice with all 62 D365 columns + the SF-field annotations), `Raw 2` (2394r, the full untouched D365 export embedded for reference), plus the curated `Cyber Edit` (37r) and `Lidiane Apr 4 Raw` (36r) Cyber sheets.
- The **only meaningful difference between the two big workbooks**: the production one's primary tab is named `Cyber Data` (Cyber-only intent) while the UAT one's is `Data to Load C&T` (Cyber **and** Tech combined), and the UAT `Notes` sheet (9 rows) is richer than production's (3 rows) — it adds data-review decisions and field-provenance annotations (Wren config vs Coastal-created fields). See [§5].

### 4c. What the extract shows of the combined load tab
Of the **first 400 rows** of `Data to Load C&T` that survived extraction, **all are `Unit = Tech`**, all `Model_Type__c = Discount`, all `Is_Active__c = Y`, all `Is_Default__c = Y`, **all Effective End Date blank**. Distribution of Solution Group / Category in that Tech slice:

- **Solution Group 1.00:** Power (155), RPA+ (130), Managed File Transfer (114).
- **Solution Category 2.00:** Network Monitoring (71), Cybersecurity (60), Systems Management (49), Robotic Process Automation (39), Business Intelligence (26), Doc Management (20), Core IGA (18), Capacity Management (2); 116 rows blank (unit/group-level scope).
- **205 unique partner accounts** appear across the captured load rows.

The Cyber rows (Unit = Cyber) live **beyond extraction row 400** in this sheet and were not captured here — they are present in the curated `Cyber Edit` / `Lidiane Apr 4 Raw` sheets (36–37 rows) and must be read from the original `.xlsx` for the full set.

---

## 5. Migration decisions captured in the `Notes` sheets

From `UAT Load Partner Discount Tech and Cyber` → `Notes` (9r) and the load template `Notes`:

- **Field color legend (load instructions):**
  - **Blue fields = DON'T LOAD** — locate-only, used to match the row to the right partner Account (`hs_accountname`, `hs_account` GUID, `dnb_dunsnumber`).
  - **Yellow fields = LOAD.** Yellow/red-font = "added per **Wren's config updates** and are in the db." Yellow/black-font = "originally created by **Coastal**" (the implementation partner).
  - **Orange fields = DON'T LOAD** — "For Fortra Use" (e.g. `hs_partnerdiscountid`).
- **Data-review decision — "all-zero" rows:** *"What is the value of the Rows with all Zero → **Load with Zeros.** Understand this will give us no business value. It will match D365 though."* → Decision to preserve fidelity with D365 even for 0%-discount rows (129 of 399 source rows have 0 software discount). This is why the load includes many `0/0/0/0/0` partner rows.
- **DUNS lookup:** the template `Notes` records "DUNS Number can be found here in D365:" — DUNS is the match key to resolve the SF partner Account.
- **Red fields are required** (template notes).

---

## 6. How this feeds RLM partner pricing (connection to RCA / Workday / MuleSoft)

- These records land as **Partner Discount** records keyed to the partner **Account** (matched via DUNS / D365 Account GUID). At quote time, **RLM partner pricing** reads the partner's discount schedule, selects the applicable row by **Unit → Solution Category → Solution Group** scope and by **Model Type** (Guaranteed Margin vs Discount), then applies the right **revenue-category %** (Software / New Maint / Renewal Maint / Subscription / Service) depending on the line's product type — choosing the **Channel-Originated** vs **Fortra-Originated** track based on who sourced the opportunity.
- This is the **channel/partner counterpart** to the customer-facing pricing covered in the design KB (`Rev_Mgmt_Default_Pricing_Procedure`, AttributeBasedAdjustment, etc.). Partner discounts are an additional waterfall input distinct from end-customer pricing.
- **Currency relevance (cross-ref SC-3384):** the load model has **no per-row currency key** on the discount % columns; the D365 source `exchangerate` is mostly blank/`1` and `hs_quotacommitment_base` is the only base-currency field. This mirrors the currency-blind data pattern flagged in the multi-currency pricing RCA (memory: `project_sc3384_multicurrency_pricing`) — partner discounts are stored as plain percentages (currency-agnostic by nature), but any currency-specific partner pricing would have to be handled upstream.
- **Workday / MuleSoft:** not directly referenced in these data lists. Partner discounts affect net price on the quote/order; the resulting net flows to Workday via the standard order→Workday MuleSoft path documented elsewhere. No partner-discount-specific integration appears in scope.

---

## 7. Open questions & gaps

1. **`Cyber Data` sheet extracted header-only** in `PartnerDiscount_CyberforProductionLoad.xlsx` — the 589 declared rows did not survive text extraction (the row after the header is blank, then the next sheet begins). The actual production Cyber load rows must be read from the original `.xlsx`. **Gap: the production Cyber row content is not in the text extract.**
2. **400-row extraction cap** truncates every large sheet: `Raw 2` (2394r), `Data to Load C&T` (589r), `Tech ALL Columns` (555r). Cyber rows in `Data to Load C&T` sit beyond row 400 and were not captured. Full content requires the originals.
3. **2394 vs 399 row mystery:** the D365 `Sheet1` declares 2394 rows but only ~399 are populated business rows (60 partners × brands). Are the other ~1995 rows blank padding, or did extraction stop? (The on-disk `.txt` ends at line 402, and the extractor logged "truncated at 400 non-empty rows; sheet has 2394 rows" — so 2394 is the sheet's used-range, but only ≤400 non-empty were emitted.) Confirm whether the true populated count exceeds 400.
4. **`hs_partnerdiscountclassificationname` empty** for all exported rows — is partner classification (e.g. tier) intended to drive pricing, or is Tier captured only on the Account? The curated Cyber sheets carry **Tier** (Diamond/Gold/Bronze/Authorized/MSP) and **Partner Type** (Reseller/Distributor/MSP) + **Direct/Indirect**, but these are *not* in the 22-column load shape → presumably stored on the Account, not the Partner Discount record. Confirm where Tier/Type land in SF.
5. **Effective End Date is blank** for essentially all load rows (Channel-orig track) even where D365 had `hs_contracttermenddate` — confirm whether open-ended discounts are intended or whether end-dates should be carried over.
6. **Guaranteed-Margin model mechanics:** how does RLM enforce a "Guaranteed Margin" vs a straight "Discount" model? The data only stores percentages; the GM-vs-Discount behavior must be implemented in the pricing procedure. Cross-reference the design KB pricing-procedure docs.
7. **"Wren's config updates" vs "Coastal-created" fields** — the Notes distinguish two provenance waves of fields. Which exact SF fields belong to each wave, and is there a risk of duplicate/competing fields? (e.g. were the `Non_Orig_*` fields all from one wave?)
8. **Solution taxonomy completeness:** the rename map (Terranova→Human Risk Management, Fortra VM→Vulnerability Management, Phishlabs→Brand Protection) covers only the Cyber pilot. Is there an equivalent legacy→RCA solution rename table for the full Tech/Cyber brand catalog? Not present in these files.

---

## Sources

Files read (all under `Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/`; text extracted under `Data/discovery-extract/text/…`):

- [D365PartnerContractsAllBrands_2026_03_17.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/D365PartnerContractsAllBrands_2026_03_17.xlsx) — raw D365 all-brands export; 53-col schema, 399 rows extracted (sheet declares 2394).
- [Archive/D365PartnerContractsAllBrands_2026_03_17_Backup.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/Archive/D365PartnerContractsAllBrands_2026_03_17_Backup.xlsx) — byte-identical backup of the above.
- [Copy of D365 Partner Discounts Data Template-WIP-Lidiane 2026.2.27.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/Copy of D365 Partner Discounts Data Template-WIP-Lidiane 2026.2.27.xlsx) — WIP Cyber load template (legacy solution names).
- [CyberDiscounts_UATSample_041326.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/CyberDiscounts_UATSample_041326.xlsx) — UAT sample (standardized solution names).
- [PartnerDiscount_CyberforProductionLoad.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/PartnerDiscount_CyberforProductionLoad.xlsx) — production load workbook; field-map headers; `Cyber Data` sheet extracted header-only.
- [UAT Load Partner Discount Tech and Cyber.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/UAT Load Partner Discount Tech and Cyber.xlsx) — combined Cyber+Tech UAT load workbook; richest `Notes`.

**Could not fully read (extraction-limited, not encrypted):** the `Cyber Data` sheet of `PartnerDiscount_CyberforProductionLoad.xlsx` (header-only in extract); all sheets >400 rows are truncated at 400 (`Raw 2`, `Data to Load C&T`, `Tech ALL Columns`). Full row-level content beyond row 400 requires opening the original `.xlsx`.

**Related KB / memory:** `FORTRA_KNOWLEDGE_BASE.md` (design synthesis, pricing procedure), `project_sc3384_multicurrency_pricing` (currency-blind pricing data pattern), `project_sc3359_partner_pricing_net_not_applied` (RLM partner-pricing net-application defect).
