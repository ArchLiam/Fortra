# SC-3350 — COLA Completion Plan (what it does · components · what to configure)

**Goal:** complete the COLA feature end-to-end in FortraUAT. Division of labour: **you configure** (Setup,
data, flow, registration), **I code** (Apex, procedure logic, tests, packaging). This is the working
reference. Grounded in the verified research in [README.md](README.md) and [evidence/](evidence/).

---

## 1. What COLA does (functional summary)

COLA (Cost-of-Living Adjustment) automatically raises renewal prices by a predefined uplift % tied to each
product's **solution**, while letting users override and keeping an audit trail.

**Flow of one renewal line:**
1. A renewal quote is generated (RLM `initiateRenewal`). Each renewal line traces back to the customer's
   existing **Asset** and its **prior price**.
2. The system looks up the product's solution and finds its **uplift %** (e.g. GoAnywhere 7.85%,
   Data Protection 4.70%).
3. The pricing procedure applies **`Final Price = Prior Price × (1 + COLA% / 100)`** — **single-year**,
   **renewal-only**.
4. A Deal Desk user may **override** the % on a line; the override **sticks** (automation won't overwrite it),
   and the system records who/when/why for **auditability**.
5. The system-derived default % is stored read-only alongside the (possibly overridden) applied %.

**Scope (locked by the canonical [User Story](evidence/USER_STORY.md)):** single-year only. No multi-year /
out-year / MyCAP compounding. Description generation on the line is a *related* concern (SC-3349's class), not
a COLA requirement — but the same fix lights it up for free.

---

## 2. Required component list

Legend: ✅ built & working · ⚠️ built but needs work · ❌ missing · ➖ out-of-scope (remove/shelve) · 🔍 verify

### A. Data model — the rule store
| Component | State | Note |
|---|---|---|
| `COLA_Uplift_Rules__mdt` (CMDT) + 22 records | ⚠️ | Live store. Keyed on `Solution_Category__c`. **2 rates wrong** (Messenger* 12, SecureCare/SSO 4.70 not representable). Spec wanted a **custom object** keyed on Solution Name with field history → **DECISION D1**. |
| `MyCAP_Rules__mdt` + 1 record | ➖ | Out-year — out of scope. Shelve. |
| `Product2.Solution__c / Solution_Group__c / Solution_Category__c` | ✅ | All three grains exist; matching currently uses **Category**. Solution-Name keying is available if we re-point. |

### B. Apex (Fortra-owned, live-only — none in `force-app`)
| Class | Role | State |
|---|---|---|
| `COLAUpliftHandler` (+ `QuoteLineItemTrigger`) | Trigger that stamps COLA on QLI insert/update (the headless path) | ⚠️ Defect #1 race; **candidate for retirement** once reprice is guaranteed |
| `COLAUpliftPrehook` | Pricing-procedure prehook — applies COLA during a reprice | ✅ works on reprice; ⚠️ B2 fail-silent |
| `AssetContractQueryHelper` | Resolves contract-level override % per asset | ⚠️ B1 multi-asset collapse (keyed by ContractId) |
| `QLDescriptionGeneratorPrehook` | Builds the Line Item Description (shared w/ SC-3349) | ✅ works on reprice |
| `COLAUpliftTest`, `AssetContractQueryHelperTest`, `QLDescriptionGeneratorPrehookTest` | Tests | ✅ all four classes ≥75% now |

### C. Pricing procedure (RLM)
| Component | State |
|---|---|
| `Rev_Mgmt_Default_Pricing_Procedure` **V10** — Path A (`COLAUpliftonRenewal` → `InputUnitPrice`) + Path B (`DerivedPricingRenewals` → `NetUnitPrice` for maintenance) | ✅ wired & correct |
| Context `SalesTransactionContextExt_v2` | ✅ |
| Prehook registration (COLA + description prehooks; description registered **LAST**) — **UI-only RLM config** | 🔍 verify order; not in metadata |

### D. Fields
| Object | Fields | State |
|---|---|---|
| QuoteLineItem | `COLA_Uplift_Percent__c`, `Default_COLA_Uplift_Percent__c`, `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `COLACalculatedPrice__c`, `Is_COLA_Overridden__c`, `COLA_Override_Reason__c`, `COLA_Applied/Modified_*` | ✅ in use |
| QuoteLineItem | `COLA_Outyear_Uplift_Percent__c`, `Final_Year_COLA_Calculated_Price__c` | ➖ out-of-scope; `COLA_Uplift2__c`, `COLAUpliftPercent__c` look like legacy dupes 🔍 |
| Contract | `COLA_Override_Percent__c`, `COLA_Override_Persist_Until__c` | ✅ contract-tier override |
| OrderItem | `COLA_Uplift_Percent__c`, `COLACalculatedPrice__c` | ✅ carries to order |
| Asset | `Price` (used as base), `PricingSource` (null everywhere — unused) | ✅ / ➖ |

### E. Security & UX
| Component | State |
|---|---|
| `COLA_Admin` permission set | ✅ exists (CMDT edit also needs *Customize Application*) |
| `upliftRates` LWC + `UpliftRates*`/`UpliftRateMatcher*` Apex (bodies **hidden/managed**) | 🔍 **verify** — likely a rate-admin UI; confirm whether it's the intended RevOps surface (Req #6) and what store it reads |
| `COLAUpliftPass` / `COLAUpliftFail` ExplainabilityMsgTemplate | ✅ |

### F. Renewal generation
| Flow | State |
|---|---|
| `Fortra_Create_Renewal_Quote` v6 (`initiateRenewal`, **no `skipPricing`, no reprice**) | ⚠️ **the gap** |
| `Fortra_Renewal_Quote_Creation` v1 (trigger-only manual insert) | 🔍 confirm which is live |

---

## 3. What's actually broken (and the one root cause)

Everything works **except renewals never run a pricing pass**, so the prehook chain (COLA + description) never
fires on a renewal. The trigger stamps `UnitPrice` but the rollups stay $0 and no description is written.
**Fixing "renewals reprice" fixes defect #1 and defect #2 together.** Secondary issues: the 2 wrong rates
(grain), B1 multi-asset, B2 fail-silent, out-of-scope out-year code, go-live data, and packaging.

---

## 4. Gating decisions (settle these first — they shape the work)

- **D1 — Rule store & match grain.** To get the per-solution rates right (Messenger* 12%, SecureCare 4.70%)
  the lookup must key on **Solution Name**, not Category. Two ways:
  - **(Rec for "perfect"/spec) Migrate to custom object `COLA_Uplift_Rules__c`** keyed/matched on Solution
    Name → fixes the rates **and** restores field-history audit (Req #1) **and** record-level security (Req #6)
    in one move. Bigger change (data load + lookup code + procedure SOQL).
  - **(Lighter) Keep the CMDT but re-key it on Solution Name** (add `Solution_Name__c` external-id) → fixes
    rates/grain only; still no field history; security stays at *Customize Application*. Needs a spec waiver.
- **D2 — Reprice mechanism.** Force pricing on renewal via **`skipPricing=false`** on `initiateRenewal`, or a
  post-creation **Place Sales Transaction (`pricingPref=Force`)** step. (Recommend the latter — explicit and
  testable.)
- **D3 — Engine consolidation.** Once renewals reprice, the `COLAUpliftHandler` **trigger is redundant** and
  risks double-applying COLA. Recommend **prehook-only**: retire/guard the trigger. Needs a live double-apply
  trace to confirm safe.

---

## 5. What YOU need to configure  ✅

In rough order. Items marked **(after D-decision)** depend on §4.

1. **Confirm the live renewal flow.** Determine whether the "Renew" button runs `Fortra_Create_Renewal_Quote`
   v6 or `Fortra_Renewal_Quote_Creation` v1. (Setup → Flows; check the Renew action / `quotingAI` override.)
2. **Make renewals reprice (D2).** In the live renewal flow, either set **`skipPricing = false`** on the
   `initiateRenewal` action, **or** add a **Place Sales Transaction (`pricingPref=Force`)** / Run-Pricing
   action immediately after the quote is created. → this alone fires COLA **and** descriptions.
3. **Verify prehook registration order** (Setup, UI-only RLM config): `COLAUpliftPrehook` registered on the
   procedure plan, `QLDescriptionGeneratorPrehook` registered **LAST**. Capture the order as a runbook step
   (it's not in metadata, so it must be re-verified after any procedure republish).
4. **Rate data (after D1):**
   - If custom object: load `COLA_Uplift_Rules__c` from the [User Story mapping table](evidence/USER_STORY.md)
     at Solution-Name grain, enable **field history** on Default COLA %.
   - If CMDT: correct/extend records so Messenger*/Peek = 12.00 and SecureCare/SSO = 4.70 (requires the
     Solution-Name re-key I'll code).
5. **Go-live data cleanup (CMDT):**
   - **B8 TEMP_BoKS:** before deleting `TEMP BoKS IAM ProductCat`, either re-point the permanent
     `Powertech IAM BoKS` rule's `Solution_Category__c` to `Powertech Identity & Access Manager (BoKS)`, **or**
     re-categorize the 17 BoKS Product2 records — else they fall to silent 0%.
   - Decide intent for **88 null-`Solution_Category__c` products** (silent 0% today) and the rate-0 rules
     (`Fortra Platform`, `IPP`).
6. **Restricted picklist `QuoteLineItem.COLA_Source__c`:** add the **`MyCAP Default`** value to the `force-app`
   value set (or, since out-year is out-of-scope, we drop `MyCAP Default` usage in code — your call). Needed so
   the field can deploy to prod without `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`.
7. **Permissions:** assign `COLA_Admin` to the RevOps users who manage rates; confirm standard users have no
   edit path. If we adopt the custom object, set its OWD + the `COLA_Admin` CRUD/FLS.
8. **Confirm the `upliftRates` LWC's role** — if it's the intended rate-admin screen, decide whether it stays
   (and what store it points at) so RevOps rate edits go through one surface.
9. *(Optional / native)* If you ever want native renewal base-pricing: set `Asset.PricingSource =
   LastTransaction`. Not required for the current custom path (it reads `Asset.Price`).

## 6. What I'll code  🛠️

1. **Defect #1+#2 architecture (D2/D3):** ensure COLA is applied via the prehook within the guaranteed
   reprice; retire/guard the `COLAUpliftHandler` trigger after a double-apply trace.
2. **Solution-Name match grain (D1):** re-point the rule lookup (handler + prehook) from
   `Solution_Category__c` to `Solution__c`; adjust the procedure SOQL/store accordingly.
3. **B1 multi-asset:** re-key `AssetContractQueryHelper` per-ACR (4-in/4-out).
4. **B2 fail-silent:** surface COLA/override failures (Explainability) instead of silent SUCCESS.
5. **Remove out-of-scope:** out-year/MyCAP machinery + broken `Final_Year` formula + legacy dup fields.
6. **Tests:** add a **golden-value** assertion tied to the mapping table (not formula-mirrored); lift the
   prehook off the 75.1% knife-edge.
7. **Packaging:** back-fill `force-app` authoritatively (all COLA classes, CMDT/object + records, fields,
   `COLA_Admin`, templates) so a prod deploy doesn't regress.

---

## 7. Definition of "done"
A renewal generated in UAT: every renewal line shows `UnitPrice = PriorPrice × (1 + COLA%)` with correct
per-solution rate, populated `Default_COLA_Uplift_Percent__c`, a generated Line Item Description, non-zero
Net/Subtotal/GrandTotal rollups; a manual override on a line persists across reprice; rate edits are limited
to authorized users; and the whole bundle exists in `force-app` ready to promote.
