# 26 — Cross-Team: Current (As-Is) Payment & Deposit Process

> **Scope:** Discovery walkthrough of how Fortra receives, deposits, applies, and reconciles **customer cash/payments today** (as-is), across multiple legacy billing systems. Captured from a single cross-team meeting between the **CRM (D365→Salesforce) discovery team**, the **Finance / Cash Applications team**, the **Treasury team**, and the **Workday/integration (Coastal/Strada) team**.
>
> **Source:** [Current Payment Deposit Process.docx](../Fortra%20Discovery%20Documentation/Cross%20Team%20Meetings/Current%20Payment%20Deposit%20Process.docx) — Teams meeting transcript, **2025-05-20, 5:01 PM** (transcription started by Dawn Krauss).
>
> **Why this matters for the implementation:** This is the *as-is* baseline for the **order-to-cash (O2C) cash-application layer** that future-state Salesforce RCA → MuleSoft → Workday must replace. The meeting was explicitly scoped to *current state only* ("not really focus on the future state… tell us what we're looking at today"), but several future-state Workday integration hooks were called out and are flagged below.

---

## 1. Meeting context, participants & purpose

| Attribute | Detail |
|---|---|
| Date / time | 2025-05-20, 17:01 (transcription start) |
| Duration | ~29.5 min |
| Format | MS Teams call, recorded |
| Convener | **Dawn Krauss** (CRM rebuild / discovery lead) |
| Purpose | Connect CRM-discovery, Finance, Treasury and integration teams; capture the *as-is* payment/deposit business process so the **billing solution between CRM (D365→Salesforce) and the Workday financial system** can be designed. This was a **follow-up** to an earlier billing-solution meeting that surfaced this gap. |

### Participants and roles

| Person | Team / Role | Why present |
|---|---|---|
| **Dawn Krauss** | CRM rebuild / discovery program lead | Convener; framing & recap |
| **Trisha Dolezal** | **Cash App(lications) Manager**, Finance | Primary narrator of the as-is cash-application process |
| **Courtney Guenigsman** | **Collections** lead, Finance | Co-narrator; collection-status, fees, exceptions, multi-brand systems |
| **German Wren** ("Ren") | (Finance / systems) | Color on InterPayments / Stripe surcharge logic |
| **Jhemma Winkworth** ("Gemma") | **Treasury** team | Bank integrations, Kyriba, future-state goals |
| **LakshmiNarasimhan Srinivasan** ("Lakshmi") | **Workday integration** (Strada/Coastal) | Integration-scope questions; called out future Workday lockbox connector |
| **Alex Mahoney** | **Strada/Coastal** functional team | Asked the originating questions; consumer of the walkthrough |

> **Key downstream contacts named:** **Erik Tom Thompson** (Treasury, Finance) — best contact for **Kyriba** detail and **banking contacts** (e.g., JP Morgan rep). **"Javy"** (former employee, now departed) — previously drove the Stripe surcharge / InterPayments initiative and bank-clearinghouse strategy; several threads "paused once Javy left." **"Mays"** — Collections team member who posts Alert Logic payments in NetSuite.

---

## 2. The "as-is" landscape in one diagram (text form)

Fortra is **not yet on a single accounting system**. As of 2025-05-20 there are **multiple parallel billing/AR stacks per acquired brand**, each with its own payment-application path. This is the central complication for the O2C redesign.

| Brand / Entity | CRM | AR / Accounting system | Notes |
|---|---|---|---|
| **Fortra "core" (D365 brands)** | **D365** | **Great Plains (GP)** | Main flow described below; CRM↔GP integration pushes paid status to D365 overnight |
| **Tripwire** | (separate) | **Zuora** ("Zora") **+ its own separate Great Plains instance** | Payments **posted twice** — once in Zuora, once in Tripwire's separate GP |
| **Alert Logic** | (separate) | **NetSuite** (via a **PacWest / "pacquest" / PAC W** domestic bank account) | Posted by Collections member **Mays**; **import to NetSuite** exists; "pre-CRM" |
| **Globalscape** | (separate) | **OrdersX** (e-commerce), credit cards via **CyberSource** | Single product, fixed price; manual; "pre-CRM" |

