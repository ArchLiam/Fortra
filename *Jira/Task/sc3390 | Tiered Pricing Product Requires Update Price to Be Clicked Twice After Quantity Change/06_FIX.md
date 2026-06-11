# SC-3390 — Fix Applied & Validated (UAT)

**Date:** 2026-06-11 · **Org:** FortraUAT · **Status: FIXED & validated in UAT** (root cause proven, fix proven on 2 products).
**Fix chosen:** option **(a)** — make the Unit Quantity attribute price‑impacting (user-selected over Instant Pricing).

---

## 1. What was wrong (proven)
After changing the Product‑Configurator **"Unit Quantity"** attribute (DeveloperName `Attribute_Volume`,
`AttributeDefinition 0tjWC0000000tqvYAA`) on a tiered line, the **first** "Update Prices" click priced the
**old** volume — the value committed to the pricing context **one reprice cycle late**. Live FINEST proof:
after 49→50, click‑1 read `Attribute_Volume: 49` (→ stale 1231.2); only click‑2 read `50` (→ 1357.2).
Every mismatch fell through the prehook's silent `RESET … resetting to list price` — **no error shown**
(the core "reps quote stale prices" risk). See `05_LIVE_REPRO_RESULTS.md` / `evidence/PROOF-two-click-stale-volume.txt`.

## 2. The fix
Flip **`ProductAttributeDefinition.IsPriceImpacting` from `false` → `true`** on **all 26** tiered PADs that carry
`Attribute_Volume`, then run **Setup → Salesforce Pricing Setup → Sync Pricing Data**.

- **Why it works:** `IsPriceImpacting=true` makes the platform treat a Unit Quantity edit as price‑affecting, so
  the edit is committed into the same reprice cycle — the first reprice now reads the just‑typed value instead of
  the prior one. It's the targeted, root‑cause config fix; it does **not** require Instant Pricing and imposes no
  per‑edit reprice churn on non‑tiered products.
- **Why it's safe:** Unit Quantity has **0** `AttributeBasedAdjustment` / `AttributeAdjustmentCondition` rows
  org‑wide, so the flag only enlists it into the standard attribute‑pricing decision‑table lookup
  (`0lDa50000007BEuEAM`) as a **harmless no‑match pass‑through** (CLSAAS already runs two other price‑impacting
  attributes with zero adjustment rows and prices fine). The Fortra tier math still runs entirely in the custom
  prehook off `Attribute_Tier_Pricing_Storage__c`. No pricing‑procedure version change → **no** ExpressionSet
  republish / context re‑sync. See `Data/sc3390/` design research.

## 3. Validation (live FINEST traces, Instant Pricing OFF)
| Product | Boundary | Before fix (`IsPriceImpacting=false`) | After fix (`=true`) |
|---|---|---|---|
| **CLSAAS** (Managed Service) | 49→50 | click‑1 read **49** → 1231.2 (stale); needed 2nd click | click‑1 read **50** → **1357.2** ✅ |
| **SEAW** (End Users‑All Topics) | 499→500 | — | click‑1 read **500** → **6000** ✅ |

Both are clean A/B (same Instant‑Pricing‑OFF configurator; only the flag changed; no auto‑reprice fired between
clicks). Null‑volume lines still correctly reset to list with **no error** (regression‑OK). Evidence:
`evidence/PROOF-fix-a-ispriceimpacting-works.txt`, `evidence/PROOF-fix-a-generalizes-SEAW.txt`.

## 4. Rollout record
- 26/26 Unit Quantity PADs now `IsPriceImpacting=true`, Status=Active. CLSAAS (`0v7WC0000000TvBYAU`) flipped +
  validated first; remaining 25 via per‑record `sf data update` (OK=25, FAIL=0). Sync Pricing Data run twice.
- Full Id list + by‑product mapping: `evidence/fix-a-ROLLOUT.txt`, CSV `Data/sc3390/fix/ispriceimpacting-rollout.csv`.

## 5. Reversibility
Fully reversible: set the 26 PADs' `IsPriceImpacting` back to `false` and re‑run **Sync Pricing Data**. No version
history, no schema change, no irreversible publish.

## 6. Production promotion (DATA/CONFIG, not deployable metadata) — **currently BLOCKED**
`IsPriceImpacting` is an sObject field on records, **not** captured in deployable metadata — a Gearset/metadata
deploy will **not** carry it.

