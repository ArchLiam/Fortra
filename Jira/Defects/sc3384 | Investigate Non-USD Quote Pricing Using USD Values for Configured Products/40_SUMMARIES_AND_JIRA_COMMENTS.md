# SC-3384 — Peer-review summaries + Jira comments

Source: `20_PEER_REVIEW.md` (verdict) + `30_COMPREHENSIVE_REPORT.md` (corrected build spec) + `evidence/LIVE_REVERIFY_2026-06-11.md` (live confirmation of all 6 blockers).

---

## A. Three summaries (pick by audience)

### A1 — One-liner (BLUF)
The RCA thesis is **correct** — non-USD configured prices come from **currency-blind lookups over USD-only data** — but it wasn't build-ready: the review found **6 gating blockers**, all now **re-verified live** and folded into a corrected build spec. **One live gate remains** (a fresh FINEST reprice of the repro quote) before code/data land.

### A2 — Leadership (3–4 sentences)
On non-USD quotes, list prices are right but every *configured* price (attribute / tier / server-type discount) is pulled from a **USD-only** record and stamped onto the foreign line. It is **not "just a data fix"** — the supporting data is 100% USD **and** the lookups omit currency, so both must ship together, **data first**, to avoid resetting live non-USD lines to list/$0. The peer review rated the investigation strong but **not yet buildable** (6 blockers); those are now resolved against the live org, leaving a single verification step. **EUR-only MVP is ~2 weeks** across three owners (Marc=data, Nir=config, Liam=code); the org-wide backfill, rate reload, and JPY documents are larger, separate efforts.

### A3 — Engineering (scannable)
- **Verdict:** investigation/thesis sound; **was NEEDS-REWORK** due to 6 blocker-class build errors — all now corrected and live-verified.
- **B1:** the headline AAMP line has `Has_Attribute_Adjustment__c=false` → its 3150/1575 may be **stored/migration residue**, not live engine output → **fresh FINEST reprice required** before touching the override layer.
- **B2:** 3150 and 1575 come from **two different ABA steps/rows** (different hashes) — not one step.
- **B3:** build from **active V13** (not V9/V12); new version + republish + context re-sync.
- **B4:** strike the **phantom** decision table `0lDWC0000000Gft2AE` (referenced 0× in V13); the real one is `0lDa50000007BEuEAM` (×2).
- **B5:** the line currency tag is **`STICurrencyIsoCode`**, not `CurrencyIsoCode`; enforce currency in the **composite key**, not the SOQL (or EUR lines keep stale values).
- **B6:** **load EUR data, verify, THEN deploy config** — never concurrently.
- **Next:** one live FINEST reprice closes B1/B2 + the BESEPB-824 and CLSAAS-Net=0 traces; then WS-A→E (≈2wk EUR MVP).

---

## B. Jira comment — STATUS (high-visibility, paste into SC-3384)

```markdown
## 🟠 SC-3384 Peer Review — VERDICT: NEEDS-REWORK → re-grounded (1 live gate left)

**TL;DR:** The root-cause thesis is **correct and repo-verified** — non-USD *configured* prices (attribute / tier / server-type discount) are read from **USD-only data by currency-blind lookups** and stamped onto the foreign line. List prices are fine. It is **NOT "only a data issue"** — data + config must ship **together, data-first**. The review found **6 build-blockers**; **all are now re-verified live (2026-06-11)** and folded into a corrected build spec. **One gate remains before build.**

### ✅ Blockers — all verified against the live org
| # | Blocker | Live result |
|---|---|---|
| **B1** | AA EUR price not proven live engine output | QLI `0QLWC000003cBGr4AM` EUR, **`Has_Attribute_Adjustment__c = false`**, 3150/1575 (list 2898) → re-price fresh before trusting |
| **B2** | One step can't emit 3150 **and** 1575 | 3 USD ABA rows; two **active** rows have **different hashes** → two different steps |
| **B3** | Build from **V13** (active), not V9/V12 | confirmed; new version + republish + context re-sync |
| **B4** | `0lDWC0000000Gft2AE` is a **phantom** edit | referenced **0×** in V13; real table = `0lDa50000007BEuEAM` (**2×**) |
| **B5** | Line currency tag = **`STICurrencyIsoCode`** | header is `CurrencyIsoCode`; enforce currency in the **key**, not the SOQL |
| **B6** | **Data first, then config** | ABA = **13,072 rows / 0 non-USD**; config-first resets live non-USD lines to list/$0 |

### ⛔ One gate before any code/data lands
A **fresh FINEST reprice of repro quote `0Q0WC0000036xy90AA`** (writes to the quote — needs sign-off) to: re-ground B1, pin the 3150/1575 emitters, pin BESEPB's 824 source, and localize CLSAAS Net=0. **Everything else is verified read-only.**

### 📋 Effort
EUR-only MVP **~2 weeks** — **Marc** (data seed), **Nir** (decision-table currency key + procedure), **Liam** (`AttributeVolumePricingPrehook`). Out of scope: org-wide backfill of already-mispriced non-USD records, the rate reload (7 currencies @ 1.0), and JPY documents.

📎 Full detail: `30_COMPREHENSIVE_REPORT.md` · live evidence: `evidence/LIVE_REVERIFY_2026-06-11.md`
```