> Trisha/Courtney explicit call-out: *"we're still not in the same accounting system. We have Great Plains for everything in D365… global scape, tripwire and alert logic are still in their own billing systems."* These are described as **"outside of CRM… pre-CRM."**

---

## 3. Payment channels & end-to-end as-is flows

There are **four customer payment channels** for the core D365/GP flow: **(1) Credit card, (2) Lockbox checks, (3) ACH / wire (electronic), (4)** plus the **brand-specific** flows (Tripwire/Zuora, Alert Logic/NetSuite, Globalscape/OrdersX).

### 3.1 Credit card (D365 portal → Stripe → GP → D365)

**Systems:** D365 invoice → Fortra Portal → **Stripe** → bank (ACH payout) → **Great Plains** → (overnight integration) → **D365**.

**Step-by-step (customer-initiated, "self-pay"):**
1. Invoice in D365 carries a **"pay" link** — present **only for invoices under $10,000 USD**, on **any billing entity**.
2. Customer clicks the link → routed to the **Fortra Portal** → enters card details directly into **Stripe**. **Fortra never stores card data** ("we do not keep any of that information ourselves"; nothing passed via email).
3. On click/payment, the portal **talks back to CRM (D365)** and triggers a **collection status change → "Paid in Portal"** on the invoice.
   - Purpose of the status: tells the team the payment step is complete and they are **awaiting funds**; it **lets the Customer OPS teams release keys / licenses to the customer ahead of actual cash receipt**.
4. **~3 days later** (treated like ACH timing), Stripe sends Fortra **one bulk ACH payout** covering everything processed 3 days prior (e.g., "$34,000… $12,000, however much").
5. When the Cash App team sees the Stripe payout hit the bank, they **log into the Stripe portal**, pull the **payouts for that day** matching the amount, which **lists the individual transaction details** (each payment processed).
6. Cash App follows usual process: **build an import file → import into GP → payments applied to invoices.**
7. **Overnight integration** pushes payment info from GP back into **D365**, marking those invoices **paid**.

**Manual ("assisted") credit-card payments — invoices over $10,000:**
- For card requests **over $10,000**, **Courtney (Collections) approves a manual payment**.
- Collections **manually processes the card in Stripe**, taking card details **over the phone** (again, nothing stored on file, nothing via email).
- Same end result as self-pay; Fortra staff just operate the portal on the customer's behalf with their own access.

**Stripe fees (current state):**

| Scenario | Fee | Treatment |
|---|---|---|
| Customer self-pays in portal | **3% of invoice total** | **Fortra currently absorbs the fee** |
| Fortra makes a manual (assisted) payment | **5%** | Fortra absorbs |
| Fee booking | — | Stripe fees recorded **in the General Ledger at month-end** |

**Surcharge / fee pass-back initiative (paused):**
- Goal was to **pass the 3% to the customer** (added to their total at pay time in the portal) so the customer incurs the fee, not Fortra.
- Implemented via a service called **InterPayments** ("inter/intra payments"), which **integrates into Stripe** ("scribe") and applies the legally-allowable surcharge **based on the customer's city/state/country regulations** — InterPayments owns that logic and decides how much fee can be charged for a given card/location.
- Customer sees the surcharge on the UI and can decline (choose not to pay by card); payment still processes through Stripe, with InterPayments as the **source of allowable fee amount**.
- **Status:** **paused** when **Javy left**. Dawn: it's on the **future tools list**, likely revisited **once on Workday**. (Owner to re-engage: **Eric** per Courtney.)

---

### 3.2 Lockbox checks (JP Morgan lockbox → GP) — "the easier one"

**Systems:** **JP Morgan lockbox** → manual pull → spreadsheet/import → **Great Plains**.

**Step-by-step:**
1. Customers mail checks to the **JP Morgan lockbox**; **all checks are held at JP Morgan**.
2. Checks mailed to the **Eden Prairie office** are **forwarded to the lockbox address**.
3. Cash App **logs into JP Morgan**, pulls **check copies** and a **details report** — but the report comes **without invoice information**.
4. They use the **check copies to derive the invoice information**, then **build an import file → import into GP → apply payments.**
5. They maintain a **spreadsheet/log** of what's been posted and which checks.

