# BSI Discovery — Tripwire TE License Management (Interim Phase)

> **Scope:** Three BSI (Business Systems & Innovation) discovery PDFs covering how **Tripwire Enterprise (TE)** on-premise licensing, software downloads, and support/maintenance entitlement are represented in the **legacy Tripwire Salesforce org** during the **interim phase** — i.e., before full migration to Salesforce Revenue Cloud Advanced (RCA), Workday, and MuleSoft. Two are deep R&D research/design notes by **Keith Irwin** (July 2023, with May 2024 addenda); the third is a "Phase 1 Support" field cheat-sheet for spinning up working test data in Salesforce.
>
> **Why this matters to the program:** Tripwire SF is one of the three legacy CRMs being consolidated onto RCA (alongside D365/Dynamics and Globalscape SF). Unlike the others, Tripwire carries a **standalone product-licensing apparatus** (the TE License Server + the Tripwire Community Center / TCC portal) that reaches into Salesforce **Asset** records to generate X.509 license certificates and to gate software/content downloads. These docs are the **as-built knowledge transfer** for that apparatus: what fields the License Server reads, the two competing license-data models (the old **LAC** system vs. the newer **Issued Product / Configuration / Configured Product** self-serve model), and the explicit design intent to **move the Salesforce-query logic out of the License Server and into Salesforce** so the server degrades to a pure certificate generator. The stated long game (User-Configurable doc, footnote 2) is that after Tripwire leaves Salesforce, **D365 — or a future portal — should be able to call the License Server unchanged via a simple HTTP/JSON request/response**, never querying the CRM directly.
>
> **Connection to the rest of the discovery KB:** This is the licensing/entitlement counterpart to the legacy-CRM field inventories in [12_globalscape-rlm-field-mappings.md](12_globalscape-rlm-field-mappings.md) and the D365 quoting/T&C docs. The "Create Assets" automation and the Support Start/Expiration date fields here are the entitlement basis that, in target state, becomes RCA **Asset / entitlement** + Workday revenue recognition. The X.509 cert generation is explicitly the **one piece that cannot move to Salesforce** (User-Configurable footnote 3).

---

## 0. Glossary (Tripwire-native terms)

| Term | Expansion | Meaning in these docs |
|---|---|---|
| **TE** | Tripwire Enterprise | On-premise change-monitoring / FIM (File Integrity Monitoring) product. Console + agents. |
| **TE console** | — | The on-premise software hub for the TE monitoring system. Each console needs its own license; not scalable beyond a few thousand nodes, so orgs buy **many** consoles. |
| **node** | — | A monitored server / network device / database / directory service. Each node monitored by an agent **also needs a license**. Selling TE = selling console software **plus** the right to monitor a quantity of a node type. |
| **TCC** | Tripwire Customer Center (a.k.a. Tripwire Community Center) | Customer-facing self-serve portal. Hosts the TE Licensing menu, downloads, license (re)distribution. |
| **LAC** | License Authorization Code | (1) A random string acting as a synthetic login identity to the TE License Server; (2) shorthand for the **old** asset-based license-management system. |
| **MSP** | Managed Service Providers | Mentioned as a term; not elaborated. |
| **TFS** | Tripwire for Servers | TE precursor product, still supported but **out of scope going forward** (see §2.1). |
| **Customer Ops** | (née **Order Admin**) | The team that manages license allocation in the old LAC system; sets up the parallel Issued Product/Configuration apparatus in the new system. |
| **Business Systems Support** | — | The team the User-Configurable doc wants to **own** the License Server once it runs on Salesforce-accessible infra. |
| **/generate2** | — | The new License Server REST endpoint. Accepts a JSON doc (host, version, features+quantities, cert name, expiry days) → returns a single concatenated X.509 license text file. |

---

## 1. Phase 1 Support — Required Salesforce Fields (test-data cheat-sheet)

**Source:** [Tripwire Salesforce Required Fields for Support-Download Maintenance.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Tripwire%20Salesforce%20Required%20Fields%20for%20Support-Download%20Maintenance.pdf)

