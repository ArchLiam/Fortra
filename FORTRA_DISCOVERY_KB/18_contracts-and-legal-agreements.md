# Contracts & Legal — Agreements, Schedules & NDAs

**Scope:** Discovery inputs from `Fortra Discovery Documentation/Contracts and Legal Documents/`. These are the
**legal agreement templates** that govern Fortra's commercial deals. They define the contract architecture that the
Salesforce Revenue Cloud Advanced (RCA) Quote-to-Cash, document generation (DocGen), and Workday/MuleSoft billing flows
must reflect — term lengths, renewal/auto-renew windows, payment terms, license metrics, and brand-specific obligations.

> **How this connects to the SF RCA build.** Every concrete term below maps to a Salesforce/Workday data point:
> - **License metric** (Subscription / Perpetual / Term) → RLM Selling Model / `ProductSellingModel`; drives Maintenance vs Subscription Fee logic.
> - **Term length & renewal window** → Quote/Order/Asset term fields, renewal automation (`initiateRenewal`), and the COLA renewal universe (SC-3350).
> - **Payment terms (Net 30, annual in advance)** → Workday billing schedule / invoice timing mapped via MuleSoft.
> - **Order Form** = the transactional document; in RCA this is the **Quote/Order**. The MSA + Solution Specific Schedule are the master/umbrella that the Order references.
> - **DPA / Export / End-Use** = compliance gates that may need to be enforced/recorded on the Account or Order (esp. for offensive-security SKUs — Core Impact, Cobalt Strike, OST).
>
> A separate repo file `FORTRA_KNOWLEDGE_BASE.md` synthesizes the Confluence **design** docs; this discovery doc complements it
> with the raw legal/business inputs.

---

## 1. Inventory of agreement templates