**Lockbox exceptions & nuances:**
- Some lockbox receipts are **not AR-related** (e.g., **tax refunds**, **AP refunds / AP credits**) — these are **exception items**; team must **email people and ask questions** to classify.
- **Pre-CRM brands' checks** (Alert Logic, Globalscape) also arrive but are **posted in a system outside Great Plains** (their own brand systems).
- **Currency:** lockbox should be **all USD**, but they **do receive some CAD**. Treasury decided **not to open a Canadian lockbox** (insufficient volume); Canadian customers send checks to the **USD lockbox**, and Fortra **writes off the conversion** difference. CAD checks must be **held 2–3 days until the bank's FX adjustment** posts at JP Morgan before applying.
- **Only one lockbox: JP Morgan. No Bank of America lockbox** (confirmed by Trisha & Jhemma).

---

### 3.3 ACH / wire (electronic payments) (JP Morgan → GP) — the highest-effort channel

**Systems:** **JP Morgan** (12 bank accounts) → manual pull/match → spreadsheet (Paragon-tracked) → **Great Plains** (domestic only).

Trisha refers to these as **"ACH wires" / "electronic payments."**

**Step-by-step:**
1. Pull a **report from JP Morgan** across **12 bank accounts**.
2. **Domestic USD account** = **highest volume + most difficult + most time-consuming**:
   - **95% of payments have NO invoice information** in the bank file.
   - For each: **search the remittances folder → search CRM → find customer → look at open invoices → match → fill the import spreadsheet → import into GP.**
3. **International accounts** = lower complexity ("easier"): Europeans habitually **provide invoice info** (longer history with electronic payments). **International is applied 100% manually — NO GP import file** (no file created/imported for international).

**ACH/wire exceptions & nuances:**
- **Partner payments:** larger, **span multiple end-customer accounts** (could be 10+), and partners **don't send remittances**. Cash App **does NOT post these at all** until the partner supplies a remittance (can't apply to a single customer when funds cover many).
- **Short-pays / over-pays:** constant; especially with partners billed through **multiple legal entities/currencies** who "pick an account" and **pay into the wrong account**. Resolution: push the customer to pay the difference and fix their bank info; **very small differences written off** as conversion.
- **Wrong intermediary banks** used by customers → another source of short-pay/over-pay.
- **Bank fees** (e.g., a **$20 wire transfer fee**, ACH fees): **Fortra currently absorbs / writes these off** ("on ourselves"). Happens **daily**, **mostly on wire payments** more than standard ACH. Talked about passing to customer but "never went anywhere — hard push to enforce."
- **Intercompany / multi-legal-entity:** payments routinely arrive in the **wrong legal entity's account**. Example: the **domestic USD account** receives payments for **Terra Nova** or **Fortra International Limited**. Each such case **requires a manual bank transaction to intercompany the funds** to the correct legal entity. Driven heavily by **acquisition accounts** and **partners** billed across multiple legal entities/currencies.

**Tracking:** Trisha's team maintains a **spreadsheet (in "Paragon")** logging every incoming ACH — what was imported vs. manual entry vs. routed to another system, plus tax-related and recurring (e.g., facilities) items. **Write-offs are tracked** (conversion write-offs vs. bank-fee write-offs are separable on record).

---

### 3.4 Brand-specific legacy flows (pre-CRM, not on D365/GP)

| Brand | System(s) | As-is process | Quirks |
|---|---|---|---|
| **Tripwire** | **Zuora ("Zora") + separate Great Plains instance** | Payment **posted twice**: in Zuora **and** in Tripwire's own separate GP | Double-posting is the headline pain point |
| **Alert Logic** | **NetSuite**, **PacWest ("PAC W"/"pacquest")** domestic bank account; an **HSBC** account also still open | Collections member **Mays** logs into the PacWest domestic account and **posts in NetSuite**. For funds received into **Fortra accounts**, Trisha's team sends a **weekly spreadsheet** (~every **Wednesday**) listing amount/invoice; Mays posts on her side. **NetSuite import exists** for those payments. | Cross-team weekly handoff; "pre-CRM" |
| **Globalscape** | **OrdersX** (e-commerce portal), credit cards via **CyberSource** | Single product, **always $5,999** (fixed price), paid by credit card in OrdersX. Two card settlements received: **American Express**, and **Merchant Bankcard** (covers all non-Amex cards). | Payments are **auto-applied in OrdersX**, but the **money from Merchant Bankcard / Amex isn't received until 3 days later** → team must **manually adjust the payment method and the date** (paid that day, funded 3 days later). Otherwise easy; **all manual, no import.** |

