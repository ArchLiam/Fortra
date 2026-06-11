# SC-3390 — Live Repro Runbook (authorized 2026-06-11)

**Goal:** capture the single decisive proof — a paired FINEST ApexLog showing the tier prehook reading the
**old** Unit Quantity on the first "Update Price" click and the **new** value on the second — to confirm (or
refute) the one-cycle stale-context root cause and validate which fix lever closes it.

**Authorization:** user said "go ahead" (2026-06-11). All prep below is done/read-only. **The two clicks in
step B are a UI action that only a human can perform** — Claude cannot click the managed RLM "Update Price"
button, and the test cannot be reproduced headlessly (see §D). Claude runs the log capture/analysis in §C.

---

## A. Pre-armed state (all verified read-only, nothing left to set up)

| Item | Value | Status |
|---|---|---|
| Org | FortraUAT (`liam.jeong.c@fortra.com.uat`, user `005WC00000MgTN2YAN`) | ✅ |
| FINEST trace on that user | TraceFlag `7tfWC000000aq89YAA` → DebugLevel `Finiest` (`7dlWC0000001YxJYAU`) | ✅ active **until 2026-06-11T23:13:49Z** |
| Repro quote (test account) | **`0Q0WC0000037rFZ0AY`** — "Q-Wren - Test GS Quotes w Harddware Copy", **Draft**, Account **"Fortra, LLC - Test"** | ✅ safe (test data) |
| Repro line | **`0QLWC000003d2QJ4AY`** — CLSAAS, `Has_Attribute_Adjustment__c=true` (**eligible**), Feature Options=**Managed Service**, Unit Volume=**null** | ✅ primed at the buggy reset state |
| Tier oracle (Managed Service, USD, Total Price) | Unit Volume **1–49 → 1231.2**, **50–99 → 1357.2**, 100–199 → 1663.2 | ✅ from live `Attribute_Tier_Pricing_Storage__c` |
| Gold oracle line | `0QLWC00000311rZ4AQ` (quote gBPJ) Unit Volume=50 → NetUnitPrice **1357.2** | ✅ proves engine prices 50–99 correctly when value is committed |

> **If the trace window has expired** (after 23:13:49Z on 2026-06-11), tell Claude — re-arming is a one-line
> TraceFlag create (a mutation; needs a fresh ok). Reuse DebugLevel `7dlWC0000001YxJYAU`.

> **Strictly off-limits:** quote `0Q0WC0000037swP0AQ` (OhioHealth Corporation — **real customer data**). It is
> the read-only symptom reference only; do **not** edit it.

---

## B. The repro — your 5 manual steps (UI)

Open quote **`0Q0WC0000037rFZ0AY`** in the Transaction Line Editor (the standard RLM quote grid). Work on the
CLSAAS line **`0QLWC000003d2QJ4AY`**. **Note the wall-clock time of each "Update Price" click** (or just tell
Claude "did click 1" / "did click 2" right after each — that timestamps the logs).

1. **Establish the lower tier.** Open the line's configurator/side panel. Set **Unit Quantity = 49**. Click
   **Update Price**. → Expect the line to settle at **NetUnitPrice 1231.2** (the 1–49 tier). *(If it's still 0 /
   2180 / blank, click once more to settle the baseline — that's fine, it's not the measured part.)*
2. **Cross the boundary.** Change **Unit Quantity = 50** (this crosses into the 50–99 tier). **Do not click yet.**
3. **CLICK 1 (measured).** Click **Update Price once**. **Record the price shown** and the time. → If the bug
   reproduces, the line **stays at 1231.2** (or otherwise ≠ 1357.2) with **no error/warning**.
4. **CLICK 2 (measured).** Click **Update Price again**. **Record the price shown.** → Expect it to now correct
   to **1357.2** (the 50–99 tier).
5. **Tell Claude** the two prices you saw and roughly when you clicked. Claude pulls both ApexLogs and diffs the
   `Attribute_Volume:` line.

