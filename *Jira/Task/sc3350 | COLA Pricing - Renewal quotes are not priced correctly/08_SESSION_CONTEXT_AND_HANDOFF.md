# SC-3350 — Full Session Context & Handoff (2026-06-10)

Owner: Liam Jeong · Org: FortraUAT · Compiled at end of session. This is the complete narrative of what was
done, found, fixed, and what remains **unsolved**. Read with [README.md](README.md) (the research dossier).

---

## 0. The ticket
**SC-3350 "COLA Pricing — Renewal quotes are not priced correctly."** Two stated defects:
- **#1** Renewal quote lines priced at plain list instead of prior-price + COLA uplift %.
- **#2** Line Item Description not populated on renewal lines.

Canonical test quote: **00780886 / `0Q0WC000003671t0AA`** ("Nir - COLA Test Account"), 2 lines:
Abstract (Asset 4356 × 7.85% → **4697.946**) and beSECURE (875 × 6.2% → **929.25**).

---

## 1. Deep research (14-agent workflow) → the dossier
Re-researched against current live FortraUAT after discovering **Marc DeBrey reworked all 5 COLA classes that
morning**. Key result: **Marc's rework was coverage/testability only — it fixed the NO-GO coverage blocker
(Handler 42→92%, Prehook 3→75%, ACQH 0→86%) but did NOT fix either defect.** Both still reproduced.
Output: this dossier ([README.md](README.md), [01-06](01_OPEN_QUESTIONS_AND_RECOMMENDATION.md), 14 verified
notes in [evidence/research-notes/](evidence/research-notes/)). Ticket map: SC-3350 canonical; SC-3354 dead
alias; SC-3346 parent; SC-3349 = separate descriptions ticket.

## 2. User-Story conformance ([03](03_USERSTORY_CONFORMANCE.md))
The canonical User Story is **single-year only** (resolves the scope fork → Option A; live out-year/MyCAP is
out-of-scope gold-plating). Verdict: **not fully conformant** — live uses a **CMDT** not the spec'd custom
object (no field history); matches on **Solution Category** not **Solution Name**; **2 rates wrong** on ~34
products (Messenger*/Peek 7.85 vs 12.00, SecureCare/SSO 7.85 vs 4.70). Pricing math + override are correct.

## 3. Completion plan + roadmap ([04](04_COMPLETION_PLAN.md), [05](05_ROADMAP.md))
Established what COLA does, the full component list, and a diagnose→decide→build→validate→package roadmap.
Confirmed the live renewal path is `Fortra_Create_Renewal_Quote` v6 (overrides `quotingAI__createRenewalQuote`).

---

## 4. Execution — what actually happened in the org

### 4a. Bill To Place prerequisite (fixed)
Reprice-All on 00780886 failed: *"Select a Bill To Place related to this Quote's Account."* The quote's
`Bill_To_Place__c`/`Ship_To_Place__c` pointed to a Place on a **different account**, and the quote's account
had **no Places**. **Fix (done):** created `Places__c` **`a0lWC000004n5x7YAA`** (US address) on account
`001WC00000kJGcuYAG` and set it as Bill/Ship To Place on the quote. ⚠️ This is a **renewal data prerequisite**
likely affecting other renewals — the renewal flow doesn't carry Places.

### 4b. The decisive reprice trace ([evidence/STEP2_REPRICE_TRACE.md](evidence/STEP2_REPRICE_TRACE.md))
Forcing a Reprice-All on the renewal:
- ✅ **Defect #2 (descriptions) is FIXED by a reprice** — both lines got proper generated descriptions
  (`Abstract | CU | Primary | Production`, etc.). This proves the unifying thesis: descriptions generate
  inside a pricing pass; renewals just never run one.
- ✅ **COLA applies correctly to UnitPrice/Subtotal** (4697.946 / 929.25), single application.
- ❌ **Net side is $0** — `NetUnitPrice / NetTotalPrice / TotalPrice / GrandTotal = 0`. This became the focus.

### 4c. Net-price RCA (4-agent workflow) + fix design ([06](06_NETPRICE_FIX_SPEC.md))
Static trace concluded: the renewal pricing branch lacks an `InputUnitPrice → NetUnitPrice` **seed** (the
new-sale branch has one, gated to exclude renewals). Designed a guarded seed for the renewal container.
**This RCA turned out to be incomplete** (see §5).

### 4d. The V11 net-price saga — UNSOLVED after ~6 deploy cycles
To add the net seed, V11 of `Rev_Mgmt_Default_Pricing_Procedure` was edited via metadata and activated
repeatedly (each cycle = deactivate V11 → deploy → reactivate → reprice). **Every variation left `NetUnitPrice = 0`:**

