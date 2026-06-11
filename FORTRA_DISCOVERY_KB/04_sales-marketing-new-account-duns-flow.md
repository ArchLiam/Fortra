# Sales & Marketing — New Account, Sales Inquiry & DUNS / D&B Matching Flow

**Scope:** Proposed changes to Fortra's new-account creation and inbound Sales Inquiry handling, built around Dun & Bradstreet (D&B) DUNS-number matching to deduplicate Accounts and build the corporate hierarchy (Global Ultimate → Domestic Ultimate → child Account).

**Primary source:** [SalesInquiryDUNSProposedChanges.pdf](Fortra Discovery Documentation/Sales and Marketing/New Account Flow Updates/SalesInquiryDUNSProposedChanges.pdf) — a single document containing **two** flow diagrams (one per page). Companion editable copies exist as `.drawio` and `.vsdx` (Visio). Page 3 of the PDF is blank.

This is a **discovery / proposed-design** artifact (raw business input), complementary to the synthesized Confluence design KB (`FORTRA_KNOWLEDGE_BASE.md`). It documents *intended* behavior; it is not a record of as-built Salesforce automation.

---

## 1. What this flow is for

Fortra is consolidating multiple legacy CRMs (D365/Dynamics, Tripwire SF, Globalscape SF) onto Salesforce Revenue Cloud Advanced. A central data-quality requirement during and after consolidation is **Account deduplication and hierarchy integrity**. The proposed solution uses the **D&B Service** (Dun & Bradstreet) as the authoritative external matching source: every inbound company is resolved to a **DUNS number** and its place in the D&B corporate family tree (Domestic Ultimate, Global Ultimate) before an Account is created or linked.

Two distinct entry paths are covered, each with its own diagram:

| # | Entry path | Trigger | Diagram page | Key difference |
|---|------------|---------|--------------|----------------|
| **Flow A** | **Inbound Sales Inquiry** (automated, marketing-sourced) | Form Submissions / HubSpot data | PDF page 1 | Creates a **Sales Inquiry** record; matches on *existing Accounts only* (no user in the loop, no resubmit) |
| **Flow B** | **Manual new-account creation** (rep-initiated) | "Launch New Account Wizard" | PDF page 2 | Validates input, calls D&B, and can **create new Account + hierarchy** from DUNS data; has a user-facing error/resubmit loop |

---

## 2. The DUNS hierarchy concepts (D&B)

The matching logic depends on three DUNS values that D&B returns for any company. These map to the D&B corporate family tree and are the basis for Account hierarchy in Salesforce:

| D&B value | Meaning | Salesforce role (proposed) |
|-----------|---------|----------------------------|
| **DUNS** (entity DUNS) | The 9-digit identifier for the specific legal entity / site that was matched | The leaf/operating Account |
| **Domestic Ultimate DUNS** | The highest entity in the family tree **within the same country** | Parent Account at the country level |
| **Global Ultimate DUNS** | The single topmost parent of the entire worldwide corporate family | Top-of-hierarchy parent Account |

The flow walks **up** this tree (entity → Domestic Ultimate → Global Ultimate) to find any already-existing Account to attach to, and only creates new parent Account(s) when no level of the hierarchy already exists in Salesforce.

---

## 3. Flow A — Inbound Sales Inquiry (Form Submissions / HubSpot)

**Entry point:** `Form Submissions / HubSpot Data` (marketing-captured inbound leads).

**Steps (left-to-right per diagram):**

1. **Send available info to D&B** — pass whatever fields the form/HubSpot captured to the **D&B Service**.
2. **D&B Service → Retrieve DUNS, Domestic Ultimate DUNS, Global Ultimate DUNS** — D&B returns the three-level hierarchy identifiers.
3. **Create Sales Inquiry with info from Form Submission / HubSpot data** — a **Sales Inquiry** record is always created from the inbound data (this is the inbound capture object).
4. **Decision: Does account with DUNS exist?**
   - **YES → Link to existing account.** (Inquiry attaches to the already-known entity Account.)
   - **NO →** go to step 5.
5. **Decision: Does account with Domestic Ultimate DUNS exist?**
   - **YES → Link to existing account** (link to the Domestic Ultimate Account).
   - **NO →** go to step 6.