| # | Document | Type | Brand / Scope | Version / Date | Governing law | Notes |
|---|----------|------|---------------|----------------|---------------|-------|
| 1 | [Master Solutions Agreement](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Fortra%20Master%20Solutions%20Agreement%20with%20Sig%20Blocks%2009_04_24%20(7).docx) | **MSA** (master) | All Fortra solutions | 09/04/24 (Sept 4 2024) | Minnesota; Hennepin County | The umbrella contract; incorporates Schedules + Order Forms by reference |
| 2 | [Solution Specific Schedule – Core, Cobalt, OST](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Solution%20Specific%20Schedule%20-%20Core,%20Cobalt,%20and%20OST.docx) | Solution Schedule (+ OST Addendum + End-Use Statement) | Core Impact, Cobalt Strike, Outflank Security Tooling (offensive security) | — | per MSA | Dual-use export-controlled; embeds OST Addendum + End-Use Statement |
| 3 | [Solution Specific Schedule – Digital Defense & Beyond Security](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Solution%20Specific%20Schedule%20-%20Digital%20Defense%20and%20Beyond%20Security.docx) | Solution Schedule | Digital Defense (Frontline VM) + Beyond Security (vuln scanning / pentest services) | — | per MSA | Adds network-intrusion consent + waiver of claims |
| 4 | [Solution Specific Schedule – Terranova](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Solution%20Specific%20Schedule%20-%20Terranova.docx) | Solution Schedule | Terranova (security awareness training) | — | per MSA | SCORM/downloadable content + Phishing Simulator terms |
| 5 | [Solution Specific Schedule – Agari, Phishlabs, Clearswift](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Solution%20Specific%20Schedule%20-Agari,%20Phishlabs,%20and%20Clearswift.docx) | Solution Schedule | Agari, PhishLabs, Clearswift (email security / brand protection) | — | per MSA | **"No additional terms"** — relies entirely on the MSA |
| 6 | [Alert Logic Solution Specific Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Alert%20Logic%20Solution%20Specific%20Schedule%20(20%20MAY%2024).docx) | Solution Schedule | Alert Logic (MDR / managed detection) | 20 MAY 24 | per MSA | Appliance warranty, Node/log entitlements + **overage tiering** |
| 7 | [Digital Guardian Cloud Services Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Digital%20Guardian%20Cloud%20Services%20Schedule%20(04%20DEC%2024)%20(1).docx) | Cloud/SaaS Schedule | Digital Guardian (DLP) — SaaS | 04 DEC 24 | per MSA | Sample Match Data add-on module |
| 8 | [Digital Guardian Managed Services Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Digital%20Guardian%20Managed%20Services%20Schedule%20(04%20DEC%2024).docx) | Managed Services Schedule | Digital Guardian (DLP) — Managed | 04 DEC 24 | per MSA | **Seat**-based; setup fee + monthly per-seat fee; 24×7 availability |
| 9 | [Digital Guardian Secure Collaboration Encryption Services Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Digital%20Guardian%20Secure%20Collaboration%20Encryption%20Services%20Schedule.docx) | Cloud/SaaS Schedule | DG Secure Collaboration (encryption, fka Vera) | — | per MSA | Internal vs External User distinction (External not billed) |
| 10 | [Schedule SFTaaS – Globalscape Arcus & GoAnywhere MFTaaS](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Schedule%20SFTaaS%20(Globalscape%20Arcus%20GoAnywhere%20MFTaaS)_final-clean-Mar21.docx) | Cloud/SaaS Schedule | GoAnywhere MFTaaS (AWS) + Globalscape Arcus (Azure) | "final-clean-Mar21" | per MSA | Pass-through to AWS/Microsoft customer agreements; references DPA |
| 11 | [Tripwire Managed Services Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Tripwire%20Managed%20Services%20Schedule%20(7%20July%2023).docx) | Managed Services Schedule | Tripwire **ExpertOps** (FIM / SCM) | 7 July 23 | per MSA | Hosted Service vs Remote Operations; **no auto-renew** |
| 12 | [Tripwire Professional Services Schedule](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Tripwire%20Professional%20Services%20Schedule%20(7%20July%2023).docx) | Professional Services Schedule | Tripwire | 7 July 23 | per MSA | Day-rate (8h), reschedule fees, 1-yr prepaid PS expiry |
| 13 | [Offensive Security Solutions EULA Template](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Fortra%20LLC%20-%20Offensive%20Security%20Solutions%20EULA%20Template%20V.110422.docx) | **EULA** (standalone) | Core Impact, Cobalt Strike, OST | V.110422 (Nov 4 2022) | **Delaware** | Standalone alternative to MSA+Schedule for offensive tools |
| 14 | [Fortra Evaluation Agreement](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Fortra%20Evaluation%20Agreement%20(Nov%202022)%20(1).docx) | **Eval** | Any Fortra product | Nov 2022 | Minnesota | 30-day no-cost eval; liability cap **$100** |
| 15 | [Fortra Client DPA](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Fortra%20Client%20DPA%20July%20with%20Sig%20Blocks%202024.docx) | **DPA** | All (data processing) | July 2024 | per Services Agreement | GDPR/UK GDPR/FADP/CCPA; SCCs; Schedule 1 (processing) + Schedule 2 (TOMs) |
| 16 | [Updated End Use Statement](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/Updated%20End%20Use%20Statement%20-%20110722%20(1).docx) | **End-Use Statement** | Core Impact, Cobalt Strike, OST (dual-use) | 110722 (Nov 7 2022) | US/Dutch export law | Export-control certification; Chamber-of-Commerce legalization |
| 17 | [OST Solution Addendum (clean)](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/OST%20Solution%20Addendum%20CLEAN%20110722.docx) | Addendum | Outflank Security Tooling | 110722 (Nov 7 2022) | per MSA | Account/Use-Case/Use-By-Date controls; logging & reporting |
| 18 | [NDA – Fortra (Int'l) Mutual (Security Requests)](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20(Int'l)%20Mutual%20Feb%202025%20(Security%20Requests).docx) | **NDA** (mutual) | Fortra International Ltd (UK entity) | Feb 2025 | **England & Wales** | Scoped to reviewing Fortra security collateral (SOC2/BCP/DR/CAIQ) |
| 19 | [NDA – Fortra (UK) Mutual + License Restrictions](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20(UK)%20Mutual%20License%20Restrictions%20(Nov.%202024)%20(1).docx) | NDA + Eval license | Fortra International Ltd | Nov 2024 | England & Wales | Adds 30-day Evaluation License clause |
| 20 | [NDA – Fortra (UK) Mutual](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20(UK)%20Mutual%20Nov%202022.docx) | NDA (mutual) | Fortra International Ltd | Nov 2022 | England & Wales | Base UK mutual NDA |
| 21 | [NDA – Fortra Mutual + License Restrictions](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20Mutual%20&%20License%20Restrictions%20(Nov%202022).docx) | NDA + Eval license | Fortra LLC (US) | Nov 2022 | Minnesota | US mutual NDA + 30-day Eval license clause |
| 22 | [NDA – Fortra Mutual (Spanish)](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20Mutual%20(Nov%202022)-Spanish.docx) | NDA (mutual, Spanish) | Fortra LLC (US) | Nov 2022 | Minnesota | "Acuerdo de Confidencialidad" — Spanish translation |
| 23 | [NDA – Fortra Mutual (Security Requests)](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20Mutual%20April%202025%20(Security%20requests).docx) | NDA (mutual) | Fortra LLC (US) | April 2025 | Minnesota | Scoped to reviewing security collateral (SOC2/BCP/DR/CAIQ/SIG) |
| 24 | [NDA – Fortra Mutual](Fortra%20Discovery%20Documentation/Contracts%20and%20Legal%20Documents/NDA%20-%20Fortra%20Mutual%20Nov%202022%20(2).docx) | NDA (mutual) | Fortra LLC (US) | Nov 2022 | Minnesota | Base US mutual NDA |