---

## 4. Banks, clearinghouses & Treasury tooling

| Item | Detail |
|---|---|
| **Banks (named)** | **JP Morgan** (lockbox + bulk of ACH/wire reporting), **Bank of America**. Also referenced: **HSBC** (Alert Logic, still open), **PacWest** (Alert Logic NetSuite postings). |
| **Bank accounts** | **12 bank accounts** pulled for ACH/wire reporting; **1 domestic USD account** is the high-volume one. |
| **Lockbox** | **JP Morgan only** (no BofA lockbox). |
| **Card processors** | **Stripe** (D365 core, surcharged via **InterPayments**), **CyberSource** (Globalscape/OrdersX). |
| **Clearinghouse / Treasury platform** | Currently a system Dawn called **"Truvada"** (almost certainly **Trovata** — bank-data aggregation); **moving to Kyriba**. |
| **Kyriba (future Treasury)** | Treasury (Jhemma) can **pull in activity for all banks** via Kyriba (some foreign-bank limitations). Kyriba also provides **dashboards and Treasury reporting**. For **Workday**, the team wants a **direct feed** to **auto-book deposits/payments** rather than manual. Kyriba "can do something similar" but boundaries vs. direct bank↔Workday feeds are **not yet defined**. |
| **JP Morgan internal platform** | Trisha (via Javy) heard **JP Morgan is building its own Trovata/Kyriba-like internal system**; suggested a conversation with the **JP Morgan rep** to see if it integrates directly with Workday — potentially avoiding an outside aggregator ("just have the one"). |

---

## 5. The "Paid in Portal" collection status (CRM hook)

This is the one explicit **CRM-side data point** in the as-is flow and is directly relevant to the Salesforce build:

- **Object:** invoice in **D365** (CRM).
- **Trigger:** customer clicks the invoice "pay" link (sub-$10k invoices) → Fortra Portal → Stripe; the **portal talks back to CRM** and sets a **collection status = "Paid in Portal."**
- **Business value:** signals the payment step is complete and cash is pending; **gates / enables release of keys & licenses by Customer OPS ahead of actual cash receipt.**
- **Implication for SF RCA:** the future Salesforce order-to-fulfillment flow must reproduce an equivalent **"payment initiated / pending settlement" signal** so license/key provisioning can proceed before Workday confirms cash receipt (a ~3-day gap for card/ACH). See connection to fulfillment / license-release logic in the design KB.

---

## 6. Pain points (consolidated) — the as-is friction the redesign must remove

