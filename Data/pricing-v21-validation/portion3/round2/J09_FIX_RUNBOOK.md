# J-09 PBEDP Contributor Backfill — Step-by-Step Fix Runbook

**Ticket:** SC-3372 / M5-PBEDP · V21 defect **J-09** · **UAT ONLY (FortraUAT)**
**Root cause:** Nir's "Maintenance Derived Pricing" rollout flagged the maintenance PBEs `IsDerived=true` and added the native DerivedProducts pull to the procedure, but **did not backfill the `PriceBookEntryDerivedPrice` (PBEDP) contributor-config rows**. A derived PBE with 0 PBEDP rows → native pull resolves no contributor → `Source_List_Price__c` stays null → `tier% × null = null`. The line prices silently null.
**Fix:** insert one PBEDP row per uncovered derived PBE, pointing at the correct contributing license. **Data only — no procedure edit, no Apex.**

---

## Safety model (read first)
- Every inserted row carries `Legacy_Rule_Id__c = 'M5-PBEDP-20260630'` → **100% reversible** by deleting on that marker.
- Staged in **tiers** so you never bulk-write blind:
  - **Proof** (1 row) → prove the mechanism.
  - **Tier A** (171 rows) → unambiguous single-product exact matches.
  - **Tier B** (82 rows) → name-collisions resolved to the sole priced candidate; **needs a business call** (see Stage 3).
  - **EFT 8 evidence PBE** → 4-product ambiguity; needs an explicit contributor pick (Stage 4).
- **Org guard:** always `-o FortraUAT`. NEVER the `uat` alias. **Do NOT deploy to production.**
- **Blast radius:** 47,039 existing QLIs sit on the 253 PBEs; they re-price on next touch. That is why Tier B / full-set is gated.

## Files (all in `Data/pricing-v21-validation/portion3/round2/`, LF-normalized, insert-ready)
| file | rows | what |
|---|---|---|
| `j09_proof_1row.csv` | 1 | single reversible proof (Advanced Auth Modes) |
| `j09_import_TIER_A_unambiguous_171.csv` | 171 | unambiguous set |
| `j09_import_TIER_B_needs_marc_82.csv` | 82 | name-collision set (gated) |
| `../j09_import_253.csv` | 253 | full actionable set (Tier A + B) |
| `live_blocked_for_marc.csv` | 223 | **excluded** (wrong pricebook — do NOT insert) |

---

## STAGE 0 — Preflight (read-only, run every time before a write)
```bash
cd /Users/liamjeong/Documents/Code/Fortra

# 0.1 confirm org + active proc
sf org display -o FortraUAT | grep Username
# expect: liam.jeong.c@fortra.com.uat

# 0.2 confirm NO stray rows already carry our marker (expect 0)
sf data query -o FortraUAT -q "SELECT COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'"

# 0.3 snapshot the proof line BEFORE (expect NetUnitPrice/Source_List_Price__c = null)
sf data query -o FortraUAT -q "SELECT Id,Product2.Name,Quantity,UnitPrice,NetUnitPrice,ListPrice,Source_List_Price__c FROM QuoteLineItem WHERE Id='0QLWC000003DAub4AG'"
```
**Gate:** proceed only if marker count = 0 and the proof line is null.

---

## STAGE 1 — Single reversible proof (RECOMMENDED FIRST)
Proves null→priced end-to-end with 1 row, ~zero blast radius, on an **open-opp** Draft quote (so the save/reprice actually runs).

**Proof target:** PBE `01uWC000005wsZGYAY` (Advanced Authentication Modes-NewMaintenance) ← contributor `01tWC00000DD11YYAT`.
**Verify on:** QLI `0QLWC000003DAub4AG`, Quote `0Q0WC0000028bsk0AA` (Draft, opp "Evaluating", USD, Fortra Price Book).

```bash
# 1.1 INSERT the single PBEDP row
sf data import bulk -o FortraUAT -s PriceBookEntryDerivedPrice \
  -f Data/pricing-v21-validation/portion3/round2/j09_proof_1row.csv \
  --line-ending LF --wait 10

# 1.2 confirm the row landed (expect 1, PricebookEntryId=01uWC000005wsZGYAY)
sf data query -o FortraUAT -q "SELECT Id,PricebookEntryId,ContributingProductId,Formula FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'"

# 1.3 Force-reprice the quote
cat > /tmp/j09_body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"Quote","method":"PATCH","id":"0Q0WC0000028bsk0AA"}}}]}}
JSON
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" \
  --method POST -o FortraUAT --body "$(cat /tmp/j09_body.json)"

# 1.4 read the line AFTER — PASS = Source_List_Price__c and NetUnitPrice go null -> non-zero
sf data query -o FortraUAT -q "SELECT Id,NetUnitPrice,ListPrice,Source_List_Price__c FROM QuoteLineItem WHERE Id='0QLWC000003DAub4AG'"
```
**PASS criteria:** `Source_List_Price__c` non-null AND `NetUnitPrice` non-zero AND no "contributing products are missing" error. `ListPrice` should equal the contributor's list.
**If it did not flip:** the quote's opp may have closed — re-run Stage 0.3 on another candidate from `proof_target.json` (20 open-opp candidates exist). Do NOT proceed to bulk until the proof passes.

**Decision after proof:** roll back the proof row (Stage 6) and stop, OR keep it and continue to Stage 2.

---

