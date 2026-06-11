# BSI Discovery — Campaign / Marketing Product & Products of Interest (POI) UAT

**Scope:** UAT screenshot walkthrough of the Salesforce **Campaign** object's *Marketing Product* feature and the related *Products of Interest (POI)* model on the **Inquiry** (Fortra's renamed Lead) object, in the **Fortra Sales** Lightning app (UAT org). All sources are PNG screenshots (no text extract existed); reconstructed here via vision.

**Why it matters:** This is the marketing-attribution layer of Fortra's lead-to-opportunity funnel. A **Campaign** carries a *Marketing Product* (the offering being marketed); inbound web-form **Inquiries** carry one-or-more *Products of Interest* (multi-select + a child related list); and the **Unit** (business line) on the Inquiry is expected to auto-derive from the Product of Interest. The screenshots are an active-defect UAT pass — they double as a bug log (one confirmed mismatch bug, plus expected-behavior annotations).

> Terminology note: Fortra renames the standard SF **Lead** object to **"Inquiry"** (the Lightning app is "Fortra Sales", tab label "Inquiries"). See the SC-3171 close-reason memory ("Lead is labeled 'Inquiry'") and the design-KB Lead/Inquiry docs. Treat "Inquiry" = Lead throughout this doc.

---

## 1. Feature model at a glance

```
Campaign (renamed/standard SF Campaign)
  └─ Marketing Product   [lookup → "Marketing Products" search; single value]
  └─ Focus Area          [picklist, REQUIRED]
  └─ Is Branded?         [checkbox]
  └─ Objective           [picklist]
  └─ Partner Account, Legacy Id, ...
  └─ Related lists: Products of Interest, Campaign History, Child Sales Inquiries,
                    Notes, Files, Inquiry History, Opportunities (8)
  └─ Custom Links: "View All Campaign Members", "View Campaign Influence Report"

Inquiry (= Lead, renamed)
  └─ Product of Interest [MULTI-SELECT picklist on the record; e.g. "Brand Protection;Cloud Data Protection"]
  └─ Unit                [picklist; EXPECTED to auto-populate from Product of Interest → e.g. Brand Protection ⇒ Cyber]
  └─ PCTA Type           [picklist; e.g. "Demo"]
  └─ Priority            [picklist; e.g. "Hot"]
  └─ Inquiry Status      [New | Pending Res(ponse) | Assigned | Working | Closed | Converted ...]
  └─ Related lists: Campaign History, Child Inquiries, Products of Interest (child object),
                    Files, Inquiry History
  └─ "Add Product of Interest" pop-up (child record): Marketing Product (picklist), Notes, Part of Original Request (checkbox)
```