This is a practical recipe: **the minimum Opportunity + Opportunity Line Item field set** that, when filled correctly, lets the **"Create Assets" automation** generate/update the Account's Asset records that in turn enable **(a) Support** and **(b) Product downloads / portal access**. It is framed as "Phase 1 Support" — interim test-data setup, not target schema.

### 1.1 Opportunity header fields

| Field Label | Field API | Type | Value to use | Notes |
|---|---|---|---|---|
| Opportunity Record Type | `RecordTypeId` | Picklist | **Direct Sales** | Default; "doesn't matter" for this purpose |
| Opportunity Currency | `CurrencyIsoCode` | Currency | **USD** | Use **JPY if Japan** |
| Opportunity Name | `Name` | Text | Anything | — |
| Account Name | `AccountId` | Lookup | (Id) | Must link to an account that **exists in the org** |
| Opportunity Type | `Type` | Picklist | **Add-On Business (Z1)** | — |
| Sales Stage | `StageName` | Picklist | **1 - PreQualified** | "Anything but none" |
| Forecast Category | `ForecastCategoryName` | Picklist | **Pipeline** | Default is fine |
| Close Date | `CloseDate` | Date | `<creation-date>` | Default to creation date is fine |
| Lead Source | `LeadSource` | Picklist | **Sales - Inbound** | "Anything by[sic] none" |

### 1.2 Opportunity Line Item fields

| Field Label | Field API | Type | Value to use | Notes |
|---|---|---|---|---|
| Product | `Product2Id` | Lookup(Product) | Product | **Must be the renewal variant of the SKU if the opportunity is a renewal** |
| Line Product | `Line_Product__c` | Lookup(Product) | Same product | If renewal, renewal variant; matches Product |
| Line Product Code | `Line_Product_Code__c` | Text | Same product's code | If renewal, renewal variant; matches Product |
| Sales Price | `UnitPrice` | Currency(16,2) | Any | **Non-zero** |
| Quantity | `Quantity` | Number(10,2) | Actual | **This matters for licensing** (drives node counts) |
| Support Start Date | `Support_Start_Date__c` | Date | Actual | — |
| Support Expiration Date | `Support_Expiration_Date__c` | Date | Actual | — |
| Asset | `Asset__c` | Lookup(Asset) | «Id» | **Renewal opportunities must match the existing asset** |
| Asset ID | `Asset_ID__c` | Text | «id» | **Renewal opportunities must match the existing asset** |

> **Support entitlement note:** `Support_Start_Date__c` and `Support_Expiration_Date__c` on the line are the support-contract window. In the LAC model these flow onto the Asset as **Support Start Date** and **Usage End Date** — the inclusive range that gates LAC access to the License Server (see §2.3). The naming differs by layer (OLI: "Support Expiration Date"; Asset: "Usage End Date").

### 1.3 Renewal SKU pattern (worked example)

If the Asset on the Account is **"Tripwire for Databases"** (code **`172310-00`**), then on a **renewal** Opportunity Line Item the Product must be the **Enterprise Support Renewal** variant:

| Base product | Base code | Renewal-variant product | Renewal code |
|---|---|---|---|
| Tripwire for Databases | `172310-00` | **Tripwire for Databases – Enterprise Support Renewal** | `172310-04` |

This is the concrete instance of the repeated rule "must be renewal variant of SKU if opportunity is renewal." The `-00` → `-04` suffix encodes the renewal/support variant.

### 1.4 The "Create Assets" automation & Asset IDs

- **Trigger:** correctly filled Opportunity + Opportunity Products → the **"Create Assets" automation** updates the Account's Assets.
- **Effect of created/updated Assets:** enables **Support** and **Product downloads / portal access** (i.e., TCC entitlement).
- **Asset ID caveat (operational risk):** for renewals you should supply the existing **Asset IDs**. If you cannot, "the staff on the Tripwire Salesforce side will need to be very experienced at resolving them correctly. **There are sometimes 100s of assets**" per customer — because each licensed capability is its own Asset (see §3.1). This is a flagged manual-resolution pain point.

---

## 2. The OLD License System — LAC (asset-based)

