# SC-3350 — COLA User Story Conformance Audit

**Question put to me:** *"I found the main user story of COLA — confirm that it's correctly implemented."*
**Verdict: I cannot confirm it as a literal implementation.** The **pricing math and override behaviour are
correct** (the core of the spec), but there are **three structural deviations** and the **two ticket defects
remain**, so several acceptance criteria are not met as written. Every line below is verified against live
FortraUAT (2026‑06‑10, read‑only). The user story is preserved at [evidence/USER_STORY.md](evidence/USER_STORY.md).

> **Silver lining:** the user story is explicitly **single‑year** (Req #5 = `Base × (1 + COLA%/100)`, no
> out‑year / MyCAP / compounding). That **resolves the scope fork** ([README.md](README.md) §7) decisively
> toward **Option A** — the live out‑year/MyCAP machinery is **out of scope** for this story.

---

## Conformance matrix

| Req | Acceptance criterion | Live implementation | Verdict |
|---|---|---|---|
| **#1** Custom object | Custom object **`COLA_Uplift_Rules__c`** with **Unit, Solution Group, Solution Category, Solution Name, Default %, Active**; **field history tracking** on Default % | **Custom Metadata Type `COLA_Uplift_Rules__mdt`** — *not* a custom object. Fields are only `Solution_Category__c` (External Id), `Default_Uplift_Percent__c`, `Is_Active__c`, `Effective_Start/End_Date__c`, `Description__c`. **No Unit / Solution Group / Solution Name fields.** CMDTs **cannot** have field‑history tracking. | ❌ **FAIL (data model)** |
| **#2** Populate rules | Load all solutions per the mapping table (rates at **Solution** grain) | 22 category rows loaded. **19 / 21 category‑level rates match.** The **2 per‑solution exceptions are not representable** and are wrong in live (see Rate Conformance below). | ⚠️ **PARTIAL** |
| **#3** Quote‑line automation | On renewal, populate `COLA_Uplift_Percent__c` + `Default_COLA_Uplift_Percent__c` by matching the **product's Solution Name**; missing → 0% | Populates both fields and defaults missing → effectively 0%. **But matches on `Product2.Solution_Category__c`, NOT Solution Name** (handler `COLAUpliftHandler.cls:36,89`; prehook `COLAUpliftPrehook.cls:641‑659`). And **defect #1** (headless‑renewal race) means some renewal lines are **never populated** → stay at list. | ❌ **PARTIAL / FAIL** (wrong grain + unreliable) |
| **#4** User override | Override persists; automation won't overwrite; Default read‑only | `Is_COLA_Overridden__c` + shared `isManualLineOverride()` predicate; override retained across recalcs. Live proof: 8 lines `Is_COLA_Overridden__c=true` with value ≠ default (e.g. 10 vs 5, 8 vs 7.85, 3 vs null). Default populated by system. | ✅ **PASS** |
| **#5** Pricing procedure | `Final = Base × (1 + COLA%/100)`, **renewal‑only** | V10 Path A/B apply exactly this; **penny‑verified** on audit renewal `0Q0WC000003671t0AA` (4356×1.0785=4697.946; 875×1.062=929.25); gated on `ActionType='Renew'`. **But defect #1 leaves race lines at list and rollups at $0.** | ⚠️ **PARTIAL** (formula correct; not reliably applied) |
| **#6** Security | Authorized RevOps can edit rules; standard users cannot | With a CMDT, editing requires **Customize Application** (a deploy/setup‑level system permission) — so standard users inherently cannot edit, satisfying the *intent*. But the spec's record‑level CRUD model (custom object + a `COLA_Admin` permission set) doesn't apply: `COLA_Admin` grants **no object CRUD** on the rules (CMDTs aren't governed by `ObjectPermissions`). | ✅ **PASS in spirit, different mechanism** |
| **Scope** | Single‑year only | Live adds **inert out‑year / MyCAP** machinery (`COLA_Outyear_Uplift_Percent__c`, `Final_Year_COLA_Calculated_Price__c`) — computed but **referenced 0× in pricing**, and the formula is broken. | ➕ **OUT‑OF‑SPEC EXTRA (gold‑plating)** |

---

## The headline gap — Rate Conformance (Req #2/#3)

