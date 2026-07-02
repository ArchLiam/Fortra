# SC-3390 — Live Repro Results: ROOT CAUSE CONFIRMED

> **Note (2026-06-11):** §4's fix ranking ("(e) Instant Pricing first") is **superseded by `06_FIX.md`** — both
> (e) and (a) were validated and the team **shipped (a) `IsPriceImpacting=true`**. The root‑cause proof in §1 stands.

**Date:** 2026-06-11 · **Org:** FortraUAT · **Status: root cause PROVEN by a live FINEST trace** (upgrades the
prior `02_…`/`03_…` verdict from *PLAUSIBLE-UNPROVEN* to **CONFIRMED**).

**How:** authorized live repro on a safe test quote. Liam edited the Unit Quantity on a tiered CLSAAS line in
the Product Configurator and clicked **"Update Prices"** three times across a tier boundary; Claude pulled the
three FINEST ApexLogs and read the prehook's volume markers. Trace was the pre-existing TraceFlag
`7tfWC000000aq89YAA` (DebugLevel `Finiest`) on user `005WC00000MgTN2YAN`.

- **Quote:** `0Q0WC0000037rFZ0AY` ("Q-Wren - Test GS Quotes w Harddware Copy", Draft, Account **"Fortra, LLC -
  Test"** — test data, not a real customer).
- **Line:** CLSAAS (Click and Launch Security Awareness Training – All Star), `Has_Attribute_Adjustment__c=true`,
  Feature Options = **Managed Service**, Unit Type = Per User.
- **Instant Pricing:** **OFF** during the repro (configurator banner: *"Prices don't reflect the latest
  selections. To get the latest pricing, enable Instant Pricing or click Update Prices."*).
- **Tier oracle (CLSAAS / Managed Service / USD / Total Price, 1:1 to net):** 1–49 = **1231.2**, 50–99 = **1357.2**.

---

## 1. The decisive evidence

Only **one** line on the quote carries a non-null Unit Volume (the line being edited); the other 5 CLSAAS lines
read null and reset to list each pass. Tracking that one non-null read across the three clicks:

| # | User action | Prehook `cls:280` reads | Prehook `cls:305` MATCH | Resulting price | Log |
|---|---|---|---|---|---|
| A | Set **Unit Quantity = 49**, Update Prices | `Attribute_Volume: 49` | `Volume=49 … BasePrice=1231.200000` | **1231.2** ✅ baseline | `07LWC00000OsYTY2A3` (11:41:15) |
| B | Change to **50**, **CLICK 1** | `Attribute_Volume: 49` ← **STALE** | `Volume=49 … BasePrice=1231.200000` | **1231.2** ❌ **stale** | `07LWC00000OsqyH2AR` (11:41:46) |
| C | **CLICK 2** (no further edit) | `Attribute_Volume: 50` ← correct | `Volume=50 … BasePrice=1357.200000` | **1357.2** ✅ correct | `07LWC00000OscQh2AJ` (11:42:32) |

Verbatim `cls:305` lines (see `evidence/PROOF-two-click-stale-volume.txt` + the three raw logs in
`Data/sc3390/logs/`):

```
A  11:41:15 |[305]| MATCH: Attr=Feature_Options:Managed Service, Volume=49, PriceMode=Total Price, BasePrice=1231.200000
B  11:41:46 |[305]| MATCH: Attr=Feature_Options:Managed Service, Volume=49, PriceMode=Total Price, BasePrice=1231.200000   <-- old value, after changing to 50
C  11:42:32 |[305]| MATCH: Attr=Feature_Options:Managed Service, Volume=50, PriceMode=Total Price, BasePrice=1357.200000
```

**Reading:** after changing 49→50, the **first** "Update Prices" reprices against the **prior-committed** volume
(49) and matches the old 1–49 tier; the **second** click reprices against the now-committed value (50) and
matches the correct 50–99 tier. **This is the one-cycle stale-context lag, observed directly.**

---

## 2. What this proves (and disproves)

- ✅ **CONFIRMED — one-cycle stale-context snapshot** is the root cause (the `02_…` candidate
  `nonpriceimpacting-attr-write-after-reprice`). The Unit Quantity value commits to the pricing context one
  reprice cycle *after* the UI edit, so the first reprice always prices the previous value.
- ✅ **CONFIRMED — silent failure.** Every non-matching/null read routes through `cls:283`
  `RESET: Attribute_Volume not set — resetting to list price` — no exception, no warning. The configurator's
  generic "prices don't reflect latest selections" banner is the *only* hint, and it does **not** tell the rep
  the displayed price is wrong after the first click.
- ❌ **REFUTED — engine/downstream defect.** The engine prices its input perfectly every time (49→1231.2,
  50→1357.2). The fault is exclusively the **stale INPUT volume**, not tier math or downstream propagation. This
  closes the door on the `total-price-mode-net-channel` and `static-recursion-guard` families for good.
- ❌ **REFUTED — Quantity→Volume sync / `Has_Attribute_Adjustment__c` lag.** The flag was `true` throughout and
  the engine reached the volume read on every click; the only thing that lagged was the **volume value itself**.

---

## 3. UI note (observed)

In the **configurator** Summary panel the rep saw the line at the static list label ($2,180) / Net Amount $0.00
through both clicks — i.e. the configurator preview did **not** surface the prehook's computed tier price at all,
which makes the stale state *even less visible* than the grid. The prehook nonetheless computed 1231.2 (stale)
then 1357.2 (correct) as shown above. The user-facing manifestation (per the ticket) is on the **grid Net Unit
Price** after the reprice: it lands on the stale tier after click 1 and corrects after click 2. Either way the
financial risk stands — a rep can read/quote the stale tier.

---

## 4. Impact on the fix recommendation

The proof says the fix must **make the first reprice see the just-typed value** (or remove the manual-reprice
dependency). In priority order:

1. **(e) Enable Instant Pricing** (declarative, reversible; `03_…§4e`) — reprices on every change, collapsing the
   edit-then-reprice cycle. **Validate next:** flip the configurator's **Instant Pricing** toggle ON, redo
   49→50, and confirm the log shows `Attribute_Volume: 50` and 1357.2 on the **first** action (no second click).
   *This is the single most promising ship-first fix and is now one toggle away from validation.*
2. **(a) `IsPriceImpacting = true` on the 26 tiered PADs** (`02_…§6a`) — makes a Unit Quantity edit a
   price-affecting change so it enlists the same-cycle reprice. Heavier blast radius; validate with the same repro.
3. **(f) commit-before-hydrate sequencing** (`03_…§4f`) — only if (e)/(a) don't fully close it; likely a managed
   seam → Salesforce escalation.
4. **(c) defensive guard** in parallel regardless — kill the *silent* part (loading state / submit-time
   "reprice required" warning) so a stale price can't be quoted unknowingly.

**Recommended next action:** the **Instant Pricing ON** re-run (fix (e) validation) — same quote/line, one toggle,
two FINEST logs. If it prices 1357.2 on the first action, (e) is the recommended ship-first fix.

---

## 5. Artifacts
- `evidence/PROOF-two-click-stale-volume.txt` — the distilled 3-click proof.
- `Data/sc3390/logs/click49_184115.log`, `click50a_184146.log`, `click50b_184232.log` — raw FINEST logs (~9.3 MB each).
- `evidence/repro-baseline-state.txt` — pre-repro fixture/oracle/trace state.