**Source:** [Salesforce • TE License — LAC Research Notes.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Salesforce%20%E2%80%A2%20TE%20License%20%E2%80%94%20LAC%20Research%20Notes.pdf) — Keith Irwin, 2023-07-11 (with **2024-05-04** addenda).

Document goal: give an implementer enough knowledge to **run the TE Licensing Server on Salesforce infrastructure** — everything **except the non-portable X.509 certificate generation**.

### 2.1 TFS disclaimer (out of scope)

Fortra still supports legacy **Tripwire for Servers (TFS)** customers and the current License Server *can* download TFS / generate TFS licenses, but **TFS is not a forward concern**. If it ever must be handled:
- Add **"product family"** to the fields collected per Asset to distinguish TFS from TE.
- For a TFS console: use the **"old" certificate designation**, provide **TFS files (no content)** for download, and use license version **`4.8`**.
- Otherwise: TFS questions go to **Tripwire Product Support**.

### 2.2 LAC vs. the "new system" (one-paragraph contrast)

- **LAC (old):** Customer Ops (née Order Admin) manually manages the allocation of product capabilities, license quantities, and hostnames per licensed TE console. Customers must **request changes through Customer Ops** — there is no self-serve.
- **New system:** Customer Ops generates **Issued Product** objects that *mirror* the Assets. Issued Products can be manipulated in the self-serve system **without touching the Asset records** — Assets must stay as-is **for proper revenue recognition** (the integration-critical constraint). The new model is fully described in §3.

### 2.3 Asset record fields used by the LAC system

In the LAC system, **every Asset record has `Type = 'lic'`** and carries the following custom fields (only `type = 'lic'` is of interest):

| Field (logical name) | Purpose / semantics |
|---|---|
| **LAC** | Randomly generated string the user presents to download software or generate a license. Also acts as a per-console synthetic login identity. |
| **Evaluation Days** | Number of days an evaluation license is valid. |
| **Type** | Asset type. Only `'lic'` is relevant here. |
| **Config ID** | Identifier of which **console** the Asset's licenses are assigned to. **Config ID ≙ a TE console.** |
| **Hostname** | Host name of the console; **must match the host on which TE is deployed** for the license to work. |
| **Product Code** | Partially semantic code indicating product kind (perpetual / time-limited / eval) — its **leading letters** are how license type is detected (see §2.5). |
| **Quantity** | Number of licenses available for the product this license represents. |
| **Support Start Date** | Support-contract start date. |
| **Usage End Date** | Support-contract end date. |
| **Product Reference** | The product capability purchased (e.g., TE for File Systems) plus the **feature codes** the TE software maps to licensed capabilities. |

**Grouping rule:** the license Asset records for an Account are a **flat list**. Grouping by **Config ID** (equivalently by **LAC** or **hostname**) yields the licenses granted to **one TE console**. Within a group: **same** Support Start Date, Usage End Date, LAC, hostname; **different** Quantity, Product Code, Product Reference per row (e.g., same console licensed for File System + Database + VMware ESX monitoring, each its own quantity).

**Feature path:** features are reached via `Asset.Product.Feature__c` (a comma-separated feature-tag list per product).

### 2.4 LAC lifecycle: download access vs. license generation (and the May-2024 change)

The LAC governs **access to the License Server**, which is distinct from whether a generated **TE license** is expired.

| License type | LAC website access window | Generated-license expiry |
|---|---|---|
| **Commercial Perpetual** | Today ∈ [Support Start Date, Usage End Date] inclusive; else "expired" | **36,500 days (100 years)** from generation date; never practically expires even if support lapses |
| **Commercial Time-Limited** | Same support-window rule (Product Code starts with `UsgCfg`) | Expires on the **Usage End Date** |
| **Evaluation** | *(Original 2023 rule)* 10 days from Support Start Date, regardless of Usage End Date. **2024-05-04 change:** eval LACs are now usable **up until the day the license expires** (same as commercial) | Expires on the **Usage End Date** (a long Usage End Date yields a long-lived eval license even after LAC login lapses) |