The naming is overloaded and is itself a source of UAT confusion (see [Bug & Observations](#4-uat-bugs--observations)):
- **Campaign.Marketing Product** — a *lookup* that searches "Marketing Products".
- **Inquiry.Product of Interest** — a *multi-select picklist* directly on the Inquiry record.
- **Products of Interest** — a *child related-list object* hanging off both Campaign and Inquiry; its "Add Product of Interest" pop-up has a field whose label still reads **"Marketing Product"** (struck through in the screenshot and re-annotated by the tester as it *should* read **"Product of Interest"**).

---

## 2. Campaign object — fields & layout (UAT)

Observed on the sample record **"Customer Conference - Email Invite (Sample)"** (Owner: Joe Romo; Created/Modified 3/24/2025).

### 2.1 Details — left column
| Field | Type (observed) | Sample value | Notes |
|---|---|---|---|
| Campaign Name | Text | Customer Conference - Email Invite (Sample) | |
| Active | Checkbox | ✓ (checked) | |
| Parent Campaign | Lookup → Campaign | Customer Conference Event (Sample) | Hierarchy supported |
| Type | Picklist | Email | Also seen: "Event" (on Campaign History rows) |
| Campaign Currency | Currency picklist | USD - U.S. Dollar | Required on create pop-up |
| Objective | Picklist | --None-- | |
| Is Branded? | Checkbox | unchecked | |
| **Marketing Product** | **Lookup** ("Search Marketing Products…") | *(empty on sample)* | The feature under test. Single-value lookup, magnifier search box. |
| **Focus Area** | Picklist, **REQUIRED** (red asterisk) | --None-- | Has an info-tooltip (ⓘ) icon |
| Description | Long text | "Email invite to our conference" | |

### 2.2 Details — right column
| Field | Type | Sample value |
|---|---|---|
| Partner Account | Lookup → Account | *(empty)* |
| Campaign Owner | User | Joe Romo |
| Status | Picklist | Completed |
| Start Date | Date | 7/19/2025 |
| End Date | Date | 7/25/2025 |
| Legacy Id | Text | *(empty)* — legacy-CRM external key (D365/Tripwire/Globalscape migration) |

Highlight (compact) bar shows: **Type, Status, Start Date, End Date**.

### 2.3 Planning section
| Field | Sample value |
|---|---|
| Num Sent in Campaign | 18,575 |
| Expected Response (%) | 0.00% |
| Budgeted Cost in Campaign | USD 15,500.00 |
| Actual Cost in Campaign | USD 20,000.00 |
| Expected Revenue in Campaign | USD 100,000.00 |

> In the "Planning Section" screenshot the entire Planning block is **struck through with a large red X** by the tester — interpreted as a UAT instruction to **remove / hide the Planning section** from this layout (these are standard SF campaign-planning fields not used by Fortra). The "Campaign Statistics" section header appears below it.

### 2.4 Activity panel
The right-hand **Activity** composer panel (Log a Call / Email / Event tabs, "Only show activities with insights", Upcoming & Overdue) is **struck through with a red X** in the "Activity Section" screenshot — interpreted as **remove the Activity panel** from the Campaign layout for UAT.

### 2.5 Custom Links section
Two custom links present (the first is highlighted as in-scope):
- **View All Campaign Members** ← highlighted
- View Campaign Influence Report

Also visible in that block: **Created By** Joe Romo 3/24/2025 10:44 PM, **Last Modified By** Joe Romo 3/24/2025 10:44 PM, and a stray field value "7" (likely Number of Leads/Contacts).

### 2.6 Page-level buttons
Edit · Clone · **Child Campaign** · (overflow ▾).

---

## 3. Related tabs / related lists

### 3.1 Campaign → Related tab
The Campaign **Related** tab (highlighted) exposes these related lists:

| Related list | Count (sample) | Action button | Notes |
|---|---|---|---|
| **Products of Interest** | (0) | **New** (red-annotated) | Child object; cart icon |
| Campaign History | (1) | Add to Campaign | Shows member rows: e.g. "test campaign - abby meyer - 01/28", Type **Event**, Status **Sent**; "View All" |
| Child Sales Inquiries | (0) | New | star icon |
| Notes | (0) | New | |
| Files | (0) | Upload Files | |

> The **Products of Interest (0)** related list and its **New** button are circled/red-marked — the focus of this UAT: the ability to add POI child records from the Campaign.

### 3.2 Campaign → Opportunities related list
Header **Opportunities (8)** — "8 items · Sorted by Close Date". Columns: **Opportunity Name, Sales Stage, Amount, Forecast Amount, Close Date**. Sample rows (note legacy product tags TE/TFS/FIM/Tripwire — D365/Tripwire heritage):

| # | Opportunity Name | Sales Stage | Amount | Forecast Amount | Close Date |
|---|---|---|---|---|---|
| 1 | Adirondack Health - Tripwire - Greenzeig | 3- Evaluating | USD 463,440.00 | USD 463,440.00 | 6/24/2026 |
| 2 | Baker Hughes-FIM | 1- Pre-Qualified | — | — | 3/31/2026 |
| 3 | Net New TE On-Prem | 11- Closed Lost | USD 67,683.60 | USD 67,683.60 | 1/29/2026 |
| 4 | Prabhudas Lilladher Pvt Ltd- | 1- Pre-Qualified | USD 21,409.50 | USD 21,409.50 | 12/31/2025 |
| 5 | MY/MTMY/Excel Force /MSEC/TE FIM | 1- Pre-Qualified | — | — | 6/30/2025 |
| 6 | Malomatia_MSP_TE | 11- Closed Lost | USD 204,669.09 | USD 192,869.09 | 6/18/2025 |
| 7 | Family bank_TE | 11- Closed Lost | — | — | 4/27/2025 |
| 8 | Airbus Defense and Space-TFS | 11- Closed Lost | USD 12,352.50 | USD 12,352.50 | 3/3/2025 |

**Sales Stage picklist values observed:** `1- Pre-Qualified`, `3- Evaluating`, `11- Closed Lost` (numbered/ordered stage names — useful for stage-mapping work).

### 3.3 Inquiry → Related tab
Inquiry "**Test Form Inquiry**" (Name: Abby Schoenecker, Company: Jamf). Path/status bar values:
**New → Pending Res(ponse) → Assigned → Working → Closed → Converted**.

Related List Quick Links: **Campaign History (1), Child Inquiries (0), Products of Interest (0), Files (0), Inquiry History (1)**.
Related tab top lists: **Products of Interest (0)**, then **Campaign History (1)** (with "Add to Campaign"; row "test campaign - a…", Type Event, Status Sent).

---

## 4. UAT bugs & observations

### 4.1 BUG — "Products of Interest Field and List Not Matching" (confirmed)
Screenshot: [Products of Interest Field and List Not Matching.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20Field%20and%20List%20Not%20Matching.png)

On Inquiry **"Test Form Inquiry"** (Abby Schoenecker / Jamf):
- The **Product of Interest** *field* (multi-select picklist) = **"Brand Protection;Cloud Data Protection"** (two values).
- The **Products of Interest** *related list* (child object) count = **(0)** — both the Quick Link and the Related-tab list show zero child records.

**Defect:** the multi-select picklist value on the Inquiry and the child related-list of Products of Interest are **out of sync** — selecting products in the field does **not** create matching POI child records (and/or vice-versa). The tester boxed both the related-list link and the field value to highlight the mismatch. This is the central UAT issue for this feature: the two representations of "products of interest" must be kept consistent (likely a Flow/trigger that should fan-out the multi-select picklist into child POI records, or roll child records up into the picklist).

Other field values on this Inquiry (context for repro): Inquiry Owner Joe Romo, Inquiry Status **New**, Priority **Hot**, **PCTA Type Demo**, **Unit Cyber**, Address France, Phone (952) 607-6097, Email abby.schoenecker@jamf.com.

### 4.2 EXPECTED BEHAVIOR — Unit must auto-populate from Product of Interest
Screenshot: [Unit Field Populating Based on POI Field.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Unit%20Field%20Populating%20Based%20on%20POI%20Field.png)

On Inquiry **"Robert"** (Name: Robert Plant, Company: Zeppelin):
- **Product of Interest** = **Brand Protection**.
- **Unit** field is **blank**, annotated by the tester: *"Should get populated as **Cyber** based on product of interest = brand protection."*

**Mapping rule captured:** `Product of Interest = Brand Protection ⇒ Unit = Cyber`. This confirms a one-way derivation: the Inquiry's **Unit** (business line / division picklist) should be auto-set from the selected Product(s) of Interest. Corroborated by the Abby/Jamf record where POI includes Brand Protection and **Unit = Cyber** is populated. The Robert Plant record shows the rule **not firing** when expected — a second defect/gap.
Other Robert Plant values: Inquiry Status New, Priority Hot, PCTA Type Demo, Email robplant374@gmail.com, Phone 876-543-210, Address Kentucky / United States.

### 4.3 Label defect — "Marketing Product" should read "Product of Interest"
Screenshot: [Marketing Product to Product of Interest.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Marketing%20Product%20to%20Product%20of%20Interest.png)

The **"Add Product of Interest"** pop-up (launched from the POI related-list **New** button) has a first field labeled **"Marketing Product"** (a `--None--` picklist). The tester **struck it through** and wrote the corrected label **"Product of Interest"** in red. So: rename the pop-up field label `Marketing Product` → `Product of Interest`.

Pop-up fields (the POI child-record create screen):
| Field | Type | Notes |
|---|---|---|
| ~~Marketing Product~~ → **Product of Interest** | Picklist (--None--) | label correction required |
| Notes | Long text | |
| Part of Original Request | Checkbox | distinguishes the originally-requested product vs. later add-ons |

Footer button: **Next** (multi-step pop-up / screen flow).

### 4.4 Marketing Product field label faintly rendered
In [Marketing Product Field on Campaign.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Marketing%20Product%20Field%20on%20Campaign.png) and the create pop-up, the **Marketing Product** label is partially obscured/struck with a red underline (tester marking the field to call attention to it, not necessarily a rendering bug). The lookup search placeholder reads **"Search Marketing Products…"** with a magnifier icon — confirming it is a lookup to a Marketing-Product source, not a free-text field.

### 4.5 POI "New" button → empty child list
Screenshots: [Products of Interest New Button.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20New%20Button.png) and [Products of Interest New Button 2.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20New%20Button%202.png)

- From an Inquiry (Abby Schoenecker), a dedicated **Products of Interest** related tab opens showing **"0 items · Updated a few seconds ago"** with a red-annotated **New** action — i.e., POI child records are created via this **New** button (which opens the §4.3 pop-up). The empty state persists, tying back to the §4.1 field-vs-list mismatch.

### 4.6 Layout cleanup directives (red X)
- **Planning** section → remove (red X, §2.3).
- **Activity** composer panel → remove (red X, §2.4).

### 4.7 In-scope confirmations (no defect)
- **View All Campaign Members** custom link present and highlighted as expected (§2.5).
- Campaign **Related** tab present and highlighted (§3.1).
- Campaign **Opportunities (8)** related list renders with expected columns (§3.2).
- Inquiry **Related** tab + Quick Links present (§3.3).

---

## 5. Picklist & enum values harvested (reusable)

| Object.Field | Values observed |
|---|---|
| Inquiry.Product of Interest (multi-select) | Brand Protection, Cloud Data Protection (semicolon-joined when multi: `Brand Protection;Cloud Data Protection`) |
| Inquiry.Unit | Cyber (derived from POI) |
| Inquiry.PCTA Type | Demo |
| Inquiry.Priority | Hot |
| Inquiry.Inquiry Status / Path | New, Pending Res(ponse), Assigned, Working, Closed, Converted |
| Campaign.Type | Email, Event |
| Campaign.Status | Completed, Sent (Sent seen on Campaign-History member rows) |
| Campaign.Campaign Currency | USD - U.S. Dollar |
| Opportunity.Sales Stage | 1- Pre-Qualified, 3- Evaluating, 11- Closed Lost |
| POI child.Part of Original Request | (boolean) |

**POI → Unit derivation rule:** `Brand Protection ⇒ Cyber` (only mapping explicitly stated; the full POI→Unit matrix is an open question, see below).

---

## 6. Connections to the SF RCA / Workday / MuleSoft implementation

- **Top-of-funnel, not RCA-priced.** This Campaign/POI/Inquiry layer sits *upstream* of the Quote/Order/RCA pricing engine documented in `FORTRA_KNOWLEDGE_BASE.md` and the project memories. POI/Marketing Product are **marketing-attribution & routing** constructs; they feed Inquiry → Opportunity conversion, not the pricing procedures (no `ExpressionSet`, `PriceBookEntry`, etc. involved here).
- **"Inquiry" = Lead rename** ties directly to the SC-3171 close-reason work (Lead labeled "Inquiry", Inquiry Status path New→…→Closed→Converted). The status path here matches that ticket's object.
- **Unit** is the same business-line concept used across Fortra (Cyber, etc.); auto-deriving it on the Inquiry seeds correct routing/territory and ultimately the Unit on downstream records.
- **Marketing Product vs. Product2.** The Campaign **Marketing Product** lookup searches "Marketing Products" — likely a curated marketing catalog object, NOT the full RCA `Product2` catalog. Confirm whether "Marketing Products" is a custom object, a filtered `Product2` lookup, or a separate `Marketing_Product__c`. (Open question.)
- **Legacy Id** on Campaign is the standard cross-system external key used throughout the D365/Tripwire SF/Globalscape SF → SF migration (consistent with the migration memories).
- **Workday/MuleSoft:** no direct interaction at this layer; these objects do not sync to Workday (financial back end) — they are pre-sale CRM only.

---

## 7. Open questions / ambiguities

1. **POI sync mechanism (the core bug):** Is the intended source of truth the **multi-select picklist** (`Inquiry.Product of Interest`) fanned out into child **Products of Interest** records, or the reverse (child records rolled up into the picklist)? §4.1 shows them desynchronized at (0) child vs. 2 picklist values — the automation that keeps them consistent is missing or broken.
2. **Full POI → Unit mapping matrix.** Only `Brand Protection ⇒ Cyber` is stated. Need the complete map (e.g., what Unit does "Cloud Data Protection" drive? does a multi-value POI resolve to one Unit or many?).
3. **What object backs "Marketing Products"?** Custom object vs. filtered `Product2` vs. `Marketing_Product__c` — and is `Campaign.Marketing Product` single-value while `Inquiry.Product of Interest` is multi-select intentional, or should they align?
4. **Pop-up "Next" flow:** the "Add Product of Interest" pop-up has a **Next** button (multi-screen flow) — the subsequent screens are not captured. What additional fields/steps follow?
5. **Layout-removal scope:** the red-X on **Planning** and **Activity** — confirm these are "remove from page layout" directives and not "out of scope for this screenshot."
6. **POI child object fields:** only Marketing Product/Product of Interest (picklist), Notes, Part of Original Request are seen on create. Full field set / object API name unknown.
7. **Label rename ownership:** confirm the `Marketing Product → Product of Interest` field-label change on the POI create pop-up was logged/fixed.

---

## Sources

All under `Fortra Discovery Documentation/BSI Discovery Info/UATScreenshots/` (read with vision — no `.txt` extracts exist for these PNGs):

- [Marketing Product Field on Campaign.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Marketing%20Product%20Field%20on%20Campaign.png)
- [Marketing Product Field on Campaign Creation Pop Up.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Marketing%20Product%20Field%20on%20Campaign%20Creation%20Pop%20Up.png)
- [Marketing Product to Product of Interest.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Marketing%20Product%20to%20Product%20of%20Interest.png)
- [Products of Interest New Button.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20New%20Button.png)
- [Products of Interest New Button 2.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20New%20Button%202.png)
- [Products of Interest Field and List Not Matching.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Products%20of%20Interest%20Field%20and%20List%20Not%20Matching.png) — confirmed bug
- [Unit Field Populating Based on POI Field.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Unit%20Field%20Populating%20Based%20on%20POI%20Field.png)
- [Related Tab on Campaign Object.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Related%20Tab%20on%20Campaign%20Object.png)
- [Related Opportunities on Campaign Object.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Related%20Opportunities%20on%20Campaign%20Object.png)
- [Related Tab on Inquiry Object.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Related%20Tab%20on%20Inquiry%20Object.png)
- [Activity Section on Campaign Object.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Activity%20Section%20on%20Campaign%20Object.png) — layout-removal (red X)
- [Planning Section on Campaign Object.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/Planning%20Section%20on%20Campaign%20Object.png) — layout-removal (red X)
- [View All Campaign Members Link.png](Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/UATScreenshots/View%20All%20Campaign%20Members%20Link.png)

**Not extractable:** none. The scoped extracted-text directory `Data/discovery-extract/text/BSI Discovery Info/UATScreenshots/` contains no `.txt` files (the source artifacts are PNG screenshots only); all 13 were read directly via vision from the original PNGs.