| # | Seed variation | Container | Result | Why it failed |
|---|---|---|---|---|
| 1 | `AssignmentElement` + inline `advancedCondition` | ListContainer63 (renewal) | Net 0 | **Assignments can't write NetUnitPrice** in this engine (0 of 136 do); inline condition on an assignment is ignored. |
| 2 | `AssignmentElement` (no condition) | ListContainer2 (COLA) | Net 0 | same — assignment can't write Net. |
| 3 | `FormulaBasedPricing`, formula = `InputUnitPrice` | ListContainer2 | Net 0 | `InputUnitPrice` is a computed pricing variable, **not readable** as a formula input. |
| 4 | `FormulaBasedPricing`, `IF(Net=0, Pre_COLA_Price__c*(1+COLA_Uplift_Percent__c/100), Net)` | ListContainer2 | Net 0 | **`COLA_Uplift_Percent__c` is NOT in the pricing context** (prehook deliberately doesn't write it — "poisons the batch"; synced to QLI via trigger). Formula → null. |
| 5 | `FormulaBasedPricing`, `IF(Net=0, COLACalculatedPrice__c, Net)` | ListContainer2 | Net 0 | **`COLACalculatedPrice__c` IS in the context (log-confirmed) — yet Net still 0.** A `FormulaBasedPricing` in `ListContainer2` does not write `NetUnitPrice`, cause unknown. |

Metadata mechanics learned the hard way: you **can't deploy to an active expression-set version** (must
deactivate first); **can't create a version via metadata** (collides on `CalculationProcedureId` — only the
Designer "Save As New Version" mints versions); the Designer **renames containers** on clone.

### 4e. The debug-log breakthrough (what finally gave runtime truth)
Two logs were captured. The first was only the async `MyCAPFlagApplier` queueable (useless). The second
(`evidence/07LWC00000OqD532AF-file.txt`, 26k lines) is the **pricing transaction** and proved:
- ✅ COLA prehook runs perfectly: `AssetPrice=4356, COLA%=7.85, AdjustedPrice=4697.95`; writes
  `COLACalculatedPrice__c` to context; `Update result: {isSuccess=true}`; **no "not in updatable" error**.
- ✅ **`SellingModelType = null`** on the lines → the TermDefined `SubscriptionPricing` step does **NOT** fire.
  (My earlier "SubscriptionPricing overrides Net" theory was **wrong** — nothing overrides the seed.)
- ✅ `COLACalculatedPrice__c = 4697.95 / 929.25` **is** in the context.
- ❌ **`NetUnitPrice = 0.0` from the first context snapshot to the last.** Nothing — prehook or procedure —
  ever writes a non-zero Net for these lines. Final line state: `UnitPrice=4697.946, Subtotal=4697.946,
  TotalLineAmount=4697.946, NetUnitPrice=0.0, SellingModelType=null, PrehookRSNetUnitPrice__c=null`.

---

## 5. The unsolved problem (precise statement for escalation / Support)
> For a **non-derived, `ItemPricingSource=LastTransaction`, `SalesTransactionActionType=Renew`,
> `SellingModelType=null`** renewal line whose COLA is correctly applied on the **list/Unit/Subtotal** side
> (`UnitPrice=Subtotal=TotalLineAmount=4697.946`), **`NetUnitPrice` is never written and stays $0** — and an
> added `FormulaBasedPricing` (output `NetUnitPrice`) in the COLA container `ListContainer2`, using a
> context-readable field (`COLACalculatedPrice__c`), **does not write `NetUnitPrice` either.** Why does no
> pricing step set `NetUnitPrice` for this attribute combination, and why is the added Formula step inert?

This is inside the declarative expression-set engine, which neither the waterfall popover nor the Apex debug
log exposes. **It needs Salesforce RLM pricing-engine expertise / Support**, not more procedure edits.

## 6. Current state of the org
- **Defect #2 (descriptions):** effectively addressed — a reprice generates them.
- **Defect #1 / net-price:** **STILL $0 net on renewal lines.** UNSOLVED.
- **`Rev_Mgmt_Default_Pricing_Procedure` V11 is Active** with an **inert** `SeedNetUnitPriceRenewal`
  `FormulaBasedPricing` in `ListContainer2` (does nothing — Net was 0 before and after). V10 retained inactive.
  ⚠️ V11's "Last Modified By" is now Liam (whole-component deploys), but content preserves Nir's 19:28Z work.
- Test quote 00780886 has a real Bill/Ship To Place now (`a0lWC000004n5x7YAA`).

## 7. Recommended next steps
1. **Escalate the §5 question** to Salesforce RLM Support / an RLM pricing-engine expert. That's the blocker.
2. **Revert the inert V11 seed** to leave the procedure clean (deactivate → deploy the pre-seed V11 → reactivate),
   or accept it (harmless). [Pending user decision at session end.]
3. **Separately**, the conformance gaps ([03](03_USERSTORY_CONFORMANCE.md)) and the 2 wrong rates remain.
4. Consider whether the net-price issue is the broader **$0-net family** (SC-3345/SC-3347) — it may not be
   COLA-specific (any non-derived `SellingModelType=null` renewal line).

## 8. Artifacts
- Dossier: this folder (`README.md`, `01`–`06`, `08`, `evidence/`).
- Debug logs: `evidence/07LWC00000OqD532AF-file.txt` (the pricing transaction — primary evidence).
- Working retrieves/edits: `Data/sc3350/` (`live/`, `cur/`, `v11fix3/` = the last deployed seed, `ctx/` =
  context def, `research/` = agent notes).
- Bill To Place created: `Places__c a0lWC000004n5x7YAA`.