> **Decoupling principle (stated twice):** the date a *license* expires is not tied to when the *LAC* expires. A perpetual license generated while support was active lasts 100 years even after the customer stops paying for TE support/updates. The on-prem TE server **does not call home** to verify.

### 2.5 License-generation algorithm (LAC → /generate2)

This is the canonical "how to build a TE license" logic — currently run on the License Server, but documented so it can run **client-side in Salesforce** and POST a JSON doc to the License Server **`/generate2`** endpoint to receive the cert file back.

**Preconditions:** Assets matching the LAC have Support Start Date in the past, Usage End Date in the future; for an Eval license, also within 10 days of Support Start Date *(pre-2024-05-04 rule)*.

**Inputs the generator needs:**
1. Expiration in **days** (from generation date)
2. TE Console **host name** (e.g., `twapp01` — **no domain**)
3. TE Console **version** (e.g., `9.0.0`)
4. **Signing cert name** = `"current"` for TE
5. A list of **features + quantities** (e.g., `("FSI" 35) ("TWRouter" 5) …`)

**Step 1 — Query & group:** query all Asset records matching the user's LAC; group by **Config ID**. Each group = one console = the source data for one license.

**Step 2 — Determine license type** from a Product Code in the group:
- starts with **`E`** → **Evaluation**
- starts with **`UsgCfg`** → **Commercial Time-Limited**
- otherwise → **Commercial Perpetual**

**Step 3 — Number of days:**
- Perpetual → **36500** (skip the rest)
- Else → `days(Today → Usage End Date)`

**Step 4 — Features (pivot/aggregation):** scan every Asset + its Product, extract feature tags (`Asset.Product.Feature__c`), and **sum the license Quantity per feature tag** across all Assets in the group.

> Worked example from the doc:
> - Asset #1: qty 100, features `FSI,TWRouter` → `{FSI→100, TWRouter→100}`
> - Asset #2: qty 50, features `TWRouter,TWRouter-Policy` → `{FSI→100, TWRouter→150, TWRouter-Policy→50}`
>
> Continue until the table is built. The **TE License file = one X.509 cert per feature, all certs concatenated into a single text file.**

**Step 5 — Hostname:** pick the **first** hostname in the group (all should match). If none present, let the user supply one and update the Assets; **after that the hostname can only be changed via Support.**

**Step 6 — TE Version:** user-supplied (e.g., `9.0.0`, `8.6.0`).

**Output:** JSON request → `/generate2` on the new license server → single text license file, storable in Salesforce.

**Illustration in source (described, not a separate diagram needing vision read):** a perpetual console `ziocimm11` (no domain), support ending in 21 days, with 3 license Assets — `"Tripwire Enterprise Console - JA - License (TE)"` (the console itself) + two File-System capability Assets (features `FSI, FSI-Policy, FSI-Remediation`). The "Features" pivot totals each feature to 9 (`4 + 5`). The license is perpetual → never expires, but the LAC stops working after the support contract ends (July 31 in the example).

### 2.6 Downloads gated by license type

A customer with an **unexpired LAC** can download Tripwire software and **content** (rules/policies for config best-practice and vulnerability checks). **No paid apps.**

| License type | Software downloads | Content downloads |
|---|---|---|
| **Evaluation** | All downloads | **Only content with `"Sampler"` in the filename** |
| **Commercial Time-Limited / Perpetual** | All downloads | All content |

**Software Download Categories:** Console · TE Agents · TE Agent Updaters · Axon Agents · Axon Agent Updaters · Extras · Documents.

Content should be **searchable/filterable** the same way as on TCC: by **type, platform, framework**.

### 2.7 Existing TE License web app behavior (observed, mostly retired by 2024-05-04)

