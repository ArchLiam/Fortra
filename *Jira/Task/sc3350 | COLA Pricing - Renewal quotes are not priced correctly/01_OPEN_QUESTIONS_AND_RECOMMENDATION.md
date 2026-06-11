# SC-3350 — Open Questions, Decision Tree & Recommended Path

Companion to [README.md](README.md). This is the actionable layer: what must be decided before code, in what
order, and the recommended sequencing. Questions are grouped **blocking → behavioral → packaging** and tagged
with who owns the answer.

---

## A. The two blocking decisions (settle BEFORE writing any fix)

### A1 — Renewal pricing architecture (owner: Marc DeBrey / German Wren)
COLA is implemented twice (trigger `COLAUpliftHandler` + prehook `COLAUpliftPrehook`); the prehook header
claims it "replaces" the trigger but the trigger is still Active. Renewals run **only** the trigger today
(no reprice), and the trigger bails on the `QuoteActionId` before‑insert race. **Pick one engine and one
trigger‑point:**

| Option | Mechanism | Fixes | Risk |
|---|---|---|---|
| **(Rec) Force a reprice on renewal** | `initiateRenewal skipPricing=false`, or a post‑creation **Place Sales Transaction `pricingPref=Force`** in the renewal flow | **#1 and #2 together** (whole prehook chain fires) | Must confirm the reprice runs in an **updatable** context or description writes silently drop (B2). Governor/volume on bulk renewals. |
| After‑insert reconcile (trigger) | Re‑query inserted QLIs joined to `QuoteAction` by Id, stamp COLA | #1 only | Recursion guard; may race the engine write‑back; doesn't fix #2. |
| Before‑update self‑heal (trigger) | Drop the `Pre_COLA_Price__c != null` gate so unstamped lines derive COLA | #1 only, and only for lines that get *some* update | Smallest change; fragile; doesn't fix #2. |
| Prehook‑only (delete handler) | Marc's stated direction; remove the trigger | #1+#2 **iff** a pricing pass is guaranteed on every renewal QLI | Today a pricing pass is **not** guaranteed — depends on A1's reprice decision. |

**Recommendation:** the **force‑reprice** path is the only one that fixes both defects and aligns with the
platform's supported levers (see [02_PLATFORM_MECHANISM.md](02_PLATFORM_MECHANISM.md)). It also lets the
trigger be retired (resolving the split‑brain B7).

### A2 — Scope fork: single‑year vs multi‑year (owner: business / German Wren)
- **Option A — fix the two documented year‑1 defects** (matches all design docs). Small, well‑scoped.
- **Option B — finish wiring the spreadsheet's multi‑year compounding** for license **and** maintenance
  (matches Leah's spreadsheet; large; touches the procedure + maintenance derivation; requires fixing the
  broken `Final_Year_COLA_Calculated_Price__c` formula first).

**Cannot be decided from code** — the docs and the spreadsheet disagree, and the live system computes the
multi‑year number but bills the single‑year one. Needs the business owner. **Verify the actual spreadsheet
attachment** (not in the repo) before committing to B.

---

## B. Highest‑value diagnostics to run next (cheap, decisive)

These are the things the **read‑only** research could not do and that will most sharply de‑risk the fix:

1. **`SELECT PricingSource, COUNT(Id) FROM Asset ... GROUP BY PricingSource`.** If Fortra renewable assets are
   `PriceBookListPrice`, that one field explains "priced at list" and may be most of defect #1 — a near
   one‑field fix independent of the Apex stack.
2. **Live debug‑log trace of a freshly generated renewal** (post‑Marc‑rework). Confirms: does the pricing
   procedure run at all on a renewal (the `skipPricing`‑omitted default is undocumented)? Does the COLA
   prehook fire? Does the description prehook fire and write in an updatable context? This is the single most
   important next step.
3. **Determine which renewal flow the live "Renew" button invokes** — `Fortra_Create_Renewal_Quote` v6
   (`initiateRenewal`) or `Fortra_Renewal_Quote_Creation` v1 (trigger‑only manual insert). Both are Active.
   Determines whether the pricing engine is even in the picture.
4. **Confirm `Procedure Plan Orchestration for Pricing` is ON** — `RevSignaling` prehooks only fire inside a
   pricing run when this is enabled.

> ⚠️ All four require either DML (generating a renewal) or org config inspection beyond read‑only SOQL. Per
> standing guidance, any UAT DML — even a test renewal — needs a fresh explicit go‑ahead. Flag before running #2.

---

## C. Behavioral questions (for Marc/German, non‑blocking but shape the fix)

1. **COLA base inconsistency:** Path A uses raw `Asset.Price` (gross); Path B nets prior partner +
   discretionary discounts. Which is correct? Should they be reconciled?
