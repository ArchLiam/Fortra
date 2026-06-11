# BSI Discovery — D365 Entity Junctions & FortraUAT Role Changes

**Scope:** Two BSI (Business Systems & Innovation) discovery spreadsheets at the top level of `BSI Discovery Info/`:
- [D365EntityJunctions.xlsx](Fortra Discovery Documentation/BSI Discovery Info/D365EntityJunctions.xlsx) — the legacy Dynamics 365 (D365 / CRM) N:N junction-entity map, annotated with BSI migration notes about whether each junction is still needed in Salesforce Revenue Cloud Advanced (RCA).
- [FortraUATRoleChanges.xlsx](Fortra Discovery Documentation/BSI Discovery Info/FortraUATRoleChanges.xlsx) — the Salesforce **Role Hierarchy** to be stood up in the FortraUAT org, the parent/child role wiring, and the role-consolidation rename map ("Changes Made").

**Why this matters for the build:**
- The **junction map** is the source-of-truth inventory of D365 N:N relationships that the data-migration team must decide to (a) re-create as Salesforce junction objects / lookups, (b) replace with native RCA constructs, or (c) drop. BSI has already pre-annotated several as "may not be needed in RCA" / "will be very different in the new portal."
- The **role hierarchy** is the Salesforce **Role** (`UserRole`) record-access model for UAT — not profiles or permission sets. It collapses the old brand-prefixed D365 roles (Cyber* / Tech*) into a single shared hierarchy. This drives record visibility (Owner-based sharing roll-up) for Accounts, Opportunities, Quotes, Orders, etc.

> Connection to the design KB: `FORTRA_KNOWLEDGE_BASE.md` covers the target RCA design. This discovery doc is the **legacy-source inventory** (D365 junctions) + the **UAT security skeleton** (roles) that feed that design. The two brands referenced throughout are **Cyber** (security portfolio) and **Tech** (Automation / MFT / Power portfolios), each previously running parallel role trees that are now being merged.

---

## Part 1 — D365 Entity Junction / Relationship Map

Source: `D365EntityJunctions.xlsx`, `Sheet1` (18 rows × 4 columns). Each row is one D365 **junction entity** (the intersect table that materializes a many-to-many relationship). The `hs_` prefix is Fortra's legacy "HelpSystems" Dynamics publisher prefix; `hsp_` is the portal variant.

Columns in source:
- **BSI Notes** — purpose of the junction + BSI's migration commentary.
- **entitylogicalname** — the D365 junction entity's logical name.
- **RelatedEntities** — the entities the junction connects (the "ends" of the N:N).
- **LookupFields** — the actual lookup field API names on the junction that point to those entities.

### 1.1 Junction inventory (full table)