**Simplest fallback** (if the 49 baseline is fiddly): from the current null state, just set **Unit Quantity =
50**, **Update Price** (observe it does **not** become 1357.2), **Update Price again** (observe 1357.2). The
49→50 cross is preferred because both states are real tier prices (no null ambiguity), but either demonstrates
the double-click.

---

## C. Log capture & analysis — Claude runs these (read-only) right after your clicks

```bash
ORG=FortraUAT ; USER_ID=005WC00000MgTN2YAN
# 1) List the user's recent ApexLogs (covers the repro window)
sf data query --target-org $ORG --use-tooling-api \
  -q "SELECT Id,LogLength,Operation,StartTime,Status FROM ApexLog WHERE LogUserId='$USER_ID' AND StartTime >= $(date -u -v-20M +%Y-%m-%dT%H:%M:%S.000+0000) ORDER BY StartTime DESC"
# 2) Pull the two newest place/pricing logs (click-1 and click-2)
sf apex log get --target-org $ORG --log-id <CLICK1_LOG_ID> > Data/sc3390/logs/click1.log
sf apex log get --target-org $ORG --log-id <CLICK2_LOG_ID> > Data/sc3390/logs/click2.log
# 3) Decisive greps on BOTH, then diff
for L in click1 click2; do echo "== $L =="; grep -nE \
  'Attribute_Volume:|No eligible line items|RESET: Attribute_Volume not set|RESET: No matching tier|MATCH: Attr=|AttributeVolumePricingPrehook v3.0 (START|END)' \
  Data/sc3390/logs/$L.log; done
```

**Verdict reading:**
- **CONFIRMS root cause** if click-1 shows `Attribute_Volume: 49` (old) / a `RESET` / `No eligible line items`,
  **and** click-2 shows `Attribute_Volume: 50` + `MATCH` (Base_Price 1357.2).
- **REFUTES it** if click-1 already shows `Attribute_Volume: 50` yet the displayed price is still stale → the lag
  is in the managed grid-refresh, not the prehook input (re-open the §02 downstream candidates).
- If click-1 `No eligible line items` while the line is visibly tiered → eligibility/commit ordering is the
  window (supports fix (f) commit-before-hydrate and fix (e) Instant Pricing).

Results get written up in `05_LIVE_REPRO_RESULTS.md` and folded back into `02_…` / `03_…`.

---

## D. Why this can't be done headlessly (recon verdict, for the record)

- **0 tiered lines org-wide carry a committed non-null `Attribute_Volume`** (live query) — there is nothing to
  reprice against without first writing the value.
- Setting `QuoteLineItemAttribute.AttributeValue` is **DML on a Quote-graph child**; metadata says it's
  updateable, but the **RLM/Subscription-Mgmt usage-assignment lock** very likely blocks it at runtime (same
  error class as Quote DML) — unverified, and a probe is itself a mutation.
- The pricing REST surfaces (`/connect/core-pricing/pricing/` stateless compute; `/connect/.../actions/place`
  persisting) **hydrate the volume from the persisted `AttributeValue` column** — they read the committed value,
  they don't let you stage the 49→50 edit. And the bug is a **UI side-panel-save vs reprice timing** artifact,
  which a sequential headless "commit-then-reprice" cannot reproduce (no race).
- Net: the engine half is deterministic (the gold oracle line prices 50→1357.2 correctly). The defect lives in
  the **UI commit/refresh sequencing**, so a human's two clicks are the only path to the decisive log.

---

## E. Optional adjunct experiment (needs a separate explicit ok — a mutation)

To resolve the open "does the RLM lock cascade to `QuoteLineItemAttribute`?" question and enable a headless
engine-isolation data point: attempt a **`Database.update` (with `Database.rollback`) setting Unit Volume=50** on
a **test-fixture** line, observing only whether it throws the lock error. This is a write (even if rolled back)
on test data — **not run** without a fresh ok. If it succeeds, a single headless reprice would show whether the
engine prices 50–99 on the **first** call given a committed value (further isolating UI-timing vs engine).
