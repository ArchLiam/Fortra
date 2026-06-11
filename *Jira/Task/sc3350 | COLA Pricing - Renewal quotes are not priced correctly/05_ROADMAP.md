# SC-3350 — COLA Completion Roadmap (UAT)

Sequenced, dependency-aware plan to finish COLA end-to-end in FortraUAT. **You** = config/Setup/data/decisions.
**Me** = Apex/procedure/tests/packaging. We do one step at a time; each step has an exit gate before the next.

**Strategy:** *diagnose → decide → build → validate → package.* We run one decisive live trace FIRST (Step 2) so
the architecture decisions (Step 3) are evidence-based, not guesses.

---

## Status board

| Step | Title | Owner | Status |
|---|---|---|---|
| **1** | Confirm the live renewal flow | me | ✅ **done** — `Fortra_Create_Renewal_Quote` v6 (overrides `quotingAI__createRenewalQuote`; no `skipPricing`, no reprice) |
| **2** | Decisive trace: force a reprice on a broken renewal & observe | you + me | ✅ **done** — see [evidence/STEP2_REPRICE_TRACE.md](evidence/STEP2_REPRICE_TRACE.md). Reprice ✅ fixes descriptions, ✅ applies COLA once (no double-apply), ✅ no gack. **NEW defect isolated: net-price = $0** (NetUnitPrice/Total/Grand all 0; list/Subtotal correct). Bill To Place is a hard prerequisite. |
| **2b** | Diagnose the $0 net-price | me | ✅ **done** — [evidence/NET_PRICE_ZERO_RCA.md](evidence/NET_PRICE_ZERO_RCA.md). Renewal branch is **missing a `InputUnitPrice→NetUnitPrice` seed**; the only seed (`QuantityPrice49`) is gated `ItemPricingSource NotEquals 'LastTransaction'`. NOT a COLA bug — a procedure gap COLA exposed. |
| **2c** | Fix the $0 net-price — **✅ DEPLOYED to V11 Draft 2026-06-10 21:10Z.** Seed `InputUnitPrice→NetUnitPrice` AssignmentElement `SeedNetUnitPriceRenewal` added to V11's renewal container (`ListContainer63`, seq 2, formula bumped to seq 3), gated `ItemPricingSource=LastTransaction AND DerivedPricingAttribute=false AND (NetUnitPrice IsNull OR NetUnitPrice=0)`. Dry-run + deploy succeeded; V10 (Nir's) content intact; V11 NOT activated. | me (deployed) | ⏳ **validate via Simulate** |
| **2d** | Simulate V11 on quote 00780886 → expect Net 4697.946 / 929.25. Then coordinate w/ Nir/Marc + fresh ack → Activate V11. | you (simulate) + me | ⛔ |
| **3** | Lock decisions D1 (store/grain) · D2 (reprice ✅ validated) · D3 (trigger — no double-apply seen) | you + me | ⛔ |
| **4** | Rules: store + Solution-Name grain + correct rates | you (data) + me (code) | ⛔ |
| **5** | Wire the renewal flow to force pricing | you | ⛔ |
| **6** | Code fixes: trigger consolidation, B1, B2, remove out-year, golden tests | me | ⛔ |
| **7** | Go-live data cleanup (TEMP_BoKS, null categories, picklist) | you | ⛔ |
| **8** | End-to-end UAT validation across scenarios | you + me | ⛔ |
| **9** | Packaging: back-fill `force-app`, prod-ready | me | ⛔ |

---

## Step details

### Step 1 — Confirm live renewal flow ✅
Done. The production renewal path is `Fortra_Create_Renewal_Quote` v6; it does not request or run pricing.

### Step 2 — Decisive trace ⏳  *(the one test that de-risks everything)*
Take a renewal quote that's currently **broken** (priced at list, $0 rollups, null description) and **force a
full reprice** on it, then observe. This single test answers three things at once:
- **D2 proof:** does a reprice make COLA apply, populate Net/Subtotal/GrandTotal, and generate the description?
- **D3 proof:** does the still-active trigger **double-apply** COLA when the prehook also runs?
- **Risk check:** does Reprice-All itself **gack** (it has before — SC-3308 / contextDef errors)? If so, that's
  a blocker we must design around.
- **Exit gate:** a captured before/after of one renewal line + a clear yes/no on each of the above.
- **Needs:** one UAT mutation (a reprice) — requires your go-ahead.

### Step 3 — Lock decisions (informed by Step 2)
- **D1 — rule store & match grain.** Custom object `COLA_Uplift_Rules__c` keyed on Solution Name (spec-faithful;
  fixes rates + audit + security) **vs** keep CMDT re-keyed on Solution Name (lighter; needs a spec waiver).
- **D2 — reprice mechanism.** `skipPricing=false` on `initiateRenewal` **vs** post-creation Place Sales
  Transaction (`pricingPref=Force`).
- **D3 — engine.** Retire the `COLAUpliftHandler` trigger (prehook-only) vs keep it as belt-and-suspenders.
- **Exit gate:** D1/D2/D3 written down.

### Step 4 — Rules: store + grain + rates
Stand up the chosen store keyed on **Solution Name**; load the [User Story rates](evidence/USER_STORY.md)
(incl. Messenger* 12.00, SecureCare/SSO 4.70); enable field history if custom object. I re-point the lookup
code from `Solution_Category__c` to `Solution__c`.
- **Exit gate:** every product in the mapping table resolves to its correct rate in a dry-run.

### Step 5 — Wire renewal flow to force pricing
Update `Fortra_Create_Renewal_Quote` v6 per D2; verify the prehook registration order (description prehook LAST).
- **Exit gate:** a freshly generated renewal runs a pricing pass automatically.

### Step 6 — Code fixes
Trigger consolidation (D3) after a double-apply trace; B1 (per-ACR re-key); B2 (surface failures); remove
out-year/MyCAP + broken `Final_Year` + legacy dup fields; add a golden-value test; lift prehook coverage buffer.
- **Exit gate:** all COLA tests green with a spec-anchored assertion; no double-apply.

### Step 7 — Go-live data cleanup
B8 TEMP_BoKS (re-point permanent rule or recategorize 17 products); 88 null-category products; rate-0 rules;
add `MyCAP Default` to the `COLA_Source__c` value set (or drop it as out-of-scope).
- **Exit gate:** no product silently falls to 0% unintentionally; picklist deploy-safe.

### Step 8 — End-to-end UAT validation
Generate renewals across scenarios: CMDT-rate line, per-solution exception (MessengerConsole), contract-override
line, multi-asset contract (B1), and a manual override. Confirm the [Definition of Done](04_COMPLETION_PLAN.md#7-definition-of-done).
- **Exit gate:** all scenarios pass; sign-off-ready.

### Step 9 — Packaging
Back-fill `force-app` authoritatively (classes, store + records, fields, PS, templates); confirm a validate-only
deploy is clean.
- **Exit gate:** prod-promotable bundle.

---

*One step at a time. We don't start Step N+1 until Step N's exit gate is met.*