**Fortra legal entities seen:** `Fortra, LLC` — Delaware LLC, **11095 Viking Drive, Suite 100, Eden Prairie, MN 55344**
(notices to `Contracts@Fortra.com`, Attn: Legal). `Fortra International Limited` — **3rd Floor, 1 Ashley Road, Altrincham,
Cheshire WA14 2DT, UK**. The Netherlands/Dutch CDIU (Central Import & Export Office) appears for the offensive-security (OST) export path.

---

## 2. Master agreement architecture

```
                          MASTER SOLUTIONS AGREEMENT (MSA)
                          standard T&Cs, governs ALL solutions
                                       │  incorporates by reference
        ┌──────────────────────────────┼───────────────────────────────────┐
        │                              │                                    │
  SOLUTION SPECIFIC SCHEDULE(S)   ADDENDUMS / DPA                     ORDER FORM(s)
  (per brand / per delivery type) (data processing, OST)     = the transactional doc
                                                              (quote / SOW / portal purchase)
                                                              → license type, metric, term,
                                                                cost, payment terms
```

### 2.1 Order of precedence (MSA §15)
On conflict, this order **controls** (highest first):
1. **Solution Specific Schedule** (if any)
2. **The MSA** itself
3. **The Order Form**

Each individual Schedule additionally states: *"This Schedule will control in case of any conflict between … this Schedule and
the Agreement."* The DPA, however, **overrides everything** for data-processing matters, and the **Standard Contractual Clauses
override the DPA**.

Client purchase-order terms are expressly **rejected and null/void** (MSA §15). English-language version prevails over any translation.

### 2.2 Core MSA defined terms (reusable vocabulary for SF data model)

| Term | Definition (MSA) | SF/RCA relevance |
|------|------------------|------------------|
| **Solution** | Any service, software, and/or appliance ordered | Product2 / catalog |
| **Order Form** | Transactional doc (quotation or SOW) stating license type, **license metric** (subscription / perpetual / term), cost, payment terms | = Quote / Order in RCA |
| **Solution Specific Schedule** | Per-solution descriptions, specs, service levels | Brand attribute on Product / contract template |
| **Service** | Managed / Maintenance / cloud / SaaS hosted by Fortra | Selling-model / line-type |
| **Professional Services** | Implementation, integration, training, data conversion, on-site consult — **excludes Maintenance** | Separate PS line items / SOW |
| **Maintenance Fees / Maintenance Period / Maintenance Services** | Annual fees + period for perpetual/term licenses; access to tech support, self-service, updates/enhancements | Maintenance line items; renewal logic (COLA) |
| **Subscription Fees / Subscription Period** | Annual fees + period for subscription licenses (includes Maintenance) | Subscription pricing engine (RLM) |
| **Seats** | Individuals with unique user ID; "active"/"inactive" | Quantity / usage metric |
| **Authorized Users / Authorized Devices** | Who/what may use the Solution per Order Form | Entitlement quantity caps |
| **Excluded Data** | ITAR data; PCI/GLBA financial data; HIPAA PHI; SSN/passport/license #; unencrypted-in-transit data | Compliance — must NOT flow to Fortra |

---

## 3. Key recurring terms relevant to quoting / billing / contracts in Salesforce

### 3.1 Term, renewal & auto-renewal (the single most billing-relevant cluster)