The spec keys rates at **Solution Name** grain; the live CMDT keys at **Solution Category** grain. Each
category holds **many** solutions (live: "Systems Management" = **76** distinct solutions; "Cybersecurity" =
**23**), so the spec's per‑solution exceptions are **structurally unrepresentable** and are wrong in live:

| Spec row (Solution grain) | Spec rate | Live category rate applied | Affected live products | Result |
|---|---|---|---|---|
| Systems Management → **MessengerConsole** | **12.00%** | 7.85% (`Systems Management`) | MessengerConsole (10) + MessengerPlus (10) + PeekPlus (10) | **Under‑applied** by 4.15 pts on ~30 products |
| Cybersecurity → **SecureCare** | **4.70%** | 7.85% (`Cybersecurity`) | SecureCare (2) + Single Sign On Mgd Svcs (2) | **Over‑applied** by 3.15 pts on ~4 products |

The other 19 category rates match the spec to the cent (Vulnerability Mgmt 6.2, Brand Protection 5, Data
Protection 4.7, RPA 9.85, GoAnywhere/Globalscape/BI/Doc Mgmt 7.85, etc. — see
[evidence/LIVE_DATA_SNAPSHOT.md](evidence/LIVE_DATA_SNAPSHOT.md) §A). The clean reading: **the live model
implemented the category‑level defaults but dropped the per‑solution exceptions** the spec explicitly calls
out (consistent with the Confluence "Increase Table," where 7.85 is the Systems Management / Cybersecurity
*default* and 12.00 / 4.70 are *exceptions*). A category‑keyed CMDT cannot hold "MessengerConsole = 12 but the
rest of Systems Management = 7.85."

---

## What IS correctly implemented (give credit where due)

- **Req #5 formula is exact and renewal‑gated** — penny‑accurate on the happy path; this is the heart of the spec.
- **Req #4 override** — works end‑to‑end, with audit fields (`COLA_Override_Reason__c`, `COLA_Modified_By/Date__c`).
- **19 of 21 category rates** match the mapping table.
- **Missing‑match → 0%** behaviour holds (no rule ⇒ no uplift).
- **Req #6 intent** (standard users can't change rules) holds, albeit via CMDT/Customize‑Application rather than the spec'd custom‑object security.

---

## What blocks "correctly implemented" — and the fix implication

| Gap | Severity | Fix path |
|---|---|---|
| **Data model is a CMDT, not the spec'd custom object** → no Unit/Group/Solution‑Name fields, **no field‑history (auditability fails Req #1)** | Design | Either (a) accept the CMDT and get the business to amend Req #1/#6, or (b) migrate to `COLA_Uplift_Rules__c` custom object as written (enables field history, record‑level security, **and** Solution‑Name keying). Decide with Marc/German. |
| **Match grain = Category, not Solution Name (Req #3)** → can't honour per‑solution rates | High (wrong $) | Re‑key the rule lookup on `Product2.Solution__c` (the field exists). Requires the data model to carry Solution Name → ties to the row above. |
| **2 rate exceptions wrong** (Messenger*/Peek 7.85 vs 12.00; SecureCare/SSO 7.85 vs 4.70) | High (wrong $ on ~34 products) | Falls out of fixing the grain; or add per‑solution override rows. |
| **Defect #1** (renewal race → priced at list) breaks Req #3/#5 reliability | High | The README §10 / 01_OPEN_QUESTIONS architecture fix (force a reprice / fix the trigger guard). |
| **Out‑year/MyCAP gold‑plating** | Cleanup | Out of scope for this single‑year story — remove or shelve; don't ship the broken `Final_Year` formula. |

---

## Bottom line

The COLA feature is **substantially built and the pricing/override core is correct**, but it is **not a
faithful implementation of this user story**: the data model is a Custom Metadata Type instead of the
specified auditable custom object, rule matching is at Solution **Category** grain instead of Solution
**Name**, two of the twenty‑one rate exceptions are consequently wrong on ~34 live products, and defect #1
still leaves some renewal lines at list price. Conversely, the user story **confirms the fix is single‑year**
— so the out‑year/MyCAP machinery is out of scope. I'd report this to peer review as **conditional / not yet
conformant**, with the data‑model‑vs‑grain decision (Marc/German) as the gating item.