- Login = **LAC + email address**, stored in session; the email/LAC entered at login are reused when generating a license.
- A URL like `https://secure.tripwire.com/license/?lac=45303135333937AKlSRX` **pre-populates the LAC** into the login form but does nothing else automatically; an email is always required before any feature.
- UI offers **Generate License / Download Software / Download Policies** buttons, plus a bulleted link list and a "next" button.
- **Generate License** lists products + quantity + an expiry date for Eval/Time-Limited (**none shown for Perpetual**) and lets the user choose a TE product version before generating.
- Generated license is **emailed** to the login email and **NOT stored in Salesforce**.
- Downloads behave like TCC: each uses an **access token that times out after 30 minutes**; files live on the **CDN**.
- **2024-05-04 status:** the old service is *mostly retired*; the new site is **three pages linked by a `lac=<lac>` query-string parameter**. Improvement ideas: re-skin to match current TCC / Fortra branding; possibly condense to a single page (license details on top, tabbed downloads below, direct download for the license in addition to email).

---

## 3. The NEW (interim self-serve) System — User-Configurable TE License Management

**Source:** [Salesforce • TE License — User Configurable TE License Management.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Salesforce%20%E2%80%A2%20TE%20License%20%E2%80%94%20User%20Configurable%20TE%20License%20Management.pdf) — Keith Irwin, 2023-07-13.

### 3.1 Design goal & architecture shift

Port the current Tripwire Portal TE-licensing implementation to a **new License Server API** so that:
1. **License-info-gathering queries run inside Salesforce**, not on the License Server.
2. The super-slow TCC TE Licensing page gets **fast**.
3. **Customer Ops can use a variant** of the new TCC functionality on the rare occasions they need it.

**The big change:** instead of sending user/console IDs to the server and having the **server** look up Salesforce, Salesforce looks up everything the generator needs and sends it to the server, which returns a certificate. The server stops querying Salesforce, stops storing the cert, stops emailing it — **it becomes a pure X.509 certificate generator**. Salesforce then emails / saves / offers the cert for download.

**Stated rationale & footnotes (architecture intent for the program):**
- **[1]** Ownership of the standalone License Server is fuzzy (nominally R&D, always low priority); moving infra/automation into Salesforce lets **Customer Ops + SF Admins + Business Systems Support** fix issues without "trawling the company."
- **[1] (maintenance driver):** today, Rule/Policy file lists + software-update lists must be **republished with a new server build every month** (when someone remembers). Moving client interaction to Salesforce removes this — **Salesforce already knows about software and policy downloads.**
- **[2]** When the TE product business eventually **leaves Salesforce**, we want full requirements + example implementation in hand. **We do NOT want to update the License Server to query D365.** Instead, **D365 (or a future portal) should call the License Server unchanged via simple HTTP/JSON.** (Nor force D365 to handle product downloads.)
- **[3]** **X.509 certs cannot be generated on Salesforce** the way TE needs them — this is the single piece that *must* stay external.
- **[4]** Policy example: the software can detect if common accounts still use default passwords.

> **"You're just moving things around" — yes, deliberately.** Quote from source: *"We're moving the Salesforce parts to Salesforce and leaving the license generation part to the server."* Nothing functional changes; speed + maintainability are the gains.

### 3.2 TE product model (why licensing is shaped this way)

- TE console = on-prem server software managing a DB; receives change sets (via **Rules**) from agents/agent-proxies on remote **nodes**. Detects policy drift or tampering ("tripwire"); supports new baselines or security alerts.
- **Console needs a license; every monitored node also needs a license.** Selling TE = selling console software **+ the right to monitor a quantity of a node type.**
- A console isn't scalable past a few thousand nodes → orgs buy **many consoles** and **distribute capabilities** among them (e.g., DB + a few servers in Accounting on one console; VMs for cloud R&D on another). Customers buy a pool of (say) "database" licenses and **distribute them freely** across consoles.

### 3.3 The three-object self-serve data model

When a deal closes/renews, new **Asset** records are added to the Account. Tripwire Assets are dual-purpose: a traditional product (a console or installable add-on) **OR** an **unlocked capability** within a licensed console. Example:
- `Tripwire Enterprise Console` (software-download Asset — the console itself)
- `TE Database monitoring capability (100)` — 100 nodes
- `TE File System monitoring capability (900)` — 900 nodes
- `TE Directory Services monitoring capability (100)` — 100 nodes

(The number = nodes the customer may monitor under that capability; capability quantities can be **split across consoles**, e.g., 75/25 for DB monitoring.)