| # | Pain point | Channel(s) | Impact |
|---|---|---|---|
| 1 | **Fragmented accounting systems** (GP, Zuora+separate GP, NetSuite, OrdersX) — not on one ledger | All / multi-brand | Per-brand processes; Tripwire **double-posting**; weekly cross-team spreadsheet handoffs |
| 2 | **95% of domestic ACH/wire payments lack invoice info** | ACH/wire | Heavy manual matching: remittance folder + CRM + open-invoice lookup |
| 3 | **Manual, spreadsheet-driven cash application** end-to-end | All | Build-import-file workflow; Paragon spreadsheet; manual logs |
| 4 | **International ACH applied 100% manually, no import** | ACH/wire (intl) | No automation for non-domestic |
| 5 | **Partner payments without remittances** span many accounts | ACH/wire | Funds held / unposted until remittance arrives |
| 6 | **Short-pays / over-pays, wrong-account & wrong-intermediary-bank** | ACH/wire | Constant rework; chase customers; write-offs |
| 7 | **Intercompany mis-routed receipts** (e.g., Terra Nova, Fortra International Ltd into USD account) | ACH/wire | Manual intercompany bank transactions every time |
| 8 | **Currency / FX:** CAD into USD lockbox; hold 2–3 days for bank FX; conversion write-offs | Lockbox | Delay + write-off leakage |
| 9 | **Fees absorbed by Fortra:** 3%/5% Stripe card fees + daily wire/ACH bank fees | Card, ACH/wire | Margin leakage; surcharge pass-back (InterPayments) **paused** since Javy left |
| 10 | **No lockbox integration in current Workday integration scope** | Lockbox | Flagged by Lakshmi as a scope gap to add to JP Morgan discussions |
| 11 | **3-day settlement lag** (Stripe payout, CyberSource Amex/Merchant Bankcard) | Card | OrdersX requires manual payment-method/date adjustment; "Paid in Portal" status bridges the gap for core flow |
| 12 | **No card data retained** (compliance positive, but) all over-$10k card payments are manual phone-keyed | Card | Manual Collections effort |

---

## 7. Future-state signals & implications for SF RCA → MuleSoft → Workday O2C

> The meeting was scoped to as-is, but the integration/Treasury participants surfaced explicit future-state intentions. These are the actionable design hooks.

1. **Bank-activity direct feeds into Workday.** Treasury's stated goal: **automatic feeds from the banks into Workday** (both **deposits and payments**) to **auto-book entries** instead of manual. SOW currently lists **bank integrations for ~4 banks**, with **two named (JP Morgan, Bank of America)**; intention is to integrate **all activity (deposits + payments) for those banks.**

2. **Workday lockbox connector — add to scope.** Lakshmi flagged that **no lockbox integration is currently in the integration list**. Workday has a **delivered lockbox connector**: receive bank lockbox data → Workday creates a **customer payment + customer deposit** automatically. **Action:** add a **lockbox integration to the JP Morgan integration scope** (Jhemma agreed to add lines as needed).

3. **Kyriba vs. direct bank↔Workday boundary undefined.** Need to define what **Kyriba** owns (multi-bank aggregation, Treasury dashboards/reporting) vs. what flows **directly into Workday** as deposit/payment feeds. Possible overlap; possibly **JP Morgan's own emerging internal platform** could feed Workday directly and remove an aggregator. **Owner to clarify: Erik Tom Thompson (Treasury).**

4. **Surcharge (InterPayments) likely revived on Workday.** Card surcharge pass-through (3% to customer, geo-compliant via InterPayments over Stripe) is **on the future tools list** for the **Workday era**. Owner to re-engage: **Eric**.

5. **Consolidate brand AR onto one system.** The strongest implicit requirement: collapse **Tripwire (Zuora + separate GP), Alert Logic (NetSuite/PacWest/HSBC), Globalscape (OrdersX/CyberSource)** and **core (D365/GP)** into the unified **Salesforce RCA (billing/CRM) ↔ Workday (financial)** target, eliminating double-posting and weekly spreadsheet handoffs.

6. **CRM "payment pending" signal must persist.** Salesforce RCA must reproduce the **"Paid in Portal"** semantic so Customer OPS can release keys/licenses during the **~3-day settlement lag** before Workday confirms cash.

7. **Auto cash-matching to replace 95%-manual ACH matching.** A major value lever: structured remittance capture + auto-application against open invoices in Workday/RCA to eliminate the remittance-folder/CRM-lookup matching that dominates the domestic USD account.

8. **Intercompany & FX automation.** Future state must handle **multi-legal-entity receipts** (Terra Nova, Fortra International Limited, acquisition accounts) and **CAD/USD FX** without per-item manual bank transactions and conversion write-offs.

> **Connection to design KB:** This document is the *raw business discovery* counterpart to the O2C / billing-integration design narratives in `FORTRA_KNOWLEDGE_BASE.md`. The future-state SF RCA→MuleSoft→Workday billing/cash-application design should reconcile against the as-is pain points above; MuleSoft is the integration layer that would carry bank/lockbox feeds and the CRM payment-status signal.

---

## 8. Open questions & ambiguities