| Instrument | Initial term | Renewal | Non-renewal notice | Price-change notice |
|------------|--------------|---------|--------------------|---------------------|
| **MSA (the master)** | **3 years** | Auto-renew successive **1-year** | ≥ 60 days before term end | n/a (master) |
| **MSA — Order Form** | As stated; **default 12 months** if unspecified | Auto-renew, same duration | ≥ 60 days before Renewal Term | Fortra ≥ 60 days for amended terms / price increase |
| **MSA — Maintenance/Subscription Period** | Per Order Form | Auto-renew successive **12-month** | ≥ **60 days** to cancel Maintenance | Fees change at Fortra's discretion each period |
| **Core/Cobalt/OST Schedule + EULA** | Default 12 months | Auto-renew, same duration | ≥ **30 days** before Renewal Term (note: shorter than MSA's 60) | Fortra ≥ 60 days |
| **Tripwire Managed (ExpertOps)** | Per Order Form; default **12 months** | **Does NOT auto-renew** — Client must place a new Order Form per renewal | n/a | 6-month notice before end-of-availability of a Service |
| **Tripwire Remote Operations** | ≥ 1 year minimum | New Order Form | — | — |
| **Evaluation Agreement** | **30 days** (extendable in writing) | None | Auto-expires; uninstall required | n/a |
| **NDAs (all)** | Until terminated | n/a | **15 days** written notice to terminate; confidentiality survives **3 years** (trade secrets indefinitely) | n/a |
| **DPA** | Co-terminus with Services Agreement | — | Delete/return data ≤ **90 days** after cessation | — |

> **MSA self-termination quirk:** the MSA *automatically terminates 6 months after the last Order Form then in effect expires/terminates.*
> Relevant for any "contract still active?" logic.

### 3.2 Payment terms (MSA §2 — default, overridable by Order Form)
- **Billing cadence:** all Solution fees invoiced **annually, in advance**.
- **Payment due:** within **30 days** of invoice receipt, **in U.S. dollars**.
- **Late charge:** lesser of **1.5%/month** or legal max on undisputed overdue amounts.
- **No refunds/credits** unless specified.
- **Taxes:** quoted **exclusive** of sales/use/excise/VAT; client pays its own taxes net of withholding; gross-up clause if withholding required; valid tax-exemption certificate needed to avoid collection.
- **Suspension trigger:** Fortra may suspend if undisputed amount is **10+ days overdue** (MSA §4); Alert Logic schedule allows data erasure after **30 days** delinquent/suspended/terminated.

### 3.3 License grant defaults (MSA §3)
- Standard grant: **limited, non-exclusive, non-transferable, non-assignable, worldwide**, scoped further by Order Form license metric.
- **Transfers** require prior written Fortra consent (sole discretion), possible fee, removal from prior device/user, current on Maintenance Fees.
- **Client cannot assign** the MSA at all (operation of law or otherwise) — assignment is null/void.

### 3.4 Liability caps (varies sharply by instrument — relevant for risk on each SKU family)

| Instrument | Liability cap |
|------------|---------------|
| MSA | Amounts paid by Client in the **12 months** prior to the act/omission |
| Core/Cobalt/OST Schedule & EULA | Amount paid for the **particular Solution license** |
| Alert Logic Schedule | **US $100** total aggregate |
| Evaluation Agreement | **$100** direct damages |
| DPA | Inherits Services Agreement cap (aggregated with all other claims) |

### 3.5 Warranty
- MSA: Solution (excl. Service) conforms to spec for **90 days**; a Service performed workmanlike for **10 days** (unless Schedule says otherwise). Sole remedy = re-perform / commercially reasonable efforts to fix.
- Offensive tools (Core/Cobalt/OST, EULA): **"AS IS"**, no warranties.
- Alert Logic appliance: 90-day defects warranty (repair/replace).
- Tripwire Managed: remedy = **SLA credit** (request within 10 days of event); Client Content restore = sole remedy for deletion/corruption.

### 3.6 Confidentiality / audit / export (compliance fields)
- **Confidentiality:** mutual; reasonable standard of care; return/destroy on request (backups exempt).
- **Audit (MSA §8):** Fortra may audit compliance; Client bears cost if non-compliant.
- **Export control (MSA §12):** EAR/cybersecurity-item controls; no export to embargoed countries (Cuba, Iran, Sudan, North Korea, Syria); anti-corruption (FCPA, UK Bribery Act); Commercial Item / 48 CFR FAR clauses for US Gov end-users.
- **Data residency/processing:** governed by DPA → see §6.

---

## 4. Solution-Specific Schedules — purpose & operationally-relevant terms

### 4.1 Core Impact, Cobalt Strike, Outflank Security Tooling (OST) — offensive security
**Purpose:** licenses penetration-testing / red-teaming tools for *lawful and ethical* use to vetted, technical end-users.
This is Fortra's **most heavily controlled** SKU family.

- **License grant:** non-exclusive, non-transferable, **non-sublicensable**; **one Authorized User per purchased license key**.
- **Authorized Users:** must be named on Order Form **or End-Use Statement**; role change / departure = immediate Order Form amendment; additions need written Fortra approval; **no refund** for unused capacity.
- **End-Use Statement (mandatory):** export-control certification (see §5). Required before provision.
- **Renewal:** default 12 months, auto-renew, **30-day** non-renewal notice.
- **Support:** email only; no support for 3rd-party deps (Metasploit Framework, Java frameworks).
- **Audit:** independent third-party auditor permitted (sensitive nature). Records retention **3 years** post-term (OST).
- **Governing law (EULA standalone):** **Delaware** (note: differs from MSA's Minnesota).

**OST Solution Addendum (extra controls — unique to OST):**
- **Account** per Authorized User; accounts strictly non-shareable.
- **Use-Case** model: each access tied to a **codename** + **Use-By Date**; tooling must be **irreversibly deleted on/before Use-By Date**.
- **Reporting:** maintain Records of all Use-Cases, users, Use-By Dates, deletions for **3 years**; annual report to Fortra (or on request).
- **Log Confirmation:** Fortra may send access logs ≤ 4×/year (more if suspicious / labeled "Urgent"); Client confirms within **3 weeks**.
- **Support helpdesk:** **9:00–18:00 CEST**, Mon–Fri, excl. Dutch holidays (OST is a Netherlands-run platform).

### 4.2 Digital Defense & Beyond Security — vulnerability scanning / pentest services
**Purpose:** active scanning / intrusion-style services.
- **Network Intrusion Consent + Waiver:** Client expressly consents to invasive/intrusive techniques and **waives claims** for inadvertent system/data damage — *conditioned* on Fortra performing per the Agreement; Fortra still indemnifies per MSA §10. Only schedule with this consent clause.

### 4.3 Terranova — security awareness training
**Purpose:** SCORM training content, phishing simulation.
- **Downloadable Content** (SCORM files, videos, posters): limited, non-exclusive, non-transferable license for **internal training only**, no derivatives; permanently delete at term end + sworn officer statement on demand.
- **Usage proof / true-up:** Client must demonstrate Authorized-User counts on demand; **pay underpaid fees** revealed by verification → relevant for usage-based billing reconciliation.
- **Phishing Simulator:** internal use only, own/controlled domains only, lawful content; collects IP/browser/OS metadata (not user-entered data). Gmail/Outlook **Phish Submitter** add-ons forward reported emails to security team.

### 4.4 Agari, PhishLabs, Clearswift — email security / brand protection
**Purpose:** email security suite. **No additional terms** — operates entirely under the MSA. (Simplest schedule.)

### 4.5 Alert Logic — managed detection & response (MDR)
**Purpose:** cybersecurity solution = Appliances + Cloud Software + Solution Services (SOC threat detection).
- **Appliance:** title stays with Fortra; risk of loss on shipment; **90-day** materials/workmanship warranty; may include 3rd-party/open-source (e.g., Linux).
- **Entitlement = Nodes + log data usage.** **Overage model (billing-critical):**
  - Exceed Entitlement → **30-day Usage Grace Period** to come back in-bounds.
  - If not: auto-**Upgraded Entitlement** tier for remainder of term + **Overage Fees** billed in arrears from first day of the month the overage occurred; Order Form revised; Upgraded Entitlement carries into renewals.
  - Default rate = then-current list price if Order Form silent.
- **Service Commencement Date:** if Order Form effective ≤ 15th of month → 1st of next month; if > 15th → 1st of second next month. (Affects billing start date.)
- **Excluded Data** extended to include unencrypted **Personal Data** (except Required Personal Data: IPs, User IDs/hostnames, contact info).
- **Liability cap = US $100.** Terms modifiable via URL/email with 30-day reject window.

### 4.6 Digital Guardian (DG) — Data Loss Prevention; three delivery schedules
DG appears as **three separate schedules** by delivery model:

**(a) DG Cloud Services (SaaS):**
- Non-exclusive, non-assignable, worldwide right for **internal business operations** during Subscription Period.
- **Sample Match Services / Sample Match Data:** DG may collect sensitive data (names, SSNs, credit cards) when rules match; **disabled by default**, requires a **dedicated add-on module license** → a discrete SKU/entitlement to model.
- Data deletion if account delinquent/suspended/terminated **30+ days**.

**(b) DG Managed Services (Seat-based):**
- **Seats** = OS instances with DG software installed (or users on shared virtualized server).
- Add Seats mid-term at **same pricing, prorated**, co-terminating with existing services.
- **Fees:** (i) one-time **setup fee** + (ii) **monthly per-seat** ongoing fee; based on purchased Seats not actual usage; **non-cancellable, non-refundable**; Seat count **cannot decrease** mid-term.
- **Availability:** commercially reasonable **24×7**; planned downtime ≥ 8h notice, scheduled Fri 6pm–Mon 3am ET.
- **Client Metadata** (file/user/event/time) handled with safeguards.

**(c) DG Secure Collaboration Encryption Services:**
- **Internal User** (Client-domain identity, can create/own Content) vs **External User** (non-Client domain, collaborate/read only). **External Users are NOT Authorized Users for billing** → only Internal Users count toward fees.
- Fortra cannot view Client Content; open-source components governed by their own licenses (Open Source License Terms override on conflict).

### 4.7 Globalscape Arcus & GoAnywhere MFTaaS — secure file transfer (SFTaaS)
**Purpose:** hosted secure-file-transfer-as-a-service.
- **Two products / two clouds:** **Globalscape Arcus** runs on **Microsoft/Azure** (Microsoft Client Agreement); **GoAnywhere MFTaaS** runs on **AWS** (AWS Customer Agreement). Client+Fortra both agree to the underlying hyperscaler terms.
- **Subscription Services** = hosted software + updates + Maintenance; explicitly **not Professional Services**.
- License delivered via a **key**; deemed delivered/accepted on availability.
- **Personal Information** processed per the **Fortra DPA** (`fortra.com/legal/data-processing-agreement`).
- **Incorporated addenda:** GoAnywhere SaaS Policies + GoAnywhere MFT Client Care Manual; Globalscape Arcus Service Level Policy; Fortra DPA.
- **Feedback** = perpetual royalty-free license to Fortra; never Client Confidential Information.

### 4.8 Tripwire — Managed Services (ExpertOps) and Professional Services
**Tripwire Managed (ExpertOps):**
- Two delivery methods under one "Service": **Hosted Service** (Fortra-cloud) vs **Remote Operations** (Fortra remotely manages Client's on-prem Software; needs ≥ 1 year support).
- **Software is licensed, not sold.** Term default **12 months**; **NO auto-renew** (new Order Form per renewal); 6-month end-of-availability notice.
- Term start: Remote Ops = first day of the month service activates (full-month increments); Hosted = day credentials/console/agents provided.
- **Increase nodes / upgrade Service Tier** mid-term by new order + fees.
- **PCI DSS responsibility matrix** (except Remote Ops); SOC 2 safeguards; restore-from-backup = sole remedy for Content loss.
- **Non-solicit:** no soliciting Fortra staff during + **6 months** after.

**Tripwire Professional Services:**
- Scope: implementation/upgrade, design/architecture/integration, **Resident Engineer** term engagements (remote or on-site).
- **Billing:** full-**Day** increments; a **Day = 8 hours**. ≥ 5 Days → option of 4×10-hour days invoiced as 5 Days.
- **Prepaid PS expires after 1 year**, no refund.
- **Reschedule fees:** **20%** if < 10 business days' notice; **50%** if < 5 business days' notice; plus non-refundable expenses.
- No termination for convenience once Order Form accepted (without other party's consent).
- Expenses reimbursed at cost up to a not-to-exceed; **6-month non-solicit**.

---

## 5. End-Use Statement & export control (offensive-security gate)

Mandatory for **Core Impact + Cobalt Strike + OST** (dual-use cyber tools under US **EAR** and **Dutch/EU Dual-use Regulation**).
Must be completely and truthfully filled out **before** Fortra provisions. If Client is **outside the EU customs union and outside
EU001 GEA countries**, the statement must be **legalized by the local Chamber of Commerce** (or competent authority).

**Structure (4 tables):**
- **A. Parties** — Supplier = Fortra LLC (Eden Prairie MN); Client = Recipient.
- **B. Dual-use services/technology** — description (Cobalt Strike / OST / Core Security); end-use type (internal red teaming / external red teaming on customers' environments / other); end-use location(s).
- **C. Certification** — Client certifies: lawful/ethical pentest only with written consent of tested org; **no** law-enforcement / intelligence / military / surveillance / human-rights-violating use; confidential, not passed to others; not used to build competing tech; subject to US + Dutch export jurisdiction; not embargoed (Cuba/Iran/Syria/Sudan/North Korea); not on SDN/Entity/Denied-Persons/Excluded-Parties lists; import authorization provided or not required. **Certifications survive termination.**
- **D.** Chamber-of-Commerce legalization stamps.

**If an export application is not approved, Fortra can terminate.** Client pays export application fees. Same certification logic appears
in the Core/Cobalt/OST Schedule, the EULA, and the standalone End-Use Statement (all consistent).

> **SF relevance:** for these SKUs, a signed End-Use Statement + (for some geos) legalization is a **provisioning prerequisite** — a candidate
> compliance checkpoint/flag on the Account or Order before fulfillment can proceed.

---

## 6. Data Processing Agreement (DPA) — privacy/compliance backbone

**Incorporated by reference into the MSA / Services Agreement.** Fortra = **Processor** (or **Sub-processor** if Client is itself a Processor);
Client = **Controller**. DPA overrides the Services Agreement on data matters; **SCCs override the DPA**.

**Laws covered:** GDPR (+ Member State laws), **UK GDPR** + Data Protection Act 2018, Swiss **FADP**, **CCPA** (as amended by CPRA, eff. 1 Jan 2023).

**Key operational terms:**
- Process only on **Client's written instructions**; **no sale/share** of Client Personal Data (CCPA); no use outside the business relationship; may use **anonymized** data (and non-anonymized **threat information** if Client not identified as source) to improve Services.
- **Sub-processors:** general authorization; list on request; Client objects within **10 days**; unresolved in **30 days** → either party may terminate affected Services (sole remedy). Fortra remains fully liable for sub-processors.
- **Breach notification:** without undue delay; include nature, contact, consequences, remediation.
- **Deletion/return:** delete or return Client Personal Data ≤ **90 days** after Service cessation (on written request).
- **Audit:** once per calendar year, at Client's cost, **no premises/systems access**; agreed scope; results are Fortra confidential.
- **International transfers:** EU SCCs (Implementing Decision (EU) 2021/914, Modules 2 & 3) + UK Addendum (ICO) + Swiss adaptations; execution of the Services Agreement = execution of the SCCs. FISA §702 safeguard reps.
- **Liability:** inherits the Services Agreement cap (aggregated).

**Schedule 1 — Data Processing Instruction (categories to capture for records of processing):**
- *Types of Personal Data:* name; business contact info (company, email, phone, fax, address, zip); personal contact info; local identifiers (passport, tax ID, SIN, license #); title; position; employer; ID/professional/personal-life data (security Q&A); connection/localization/device data; network data (source/dest IP); log/config/diagnostic data; electronic credentials (IP, username, password); special categories if applicable.
- *Data Subjects:* Client's customers/partners/vendors (natural persons); their employees/contacts; Client's employees/agents/advisors/contractors/authorized users.
- *Frequency/duration:* continuous, for the Services Agreement duration.

**Schedule 2 — Technical & Organizational Measures (TOMs)** — a full security-controls catalog Fortra commits to (useful as the canonical
list of Fortra's stated security posture):
Organization of Information Security; Asset Management; Personnel Security & Acceptable Use; Access Control (RBAC, ≥ 8-char passwords, regular rotation);
Working Remotely (no remote work in sanctioned/high-risk countries); Server/Serverless Security; Key Management & Cryptography; Backup & Restoration
(offsite copies, tested); Change Management (routine vs emergency); Incident Management (**SIRT**, mandatory reporting); Logging & Monitoring;
Vulnerability & Penetration Testing (independent 3rd-party); Software Development Lifecycle (PRD-driven); Data Retention & Disposal (IP/PII/PHI/BSI);
Information Classification (**Public / Internal / Confidential**); Workstation & Mobile Device; Network Security (segregation, anti-malware, encryption in transit);
**Artificial Intelligence** (no copyrighted/proprietary/customer data into AI models without authorization; AI augments not replaces humans);
Business Continuity & DR (BIA/BCP/DRP, annual); Risk Assessment; Vendor Management; Customer Support & Responsiveness.

---

## 7. Evaluation Agreement & Eval-license clauses

**Standalone Evaluation Agreement (Nov 2022):**
- No-cost, **30-day** Evaluation Period (extendable in writing); temporary, limited, non-exclusive, non-transferable license; **no copies**.
- Customer **uninstalls / returns** at end; bound by product EULA on download/install.
- **Liability cap $100**; "AS IS"; confidentiality survives **5 years**; Minnesota law; no purchase obligation.

**Eval-license clauses embedded in two NDAs** (US Nov 2022 + UK Nov 2024 "License Restrictions" variants): same 30-day eval, eval product treated
as Confidential Information; prohibitions on reverse-engineering, redistribution, copies, removing notices, publishing benchmarks.

---

## 8. NDA family (7 documents)

All are **mutual** NDAs sharing one base template; they differ by **(a) signing entity / governing law**, **(b) permitted-purpose scope**,
**(c) presence of an Eval-license clause**, and **(d) language**.

| Variant | Entity / Law | Purpose scope | Eval clause? | Notes |
|---------|-------------|---------------|--------------|-------|
| US Mutual (Nov 2022) | Fortra LLC / Minnesota | Evaluate/pursue business relationship | No | Base US |
| US Mutual + License Restrictions (Nov 2022) | Fortra LLC / Minnesota | Same | **Yes** (30-day eval) | |
| US Mutual (Spanish, Nov 2022) | Fortra LLC / Minnesota | Same | No | Spanish translation; note: only 11 clauses (Return-of-Materials lacks the retained-copy carve-out) |
| US Mutual — Security Requests (April 2025) | Fortra LLC / Minnesota | **Review Fortra security collateral**: SOC 2, BCP/DR, vuln scans, pentests, CAIQ/SIG | No | Purpose narrowed to vendor-security review |
| Int'l Mutual — Security Requests (Feb 2025) | Fortra Int'l Ltd / England & Wales | Same security-review scope | No | UK-law twin of the April 2025 US version |
| UK Mutual (Nov 2022) | Fortra Int'l Ltd / England & Wales | Evaluate/pursue business relationship | No | Base UK |
| UK Mutual + License Restrictions (Nov 2024) | Fortra Int'l Ltd / England & Wales | Same | **Yes** (30-day eval) | |

**Common NDA terms:** mutual; "Confidential Information" excludes public/independently-developed/rightfully-received/compelled-disclosure;
no license granted; return/destroy on termination (one retained copy permitted by US/UK versions for legal/archival); **15-day** termination notice;
confidentiality survives **3 years** (trade secrets indefinitely); "AS IS"; prevailing-party attorneys' fees; injunctive relief available.

The **"Security Requests"** variants are notable: their permitted purpose is specifically *reviewing Fortra's own security posture documents*
(SOC 2, BCP/DR, vulnerability scans, penetration tests, **CAIQ/SIG** questionnaires) — i.e., used when a prospect's security team vets Fortra,
not for general deal discussions.

---

## 9. Open questions / ambiguities

1. **Order Form ↔ Quote/Order mapping.** Legal docs use "Order Form"; RCA uses Quote/Order. Confirm which RCA object is the contractual "Order Form" and how Schedule selection (brand) is captured on the Quote/Order for DocGen.
2. **Auto-renew divergence.** MSA Order Forms auto-renew (60-day notice); Core/Cobalt/OST use **30-day** notice; Tripwire ExpertOps **does not auto-renew at all**. The renewal automation (and COLA renewal universe, SC-3350) must be brand/SKU-aware — a single global auto-renew rule would be wrong for Tripwire and mis-time the offensive-security notice window.
3. **Liability-cap by SKU.** Alert Logic ($100) and offensive tools (per-license) cap differently from the MSA (12-month). Not a billing field per se, but relevant if contract metadata is surfaced in SF.
4. **Governing-law split.** MSA/most = Minnesota; **EULA = Delaware**; UK/Int'l NDAs = England & Wales. Entity selection (Fortra LLC vs Fortra International Ltd) drives this — needs an entity/region attribute somewhere in the data model.
5. **Usage true-up / overage billing.** Alert Logic (Node/log overage tiering) and Terranova (user-count true-up) imply consumption reconciliation back to Workday/billing. Where is overage measured and how does it post? Not covered in these legal docs.
6. **Export/End-Use enforcement in SF.** No discovery doc here states *how* the mandatory End-Use Statement / legalization is enforced operationally for offensive-security SKUs (manual gate vs. system flag). Likely needs an Account/Order compliance checkpoint.
7. **Schedule effective dates.** Several Schedules (Digital Defense/Beyond Security, Terranova, Agari/Phishlabs/Clearswift) carry **no version/date** in the extracted text — version control of these templates is unclear.
8. **DG add-on module licensing.** Sample Match Data requires a "dedicated add-on module license" — confirm this is a distinct catalog SKU/entitlement in RCA.
9. **No Solution Specific Schedules** were found in this corpus for several brands referenced elsewhere in the program (e.g., a dedicated Tripwire *software* schedule beyond Managed/PS, or GoAnywhere on-prem). The corpus is SaaS/Managed/PS-heavy; perpetual on-prem software schedules may live elsewhere.

---

## Sources

All paths relative to repo root; extracted text under `Data/discovery-extract/text/Contracts and Legal Documents/`, originals under `Fortra Discovery Documentation/Contracts and Legal Documents/`.

- Fortra Master Solutions Agreement with Sig Blocks 09_04_24 (7).docx
- Solution Specific Schedule - Core, Cobalt, and OST.docx
- Solution Specific Schedule - Digital Defense and Beyond Security.docx
- Solution Specific Schedule - Terranova.docx
- Solution Specific Schedule -Agari, Phishlabs, and Clearswift.docx
- Alert Logic Solution Specific Schedule (20 MAY 24).docx
- Digital Guardian Cloud Services Schedule (04 DEC 24) (1).docx
- Digital Guardian Managed Services Schedule (04 DEC 24).docx
- Digital Guardian Secure Collaboration Encryption Services Schedule.docx
- Schedule SFTaaS (Globalscape Arcus GoAnywhere MFTaaS)_final-clean-Mar21.docx
- Tripwire Managed Services Schedule (7 July 23).docx
- Tripwire Professional Services Schedule (7 July 23).docx
- Fortra LLC - Offensive Security Solutions EULA Template V.110422.docx
- Fortra Evaluation Agreement (Nov 2022) (1).docx
- Fortra Client DPA July with Sig Blocks 2024.docx
- Updated End Use Statement - 110722 (1).docx
- OST Solution Addendum CLEAN 110722.docx
- NDA - Fortra (Int'l) Mutual Feb 2025 (Security Requests).docx
- NDA - Fortra (UK) Mutual License Restrictions (Nov. 2024) (1).docx
- NDA - Fortra (UK) Mutual Nov 2022.docx
- NDA - Fortra Mutual & License Restrictions (Nov 2022).docx
- NDA - Fortra Mutual (Nov 2022)-Spanish.docx
- NDA - Fortra Mutual April 2025 (Security requests).docx
- NDA - Fortra Mutual Nov 2022 (2).docx

*All 24 in-scope files were extracted as clean plaintext and read in full. None were encrypted, binary, or empty.*