> **⛔ PRECONDITION — prod is not ready (verified 2026-06-11, read-only):** FortraProd is a **pre‑cutover** org for
> the whole RLM tiered‑pricing stack: `ProductAttributeDefinition` = **0 rows**, no `Attribute_Volume`
> AttributeDefinition, `AttributeVolumePricingPrehook` **absent**, `Attribute_Tier_Pricing_Storage__c` = 0,
> Product2/Quote = 0, pricing procedure at **V1** (UAT is V12). **There are no PADs to flip in prod.** This fix
> **cannot be promoted standalone** — it rides the broader RLM tiered‑pricing go‑live (catalog + 26 PADs + prehook
> + tier storage + procedure). The UAT PAD Ids in `ispriceimpacting-rollout.csv` are **UAT‑only**; do not reuse them.
> **Flag on the ticket: do not close as "prod‑ready."**

When the RLM stack IS in prod, promote by:
1. Query the Unit Quantity PADs by attribute DeveloperName (PAD **Ids differ across orgs**):
   `SELECT Id,Product2.ProductCode,IsPriceImpacting FROM ProductAttributeDefinition WHERE AttributeDefinition.DeveloperName='Attribute_Volume'`
2. Set `IsPriceImpacting=true` on all of them (confirm the count matches prod's tiered catalog).
3. Run **Setup → Salesforce Pricing Setup → Sync Pricing Data** in prod.
4. Verify with the same 1‑product boundary‑cross repro + FINEST log (first click reads the new volume).
5. Rollback = flip back to `false` + Sync.

## 6a. ⚠️ DURABILITY RISK — the fix can be silently lost (action required)
Because `IsPriceImpacting` is **pure PAD data** (not in `force-app`/`Org Data` metadata; PAD SOQL is even
API‑restricted), any process that re‑seeds PADs from a pre‑fix source can **silently revert all 26 flags to
`false`** and re‑open the bug **with no error**:
- A **sandbox refresh** from a pre‑fix org.
- A **Gearset PAD data migration** — the repo's own `Org Data/_src/flows/GearsetCloneSupportFlowProductAttributeDefinition.flow-meta.xml`
  migrates PADs but sets **only `GearsetExternalId__c`**; it does **not** carry `IsPriceImpacting`.

**Mitigation (recommended follow‑up):** (1) add `IsPriceImpacting` to the Gearset PAD field‑set / clone‑support
flow so migrations preserve it; and/or (2) add a post‑deploy/post‑refresh check asserting all
`AttributeDefinition.DeveloperName='Attribute_Volume'` PADs are `IsPriceImpacting=true` (alert if any flip back).

## 7. Defensive guard (c) — scoped OUT (optional future hardening)
Not built (user chose option a, not a+c). With (a) in place the **first click is now correct**, so the
silent‑stale‑price money risk is largely resolved at the source. The bug also leaves **no durable at‑rest
fingerprint** (it self‑corrects), so a passive validation rule would catch nothing — a guard would have to
recompute the tier at convert‑time (a before‑save Quote flow on `Create_Order_from_Quote__c`). Documented as an
optional belt‑and‑suspenders only.

**Residual the fix does NOT cover:** (a) closes the *edit‑then‑reprice* lag, but the prehook's **null / no‑tier‑match
silent reset to list price** still fires (confirmed post‑fix: blank SEAW Unit Quantity → `RESET to list, no error`;
likewise a no‑tier value like CLSAAS `Feature Options='Console'`). A genuinely empty Unit Quantity or an
unsupported tier key still prices at list **with no warning** — that residual silent‑reset surface is the only
thing a future (c) guard would add value on.

## 8. Residual items / recommended before prod
- Broader QA sweep across more of the 26 products and edge cases (Console/no‑tier line stays at list; non‑tiered
  line unaffected; a multicurrency tiered line is unchanged — SC‑3384 is orthogonal and **not** fixed/worsened here).
- Test quote `0Q0WC0000037rFZ0AY`: the configurator Unit‑Quantity edits during validation were **transient and
  never committed** (lines' `LastModifiedDate` predates the test clicks; 0 non‑null Unit Volume on the quote), so
  it's already at its baseline (null) state — nothing to reset.
- **Broader UAT QA sweep recommended:** only CLSAAS + SEAW were trace‑validated; exercise more of the 26 products
  + edges (Console/no‑tier stays at list; non‑tiered unaffected; a multicurrency tiered line is unchanged) before sign‑off.
- **Mechanism note:** the fix is empirically proven, but *why* the flag closes the window (transient request
  payload vs persisted `AttributeValue` hydration) isn't fully pinned; multi‑edit / multi‑tiered‑line‑per‑click
  races weren't traced. Low concern, but a multi‑edit repro would fully close it.
- FINEST TraceFlag `7tfWC000000aq89YAA` auto‑expires 2026‑06‑11T23:13:49Z — no cleanup needed.