- **Kyriba scope vs. direct Workday bank feeds** — exact division of responsibility is undefined (Jhemma deferred to Erik Tom Thompson; "need to dig into all of that").
- **"Truvada"** — almost certainly **Trovata** (transcription artifact); confirm the current clearinghouse/aggregator name and migration timeline to Kyriba.
- **Number of bank integrations** — "~4 banks" referenced, **2 named (JP Morgan, BofA)**; the other ~2 and whether HSBC/PacWest are in scope is unconfirmed.
- **Lockbox integration not yet in the integration list** — needs to be formally added to JP Morgan scope.
- **Surcharge (InterPayments) revival** — paused; ownership/timeline TBD (Eric).
- **JP Morgan's internal Trovata/Kyriba-like platform** — does it exist/integrate with Workday? Needs a JP Morgan rep conversation (via Erik Tom Thompson).
- **Whether the over-$10k manual-card and under-$10k self-pay thresholds carry into future state**, and whether the "pay link on invoices < $10k USD on any billing entity" rule persists in Workday/RCA invoicing.
- **CAD (and other non-USD) lockbox handling** — will future state open currency-specific lockboxes or keep FX write-off approach?
- **Bank-fee / FX write-off pass-through to customers** — repeatedly raised, never enforced; future-state policy undecided.
- **Brand-system retirement sequencing** — when Zuora / NetSuite / OrdersX / CyberSource / separate Tripwire GP retire relative to the Workday cutover.
- **No meeting recording transcript beyond the .docx** — the **.mp4 recording exists but has no separate text transcript** (see Sources); any visual/screen-share content in the recording is **not captured** here.

---

## 9. Glossary / system index (as named in the meeting)

| Term | Meaning |
|---|---|
| **GP / Great Plains** | Microsoft Dynamics GP — core AR/accounting ledger today (multiple instances: core + a separate Tripwire instance) |
| **D365** | Microsoft Dynamics 365 — current core CRM (being replaced by Salesforce RCA) |
| **Stripe** ("scribe") | Card processor for the D365/Fortra-portal flow |
| **InterPayments** ("inter/intra payments") | Surcharge service over Stripe; geo-compliant card-fee calculation (paused) |
| **CyberSource** | Card processor for Globalscape OrdersX |
| **OrdersX** | Globalscape e-commerce/order portal (fixed $5,999 product) |
| **Zuora** ("Zora") | Tripwire subscription billing system |
| **NetSuite** | Alert Logic accounting system |
| **JP Morgan** | Primary bank; sole lockbox; main ACH/wire reporting |
| **Bank of America** | Secondary named bank in integration scope |
| **PacWest** ("PAC W"/"pacquest") | Bank account used for Alert Logic NetSuite postings |
| **HSBC** | Bank account still open for Alert Logic |
| **Kyriba** | Future Treasury platform (multi-bank aggregation, dashboards, Workday feeds) |
| **Trovata** ("Truvada") | Current bank-data aggregator/clearinghouse, being replaced by Kyriba |
| **Paragon** | Spreadsheet/tool where Cash App tracks incoming ACH detail |
| **"Paid in Portal"** | D365 invoice collection status set when a customer pays via the portal link |
| **Merchant Bankcard / American Express** | Two card-settlement streams in Globalscape/OrdersX |
| **Terra Nova / Fortra International Limited** | Legal entities whose receipts land in the domestic USD account (intercompany) |

---

## Sources

- **Used:** [Cross Team Meetings/Current Payment Deposit Process.docx](../Fortra%20Discovery%20Documentation/Cross%20Team%20Meetings/Current%20Payment%20Deposit%20Process.docx) — Teams transcript, 2025-05-20 (extracted text: `Data/discovery-extract/text/Cross Team Meetings/Current Payment Deposit Process.docx.txt`). Read in full.
- **Exists but NOT extractable (no transcript):** `Cross Team Meetings/Current Payment Deposit Process-20250520_130128-Meeting Recording.mp4` — ~146 MB video recording of the same meeting; **no separate transcript/audio extraction available**. Any screen-share/visual content in the video is not captured in this document. The .docx transcript is the authoritative text source.