6. **Decision: Does account with Global Ultimate DUNS exist?**
   - **YES → Link to existing account** (link to the Global Ultimate Account).
   - **NO →** go to step 7.
7. **Create Global Ultimate and (if needed) Domestic Ultimate** — when *no* level of the hierarchy already exists, create the top parent(s). The final box connects back to **Link to existing account**, so the newly created Global/Domestic Ultimate becomes the Account the Inquiry is linked to.

**Distinguishing characteristics of Flow A:**
- Always produces a **Sales Inquiry** record regardless of match outcome.
- Matching is read-only against existing Accounts at three levels; it does **not** create a brand-new leaf/entity Account — it only creates the *parent* (Global/Domestic Ultimate) if the whole family is missing, then links.
- Fully automated — no "DUNS not found" / resubmit branch (contrast with Flow B). The assumption is that inbound form data has already been enriched/sent to D&B successfully.

### Flow A — ASCII representation
```
Form Submissions / HubSpot Data
        │
        ▼
Send available info to D&B ──▶ D&B Service
        │                       (returns DUNS, Domestic Ultimate DUNS,
        ▼                        Global Ultimate DUNS)
Create Sales Inquiry with info from Form Submission / HubSpot data
        │
        ▼
Does account with DUNS exist? ──YES──▶ Link to existing account
        │ NO
        ▼
Does account with Domestic Ultimate DUNS exist? ──YES──▶ Link to existing account
        │ NO
        ▼
Does account with Global Ultimate DUNS exist? ──YES──▶ Link to existing account
        │ NO
        ▼
Create Global Ultimate (and if needed Domestic Ultimate) ──▶ Link to existing account
```

---

## 4. Flow B — Manual New Account creation ("Launch New Account Wizard")

**Entry point:** `Launch New Account Wizard` (a rep clicks to create a new Account; implies a Salesforce Screen Flow / wizard UI).

**Minimum required fields to proceed (input validation):**
> **(Account Name + Domain + State + Country) OR DUNS Number**

i.e. either the full 4-field set, *or* a known DUNS number on its own, is sufficient to call D&B.

**Steps (left-to-right per diagram):**

1. **Present Form to collect Account information** — wizard screen collecting the minimum-required fields above.
2. **Send all info to D&B** → **D&B Service** → **Retrieve DUNS, Domestic Ultimate DUNS, Global Ultimate DUNS.**
3. **Decision: Is DUNS Found?**
   - **NO → Provide appropriate message and request user to update and resubmit form** → loops back to **Present Form to collect Account information** (the error/retry loop unique to Flow B).
   - **YES →** go to step 4.
4. **Decision: Does Account with DUNS already exist?**
   - **YES → Provide appropriate message and request user to update and resubmit form** (i.e. block duplicate creation — the entity Account already exists; send the user back to the form). *Note: the diagram routes the "YES, already exists" branch into the same resubmit/message box as the "DUNS not found" path.*
   - **NO →** go to step 5.
