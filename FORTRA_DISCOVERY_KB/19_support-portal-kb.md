# 19 — Support & Portal: Globalscape Knowledge Base (InstantKB Export)

> Discovery-input KB for the **Globalscape support knowledge base** as it existed on the legacy
> InstantKB platform (`kb.globalscape.com`). This is the raw export Fortra captured during the
> Salesforce Revenue Cloud Advanced (RCA) consolidation, so the legacy KB content and its data
> model are understood before any migration to the Fortra Support Portal / Salesforce Knowledge.
>
> Source files live in
> [`Fortra Discovery Documentation/Support and Portal/`](Fortra Discovery Documentation/Support and Portal/).
> Two artifacts describe the KB *data*; a third (a 906 MB full HTML dump) is referenced but **not
> extracted** — see [§7 Not Extracted / Available on Request](#7-not-extracted--available-on-request).
>
> **How this connects to the design KB:** `FORTRA_KNOWLEDGE_BASE.md` defines the product hierarchy.
> **Solution Category 2.00** is the level "used on Support Portal **KB/Downloads**" and equals the
> Workday "Fortra Business Unit"; **Feature 4.00** is the "Software Product Family" used for
> **Support Portal case selection**. Globalscape is a **Solution Category** under the **Managed File
> Transfer** Solution Group (alongside GoAnywhere). The legacy InstantKB content described here is
> the body of articles that must land at the **Globalscape Solution Category** node of the new
> portal and be re-tagged to the new Feature 4.00 products (EFT, CuteFTP, DMZ Gateway, Arcus, etc.).

---

## 1. What the two source artifacts actually contain

| File | Format | What it is | Rows |
|---|---|---|---|
| [`Globalscape KB Article.xlsx`](Fortra Discovery Documentation/Support and Portal/Globalscape%20KB%20Article.xlsx) | XLSX (single sheet) | **Table inventory** of the InstantKB SQL Server database (`dbo` schema) — a list of every `InstantKB_*` table and its **record count**. This is the schema/volume map, NOT article content. | 59 tables |
| [`Fortra GlobalScape  InstantKB_Articles.csv`](Fortra%20Discovery%20Documentation/Support%20and%20Portal/Fortra%20GlobalScape%20%20InstantKB_Articles.csv) | CSV (tab-delimited, 49 columns) | **The actual article export** — one row per KB article, including title, category, type, dates, view counts, ratings, attachment refs, and the article **body** (HTML in the `ArticleMarkDown`/body field). | **867 articles** (matches `InstantKB_Articles` = 867 in the xlsx inventory) |
| `kb_globalscape_com202508081526.zip` | ZIP, **950 MB** | Full HTML crawl/dump of the public `kb.globalscape.com` site (captured **2025-08-08 15:26**). | Not extracted |

The two data files cross-validate: the xlsx says `dbo.InstantKB_Articles` holds **867** records, and the
CSV has exactly **867** data rows. The CSV is the authoritative article-level source for migration.

---

## 2. InstantKB database table inventory (volume map)

From [`Globalscape KB Article.xlsx`](Fortra%20Discovery%20Documentation/Support%20and%20Portal/Globalscape%20KB%20Article.xlsx),
Sheet1 (`SchemaName`, `TableName`, `Record Count`). All tables are schema `dbo`. The full 59-table
list, grouped by function:

### 2.1 Article content & metadata
| Table | Rows | Meaning |
|---|---|---|
| `InstantKB_Articles` | **867** | The KB articles themselves (= the CSV) |
| `InstantKB_ArticleVersions` | 4,287 | Version history (≈4.9 versions per article on average) |
| `InstantKB_ArticleCategories` | 1,319 | Article→category links (many-to-many; > article count, so articles are multi-categorized internally) |
| `InstantKB_ArticleCustomFields` | 1,517 | Custom field values attached to articles |
| `InstantKB_ArticleRoles` | 10,466 | Per-article role/visibility ACLs |
| `InstantKB_Attachments` | 85 | File attachments on articles |
| `InstantKB_AttachmentTypes` | 167 | Allowed attachment MIME/type defs |
| `InstantKB_ArticleRelatedLinks` | 4 | "Related link" references |
| `InstantKB_ArticleRelatedArticles` | 0 | (none used) |
| `InstantKB_Notes` | 1 | Internal notes |

### 2.2 Engagement / analytics (large tables — migration weight)
| Table | Rows | Meaning |
|---|---|---|
| `InstantKB_ArticleRead` | **27,396,895** | Per-read event log (~27.4M reads) — analytics, not needed in SF Knowledge |
| `InstantKB_LogEntries` | 471,750 | System/audit log |
| `InstantKB_ArticleRatings` | 18,640 | Individual rating events |
| `InstantKB_ArticleCommentRatings` | 421 | Ratings on comments |
| `InstantKB_WhosOn` | 123 | "Who's online" snapshots |
| `InstantKB_ArticleComments` | 0 | Comments feature unused |

### 2.3 Taxonomy / configuration
| Table | Rows | Meaning |
|---|---|---|
| `InstantKB_Categories` | **45** | The category master (the `ArticleCategoryID` lookup target in the CSV) |
| `InstantKB_CategoryRoles` | 308 | Per-category ACLs |
| `InstantKB_Types` | 30 | Article **type** master (the `ArticleTypeID` lookup) |
| `InstantKB_Status` | 25 | Article **status** master (`ArticleStatusID`) |
| `InstantKB_Priorities` | 16 | Priority master (`ArticlePriorityID`) |
| `InstantKB_Levels` | 15 | Level master (`ArticleLevelID`) |
| `InstantKB_Channels` | 6 | Publishing channels |
| `InstantKB_DataViews` | 18 | Saved report/list views |
| `InstantKB_Settings` | 11 | App settings |
| `InstantKB_Tabs` | 6 | UI tabs (article CSV all `TabID=1`) |
| `InstantKB_TabRoles` | 36 | Tab ACLs |
| `InstantKB_Departments` | 2 | Departments |
| `InstantKB_Glossary` | 0 | Glossary unused |

### 2.4 Users / permissions
| Table | Rows | Meaning |
|---|---|---|
| `InstantKB_Users` | **504** | Staff/admin user accounts |
| `InstantKB_UserDepartments` | 144 | User→department |
| `InstantKB_WhosOn` / `UserLists` / `UserUserLists` | 123 / 6 / 1 | Misc user grouping |
| `InstantKB_PermissionSets` | 5 | Permission set defs |
| `InstantKB_PermissionSetsTabs` | 49 | Permission→tab grants |
| `InstantKB_PermissionSetsRoles` | 8 | Permission→role |
| `InstantKB_StaffPermissionSets` / `StaffPermissionSetsTabs` | 2 / 10 | Staff-specific permissions |
| `InstantKB_UserLevels` | 5 | User levels |
| `InstantKB_Roles` *(implicit)* | — | Referenced by `ArticleRoles`/`CategoryRoles` |

### 2.5 Ticketing / workflow (largely UNUSED — KB-only deployment)
All ticketing tables are **empty (0 rows)**, confirming this InstantKB instance was used **only as a
knowledge base**, not as a help-desk/ticketing system (tickets were handled elsewhere — Salesforce
Service Cloud / legacy systems):

`InstantKB_Tickets` 0, `InstantKB_TicketReplies` 0, `InstantKB_TicketNotes` 0,
`InstantKB_TicketUsers` 0, `InstantKB_TicketCategories` 0, `InstantKB_TicketCustomFields` 0,
`InstantKB_SLAs` 0, `InstantKB_StandardReplies` 0, `InstantKB_Rules` 0, `InstantKB_Alerts` 0,
`InstantKB_Notifications` 0, `InstantKB_EmailHistory` 0, `InstantKB_Holidays` 0,
`InstantKB_DepartmentWorkTimes` 0, `InstantKB_TroubleshooterSteps` 0,
`InstantKB_WorkFlowStepsNextSteps` 0.

Workflow scaffolding exists but is minimal: `InstantKB_WorkFlows` 6, `InstantKB_WorkFlowSteps` 25,
`InstantKB_WorkFlowDepartments` 5 — and the articles barely use it (see §4, `ArticleWorkFlowStepID`).

> **Migration implication:** Only `InstantKB_Articles` + `ArticleVersions` + `ArticleCategories` +
> `Attachments` carry content worth migrating to Salesforce Knowledge. The 27.4M-row `ArticleRead`
> and 471K-row `LogEntries` are analytics exhaust and should be **excluded** from migration (archive
> or summarize only). Ticketing tables are empty → nothing to migrate there.

---

## 3. The article CSV data model (49 columns)

One row per article. Tab-delimited. Below is the full column list with type/role and observed values.
(Columns whose master tables are in the xlsx are noted; the CSV gives the *ID*, the lookup tables give
the label — the label tables themselves were **not** in the export beyond the row-count inventory, so
type/status/category *names* are inferred from article-title clustering, see §5.)

| # | Column | Role / observed behavior |
|---|---|---|
| 1 | `ArticleID` | PK. Numeric, range **10017 – 11649** (note: not all created in ID order vs date) |
| 2 | `TabID` | Always **1** (single KB tab) |
| 3 | `ArticleParentID` | Almost always 0 (flat, no parent/child threading) |
| 4 | `ArticleCategoryID` | FK → `InstantKB_Categories`. **Primary product/category dimension** (see §5) |
| 5 | `ArticleTitle` | Human title (the migration's primary content signal) |
| 6 | `ArticleTitleEncoded` | URL slug of the title |
| 7 | `ArticlePercentComplete` | All **0** (authoring-progress field, unused) |
| 8 | `ArticleRating` | Rounded avg rating 0–4 (see §4 distribution) |
| 9 | `ArticleViews` | Lifetime view count. **Total 33,042,183** across all articles |
| 10 | `ArticleTypeID` | FK → `InstantKB_Types`. Article **type** (KB/FAQ/Troubleshooting/etc., see §5.2) |
| 11 | `ArticleLevelID` | FK → `InstantKB_Levels`. **866 = 0**, 1 = level 1 (essentially unused) |
| 12 | `ArticleStatusID` | FK → `InstantKB_Status`. **All 867 = 0** → all in same status (published) |
| 13 | `ArticlePriorityID` | All **0** (unused) |
| 14 | `ArticleAccessType` | **1 = public** (814), **2 = restricted/internal** (52), 0 (1). See §5.3 |
| 15 | `ArticleWorkFlowStepID` | 865 = 0 (no workflow), 1 article = step 5, 1 = step 1 |
| 16–17 | `ArticleCreatedUserID` / `ArticleCreatedUsername` | Author. Top authors: `GlobalSCAPE 5` (368), `kmarsh` (353), `GlobalSCAPE Support 1` (83) |
| 18 | `ArticleCreatedDate` | Creation timestamp. **Range 2006-01-24 → 2025** (see §4 by-year) |
| 19–20 | `ArticleModifiedUserID` / `ArticleModifiedUsername` | Last editor. Dominated by `kmarsh` (726) — a single KB curator |
| 21 | `ArticleModifiedDate` | Last-modified timestamp. **Heavy 2023 (190) & 2024 (354)** refresh — a recent re-curation pass |
| 22–24 | `ArticleAssignedUserID/Username/Date` | Assignment (mostly empty/NULL) |
| 25–28 | `ArticleSuggestedUserID/Username/Email/Date` | Community-suggested-article fields (unused, NULL) |
| 29–31 | `ArticleReportedUserID/Username/Date` | "Report this article" fields (unused, NULL) |
| 32 | `ArticleDueDate` | NULL |
| 33 | `ArticleReviewDate` | NULL (no review-cadence enforced) |
| 34 | `ArticleExpiresDate` | NULL (no expiry) |
| 35 | `ArticlePassword` | Per-article password gate (empty) |
| 36 | `TotalRatings` | Count of ratings on the article. **Sum 18,083** (≈ the 18,640 `ArticleRatings` rows) |
| 37 | `AttachmentCount` | Per-article attachment count. **62 articles have attachments, 90 total** |
| 38 | `CommentCount` | ~0 (comments unused) |
| 39 | `RelatedLinkCount` | ~0 |
| 40 | `RelatedArticleCount` | ~0 |
| 41 | `TagCount` | ~0 (no tagging) |
| 42 | `ArticleDownloadFile` | Downloadable file ref (mostly empty) |
| 43 | `ArticleDownloadLink` | External download URL (mostly empty) |
| 44 | `ArticleDownloadPassword` | (empty) |
| 45 | `ArticleImageUrl` | Hero/thumbnail image URL, e.g. `https://kb.globalscape.com/Uploads/Images/...png` |
| 46 | `ArticleSettingsXML` | Per-article XML settings; uniformly `<?xml version='1.0' encoding='UTF-8'?><settings />` (empty settings) |
| 47 | `ArticleVersion` | Editorial version string. Top: `1` (213), `1.1` (130), `0` (114), `1.2` (81)… up to `2.x`/`3.x` |
| 48 | `ArticleMarkDown` | **The article body** (HTML, despite the name). Contains the full Q/A/Discussion content, `<a href>` links, CVE references, code blocks |
| 49 | `ArticleIsMarkDown` | Flag: 814 = `0` (HTML, not markdown), 5 = `1`. So bodies are **HTML**, not markdown |

> **Body content note:** The article body in `ArticleMarkDown` is structured HTML with a recurring
> **QUESTION / ANSWER / MORE INFORMATION** or **DISCUSSION** pattern (e.g. the EFT Arcus / Azure
> Stack CVE article). Embedded newlines and tabs inside these HTML bodies cause a handful of CSV
> rows to mis-split when naively column-counted — see [§6 Data-quality notes](#6-data-quality--parsing-notes).

---

## 4. Volume, freshness & engagement metrics (from the 867-row CSV)

### 4.1 Created-date by year (KB age)
The KB spans **~19 years**: first article **2006-01-24**, newest in **2025**. Authoring volume by
creation year:

| Year | New articles | | Year | New articles |
|---|---|---|---|---|
| 2006 | 130 | | 2016 | 63 |
| 2007 | 36 | | 2017 | 53 |
| 2008 | 36 | | 2018 | 50 |
| 2009 | 67 | | 2019 | 29 |
| 2010 | 40 | | 2020 | 50 |
| 2011 | 67 | | 2021 | 13 |
| 2012 | 51 | | 2022 | 16 |
| 2013 | 24 | | 2023 | 26 |
| 2014 | 21 | | 2024 | 41 |
| 2015 | 49 | | 2025 | 4 |

### 4.2 Modified-date by year (curation activity)
A **large recent re-curation** happened — most articles were last touched in **2023–2024**:

| Year | Articles last modified |
|---|---|
| 2023 | **190** |
| 2024 | **354** |
| 2019 | 56 |
| 2012 | 46 |
| 2017 | 31 |
| 2016 | 28 |
| (others 2011–2025) | remainder |

`kmarsh` is the modifying user on **726 of 867** articles — effectively the sole KB curator in the
modern era. **Migration implication:** content is current (recently reviewed), so it is worth
migrating largely as-is rather than treating as stale.

### 4.3 Views & ratings
- **Total lifetime views: 33,042,183.** This is a heavily-trafficked KB; the top articles each have
  hundreds of thousands of views — **prioritize these for migration & SEO redirect mapping.**
- `ArticleRating` (rounded 0–4) distribution: `1`→302, `0`→274, `2`→239, `3`→49, `4`→3.
- `TotalRatings` sum = **18,083**.

### 4.4 Top 15 most-viewed articles (migrate & redirect first)
These are error-code/troubleshooting reference pages with the heaviest organic-search traffic — they
are the highest-value SEO assets and must keep working URLs (301 redirects) post-migration:

| Views | ArticleID | Title |
|---|---|---|
| 973,393 | 10142 | File Transfer Status and Error Codes |
| 903,303 | 10407 | Can I use a Windows Command Prompt to send FTP Commands to a server? |
| 624,202 | 10224 | Establishing an FTP Connection from the Command Prompt |
| 495,264 | 10305 | CuteFTP - 550 Permission Denied (or No such file or folder) |
| 461,049 | 10438 | Tuning Windows for TCP/IP performance |
| 370,004 | 10235 | CuteFTP - Socket Error 10054 |
| 320,796 | 10300 | 530 Not logged in (or Password Rejected) |
| 306,637 | 10140 | Winsock Error Codes |
| 293,766 | 10141 | HTTP Status and Error Codes |
| 228,381 | 10384 | Socket Error 10060 |
| 224,993 | 11194 | Upgrading EFT v7.x - 8.0.6 to a later version |
| 212,983 | 10137 | I cannot login to my FTP site. What is my password? |
| 211,753 | 10528 | Officially Supported Products and EOL Dates |
| 196,241 | 10133 | Firewall and Router Setup |
| 192,498 | 10262 | EFT Server Client Log Explained |

---

## 5. Product / category breakdown (the migration taxonomy)

### 5.1 `ArticleCategoryID` distribution (primary dimension)
The 45-row `InstantKB_Categories` table holds the labels; the CSV gives IDs. Category meaning is
**inferred from the titles of the articles in each bucket** (the label table was not exported beyond
its row count). The KB is overwhelmingly **EFT-centric**:

| CategoryID | # articles | Inferred category (from title clustering) | Maps to Fortra portal Feature 4.00 |
|---|---|---|---|
| **10** | **661** | **EFT** (Enhanced File Transfer Server) — core MFT product | EFT |
| **7** | **106** | **CuteFTP** (Windows/Mac FTP client) | CuteFTP |
| **0** | **35** | **WAFS / CDP** (Wide-Area File Services, replication) + uncategorized/legacy | WAFS/CDP |
| **17** | **23** | **General / Networking / Corporate** (firewall setup, Winsock/error codes, tax forms, holiday schedule, DST) | (cross-product / corporate) |
| **35** | **12** | **DMZ Gateway** (reverse-proxy companion to EFT) | DMZ Gateway |
| **101** | **11** | **EFT Arcus** (cloud/SaaS MFT — Azure-hosted) | EFT Arcus |
| **5** | **10** | **Registration / Licensing / Serial numbers** | (licensing) |
| **39** | 2 | **Advanced Workflow Engine (AWE) / Automate** | AWE |
| **38** | 2 | **Web Transfer Client (WTC)** | WTC |
| **20** | 2 | **Installation / Compliance** (NAFTA cert, install.log) | (corporate) |
| **37** | 1 | EFT upgrade / Oracle ODAC drivers | EFT |
| **114** | 1 | **RAM** (Remote Agent Module) upgrade | RAM |
| **100** | 1 | EFT SFTP COM API (PowerShell validation) | EFT/API |

> So **~88%** of articles are EFT (661) + CuteFTP (106). The "modern" cloud product **EFT Arcus**
> (category 101) is small but growing — and is the product most relevant to the go-forward SaaS
> business. Title-keyword scan corroborates the spread: EFT in 287 titles, FTP 141, CuteFTP 85,
> WTC/Web Transfer Client 52, DMZ 28, HTTP 26, AWE 18, SSL 19, ARM 15, Globalscape/GlobalSCAPE 20,
> Arcus 11, SSH 13, WAFS 5.

### 5.2 `ArticleTypeID` distribution
The 30-row `InstantKB_Types` master holds labels; inferred from usage these are KB content types
(Troubleshooting / How-To / FAQ / Reference). Distribution:

| TypeID | # | Likely meaning (inferred) |
|---|---|---|
| 7 | 369 | How-To / Configuration |
| 8 | 127 | FAQ / Conceptual |
| 4 | 127 | Feature / Capability |
| 2 | 97 | Troubleshooting / Error |
| 5 | 61 | Networking / Connection issue |
| 12 | 35 | Known issue / Bug |
| 6 | 32 | Reference |
| 1 | 13 | General |
| 10 | 4 | (misc) |
| 34 | 1 | (misc) |
| `24719` | 1 | **Corrupt** — parse artifact, ArticleID 10599 (see §6) |

### 5.3 `ArticleAccessType` — public vs internal
- **1 = Public** → **814 articles** (visible on `kb.globalscape.com`).
- **2 = Restricted / internal-staff** → **52 articles**. These are advanced/registry-tuning and
  internal-config docs — e.g. *"List of Windows Registry Settings/Advanced Properties for EFT
  Server"*, *"How EFT Server's VFS Permissions Work"*, *"Override Outbound on Listening IP"*,
  *"Kill EAS Service on Startup"*, *"Specify the location of FTP.CFG"*.
- **0 = (1 article)** — likely a draft/unset.

> **Migration implication:** the 52 `AccessType=2` articles must map to an **internal-only**
> Salesforce Knowledge data category / channel (not the public Experience Cloud portal). The
> public/internal split must be preserved.

---

## 6. Representative article examples (by product)

These concrete examples show the body style (QUESTION / ANSWER / DISCUSSION / MORE INFORMATION) and
help validate the taxonomy mapping:

| Product | ArticleID | Title |
|---|---|---|
| **EFT** | 10017 | Can I configure EFT to run executables, batch files, and scripts automatically when specific events occur? |
| EFT | 10142 | File Transfer Status and Error Codes *(highest-traffic article, 973K views)* |
| EFT | 10251 | Moving EFT Server from one computer to another computer |
| EFT | 11573 | EFT REST API Reference for v8.1 |
| EFT | 11509 | Deny Login Attempts to EFT from Specific Usernames |
| EFT | 11322 | Installing and configuring Shibboleth as the backend IDP server for use with EFT SSO |
| **CuteFTP** | 10128 | CuteFTP - Error 12002. The operation timed out *(182K views)* |
| CuteFTP | 10305 | CuteFTP - 550 Permission Denied (or No such file or folder) |
| CuteFTP | 10205 | CuteFTP - Public key authentication failing |
| **DMZ Gateway** | 11201 | DMZ Gateway® Configuration Settings |
| DMZ Gateway | 11114 | Installing or Upgrading DMZ Gateway in a Failover (ACTIVE/PASSIVE) Cluster |
| DMZ Gateway | 11206 | Running DMZ Gateway as non-root user in Linux |
| **EFT Arcus (cloud)** | 11405 | Enable Azure AD SSO with EFT Arcus and the Web Transfer Client |
| EFT Arcus | 11484 | Understanding your EFT Arcus monthly charges |
| EFT Arcus | 11496 | Is my EFT Arcus implementation susceptible to the Azure Stack vulnerabilities? *(CVE-2019-1372/1234)* |
| EFT Arcus | 11582 | Assigning an SSL Certificate to an EFT Arcus Site |
| **WAFS/CDP** | 10415 | How can WAFS/CDP benefit my organization? |
| **AWE / Automate** | 11468 | Can you provide examples of workflows in the Advanced Workflow Engine? |
| **WTC** | 11596 | How to hide Forgot Username or Password links in WTC? |
| **Licensing** | 10121 | About Registration Serial Numbers |
| **Corporate/cross** | 10120 | Can GlobalSCAPE products be exported from the United States? (ECCN and CCATS) |
| Corporate/cross | 10528 | Officially Supported Products and EOL Dates *(211K views)* |

---

## 7. Data-quality & parsing notes

- **Embedded HTML/newlines in `ArticleMarkDown` (body)** cause a handful of CSV rows to split across
  more than 49 tab-delimited columns. The clearest case is **ArticleID 10599** ("Upload using
  CuteFTP Pro on the Windows Explorer right-click menu not available on Windows 7 64bit OS"):
  its body content bleeds into later columns, producing the spurious `ArticleTypeID = 24719` and a
  date-column value of `GlobalSCAPE 5`. Any migration ETL must parse the CSV with a **quote/newline-
  aware** reader (RFC-4180 with embedded newlines), not a line-by-line tab split.
- **Title quoting artifacts:** titles containing literal quote marks render as doubled quotes in the
  export, e.g. `Upload using CuteFTP Pro"" on the Windows Explorer…` and
  `Does EFT "call home"" to Globalscape?"`. Normalize quote escaping on import.
- **Unused/flat fields:** `ArticleStatusID` (all 0), `ArticlePriorityID` (all 0),
  `ArticlePercentComplete` (all 0), `ArticleReviewDate`/`ExpiresDate`/`DueDate` (NULL),
  `Tag/Comment/RelatedArticle` counts (~0). These carry **no migratable signal** — do not build
  Salesforce Knowledge fields around them.
- **Bodies are HTML, not markdown** (`ArticleIsMarkDown = 0` for 814/867) despite the
  `ArticleMarkDown` column name. Migrate as Rich-Text HTML.

---

## 8. Mapping to the Fortra Support Portal / Salesforce (migration guidance)

How this legacy KB lands in the consolidated RCA/portal world (cross-reference
[`FORTRA_KNOWLEDGE_BASE.md` §2 Product Hierarchy](FORTRA_KNOWLEDGE_BASE.md)):

| Legacy InstantKB concept | Target in Fortra / Salesforce |
|---|---|
| The whole KB | Sits under **Solution Category 2.00 = "Globalscape"** (Managed File Transfer Solution Group). Solution Category is the level "used on Support Portal **KB/Downloads**". |
| `ArticleCategoryID` (EFT, CuteFTP, DMZ Gateway, Arcus, WAFS, WTC, AWE, RAM) | **Feature 4.00** ("Software Product Family", used for **Support Portal case selection**) — re-tag each article to the correct Feature node. |
| `ArticleAccessType` (1 public / 2 internal) | Salesforce Knowledge **Data Category visibility** / channel: public → Experience Cloud portal; `2` → internal-only. |
| `ArticleTitle` + `ArticleMarkDown` (HTML body) | Knowledge Article `Title` + Rich-Text body field. |
| `ArticleVersion` / `InstantKB_ArticleVersions` (4,287) | Salesforce Knowledge versioning (migrate latest published version; history optional). |
| `ArticleViews` (33M total) | Used to **prioritize migration order** and build **301-redirect map** from `kb.globalscape.com/<slug>` (`ArticleTitleEncoded`) to new portal URLs — critical for the 15 top articles (§4.4). |
| `Attachments` (85 files) + `ArticleImageUrl` | Re-host images/files; rewrite `https://kb.globalscape.com/Uploads|attachments/...` URLs to the new asset CDN. |
| Empty ticketing tables | Nothing to migrate — tickets/cases handled in Salesforce Service Cloud, not InstantKB. |
| `InstantKB_ArticleRead` (27.4M) / `LogEntries` (471K) | **Exclude** from migration — analytics exhaust; archive or summarize only. |

**Open questions / follow-ups for migration scoping** are listed in the structured output.

---

## Sources

- [`Fortra Discovery Documentation/Support and Portal/Globalscape KB Article.xlsx`](Fortra%20Discovery%20Documentation/Support%20and%20Portal/Globalscape%20KB%20Article.xlsx) — InstantKB database table/row-count inventory (59 tables, single sheet).
- [`Fortra Discovery Documentation/Support and Portal/Fortra GlobalScape  InstantKB_Articles.csv`](Fortra%20Discovery%20Documentation/Support%20and%20Portal/Fortra%20GlobalScape%20%20InstantKB_Articles.csv) — 867-article export, 49 columns (titles, categories, types, dates, views, ratings, attachments, HTML body). Read via the extracted `.txt` and analyzed programmatically.
- **`Fortra Discovery Documentation/Support and Portal/kb_globalscape_com202508081526.zip`** — 950 MB full HTML dump of `kb.globalscape.com` (captured 2025-08-08 15:26). **NOT extracted** (binary ZIP, too large for the text pipeline). Available on request; would be the source for full rendered article HTML, images, and the public site's category/navigation labels that the CSV references only by numeric ID.
- Cross-reference: [`FORTRA_KNOWLEDGE_BASE.md`](FORTRA_KNOWLEDGE_BASE.md) §2 (Product Hierarchy — Solution Category 2.00 & Feature 4.00 portal usage).