---

## C. Jira comment — BUILD PLAN (high-visibility, for engineering)

```markdown
## 🛠️ SC-3384 — Corrected build plan (post peer review + live re-verify)

**Sequencing (non-negotiable):** EUR data **loaded & verified → THEN** config/code. Every procedure change = **new version off live V13 → republish → re-sync `SalesTransactionContextExt_v2`**. Version hard-delete is blocked; don't remove the Quote/Order `PricingActionParameters` bindings.

| WS | Change | Owner | Notes |
|---|---|---|---|
| **A** | Seed EUR `AttributeBasedAdjustment` + `Attribute_Tier_Pricing_Storage__c` rows | **Marc** | values via `CEILING(EUR_list × mult / 5) × 5` — **not** USD×0.92 (repro is at the corrupted 0.92, not 0.9346). Split A1 (4 SKUs, this ticket) / A2 (org-wide, separate). ABA = no Apex DML → REST/composite-key load |
| **B** | Add `CurrencyIsoCode` key to **`0lDa50000007BEuEAM` only** + both ABA steps | **Nir** | **strike phantom `0lDWC0000000Gft2AE`**; add `0lDa50000007BEsEAM` if the trace shows BESEPB prices there. AAMP-as-% (Option A) = **business decision** (sets EUR net 1449 vs 1575). Coordinate w/ **SC-3360** (same matrix) |
| **C** | `AttributeVolumePricingPrehook` currency-aware | **Liam** | capture **`STICurrencyIsoCode`**; thread currency into the **composite key** (not the SOQL); fail-open on blank; ~12 test methods reworked |
| **D** | CLSAAS **Net=0** total-price net channel | **Nir** | FINEST trace in V13; validate after EUR data lands (a WS-C miss flips the line to Unit-Price mode) |
| **E** | PIAMBK auto-add wrong-PBE | **Liam → Marc/Nir** | **PARTIAL** — resolver unidentified (likely a managed RLM ProductConfigurationRule, may not be editable); EUR PBE `01uWC000005wzX8YAI` already exists; couples to SC-3346 (NO-GO) |

**Per-family status:** CLSAAS = build-grade (the one ready leg) · BESEPB = mechanism confirmed, 824 emitter unpinned · AAMP = **gated on B1/B2 live trace** · VMA = reclassified **DATA+CONFIG** (routes through the same no-currency ABA table) · PIAMBK = **PARTIAL**.

**Acceptance:** on the EUR repro quote — BESEPB/VMA nets EUR-correct (not 824/500 USD); CLSAAS pulls the EUR tier **and** Net ≠ 0; AAMP per chosen Option; PIAMBK auto-adds cleanly; **all USD lines byte-identical (3150/1575/824/500)**; regression across AUD/CAD/GBP (JPY/ILS after rate reload).

**Out of scope (call out explicitly):** existing non-USD Orders/Assets/Invoices already carry wrong nets (5,162 non-USD orders) — separate backfill, coordinate SC-3350/SC-3346. Non-EUR currencies blocked on the rate reload.
```
