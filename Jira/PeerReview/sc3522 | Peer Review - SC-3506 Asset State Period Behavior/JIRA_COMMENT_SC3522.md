# SC-3522 — Peer Review Comment (draft for Jira)

---

## ✅ Peer Review of SC-3506 — Asset State Period Behavior (Amendments / Renewals / Cancellations)

**Bottom line:** The native **Asset State Period engine is behaving correctly** across all three lifecycle actions. Every material defect found is **upstream pricing**, not the ASP engine. SC-3506's core conclusion holds; a few write-up corrections + a sample note are recommended before close.

### 🎯 Scenario results

| Scenario | ASP structure | Price / MRR |
|---|---|---|
| **Amendment** (Upsell) | ✅ Prior period end-dated at effective date; new contiguous period with new qty | 🚩 Added units priced **$0** |
| **Renewal** | ✅ New forward-dated period (starts day after prior end, exact 1-yr term, original preserved) | 🚩 Renewal period **MRR = 0** |
| **Cancellation** | ✅ **No new period**; asset qty/MRR → 0; lifecycle closed | ✅ Correct negative credit (−206) |

### 🔬 How it was verified
1. **Read-only census** of **all 15 live lifecycle assets** (10 Upsells, 5 Renewals, 1 Cancellation) — structure invariants hold everywhere (correct effective-date splits, forward-dating, contiguity, no overlaps/gaps, no new period on cancel).
2. **3 live self-run end-to-end tests** (UI-driven, CLI-verified): Amendment (Order 00095676), Cancellation (Order 00095677), Renewal (Order 00095678) — each reproduced the expected structure.

### 🚩 Confirmed defects — all UPSTREAM of the ASP engine
- **12-year (2039) renewal period** on one asset — root cause is the renewal source line carrying **`PricingTermCount = 12`** (months read as years). The ASP faithfully copied a bad input. → fix at renewal term derivation (cf. SC-3297). *Data-specific — a clean renewal produced a correct 1-yr term.*
- **$0 MRR on amendment & renewal periods** — the added/renewed units price to **$0** before assetization (`Asset.PricingSource = null` carryover gap + COLA renewal zero-price). → route to **SC-3350 / SC-3346** (renewal) and the SC-3441 carryover family (amendment). ASP structure is correct; only the **price** is wrong.

### 🔧 Corrections for the investigation write-up (these are NOT bugs)
- ~~"Overlapping state periods"~~ — **false**; periods tile contiguously (artifact of sorting by CreatedDate instead of StartDate). **Retract.**
- **Null ASP End Date on OneTime products = correct** native behavior (~42% of all ASP rows). Don't force a bounded end date; source OneTime license expiry from the **Contract**.
- **Same-day amendment → single period = expected** (when effective date == asset start date). Not a contradiction.

### 📄 License-key (LKG) note
LKG reads **`Asset.Quantity`** and **`Asset.LifecycleEndDate`** (not AssetStatePeriod directly), and the hardware key path is currently inert. So the license-key risk is a **wrong price on an otherwise correctly-structured latest period** (right quantity/dates, wrong MRR) — data-integrity + prospective, not a proven mis-issued key today.

### ✔️ Acceptance criteria
- **AC1 (document expected behavior)** — ✅ done (per-scenario spec).
- **AC2 (verify implementation matches)** — ✅ for Upsell / Renewal / Cancellation structure. ⚠️ *Thin sample:* org has **no** live Downsell / Cross-Sell / Upgrade / Downgrade / Swap / T&C amendments to test.
- **AC3 (identify gaps)** — ✅ done (defects above, all upstream).

**Disposition:** Core conclusion (ASP mechanics correct) **validated**. Recommend the write-up (1) label the 2 defects as **upstream pricing**, (2) fold in the 3 corrections, and (3) note the untested amendment subtypes.

*(Full detail, queries, and evidence in the Jira/PeerReview workspace: PEER_REVIEW_REPORT.md, VALIDATION_RUNBOOK.md, SMOKE_TEST_READONLY.md, SMOKE_TEST_WRITE_SELFRUN.md.)*

---

### ℹ️ Secondary observation (separate from the ASP behavior) — Quote carryover of Opportunity / Bill-To / Ship-To
While testing, I noticed Renew / Cancel / Amend quotes **inconsistently** carry the source Contract's related Opportunity and header info (Bill-To, Bill-To Place, Ship-To Place, Bill-To Contact) — and the **Quote → Contract link (`Quote.ContractId`) is frequently NULL**. Not sure if by design or a gap. Likely overlaps **SC-3502** (stamp Legal Entity/Bill-To/Ship-To on renewal quotes) and **SC-3339** (carry Bill-To/Ship-To Quote→Order). Flagging for the team to confirm intended behavior; can raise as its own ticket if useful.