| # | Junction entity (`entitylogicalname`) | Connects (RelatedEntities) | Lookup fields | Purpose | BSI migration note |
|---|---|---|---|---|---|
| 1 | `hs_accountproductfamily` | account, product | `hs_account`, `hs_productfamily` | Junction between **hierarchy products and accounts**. High-level "what a customer owns" without scanning every owned product. | **(more recent)** — the modern product-hierarchy approach. Likely maps to an Asset / owned-product roll-up in RCA. |
| 2 | `hs_accountproductgroups` | account, hs_productline, hs_productbrand, account, hs_softwareproductmaster | `hs_account`, `hs_currentproductdownloadset`, `hs_productbrand`, `hs_reseller`, `hs_softwareproductmaster` | Junction between **Software Product Masters** + account. Same "what a customer owns" summary. | **(legacy, but still used.** The relationships used before a true product hierarchy existed.) Superseded by #1 but live data still present. |
| 3 | `hs_associatedcompetitor` | hs_brandaccount, competitor, contact | `hs_brandaccount`, `hs_competitor`, `hs_pointofcontact` | Junction between one or more predefined **competitor** and account. | Competitor tracking; maps to Opportunity Competitor / custom junction in SF. |
| 4 | `hs_associatedcontact` | account, hs_brandaccount, contact, hs_productbrand, organization | `hs_account`, `hs_brandaccount`, `hs_contact`, `hs_productbrand`, `organizationid` | Junction between **contacts and related accounts**. Defines **persona, role, and key attributes**. | Closest SF analog = `AccountContactRelation` (Contacts-to-Multiple-Accounts) with role + persona fields. |
| 5 | `hs_associatedpartner` | invoice, lead, opportunity, salesorder, account, quote | `hs_invoiceid`, `hs_leadid`, `hs_opportunityid`, `hs_orderid`, `hs_partnerid`, `hs_quoteid` | Junction between **partner account and lead through invoice**. Defines one or more partners, their **role**, and **primary billing**. | High-value: this is the **partner-on-transaction** model (partner role + primary-billing flag across Lead/Opp/Quote/Order/Invoice). Connects to channel-partner pricing & billing design. |
| 6 | `hs_caseansweroptiondefinition` | hs_casequestiondefinition, organization | `hs_casequestiondefinition`, `organizationid` | Support-portal **dynamic question** answer options. | Part of the dynamic-question case-intake set (#6/#7/#8). Support-portal feature — "will probably be very different in the new Fortra Salesforce portal." |
| 7 | `hs_casequestionanswerresponse` | hs_casequestioncriteria, incident, hs_casequestiondefinition | `hs_casequestioncriteria`, `hs_incident`, `hs_question` | Captured **answer responses** on a case (`incident`). | Same dynamic-question set; `incident` = D365 Case. |
| 8 | `hs_casequestioncriteria` | hs_casequestiondefinition, hs_caseansweroptiondefinition, product, hs_casequestiondefinition, subject, organization | `hs_parentquestion`, `hs_parentquestionsoptionanswer`, `hs_product`, `hs_question`, `hs_subject`, `organizationid` | **Branching logic**: "next question" determined by prior answer; questions vary by product selected. | Self-referencing (parent question + parent answer) decision-tree on Case intake by Product + Subject. |
| 9 | `hs_opportunityproductsummary` | opportunity, product, transactioncurrency | `hs_opportunity`, `hs_productfamily`, `transactioncurrencyid` | Junction between **hierarchy products and opportunities**. Summarizes multiple product lines on an Opp (name + total value), built from individual opportunity product lines. | Roll-up summary by product family per Opp; currency-aware. Maps to Opportunity-level product roll-up in SF. |
| 10 | `hs_portalswitcheraccount` | account, contact | `hs_account`, `hs_contact` | Junction between **accounts used for partner-portal access**. Relates accounts so a partner, when logged into the Partner Portal, can select to see related records from other accounts. | **"I don't think this is needed in the new portal."** — candidate to drop in RCA Experience Cloud portal. |
| 11 | `hs_productbundlepriceditem` | product, product, organization | `hs_bundleproduct`, `hs_lineproduct`, `organizationid` | **Bundle definitions** in D365 / **Experlogix**. Self-junction product→product (bundle product → line product). | **"May not be needed in RCA"** — RCA native bundle/component model likely replaces Experlogix bundles. |
| 12 | `hs_productsofinterest` | campaignresponse, lead, opportunity, product, hs_productmaster, hs_softwareproductmaster | `hs_campaignresponse`, `hs_lead`, `hs_opportunity`, `hs_product`, `hs_productmaster`, `hs_softwareproduct` | Junction between **Product Masters and leads/opps** (+ campaign responses). | Marketing/sales "products of interest" tagging across Campaign Response, Lead, Opp. Connects to lead-flow / attribution design. |
| 13 | `hs_projectcontact` | contact, hs_projects | `hs_contact`, `hs_project` | Junction between **contacts and projects**. Defines multiple customer contacts involved in a project. | Maps to PSA / project-contact roles (relates to Services Project Hours reporting). |
| 14 | `hs_team_members` | account, hs_productbrand, systemuser | `hs_account`, `hs_productbrand` | Junction between **users and accounts**. Defines **Fortra roles on an account** — Account Executive, CSM Manager, etc. | Internal account-team model **per product brand**. SF analog = `AccountTeamMember` (with a brand dimension). Ties directly to the role hierarchy in Part 2. |
| 15 | `hsp_downloadpage` | product, hs_productbrand, hsp_downloadpage | `hs_portalproduct`, `hs_productbrand`, `hs_samedownloadsetsas` | Defines **how downloads are shown / made available** in the customer portal. Self-referencing (`hs_samedownloadsetsas`). | **"This will probably be very different in the new Fortra Salesforce portal."** Portal download model. |
| 16 | `hs_downloadlinkintersect` | hsp_downloadpage, hsp_downloadpagelink | `hs_downloadpage`, `hs_downloadpagelink` | Junction tying **download pages to download links**. | Same portal-download set — likely rebuilt in SF portal. |
| 17 | `hs_portalproductbranddownloadpagelinks` | hsp_downloadpage, hs_productbrand | `hs_downloadpage`, `hs_productbrand` | Junction tying **download pages to product brands** for portal links. | Same portal-download set — likely rebuilt in SF portal. |

> Note on `RelatedEntities` vs `LookupFields`: counts don't always align 1:1 because some lookups are **polymorphic** (e.g. `hs_associatedcontact.hs_account` vs `hs_brandaccount` both resolve to account-type entities) or are platform fields (`organizationid`, `transactioncurrencyid`). The `account` entity appears twice for rows #2 and #4, reflecting two distinct account-typed lookups on the same junction (e.g. account + brand-account).

### 1.2 Thematic groupings (for migration planning)

| Theme | Junctions | RCA disposition signaled by BSI |
|---|---|---|
| **Owned-product / "what a customer owns"** | `hs_accountproductfamily` (#1, current), `hs_accountproductgroups` (#2, legacy) | #1 is the modern hierarchy approach; #2 predates the product hierarchy but data still in use. Migrate to RCA Asset / owned-product roll-up; reconcile the two. |
| **Partner-on-transaction** | `hs_associatedpartner` (#5) | Keep — drives partner role + primary-billing across Lead→Opp→Quote→Order→Invoice. Core to channel pricing/billing. |
| **Account relationships / personas** | `hs_associatedcontact` (#4), `hs_team_members` (#14), `hs_projectcontact` (#13), `hs_portalswitcheraccount` (#10) | #4 → AccountContactRelation; #14 → AccountTeamMember (brand-aware); #13 → project contacts; #10 likely dropped. |
| **Competitor tracking** | `hs_associatedcompetitor` (#3) | Map to Opportunity competitor / custom junction. |
| **Product interest / marketing** | `hs_productsofinterest` (#12) | Lead/Opp/Campaign product tagging — connects to lead-flow KB. |
| **Opp product summary** | `hs_opportunityproductsummary` (#9) | Currency-aware product-family roll-up per Opp. |
| **Bundles / Experlogix** | `hs_productbundlepriceditem` (#11) | "May not be needed in RCA" — native RCA bundles likely replace. |
| **Dynamic case intake (support portal)** | `hs_caseansweroptiondefinition` (#6), `hs_casequestionanswerresponse` (#7), `hs_casequestioncriteria` (#8) | Portal feature — "will probably be very different." Decision-tree question routing by Product + Subject. |
| **Customer-portal downloads** | `hsp_downloadpage` (#15), `hs_downloadlinkintersect` (#16), `hs_portalproductbranddownloadpagelinks` (#17) | "Very different in the new Fortra Salesforce portal." Rebuild, don't lift-and-shift. |

### 1.3 D365 → reference entity glossary (logical names seen)

| D365 logical name | Meaning |
|---|---|
| `account` | Account |
| `contact` / `hs_contact` / `hs_pointofcontact` | Contact |
| `hs_brandaccount` | Brand-scoped account variant |
| `hs_productbrand` | Product **Brand** (Cyber vs Tech, etc.) |
| `hs_productline` | Product Line |
| `hs_productfamily` | Product Family (hierarchy node) |
| `product` / `hs_product` / `hs_portalproduct` | Product |
| `hs_productmaster` / `hs_softwareproductmaster` (`hs_softwareproduct`) | Software Product Master |
| `hs_currentproductdownloadset` | Current product download set |
| `hs_reseller` / `hs_partnerid` | Reseller / partner account |
| `lead` / `hs_leadid`, `opportunity` / `hs_opportunity[id]`, `quote` / `hs_quoteid`, `salesorder` / `hs_orderid`, `invoice` / `hs_invoiceid` | Sales transaction objects |
| `campaignresponse` / `hs_campaignresponse` | Campaign Response |
| `competitor` / `hs_competitor` | Competitor |
| `incident` / `hs_incident` | Case |
| `subject` / `hs_subject` | Subject (case taxonomy) |
| `hs_projects` / `hs_project` | Project |
| `systemuser` | User |
| `organization` / `organizationid` | D365 org/tenant (platform) |
| `transactioncurrency` / `transactioncurrencyid` | Currency (platform) |

---

## Part 2 — FortraUAT Role Changes (Salesforce Role Hierarchy)

Source: `FortraUATRoleChanges.xlsx`, three sheets:
- **Role Hierarchy** (92 rows × 2 cols) — flat list of every role with its **depth Level** (0 = top).
- **Roles** (93 rows × 2 cols) — explicit **Parent Role → Role** edges (the actual `UserRole.ParentRoleId` wiring).
- **Changes Made** (24 rows × 2 cols) — the **rename/consolidation map**: old D365 brand-prefixed roles → the new shared UAT role they're replaced with.

> This is the **Role** (record-access) model, NOT profiles/permission sets. Visibility rolls **up** the hierarchy (a parent role sees subordinate-owned records). The headline change is **de-branding**: separate `Cyber *` and `Tech *` roles for the same function are merged into one shared role, except where the brand split is genuinely operational (Sales: `Cyber ELT` vs `Tech ELT`, Marketing channel users, Customer Operations).

### 2.1 Role consolidation map ("Changes Made")

These 23 mappings are the active UAT changes — old assigned role → new replacement role. (Note source typos preserved verbatim, e.g. "Mananger", "Excecutive".)

| Currently Assigned Role (old / D365) | New Role to Replace it With (UAT) | Nature of change |
|---|---|---|
| Cyber Sales ELT | **Cyber ELT** | Drop "Sales" word |
| Cyber Sales Operations | **Sales Operations** | De-brand → shared |
| Cyber Services Leadership w/ Full PS cloud | **Services Leadership** | De-brand → shared |
| Tech Sales  ELT | **Tech ELT** | Drop "Sales" word |
| Tech Sales Operation | **Sales Operations** | De-brand → shared (merges with Cyber's) |
| Cyber Excecutive Ops | **Sales Executive Ops** | De-brand → shared |
| Tech Executive Op | **Sales Executive Ops** | De-brand → shared (merges with Cyber's) |
| Cyber CX ELT | **CX ELT** | De-brand → shared |
| Tech CX ELT | **CX ELT** | De-brand → shared (merges) |
| Cyber CSM (Customer Success Manager) | **CSM (Customer Success Manager)** | De-brand |
| Cyber CSM Mgr (Customer Success Manager) | **CSM Mgr (Customer Success Manager)** | De-brand |
| Cyber Customer Operations (Orders) | **Customer Operations (Orders)** | De-brand |
| Cyber CX Excecutive Ops | **CX Excecutive Ops** | De-brand (note: target name differs from final hierarchy's "CX Executive Ops") |
| Cyber Professional Services Manager | **Professional Services Mananger** | De-brand → shared (sic "Mananger") |
| Tech Professions Services Manager | **Professional Services Mananger** | De-brand → shared (merges; sic "Professions"/"Mananger") |
| Cyber Technical Support Leadership | **Technical Support Leadership** | De-brand → shared |
| Tech Technical Support Leadership | **Technical Support Leadership** | De-brand → shared (merges) |
| Cyber Marketing Operations | **Marketing Operations** | De-brand → shared |
| Tech Marketing Operations | **Marketing Operations** | De-brand → shared (merges) |
| Cyber Marketing Operations Admin | **Marketing Operations Admin** | De-brand → shared |
| Tech Marketing Operations Admin | **Marketing Operations Admin** | De-brand → shared (merges) |
| Cyber CX | **CX** | De-brand → shared |
| Tech CX | **CX** | De-brand → shared (merges) |

**Pattern:** the consolidation removes the brand prefix for **shared corporate functions** (Sales Ops, Services Leadership, CX, CSM, Customer Operations, Professional Services, Technical Support Leadership, all Marketing). It **retains** a brand split only for the top of each go-to-market tree (`Cyber ELT` / `Tech ELT`) and the brand-specific marketing/channel/customer-ops leaf roles that still appear in the final hierarchy (e.g. `Cyber Channel Marketing`, `Tech Channel Marketing`, `Cyber Product Management`, `Tech Product Management`).

> Data-quality flags for the build: (1) "Cyber CX Excecutive Ops → **CX Excecutive Ops**" but the Role Hierarchy sheet spells the live role **"CX Executive Ops"** — confirm the canonical API name before creating the role. (2) "Professional Services **Mananger**" is the consolidation target but the hierarchy/Roles sheets use "Professional Services Manager**s**" (plural). Reconcile to one exact label. (3) "Tech Sales  ELT" / "Cyber Sales ELT" have inconsistent spacing.

### 2.2 Role hierarchy with levels (full)

From the **Role Hierarchy** sheet. Level 0 = System Admin at the top; larger numbers are deeper/more-subordinate. (Levels here are the spreadsheet's stated depth labels; they generally—but not perfectly—track the Parent→Role edges in §2.3, which are authoritative for actual `ParentRoleId` wiring.)

| Level | Roles at this level |
|---|---|
| 0 | System Admin |
| 1 | Executive Leadership Team |
| 2 | CX ELT; Cyber Product Management; Marketing Operations Admin; Sales ELT; Tech Product Management |
| 3 | CSM (Customer Success Manager); CSM Mgr (Customer Success Manager); CX; CX Executive Ops; Customer Operations (Orders); Cyber Customer Operations (Renewal) Mgr; Cyber Managed Solution Services; Cyber Services Leadership w/ Full PS cloud; Professional Services Managers; Services Leadership; Tech Customer Operations Leadership; Technical Support Leadership; Marketing Operations; Sales Executive Ops |
| 4 | Cyber Customer Operations (Renewal); Consultant; Services Coordinator; Tech Managed Solution Services; Tech Customer Operations (Orders/Keys); Tech Customer Operations (Renewal); Technical Support; Technical Support - Elevated; Cyber Channel Marketing; Cyber Marketing User; Tech Channel Marketing; Tech Marketing User; Sales Operations |
| 5 | Cyber ELT; Tech ELT |
| 6 | Cyber Sales; Tech Sales |
| 7 | Americas Manager; Cyber BD Leadership; Cyber Channel Leadership; EMEA/APAC Manager; Offensive Security Manager; Strategic Verticals Manager; Automation Manager; MFT Manager; Power Manager; Tech CX ELT (Reports to Executive Leadership Team); Tech Channel Leadership; Tech Customer Experience (CX) Organization; Tech Sales Executive Ops |
| 8 | Central Manager; North Manager; Northeast Manager; South Manager; Southeast Manager; West Manager; Cyber BDR/ISR; Cyber Channel Director; Cyber Channel Program & Ops; APAC Manager; EMEA East Manager; EMEA West Manager; MEFDACH Manager; UK Manager; Offensive Security AE; FinServ Manager; Public Sector Manager; Strategic Accounts Manager; Automation AE; MFT AE; Power AE; Tech Channel Manager/Director |
| 9 | Central AE; North AE; Northeast AE; South AE; Southeast AE; West AE; Cyber Channel Account Managers; APAC AE; EMEA East AE; EMEA West AE; MEFDACH AE; UK AE; FinServ AE; Public Sector AE; Strategic AE; LATAM Manager; Tech Channel Account Managers |
| 10 | LATAM AE |

**Total: 91 named roles** (the sheet's 92 rows include the header). Special entry: `fadmi Partner Person Account` (a partner person-account role) appears in the **Roles** edges sheet under `System Admin` but is not in the leveled list.

### 2.3 Parent → Role edges (authoritative wiring)

From the **Roles** sheet (`UserRole.ParentRoleId` map). Grouped by parent for readability. The root has an **empty parent** (`(none) → System Admin`).

| Parent Role | Child Role(s) |
|---|---|
| *(none / root)* | System Admin |
| System Admin | Executive Leadership Team; **fadmi Partner Person Account** |
| Executive Leadership Team | CX ELT; Cyber Product Management; Marketing Operations Admin; Sales ELT; Tech Product Management |
| CX ELT | CSM (Customer Success Manager); CSM Mgr (Customer Success Manager); Customer Operations (Orders); CX; CX Executive Ops; Cyber Customer Operations (Renewal) Mgr; Cyber Managed Solution Services; Services Leadership; Cyber Services Leadership w/ Full PS cloud; Professional Services Managers; Technical Support Leadership; Tech Customer Operations Leadership |
| CX | Cyber Customer Operations (Renewal) |
| Services Leadership | Consultant; Services Coordinator; Tech Managed Solution Services |
| Technical Support Leadership | Technical Support; Technical Support - Elevated |
| Tech Customer Operations Leadership | Tech Customer Operations (Orders/Keys); Tech Customer Operations (Renewal) |
| Marketing Operations Admin | Marketing Operations |
| Marketing Operations | Cyber Channel Marketing; Cyber Marketing User; Tech Channel Marketing; Tech Marketing User |
| Sales ELT | Sales Executive Ops |
| Sales Executive Ops | Sales Operations |
| Sales Operations | Cyber ELT; Tech ELT |
| Cyber ELT | Cyber Sales |
| Cyber Sales | Americas Manager; Cyber BD Leadership; Cyber Channel Leadership; EMEA/APAC Manager; Offensive Security Manager; Strategic Verticals Manager |
| Americas Manager | Central Manager; North Manager; Northeast Manager; South Manager; Southeast Manager; West Manager |
| Central Manager | Central AE |
| North Manager | North AE |
| Northeast Manager | Northeast AE; North AE *(also)* |
| South Manager | South AE |
| Southeast Manager | Southeast AE; South AE *(also)* |
| West Manager | West AE |
| Cyber BD Leadership | Cyber BDR/ISR |
| Cyber Channel Leadership | Cyber Channel Director; Cyber Channel Program & Ops |
| Cyber Channel Director | Cyber Channel Account Managers |
| EMEA/APAC Manager | APAC Manager; EMEA East Manager; EMEA West Manager; MEFDACH Manager; UK Manager |
| APAC Manager | APAC AE |
| EMEA East Manager | EMEA East AE |
| EMEA West Manager | EMEA West AE |
| MEFDACH Manager | MEFDACH AE |
| UK Manager | UK AE |
| Offensive Security Manager | Offensive Security AE |
| Strategic Verticals Manager | FinServ Manager; Public Sector Manager; Strategic Accounts Manager |
| FinServ Manager | FinServ AE |
| Public Sector Manager | Public Sector AE |
| Strategic Accounts Manager | LATAM Manager; Strategic AE |
| LATAM Manager | LATAM AE |
| Tech ELT | Tech Sales |
| Tech Sales | Automation Manager; MFT Manager; Power Manager; Tech Channel Leadership; Tech Customer Experience (CX) Organization; Tech CX ELT (Reports to Executive Leadership Team); Tech Product Management *(see note)*; Tech Sales Executive Ops |
| Automation Manager | Automation AE |
| MFT Manager | MFT AE |
| Power Manager | Power AE |
| Tech Channel Leadership | Tech Channel Manager/Director |
| Tech Channel Manager/Director | Tech Channel Account Managers |

> **Note / ambiguity:** "Tech Product Management" has two parent edges in the source — `Executive Leadership Team → Tech Product Management` (line in Roles sheet) — and the level-2 listing also places it under ELT. A role can have only one `ParentRoleId`; ELT is the correct parent. Where the Roles sheet lists a child under `Tech Sales` that is also rooted elsewhere, treat the **Roles** sheet edge as the build instruction and reconcile the few apparent doubles (Northeast/North AE, Southeast/South AE doubles) — these AEs each report to two manager regions in the sheet, which is **not valid in a Salesforce role hierarchy** (single parent only). See open questions.

### 2.4 Structural observations for the SF admin

- **Single root:** `System Admin` (Level 0) is the apex; `Executive Leadership Team` sits directly beneath it. All record visibility ultimately rolls up to System Admin.
- **Four functional pillars under ELT:** (1) **CX ELT** (Customer Experience — support, CSM, customer operations, services), (2) **Sales ELT** (the entire GTM sales tree), (3) **Marketing Operations Admin** (marketing), (4) **Product Management** (Cyber + Tech, kept brand-split).
- **Sales tree is deep (Level 5→10):** `Sales Operations → {Cyber ELT, Tech ELT} → {Cyber Sales, Tech Sales} → regional managers → AEs`. Cyber sells by **geography + specialist verticals** (Americas regions, EMEA/APAC regions, Offensive Security, Strategic Verticals: FinServ / Public Sector / Strategic Accounts / LATAM). Tech sells by **product line** (Automation, MFT, Power) plus channel.
- **Brand split preserved only where operational:** Cyber vs Tech remain separate at ELT/Sales, in Marketing leaf roles (Channel Marketing / Marketing User), Customer Operations leaves, Managed Solution Services, and Product Management. Everything corporate-shared was de-branded (§2.1).
- **Deepest path = LATAM AE at Level 10:** System Admin → ELT → Sales ELT → Sales Executive Ops → Sales Operations → Cyber ELT → Cyber Sales → Strategic Verticals Manager → Strategic Accounts Manager → LATAM Manager → LATAM AE.
- **Partner role:** `fadmi Partner Person Account` is parented directly under System Admin (partner-facing person-account role, likely for the Experience Cloud partner portal — connects to the partner-portal / deal-registration design and to the `hs_associatedpartner` junction in Part 1).

---

## Cross-references & connections to the RCA / Workday / MuleSoft build

- **Data migration (junctions → SF):** Part 1 is the canonical list of D365 N:N relationships migration must triage. High-priority keeps: `hs_associatedpartner` (partner-on-transaction + primary billing), `hs_accountproductfamily`/`hs_accountproductgroups` (owned-product roll-up → RCA Assets), `hs_team_members` (→ AccountTeamMember). Likely drops/rebuilds: all portal download junctions (#15–17), `hs_portalswitcheraccount` (#10), Experlogix bundles (#11). Dynamic-case-intake set (#6–8) is a support-portal redesign decision.
- **Security model:** Part 2 supplies the `UserRole` hierarchy for the FortraUAT org. It is record-access only; profiles and permission sets (e.g. the DocGen / RLM permission sets covered elsewhere in the design KB) are layered separately. The de-branding consolidation reduces the role count and must be applied as renames/merges, not net-new roles, to preserve existing user-to-role assignments where the name is unchanged.
- **Brand dimension recurs:** `hs_productbrand` appears across junctions #2, #4, #14, #15, #17 and the role hierarchy's Cyber/Tech split — Brand is a first-class dimension in both the legacy data model and the new security model. The RCA build should confirm how Brand is represented (record type, field, or business unit) so junction migration and role visibility align.
- **Partner billing:** `hs_associatedpartner.hs_partnerid` + its "primary billing" semantics tie directly to the partner-pricing / quote-billing models documented in the channel-partner and quotes-billing discovery docs.

---

## Open questions / ambiguities

1. **Invalid double-parent AEs:** In §2.3 the Roles sheet gives `North AE` two parents (North Manager **and** Northeast Manager) and `South AE` two parents (South Manager **and** Southeast Manager). A Salesforce role has exactly one `ParentRoleId`. Which manager is the true parent for North AE and South AE? (Likely a source data error; confirm before loading.)
2. **Label/spelling reconciliation:** "CX Excecutive Ops" (Changes Made target) vs "CX Executive Ops" (hierarchy); "Professional Services Mananger" (Changes Made) vs "Professional Services Managers" (hierarchy/Roles). Establish the one canonical role label/API name per role before creating in UAT.
3. **`fadmi Partner Person Account`** — purpose, who is assigned, and whether more partner roles are expected for the Experience Cloud partner portal. Not in the leveled list; only in the edges sheet.
4. **Junction dispositions are advisory, not decided:** BSI notes say several junctions "may not be needed" / "probably very different" (#10, #11, #15–17, and the case-intake set). The actual keep/replace/drop decision per junction is not recorded here — needs a migration-mapping sign-off.
5. **`RelatedEntities` vs `LookupFields` mismatches:** rows #2, #4, #5, #8, #12 list more entities than clean lookups (polymorphic / platform fields). The exact target-object mapping per lookup needs verification against the live D365 metadata before building SF equivalents.
6. **No profile/permission-set detail:** despite the file name "Role Changes," the workbook contains only the **Role hierarchy**. Profile and permission-set assignments for UAT are out of scope of this file and must come from another source.
7. **Level vs edge discrepancies:** the stated "Level" column and the Parent→Role edges don't perfectly agree for a few roles (e.g. Tech Product Management). Treat the **Roles** (edges) sheet as authoritative for `ParentRoleId`.

---

## Sources

- [BSI Discovery Info/D365EntityJunctions.xlsx](Fortra Discovery Documentation/BSI Discovery Info/D365EntityJunctions.xlsx) — extracted text: `Data/discovery-extract/text/BSI Discovery Info/D365EntityJunctions.xlsx.txt` (Sheet1, 18r × 4c). Read in full.
- [BSI Discovery Info/FortraUATRoleChanges.xlsx](Fortra Discovery Documentation/BSI Discovery Info/FortraUATRoleChanges.xlsx) — extracted text: `Data/discovery-extract/text/BSI Discovery Info/FortraUATRoleChanges.xlsx.txt` (sheets: Role Hierarchy 92r×2c; Roles 93r×2c; Changes Made 24r×2c). Read in full.

*Both source files extracted cleanly and were read in full. No encrypted, binary, or empty files in this scope.*
