# SC-3338 — Resolution Roadmap

Sequenced, build-ready plan to close all 5 acceptance criteria. Derived from the verified dossier (README + `10_`–`15_`). Live-checked FortraUAT/FortraProd 2026-06-12.

**Guiding principles (non-negotiable):**
1. **No hard-requires** — no `nillable=false`, no layout `Required`, no `required=true`. Visibility + guidance only (ticket scope rule #2).
2. **Prod-safe first** — help text + modal ship to prod; the Quote blocker stays UAT-only until the Order-side machinery is promoted (it's absent from prod).
3. **Never deploy the stale local `Fortra_Order_Submission_Check.flow`** — it regresses UAT to the SC-3366 SOQL-governor bug. Live v13 is source of truth.
4. **Verify live before each deploy** — force-app is a sparse, partly-stale working set.

---

## Phase 0 — Align & approve (GATE) · ~0.5 day · blocks all build
The ticket explicitly requires "UX review with Wren before build."

| # | Task | Output |
|---|---|---|
| 0.1 | Walk Wren/Jomil through the dossier: the user-entered-vs-auto-populated split, the two-layer model (visibility vs enforcement), and why we are NOT using red asterisks (won't render on the dynamic FlexiPage + regression risk). | Shared understanding |
| 0.2 | Get the 4 decisions in README §10 / 14_§6: (a) AC4 prod timing (recommend UAT-only now); (b) modal scope — full readiness incl. Account/Contact-owned fields (recommend yes); (c) approve help-text copy (14_§1.2); (d) modal launch surface — quick action vs accordion (recommend quick action). | Approved design |
| 0.3 | Confirm the "Required Fields Check" modal label/wording and the blocker message tone with Wren. | Final copy |

**Exit gate:** Wren sign-off on design + copy. → proceed.

---

## Phase 1 — Help text (AC2) · ~0.5 day · PROD-SAFE · no dependencies
Smallest lift; can start immediately after Phase 0.

**Components (edit `inlineHelpText` only):**
- ADD: `Quote.BillToContactId`, `Quote.StartDate`, `Quote.Status` (standard-field overrides)
- REPLACE/APPEND: `Quote.ContactId`, `Quote.Bill_To_Place__c`, `Quote.Ship_To_Place__c`
- DO NOT disturb the other 33 of 36 fields that already have help text.
- Copy is pre-written in **14_SOLUTION_DESIGN.md §1.2** (Wren-approved in 0.2).

**Steps:**
1. Edit `force-app/main/default/objects/Quote/fields/<Field>.field-meta.xml` for the 6 fields (retrieve fresh from UAT first to avoid clobbering live state).
2. `sf project deploy start --target-org FortraUAT --metadata "CustomField:Quote.BillToContactId" "CustomField:Quote.ContactId" "CustomField:Quote.StartDate" "CustomField:Quote.Status" "CustomField:Quote.Bill_To_Place__c" "CustomField:Quote.Ship_To_Place__c"`
3. Smoke-check: open a Quote, hover the ⓘ on each field, confirm text renders on read + edit.

**Exit gate:** help text visible on all 6 driver fields in UAT. (Prod deploy deferred to Phase 5.)

---

## Phase 2 — Flow guidance modal (AC3) · ~1.5–2 days · PROD-SAFE · no dependencies
A Quote-side **screen flow** (declarative, no Apex) that reads the live Quote + Account + Contacts + Places and shows ✔/✘ readiness. **Do NOT reuse `OrderSubmissionValidator`** — it is Order-Id-keyed; there's no Order pre-conversion.

**Components:**
- New screen flow `Fortra_Quote_Required_Fields_Check` (input `recordId`).
- New Quote quick action `Review_Required_Fields` (Type=Flow, label "Required Fields Check"), added to the Quote Lightning page highlights panel next to `Convert_Quote_to_Order`.

**Build (element outline in 14_§2.5):**
1. `Get Records` Quote with cross-object driver fields (Account.Name/Phone/Type/DB_DUNS__c; BillToContact + Quote Contact First/Last + Workday mobile attrs; Bill_To_Place__c; Ship_To_Place__c + its Account; StartDate).
2. One text formula per requirement → `✔`/`✘`, mirroring `OrderSubmissionValidator.isValuePopulated` semantics (`OrderSubmissionValidator.cls:253-265`) so the Quote checklist and Order blocker agree.
3. One read-only screen, 3 grouped sections — **On this Quote** / **On the Account** (link out) / **On the Contacts** (links out) — + footer "Tax, Line Numbers, Workday IDs are filled automatically; no action needed."
4. Read-only, idempotent, no DML. (Defer the optional "Convert now" button to a later iteration.)

**Steps:** build in UAT (Flow Builder or source), add quick action to the FlexiPage, activate, deploy source to `force-app`.

**Exit gate:** action visible on the Quote; modal shows accurate ✔/✘ on a known-incomplete and a known-complete Quote.

---

## Phase 3 — Quote-time blocking validation (AC4) · ~1 day · UAT-ONLY for now
Non-restrictive, un-bypassable block at the conversion boundary. Recommended = **Option A** (14_§3): before-save record-triggered flow.

**Component:** new before-save record-triggered flow `Fortra_Quote_Block_Conversion_When_Incomplete` on Quote.

**Build:**
1. Entry: `recordTriggerType=Update`, **before-save**, fires only when `ISCHANGED(Create_Order_from_Quote__c) && Create_Order_from_Quote__c = true`. This is the exact flag the live after-save `Quote_After_Update_Create_Order_From_Quote` (v2) keys on → intercepts UI, headless checkbox, AND Data Loader/API paths (un-bypassable).
2. Evaluate the same rep-owned requirements as the modal, reading `$Record`'s direct lookups (Quote→Account, Quote→Contacts).
3. Block with a single friendly **Custom Error** (`addRecordError`), guidance-toned, pointing the rep to the Required Fields Check modal (copy in 14_§3.2). Validate **only rep-owned fields** — never the downstream/Workday auto fields.
4. Keep the live Order-side v13 flow as the downstream backstop (no change to it).

**Pattern precedent:** mirrors live `Quote_BillToContactAcct_Equal_QuoteAcct` / `Quote_BillToPlacceAcct_Equal_QuoteAcct` VRs (custom error on a Quote relationship field).

**Exit gate:** in UAT, setting `Create_Order_from_Quote__c=true` on an incomplete Quote is blocked with the friendly message and **no Order is created**; a complete Quote converts normally.

---

## Phase 4 — No-regression verification (AC5) · ~0.5 day
Runs after Phases 1–3 land in UAT.

1. `sf apex run test --target-org FortraUAT --class-names OrderSubmissionValidatorTest QuoteToOrderFieldMapperTest --result-format human` → both must stay green (neither class is modified; this guards the surrounding metadata didn't disturb compile/coverage).
2. Confirm before-save/after-save ordering: incomplete Quote errors before `createOrderFromQuote` fires; complete Quote converts. No duplicate-Order or partial-Order side effects.
3. Confirm no collision with existing Quote before-save automation (none gates the conversion flag today).
4. Full E2E: incomplete Quote → modal shows ✘ → convert blocked → fix fields → modal all ✔ → convert succeeds → Order created → `Order_Complete` action passes v13 submission check.

**Exit gate:** tests green + E2E passes.

---

## Phase 5 — Deploy & document
| Deliverable | UAT | Prod | When |
|---|---|:--:|---|
| Help text (Phase 1) | ✅ deployed | ✅ **deploy after Wren sign-off** | Phase 5 |
| Guidance modal + quick action (Phase 2) | ✅ deployed | ✅ **prod-eligible** (verify Place fields exist in prod first) | Phase 5 |
| Quote blocking flow (Phase 3) | ✅ deployed | ⛔ **HOLD** — promote only with the broader SC-3291/Order-submission prod rollout so Quote-time + Order-time enforcement land together | later |
| Stale local `Fortra_Order_Submission_Check.flow` | ⛔ never deploy | ⛔ never | — |

**Close-out:** update the ticket with the inventory (AC1 already satisfied by this dossier), link the dossier, attach the E2E evidence, note the prod-timing decision for AC4.

---

## Critical path & effort
```
Phase 0 (gate) ──► Phase 1 (help text, 0.5d)  ─┐
                ├─► Phase 2 (modal, 1.5–2d)    ─┼─► Phase 4 (verify 0.5d) ──► Phase 5 (deploy)
                └─► Phase 3 (blocker, 1d, UAT) ─┘
```
- Phases 1–3 are independent after Phase 0 → can be built in parallel.
- **Total ~4–5 build days** + Phase 0 review + Phase 5 deploy. Matches the ticket's "limited lift" intent.
- **AC1 (inventory) is already complete** — this dossier is the deliverable.

## Risks (carry from README §9)
- Deploying the stale local flow → SC-3366 regression. **Mitigation:** never deploy it; re-retrieve live v13 if needed.
- Over-blocking → gate strictly on `ISCHANGED(Create_Order_from_Quote__c)&&=TRUE`, keep fields nillable.
- `Ship_To_Account__c` silent hole (`QuoteToOrderFieldMapper.cls:22-23` null when no Ship_To_Place) → blocker/modal require `Ship_To_Place__c`.
- Account/Contact data owned by other teams → modal surfaces it early with quick links so reps chase it before conversion.
