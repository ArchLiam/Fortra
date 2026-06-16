# SC-3346 NEW-MAINTENANCE $0 — RCA + Resolution + Roadmap (2026-06-15, FortraUAT)

> Origin: Joe (Fortra) flagged that the middle line on quote `Q-Wren - Test Pricebook 2-2026-06-15`
> (`0Q0WC0000039Vm10AE`) — **Powertech IAM (BoKS)-NewMaintenance** (`PIA-PIA-RNM-PIAMBK`) — prices to **$0**
> and stays $0 after **Reprice All**; setting Quantity ≥ 1 + reprice also "did not change the price."
> All facts below are **live-verified read-only** against the active **V14** procedure.

## TL;DR
Joe's line is a **born-Quantity-0** defect (Mode A). Its *per-unit* net is already correct
($355 × 20% = **$71**); `$71 × 0 = $0`. **Quantity IS the fix** — but the manual qty edit **does not
commit on an Accepted/IsSyncing quote** (Mode A'), which is why it appeared not to work. The "rate stays
$0 even at qty ≥ 1" behavior is a **separate, rarer defect (~2 lines)** with a different mechanism (Mode B)
and must be a **separate ticket**.

---

## 1. Root Cause — three distinct defects (Joe's line = Mode A + A')

### 🔴 Mode A — the maintenance line is *born* with Quantity = 0, ONLY on the asset-copy path  ← Joe's blocker
**EMPIRICALLY PROVEN 2026-06-15 (live tests).** The qty=0 is born **iff the line is created by an asset-copy
QuoteAction** (`Type IN Amend/No Change/Renew`, off an existing maintenance Asset, e.g. `02iWC000008DFvvYAG`) →
born `StartQuantity=1, EndQuantity=1, Quantity=0` with a `QuoteActionId`. The other two creation paths BOTH
birth qty=1 and price correctly:

| Creation path | QuoteAction? | Born shape | Qty | Net |
|---|---|---|---|---|
| Greenfield **Configurator AutoAdd** (rule `14OWC0000022ULp2AM`) | no | sQ=0, eQ=1 | **1** | **$62.48** ✅ |
| Manual add | no | sQ=0, eQ=1 | **1** | $71 ✅ |
| **Asset-copy (Amend / No-Change / Renew)** | **yes** | sQ=1, eQ=1 | **0** | **$0** ❌ |

- Proven greenfield: new Draft quote `0Q0WC0000039bwH0AQ` — adding `PIA-PIA-NRPS-PIAP` auto-added PIAMBK at
  **qty 1 / net $62.48** with **no QuoteAction**. So the AutoAdd rule's `actionParameters=[]` is **NOT the bug**.
- Joe's L2 and the test-bed qty=0 line both trace to the **same source Asset** `02iWC000008DFvvYAG` via QuoteActions
  (L2 = Amend/FieldAmendment; test-bed = No Change). The platform asset-copy clones the source asset (qty 1) into a
  new line with **Quantity 0**.
- The only quantity-normalizer in the build, **`RenewalAssetQuantityHandler.cls`**, is **triple-gated to renewals**
  (`Quote_Type=Renewal`/`OriginalActionType=Renew` + `Fortra_Product_Type__c='Renewal Maintenance'` + QuoteAction.Type
  whitelist that excludes `Amend`) → **never fires** on an Amend/No-Change asset-copy. No New-business equivalent exists.
- Net/unit is correct: PBEDP `182WC000000FN26YAG` seeds `Source_List_Price__c=355`; MTD `Standard` →
  `Maintenance_Rate__mdt`=0.20 → **$71/unit**. `$71 × 0 = $0`.
- `ListPrice=0` is **NORMAL** for ALL these derived lines (price lands in the **Net** fields) — a red herring.

> ⛔ **DO NOT edit the AutoAdd rule** (`14OWC0000022ULp2AM`) or the other 198 maintenance rules — greenfield auto-add
> already births qty 1. The fix is **the Apex normalizer ONLY** (see §2).

### 🟠 Mode A' — the qty=1 edit did not persist  ← compounds Joe's symptom
- L2 `QuoteLineItemHistory` has **zero Quantity rows** (no `0→1→0` pair) → the user's qty=1 **never committed**
  (it was not a revert).
- Quote is **`Status=Accepted` + `IsSyncing=true`** → the RLM/Place-Sales-Transaction line editor does **not commit**
  the qty change. It is **NOT a field lock** (`Quantity.isUpdateable=true` even at Accepted). The 14:40:55 whole-quote
  reprice re-stamped the line but qty stayed 0 → re-priced to $0.
- **Implication:** quantity must be set on a **Draft** quote (before accept/sync), OR the durable Mode-A fix removes
  the need for any manual edit.

### 🟡 Mode B — per-unit net itself = $0 at Quantity ≥ 1  ← separate ticket, NOT Joe's line
- ~2 no-MTD lines (`broQ4`, `DAuh4`). **Byte-identical-twin proof:** `broQ4` (net 0) vs `broR4` (net 462 = 0.23×2008)
  on the **same quote / product / srcLP / attributes** → priced by the **native `DerivedProductsRenewals` engine
  (container seq 5)**, which **failed to bind the contributor** on the duplicate/anomalous-provenance line.
  (`462` is not a maintenance-rate tier, confirming it was the native engine, not the MTD formula.)
- The V14 7-tier `DerivedPricingFormula` is **correct — DO NOT touch it.**
- Needs a **FINEST pricing/expression-set log** on an authorized reprice to finish RCA. Track separately.

### Re-baseline (live 2026-06-15)
`Fortra_Product_Type__c='New Maintenance' AND Source_List_Price__c>0 AND NetTotalPrice=0` → **8 lines**
(6 Mode-A `qty=0` + 2 Mode-B `qty≥1`), all created 2026-06-06→06-15 by the build/test team (Nir/German/Marc).
Earlier "13 / 4-Mode-B / 6,499" figures were stale/inflated (6,499 = lines with srcLP null/0 = a different category).
**Treat the impact set as a live query, not a fixed count** — V14 is co-owned and changes day-to-day.

---

## 2. Resolution (per mode)

| Mode | What must change | Type | Owner |
|---|---|---|---|
| **A** (Joe) | **Apex normalizer ONLY** (rule edit ruled out empirically). Generalize `RenewalAssetQuantityHandler` (or add a sibling) to normalize **any asset-copy line**: `QuoteAction.Type IN (Amend, No Change, Renew)` AND `Quantity <= 0` AND `StartQuantity > 0` → set `Quantity = StartQuantity` (source-asset qty). Wire into the existing `QuoteLineItemTrigger` after-insert hook. Covers all products in one place; **no rule/config edits.** | CODE | Nir |
| **A'** (persistence) | Mostly dissolved by fixing A (no manual edit needed). If manual edits must work, edit on a **Draft** quote before accept/sync. | lifecycle | Nir |
| **B** (separate) | Fix native contributor-binding in `DerivedProductsRenewals` (seq 5) for duplicate/anomalous companion lines + clean duplicate data. **Do NOT change `DerivedPricingFormula`.** | CODE/DATA (TBD) | Nir/Marc — own ticket |
| **Spec gate** | Intended New-Maintenance quantity rule is **unspecified in the SDD**. "Maint qty = license qty" is the natural inference but needs sign-off before coding. | SPEC | Nir/Marc (business) |

---

## 3. Step-by-step roadmap

> Each phase has an exit gate — don't advance until it passes. **No DML/deploy without fresh explicit authorization.**

**P0 — Reproduce on an editable Draft quote** *(do first; no owner gate)*
- New quote → add license `PIA-PIA-NRPS-PIAP` → configurator auto-adds the maintenance line → confirm born qty 0.
- Set qty=1 **while Draft** → reprice → confirm net = $71. Then Accept/sync and retry the edit to characterize the
  commit failure. **Capture a FINEST pricing/expression-set log.**
- **Gate:** born-qty=0 reproduced; qty edit commits on Draft but not on Accepted; log captured.

**P1 — Spec sign-off** *(BLOCKED on Nir/Marc)*
- Authoritative confirmation that New-Maintenance `Quantity = source license quantity`; confirm Mode B is separate.
- **Gate:** written owner decision.

**P2 — Build the Mode-A Apex normalizer** *(needs P1; mechanism already decided)*
- Mechanism is settled (P0 proved the rule is innocent): generalize `RenewalAssetQuantityHandler` (or sibling) to
  cover asset-copy QuoteActions (Amend/No-Change/Renew), `Quantity<=0 AND StartQuantity>0 → Quantity=StartQuantity`.
  Draft under `Data/sc-maint/sc3346_fix/`. Add test coverage (build at 43%, 4 red tests).
- **Gate:** class + test drafted; renewal path regression-checked; coverage plan defined.

**P3 — Implement & deploy Mode-A fix to UAT** *(needs P2 + deploy auth)*
- Ship config or code. If Apex, add coverage (build is at 43% with red tests). Retrieve live before/after.
- **Gate:** new auto-added lines born/normalized to source qty; renewal path unaffected.

**P4 — Verify across the population** *(needs P3)*
- Re-run the impact query; reprice each Mode-A line; confirm net > 0. Joe's quote: correct L2 qty → reprice → $71/unit
  → partner-discounted net (~$62.48 at 12%).
- **Gate:** zero Mode-A lines remain (`qty=0 AND New Maintenance AND srcLP>0 AND NetTotal=0`).

**P5 — Mode-B RCA & fix** *(parallel track; separate ticket; needs P0 log)*
- Use the FINEST log to determine native-contributor-binding failure; fix binding / clean duplicate companion data;
  verify byte-identical twins both price.
- **Gate:** twin lines both net > 0.

**P6 — Prod-cutover prerequisites** *(needs P3–P5)*
- Prod is **from-zero** (0 new classes, neither trigger, 2/5 QLI fields, proc V1 vs UAT V14, 0 `Maintenance_Rate__mdt`
  rows). Bundle with the SC-3346 field/procedure packaging; clear the COLAUpliftTest 41-error compile drift
  (0% coverage = cutover blocker).
- **Gate:** SC-3346 off NO-GO; tests green; manifest complete.

---

## 4. Risks & guardrails
- **V14 oscillation / co-ownership (Nir+Marc):** active version moves day-to-day — **always retrieve live before acting**;
  never trust a snapshot. Joe's fix is rule/Apex, **not** a procedure edit → lower exposure.
- **No DML without auth:** P0/P3/P5 need fresh explicit authorization (even validate-only).
- **Stale repo source:** repo copies drift (`PartnerNetPricePosthook` repo v1.4 vs live v1.5) — retrieve live before editing.
- **Config durability:** an Opt-1 rule change can be silently reverted by Gearset/refresh (same class as SC-3390 PAD-flag
  gap) — bake into republish source + re-verify post-refresh.
- **Don't merge Mode A and Mode B** — different mechanisms, owners, tickets.

## 5. Quick-win vs proper-fix
- **Quick-win (unblock Joe now):** per-unit price already correct; only `Quantity=0` is wrong. Set the maintenance line's
  quantity to the license quantity **on an editable (Draft) quote** and reprice → $71/unit (→ ~$62.48 net at 12% partner).
  The edit doesn't commit on Accepted+IsSyncing, so do it before accept/sync or reopen to Draft. *(Write auth required;
  data correction, not code.)*
- **Proper-fix (systemic):** make the auto-add inherit the source quantity so the line is **never born qty 0** —
  eliminating the manual-edit dependency. Mode B fixed separately.

## Key record IDs
- Quote `0Q0WC0000039Vm10AE` (Accepted, IsSyncing, Type New) · L2 QLI `0QLWC000003ehR84AI`
- Product `PIA-PIA-RNM-PIAMBK` (`01tWC00000DD1bsYAD`) · License `PIA-PIA-NRPS-PIAP` (`01tWC00000DD1btYAD`)
- Auto-add rule `ProductConfigurationRule 14OWC0000022ULp2AM` · QuoteAction `7ocWC00000uh8uvYAA` (Amend)
- PBEDP `182WC000000FN26YAG` · Active proc `Rev_Mgmt_Default_Pricing_Procedure` **V14** (`9QMWC00000023eX4AQ`)
- Mode-B examples: `broQ4` (FAIL) vs `broR4` (PASS, 462) · `DAuh4`