In parallel, **Customer Ops** sets up the license-generation apparatus — **three custom objects**:

| Object | API Name | Role | Cardinality |
|---|---|---|---|
| **Issued Product** | `Issued_Object__c` *(API name as written in source)* | Represents the **total pool** of a given product a customer has rights to (summed across Assets, over time). One per **non-console** Asset. | One per non-console product |
| **Configuration** | `Configuration__C` | Represents a **console** — holds a nickname, a network name, and a link to the **console Asset**. | One per TE console |
| **Configured Product** | `Configured_Product__c` | The **join** linking a Configuration (console) to an Issued Product, carrying the **assigned license number** (≤ available). This is what records **how licenses are divided among consoles**. | Many-to-many join |

> **Note on naming:** the docs flag that the object documentation for `Configured_Product__c` says it links "Configurations and Configured Products" — Keith marks this **"(sic)"** and corrects it to **"Configurations and Issued Products."** The Issued Product object's API name is recorded as **`Issued_Object__c`** (note the mismatch between label "Issued Product" and API `Issued_Object__c`).

Generated license files remain tied to a console by **hostname + product version + (feature tags + quantity)** — identical to the LAC mechanism (§2.5); only the data source changed from raw Assets to **Configured Products**.

### 3.4 Customer-user TCC portal interactions

TCC "TE Licensing" menu shows:
- A list of **consoles** (Configuration records)
- A list of **products with license counts** (Issued Product records)

**Click a console (Configuration):**
- Edit & save **nickname** inline.
- View/edit **hostname**, pick a **product version**, **generate a certificate** (emailed + a TCC download link).
- See each "product license" available to the customer with its license count (blank if none assigned to this console).
- You do **not** redistribute license numbers from the console view — you must click a **product** to redistribute.

**Click a product (Issued Product) → Edit License Assignments:**
- An **edit** button per product, with **assigned vs unassigned** quantities shown up front.
- Editor shows a **"From" console** + a **"To" console** + a **slider** for how many to move.
- If unassigned licenses exist, an **"Unassigned"** pseudo-console can be the From or To.
- Slider moves update the affected consoles' values live.
- **Apply** updates the Salesforce-side license definition; then open the console detail and **Generate** an updated license file.