2. **Regional × COLA:** live regional is a Services‑only **MIN/floor** that can overwrite the COLA'd price;
   the SDD claims a compounding multiplier. Which is intended?
3. **B1 multi‑asset (`AssetContractQueryHelper`):** re‑key per‑ACR (as the prehook already does), or is
   "one active Contract per Asset" a real invariant? Live data (1 contract → 4 assets) says per‑ACR is the fix.
4. **B2 fail‑silent:** should a COLA/override failure surface to Deal Desk, or is silent‑SUCCESS acceptable?
5. **B5 "one‑time" override:** null persist = apply‑once‑then‑stop, or apply‑forever (current)? If once, what consumes it?
6. **B6 Asset.Price ≤ 0:** handler stamps $0, prehook skips. They must agree.
7. **Per‑product rate exceptions** (Messenger* 12%, SecureCare/SSO 4.70%): do those Product2s carry distinct
   `Solution_Category__c`, or is a product‑level override needed? (In scope even under Option A.)
8. **Out‑year (B3/B4):** if Option B, fix the `Final_Year` base/exponent first; confirm year‑1=CMDT,
   out‑year=MyCAP 3% flat, and whether the field's current `INVALID_FIELD` state is a real compile error.

---

## D. Go‑live data remediation (CMDT)

1. **B8 TEMP_BoKS:** the deletion‑before‑go‑live instruction strands 17 BoKS products at silent 0%. Either
   re‑point the permanent `Powertech IAM BoKS` rule's `Solution_Category__c` to
   `Powertech Identity & Access Manager (BoKS)`, **or** re‑categorize the 17 Product2 records — decide before
   deleting TEMP.
2. **88 null‑category Product2** get no COLA on renewal — intended, or a data gap needing a default rule?
3. **Dead/zero rules:** `Fortra Platform` (0 products), `Powertech IAM BoKS` (0 products), `IPP` (rate 0, 4
   products) — intentional or unset?

---

## E. Packaging / source‑control (owner: Liam + release)

1. Make **force‑app authoritative** — back‑fill all 16 COLA classes + Contract/OrderItem object dirs + both
   CMDT types & 23 records + `COLA_Admin` PS + 2 ExplainabilityMsgTemplates from UAT, **before** any change ships.
2. Approve adding **`MyCAP Default`** to the restricted `COLA_Source__c` value set (else
   `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` on deploy).
3. Fix the `DocuSign_API_Access` PS reverse‑drift (`OrderItem.COLA_Uplift_Percent__c`) — add the OrderItem
   field to source or remove the FLS line.
4. Decide if the inert outyear pair (`COLA_Outyear_Uplift_Percent__c`, `Final_Year_COLA_Calculated_Price__c`)
   enters source now or waits on the A2 multi‑year decision.
5. Confirm the new live‑only `AssetContractQueryHelperTest` is in scope for source control.

---

## F. Coverage / test‑quality (no longer blocking, but harden before hand‑back to Nir)

- Per‑class 75% gate is **cleared** (Handler 91.8% / Prehook 75.1% / QLDescGen 80% / ACQH 86%). But:
  - Prehook is exactly **75.1%** — a one‑line regression fails it. Target ~85% for buffer.
  - Expected values are **formula‑mirrored** — add ≥1 **golden‑value** assertion tied to the spreadsheet,
    independent of the formula, so a wrong‑but‑consistent COLA math change is caught.
  - **PROD org‑wide** coverage is unknown (UAT org‑wide is 44%); the prod gate evaluates the destination
    org's org‑wide ≥75%. Measure before promoting.
  - The stale `AssetContractQueryHelper` aggregate read (seen flapping to 18.6% mid‑run) could false‑fail a
    deploy gate — ensure the deploy runs `RunLocalTests` rather than trusting cached aggregates.

---

## G. Ticket hygiene

1. Confirm in Jira whether a **distinct** COLA "Peer Review ticket" exists (Nir's phrasing) separate from
   SC‑3350 — the repo says no (only SC‑3352, which is SC‑3349's). **Do not invent a number.**
2. Confirm the Jira hierarchy: is **SC‑3346** the parent Story of SC‑3350, and is **SC‑3354** a renumber vs a
   sibling? (Can't be resolved read‑only — no Jira CLI/MCP.)
3. Decide whether SC‑3350 **#2** folds into SC‑3349's shipped `QLDescriptionGeneratorPrehook` fix or stays here.
4. Retrieve Leah Guenther's "Perpetual Sales Calculations" image from SC‑3346 — it's the source of truth for
   the A2 multi‑year decision and is not in the repo.