5. **Create Account with info from DUNS** — create the new leaf/entity Account, populated from authoritative D&B data (not just the user's free-text input).
6. **Decision: Does Domestic Ultimate exist?**
   - **YES → Link to Domestic Ultimate** (attach the new Account under the existing Domestic Ultimate parent). *(End of that branch.)*
   - **NO →** go to step 7.
7. **Create Domestic Ultimate** — create the Domestic Ultimate parent Account.
8. **Decision: Is Global Ultimate DUNS different than Global Ultimate?** *(diagram label; read as: is the Global Ultimate a distinct entity from the Domestic Ultimate just created?)*
   - **YES → Create Global Ultimate & Link to Domestic Ultimate** — create the Global Ultimate parent and link it above the Domestic Ultimate. *(End of branch.)*
   - **NO →** (no further node shown — implies the Domestic Ultimate is also the Global Ultimate / top of tree, so no additional parent is created.)

**Distinguishing characteristics of Flow B:**
- **Creates a new entity Account** ("Create Account with info from DUNS") — Flow A does not.
- Has explicit **error handling / resubmit** for "DUNS not found" and "duplicate DUNS already exists."
- Builds the hierarchy **downward from the new Account**: create the leaf, then ensure Domestic Ultimate, then ensure Global Ultimate, linking at each level.
- D&B is used to **enrich** the Account (data from DUNS overrides/augments the user's typed input).

### Flow B — ASCII representation
```
Launch New Account Wizard
        │
        ▼
Present Form to collect Account information ◀──────────────┐
  (min: [Account Name + Domain + State + Country] OR DUNS) │
        │                                                  │
        ▼                                                  │
Send all info to D&B ──▶ D&B Service (returns 3 DUNS levels)│
        │                                                  │
        ▼                                                  │
Is DUNS Found? ──NO──▶ Provide message & request resubmit ─┘
        │ YES                          ▲
        ▼                              │ YES (already exists)
Does Account with DUNS already exist? ─┘
        │ NO
        ▼
Create Account with info from DUNS
        │
        ▼
Does Domestic Ultimate exist? ──YES──▶ Link to Domestic Ultimate
        │ NO
        ▼
Create Domestic Ultimate
        │
        ▼
Is Global Ultimate (DUNS) different than [Domestic] Global Ultimate?
        │ YES
        ▼
Create Global Ultimate & Link to Domestic Ultimate
```

---

## 5. As-is vs Proposed

The artifact is titled **"Proposed Changes."** It does not draw an explicit "as-is" diagram; both diagrams are the **proposed** target state. The implied change vs. legacy behavior:

- **Proposed:** Every new company (inbound Inquiry or manual creation) is resolved through **D&B DUNS matching** and slotted into the **Global/Domestic Ultimate hierarchy** before an Account is created or linked — preventing duplicates and orphaned Accounts during the multi-CRM consolidation.
- **Implied as-is gap:** legacy CRMs created Accounts without enforced DUNS resolution or hierarchy, producing duplicates and broken parent/child relationships — the problem this design targets.

(No explicit as-is flow exists in these files; treat the "as-is" as inferred, not documented.)

---

## 6. Salesforce objects & automation implied

These are *inferred from the diagram labels* — the artifact does not specify API names or implementation. Flag as design intent, not as-built.

| Concept in diagram | Likely Salesforce object / mechanism | Notes / open questions |
|--------------------|--------------------------------------|------------------------|
| **Sales Inquiry** (Flow A) | Custom object (e.g. `Sales_Inquiry__c`) **or** a repurposed/renamed **Lead** | See cross-ref below — Fortra renames Lead to "Inquiry" elsewhere; needs confirmation whether "Sales Inquiry" = Lead or a separate object. |
| **Account** + DUNS, Domestic Ultimate DUNS, Global Ultimate DUNS | Standard `Account`; standard D&B fields `DunsNumber`, plus `DomesticUltimateDunsNumber` / `GlobalUltimateDunsNumber` (D&B-style fields) | Hierarchy modeled via `ParentId` or a custom parent lookup; matching is by DUNS field equality. |
| **D&B Service** | External callout to Dun & Bradstreet (Data.com / D&B Hoovers / D&B Direct+ API) | Whether this is native SF Data.com (deprecated), a managed package, or a custom MuleSoft callout is **not stated**. Given the BSI/MuleSoft integration layer, a MuleSoft-mediated D&B Direct+ callout is plausible but unconfirmed. |
| **Form Submissions / HubSpot Data** | HubSpot → Salesforce lead/inquiry integration | HubSpot is Fortra's marketing automation source; the HubSpot↔SF sync feeds Flow A. |
| **Launch New Account Wizard** / **Present Form** | Salesforce **Screen Flow** (Lightning) | The "wizard," validation of minimum fields, and the "resubmit" loop strongly imply a Screen Flow with screen + decision elements. |
| **Create / Link** steps | Flow record-create / record-update, or Apex | Hierarchy linking (`ParentId`) and dedupe matching logic. |

---

## 7. Decision-point summary (both flows)

| Decision | Flow A (Inquiry) | Flow B (Wizard) |
|----------|------------------|-----------------|
| Is DUNS Found? | (assumed found; not branched) | **Yes:** continue; **No:** message + resubmit |
| Does account with **DUNS** exist? | Yes → link; No → check Domestic Ultimate | Yes → message + resubmit (block dup); No → create Account |
| Does account with **Domestic Ultimate DUNS** exist? | Yes → link; No → check Global Ultimate | Yes → link to Domestic Ultimate; No → create Domestic Ultimate |
| Does account with **Global Ultimate DUNS** exist? | Yes → link; No → create Global Ultimate (+ Domestic if needed) | (handled as "is Global Ultimate different?" → create Global Ultimate & link) |
| Outcome when nothing exists | Create Global Ultimate (+ Domestic Ultimate) and link | Create leaf Account + Domestic Ultimate + Global Ultimate, linked top-down |

**Key behavioral contrast:** In **Flow A**, an existing entity DUNS match links the Inquiry and stops; the deepest *create* action is the parent hierarchy only. In **Flow B**, an existing entity DUNS match is treated as a **duplicate error** (resubmit), because the user is explicitly trying to create a *new* Account.

---

## 8. Open questions / ambiguities

1. **"Sales Inquiry" object identity.** Is it the standard Lead (Fortra renames Lead to "Inquiry" — see memory note *SC-3171 close-reason interlock*, "Lead is labeled 'Inquiry'"), or a distinct custom object? This directly affects matching/automation design. **Unresolved by these files.**
2. **D&B integration mechanism.** Native SF feature vs. managed package vs. custom MuleSoft callout to D&B Direct+ — not specified. Matters for the BSI/MuleSoft integration scope.
3. **Flow B "duplicate exists → resubmit" UX.** The diagram routes "DUNS already exists" back to the same resubmit message as "DUNS not found." Intended behavior on a duplicate (offer to open the existing Account? hard block?) is unclear.
4. **Flow B step 8 label** ("Is Global Ultimate DUNS different that Global Ultimate") is grammatically garbled in the source; interpreted as "is the Global Ultimate a distinct entity from the Domestic Ultimate just created." The **NO** branch has no terminal node drawn.
5. **Matching field precision.** Diagram says "account with [X] DUNS exist?" — whether matching is on the entity DUNS field, or against parent-DUNS fields across all Accounts, is not field-level specified.
6. **No SLA/owner/date metadata.** The artifact carries no author, owner, approval date, or version stamp.
7. **Re-enrichment of existing Accounts.** Neither flow addresses updating an existing matched Account's data from fresher D&B values; both only *link*.

---

## 9. Connections to the broader RCA / Workday / MuleSoft program

- **Consolidation context:** Clean, deduplicated, DUNS-hierarchied Accounts are foundational for the D365/Tripwire/Globalscape → Salesforce RCA migration; this flow is the front-door guardrail against re-introducing duplicates.
- **HubSpot (marketing) → SF:** Flow A is the inbound marketing capture path; ties to Sales & Marketing lead/inquiry handling (cross-ref the Lead Flow Scenarios discovery docs if present in other KB topics).
- **MuleSoft:** If D&B is reached via callout, it likely sits in the same MuleSoft integration layer that BSI owns; this is the integration-architecture overlap to confirm.
- **Design KB:** Complementary to `FORTRA_KNOWLEDGE_BASE.md` (Confluence design docs). This discovery artifact is the *proposed* account/inquiry intake design; reconcile against any account-management design doc there.

---

## Sources

- [SalesInquiryDUNSProposedChanges.pdf](Fortra Discovery Documentation/Sales and Marketing/New Account Flow Updates/SalesInquiryDUNSProposedChanges.pdf) — **primary**, read with vision. Page 1 = Flow A (Sales Inquiry / HubSpot); Page 2 = Flow B (New Account Wizard); Page 3 = blank.
- [SalesInquiryDUNSProposedChanges.vsdx](Fortra Discovery Documentation/Sales and Marketing/New Account Flow Updates/SalesInquiryDUNSProposedChanges.vsdx) — Visio editable source; extracted text confirmed identical node labels across pages 1–2 (page 3 empty). Layout scrambled by extraction; used to cross-check labels.
- [SalesInquiryDUNSProposedChanges.drawio](Fortra Discovery Documentation/Sales and Marketing/New Account Flow Updates/SalesInquiryDUNSProposedChanges.drawio) — draw.io editable source. Extracted text yielded only the "D&B Service" node labels (the extractor captured a limited subset); content otherwise duplicates the PDF/VSDX. No additional information beyond the PDF.

*No in-scope file was encrypted, password-protected, or fully empty. The `.drawio` text extraction was partial (extractor limitation), but the PDF (vision) and `.vsdx` text together provide complete coverage of both diagrams.*
