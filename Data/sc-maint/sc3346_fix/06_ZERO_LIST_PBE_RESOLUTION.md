# SC-3346 ZERO-LIST-PBE — Resolution (2026-06-14, FortraUAT)

## Root cause CORRECTED: it's a PRICE-BOOK / PBE-IsDerived issue, not a "Stamp_Source_List_Price coverage gap"
The retest blamed the null `Source_List_Price__c` ("stamp-flow coverage gap"). That is a **downstream symptom**.
The real cause: the canonical $0 line is on a **non-derived PBE on the Standard Price Book**.

### Proof (same product, two books)
BoKS-NewMaintenance product `01tWC00000DD1bsYAD` has 4 PBEs:
| PBE | Book | IsDerived | PBEDP |
|---|---|---|---|
| 01uWC000005wsbUYAQ | **Fortra Price Book** | **true** | ✅ (contributor = BoKS license 01tWC00000DD1btYAD) |
| 01uWC000004dT3QYAU | Standard Price Book | **false** | ❌ none |
| 01uWC000004muSFYAY | Standard Price Book | false | ❌ |
| 01uWC000005wzX8YAI | Fortra Price Book | false | ❌ |

- **Canonical fail** `00780964` is on the **Standard Price Book** → picks the non-derived PBE (`01uWC000004dT3QYAU`,
  IsDerived=false) → the line is not recognized as derived → the derived formula never runs **and** the
  `Stamp_Source_List_Price` flow's `Is_Derived_Line` gate (`Get_Maintenance_PBE.IsDerived`) skips it → SLP stays null
  → commits **$0** (Base 355, SLP null, ItemIsDerived__std=false).
- **Working** `00781057` is on the **Fortra Price Book** → picks the derived PBE (`01uWC000005wsbUYAQ`, IsDerived=true,
  has PBEDP) → flow stamps SLP=355 → formula prices **71** (0.20×355).

So the chain is: **non-derived PBE (wrong book) → not derived → flow skips → null SLP → $0**. The null SLP is the
last link, not the cause.

## Exposure: tiny, and concentrated off the real transacting book
- **Fortra Price Book is the real book** (94,295 Won + 12,717 Approved + 22,472 Draft …). Maintenance derives
  correctly there.
- **Standard Price Book is a minor/default book** (~685 quotes; 319 Accepted, 6 Ordered). **19 of 21** Standard-book
  maintenance QLIs are on **non-derived** PBEs.
- Actual $0/null-net maintenance lines: **Standard 7 (2 Accepted)** + **Fortra 5 (1 Accepted)** = ~12 lines, 3 Accepted.
  Negligible vs the ~100K Fortra-book volume that prices correctly.

## Two distinct sub-cases → two fixes
1. **Standard-book lines (dominant, ~19 non-derived):** the Standard book's maintenance PBEs are non-derived with no
   PBEDP, so maintenance can't derive there. **Owner/config decision:**
   - (a) **Restrict maintenance to the Fortra book** (recommended) — the real transacting book; the Standard book is the
     SF default and isn't set up for derived maintenance. Migrate/redirect the handful of Standard-book maintenance quotes.
   - (b) **Mirror the derived config onto the Standard book** — set `IsDerived=true` + add PBEDP (contributor crosswalk)
     on the 19 PBEs. More work; needs the same business contributor crosswalk as the broader SC-3372 backfill.
2. **Fortra-book residual (5 net=0):** these are the SC-3372 PBEDP-coverage gap / un-priced drafts on the real book —
   covered by the proven REST PBEDP backfill (PBEDP-COVERAGE / M5-PBEDP) + a reprice. UAT-fixable.

## DECISION (owner: restrict maintenance to the Fortra book) + the clinching fact
**The Standard Price Book is `IsActive=FALSE`** (`IsStandard=true` — the Salesforce system *default*). The **Fortra
Price Book is the active selling book** (`IsActive=true`). So every Standard-book quote is an anomaly on an *inactive
default*, not real selling. → **ZERO-LIST-PBE is reclassified: NOT a build defect on the real transacting path.** The
build prices maintenance correctly on the Fortra book; the canonical $0 (`00780964`) is a wrong-book artifact.

### Resolution actions
1. **Reclassify** ZERO-LIST-PBE from "fail/high" to **works-as-designed on the real (Fortra) book**; the $0 is a
   wrong-book (inactive Standard default) artifact, not a SC-3346 build defect.
2. **Remediate the only real exposure — 2 Accepted Standard-book maintenance lines** (re-quote on Fortra / data fix):
   - `00780583` (Tripwire App Custom Workflow … -NewMaintenance) — Net null, SLP null
   - `00780816` (EFT 8 Continuum-NewMaintenance) — Net 0, SLP null
   (Plus ~5 Standard-book Drafts — harmless; just re-create on Fortra if used.)
3. **Process guard (recommended, follow-up):** ensure new quotes are created on the **Fortra** book (the active book);
   the anomalous Standard-book quotes came from a creation path that fell back to the `IsStandard` default. A lightweight
   before-save guard (`if Pricebook2 = Standard → block/redirect maintenance`) or a quote-default fix would prevent
   recurrence — but per the owner decision ("no PBE config sprawl"), this is a follow-up, not a SC-3346 build change.
4. **Fortra-book residual (5 net=0 lines):** the SC-3372 PBEDP backfill (PBEDP-COVERAGE / M5) + a reprice — UAT-fixable,
   the proven REST-backfill pattern; tracked under SC-3372, not here.

## Net
ZERO-LIST-PBE is **real but minor** and **mis-rooted in the retest**. The $0 comes from lines landing on a non-derived
maintenance PBE (Standard Price Book), not from a stamp-flow bug. The real transacting book (Fortra) prices correctly.
Fix = a price-book/config decision for the Standard book (owner) + the SC-3372 PBEDP backfill for the Fortra residual
(UAT-fixable). The canonical BoKS contributor is known (the BoKS license), so a demonstrable per-line fix is possible if
desired (mark `01uWC000004dT3QYAU` derived + PBEDP → reprice 00780964 → 71), but the systemic Standard-book decision is owner-gated.