**Conservation warning / abuse caveat (important for entitlement integrity):**
- Re-assignment only **rearranges** the DB; the total per Issued Product is conserved (can't over-assign one console).
- **BUT** the DB only stores **templates** for generating a license (plus the last generated cert, if any). **Whether a customer actually downloaded/deployed a license is not recorded.** What's actually loaded into a TE console is what matters.
- **Exploit:** move all FIM to console A, generate+deploy; move all FIM to console B (leaving A "empty"), generate+deploy — **doubling/tripling licensed capability**. A customer can buy one console + a quantity and replicate it across data centers. This **violates the contract**, but **nothing in the current system prevents it** — the on-prem TE server **does not call home** to verify quantities.

### 3.5 Query for console-specific licensing detail

Select **all Issued Products** and **all Configured Products** for a given **Configuration (console)**. List all Configured Products with quantities; then list any Issued Products **not** present in the Configured Products list with a **blank, grayed-out** quantity.

> Keith's caveat: unsure that listing **unused** features is necessary/helpful. If not needed, just query **Configured Products** — that's sufficient.

### 3.6 DB-side updates the portal performs (license redistribution)

The portal touches only **Configured Product** for redistribution between consoles (the **scope of one interaction = one Configured Product** create/update/delete). **Issued Product** is only touched when **unassigned** licenses are involved.

| Action | Configured Product effect | Issued Product effect |
|---|---|---|
| Move licenses console → console (both already have the product) | **Decrement** source CP, **increment** target CP | **None** (assigned total unchanged) |
| Move to a console that lacks that product type | **Create** a new CP linking Product↔Console with the qty | None |
| Remove **all** licenses of a product from a console | **Delete** the CP (no more link) | None |
| Remove some licenses from a console (to another console) | **Decrement** CP assigned | None |
| Add licenses to a console (from another console) | **Increment** CP assigned | None |
| Add an **Unassigned** license to a console | **Increment** CP assigned | **Increment** IP assigned |
| Move a license from a console **to the Unassigned bucket** | **Decrement** CP assigned | **Decrement** IP assigned |

> An Issued Product's **Available Licenses** is a **formula = Total License Quantity − Assigned Licenses**, so unassigned-license accounting only requires updating **Assigned Licenses** on the Issued Product.

### 3.7 Custom-object schema, fields & triggers (as documented)

**`Configured_Product__c` — links Console ↔ Product**
- Object doc: "Enables a many-to-many relationship between Configurations and Configured Products *(sic → Issued Products)* to represent the assignment of an issued product to a specific configuration."
- **Trigger:** if **assigned licenses = 0**, the Configured Product is **deleted**; then the trigger ensures that if exactly **one** console is linked to one Issued Product, **that console gets all** the licenses available from the Issued Product.

**`Configuration__C` — Console**
- Object doc: "Represents a console (to which issued products can be assigned)."
- **Trigger:** **cannot delete** the console while there's still an Asset representing the **console-license purchase** (the console itself, not features).
- **Guess (Keith, unverified):** deleting a **console-type Asset** likely fires a trigger that deletes this Configuration, which (cascade?) deletes the Configured Product, which re-calculates Issued Product values (licenses becoming available).

**`Issued_Object__c` (Issued Product) — Product**
- Object doc: "Represents the total quantity (or pool) for a given product that a customer has rights to based on purchases over time."

| Field | Type | Definition |
|---|---|---|
| **Total License Quantity** | Number(10,2) | Summed quantity across all Assets associated with this Issued Product. Maintained by **AssetRollup**. |
| **Assigned Licenses** | Number(10,2) | Licenses currently assigned to a configuration. Maintained by **ConfiguredProductRollUp**. |
| **Issued Product Count** | Formula = `1` | Asserts the IP represents one product (no field-def documentation). |
| **Available Licenses** | Formula = `Total License Quantity − Assigned Licenses` | Available licenses; **excludes evaluation records**. |

- **Triggers (code "hard to read", paraphrased):**
  - Delete the Issued Product if it is **no longer associated with an Asset**.
  - Delete the Issued Product if **Total License Quantity = 0**.
  - On a Total-License-Quantity **decrease**, update the related Configured Product (**if there's just one**) to match.

### 3.8 Database conclusions (per the doc)

Most automation around these objects exists to support **Customer Ops** updating the **total** licenses a customer has purchased (rollups, cleanup), **not** the portal's day-to-day **redistribution**. Portal redistribution: updates **Issued Product → Assigned Licenses** only when licenses leave/enter a console, and creates/updates/deletes **Configured Product** links per the user's add/update/remove. The triggers on Configuration/Configured Product/Issued Product are believed to be for **Customer Ops balancing**, **not** part of the TCC UI, and can **remain in place** when a new UI is ported on top of the customer portal. (Keith did **not** audit for additional process builders / workflows / flows / validations.)

---

## 4. Cross-system synthesis & how this maps to RCA / Workday / MuleSoft

| Discovery concept | Interim-phase representation (Tripwire SF) | Target-state / program implication |
|---|---|---|
| **Support/maintenance entitlement** | Asset Support Start Date / Usage End Date (OLI `Support_Start_Date__c` / `Support_Expiration_Date__c`); gates LAC access | Becomes RCA Asset/entitlement + support-renewal SKUs; "Create Assets" automation is the legacy analog of RCA asset lifecycle. **Assets must not be mutated by self-serve** (revenue-recognition constraint) — echoes the Globalscape/RLM rule that Asset state feeds Workday. |
| **License pool & distribution** | `Issued_Object__c` (pool) + `Configuration__C` (console) + `Configured_Product__c` (assignment) | A bespoke Tripwire-only model with **no obvious RCA-native equivalent**; open question whether RCA represents per-console capability distribution at all, or whether this stays a Tripwire-product-business concern that **leaves Salesforce** with the product line (footnote 2). |
| **License generation** | TE License Server `/generate2`, X.509 certs | **Stays external** (footnote 3); the design intent is to make it a stateless HTTP/JSON service callable by **any** future CRM/portal — conceptually a MuleSoft-style integration boundary, though MuleSoft is not named in these docs. |
| **Renewal SKU variants** | `-00` base → `-04` Enterprise Support Renewal (e.g., `172310-00` → `172310-04`) | Renewal-variant SKU discipline must carry into the RCA product catalog (see [09_products-catalog-hierarchy-and-skus.md](09_products-catalog-hierarchy-and-skus.md)). |
| **Multi-currency** | USD default; **JPY for Japan** on Opportunity `CurrencyIsoCode` | Tripwire is multi-currency in interim SF — relevant to the RCA multi-currency pricing work (cf. SC-3384). |

---

## 5. Open questions, ambiguities & gaps

1. **Object API-name confirmation.** Source records **`Issued_Object__c`** (label "Issued Product") and **`Configuration__C`** (note the capital `C` suffix as written). These are transcriptions from object documentation, not verified against the org — confirm exact API names/casing before any code references them.
2. **No field-level schema for `Configuration__C` / `Configured_Product__c`** beyond the assigned-license count and the console link. (Issued Product is the only object with a field table.) The nickname / network-name fields on Configuration are described prose-only.
3. **Trigger logic is paraphrased** ("the code is hard to read") — the Issued Product / Configured Product / Configuration triggers, AssetRollup, and ConfiguredProductRollUp need source inspection before any migration or refactor.
4. **No audit of process builders / flows / validation rules** around these objects (explicitly skipped by Keith).
5. **LAC-vs-new coexistence:** both systems read the same Assets but the new system mirrors them into Issued Products. Which is authoritative in the current production interim state, and whether both portals are live, is not stated.
6. **The entitlement-abuse gap** (§3.4) is a known, unmitigated business risk (license replication across consoles) — flagged but no remediation proposed; the TE server does not call home.
7. **"Phase 1 Support" scope:** the required-fields cheat-sheet is for test-data setup; it does not enumerate which automations beyond "Create Assets" must fire, nor the full Asset field set the automation writes.
8. **Currency precision:** the JPY note implies currency-specific handling (zero-decimal yen) that the OLI `UnitPrice` Currency(16,2) fields don't obviously accommodate — relevant to the SC-3384 multi-currency rendering concerns.
9. **MuleSoft / Workday are not named** in any of the three docs — the integration-layer mapping in §4 is inferred from program context, not stated by the source.

---

## Sources

All three are clean, fully text-extractable PDFs (no vision read required; the single "illustration" in the LAC doc is fully described in-text and contains no data not captured above).

| File | Author / Date | Used for |
|---|---|---|
| [Tripwire Salesforce Required Fields for Support-Download Maintenance.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Tripwire%20Salesforce%20Required%20Fields%20for%20Support-Download%20Maintenance.pdf) | (undated; "Phase 1 Support") | §1 — required Opportunity/OLI fields, renewal SKU, Create Assets automation |
| [Salesforce • TE License — LAC Research Notes.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Salesforce%20%E2%80%A2%20TE%20License%20%E2%80%94%20LAC%20Research%20Notes.pdf) | Keith Irwin, 2023-07-11 (2024-05-04 addenda) | §2 — LAC system, Asset fields, license-gen algorithm, downloads, web app |
| [Salesforce • TE License — User Configurable TE License Management.pdf](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/TripwireInterimPhaseWork/Salesforce%20%E2%80%A2%20TE%20License%20%E2%80%94%20User%20Configurable%20TE%20License%20Management.pdf) | Keith Irwin, 2023-07-13 | §3 — Issued Product/Configuration/Configured Product model, portal UX, triggers |

*Extracted-text copies read in full at:* `/Users/liamjeong/Documents/Code/Fortra/Data/discovery-extract/text/BSI Discovery Info/TripwireInterimPhaseWork/*.txt`

**Not extractable / empty / encrypted in scope:** none — all three files extracted cleanly and were read in full.
