# Golden Harness — Runbook (Wave 0, Step 0.5 baseline + per-wave regression gate)

**Division of labor**
- **You** perform every *reprice* (the only write). Options, any one:
  - UI: open the Quote/Order → **Reprice All** in the Transaction Line Editor, or
  - Flow: run `Fortra_Quote_Reprice` (Quote) / `Fortra_Order_Reprice` (Order), or
  - Managed API: `POST /connect/rev/sales-transaction/actions/place` with `pricingPreference=Force`.
- **Me / you (read-only)** capture snapshots with `snapshot.sh` and compare with `diff.py`. No snapshot or diff ever writes to the org.

**Setup (once):** `chmod +x snapshot.sh` · `export ORG=FortraUAT`

---

## A. Capture the baseline — Step 0.5 (do this once, after records are bound)

For each scenario `S#` in `scenarios.tsv` (with its bound `quote_id` / `order_id`):

```
# 1. (YOU) Reprice the Quote.
# 2. Snapshot the Quote (read-only):
./snapshot.sh Quote <quote_id> baselines/S#_quote.tsv

# 3. (YOU) Convert Quote→Order and reprice the Order (scenarios that cover Order).
# 4. Snapshot the Order (read-only):
./snapshot.sh Order <order_id> baselines/S#_order.tsv
```

**Idempotency (S1, S5, S8, S11 minimum):**
```
# (YOU) reprice the SAME quote a 2nd time, then:
./snapshot.sh Quote <quote_id> baselines/S#_quote_2nd.tsv
python3 diff.py baselines/S#_quote.tsv baselines/S#_quote_2nd.tsv     # MUST print GATE PASS
```

**Asset count (post-activation downstream proxy — S1..S4, S12):** after the Order is activated,
```
sf data query -o $ORG -q "SELECT count() FROM Asset WHERE Order__c='<order_id>'"   # confirm field name; else via AssetAction
```
Record the count in `baselines/S#_assetcount.txt`.

**Baseline validation (Step 0.5 gate):**
- Every intended scenario produced a non-empty snapshot for both Quote and Order.
- Idempotency scenarios pass `diff.py` (1st == 2nd click).
- Known-good numbers look right for the *passing* set; any *known-failing* scenario is listed in `KNOWN_FAILING.md` and its baseline is frozen **separately** (so a later wave is never credited with "accidentally fixing" it).

Once all rows are captured and consistent → **Wave 0 GATE is green. The baseline is now the oracle.**

---

## B. Per-wave regression gate (Waves 1–4 exit check)

After any wave's change is deployed to UAT (by you, under separate authorization):
```
# (YOU) reprice each scenario again, then (read-only):
./snapshot.sh Quote <quote_id> post/S#_quote.tsv
./snapshot.sh Order <order_id> post/S#_order.tsv

# Compare against the frozen baseline:
python3 diff.py baselines/S#_quote.tsv post/S#_quote.tsv
python3 diff.py baselines/S#_order.tsv post/S#_order.tsv
```
- **Cleanup waves (1–2):** every scenario must print `GATE PASS — 0 delta`. Any delta = stop, investigate; a cleanup wave must not move a number.
- **Behavioral waves (3–4):** only the *intended* columns may change. Run with `--ignore <cols>` for the approved delta (e.g. the E-04 fix changes `NetUnitPrice` on S8 only); every *other* column and *every other scenario* must still be 0 delta. An unexpected delta on an untouched scenario is the F-09 regression signature — stop.

**Governor gate (S14, and S12 high-qty):** capture SOQL/CPU from the reprice debug log; assert counts do not exceed the baseline. (guards SC-3366 / SC-3447)

---

## Files
- `scenarios.tsv` — the S1–S14 matrix (bind `quote_id`/`order_id` before running).
- `snapshot.sh` — read-only per-line oracle capture (normalized, diffable).
- `diff.py` — the gate check (exit 0 = pass).
- `baselines/` — the frozen oracle (Step 0.5 output). `post/` — per-wave re-captures.