## STAGE 2 — Tier A bulk insert (171 unambiguous)
Each row's contributor name resolves to exactly one active product; no selection judgment. Safe once the proof passes.
```bash
# 2.1 INSERT (skip if the proof row already covers PBE 01uWC000005wsZGYAY — it is included in Tier A;
#     bulk re-inserting it would create a DUPLICATE PBEDP. Either roll back the proof first (Stage 6),
#     or remove that one line from the Tier A file before import.)
sf data import bulk -o FortraUAT -s PriceBookEntryDerivedPrice \
  -f Data/pricing-v21-validation/portion3/round2/j09_import_TIER_A_unambiguous_171.csv \
  --line-ending LF --wait 10

# 2.2 confirm count (expect 171, or 253 if Tier B already loaded)
sf data query -o FortraUAT -q "SELECT COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'"
```
⚠️ **Dedup note:** the proof row (Stage 1) is PBE `01uWC000005wsZGYAY`, which is also in Tier A. Roll back the proof row before Stage 2, OR delete that one line from the Tier A CSV, so you don't insert two PBEDP rows for the same PBE.

---

## STAGE 3 — Tier B (82) — BUSINESS DECISION REQUIRED
For 41 license names, two active products share the name: a **$0-priced perpetual (NRPS)** and a **priced subscription (RSS)**. The mapping took the **only priced candidate**. The pick is forced (the alternative is $0 and wouldn't fix the null), but the semantics need a call:

> **Should perpetual maintenance derive its list from the *subscription* price when the perpetual SKU is $0 in the Fortra Price Book? Or is the perpetual's $0 the real gap to fix?**

Full table (both candidates + prices): `marc_ambiguous_picks.csv`. Handoff doc: `MARC_DEBREY_HANDOFF.md`.

- **If "yes, use the subscription price" (or an owner overrides the mapping):** insert Tier B:
```bash
sf data import bulk -o FortraUAT -s PriceBookEntryDerivedPrice \
  -f Data/pricing-v21-validation/portion3/round2/j09_import_TIER_B_needs_marc_82.csv \
  --line-ending LF --wait 10
```
- **If "no, the perpetual $0 is the gap":** leave Tier B blocked; the real fix is pricing the perpetual SKUs (separate zero-list-contributor work), not a PBEDP row.

---

## STAGE 4 — EFT 8 Express evidence PBE (the spec's named record)
PBE `01uWC000005wsZpYAI` (EFT 8 Express-NewMaintenance) is **not** in the 476 payload — "EFT 8 Express" → 4 products (active: `GS-GSE-NRPS-EFEP` perpetual, `GS-GSE-RSS-EFES` subscription). Recommended contributor: **`GS-GSE-RSS-EFES` `01tWC00000DD1E4YAL`** (the license line present on the evidence quote, List 958.8). **Confirm the pick, then:**
```bash
sf data create record -o FortraUAT -s PriceBookEntryDerivedPrice \
  -v "PricebookEntryId=01uWC000005wsZpYAI ContributingProductId=01tWC00000DD1E4YAL \
      Formula=UnitPrice PricingSource=Product DerivedPricingScope=Both \
      EffectiveFrom=2026-04-01T00:00:00.000Z EffectiveTo=2099-12-31T00:00:00.000Z \
      Legacy_Rule_Id__c=M5-PBEDP-20260630"
```
Then reprice the evidence quote `0Q0WC0000029Agw0AE` (same recipe as 1.3, swap the quote id) and confirm QLI `0QLWC000003KEbO4AW` flips null→priced.

---

## STAGE 5 — Verification & coverage metric
```bash
# 5.1 re-run the live re-validation to see coverage move (PBEDP-covered count rises)
python3 Data/pricing-v21-validation/portion3/round2/revalidate.py

# 5.2 regression control — a covered line you did NOT touch must stay stable
sf data query -o FortraUAT -q "SELECT Id,IsDerived,(SELECT Id FROM PriceBookEntryDerivedPrices) FROM PricebookEntry WHERE Id='01uWC000005wsbVYAQ'"

# 5.3 confirm total inserted rows == expected (1 / 171 / 253 / +EFT8)
sf data query -o FortraUAT -q "SELECT COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'"
```
A calc **error** after insert = regression → roll back and investigate. A clean null→priced flip on the target(s) with the control unchanged = PASS.

---

## STAGE 6 — Rollback (full or partial)
```bash
# 6.1 export the marker rows' Ids to a single-column CSV
sf data query -o FortraUAT -r csv \
  -q "SELECT Id FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'" \
  > /tmp/j09_rollback_ids.csv

# 6.2 bulk delete
sf data delete bulk -o FortraUAT -s PriceBookEntryDerivedPrice \
  -f /tmp/j09_rollback_ids.csv --line-ending LF --wait 10

# 6.3 confirm 0 remain
sf data query -o FortraUAT -q "SELECT COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE Legacy_Rule_Id__c='M5-PBEDP-20260630'"
```
(Previously-repriced quotes keep their last computed values until re-priced again; delete the marker rows and reprice to revert pricing too.)

---

## Field reference (PriceBookEntryDerivedPrice)
| field | type | required | notes |
|---|---|---|---|
| `PricebookEntryId` | reference | ✅ | the derived maint PBE; not updateable |
| `ContributingProductId` | reference | (needed) | the license; not updateable |
| `Formula` | string | ✅ | `UnitPrice` |
| `DerivedPricingScope` | picklist | ✅ | `Both` |
| `EffectiveFrom` | datetime | ✅ | `2026-04-01T00:00:00.000Z` |
| `EffectiveTo` | datetime | — | `2099-12-31T00:00:00.000Z` |
| `PricingSource` | picklist | — | `Product`; not updateable |
| `Legacy_Rule_Id__c` | string | — | `M5-PBEDP-20260630` (reversible marker) |
| `ProductId` / `ProductSellingModelId` | — | — | **do NOT set** — auto-derived; create errors if set |
